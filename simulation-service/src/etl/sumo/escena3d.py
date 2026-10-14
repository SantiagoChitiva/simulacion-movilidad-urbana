"""
Geometría de la escena del simulador 3D comparativo.

Todo va en coordenadas de la red de SUMO (metros, x al este, y al norte, z = altura del
modelo 3D de la red), las mismas que reporta TraCI para los actores, para que el visor
no tenga que proyectar nada en cada frame. Para el minimapa se incluye la transformación
inversa en forma de puntos de control (centro y bbox en lon/lat).

Incluye:
- carriles (forma 3D, ancho, si son peatonales o ciclorrutas),
- polígonos de los cruces (junctions),
- las luces del semáforo propuesto, una por conexión controlada (en la línea de pare),
- edificios de Microsoft Building Footprints (data/processed/edificios_ms.geojson)
  recortados a la zona; sin altura conocida se les asigna una de 6 a 21 m,
- las vías con nombre (para elegir qué mirar) y, por cada acceso al cruce, las rutas
  posibles según el giro (para inyectar el actor seguido).
"""
import json
import xml.etree.ElementTree as ET
import zlib
from collections import defaultdict
from functools import lru_cache
from pathlib import Path
from typing import Any

from .configuration import EDIFICIOS_GEOJSON
from .intersecciones import _via_osm
from .semaforo_nuevo import tipo_nodo

LARGO_ANTES_M = 220      # tramo que recorre el actor antes de llegar al cruce
LARGO_DESPUES_M = 160    # y después de cruzarlo
MAX_EDIFICIOS = 2500


def _puntos(shape: str) -> list[list[float]]:
    puntos = []
    for par in shape.split():
        xyz = [float(c) for c in par.split(",")]
        if len(xyz) == 2:
            xyz.append(0.0)
        puntos.append([round(xyz[0], 2), round(xyz[1], 2), round(xyz[2], 2)])
    return puntos


def _altura_edificio(props: dict, centro: tuple[float, float]) -> float:
    altura = props.get("height")
    if isinstance(altura, (int, float)) and altura > 0:
        return float(altura)
    # determinística por posición: 2 a 7 pisos de 3 m
    semilla = zlib.crc32(f"{centro[0]:.5f},{centro[1]:.5f}".encode())
    return 3.0 * (2 + semilla % 6)


@lru_cache(maxsize=1)
def _edificios_lonlat(path: Path) -> tuple[tuple[tuple[tuple[float, float], ...], float, tuple[float, float]], ...]:
    """(anillo exterior, altura, centro) de cada edificio; se lee una sola vez (~10 MB)."""
    if not path.is_file():
        return ()
    datos = json.loads(path.read_text(encoding="utf-8"))
    edificios = []
    for f in datos.get("features", []):
        geom = f.get("geometry") or {}
        if geom.get("type") == "Polygon":
            anillos = [geom["coordinates"][0]]
        elif geom.get("type") == "MultiPolygon":
            anillos = [p[0] for p in geom["coordinates"]]
        else:
            continue
        for anillo in anillos:
            if len(anillo) < 4:
                continue
            cx = sum(p[0] for p in anillo) / len(anillo)
            cy = sum(p[1] for p in anillo) / len(anillo)
            puntos = tuple((p[0], p[1]) for p in anillo)
            edificios.append((puntos, _altura_edificio(f.get("properties") or {}, (cx, cy)), (cx, cy)))
    return tuple(edificios)


def edificios_zona(
    bbox_lonlat: tuple[float, float, float, float],
    a_xy,
    z_suelo,
    path: Path = EDIFICIOS_GEOJSON,
) -> list[dict]:
    """Edificios cuyo centro cae en el bbox (w, s, e, n), en coordenadas de la red."""
    w, s, e, n = bbox_lonlat
    salida = []
    for anillo, altura, (cx, cy) in _edificios_lonlat(path):
        if not (w <= cx <= e and s <= cy <= n):
            continue
        puntos = [a_xy(lon, lat) for lon, lat in anillo]
        x0, y0 = a_xy(cx, cy)
        salida.append({
            "contorno": [[round(x, 2), round(y, 2)] for x, y in puntos],
            "altura": altura,
            "z": round(z_suelo(x0, y0), 2),
        })
        if len(salida) >= MAX_EDIFICIOS:
            break
    return salida


