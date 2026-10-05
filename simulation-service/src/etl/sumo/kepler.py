"""
FCD de SUMO (fcd-output.geo=true) → GeoJSON de trips para la capa Trip de kepler.gl.

Cada vehículo/persona es un LineString con coordenadas [lon, lat, z, t]:
- t = unix time = medianoche de base_date (UTC) + segundos de simulación. Kepler solo
  reconoce como tiempo valores unix "reales", por eso la fecha ancla; muestra la hora
  en UTC, así que 07:00:00 en pantalla = 25200 s en SUMO.
- z = altura relativa a z_base (por defecto la mínima del FCD), para que los trayectos
  no floten a 2500 m: kepler no dibuja terreno. SUMO solo escribe z si la red es 3D.
"""
import json
import math
import re
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# SUMO a veces escribe x=inf, y=inf, z=-1073741824 en posiciones que no puede
# convertir a lon/lat: por encima de este valor absoluto z se considera inválida
_Z_INVALIDA = 1e5


@dataclass(frozen=True)
class KeplerTripsConfig:
    fcd_path: Path
    output_path: Path
    step: float = 5.0             # segundos: como máximo un punto cada `step` por entidad
    angle: float = 20.0           # ...pero también se guarda si el rumbo cambia >= `angle` grados
    min_move: float = 20.0        # metros: descarta entidades que se mueven menos
    base_date: str = "2000-01-01" # fecha ancla (convención; no afecta la hora)
    z_scale: float = 1.0          # exageración vertical
    z_base: float | None = None   # altura que se resta a z; None = mínima del FCD
    include_z: bool = True        # False = todo queda en z = 0


@dataclass
class KeplerTripsStats:
    entidades: int = 0
    puntos_invalidos: int = 0
    puntos_leidos: int = 0
    puntos_exportados: int = 0
    trips_escritos: int = 0
    descartados: Counter = field(default_factory=Counter)   # por modo: casi sin movimiento
    por_modo: Counter = field(default_factory=Counter)
    z_min: float | None = None
    z_max: float | None = None


@dataclass(frozen=True)
class KeplerTripsResult:
    output_path: Path
    stats: KeplerTripsStats


@dataclass
class _Entidad:
    kind: str                     # "vehicle" | "person"
    mode: str
    pts: list[tuple[float, float, float, float, float]] = field(default_factory=list)
    # cada punto: (t, lon, lat, angle, z)


# ------------------------------------------------------------ utilidades

def haversine(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def angle_diff(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return 360 - d if d > 180 else d


def mode_of(kind: str, elem: ET.Element) -> str:
    if kind == "vehicle":
        return elem.get("type", "desconocido")
    # personas: el modo sale del prefijo del id (peaton_12, transporte_publico_3)
    return re.sub(r"_?\d+$", "", elem.get("id", ""))


def reduce_points(pts: list[tuple], step: float, angle_thr: float) -> list[tuple]:
    """1) colapsa tramos quietos a (primer, último) punto; 2) muestrea por tiempo/rumbo."""
    # 1) tramos quietos: conserva el primer y el último punto de cada tramo con misma posición
    comp = []
    n = len(pts)
    for i, p in enumerate(pts):
        same_prev = i > 0 and abs(p[1] - pts[i - 1][1]) < 1e-6 and abs(p[2] - pts[i - 1][2]) < 1e-6
        same_next = i < n - 1 and abs(p[1] - pts[i + 1][1]) < 1e-6 and abs(p[2] - pts[i + 1][2]) < 1e-6
        if not (same_prev and same_next):
            comp.append(p)

    # 2) muestreo
    out = []
    last_t = last_ang = None
    for i, p in enumerate(comp):
        keep = (
            i == 0
            or i == len(comp) - 1
            or p[0] - last_t >= step
            or angle_diff(p[3], last_ang) >= angle_thr
        )
        if keep:
            out.append(p)
            last_t, last_ang = p[0], p[3]
    return out


# --------------------------------------------------------------- lectura

def read_entities(fcd_path: Path, stats: KeplerTripsStats) -> dict[str, _Entidad]:
    """Agrupa los puntos del FCD por entidad, descartando posiciones inválidas."""
    entidades: dict[str, _Entidad] = {}
    root: ET.Element | None = None

    for event, elem in ET.iterparse(fcd_path, events=("start", "end")):
        if event == "start":
            if root is None:
                root = elem          # <fcd-export>
            continue

        if elem.tag != "timestep":
            continue

        t = float(elem.get("time", 0))
        for child in elem:
            if child.tag not in ("vehicle", "person"):
                continue
            stats.puntos_leidos += 1

            x = float(child.get("x", "inf"))
            y = float(child.get("y", "inf"))
            z = float(child.get("z", 0))
            if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)) or abs(z) > _Z_INVALIDA:
                stats.puntos_invalidos += 1
                continue

            eid = child.get("id")
            ent = entidades.get(eid)
            if ent is None:
                ent = entidades[eid] = _Entidad(child.tag, mode_of(child.tag, child))
            ent.pts.append((t, x, y, float(child.get("angle", 0)), z))

        # libera memoria: el timestep ya fue procesado
        elem.clear()
        if root is not None:
            root.clear()

    stats.entidades = len(entidades)
    return entidades


