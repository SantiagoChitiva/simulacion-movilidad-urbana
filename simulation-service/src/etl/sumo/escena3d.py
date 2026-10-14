"""
Geometría de la escena del simulador 3D comparativo.

Todo va en coordenadas de la red de SUMO (metros, x al este, y al norte, z = altura del
modelo 3D de la red), las mismas que reporta TraCI para los actores, para que el visor
no tenga que proyectar nada en cada frame. Para el minimapa se incluye el centro y el
bbox en lon/lat.

El cruce estudiado puede ser varios nodos de SUMO (las dos calzadas de una avenida, ver
priorizacion.py): los accesos, las líneas de pare y los semáforos son los del grupo.

Incluye:
- calzadas: carriles de vehículos (sin los internos de los cruces, que cubre el polígono
  del cruce) con su índice y si la vía tiene sentido contrario (para la línea amarilla),
- ciclorrutas y senderos peatonales (footway, etc.),
- polígonos de los cruces (junctions) con la z de cada vértice,
- bocas del cruce estudiado: el final de cada carril que llega y el inicio de cada carril
  que sale (líneas de pare y cebras),
- semáforo propuesto: un poste por acceso, con los linkIndex de cada giro,
- terreno: grilla de alturas interpoladas de la red, para que suelo y edificios sigan la
  pendiente (Usaquén sube hacia los cerros),
- edificios de Microsoft Building Footprints (data/processed/edificios_ms.geojson)
  recortados a la zona; sin altura conocida se les asigna una de 6 a 21 m,
- las vías con nombre (para elegir qué mirar) y, por cada acceso al cruce, las rutas
  posibles según el giro (para inyectar el actor seguido).
"""
import json
import math
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
AREA_MIN_EDIFICIO_M2 = 12
PASO_TERRENO_M = 10
MARGEN_TERRENO_M = 120
GIRO_RECTO_GRADOS = 35
GIRO_EN_U_GRADOS = 145
_TIPOS_PEATONALES = {"footway", "pedestrian", "path", "steps", "track", "bridleway"}


def _puntos(shape: str) -> list[list[float]]:
    puntos = []
    for par in shape.split():
        xyz = [float(c) for c in par.split(",")]
        if len(xyz) == 2:
            xyz.append(0.0)
        puntos.append([round(xyz[0], 2), round(xyz[1], 2), round(xyz[2], 2)])
    return puntos


def _rumbo(p, q) -> float:
    """Rumbo de p hacia q en grados (0 = norte, sentido horario)."""
    return math.degrees(math.atan2(q[0] - p[0], q[1] - p[1])) % 360


def giro_por_rumbos(rumbo_entrada: float, rumbo_salida: float) -> str:
    """'s', 'r', 'l' o 't' según cuánto gira el recorrido (positivo = horario = derecha)."""
    d = (rumbo_salida - rumbo_entrada + 540) % 360 - 180
    if abs(d) < GIRO_RECTO_GRADOS:
        return "s"
    if abs(d) > GIRO_EN_U_GRADOS:
        return "t"
    return "r" if d > 0 else "l"


# ─────────────────────────────────────────────────────────── edificios

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


def _area(puntos: list[tuple[float, float]]) -> float:
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(puntos, puntos[1:] + puntos[:1]))) / 2


