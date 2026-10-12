"""
Priorización de cruces sin semáforo para instalación futura de señalización.

Fase F: recorre los junction de tipo "priority" o "right_before_left" de la red
(cruces no semaforizados) y les asigna un puntaje basado en los criterios del §3.2
del documento de propuesta. Los cruces con semáforo existente a menos de 300 m
quedan excluidos.

Pesos del puntaje (total 100):
  jerarquía del par de vías         40
  carriles y geometría               15
  hueco en corredor semaforizado     15
  demanda peatonal                   15
  siniestralidad (reservado)         15
"""
import math
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .intersecciones import CLASES_VIA, leer_semaforos, volumenes_por_edge, _transformador


# ─────────────────────────────────────── jerarquía de vías

_JERARQUIA: dict[str, int] = {
    "motorway": 7, "trunk": 6, "primary": 5, "secondary": 4,
    "tertiary": 3, "unclassified": 2, "residential": 1,
    "living_street": 1, "service": 0,
}


def _clase_jerarquia(tipo: str | None) -> int:
    if not tipo:
        return 0
    base = tipo.split("|")[0].split(".")[-1].removesuffix("_link")
    return _JERARQUIA.get(base, 0)


def _puntaje_jerarquia(tipo_a: str | None, tipo_b: str | None) -> float:
    """Puntuación 0-40 según el par de vías más importante que se cruza."""
    h_a = _clase_jerarquia(tipo_a)
    h_b = _clase_jerarquia(tipo_b)
    max_h = max(h_a, h_b)
    # Solo se justifica semáforo si ambas vías tienen cierta jerarquía
    if max_h >= 5 and min(h_a, h_b) >= 3:
        return 40.0
    if max_h >= 4 and min(h_a, h_b) >= 2:
        return 30.0
    if max_h >= 3:
        return 20.0
    if max_h >= 2:
        return 10.0
    return 0.0


# ─────────────────────────────────────── distancia entre puntos (m)

