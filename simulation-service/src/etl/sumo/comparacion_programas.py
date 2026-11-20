"""
Comparación de programas de un semáforo existente en una zona recortada.

Fase D del módulo de semáforos. Para cada programa (el actual de la red, el optimizado
por Webster o uno que guardó el usuario) se corre SUMO una hora punta en la misma zona
y con la misma demanda; solo cambia el programa del semáforo. SUMO usa el último
programa cargado de cada tlLogic, así que basta con pasarlo como additional.

Métricas (las mismas para todos los programas):
- tiempo perdido y espera media por vehículo (tripinfo de todos los vehículos de la zona),
- cola más larga y detenciones en los accesos del semáforo (detectores E2 por carril),
- tiempo perdido de los peatones (personinfo),
- opcional (`ssm`): conflictos entre vehículos cerca del cruce con el dispositivo SSM de
  SUMO (TTC < 1,5 s, DRAC > 3,35 m/s², PET < 1,5 s; los umbrales de telemetria.py).
"""
import math
import shutil
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import HORA_INI
from .proceso import ejecutar, revisar_cancelacion
from .programas_tls import ProgramaTLS, escribir_programa
from .telemetria import DRAC_CRITICO, PET_CRITICO, TTC_CRITICO

DURACION_S = 3600
PERIODO_E2_S = 60
RADIO_CONFLICTOS_M = 60    # conflictos que cuentan: los de cerca del cruce, no los de toda la zona
VENTANA_CONFLICTO_S = 10   # un mismo par de vehículos cuenta una vez cada 10 s


class ComparacionProgramaError(RuntimeError):
    """SUMO no está disponible o la corrida de la zona terminó con error."""


@dataclass(frozen=True)
class ComparacionProgramaConfig:
    zona_net: Path
    demanda: list[Path]          # rutas y trips de la zona (los mismos para todos)
    vtypes: Path
    accesos: list[str]           # edges de acceso del semáforo
    destino_dir: Path
    programa: ProgramaTLS | None = None   # None: el programa que trae la red
    semilla: int = 42
    inicio: float = HORA_INI
    duracion_s: float = DURACION_S
    adicionales: tuple[Path, ...] = ()    # p. ej. el programa propuesto de un semáforo nuevo
    ssm: bool = False                     # registrar conflictos (TTC, DRAC, PET)
    nodos: tuple[str, ...] = ()           # nodos del cruce: centro para filtrar los conflictos

    def args_ssm(self) -> list[str]:
        if not self.ssm:
            return []
        return [
            "--device.ssm.probability", "1",
            "--device.ssm.deterministic", "true",
            "--device.ssm.measures", "TTC DRAC PET",
            "--device.ssm.thresholds", f"{TTC_CRITICO} {DRAC_CRITICO} {PET_CRITICO}",
            "--device.ssm.range", "50",
            "--device.ssm.file", str(self.destino_dir / "ssm.xml"),
        ]

    def to_args(self, adicionales: list[Path]) -> list[str]:
        return [*self._args_base(adicionales), *self.args_ssm()]

    def _args_base(self, adicionales: list[Path]) -> list[str]:
        return [
            "-n", str(self.zona_net),
            "-r", ",".join(str(d) for d in self.demanda),
            "-a", ",".join(str(a) for a in [self.vtypes, *adicionales]),
            "--begin", str(self.inicio),
            "--end", str(self.inicio + self.duracion_s),
            "--seed", str(self.semilla),
            "--tripinfo-output", str(self.destino_dir / "tripinfo.xml"),
            "--tripinfo-output.write-unfinished", "true",
            "--statistic-output", str(self.destino_dir / "statistics.xml"),
            "--ignore-route-errors", "true",
            "--time-to-teleport", "300",
            "--no-step-log", "true",
            "--no-warnings", "true",
        ]


@dataclass(frozen=True)
class ComparacionProgramaResult:
    metricas: dict[str, float | int | None]


@dataclass
class ComparacionProgramaStats:
    detectores: int = 0
    vehiculos: int = 0
    peatones: int = 0
    corridas: list[str] = field(default_factory=list)


def escribir_detectores(zona_net: Path, accesos: list[str], destino: Path, salida: Path) -> int:
    """Un detector E2 a lo largo de cada carril de acceso al semáforo; devuelve cuántos."""
    accesos_set = set(accesos)
    raiz = ET.Element("additional")
    n = 0
    for _, elem in ET.iterparse(zona_net, events=("end",)):
        if elem.tag == "edge" and elem.get("id") in accesos_set:
            for carril in elem.findall("lane"):
                largo = float(carril.get("length", 0))
                if largo < 2:
                    continue
                ET.SubElement(raiz, "laneAreaDetector", {
                    "id": f"e2_{carril.get('id')}", "lane": carril.get("id"),
                    "pos": "0", "endPos": f"{largo:.2f}", "friendlyPos": "true",
                    "period": str(PERIODO_E2_S), "file": str(salida),
                })
                n += 1
        if elem.tag == "edge":
            elem.clear()
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    destino.parent.mkdir(parents=True, exist_ok=True)
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return n