def _transformaciones(location: ET.Element):
    """(xy -> lonlat, lonlat -> xy) de la red a partir de su <location>."""
    from pyproj import Transformer

    offx, offy = (float(v) for v in location.get("netOffset", "0,0").split(","))
    proj = location.get("projParameter")
    a_geo = Transformer.from_crs(proj, "EPSG:4326", always_xy=True)
    a_proj = Transformer.from_crs("EPSG:4326", proj, always_xy=True)

    def a_lonlat(x: float, y: float) -> tuple[float, float]:
        return a_geo.transform(x - offx, y - offy)

    def a_xy(lon: float, lat: float) -> tuple[float, float]:
        px, py = a_proj.transform(lon, lat)
        return px + offx, py + offy

    return a_lonlat, a_xy


def _leer_red(net: Path, tl_id: str | None, nombres: dict[str, str]) -> dict[str, Any]:
    location = None
    carriles, cruces, luces, edges = [], [], [], {}
    for _, elem in ET.iterparse(net, events=("end",)):
        tag = elem.tag
        if tag == "location":
            location = elem
            continue
        if tag == "edge":
            funcion = elem.get("function")
            if funcion != "internal":
                eid = elem.get("id")
                edges[eid] = {
                    "nombre": elem.get("name") or nombres.get(_via_osm(eid)),
                    "tipo": elem.get("type"),
                }
            for lane in elem.findall("lane"):
                allow = lane.get("allow", "")
                carriles.append({
                    "id": lane.get("id"),
                    "edge": elem.get("id"),
                    "interno": funcion == "internal",
                    "ancho": float(lane.get("width", 3.2)),
                    "forma": _puntos(lane.get("shape", "")),
                    "peatonal": allow == "pedestrian" or funcion in ("crossing", "walkingarea"),
                    "ciclorruta": allow == "bicycle",
                })
            elem.clear()
        elif tag == "junction":
            if elem.get("type") != "internal" and elem.get("shape"):
                cruces.append({
                    "id": elem.get("id"),
                    "tipo": elem.get("type"),
                    "x": float(elem.get("x")), "y": float(elem.get("y")), "z": float(elem.get("z", 0)),
                    "forma": _puntos(elem.get("shape", "")),
                })
            elem.clear()
        elif tag == "connection":
            if tl_id is not None and elem.get("tl") == tl_id:
                luces.append({
                    "enlace": int(elem.get("linkIndex", 0)),
                    "desde_carril": f"{elem.get('from')}_{elem.get('fromLane')}",
                    "direccion": elem.get("dir"),
                })
            elem.clear()
    return {"location": location, "carriles": carriles, "cruces": cruces, "luces": luces, "edges": edges}


def _encadenar(edge, hacia_atras: bool, largo: float) -> list:
    """Edges que siguen (o preceden) a `edge` por la conexión más recta, hasta `largo` metros."""
    cadena, acumulado, actual = [], 0.0, edge
    vistos = {edge.getID()}
    while acumulado < largo:
        vecinos = actual.getIncoming() if hacia_atras else actual.getOutgoing()
        candidatos = []
        for vecino, conexiones in vecinos.items():
            if vecino.getID() in vistos or vecino.getFunction() == "internal":
                continue
            dirs = {c.getDirection() for c in conexiones}
            candidatos.append((0 if "s" in dirs else 1, -vecino.getLaneNumber(), vecino))
        if not candidatos:
            break
        actual = min(candidatos, key=lambda c: (c[0], c[1]))[2]
        vistos.add(actual.getID())
        cadena.append(actual)
        acumulado += actual.getLength()
    return list(reversed(cadena)) if hacia_atras else cadena


