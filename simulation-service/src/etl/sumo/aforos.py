"""
Aforos vehiculares de la hora de máxima demanda (Encuesta de Movilidad 2023, EODI) ubicados
en la red de Usaquén, para validar la simulación con el GEH (validacion.py).

La publicación de SIMUR trae, en EODI/03_Aforos/:
- "a. Base de datos aforos hora de maxima demanda.xlsx", hoja BD: un volumen por
  tipología vehicular, estación (ID), periodo (AM 5:30-8:30, PM 16:00-19:00) y sentido
  (N-S, S-N, W-E, E-W). Las direcciones son texto ("AK 7 X AC 170"), sin coordenadas.
- los shapefiles de las estaciones (EPSG:3116): puntos de transporte privado, bicicletas
  y BRT (ID_TP, ID_BC, ID_BRT) y tramos de transporte público (ID_TPU).
El ID del Excel es el mismo de los shapefiles, así que no hace falta geocodificar.

Cada estación y sentido se ubica en el edge de la red más cercano (a menos de `radio_m`)
cuyo rumbo coincide con el sentido aforado y que admite la clase de vehículo de la
estación, prefiriendo la vía de mayor jerarquía. El resultado es pequeño y se versiona:
data/processed/aforos_usaquen.json.

Uso: python -m etl.sumo.aforos "<carpeta 2.PublicacionSIMUR>"
(necesita geopandas y openpyxl, que solo se usan aquí: pip install -e ".[datos]").
"""
import argparse
import json
import math
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import AFOROS_JSON, DEFAULT_SCENARIO, ScenarioPaths
from .intersecciones import _via_osm

RUTA_EXCEL = Path("EODI") / "03_Aforos" / "a. Base de datos aforos hora de maxima demanda.xlsx"
RUTA_PUNTOS = Path("EODI") / "03_Aforos" / "b. Estaciones_T1_T2_T3" / "1.Puntos_Captura_Informacion_Aforo_2023.shp"
RUTA_TRAMOS = Path("EODI") / "03_Aforos" / "c. Estaciones_T4" / "2.Tramos_Captura_Informacion_Aforo_2023_TPU.shp"

# tipología del aforo -> modo comparable de la simulación (None: no se simula)
MODO_TIPOLOGIA: dict[str, str | None] = {
    "AUTO": "auto",
    "MOTO": "moto",
    "TAXI OCUPADO": "taxi",
    "ESPECIAL OCUPADO": "especial",
    "ESCOLAR": "escolar",
    "BICICLETA EN CALZADA": "bici",
    "BICICLETA EN CICLORUTA": "bici",
    "TPC_URBANO": "bus",
    "TPC_INTERMUNICIPAL": "bus",
    "CP": None,          # camión pequeño: la simulación no tiene carga
    "CG": None,          # camión grande
    "BRT": None,         # TransMilenio troncal: no se simula
    "TRONCAL": None,
}
# prefijo del ID de estación -> clase de SUMO que debe admitir el edge aforado
CLASE_ESTACION = {"TP": "passenger", "BC": "bicycle", "TPU": "bus"}
# sentido aforado -> rumbo de marcha (grados desde el norte, sentido horario)
RUMBO_SENTIDO = {"S-N": 0.0, "W-E": 90.0, "N-S": 180.0, "E-W": 270.0}


class AforosError(RuntimeError):
    """No se encontraron los archivos de aforos o no se pudieron leer."""


@dataclass(frozen=True)
class AforosConfig:
    carpeta: Path                     # carpeta "2.PublicacionSIMUR"
    net: Path = ScenarioPaths.from_name(DEFAULT_SCENARIO).net
    nombres_vias: Path = ScenarioPaths.from_name(DEFAULT_SCENARIO).nombres_vias
    destino: Path = AFOROS_JSON
    radio_m: float = 60.0             # distancia máxima del punto de aforo al edge
    tolerancia_grados: float = 40.0   # diferencia máxima entre el rumbo del edge y el sentido
    localidad: str = "usaquen"


@dataclass(frozen=True)
class AforosResult:
    destino: Path
    puntos: list[dict]


@dataclass
class AforosStats:
    filas: int = 0
    estaciones: int = 0
    estaciones_en_red: int = 0
    sentidos_ubicados: int = 0
    sin_via: list[str] = field(default_factory=list)


def _normalizar(texto) -> str:
    """Minúsculas y sin tildes (los shapefiles traen las tildes con la codificación rota)."""
    import unicodedata

    texto = unicodedata.normalize("NFKD", str(texto or "")).encode("ascii", "ignore").decode()
    return texto.lower()


