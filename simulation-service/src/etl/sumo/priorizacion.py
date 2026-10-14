"""
Priorización de cruces sin semáforo para estudiar un semáforo nuevo.

Sigue la lógica del proyecto Semáforos de Barranquilla (github.com/Victorpay1/
semaforos-barranquilla, pipeline/src/priority.ts y config.ts), adaptada a la red de SUMO
y sin su modelo de lenguaje (Jev):

1. Cruces, no nodos. Los nodos de SUMO a menos de 20 m se agrupan (span máximo 45 m) y
   los grupos del mismo par de calles a menos de 150 m (las dos calzadas de una avenida)
   se fusionan (span máximo 200 m). Un cruce necesita dos calles distintas que se corten
   a más de 35°: así salen los nodos a mitad de cuadra y las entradas a predios.
2. Reglas duras (R), todas obligatorias:
   - participa una vía colectora (tertiary) o de mayor jerarquía, sin autopistas ni
     troncales (en Usaquén, la Autopista Norte con TransMilenio, de acceso controlado);
   - la otra vía es al menos local residencial (no de servicio ni peatonal);
   - es a nivel: sin rampas (_link) ni glorietas a menos de 40 m;
   - hay un conflicto real: desde la vía secundaria se cruza de frente o se gira a la
     izquierda (en troncales, solo cruzar de frente), no solo entrar y salir a la derecha;
   - no hay semáforo a menos de 80 m ("misma cuadra").
3. Evidencia (E), calibrada contra los cruces que ya tienen semáforo en la red (el
   "backtest" de Barranquilla: lo que la ciudad ya decidió semaforizar):
   - siniestros a menos de 30 m: >= p75 de los semaforizados (mínimo 3), o >= mediana con
     un generador cerca;
   - tramo de la vía principal sin semáforo >= 600 m (a lo largo de la vía);
   - volumen simulado que entra al cruce >= p75 de los semaforizados (si hay corrida).
   Generadores: colegios, jardines, universidades, hospitales y clínicas a menos de 200 m.
4. Niveles: prioritario (R y 2+ evidencias), recomendado (R y 1), en observación (R y
   siniestros >= mediana o un generador). El resto no se devuelve. Dos cruces del mismo
   nivel a menos de 120 m se estudian juntos: el peor baja un nivel.
5. Puntaje: piso del nivel (75 / 50 / 25) + hasta 25 puntos (siniestros 35 %, volumen
   30 %, generadores 15 %, tramo 10 %, jerarquía 10 %).

El análisis de la red (lo que no depende de la corrida) se guarda en caché en disco.
"""
import heapq
import json
import math
import xml.etree.ElementTree as ET
from bisect import bisect_right
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .configuration import POIS_GEOJSON, SINIESTROS_GEOJSON
from .evidencia import leer_puntos
from .intersecciones import _transformador, _via_osm

VERSION_ANALISIS = 2

# Jerarquía (mayor a menor), como CLASS_RANK de Barranquilla, más 'service'
JERARQUIA = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
             "residential", "living_street", "service"]
RANGO = {clase: i for i, clase in enumerate(JERARQUIA)}
RANGO_COLECTORA = RANGO["tertiary"]
RANGO_LOCAL = RANGO["residential"]

RADIO_FUSION_M = 20
SPAN_GRUPO_M = 45
RADIO_GEMELOS_M = 150
SPAN_CRUCE_M = 200
ANGULO_CRUCE_GRADOS = 35
RADIO_DESNIVEL_M = 40
RADIO_MISMA_CUADRA_M = 80
RADIO_SINIESTRO_M = 30
RADIO_GENERADOR_M = 200
TRAMO_LARGO_M = 600
TRAMO_TOPE_M = 3000
RADIO_NMS_M = 120
MIN_SINIESTROS = 3

PISO = {"prioritario": 75.0, "recomendado": 50.0, "observacion": 25.0}
_BAJA = {"prioritario": "recomendado", "recomendado": "observacion", "observacion": None}
_TIPOS_SEMAFORO = {"traffic_light", "traffic_light_unregulated", "traffic_light_right_on_red"}
_PEATONES = {"peaton", "transporte_publico"}


