"""
Recorte de red y demanda a una zona geográfica (bounding box circular alrededor de un nodo).

Paso B del módulo de semáforos: dado el centroide de una intersección y un radio, extrae
la subred con netconvert y filtra la demanda con cutRoutes.py (herramienta de SUMO).
"""
import math
import os
import sys
import shutil
import threading
from dataclasses import dataclass
from pathlib import Path

from .proceso import Cancelado, revisar_cancelacion, ejecutar


class SubredError(RuntimeError):
    """netconvert o cutRoutes.py no están disponibles o terminaron con error."""


@dataclass(frozen=True)
class SubredConfig:
    net_origen: Path
    centro_lonlat: tuple[float, float]   # (lon, lat) del nodo central
    radio_m: float                        # radio del recorte en metros
    destino: Path                         # archivo de salida zona.net.xml


@dataclass(frozen=True)
class SubredResult:
    net: Path
    bbox: tuple[float, float, float, float]   # (w, s, e, n) en grados


@dataclass
class SubredStats:
    net_creado: bool = False
    demanda_recortada: bool = False


@dataclass(frozen=True)
class SubredDemandaConfig:
    zona_net: Path
    rou_xml: Path               # rutas de la corrida origen
    destino: Path               # zona.rou.xml de salida
    net_orig: Path              # red original (para --orig-net)
    vehroute_xml: Path | None = None   # opcional: salida de vehroute-output


@dataclass(frozen=True)
class SubredDemandaResult:
    rou: Path


# --------------------------------------------------------------------------- geometría

def _bbox_grados(lon: float, lat: float, radio_m: float) -> tuple[float, float, float, float]:
    """Bounding box (w, s, e, n) centrado en (lon, lat) con radio_m metros."""
    lat_rad = math.radians(lat)
    d_lat = math.degrees(radio_m / 6_371_000)
    d_lon = math.degrees(radio_m / (6_371_000 * math.cos(lat_rad)))
    return (
        round(lon - d_lon, 6),
        round(lat - d_lat, 6),
        round(lon + d_lon, 6),
        round(lat + d_lat, 6),
    )


# --------------------------------------------------------------------------- helpers de herramientas

def encontrar_herramienta(nombre: str) -> str:
    """Localiza un script de SUMO (cutRoutes.py, randomTrips.py, ...) en SUMO_HOME o en el paquete eclipse-sumo."""
    bases: list[Path] = []
    # 1. $SUMO_HOME/tools (instalación estándar de SUMO)
    sumo_home = os.environ.get("SUMO_HOME")
    if sumo_home:
        bases.append(Path(sumo_home))
    # 2. Paquete pip eclipse-sumo: instala las herramientas bajo sumo/tools/
    try:
        import sumo as _sumo_pkg
        bases.append(Path(_sumo_pkg.__file__).parent)
    except ImportError:
        pass
    for base in bases:
        for sub in ("tools/route", "tools"):
            candidato = base / sub / nombre
            if candidato.is_file():
                return str(candidato)
    raise SubredError(
        f"No se encontró '{nombre}'. "
        "Configura la variable de entorno SUMO_HOME o instala el paquete eclipse-sumo."
    )


def _encontrar_cutroutes() -> str:
    return encontrar_herramienta("cutRoutes.py")


# --------------------------------------------------------------------------- funciones públicas

def recortar_red(
    cfg: SubredConfig,
    stats: SubredStats | None = None,
    cancelar: threading.Event | None = None,
) -> SubredResult:
    """Extrae la subred alrededor de cfg.centro_lonlat con netconvert.

    Calcula el bounding box en grados a partir del radio en metros y llama a netconvert
    con --keep-edges.in-geo-boundary.
    """
    executable = shutil.which("netconvert")
    if executable is None:
        raise SubredError(
            "No se encontró 'netconvert' en el PATH. ¿Está SUMO instalado y en el PATH?"
        )

    if not cfg.net_origen.is_file():
        raise FileNotFoundError(f"Red de origen no encontrada: {cfg.net_origen}")

    revisar_cancelacion(cancelar)

    lon, lat = cfg.centro_lonlat
    bbox = _bbox_grados(lon, lat, cfg.radio_m)
    w, s, e, n = bbox
    geo_boundary = f"{w},{s},{e},{n}"

    cfg.destino.parent.mkdir(parents=True, exist_ok=True)

    resultado = ejecutar(
        [
            executable,
            "-s", str(cfg.net_origen),
            "--keep-edges.in-geo-boundary", geo_boundary,
            "--geometry.remove", "false",
            "-o", str(cfg.destino),
        ],
        cancelar=cancelar,
    )
    if resultado.returncode != 0:
        raise SubredError(
            f"netconvert falló (código {resultado.returncode}):\n{resultado.stderr[-2000:]}"
        )

    if stats is not None:
        stats.net_creado = True

    return SubredResult(net=cfg.destino, bbox=bbox)


def recortar_demanda(
    cfg: SubredDemandaConfig,
    stats: SubredStats | None = None,
    cancelar: threading.Event | None = None,
) -> SubredDemandaResult:
    """Filtra la demanda al subconjunto de rutas que pasan por la zona con cutRoutes.py.

    cutRoutes.py retiene los vehículos cuya ruta toca al menos un edge de la subred.
    Si hay vehroute-output se usa en lugar de las rutas: trae los tiempos de salida de cada
    edge y cutRoutes los usa para calcular la hora de entrada a la zona. Las rutas que
    quedan partidas en la zona generan un tramo por parte (--disconnected-action keep.walk).
    """
    script = _encontrar_cutroutes()

    if not cfg.zona_net.is_file():
        raise FileNotFoundError(f"Subred no encontrada: {cfg.zona_net}")
    rutas = cfg.vehroute_xml if cfg.vehroute_xml is not None and cfg.vehroute_xml.is_file() else cfg.rou_xml
    if not rutas.is_file():
        raise FileNotFoundError(f"Archivo de rutas no encontrado: {rutas}")

    revisar_cancelacion(cancelar)

    cfg.destino.parent.mkdir(parents=True, exist_ok=True)

    args = [
        sys.executable, script,
        str(cfg.zona_net),
        str(rutas),
        "-o", str(cfg.destino),
        "--orig-net", str(cfg.net_orig),
        "--disconnected-action", "keep.walk",
    ]

    resultado = ejecutar(args, cancelar=cancelar)
    if resultado.returncode != 0:
        raise SubredError(
            f"cutRoutes.py falló (código {resultado.returncode}):\n{resultado.stderr[-2000:]}"
        )

    if stats is not None:
        stats.demanda_recortada = True

    return SubredDemandaResult(rou=cfg.destino)
