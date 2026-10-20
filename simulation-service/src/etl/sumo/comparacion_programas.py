"""
Comparación de programas de un semáforo existente en una zona recortada.

Fase D del módulo de semáforos. Para cada programa (el actual de la red, el optimizado
por Webster o uno que guardó el usuario) se corre SUMO una hora punta en la misma zona
y con la misma demanda; solo cambia el programa del semáforo. SUMO usa el último
programa cargado de cada tlLogic, así que basta con pasarlo como additional.

Métricas (las mismas para todos los programas):
- tiempo perdido y espera media por vehículo (tripinfo de todos los vehículos de la zona),
- cola más larga y detenciones en los accesos del semáforo (detectores E2 por carril),
- tiempo perdido de los peatones (personinfo).
"""
import shutil
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import HORA_INI
from .proceso import ejecutar, revisar_cancelacion
from .programas_tls import ProgramaTLS, escribir_programa

DURACION_S = 3600
PERIODO_E2_S = 60


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

    def to_args(self, adicionales: list[Path]) -> list[str]:
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
    adicionales = [detectores]
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
    if stats is not None:
        stats.detectores += n
        stats.vehiculos += metricas["vehiculos"] or 0
        stats.peatones += metricas["peatones"] or 0
        stats.corridas.append(cfg.programa.program_id if cfg.programa else "actual")
    return ComparacionProgramaResult(metricas=metricas)