def clase_base(tipo: str | None) -> tuple[str | None, bool]:
    """'highway.primary_link' -> ('primary', True)."""
    if not tipo:
        return None, False
    base = tipo.split("|")[0].split(".")[-1]
    return base.removesuffix("_link"), base.endswith("_link")


# ─────────────────────────────────────────────────────────── geometría

def _rumbo(p: tuple[float, float], q: tuple[float, float]) -> float:
    """Rumbo de p hacia q en grados (0 = norte, sentido horario)."""
    return math.degrees(math.atan2(q[0] - p[0], q[1] - p[1])) % 360


def _diferencia_ejes(a: float, b: float) -> float:
    """Ángulo entre dos ejes (sin sentido), en [0, 90]."""
    d = abs(a - b) % 180
    return min(d, 180 - d)


def _percentil(valores: list[float], p: float) -> float:
    if not valores:
        return 0.0
    orden = sorted(valores)
    k = (len(orden) - 1) * p / 100
    i = int(k)
    j = min(i + 1, len(orden) - 1)
    return orden[i] + (orden[j] - orden[i]) * (k - i)


def _rango_percentil(valor: float, referencia: list[float]) -> float:
    """Fracción de la referencia por debajo o igual a `valor` (0-1)."""
    if not referencia:
        return 0.0
    orden = sorted(referencia)
    return bisect_right(orden, valor) / len(orden)


