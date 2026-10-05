"""
Catálogo de intersecciones semaforizadas de la red SUMO (fase A del módulo de semáforos).

Cada semáforo (`tlLogic`) de la red controla uno o más cruces. De los `<connection tl=...>`
salen los accesos que controla (edges de entrada) y qué movimiento corresponde a cada
letra del estado de sus fases. Los volúmenes por acceso se cuentan en el vehroute-output
de una corrida, así que dependen del escenario simulado.

Los programas son los que generó netconvert a partir de OSM, no los reales.
"""
import json
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .configuration import HORA_FIN, HORA_INI

HORAS_VENTANA = (HORA_FIN - HORA_INI) / 3600

# Clases de vía de OSM (type="highway.X" en la red) con nombre en español
CLASES_VIA = {
    "motorway": "autopista",
    "trunk": "troncal",
    "primary": "arterial principal",
    "secondary": "arterial secundaria",
    "tertiary": "colectora",
    "unclassified": "local",
    "residential": "local residencial",
    "living_street": "de prioridad peatonal",
    "service": "de servicio",
    "cycleway": "ciclorruta",
    "footway": "peatonal",
    "pedestrian": "peatonal",
    "path": "sendero",
    "steps": "escaleras",
}

# Letra del estado de un movimiento en una fase → color de la luz
_LUZ = {"G": "verde", "g": "verde", "y": "amarillo", "Y": "amarillo", "u": "amarillo",
        "r": "rojo", "R": "rojo", "s": "rojo", "o": "apagado", "O": "apagado"}
_PRIORIDAD_LUZ = ["verde", "amarillo", "rojo", "apagado"]


def clase_via(tipo: str | None) -> str:
    """'highway.primary_link' -> 'enlace de arterial principal'."""
    if not tipo:
        return "sin clase"
    base = tipo.split("|")[0].split(".")[-1]
    enlace = base.endswith("_link")
    nombre = CLASES_VIA.get(base.removesuffix("_link"), base)
    return f"enlace de {nombre}" if enlace else nombre


def luz_de(estado: str) -> str:
    """Color de una fase para un acceso: el de su movimiento más permisivo."""
    luces = {_LUZ.get(c, "rojo") for c in estado}
    return next(l for l in _PRIORIDAD_LUZ if l in luces) if luces else "apagado"


@dataclass
class Acceso:
    edge: str
    calle: str | None
    clase: str
    carriles: int
    velocidad_kmh: float
    movimientos: int                       # conexiones controladas desde este acceso
    volumen: int | None = None             # vehículos en la ventana simulada
    volumen_hora: float | None = None
    volumen_por_tipo: dict[str, int] | None = None


@dataclass
class Fase:
    duracion: float
    estado: str                            # una letra por movimiento (linkIndex)
    luces: dict[str, str]                  # edge de acceso -> verde | amarillo | rojo | apagado


@dataclass
class Semaforo:
    id: str
    tipo: str                              # static | actuated | ...
    programa: str
    offset: float
    ciclo: float
    fases: list[Fase]
    cruces: list[str]
    lon: float
    lat: float
    z: float
    accesos: list[Acceso]
    calles: list[str]
    movimientos: int
    nombre: str = ""
    enlaces: list[dict[str, Any]] = field(default_factory=list)   # linkIndex -> acceso y giro


# ------------------------------------------------------------------ lectura

def extraer_nombres_vias(osm_path: Path) -> dict[str, str]:
    """id de vía OSM -> nombre (o ref). La red se generó sin --output.street-names."""
    nombres: dict[str, str] = {}
    for _, elem in ET.iterparse(osm_path, events=("end",)):
        if elem.tag == "way":
            tags = {t.get("k"): t.get("v") for t in elem.findall("tag")}
            nombre = tags.get("name") or tags.get("ref")
            if nombre:
                nombres[elem.get("id")] = nombre
            elem.clear()
        elif elem.tag == "node":
            elem.clear()
    return nombres


def _via_osm(edge_id: str) -> str:
    """'-975491104#3' -> '975491104': netconvert nombra los edges con el id de la vía OSM."""
    return edge_id.lstrip("-").split("#")[0]


def _transformador(location: ET.Element):
    from pyproj import Transformer   # diferido: solo hace falta para el catálogo

    offx, offy = (float(v) for v in location.get("netOffset", "0,0").split(","))
    proj = location.get("projParameter")
    t = Transformer.from_crs(proj, "EPSG:4326", always_xy=True)
    return lambda x, y: t.transform(x - offx, y - offy)


