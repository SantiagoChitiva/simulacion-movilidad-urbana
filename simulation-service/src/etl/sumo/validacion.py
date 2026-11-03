"""
Validación de la simulación contra los aforos de la hora de máxima demanda con el GEH.

    GEH = sqrt(2 (M - C)^2 / (M + C))

con M el volumen simulado y C el aforado (veh/h). El criterio usual de calibración (Design
Manual for Roads and Bridges) pide GEH < 5 en al menos el 85 % de los puntos.

1. `escribir_conteos` arma un additional con un `<edgeData>` por grupo de vTypes, solo en
   los edges donde hay aforo (aforos.py), que SUMO escribe cada 15 minutos.
2. `validar` toma, por punto y sentido, la hora simulada de mayor volumen dentro de la
   ventana (los aforos son de la hora de máxima demanda de su periodo) y la compara con el
   aforo del mismo periodo (AM o PM), sumando solo los modos que la simulación tiene.

La red arranca vacía, así que el primer cuarto de hora casi no cuenta, y la demanda solo
tiene los viajes internos de Usaquén: sin el tráfico de paso (trafico_paso.py) se espera
que los volúmenes simulados queden por debajo de los aforados en las vías principales.
"""
import csv
import json
import math
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .aforos import grupo_estacion
from .configuration import AFOROS_JSON, HORA_INI
from .vtypes import BUS_PT_ID, BUS_SITP_ID

PERIODO_BIN_S = 900
BINS_HORA = 3600 // PERIODO_BIN_S
UMBRAL_GEH = 5.0
CRITERIO_PORCENTAJE = 85.0

# modo comparable del aforo -> vTypes de la simulación que cuentan como ese modo
VTYPES_MODO: dict[str, tuple[str, ...]] = {
    "auto": ("auto", "informal", "otro"),
    "moto": ("moto",),
    "taxi": ("taxi",),
    "especial": ("especial",),
    "escolar": ("escolar",),
    "bici": ("bici",),
    "bus": (BUS_PT_ID, BUS_SITP_ID),
}
# modos que se comparan según el tipo de estación (prefijo del ID)
MODOS_ESTACION = {
    "TP": ("auto", "moto", "taxi", "especial", "escolar", "bici"),
    "BC": ("bici",),
    "TPU": ("bus",),
}


def geh(simulado: float, real: float) -> float:
    if simulado + real <= 0:
        return 0.0
    return math.sqrt(2 * (simulado - real) ** 2 / (simulado + real))


def periodo_de(inicio_s: float) -> str:
    """Periodo del aforo que corresponde a una ventana (AM antes del mediodía)."""
    return "AM" if inicio_s < 12 * 3600 else "PM"


def escribir_conteos(puntos: list[dict], destino: Path, salida: Path,
                     inicio: float = HORA_INI, fin: float | None = None) -> Path:
    """Additional con un edgeData por modo en los edges aforados."""
    edges = " ".join(sorted({p["edge"] for p in puntos}))
    raiz = ET.Element("additional")
    for modo, vtypes in VTYPES_MODO.items():
        atributos = {
            "id": f"conteo_{modo}", "file": str(salida), "period": str(PERIODO_BIN_S),
            "begin": str(inicio), "edges": edges, "vTypes": " ".join(vtypes), "excludeEmpty": "true",
        }
        if fin is not None:
            atributos["end"] = str(fin)
        ET.SubElement(raiz, "edgeData", atributos)
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    destino.parent.mkdir(parents=True, exist_ok=True)
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


def leer_conteos(path: Path) -> dict[str, dict[str, dict[float, float]]]:
    """modo -> edge -> inicio del intervalo -> vehículos que entraron al edge."""
    conteos: dict[str, dict[str, dict[float, float]]] = defaultdict(lambda: defaultdict(dict))
    for _, intervalo in ET.iterparse(path, events=("end",)):
        if intervalo.tag != "interval":
            continue
        modo = intervalo.get("id", "").removeprefix("conteo_")
        inicio = float(intervalo.get("begin", 0))
        for edge in intervalo.findall("edge"):
            conteos[modo][edge.get("id")][inicio] = float(edge.get("entered", 0))
        intervalo.clear()
    return conteos


def _hora_pico(serie: dict[float, float]) -> tuple[float | None, float]:
    """Inicio y volumen de la hora (4 cuartos seguidos) de mayor volumen."""
    if not serie:
        return None, 0.0
    inicios = sorted(serie)
    mejor = (None, 0.0)
    for t0 in inicios:
        total = sum(serie.get(t0 + k * PERIODO_BIN_S, 0.0) for k in range(BINS_HORA))
        if total > mejor[1]:
            mejor = (t0, total)
    return mejor