class _Grilla:
    """Índice espacial simple: celdas cuadradas de `celda` metros."""

    def __init__(self, celda: float):
        self.celda = celda
        self.celdas: dict[tuple[int, int], list] = defaultdict(list)

    def agregar(self, x: float, y: float, item) -> None:
        self.celdas[(int(x // self.celda), int(y // self.celda))].append((x, y, item))

    def cerca(self, x: float, y: float, radio: float):
        r = int(radio // self.celda) + 1
        cx, cy = int(x // self.celda), int(y // self.celda)
        for i in range(cx - r, cx + r + 1):
            for j in range(cy - r, cy + r + 1):
                for px, py, item in self.celdas.get((i, j), ()):
                    d = math.hypot(px - x, py - y)
                    if d <= radio:
                        yield d, item


# ─────────────────────────────────────────────────────────── lectura de la red

@dataclass
class _Edge:
    id: str
    desde: str
    hasta: str
    calle: str
    nombre: str | None
    rango: int
    enlace: bool
    carriles: int
    largo: float
    rumbo_salida: float     # en `desde`, alejándose
    rumbo_llegada: float    # en `hasta`, alejándose del nodo (sentido contrario al de marcha)


def _leer_red(net_path: Path, nombres: dict[str, str]) -> dict[str, Any]:
    location = None
    edges: dict[str, _Edge] = {}
    nodos: dict[str, tuple[float, float, str]] = {}
    conexiones: list[tuple[str, str, str]] = []
    glorietas: set[str] = set()
    for _, elem in ET.iterparse(net_path, events=("end",)):
        tag = elem.tag
        if tag == "location":
            location = elem
            continue
        if tag == "edge":
            if elem.get("function") not in ("internal", "crossing", "walkingarea"):
                base, enlace = clase_base(elem.get("type"))
                carriles = elem.findall("lane")
                if base in RANGO and carriles:
                    puntos = [tuple(map(float, p.split(",")[:2])) for p in carriles[0].get("shape", "").split()]
                    # un edge de solo buses (TransMilenio) no es una calle que se cruce
                    solo_bus = all(l.get("allow", "") in ("bus", "psv", "bus psv") for l in carriles)
                    if len(puntos) >= 2 and not solo_bus:
                        eid = elem.get("id")
                        nombre = elem.get("name") or nombres.get(_via_osm(eid))
                        edges[eid] = _Edge(
                            id=eid, desde=elem.get("from"), hasta=elem.get("to"),
                            calle=(nombre or f"osm:{_via_osm(eid)}").strip().upper(),
                            nombre=nombre, rango=RANGO[base], enlace=enlace, carriles=len(carriles),
                            largo=float(carriles[0].get("length", 0)),
                            rumbo_salida=_rumbo(puntos[0], puntos[1]),
                            rumbo_llegada=_rumbo(puntos[-1], puntos[-2]),
                        )
            elem.clear()
        elif tag == "junction":
            tipo = elem.get("type")
            if tipo not in ("internal", "dead_end"):
                nodos[elem.get("id")] = (float(elem.get("x")), float(elem.get("y")), tipo or "")
            elem.clear()
        elif tag == "connection":
            desde = elem.get("from", "")
            if not desde.startswith(":"):
                conexiones.append((desde, elem.get("to", ""), elem.get("dir", "")))
            elem.clear()
        elif tag == "roundabout":
            glorietas.update(elem.get("nodes", "").split())
            elem.clear()
    if location is None:
        raise ValueError(f"La red {net_path} no tiene <location>")
    return {"location": location, "edges": edges, "nodos": nodos, "conexiones": conexiones, "glorietas": glorietas}


# ─────────────────────────────────────────────────────────── agrupación

def _agrupar(nodos: dict[str, tuple[float, float, str]], ids: list[str]) -> list[list[str]]:
    """Grupos de nodos a menos de RADIO_FUSION_M, sin pasar de SPAN_GRUPO_M desde la semilla."""
    grilla = _Grilla(RADIO_FUSION_M)
    for nid in ids:
        x, y, _ = nodos[nid]
        grilla.agregar(x, y, nid)
    asignado: set[str] = set()
    grupos = []
    for semilla in ids:
        if semilla in asignado:
            continue
        sx, sy, _ = nodos[semilla]
        grupo, pendientes = [semilla], [semilla]
        asignado.add(semilla)
        while pendientes:
            x, y, _ = nodos[pendientes.pop()]
            for _, vecino in grilla.cerca(x, y, RADIO_FUSION_M):
                if vecino in asignado:
                    continue
                vx, vy, _ = nodos[vecino]
                if math.hypot(vx - sx, vy - sy) <= SPAN_GRUPO_M:
                    asignado.add(vecino)
                    grupo.append(vecino)
                    pendientes.append(vecino)
        grupos.append(grupo)
    return grupos


@dataclass
class _Cruce:
    nodos: list[str]
    x: float
    y: float
    semaforizado: bool
    entradas: list[str] = field(default_factory=list)   # edges que entran desde fuera
    patas: list[_Edge] = field(default_factory=list)    # edges que tocan el cruce desde fuera
    principal: str | None = None
    secundaria: str | None = None

    def centro(self, nodos) -> tuple[float, float]:
        xs = [nodos[n][0] for n in self.nodos]
        ys = [nodos[n][1] for n in self.nodos]
        return sum(xs) / len(xs), sum(ys) / len(ys)


def _armar_cruce(miembros: list[str], red: dict, por_nodo: dict[str, list[_Edge]]) -> _Cruce:
    nodos = red["nodos"]
    conjunto = set(miembros)
    patas = []
    vistos = set()
    for n in miembros:
        for e in por_nodo.get(n, ()):
            if e.id in vistos or (e.desde in conjunto and e.hasta in conjunto):
                continue
            vistos.add(e.id)
            patas.append(e)
    cruce = _Cruce(
        nodos=list(miembros), x=0, y=0,
        semaforizado=any(nodos[n][2] in _TIPOS_SEMAFORO for n in miembros),
        entradas=[e.id for e in patas if e.hasta in conjunto],
        patas=patas,
    )
    cruce.x, cruce.y = cruce.centro(nodos)
    return cruce


def _rumbo_pata(e: _Edge, conjunto: set[str]) -> float:
    return e.rumbo_llegada if e.hasta in conjunto else e.rumbo_salida


def _calles(cruce: _Cruce) -> tuple[str | None, str | None]:
    """(principal, secundaria): la de mayor jerarquía y la mejor que la corta a > 35°."""
    conjunto = set(cruce.nodos)
    por_calle: dict[str, list[_Edge]] = defaultdict(list)
    for e in cruce.patas:
        por_calle[e.calle].append(e)
    if len(por_calle) < 2:
        return None, None
    orden = sorted(por_calle, key=lambda c: (min(e.rango for e in por_calle[c]), -max(e.carriles for e in por_calle[c])))
    principal = orden[0]
    ejes_p = [_rumbo_pata(e, conjunto) for e in por_calle[principal]]
    for calle in orden[1:]:
        ejes = [_rumbo_pata(e, conjunto) for e in por_calle[calle]]
        if any(_diferencia_ejes(a, b) > ANGULO_CRUCE_GRADOS for a in ejes for b in ejes_p):
            return principal, calle
    return principal, None


def _fusionar_gemelos(cruces: list[_Cruce], red: dict, por_nodo) -> list[_Cruce]:
    """Une los cruces del mismo par de calles a menos de RADIO_GEMELOS_M (doble calzada)."""
    nodos = red["nodos"]
    por_par: dict[frozenset, list[int]] = defaultdict(list)
    for i, c in enumerate(cruces):
        if c.principal and c.secundaria:
            por_par[frozenset((c.principal, c.secundaria))].append(i)
    absorbido: set[int] = set()
    salida = []
    for i, c in enumerate(cruces):
        if i in absorbido:
            continue
        miembros = list(c.nodos)
        if c.principal and c.secundaria:
            for j in por_par[frozenset((c.principal, c.secundaria))]:
                if j <= i or j in absorbido or cruces[j].semaforizado != c.semaforizado:
                    continue
                otro = cruces[j]
                if math.hypot(otro.x - c.x, otro.y - c.y) > RADIO_GEMELOS_M:
                    continue
                todos = miembros + otro.nodos
                xs = [nodos[n][0] for n in todos]
                ys = [nodos[n][1] for n in todos]
                if math.hypot(max(xs) - min(xs), max(ys) - min(ys)) > SPAN_CRUCE_M:
                    continue
                miembros = todos
                absorbido.add(j)
        if len(miembros) == len(c.nodos):
            salida.append(c)
        else:
            nuevo = _armar_cruce(miembros, red, por_nodo)
            nuevo.principal, nuevo.secundaria = _calles(nuevo)
            salida.append(nuevo)
    return salida


# ─────────────────────────────────────────────────────────── reglas

def _conflicto_real(cruce: _Cruce, edges: dict[str, _Edge], conexiones_por_desde) -> bool:
    """Desde la secundaria se cruza de frente o se gira a la izquierda (en troncal, solo de frente).

    El giro se mide de punta a punta (rumbo al llegar vs. rumbo al salir del cruce), porque
    dentro de un cruce de doble calzada cada nodo ve solo una parte del movimiento.
    """
    from .escena3d import giro_por_rumbos

    conjunto = set(cruce.nodos)
    troncal = any(e.calle == cruce.principal and e.rango <= RANGO["trunk"] for e in cruce.patas)
    validos = {"s"} if troncal else {"s", "l"}
    for eid in cruce.entradas:
        e = edges[eid]
        if e.calle != cruce.secundaria:
            continue
        llegada = (e.rumbo_llegada + 180) % 360
        pendientes, vistos = [eid], {eid}
        while pendientes:
            actual = pendientes.pop()
            for hacia, _direccion in conexiones_por_desde.get(actual, ()):
                destino = edges.get(hacia)
                if destino is None or hacia in vistos:
                    continue
                vistos.add(hacia)
                if destino.desde in conjunto and destino.hasta in conjunto:
                    pendientes.append(hacia)
                    continue
                giro = giro_por_rumbos(llegada, destino.rumbo_salida)
                if giro in validos and (giro == "l" or destino.calle == cruce.secundaria):
                    return True
    return False


def _tramo_sin_semaforo(cruce: _Cruce, red: dict, adyacencia) -> float:
    """Largo del tramo de la vía principal sin semáforo que contiene el cruce (dos sentidos)."""
    nodos, conjunto = red["nodos"], set(cruce.nodos)
    patas = [e for e in cruce.patas if e.calle == cruce.principal]
    if not patas:
        return 0.0
    # dos sentidos a lo largo de la vía: se agrupan las patas por rumbo
    ref = _rumbo_pata(patas[0], conjunto)
    grupos: dict[int, list[_Edge]] = defaultdict(list)
    for e in patas:
        d = abs((_rumbo_pata(e, conjunto) - ref + 180) % 360 - 180)
        grupos[0 if d < 90 else 1].append(e)
    total = 0.0
    for sentido in (0, 1):
        inicio = grupos.get(sentido, [])
        if not inicio:
            continue
        cola = []
        for e in inicio:
            otro = e.desde if e.hasta in conjunto else e.hasta
            heapq.heappush(cola, (e.largo, otro))
        dist: dict[str, float] = {}
        encontrado = None
        while cola:
            d, n = heapq.heappop(cola)
            if n in dist or n in conjunto or d >= TRAMO_TOPE_M:
                continue
            dist[n] = d
            if nodos.get(n, (0, 0, ""))[2] in _TIPOS_SEMAFORO:
                encontrado = d
                break
            for e, vecino in adyacencia.get((n, cruce.principal), ()):
                if vecino not in dist:
                    heapq.heappush(cola, (d + e.largo, vecino))
        # sin semáforo hasta donde llega la vía: cuenta lo recorrido (con tope)
        total += encontrado if encontrado is not None else min(max(dist.values(), default=0.0), TRAMO_TOPE_M)
    return total


# ─────────────────────────────────────────────────────────── análisis (con caché)

def _firma(*paths: Path) -> list:
    return [[p.name, p.stat().st_mtime, p.stat().st_size] if p.is_file() else [p.name, None] for p in paths]


def analizar_red(
    net_path: Path,
    nombres: dict[str, str] | None = None,
    siniestros_path: Path = SINIESTROS_GEOJSON,
    pois_path: Path = POIS_GEOJSON,
) -> dict[str, Any]:
    """Cruces candidatos que cumplen R, con su evidencia fija (no depende de la corrida)."""
    nombres = nombres or {}
    red = _leer_red(net_path, nombres)
    edges, nodos = red["edges"], red["nodos"]
    a_lonlat = _transformador(red["location"])
    from pyproj import Transformer

    loc = red["location"]
    offx, offy = (float(v) for v in loc.get("netOffset", "0,0").split(","))
    a_proj = Transformer.from_crs("EPSG:4326", loc.get("projParameter"), always_xy=True)

    def a_xy(lon: float, lat: float) -> tuple[float, float]:
        px, py = a_proj.transform(lon, lat)
        return px + offx, py + offy

    por_nodo: dict[str, list[_Edge]] = defaultdict(list)
    for e in edges.values():
        por_nodo[e.desde].append(e)
        por_nodo[e.hasta].append(e)
    conexiones_por_desde: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for desde, hacia, direccion in red["conexiones"]:
        if desde in edges:
            conexiones_por_desde[desde].append((hacia, direccion))
    adyacencia: dict[tuple[str, str], list] = defaultdict(list)
    for e in edges.values():
        adyacencia[(e.desde, e.calle)].append((e, e.hasta))
        adyacencia[(e.hasta, e.calle)].append((e, e.desde))

    # nodos de la red vial con 3+ patas (o semáforo)
    viales = [
        n for n, (_, _, tipo) in nodos.items()
        if n in por_nodo and (len({e.id for e in por_nodo[n]}) >= 3 or tipo in _TIPOS_SEMAFORO)
    ]
    cruces = [_armar_cruce(g, red, por_nodo) for g in _agrupar(nodos, viales)]
    for c in cruces:
        c.principal, c.secundaria = _calles(c)
    cruces = _fusionar_gemelos(cruces, red, por_nodo)

    # índices para las distancias
    semaforos = _Grilla(RADIO_MISMA_CUADRA_M)
    desnivel = _Grilla(RADIO_DESNIVEL_M)
    for n, (x, y, tipo) in nodos.items():
        if tipo in _TIPOS_SEMAFORO:
            semaforos.agregar(x, y, n)
        if n in red["glorietas"] or any(e.enlace for e in por_nodo.get(n, ())):
            desnivel.agregar(x, y, n)
    nodos_cruce = _Grilla(RADIO_SINIESTRO_M)
    for i, c in enumerate(cruces):
        for n in c.nodos:
            nodos_cruce.agregar(nodos[n][0], nodos[n][1], i)

    # siniestros: cada uno al cruce más cercano (a menos de 30 m), sin contar doble
    siniestros = leer_puntos(siniestros_path)
    por_cruce: Counter = Counter()
    for lon, lat, _ in siniestros:
        x, y = a_xy(lon, lat)
        cercanos = list(nodos_cruce.cerca(x, y, RADIO_SINIESTRO_M))
        if cercanos:
            por_cruce[min(cercanos)[1]] += 1
    pois = _Grilla(RADIO_GENERADOR_M)
    for lon, lat, props in leer_puntos(pois_path):
        x, y = a_xy(lon, lat)
        pois.agregar(x, y, props)

    semaforizados = [{"entradas": c.entradas, "siniestros": por_cruce[i]} for i, c in enumerate(cruces) if c.semaforizado]
    candidatos = []
    descartes: Counter = Counter()
    for i, c in enumerate(cruces):
        if c.semaforizado:
            continue
        if not c.principal or not c.secundaria:
            descartes["no es un cruce de dos calles"] += 1
            continue
        rango_p = min(e.rango for e in c.patas if e.calle == c.principal)
        rango_s = min(e.rango for e in c.patas if e.calle == c.secundaria)
        if rango_p <= RANGO["trunk"]:
            # en Usaquén la única troncal es la Autopista Norte (TransMilenio por el centro):
            # sus cruces se resuelven a desnivel o por calzadas laterales, no con semáforo
            descartes["autopista o troncal de acceso controlado"] += 1
            continue
        if rango_p > RANGO_COLECTORA:
            descartes["sin vía colectora o mayor"] += 1
            continue
        if rango_s > RANGO_LOCAL:
            descartes["vía secundaria de servicio o peatonal"] += 1
            continue
        if any(True for n in c.nodos for _ in desnivel.cerca(nodos[n][0], nodos[n][1], RADIO_DESNIVEL_M)):
            descartes["rampa o glorieta cerca (desnivel)"] += 1
            continue
        if not _conflicto_real(c, edges, conexiones_por_desde):
            descartes["sin movimientos que crucen la vía principal"] += 1
            continue
        d_sem = min(
            (d for n in c.nodos for d, _ in semaforos.cerca(nodos[n][0], nodos[n][1], 1500)),
            default=None,
        )
        if d_sem is not None and d_sem < RADIO_MISMA_CUADRA_M:
            descartes["semáforo a menos de 80 m"] += 1
            continue
        generadores = [props for _, props in pois.cerca(c.x, c.y, RADIO_GENERADOR_M)]
        lon, lat = a_lonlat(c.x, c.y)
        nombre_p = next((e.nombre for e in c.patas if e.calle == c.principal and e.nombre), None)
        nombre_s = next((e.nombre for e in c.patas if e.calle == c.secundaria and e.nombre), None)
        representante = min(
            c.nodos,
            key=lambda n: (-len(por_nodo.get(n, ())), math.hypot(nodos[n][0] - c.x, nodos[n][1] - c.y)),
        )
        candidatos.append({
            "nodo_id": representante,
            "nodos": c.nodos,
            "x": round(c.x, 2), "y": round(c.y, 2),
            "lon": round(lon, 6), "lat": round(lat, 6),
            "calles": [n for n in (nombre_p, nombre_s) if n],
            "rango_principal": rango_p,
            "clase_principal": JERARQUIA[rango_p],
            "clase_secundaria": JERARQUIA[rango_s],
            "entradas": c.entradas,
            "siniestros": por_cruce[i],
            "generadores": len(generadores),
            "generadores_nombres": sorted({g.get("nombre") or g.get("tipo") for g in generadores})[:5],
            "tramo_m": round(_tramo_sin_semaforo(c, red, adyacencia)),
            "distancia_semaforo_m": round(d_sem) if d_sem is not None else None,
        })
    return {
        "candidatos": candidatos,
        "semaforizados": semaforizados,
        "descartes": dict(descartes),
        "hay_siniestros": bool(siniestros),
        "hay_pois": pois_path.is_file(),
        "nodos_viales": len(viales),
        "cruces": len(cruces),
    }


def analisis_con_cache(net_path: Path, nombres_path: Path | None, cache_path: Path,
                       siniestros_path: Path = SINIESTROS_GEOJSON, pois_path: Path = POIS_GEOJSON) -> dict:
    rutas = [net_path, siniestros_path, pois_path] + ([nombres_path] if nombres_path else [])
    firma = [VERSION_ANALISIS, _firma(*rutas)]
    if cache_path.is_file():
        try:
            datos = json.loads(cache_path.read_text(encoding="utf-8"))
            if datos.get("firma") == firma:
                return datos["analisis"]
        except (ValueError, KeyError, TypeError):
            pass
    nombres = json.loads(nombres_path.read_text(encoding="utf-8")) if nombres_path and nombres_path.is_file() else {}
    analisis = analizar_red(net_path, nombres, siniestros_path, pois_path)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps({"firma": firma, "analisis": analisis}, ensure_ascii=False), encoding="utf-8")
    return analisis


# ─────────────────────────────────────────────────────────── niveles y puntaje

@dataclass
class PuntajeCruce:
    nodo_id: str
    lon: float
    lat: float
    puntaje_total: float
    nivel: str          # "prioritario" | "recomendado" | "observacion"
    detalle: dict[str, float] = field(default_factory=dict)
    distancia_semaforo_m: float | None = None
    calles: list[str] = field(default_factory=list)
    nodos: list[str] = field(default_factory=list)
    evidencias: list[str] = field(default_factory=list)
    siniestros: int = 0
    generadores: int = 0
    tramo_m: float = 0.0
    volumen: int | None = None


def _volumen(entradas: list[str], vols: dict[str, Counter]) -> int:
    return sum(n for e in entradas for tipo, n in vols.get(e, Counter()).items() if tipo not in _PEATONES)


def puntuar(analisis: dict, volumenes_run_id: dict[str, Counter] | None = None) -> tuple[list[PuntajeCruce], dict]:
    """Niveles y puntajes de los candidatos; devuelve también los umbrales usados."""
    ref_sin = [s["siniestros"] for s in analisis["semaforizados"]]
    p50_sin = _percentil(ref_sin, 50)
    p75_sin = max(_percentil(ref_sin, 75), MIN_SINIESTROS)
    ref_vol: list[float] = []
    p75_vol = None
    if volumenes_run_id:
        ref_vol = [_volumen(s["entradas"], volumenes_run_id) for s in analisis["semaforizados"]]
        p75_vol = _percentil(ref_vol, 75)
    umbrales = {
        "siniestros_p50": p50_sin, "siniestros_p75": p75_sin, "volumen_p75": p75_vol,
        "tramo_m": TRAMO_LARGO_M, "semaforizados": len(ref_sin),
    }

    resultados = []
    for c in analisis["candidatos"]:
        sin, gen, tramo = c["siniestros"], c["generadores"], c["tramo_m"]
        vol = _volumen(c["entradas"], volumenes_run_id) if volumenes_run_id else None
        evidencias, fuertes = [], 0
        if analisis["hay_siniestros"] and sin >= MIN_SINIESTROS and (sin >= p75_sin or (sin >= p50_sin and gen)):
            fuertes += 1
            evidencias.append(f"{sin} siniestros a menos de {RADIO_SINIESTRO_M} m (p75 semaforizados: {p75_sin:.0f})")
        if tramo >= TRAMO_LARGO_M:
            fuertes += 1
            evidencias.append(
                f"más de {TRAMO_TOPE_M / 1000:.0f} km sin semáforo en ambos sentidos de la vía principal"
                if tramo >= 2 * TRAMO_TOPE_M else f"tramo de {tramo:.0f} m sin semáforo sobre la vía principal"
            )
        if vol is not None and p75_vol and vol >= p75_vol:
            fuertes += 1
            evidencias.append(f"{vol} vehículos simulados entran al cruce (p75 semaforizados: {p75_vol:.0f})")
        if gen:
            evidencias.append(f"{gen} colegio(s) o centro(s) de salud a menos de {RADIO_GENERADOR_M} m")
        if fuertes >= 2:
            nivel = "prioritario"
        elif fuertes == 1:
            nivel = "recomendado"
        elif gen or (analisis["hay_siniestros"] and sin >= max(p50_sin, 1)):
            nivel = "observacion"
        else:
            continue
        detalle = {
            "siniestros": round(_rango_percentil(sin, ref_sin), 3),
            "volumen": round(_rango_percentil(vol, ref_vol), 3) if vol is not None else 0.0,
            "generadores": round(min(gen / 3, 1.0), 3),
            "tramo": round(min(tramo / (2 * TRAMO_LARGO_M), 1.0), 3),
            "jerarquia": round(1 - c["rango_principal"] / RANGO_COLECTORA, 3),
        }
        extra = 25 * (0.35 * detalle["siniestros"] + 0.30 * detalle["volumen"] + 0.15 * detalle["generadores"]
                      + 0.10 * detalle["tramo"] + 0.10 * detalle["jerarquia"])
        resultados.append(PuntajeCruce(
            nodo_id=c["nodo_id"], lon=c["lon"], lat=c["lat"],
            puntaje_total=round(PISO[nivel] + extra, 1), nivel=nivel, detalle=detalle,
            distancia_semaforo_m=c["distancia_semaforo_m"], calles=c["calles"], nodos=c["nodos"],
            evidencias=evidencias, siniestros=sin, generadores=gen, tramo_m=tramo, volumen=vol,
        ))
        resultados[-1]._xy = (c["x"], c["y"])   # para el NMS

    _suprimir_vecinos(resultados)
    resultados.sort(key=lambda r: -r.puntaje_total)
    return resultados, umbrales


def _suprimir_vecinos(resultados: list[PuntajeCruce]) -> None:
    """Dos cruces del mismo nivel a menos de RADIO_NMS_M: el de menor puntaje baja un nivel."""
    for nivel in ("prioritario", "recomendado"):
        del_nivel = sorted((r for r in resultados if r.nivel == nivel), key=lambda r: -r.puntaje_total)
        aceptados = []
        for r in del_nivel:
            x, y = r._xy
            if any(math.hypot(x - ax, y - ay) < RADIO_NMS_M for ax, ay in aceptados):
                nuevo = _BAJA[nivel]
                r.puntaje_total = round(r.puntaje_total - (PISO[nivel] - PISO[nuevo]), 1)
                r.nivel = nuevo
                r.evidencias.append(f"se estudia junto con un cruce mejor puntuado a menos de {RADIO_NMS_M} m")
            else:
                aceptados.append((x, y))


def a_geojson(cruces: list[PuntajeCruce], umbrales: dict | None = None, notas: list[str] | None = None) -> dict:
    """Convierte la lista de PuntajeCruce a un FeatureCollection GeoJSON."""
    return {
        "type": "FeatureCollection",
        "umbrales": umbrales or {},
        "notas": notas or [],
        "features": [
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [c.lon, c.lat]},
                "properties": {
                    "id": c.nodo_id,
                    **{k: v for k, v in asdict(c).items() if k not in ("nodo_id", "lon", "lat")},
                },
            }
            for c in cruces
        ],
    }