def leer_semaforos(net_path: Path, nombres_vias: dict[str, str] | None = None) -> list[Semaforo]:
    """Recorre el .net.xml una vez y arma un Semaforo por cada tlLogic.

    `nombres_vias` (id de vía OSM -> nombre) completa los nombres que la red no trae.
    """
    nombres_vias = nombres_vias or {}
    a_lonlat = None
    edges: dict[str, dict[str, Any]] = {}
    nodos: dict[str, tuple[float, float, float]] = {}
    programas: dict[str, ET.Element] = {}
    conexiones: dict[str, list[tuple[int, str, str]]] = defaultdict(list)   # tl -> (linkIndex, from, dir)

    for _, elem in ET.iterparse(net_path, events=("end",)):
        tag = elem.tag
        if tag == "location":
            a_lonlat = _transformador(elem)
        elif tag == "edge":
            if elem.get("function") != "internal":
                carriles = elem.findall("lane")
                edge_id = elem.get("id")
                edges[edge_id] = {
                    "to": elem.get("to"),
                    "name": elem.get("name") or nombres_vias.get(_via_osm(edge_id)),
                    "type": elem.get("type"),
                    "carriles": len(carriles),
                    "velocidad": max((float(l.get("speed", 0)) for l in carriles), default=0.0),
                }
            elem.clear()
        elif tag == "junction":
            if elem.get("type") != "internal":
                nodos[elem.get("id")] = (float(elem.get("x")), float(elem.get("y")), float(elem.get("z", 0)))
            elem.clear()
        elif tag == "tlLogic":
            programas[elem.get("id")] = elem   # se conserva con sus <phase>
        elif tag == "connection":
            tl, desde = elem.get("tl"), elem.get("from")
            if tl and not desde.startswith(":"):
                conexiones[tl].append((int(elem.get("linkIndex")), desde, elem.get("dir", "")))
            elem.clear()

    if a_lonlat is None:
        raise ValueError(f"La red {net_path} no tiene <location>")

    semaforos = []
    for tl_id, prog in programas.items():
        enlaces = sorted(conexiones.get(tl_id, []))
        por_acceso = Counter(desde for _, desde, _ in enlaces)
        cruces = sorted({edges[d]["to"] for d in por_acceso if d in edges})
        puntos = [nodos[c] for c in cruces if c in nodos]
        if not puntos:
            continue   # semáforo sin cruces conocidos (no debería pasar)
        x = sum(p[0] for p in puntos) / len(puntos)
        y = sum(p[1] for p in puntos) / len(puntos)
        lon, lat = a_lonlat(x, y)

        accesos = [
            Acceso(
                edge=d,
                calle=edges[d]["name"],
                clase=clase_via(edges[d]["type"]),
                carriles=edges[d]["carriles"],
                velocidad_kmh=round(edges[d]["velocidad"] * 3.6),
                movimientos=n,
            )
            for d, n in por_acceso.items() if d in edges
        ]
        fases = []
        for ph in prog.findall("phase"):
            estado = ph.get("state", "")
            luces = {
                a.edge: luz_de("".join(estado[i] for i, desde, _ in enlaces if desde == a.edge and i < len(estado)))
                for a in accesos
            }
            fases.append(Fase(float(ph.get("duration", 0)), estado, luces))

        calles = list(dict.fromkeys(a.calle for a in sorted(accesos, key=lambda a: -a.carriles) if a.calle))
        semaforos.append(Semaforo(
            id=tl_id,
            tipo=prog.get("type", "static"),
            programa=prog.get("programID", "0"),
            offset=float(prog.get("offset", 0)),
            ciclo=sum(f.duracion for f in fases),
            fases=fases,
            cruces=cruces,
            lon=round(lon, 6),
            lat=round(lat, 6),
            z=round(sum(p[2] for p in puntos) / len(puntos), 1),
            accesos=accesos,
            calles=calles,
            movimientos=len(enlaces),
            nombre=" × ".join(calles[:2]) if calles else f"Intersección {tl_id[:18]}",
            enlaces=[{"indice": i, "acceso": d, "giro": g} for i, d, g in enlaces],
        ))
    return semaforos