def rumbo(p: tuple[float, float], q: tuple[float, float]) -> float:
    """Rumbo de p a q en grados desde el norte (x al este, y al norte)."""
    return math.degrees(math.atan2(q[0] - p[0], q[1] - p[1])) % 360


def diferencia_angular(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def _rumbo_cercano(forma: list, x: float, y: float) -> tuple[float, float]:
    """Distancia del punto a la polilínea y rumbo del segmento más cercano."""
    mejor = (math.inf, 0.0)
    for p, q in zip(forma, forma[1:]):
        dx, dy = q[0] - p[0], q[1] - p[1]
        largo2 = dx * dx + dy * dy
        t = 0.0 if largo2 == 0 else max(0.0, min(1.0, ((x - p[0]) * dx + (y - p[1]) * dy) / largo2))
        d = math.hypot(p[0] + t * dx - x, p[1] + t * dy - y)
        if d < mejor[0]:
            mejor = (d, rumbo(p, q))
    return mejor


def ubicar_sentido(net, x: float, y: float, sentido: str, clase: str, radio_m: float, tolerancia: float):
    """Edge que mejor representa el sentido aforado en (x, y), o None.

    Entre los edges cercanos con rumbo compatible y que admiten `clase`, gana el de mayor
    prioridad (jerarquía vial) y, a igual prioridad, el más cercano.
    """
    if sentido not in RUMBO_SENTIDO:
        return None
    objetivo = RUMBO_SENTIDO[sentido]
    candidatos = []
    for edge, _ in net.getNeighboringEdges(x, y, radio_m):
        if edge.getFunction() == "internal" or not edge.allows(clase):
            continue
        distancia, rumbo_edge = _rumbo_cercano(edge.getShape(), x, y)
        if distancia > radio_m or diferencia_angular(rumbo_edge, objetivo) > tolerancia:
            continue
        candidatos.append((-edge.getPriority(), distancia, edge.getID(), edge))
    if not candidatos:
        return None
    _, distancia, _, edge = min(candidatos)
    return edge, distancia


def leer_volumenes(excel: Path) -> dict[str, dict]:
    """ID de estación -> {"direccion", "volumenes": {periodo: {sentido: {tipología: veh/h}}}}."""
    import openpyxl

    libro = openpyxl.load_workbook(excel, read_only=True)
    estaciones: dict[str, dict] = {}
    for i, fila in enumerate(libro["BD"].iter_rows(values_only=True)):
        if i == 0 or not fila or fila[1] is None:
            continue
        tipologia, eid, direccion, _eodi, periodo, sentido, volumen = fila[:7]
        est = estaciones.setdefault(str(eid), {"direccion": direccion, "volumenes": {}})
        por_sentido = est["volumenes"].setdefault(str(periodo), {}).setdefault(str(sentido), {})
        # filas duplicadas exactas (3 en el BRT): se toma el valor una vez
        por_sentido[str(tipologia)] = float(volumen or 0)
    libro.close()
    return estaciones


def leer_ubicaciones(carpeta: Path) -> dict[str, dict]:
    """ID de estación -> {"lon", "lat", "localidad"} desde los shapefiles (puntos y tramos)."""
    import geopandas as gpd

    ubicaciones: dict[str, dict] = {}
    puntos = gpd.read_file(carpeta / RUTA_PUNTOS).to_crs(4326)
    for _, fila in puntos.iterrows():
        for columna in ("ID_TP", "ID_BC", "ID_BRT"):
            eid = fila.get(columna)
            if isinstance(eid, str) and eid:
                ubicaciones[eid] = {"lon": fila.geometry.x, "lat": fila.geometry.y, "localidad": fila.get("LocalMuni")}
    tramos = gpd.read_file(carpeta / RUTA_TRAMOS).to_crs(4326)
    for _, fila in tramos.iterrows():
        eid = fila.get("ID_TPU")
        if isinstance(eid, str) and eid and fila.geometry is not None:
            medio = fila.geometry.interpolate(0.5, normalized=True)
            ubicaciones[eid] = {"lon": medio.x, "lat": medio.y, "localidad": fila.get("LocalMuni")}
    return ubicaciones


def _modos(tipologias: dict[str, float]) -> dict[str, float]:
    """Volúmenes por modo comparable (suma las tipologías que van al mismo modo)."""
    modos: dict[str, float] = defaultdict(float)
    for tipologia, volumen in tipologias.items():
        modo = MODO_TIPOLOGIA.get(tipologia)
        if modo is not None:
            modos[modo] += volumen
    return {m: round(v, 1) for m, v in modos.items()}


def preparar_aforos(cfg: AforosConfig, stats: AforosStats | None = None) -> AforosResult:
    """Lee los aforos, ubica cada estación y sentido en la red y escribe `cfg.destino`."""
    import sumolib

    stats = stats if stats is not None else AforosStats()
    excel = cfg.carpeta / RUTA_EXCEL
    if not excel.is_file():
        raise AforosError(f"No está el Excel de aforos: {excel}")
    volumenes = leer_volumenes(excel)
    ubicaciones = leer_ubicaciones(cfg.carpeta)
    stats.estaciones = len(volumenes)
    stats.filas = sum(len(t) for e in volumenes.values() for p in e["volumenes"].values() for t in p.values())

    nombres = json.loads(cfg.nombres_vias.read_text(encoding="utf-8")) if cfg.nombres_vias.is_file() else {}
    net = sumolib.net.readNet(str(cfg.net))
    (xmin, ymin), (xmax, ymax) = (net.getBBoxXY()[0], net.getBBoxXY()[1])
    puntos = []
    for eid, estacion in sorted(volumenes.items()):
        ubicacion = ubicaciones.get(eid)
        clase = CLASE_ESTACION.get(eid.split("_")[0])
        if ubicacion is None or clase is None:
            continue
        # la red es solo Usaquén: las estaciones vecinas que caen en su rectángulo quedan
        # sobre tramos sueltos del borde, sin el tráfico que las cruza
        if cfg.localidad not in _normalizar(ubicacion["localidad"]):
            continue
        x, y = net.convertLonLat2XY(ubicacion["lon"], ubicacion["lat"])
        if not (xmin <= x <= xmax and ymin <= y <= ymax):
            continue
        sentidos = {s for por_periodo in estacion["volumenes"].values() for s in por_periodo}
        ubicados = 0
        for sentido in sorted(sentidos):
            encontrado = ubicar_sentido(net, x, y, sentido, clase, cfg.radio_m, cfg.tolerancia_grados)
            if encontrado is None:
                if sentido in RUMBO_SENTIDO:
                    stats.sin_via.append(f"{eid} {sentido}")
                continue
            edge, distancia = encontrado
            ubicados += 1
            puntos.append({
                "id": eid,
                "direccion": estacion["direccion"],
                "localidad": ubicacion["localidad"],
                "lon": round(ubicacion["lon"], 6), "lat": round(ubicacion["lat"], 6),
                "sentido": sentido,
                "edge": edge.getID(),
                "via": edge.getName() or nombres.get(_via_osm(edge.getID())),
                "distancia_m": round(distancia, 1),
                "volumenes": {
                    periodo: _modos(por_sentido.get(sentido, {}))
                    for periodo, por_sentido in sorted(estacion["volumenes"].items())
                    if sentido in por_sentido
                },
            })
        if ubicados:
            stats.estaciones_en_red += 1
            stats.sentidos_ubicados += ubicados

    datos = {
        "fuente": "Encuesta de Movilidad 2023 (EODI): aforos de la hora de máxima demanda, SIMUR",
        "periodos": {"AM": "5:30-8:30", "PM": "16:00-19:00"},
        "puntos": puntos,
    }
    cfg.destino.parent.mkdir(parents=True, exist_ok=True)
    cfg.destino.write_text(json.dumps(datos, ensure_ascii=False, indent=1), encoding="utf-8")
    return AforosResult(cfg.destino, puntos)


def cargar_aforos(path: Path = AFOROS_JSON) -> list[dict]:
    """Puntos de aforo ubicados en la red ([] si todavía no se prepararon)."""
    if not path.is_file():
        return []
    return json.loads(path.read_text(encoding="utf-8"))["puntos"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("carpeta", type=Path, help='carpeta "2.PublicacionSIMUR" descargada de SIMUR')
    args = parser.parse_args()
    stats = AforosStats()
    resultado = preparar_aforos(AforosConfig(carpeta=args.carpeta), stats)
    print(f"{stats.estaciones} estaciones, {stats.estaciones_en_red} en la red, "
          f"{stats.sentidos_ubicados} sentidos ubicados -> {resultado.destino}")
    if stats.sin_via:
        print("Sin vía compatible:", ", ".join(stats.sin_via))


if __name__ == "__main__":
    main()