def _indicadores(filas: list[dict]) -> dict:
    """Puntos, cuántos cumplen GEH < 5, porcentaje, GEH mediano y razón de volúmenes."""
    cumplen = sum(1 for f in filas if f["cumple"])
    porcentaje = round(100 * cumplen / len(filas), 1) if filas else 0.0
    real_total = sum(f["real"] for f in filas)
    return {
        "puntos": len(filas),
        "cumplen": cumplen,
        "porcentaje": porcentaje,
        "cumple_criterio": bool(filas) and porcentaje >= CRITERIO_PORCENTAJE,
        "geh_mediano": round(sorted(f["geh"] for f in filas)[len(filas) // 2], 2) if filas else None,
        # cuánto del volumen aforado alcanza la simulación en esos puntos
        "razon_volumen": round(sum(f["simulado"] for f in filas) / real_total, 3) if real_total else None,
    }


@dataclass(frozen=True)
class ValidacionConfig:
    conteos: Path                      # salida de los edgeData
    destino: Path                      # resumen y filas (JSON)
    destino_csv: Path
    periodo: str = "AM"                # periodo del aforo con el que se compara
    modos_simulados: tuple[str, ...] = ("auto", "moto", "taxi", "especial", "escolar", "bici")
    aforos: Path = AFOROS_JSON
    etiqueta: str = ""                 # p. ej. "con tráfico de paso"


@dataclass(frozen=True)
class ValidacionResult:
    resumen: dict


@dataclass
class ValidacionStats:
    puntos: int = 0
    sin_aforo_en_periodo: int = 0
    estaciones_no_simuladas: list[str] = field(default_factory=list)


def validar(cfg: ValidacionConfig, stats: ValidacionStats | None = None) -> ValidacionResult:
    """GEH por punto de aforo y resumen (porcentaje de puntos con GEH < 5)."""
    stats = stats if stats is not None else ValidacionStats()
    puntos = json.loads(cfg.aforos.read_text(encoding="utf-8"))["puntos"] if cfg.aforos.is_file() else []
    conteos = leer_conteos(cfg.conteos) if cfg.conteos.is_file() else {}

    filas = []
    for punto in puntos:
        real_modos = punto["volumenes"].get(cfg.periodo)
        if not real_modos:
            stats.sin_aforo_en_periodo += 1
            continue
        tipo = punto["id"].split("_")[0]
        modos = [m for m in MODOS_ESTACION.get(tipo, ()) if m in cfg.modos_simulados]
        if not modos:
            stats.estaciones_no_simuladas.append(punto["id"])
            continue
        # serie del total de los modos comparables; la hora pico se toma sobre el total
        serie: dict[float, float] = defaultdict(float)
        for modo in modos:
            for t0, n in conteos.get(modo, {}).get(punto["edge"], {}).items():
                serie[t0] += n
        inicio, simulado = _hora_pico(serie)
        sim_modos = {
            m: sum(conteos.get(m, {}).get(punto["edge"], {}).get(inicio + k * PERIODO_BIN_S, 0.0)
                   for k in range(BINS_HORA)) if inicio is not None else 0.0
            for m in modos
        }
        real = sum(real_modos.get(m, 0.0) for m in modos)
        valor = geh(simulado, real)
        filas.append({
            "id": punto["id"], "direccion": punto["direccion"], "sentido": punto["sentido"],
            "edge": punto["edge"], "via": punto.get("via"), "lon": punto["lon"], "lat": punto["lat"],
            "modos": modos, "hora_pico_simulada": inicio,
            "simulado": round(simulado, 1), "real": round(real, 1), "geh": round(valor, 2),
            "cumple": valor < UMBRAL_GEH,
            "grupo": grupo_estacion(punto["id"]),
            "simulado_por_modo": {m: round(v, 1) for m, v in sim_modos.items()},
            "real_por_modo": {m: real_modos.get(m, 0.0) for m in modos},
        })
    stats.puntos = len(filas)

    resumen = {
        "periodo": cfg.periodo,
        "etiqueta": cfg.etiqueta,
        **_indicadores(filas),
        "criterio_porcentaje": CRITERIO_PORCENTAJE,
        "umbral_geh": UMBRAL_GEH,
        # con tráfico de paso, las estaciones de calibración se usaron para estimarlo: la
        # validación independiente es la de las de control
        "por_grupo": {g: _indicadores([f for f in filas if f["grupo"] == g]) for g in ("calibracion", "control")},
        "modos_simulados": list(cfg.modos_simulados),
        "estaciones_no_simuladas": sorted(set(stats.estaciones_no_simuladas)),
        "filas": filas,
    }
    cfg.destino.parent.mkdir(parents=True, exist_ok=True)
    cfg.destino.write_text(json.dumps(resumen, ensure_ascii=False, indent=1), encoding="utf-8")
    with cfg.destino_csv.open("w", newline="", encoding="utf-8") as f:
        escritor = csv.writer(f)
        escritor.writerow(["id", "direccion", "sentido", "edge", "via", "modos", "simulado_veh_h", "aforo_veh_h", "geh", "cumple"])
        for fila in filas:
            escritor.writerow([fila["id"], fila["direccion"], fila["sentido"], fila["edge"], fila["via"] or "",
                               " ".join(fila["modos"]), fila["simulado"], fila["real"], fila["geh"],
                               "si" if fila["cumple"] else "no"])
    return ValidacionResult(resumen)