def _distancia_m(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


# ─────────────────────────────────────── resultado

@dataclass
class PuntajeCruce:
    nodo_id: str
    lon: float
    lat: float
    puntaje_total: float
    nivel: str          # "prioritario" | "recomendado" | "observacion" | "sin_accion"
    detalle: dict[str, float] = field(default_factory=dict)
    distancia_semaforo_m: float | None = None
    calles: list[str] = field(default_factory=list)


def _nivel(puntaje: float) -> str:
    if puntaje >= 60:
        return "prioritario"
    if puntaje >= 40:
        return "recomendado"
    if puntaje >= 20:
        return "observacion"
    return "sin_accion"


# ─────────────────────────────────────── función principal

def puntuar_cruces(
    net_path: Path,
    semaforos_existentes: list[Any] | None = None,   # lista de Semaforo
    volumenes_run_id: dict[str, Counter] | None = None,   # dict edge → Counter(tipo → n)
) -> list[PuntajeCruce]:
    """Puntúa los cruces no semaforizados de la red.

    Args:
        net_path: ruta al .net.xml de SUMO.
        semaforos_existentes: lista de Semaforo del catálogo (para distancia al semáforo más cercano).
        volumenes_run_id: volumenes_por_edge de una corrida (para demanda peatonal).

    Returns:
        Lista de PuntajeCruce ordenada de mayor a menor puntaje.
    """
    a_lonlat = None
    edges: dict[str, dict] = {}
    nodos: dict[str, tuple] = {}   # id → (x, y, z, type)
    tl_ids: set[str] = set()
    conexiones_por_nodo: dict[str, list[str]] = defaultdict(list)  # junction → [from_edge, ...]

    for _, elem in ET.iterparse(net_path, events=("end",)):
        tag = elem.tag
        if tag == "location":
            a_lonlat = _transformador(elem)
        elif tag == "edge":
            if elem.get("function") != "internal":
                edge_id = elem.get("id")
                edges[edge_id] = {
                    "to": elem.get("to"),
                    "from": elem.get("from"),
                    "type": elem.get("type"),
                    "name": elem.get("name"),
                    "carriles": len(elem.findall("lane")),
                }
                to = elem.get("to")
                if to:
                    conexiones_por_nodo[to].append(edge_id)
            elem.clear()
        elif tag == "junction":
            j_type = elem.get("type")
            if j_type not in ("internal", "dead_end"):
                nodos[elem.get("id")] = (
                    float(elem.get("x")), float(elem.get("y")),
                    float(elem.get("z", 0)), j_type or ""
                )
            elem.clear()
        elif tag == "tlLogic":
            tl_ids.add(elem.get("id"))
            elem.clear()
        else:
            elem.clear()

    if a_lonlat is None:
        raise ValueError(f"La red {net_path} no tiene <location>")

    # posiciones lonlat de los semáforos existentes
    posiciones_semaforos: list[tuple[float, float]] = []
    if semaforos_existentes:
        posiciones_semaforos = [(s.lon, s.lat) for s in semaforos_existentes]

    resultados: list[PuntajeCruce] = []

    for nodo_id, (x, y, z, j_type) in nodos.items():
        # solo cruces no semaforizados con tipo relevante
        if j_type not in ("priority", "right_before_left"):
            continue
        if nodo_id in tl_ids:
            continue

        lon, lat = a_lonlat(x, y)

        # distancia al semáforo más cercano
        dist_min: float | None = None
        if posiciones_semaforos:
            dist_min = min(
                _distancia_m(lon, lat, slon, slat)
                for slon, slat in posiciones_semaforos
            )
            # regla dura: excluir si hay semáforo a < 300 m
            if dist_min < 300:
                continue

        # edges que llegan a este nodo
        edges_entrantes = conexiones_por_nodo.get(nodo_id, [])
        if len(edges_entrantes) < 2:
            continue

        tipos_via = [edges[e]["type"] for e in edges_entrantes if e in edges]
        nombres_via = list(dict.fromkeys(
            edges[e]["name"] for e in edges_entrantes
            if e in edges and edges[e]["name"]
        ))

        # ordenar por jerarquía
        tipos_via.sort(key=_clase_jerarquia, reverse=True)
        tipo_a = tipos_via[0] if tipos_via else None
        tipo_b = tipos_via[1] if len(tipos_via) > 1 else None

        pts_jerarquia = _puntaje_jerarquia(tipo_a, tipo_b)

        # carriles: más carriles → mayor puntuación (máx 15)
        max_carriles = max((edges[e]["carriles"] for e in edges_entrantes if e in edges), default=1)
        pts_carriles = min(max_carriles * 3.0, 15.0)

        # hueco en corredor semaforizado: si hay semáforos en el radio 300-600 m (indicativo)
        pts_hueco = 0.0
        if posiciones_semaforos and dist_min is not None:
            if 300 <= dist_min <= 600:
                pts_hueco = 15.0
            elif 600 < dist_min <= 1000:
                pts_hueco = 7.5

        # demanda peatonal: personas que cruzan el nodo en la corrida
        pts_peatonal = 0.0
        if volumenes_run_id:
            personas_nodo = sum(
                cnt.get("peaton", 0) + cnt.get("transporte_publico", 0)
                for edge_id in edges_entrantes
                for cnt in [volumenes_run_id.get(edge_id, Counter())]
            )
            pts_peatonal = min(personas_nodo / 10.0, 15.0)

        # siniestralidad (reservado)
        pts_siniestralidad = 0.0

        puntaje = pts_jerarquia + pts_carriles + pts_hueco + pts_peatonal + pts_siniestralidad

        resultados.append(PuntajeCruce(
            nodo_id=nodo_id,
            lon=round(lon, 6),
            lat=round(lat, 6),
            puntaje_total=round(puntaje, 1),
            nivel=_nivel(puntaje),
            detalle={
                "jerarquia": pts_jerarquia,
                "carriles": pts_carriles,
                "hueco_corredor": pts_hueco,
                "demanda_peatonal": pts_peatonal,
                "siniestralidad": pts_siniestralidad,
            },
            distancia_semaforo_m=round(dist_min, 0) if dist_min is not None else None,
            calles=nombres_via[:4],
        ))

    resultados.sort(key=lambda c: -c.puntaje_total)
    return resultados


def a_geojson(cruces: list[PuntajeCruce]) -> dict:
    """Convierte la lista de PuntajeCruce a un FeatureCollection GeoJSON."""
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [c.lon, c.lat]},
                "properties": {
                    "id": c.nodo_id,
                    "puntaje_total": c.puntaje_total,
                    "nivel": c.nivel,
                    "detalle": c.detalle,
                    "distancia_semaforo_m": c.distancia_semaforo_m,
                    "calles": c.calles,
                },
            }
            for c in cruces
        ],
    }
