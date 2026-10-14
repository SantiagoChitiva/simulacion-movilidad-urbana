"""
Demanda para las zonas recortadas del simulador 3D comparativo.

La encuesta solo trae viajes internos de Usaquén. Recortada a unos cientos de metros
alrededor de un cruce, la demanda real queda en unas decenas de vehículos, muy poca
para ver el efecto de un semáforo. Por eso la zona combina:

- los viajes reales de una corrida que pasan por la zona (cutRoutes.py), si hay alguna, y
- tráfico de fondo sintético por modo (randomTrips.py), con intensidades en veh/h o
  personas/h que el usuario puede ajustar.

Los dos lados de la comparación usan exactamente los mismos archivos de demanda.
"""
import sys
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import HORA_INI
from .proceso import ejecutar, revisar_cancelacion
from .subred import SubredError, encontrar_herramienta
from .vtypes import BUS_PT_ID, VTYPES

# modo de fondo -> (vType, vClass de randomTrips)
_MODOS_FONDO: dict[str, tuple[str, str]] = {
    "auto": ("auto", "passenger"),
    "moto": ("moto", "motorcycle"),
    "taxi": ("taxi", "taxi"),
    "bici": ("bici", "bicycle"),
    "bus": (BUS_PT_ID, "bus"),
}


@dataclass(frozen=True)
class DemandaZonaConfig:
    zona_net: Path
    destino_dir: Path
    # intensidad del tráfico de fondo por modo (veh/h); "peaton" en personas/h
    intensidades: dict[str, float] = field(default_factory=lambda: {
        "auto": 700, "moto": 250, "taxi": 120, "bici": 60, "bus": 30, "peaton": 400,
    })
    inicio: float = HORA_INI
    duracion_s: float = 3600
    semilla: int = 42

    def args_random_trips(self, script: str, modo: str, destino: Path) -> list[str]:
        """Argumentos de randomTrips.py para un modo de fondo."""
        periodo = 3600 / self.intensidades[modo]
        args = [
            sys.executable, script,
            "-n", str(self.zona_net),
            "-o", str(destino),
            "-b", str(self.inicio),
            "-e", str(self.inicio + self.duracion_s),
            "-p", f"{periodo:.3f}",
            "--seed", str(self.semilla),
            "--prefix", f"fondo_{modo}_",
            "--validate",
        ]
        if modo == "peaton":
            return args + ["--pedestrians", "--max-distance", "800"]
        vtype, vclass = _MODOS_FONDO[modo]
        # fringe-factor: los viajes entran y salen por el borde de la zona, como tráfico de paso
        return args + [
            "--vclass", vclass,
            "--fringe-factor", "10",
            "--min-distance", "150",
            "--trip-attributes", f'type="{vtype}" departLane="best" departSpeed="max"',
        ]


@dataclass(frozen=True)
class DemandaZonaResult:
    archivos: list[Path]        # rutas/trips para el .sumocfg, en este orden
    vtypes: Path                # additional con los vTypes
    fuente: str                 # "real", "sintetica" o "real+sintetica"


@dataclass
class DemandaZonaStats:
    viajes_reales: int = 0
    viajes_sinteticos: dict[str, int] = field(default_factory=dict)


def escribir_vtypes(destino: Path) -> Path:
    """Additional con los vTypes del proyecto (las rutas recortadas no los traen)."""
    raiz = ET.Element("additional")
    for vtype in VTYPES.values():
        ET.SubElement(raiz, "vType", vtype.to_xml_attrs())
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    destino.parent.mkdir(parents=True, exist_ok=True)
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


def contar_viajes(path: Path) -> int:
    """Vehículos, trips y personas de un archivo de demanda."""
    if not path.is_file():
        return 0
    n = 0
    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag in ("vehicle", "trip", "person"):
            n += 1
            elem.clear()
    return n


def generar_demanda_zona(
    cfg: DemandaZonaConfig,
    rutas_reales: Path | None,
    stats: DemandaZonaStats | None = None,
    cancelar: threading.Event | None = None,
) -> DemandaZonaResult:
    """Arma la demanda de la zona: viajes reales recortados (si hay) + fondo sintético."""
    stats = stats if stats is not None else DemandaZonaStats()
    script = encontrar_herramienta("randomTrips.py")
    cfg.destino_dir.mkdir(parents=True, exist_ok=True)

    archivos: list[Path] = []
    if rutas_reales is not None and rutas_reales.is_file():
        stats.viajes_reales = contar_viajes(rutas_reales)
        if stats.viajes_reales:
            archivos.append(rutas_reales)

    for modo, intensidad in cfg.intensidades.items():
        if intensidad <= 0 or (modo != "peaton" and modo not in _MODOS_FONDO):
            continue
        revisar_cancelacion(cancelar)
        destino = cfg.destino_dir / f"fondo_{modo}.trips.xml"
        salida = ejecutar(cfg.args_random_trips(script, modo, destino), cancelar=cancelar)
        # randomTrips termina con error si ningún viaje pasa la validación (p. ej. una zona
        # sin ciclorrutas para bicis): ese modo simplemente queda sin fondo
        n = contar_viajes(destino) if salida.returncode == 0 else 0
        stats.viajes_sinteticos[modo] = n
        if n:
            archivos.append(destino)

    if not archivos:
        raise SubredError("La zona no tiene demanda: ni viajes reales ni tráfico de fondo válido.")

    sinteticos = sum(stats.viajes_sinteticos.values())
    fuente = (
        "real+sintetica" if stats.viajes_reales and sinteticos
        else "real" if stats.viajes_reales else "sintetica"
    )
    vtypes = escribir_vtypes(cfg.destino_dir / "vtypes.add.xml")
    return DemandaZonaResult(archivos=archivos, vtypes=vtypes, fuente=fuente)