# --------------------------------------------------------------- GeoJSON

def _feature(
    eid: str, ent: _Entidad, red: list[tuple], dist: float,
    base: int, z_base: float, config: KeplerTripsConfig, has_z: bool,
) -> dict[str, Any]:
    t0, t1 = red[0][0], red[-1][0]
    return {
        "type": "Feature",
        "properties": {
            "id": eid,
            "mode": ent.mode,
            "category": "vehiculo" if ent.kind == "vehicle" else "persona",
            "inicio_s": int(t0),
            "fin_s": int(t1),
            "dist_m": round(dist),
            "avg_kmh": round(dist / max(t1 - t0, 1) * 3.6, 1),
        },
        "geometry": {
            "type": "LineString",
            "coordinates": [
                [
                    round(p[1], 5),
                    round(p[2], 5),
                    round((p[4] - z_base) * config.z_scale, 1) if has_z else 0,
                    base + int(p[0]),
                ]
                for p in red
            ],
        },
    }


def convert_fcd_to_kepler_trips(config: KeplerTripsConfig) -> KeplerTripsResult:
    if not config.fcd_path.is_file():
        raise FileNotFoundError(f"No existe el archivo FCD: {config.fcd_path}")
    if config.step <= 0:
        raise ValueError("step debe ser > 0")

    base = int(
        datetime.strptime(config.base_date, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
    )

    stats = KeplerTripsStats()
    entidades = read_entities(config.fcd_path, stats)

    all_z = [p[4] for ent in entidades.values() for p in ent.pts]
    has_z = config.include_z and any(z != 0 for z in all_z)
    z_base = 0.0
    if has_z:
        stats.z_min, stats.z_max = min(all_z), max(all_z)
        z_base = config.z_base if config.z_base is not None else stats.z_min

    features = []
    for eid, ent in entidades.items():
        red = reduce_points(ent.pts, config.step, config.angle)
        dist = sum(
            haversine(red[i][1], red[i][2], red[i + 1][1], red[i + 1][2])
            for i in range(len(red) - 1)
        )
        if len(red) < 2 or dist < config.min_move:
            stats.descartados[ent.mode] += 1
            continue

        features.append(_feature(eid, ent, red, dist, base, z_base, config, has_z))
        stats.puntos_exportados += len(red)
        stats.por_modo[ent.mode] += 1

    stats.trips_escritos = len(features)

    config.output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config.output_path, "w", encoding="utf-8") as out:
        json.dump({"type": "FeatureCollection", "features": features}, out, separators=(",", ":"))

    return KeplerTripsResult(config.output_path, stats)