def edificios_zona(
    bbox_lonlat: tuple[float, float, float, float],
    a_xy,
    z_suelo,
    path: Path = EDIFICIOS_GEOJSON,
) -> list[dict]:
    """Edificios cuyo centro cae en el bbox (w, s, e, n), en coordenadas de la red.

    `z_suelo(x, y)` da la altura del terreno; el edificio se apoya en la más baja de su
    huella para no quedar flotando en una pendiente.
    """
    w, s, e, n = bbox_lonlat
    salida = []
    for anillo, altura, (cx, cy) in _edificios_lonlat(path):
        if not (w <= cx <= e and s <= cy <= n):
            continue
        puntos = [a_xy(lon, lat) for lon, lat in anillo]
        if puntos[0] == puntos[-1]:
            puntos = puntos[:-1]
        if len(puntos) < 3 or _area(puntos) < AREA_MIN_EDIFICIO_M2:
            continue
        salida.append({
            "contorno": [[round(x, 2), round(y, 2)] for x, y in puntos],
            "altura": altura,
            "z": round(min(z_suelo(x, y) for x, y in puntos), 2),
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


# ─────────────────────────────────────────────────────────── terreno

def terreno(muestras: list[tuple[float, float, float]], limites: list[float], paso: float = PASO_TERRENO_M) -> dict:
    """Grilla de alturas por distancia inversa (IDW) a partir de puntos de la red."""
    x0, y0, x1, y1 = limites
    x0, y0 = x0 - MARGEN_TERRENO_M, y0 - MARGEN_TERRENO_M
    nx = int((x1 + MARGEN_TERRENO_M - x0) // paso) + 2
    ny = int((y1 + MARGEN_TERRENO_M - y0) // paso) + 2
    celda = 40.0
    cubetas: dict[tuple[int, int], list] = defaultdict(list)
    for x, y, z in muestras:
        cubetas[(int(x // celda), int(y // celda))].append((x, y, z))
    z_media = sum(m[2] for m in muestras) / len(muestras) if muestras else 0.0
    alturas = []
    for j in range(ny):
        y = y0 + j * paso
        for i in range(nx):
            x = x0 + i * paso
            cx, cy = int(x // celda), int(y // celda)
            cercanos = []
            for r in (1, 2, 4):
                cercanos = [
                    m for a in range(cx - r, cx + r + 1) for b in range(cy - r, cy + r + 1) for m in cubetas.get((a, b), ())
                ]
                if len(cercanos) >= 4:
                    break
            if not cercanos:
                alturas.append(round(z_media, 2))
                continue
            num = den = 0.0
            for mx, my, mz in cercanos:
                d2 = (mx - x) ** 2 + (my - y) ** 2 + 1.0
                num += mz / d2
                den += 1 / d2
            alturas.append(round(num / den, 2))
    return {"x0": round(x0, 2), "y0": round(y0, 2), "paso": paso, "nx": nx, "ny": ny, "z": alturas}


def altura_terreno(t: dict, x: float, y: float) -> float:
    """Interpolación bilineal en la grilla de `terreno`."""
    fx = min(max((x - t["x0"]) / t["paso"], 0), t["nx"] - 1.001)
    fy = min(max((y - t["y0"]) / t["paso"], 0), t["ny"] - 1.001)
    i, j = int(fx), int(fy)
    dx, dy = fx - i, fy - j
    z = t["z"]
    nx = t["nx"]
    z00, z10 = z[j * nx + i], z[j * nx + i + 1]
    z01, z11 = z[(j + 1) * nx + i], z[(j + 1) * nx + i + 1]
    return (z00 * (1 - dx) + z10 * dx) * (1 - dy) + (z01 * (1 - dx) + z11 * dx) * dy


# ─────────────────────────────────────────────────────────── lectura de la red

def _leer_red(net: Path, tl_id: str | None, nombres: dict[str, str]) -> dict[str, Any]:
    location = None
    calzadas, ciclorrutas, senderos, cruces = [], [], [], []
    conexiones_tl = []
    edges: dict[str, dict] = {}
    for _, elem in ET.iterparse(net, events=("end",)):
        tag = elem.tag
        if tag == "location":
            location = elem
            continue
        if tag == "edge":
            funcion = elem.get("function")
            if funcion in ("internal", "crossing", "walkingarea"):
                elem.clear()
                continue
            eid = elem.get("id")
            tipo = (elem.get("type") or "").split("|")[0].split(".")[-1]
            carriles = elem.findall("lane")
            edges[eid] = {
                "nombre": elem.get("name") or nombres.get(_via_osm(eid)),
                "tipo": tipo, "desde": elem.get("from"), "hasta": elem.get("to"),
                "prioridad": int(elem.get("priority", 0)), "carriles": len(carriles),
            }
            peatonal = tipo in _TIPOS_PEATONALES
            for lane in carriles:
                forma = _puntos(lane.get("shape", ""))
                if len(forma) < 2:
                    continue
                allow = lane.get("allow", "")
                item = {
                    "id": lane.get("id"), "edge": eid, "indice": int(lane.get("index", 0)),
                    "n_carriles": len(carriles), "ancho": float(lane.get("width", 3.2)), "forma": forma,
                }
                if peatonal or allow == "pedestrian":
                    senderos.append(item)
                elif allow == "bicycle" or tipo == "cycleway":
                    ciclorrutas.append(item)
                else:
                    item["solo_bus"] = allow in ("bus", "psv", "bus psv")
                    calzadas.append(item)
            elem.clear()
        elif tag == "junction":
            if elem.get("type") not in ("internal",) and elem.get("shape"):
                cruces.append({
                    "id": elem.get("id"),
                    "tipo": elem.get("type"),
                    "x": float(elem.get("x")), "y": float(elem.get("y")), "z": float(elem.get("z", 0)),
                    "forma": _puntos(elem.get("shape", "")),
                })
            elem.clear()
        elif tag == "connection":
            if tl_id is not None and elem.get("tl") == tl_id:
                conexiones_tl.append({
                    "enlace": int(elem.get("linkIndex", 0)), "desde": elem.get("from"),
                    "carril": int(elem.get("fromLane", 0)), "direccion": elem.get("dir"),
                })
            elem.clear()
    # sentido contrario: hay un edge que va entre los mismos nodos al revés
    pares = {(e["desde"], e["hasta"]) for e in edges.values()}
    for c in calzadas:
        e = edges[c["edge"]]
        c["opuesto"] = (e["hasta"], e["desde"]) in pares
    return {
        "location": location, "calzadas": calzadas, "ciclorrutas": ciclorrutas, "senderos": senderos,
        "cruces": cruces, "conexiones_tl": conexiones_tl, "edges": edges,
    }


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


def _rumbo_final(edge) -> float:
    forma = edge.getShape()
    return _rumbo(forma[-2], forma[-1])


def _rumbo_inicial(edge) -> float:
    forma = edge.getShape()
    return _rumbo(forma[0], forma[1])


def rutas_por_acceso(net_path: Path, nodos: list[str] | str, nombres: dict[str, str]) -> list[dict]:
    """Por cada edge que llega al cruce (grupo de nodos): las rutas que lo atraviesan, una por giro."""
    import sumolib

    net = sumolib.net.readNet(str(net_path), withInternal=False)
    ids = [nodos] if isinstance(nodos, str) else list(nodos)
    conjunto = {n for n in ids if net.hasNode(n)}
    if not conjunto:
        return []
    accesos = []
    prioridades = []
    for nid in ids:
        if nid not in conjunto:
            continue
        for entrada in net.getNode(nid).getIncoming():
            if entrada.getFunction() == "internal" or entrada.getFromNode().getID() in conjunto:
                continue
            # recorrer el cruce (puede tener edges entre sus nodos) hasta salir de él
            salidas: dict[str, tuple] = {}
            pendientes = [(entrada, [])]
            while pendientes:
                actual, camino = pendientes.pop()
                for siguiente in actual.getOutgoing():
                    if siguiente.getFunction() == "internal" or siguiente in camino or len(camino) > 4:
                        continue
                    if siguiente.getToNode().getID() in conjunto:
                        pendientes.append((siguiente, camino + [siguiente]))
                    elif siguiente.getID() not in salidas:
                        salidas[siguiente.getID()] = (siguiente, camino)
            giros: dict[str, dict] = {}
            for salida, camino in sorted(salidas.values(), key=lambda s: -s[0].getLaneNumber()):
                direccion = giro_por_rumbos(_rumbo_final(entrada), _rumbo_inicial(salida))
                if direccion == "t" or direccion in giros:
                    continue
                antes = _encadenar(entrada, True, LARGO_ANTES_M)
                despues = _encadenar(salida, False, LARGO_DESPUES_M)
                edges = [e.getID() for e in antes] + [entrada.getID()] + [e.getID() for e in camino] \
                    + [salida.getID()] + [e.getID() for e in despues]
                giros[direccion] = {
                    "direccion": direccion,
                    "salida": salida.getID(),
                    "salida_nombre": salida.getName() or nombres.get(_via_osm(salida.getID())),
                    "edges": edges,
                    "peatones": all(e.allows("pedestrian") for e in [entrada, salida]),
                }
            if giros:
                prioridades.append(entrada.getPriority())
                accesos.append({
                    "edge": entrada.getID(),
                    "nombre": entrada.getName() or nombres.get(_via_osm(entrada.getID())),
                    "carriles": entrada.getLaneNumber(),
                    "prioridad": entrada.getPriority(),
                    "giros": [giros[d] for d in ("s", "l", "r") if d in giros],
                })
    tope = max(prioridades, default=0)
    for a in accesos:
        a["lateral"] = a["prioridad"] < tope   # la vía que cede (sin semáforo: PARE)
    return accesos


def _bocas(calzadas: list[dict], edges: dict[str, dict], conjunto: set[str]) -> list[dict]:
    """Final de cada carril que entra al cruce e inicio de cada carril que sale (pare y cebras)."""
    bocas = []
    for c in calzadas:
        e = edges[c["edge"]]
        entra = e["hasta"] in conjunto and e["desde"] not in conjunto
        sale = e["desde"] in conjunto and e["hasta"] not in conjunto
        if not (entra or sale):
            continue
        f = c["forma"]
        p, q = (f[-1], f[-2]) if entra else (f[0], f[1])
        bocas.append({
            "edge": c["edge"], "indice": c["indice"], "entra": entra, "punto": p,
            # rumbo de marcha en la boca
            "rumbo": round(_rumbo(q, p) if entra else _rumbo(p, q), 1),
            "ancho": c["ancho"],
        })
    return bocas


def _postes_semaforo(conexiones_tl: list[dict], calzadas: list[dict], accesos: list[dict]) -> list[dict]:
    """Un poste por acceso externo: en el borde derecho de su carril 0, en la línea de pare."""
    por_carril = {c["id"]: c for c in calzadas}
    externos = {a["edge"] for a in accesos}
    por_acceso: dict[str, dict] = {}
    for con in conexiones_tl:
        if con["desde"] not in externos:
            continue
        poste = por_acceso.setdefault(con["desde"], {"edge": con["desde"], "enlaces": defaultdict(list)})
        poste["enlaces"][con["direccion"] or "s"].append(con["enlace"])
    postes = []
    for edge, poste in por_acceso.items():
        derecho = por_carril.get(f"{edge}_0")
        if derecho is None:
            continue
        carriles = [c for c in calzadas if c["edge"] == edge]
        f = derecho["forma"]
        postes.append({
            "edge": edge,
            "punto": f[-1],
            "rumbo": round(_rumbo(f[-2], f[-1]), 1),
            "ancho_carril0": derecho["ancho"],
            "ancho_calzada": round(sum(c["ancho"] for c in carriles), 2),
            "enlaces": {d: sorted(v) for d, v in poste["enlaces"].items()},
        })
    return postes


def geometria_escena(
    run_dir: Path, nodo_id: str, nombres: dict[str, str],
    nodos: list[str] | None = None, tl_id: str | None = None,
) -> dict[str, Any]:
    """Geometría completa de la escena para el visor (se envía una vez al abrir)."""
    zona = run_dir / "zona.net.xml"
    zona_tls = run_dir / "zona_tls.net.xml"
    tl_id = tl_id or nodo_id
    red = _leer_red(zona_tls, tl_id, nombres)
    if red["location"] is None:
        raise ValueError(f"La red {zona_tls} no tiene <location>.")
    a_lonlat, a_xy = _transformaciones(red["location"])

    ids = list(dict.fromkeys([nodo_id, *(nodos or [])]))
    por_id = {c["id"]: c for c in red["cruces"]}
    miembros = [por_id[n] for n in ids if n in por_id]
    if not miembros:
        raise ValueError(f"El cruce '{nodo_id}' no está en la zona.")
    centro = {
        "x": round(sum(c["x"] for c in miembros) / len(miembros), 2),
        "y": round(sum(c["y"] for c in miembros) / len(miembros), 2),
        "z": round(sum(c["z"] for c in miembros) / len(miembros), 2),
    }
    conjunto = {c["id"] for c in miembros}

    todos = red["calzadas"] + red["ciclorrutas"] + red["senderos"]
    xs = [p[0] for c in todos for p in c["forma"]]
    ys = [p[1] for c in todos for p in c["forma"]]
    limites = [min(xs), min(ys), max(xs), max(ys)]
    w, s = a_lonlat(limites[0], limites[1])
    e, n = a_lonlat(limites[2], limites[3])

    muestras = [(p[0], p[1], p[2]) for c in red["calzadas"] for p in c["forma"]]
    muestras += [(c["x"], c["y"], c["z"]) for c in red["cruces"]]
    malla = terreno(muestras, limites)

    vias: dict[str, list[str]] = defaultdict(list)
    for eid, info in red["edges"].items():
        if info["nombre"]:
            vias[info["nombre"]].append(eid)
    centro_edge = {}
    for c in todos:
        if c["forma"] and c["edge"] not in centro_edge:
            centro_edge[c["edge"]] = c["forma"][len(c["forma"]) // 2]

    accesos = rutas_por_acceso(zona, ids, nombres)
    nlon, nlat = a_lonlat(centro["x"], centro["y"])
    return {
        "nodo": {"id": nodo_id, **centro, "tipo_actual": tipo_nodo(zona, nodo_id), "lon": nlon, "lat": nlat},
        "nodos": [c["id"] for c in miembros],
        "tl_id": tl_id,
        "limites": limites,
        "bbox_lonlat": [w, s, e, n],
        "calzadas": red["calzadas"],
        "ciclorrutas": red["ciclorrutas"],
        "senderos": red["senderos"],
        "cruces": red["cruces"],
        "bocas": _bocas(red["calzadas"], red["edges"], conjunto),
        "postes_semaforo": _postes_semaforo(red["conexiones_tl"], red["calzadas"], accesos),
        "terreno": malla,
        "edificios": edificios_zona((w, s, e, n), a_xy, lambda x, y: altura_terreno(malla, x, y)),
        "vias": sorted(
            (
                {"nombre": nombre, "edges": eids, "centro": centro_edge.get(eids[0])}
                for nombre, eids in vias.items() if centro_edge.get(eids[0])
            ),
            key=lambda v: v["nombre"],
        ),
        "accesos": accesos,
    }
