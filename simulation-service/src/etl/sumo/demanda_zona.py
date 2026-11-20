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
import random
import sys
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import HORA_INI
from .proceso import ejecutar, revisar_cancelacion
from .subred import SubredError, encontrar_herramienta
from .vtypes import BUS_PT_ID, PARAMS_BUS_SITP, VTYPE_BUS_SITP, VTYPE_BUS_TM, VTYPES

# modo de fondo -> (vType, vClass de randomTrips)
_MODOS_FONDO: dict[str, tuple[str, str]] = {
    "auto": ("auto", "passenger"),
    "moto": ("moto", "motorcycle"),
    "taxi": ("taxi", "taxi"),
    "bici": ("bici", "bicycle"),
    "bus": (BUS_PT_ID, "bus"),
}
# desfase de semilla por modo: con la misma semilla randomTrips sortea los mismos
# orígenes y destinos para todos los modos (moto_1 y taxi_1 hacían el mismo viaje)
_DESFASE_SEMILLA = {"auto": 0, "moto": 1, "taxi": 2, "bici": 3, "bus": 4, "peaton": 5}


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
            "--seed", str(self.semilla + _DESFASE_SEMILLA.get(modo, 0)),
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


# vTypes que define el additional de la zona: los del proyecto y los de los buses del GTFS
# (en una corrida, estos últimos vienen en pt_vehiculos.rou.xml, que la zona no carga)
IDS_VTYPES_ZONA = frozenset([*(v.id for v in VTYPES.values()), VTYPE_BUS_SITP["id"], VTYPE_BUS_TM["id"]])


def escribir_vtypes(destino: Path) -> Path:
    """Additional con los vTypes de la zona (a las rutas recortadas se les quitan: subred.sin_vtypes_repetidos)."""
    raiz = ET.Element("additional")
    for vtype in VTYPES.values():
        ET.SubElement(raiz, "vType", vtype.to_xml_attrs())
    for atributos in (VTYPE_BUS_SITP, VTYPE_BUS_TM):
        vtype = ET.SubElement(raiz, "vType", atributos)
        for clave, valor in PARAMS_BUS_SITP.items():
            ET.SubElement(vtype, "param", key=clave, value=valor)
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    destino.parent.mkdir(parents=True, exist_ok=True)
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


# corrimiento máximo de la salida de un viaje real entre semillas (s)
AMPLITUD_SALIDAS_S = 300
_ENTIDADES = ("vehicle", "trip", "person", "flow")


def variar_salidas(
    origen: Path, destino: Path, semilla: int, amplitud_s: float = AMPLITUD_SALIDAS_S,
    inicio: float | None = None, fin: float | None = None,
) -> Path:
    """Copia de una demanda recortada con cada salida corrida al azar hasta ±`amplitud_s`.

    Los viajes, sus orígenes, destinos y rutas no cambian; solo el instante exacto de salida,
    que la encuesta tampoco conoce (las respuestas se redondean y las copias de cada una ya
    se reparten al azar alrededor de la hora reportada). Con `inicio`/`fin` las salidas
    quedan dentro de la ventana. El archivo se reordena por salida: SUMO descarta lo que
    llega desordenado.
    """
    rng = random.Random(semilla)
    arbol = ET.parse(origen)
    raiz = arbol.getroot()
    fijos, entidades = [], []
    for elem in list(raiz):
        raiz.remove(elem)
        depart = elem.get("depart") if elem.tag in _ENTIDADES else None
        try:
            t = float(depart)
        except (TypeError, ValueError):
            fijos.append(elem)   # vTypes, rutas con nombre, salidas "triggered"...
            continue
        t += rng.uniform(-amplitud_s, amplitud_s)
        if inicio is not None:
            t = max(t, inicio)
        if fin is not None:
            t = min(t, fin - 1)
        elem.set("depart", f"{t:.2f}")
        entidades.append((t, elem))
    entidades.sort(key=lambda par: par[0])
    raiz.extend(fijos)
    raiz.extend(e for _, e in entidades)
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