def _media(valores: list[float]) -> float | None:
    return round(sum(valores) / len(valores), 1) if valores else None


def leer_metricas(tripinfo: Path, e2: Path, statistics: Path) -> dict[str, float | int | None]:
    """Resume tripinfo, los detectores E2 y el statistic-output de una corrida de zona."""
    perdida, espera, perdida_peaton = [], [], []
    if tripinfo.is_file():
        for _, elem in ET.iterparse(tripinfo, events=("end",)):
            if elem.tag == "tripinfo":
                perdida.append(float(elem.get("timeLoss", 0)))
                espera.append(float(elem.get("waitingTime", 0)))
                elem.clear()
            elif elem.tag == "personinfo":
                perdida_peaton.append(sum(float(w.get("timeLoss", 0)) for w in elem.iter("walk")))
                elem.clear()
    cola_max, detenciones = 0.0, 0
    if e2.is_file():
        for _, elem in ET.iterparse(e2, events=("end",)):
            if elem.tag == "interval":
                cola_max = max(cola_max, float(elem.get("maxJamLengthInVehicles", 0)))
                detenciones += int(float(elem.get("startedHalts", 0)))
                elem.clear()
    teleports = 0
    if statistics.is_file():
        nodo = ET.parse(statistics).getroot().find("teleports")
        teleports = int(nodo.get("total", 0)) if nodo is not None else 0
    return {
        "vehiculos": len(perdida),
        "demora_media_s": _media(perdida),
        "espera_media_s": _media(espera),
        "cola_max_veh": round(cola_max),
        "detenciones": detenciones,
        "peatones": len(perdida_peaton),
        "demora_peaton_s": _media(perdida_peaton),
        "teleports": teleports,
    }


def centro_nodos(net: Path, nodos: tuple[str, ...] | list[str]) -> tuple[float, float] | None:
    """Centro (coordenadas de la red) de los nodos de un cruce; None si no aparece ninguno."""
    buscados, puntos = set(nodos), []
    for _, elem in ET.iterparse(net, events=("end",)):
        if elem.tag == "junction" and elem.get("id") in buscados:
            puntos.append((float(elem.get("x")), float(elem.get("y"))))
        if elem.tag in ("edge", "junction"):
            elem.clear()
    if not puntos:
        return None
    return sum(p[0] for p in puntos) / len(puntos), sum(p[1] for p in puntos) / len(puntos)


# tipos de encuentro del dispositivo SSM de SUMO (atributo "type" de cada medida)
TIPOS_ALCANCE = frozenset({1, 2, 3, 18})            # uno detrás del otro en el mismo carril
TIPOS_CRUCE = frozenset({*range(4, 18), 19})        # convergencia, cruce y área de conflicto


def clase_encuentro(tipo: int | None) -> str:
    """"cruce" (convergencia o cruce de trayectorias), "alcance" (uno detrás del otro) u "otro"."""
    if tipo in TIPOS_CRUCE:
        return "cruce"
    if tipo in TIPOS_ALCANCE:
        return "alcance"
    return "otro"


def _medida(conflicto: ET.Element, tag: str) -> tuple[float | None, tuple[float, float] | None, int | None]:
    """Valor, posición y tipo de encuentro de una medida SSM (minTTC, maxDRAC, PET); None si es NA."""
    elem = conflicto.find(tag)
    if elem is None:
        return None, None, None
    try:
        valor = float(elem.get("value", "NA"))
    except ValueError:
        return None, None, None
    try:
        tipo = int(elem.get("type", ""))
    except ValueError:
        tipo = None
    try:   # "x,y" o, en una red 3D, "x,y,z"
        x, y = (float(v) for v in elem.get("position", "").split(",")[:2])
        return valor, (x, y), tipo
    except ValueError:
        return valor, None, tipo