def volumenes_por_edge(vehroute_path: Path) -> dict[str, Counter]:
    """Vehículos que pasaron por cada edge, por tipo, según el vehroute-output.

    Con rerouting, un vehículo trae un <routeDistribution>: la ruta que de verdad
    recorrió es la última.
    """
    volumenes: dict[str, Counter] = defaultdict(Counter)
    for _, elem in ET.iterparse(vehroute_path, events=("end",)):
        if elem.tag != "vehicle":
            continue
        rutas = elem.findall("route") or elem.findall("routeDistribution/route")
        if rutas:
            tipo = elem.get("type", "desconocido")
            for edge in set(rutas[-1].get("edges", "").split()):
                volumenes[edge][tipo] += 1
        elem.clear()
    return volumenes


# ---------------------------------------------------------------- cachés

def _firma(path: Path) -> list[float]:
    st = path.stat()
    return [st.st_mtime, st.st_size]


def catalogo(net_path: Path, cache_path: Path, nombres_path: Path | None = None) -> list[Semaforo]:
    """leer_semaforos con caché en disco (se invalida si cambia la red o los nombres)."""
    hay_nombres = nombres_path is not None and nombres_path.is_file()
    firma = _firma(net_path) + (_firma(nombres_path) if hay_nombres else [])
    if cache_path.is_file():
        try:
            datos = json.loads(cache_path.read_text(encoding="utf-8"))
            if datos.get("firma") == firma:
                return [_semaforo_desde_dict(s) for s in datos["semaforos"]]
        except (ValueError, KeyError, TypeError):
            pass
    nombres = json.loads(nombres_path.read_text(encoding="utf-8")) if hay_nombres else None
    semaforos = leer_semaforos(net_path, nombres)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(
        json.dumps({"firma": firma, "semaforos": [asdict(s) for s in semaforos]}, ensure_ascii=False),
        encoding="utf-8",
    )
    return semaforos


def volumenes(vehroute_path: Path, cache_path: Path) -> dict[str, Counter]:
    """volumenes_por_edge con caché junto a la corrida."""
    firma = _firma(vehroute_path)
    if cache_path.is_file():
        try:
            datos = json.loads(cache_path.read_text(encoding="utf-8"))
            if datos.get("firma") == firma:
                return {e: Counter(t) for e, t in datos["volumenes"].items()}
        except (ValueError, KeyError, TypeError):
            pass
    vols = volumenes_por_edge(vehroute_path)
    cache_path.write_text(json.dumps({"firma": firma, "volumenes": vols}), encoding="utf-8")
    return vols


def _semaforo_desde_dict(d: dict[str, Any]) -> Semaforo:
    return Semaforo(**{
        **d,
        "fases": [Fase(**f) for f in d["fases"]],
        "accesos": [Acceso(**a) for a in d["accesos"]],
    })


# ------------------------------------------------------------- consultas

def con_volumenes(semaforo: Semaforo, vols: dict[str, Counter] | None) -> Semaforo:
    """Copia del semáforo con el volumen simulado de cada acceso."""
    accesos = []
    for a in semaforo.accesos:
        por_tipo = vols.get(a.edge, Counter()) if vols is not None else None
        total = sum(por_tipo.values()) if por_tipo is not None else None
        accesos.append(Acceso(**{
            **asdict(a),
            "volumen": total,
            "volumen_hora": round(total / HORAS_VENTANA, 1) if total is not None else None,
            "volumen_por_tipo": dict(por_tipo) if por_tipo is not None else None,
        }))
    return Semaforo(**{**asdict(semaforo), "fases": semaforo.fases, "accesos": accesos})


def a_feature(semaforo: Semaforo) -> dict[str, Any]:
    """Punto GeoJSON con el resumen que necesita el mapa."""
    volumenes_acceso = [a.volumen for a in semaforo.accesos if a.volumen is not None]
    return {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [semaforo.lon, semaforo.lat]},
        "properties": {
            "id": semaforo.id,
            "nombre": semaforo.nombre,
            "accesos": len(semaforo.accesos),
            "ciclo_s": semaforo.ciclo,
            "fases": len(semaforo.fases),
            "volumen": sum(volumenes_acceso) if volumenes_acceso else None,
        },
    }


if __name__ == "__main__":
    # Genera nombres_vias.json del escenario a partir del OSM con que se construyó la red:
    #   python -m etl.sumo.intersecciones ../../data/processed/usaquen.osm.xml
    import sys

    from .configuration import ScenarioPaths

    destino = ScenarioPaths.from_name().nombres_vias
    nombres = extraer_nombres_vias(Path(sys.argv[1]))
    destino.write_text(json.dumps(nombres, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    print(f"{len(nombres)} vías con nombre -> {destino}")