def rutas_por_acceso(net_path: Path, nodo_id: str, nombres: dict[str, str]) -> list[dict]:
    """Por cada edge que llega al cruce: las rutas que lo atraviesan, una por giro posible."""
    import sumolib

    net = sumolib.net.readNet(str(net_path), withInternal=False)
    if not net.hasNode(nodo_id):
        return []
    nodo = net.getNode(nodo_id)
    accesos = []
    for entrada in nodo.getIncoming():
        if entrada.getFunction() == "internal":
            continue
        giros: dict[str, dict] = {}
        for salida, conexiones in entrada.getOutgoing().items():
            for con in conexiones:
                direccion = con.getDirection()
                if direccion in giros or direccion == "t":
                    continue
                antes = _encadenar(entrada, True, LARGO_ANTES_M)
                despues = _encadenar(salida, False, LARGO_DESPUES_M)
                edges = [e.getID() for e in antes] + [entrada.getID(), salida.getID()] + [e.getID() for e in despues]
                giros[direccion] = {
                    "direccion": direccion,
                    "salida": salida.getID(),
                    "salida_nombre": nombres.get(_via_osm(salida.getID())),
                    "edges": edges,
                    "peatones": all(e.allows("pedestrian") for e in [entrada, salida]),
                }
        if giros:
            accesos.append({
                "edge": entrada.getID(),
                "nombre": entrada.getName() or nombres.get(_via_osm(entrada.getID())),
                "carriles": entrada.getLaneNumber(),
                "giros": list(giros.values()),
            })
    return accesos


def geometria_escena(run_dir: Path, nodo_id: str, nombres: dict[str, str]) -> dict[str, Any]:
    """Geometría completa de la escena para el visor (se envía una vez al abrir)."""
    zona = run_dir / "zona.net.xml"
    zona_tls = run_dir / "zona_tls.net.xml"
    red = _leer_red(zona_tls, nodo_id, nombres)
    if red["location"] is None:
        raise ValueError(f"La red {zona_tls} no tiene <location>.")
    a_lonlat, a_xy = _transformaciones(red["location"])

    # posición de cada luz: final del carril que controla (la línea de pare)
    fin_carril = {c["id"]: c["forma"][-1] for c in red["carriles"] if c["forma"]}
    for luz in red["luces"]:
        luz["posicion"] = fin_carril.get(luz.pop("desde_carril"))
    red["luces"] = [l for l in red["luces"] if l["posicion"]]

    nodo = next((c for c in red["cruces"] if c["id"] == nodo_id), None)
    if nodo is None:
        raise ValueError(f"El cruce '{nodo_id}' no está en la zona.")

    xs = [p[0] for c in red["carriles"] for p in c["forma"]]
    ys = [p[1] for c in red["carriles"] for p in c["forma"]]
    limites = [min(xs), min(ys), max(xs), max(ys)]
    w, s = a_lonlat(limites[0], limites[1])
    e, n = a_lonlat(limites[2], limites[3])

    nodos_z = [(c["x"], c["y"], c["z"]) for c in red["cruces"]]

    def z_suelo(x: float, y: float) -> float:
        return min(nodos_z, key=lambda p: (p[0] - x) ** 2 + (p[1] - y) ** 2)[2] if nodos_z else 0.0

    vias: dict[str, list[str]] = defaultdict(list)
    for eid, info in red["edges"].items():
        if info["nombre"]:
            vias[info["nombre"]].append(eid)
    centro_edge = {}
    for c in red["carriles"]:
        if not c["interno"] and c["forma"] and c["edge"] not in centro_edge:
            centro_edge[c["edge"]] = c["forma"][len(c["forma"]) // 2]

    nlon, nlat = a_lonlat(nodo["x"], nodo["y"])
    return {
        "nodo": {**nodo, "tipo_actual": tipo_nodo(zona, nodo_id), "lon": nlon, "lat": nlat},
        "limites": limites,
        "bbox_lonlat": [w, s, e, n],
        "carriles": red["carriles"],
        "cruces": red["cruces"],
        "luces": red["luces"],
        "edificios": edificios_zona((w, s, e, n), a_xy, z_suelo),
        "vias": sorted(
            (
                {"nombre": nombre, "edges": eids, "centro": centro_edge.get(eids[0])}
                for nombre, eids in vias.items() if centro_edge.get(eids[0])
            ),
            key=lambda v: v["nombre"],
        ),
        "accesos": rutas_por_acceso(zona, nodo_id, nombres),
    }