def leer_conflictos(
    ssm: Path, centro: tuple[float, float] | None, radio_m: float = RADIO_CONFLICTOS_M,
) -> dict[str, int]:
    """Conflictos graves cerca del cruce en la salida del dispositivo SSM.

    Cada vehículo con el dispositivo registra sus conflictos, así que un mismo encuentro
    aparece dos veces (A con B y B con A): cada par cuenta una vez por ventana de 10 s.
    Se separan por la clase del encuentro de la medida que lo hizo grave: los de cruce
    (trayectorias que se cruzan o convergen, los que un semáforo busca evitar) y los de
    alcance (uno detrás del otro, que aumentan con las colas del rojo).
    Sin `centro` se cuentan los de toda la zona.
    """
    claves = ("graves", "ttc", "drac", "pet", "cruce", "alcance")
    vistos: dict[str, set] = {k: set() for k in claves}
    if ssm.is_file():
        for _, elem in ET.iterparse(ssm, events=("end",)):
            if elem.tag != "conflict":
                continue
            medidas = {
                "ttc": (*_medida(elem, "minTTC"), lambda v: v < TTC_CRITICO),
                "pet": (*_medida(elem, "PET"), lambda v: v < PET_CRITICO),
                "drac": (*_medida(elem, "maxDRAC"), lambda v: v > DRAC_CRITICO),
            }
            graves = {k: m for k, m in medidas.items() if m[0] is not None and m[3](m[0])}
            pos = next((m[1] for m in graves.values() if m[1] is not None), None)
            cerca = centro is None or (pos is not None and math.dist(pos, centro) <= radio_m)
            if graves and cerca:
                clave = (frozenset((elem.get("ego"), elem.get("foe"))),
                         int(float(elem.get("begin", 0)) // VENTANA_CONFLICTO_S))
                vistos["graves"].add(clave)
                for k in graves:
                    vistos[k].add(clave)
                clase = clase_encuentro(next(iter(graves.values()))[2])
                if clase in vistos:
                    vistos[clase].add(clave)
            elem.clear()
    return {
        "conflictos": len(vistos["graves"]),
        "conflictos_cruce": len(vistos["cruce"]),
        "conflictos_alcance": len(vistos["alcance"]),
        "conflictos_ttc": len(vistos["ttc"]),
        "conflictos_drac": len(vistos["drac"]),
        "conflictos_pet": len(vistos["pet"]),
    }


def agregar_semillas(corridas: list[dict[str, float | int | None]]) -> dict:
    """Métricas de varias semillas: la media de cada una y su rango (mínimo, máximo).

    Una sola semilla da un número que puede cambiar bastante con otra; con varias se
    reporta "entre X y Y", como hace Semáforos de Barranquilla.
    """
    claves = corridas[0].keys() if corridas else []
    medias: dict[str, float | int | None] = {}
    rangos: dict[str, list] = {}
    for k in claves:
        valores = [c[k] for c in corridas if c.get(k) is not None]
        if not valores:
            medias[k] = None
            continue
        media = sum(valores) / len(valores)
        medias[k] = round(media, 1) if isinstance(media, float) and not media.is_integer() else round(media)
        rangos[k] = [min(valores), max(valores)]
    return {**medias, "rangos": rangos, "repeticiones": len(corridas)}


def correr_programa(
    cfg: ComparacionProgramaConfig,
    stats: ComparacionProgramaStats | None = None,
    cancelar: threading.Event | None = None,
) -> ComparacionProgramaResult:
    """Corre SUMO en la zona con un programa y devuelve sus métricas."""
    sumo = shutil.which("sumo")
    if sumo is None:
        raise ComparacionProgramaError("No se encontró 'sumo' en el PATH. ¿Está instalado eclipse-sumo?")
    revisar_cancelacion(cancelar)
    cfg.destino_dir.mkdir(parents=True, exist_ok=True)
    salida_e2 = cfg.destino_dir / "e2.xml"
    detectores = cfg.destino_dir / "detectores.add.xml"
    n = escribir_detectores(cfg.zona_net, cfg.accesos, detectores, salida_e2)
    adicionales = [detectores, *cfg.adicionales]
    if cfg.programa is not None:
        programa = cfg.destino_dir / "programa.add.xml"
        escribir_programa(cfg.programa, programa)
        adicionales.append(programa)

    resultado = ejecutar([sumo, *cfg.to_args(adicionales)], cwd=cfg.destino_dir, cancelar=cancelar)
    if resultado.returncode != 0:
        raise ComparacionProgramaError(
            f"SUMO falló en la zona (código {resultado.returncode}):\n{resultado.stderr[-2000:]}"
        )
    metricas = leer_metricas(cfg.destino_dir / "tripinfo.xml", salida_e2, cfg.destino_dir / "statistics.xml")
    if cfg.ssm:
        centro = centro_nodos(cfg.zona_net, cfg.nodos)
        metricas.update(leer_conflictos(cfg.destino_dir / "ssm.xml", centro))
    if stats is not None:
        stats.detectores += n
        stats.vehiculos += metricas["vehiculos"] or 0
        stats.peatones += metricas["peatones"] or 0
        stats.corridas.append(cfg.programa.program_id if cfg.programa else "actual")
    return ComparacionProgramaResult(metricas=metricas)
