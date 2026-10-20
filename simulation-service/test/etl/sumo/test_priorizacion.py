import json

import pytest

from etl.sumo.priorizacion import analizar_red, puntuar

_LOCATION = (
    '<location netOffset="-600000.00,-515000.00" convBoundary="0,0,2000,2000" '
    'origBoundary="-74.1,4.6,-74.0,4.8" projParameter="+proj=utm +zone=18 +ellps=WGS84 +datum=WGS84 +units=m +no_defs"/>'
)


class Red:
    """Arma un .net.xml mínimo: nodos, edges de un carril (ida y vuelta) y conexiones."""

    def __init__(self):
        self.nodos: dict[str, tuple[float, float, str]] = {}
        self.edges: list[tuple[str, str, str, str, str]] = []
        self.conexiones: list[tuple[str, str, str]] = []

    def nodo(self, nid, x, y, tipo="priority"):
        self.nodos[nid] = (x, y, tipo)

    def via(self, desde, hasta, nombre, clase="residential", doble=True):
        eid = f"{nombre}_{desde}_{hasta}"
        self.edges.append((eid, desde, hasta, nombre, clase))
        if doble:
            self.edges.append((f"-{eid}", hasta, desde, nombre, clase))
        return eid

    def conexion(self, desde, hacia, direccion="s"):
        self.conexiones.append((desde, hacia, direccion))

    def escribir(self, path):
        lineas = ["<net>", _LOCATION]
        for eid, a, b, nombre, clase in self.edges:
            (xa, ya, _), (xb, yb, _) = self.nodos[a], self.nodos[b]
            largo = ((xa - xb) ** 2 + (ya - yb) ** 2) ** 0.5
            lineas.append(
                f'<edge id="{eid}" from="{a}" to="{b}" name="{nombre}" type="highway.{clase}">'
                f'<lane id="{eid}_0" index="0" length="{largo:.1f}" shape="{xa},{ya} {xb},{yb}"/></edge>'
            )
        for nid, (x, y, tipo) in self.nodos.items():
            lineas.append(f'<junction id="{nid}" type="{tipo}" x="{x}" y="{y}"/>')
        for desde, hacia, d in self.conexiones:
            lineas.append(f'<connection from="{desde}" to="{hacia}" fromLane="0" toLane="0" dir="{d}"/>')
        lineas.append("</net>")
        path.write_text("\n".join(lineas), encoding="utf-8")
        return path


def _cruz(red, nid="J", x=1000, y=1000, principal="Avenida X", clase="tertiary", secundaria="Calle Y"):
    """Cruce en + de `principal` (este-oeste) y `secundaria` (norte-sur) que se cruza de frente."""
    red.nodo(nid, x, y)
    for sufijo, dx, dy in (("o", -300, 0), ("e", 300, 0), ("s", 0, -200), ("n", 0, 200)):
        red.nodo(f"{nid}{sufijo}", x + dx, y + dy, "dead_end")
    red.via(f"{nid}o", nid, principal, clase)
    red.via(nid, f"{nid}e", principal, clase)
    sur = red.via(f"{nid}s", nid, secundaria)
    norte = red.via(nid, f"{nid}n", secundaria)
    red.conexion(sur, norte, "s")


def _analizar(tmp_path, red):
    return analizar_red(
        red.escribir(tmp_path / "red.net.xml"), {},
        siniestros_path=tmp_path / "no-siniestros.geojson", pois_path=tmp_path / "no-pois.geojson",
    )


def test_cruce_simple_cumple_las_reglas(tmp_path):
    red = Red()
    _cruz(red)
    analisis = _analizar(tmp_path, red)
    assert len(analisis["candidatos"]) == 1
    c = analisis["candidatos"][0]
    assert c["nodo_id"] == "J" and c["calles"] == ["Avenida X", "Calle Y"]
    assert not analisis["hay_siniestros"] and not analisis["hay_pois"]


def test_semaforo_a_menos_de_80_m_excluye(tmp_path):
    red = Red()
    _cruz(red)
    red.nodo("S", 1070, 1000, "traffic_light")
    analisis = _analizar(tmp_path, red)
    assert analisis["candidatos"] == []
    assert analisis["descartes"].get("semáforo a menos de 80 m") == 1


def test_via_local_por_local_no_es_candidata(tmp_path):
    red = Red()
    _cruz(red, clase="residential")
    analisis = _analizar(tmp_path, red)
    assert analisis["candidatos"] == []
    assert analisis["descartes"]["sin vía colectora o mayor"] == 1


def test_troncal_excluida(tmp_path):
    red = Red()
    _cruz(red, principal="Autopista", clase="trunk")
    assert _analizar(tmp_path, red)["candidatos"] == []


def test_solo_giro_a_la_derecha_no_es_conflicto(tmp_path):
    red = Red()
    red.nodo("J", 1000, 1000)
    for sufijo, dx, dy in (("o", -300, 0), ("e", 300, 0), ("s", 0, -200)):
        red.nodo(f"J{sufijo}", 1000 + dx, 1000 + dy, "dead_end")
    red.via("Jo", "J", "Avenida X", "tertiary")
    este = red.via("J", "Je", "Avenida X", "tertiary")
    sur = red.via("Js", "J", "Calle Y")
    red.conexion(sur, este, "r")      # la calle solo entra a la derecha
    analisis = _analizar(tmp_path, red)
    assert analisis["candidatos"] == []
    assert analisis["descartes"]["sin movimientos que crucen la vía principal"] == 1


def test_nodo_a_mitad_de_cuadra_no_es_cruce(tmp_path):
    red = Red()
    red.nodo("M", 1000, 1000)
    for sufijo, dx in (("o", -300), ("e", 300)):
        red.nodo(f"M{sufijo}", 1000 + dx, 1000, "dead_end")
    red.nodo("Mp", 1000, 1030, "dead_end")
    red.via("Mo", "M", "Avenida X", "tertiary")
    red.via("M", "Me", "Avenida X", "tertiary")
    red.via("M", "Mp", "Avenida X", "service")   # entrada a un predio, misma calle
    analisis = _analizar(tmp_path, red)
    assert analisis["candidatos"] == []


def test_doble_calzada_es_un_solo_cruce(tmp_path):
    red = Red()
    # dos calzadas de la avenida a 30 m, cortadas por la misma calle
    red.nodo("J1", 1000, 1000)
    red.nodo("J2", 1000, 1030)
    for nid, (x, y) in {"o1": (700, 1000), "e1": (1300, 1000), "o2": (700, 1030), "e2": (1300, 1030),
                        "s": (1000, 800), "n": (1000, 1230)}.items():
        red.nodo(nid, x, y, "dead_end")
    red.via("o1", "J1", "Avenida X", "secondary", doble=False)
    red.via("J1", "e1", "Avenida X", "secondary", doble=False)
    red.via("e2", "J2", "Avenida X", "secondary", doble=False)
    red.via("J2", "o2", "Avenida X", "secondary", doble=False)
    sur = red.via("s", "J1", "Calle Y")
    medio = red.via("J1", "J2", "Calle Y")
    norte = red.via("J2", "n", "Calle Y")
    red.conexion(sur, medio, "s")
    red.conexion(medio, norte, "s")
    analisis = _analizar(tmp_path, red)
    assert len(analisis["candidatos"]) == 1
    assert sorted(analisis["candidatos"][0]["nodos"]) == ["J1", "J2"]


def test_siniestros_y_generadores_se_asignan_al_cruce(tmp_path):
    from pyproj import Transformer

    red = Red()
    _cruz(red)
    t = Transformer.from_crs("+proj=utm +zone=18 +ellps=WGS84 +datum=WGS84 +units=m +no_defs", "EPSG:4326", always_xy=True)
    lon, lat = t.transform(1000 + 600000, 1000 + 515000)
    punto = {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat]}, "properties": {"tipo": "school"}}
    (tmp_path / "s.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": [punto] * 5}), encoding="utf-8")
    (tmp_path / "p.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": [punto]}), encoding="utf-8")
    analisis = analizar_red(red.escribir(tmp_path / "red.net.xml"), {}, tmp_path / "s.geojson", tmp_path / "p.geojson")
    c = analisis["candidatos"][0]
    assert c["siniestros"] == 5 and c["generadores"] == 1
    assert c["colegios"] == 1 and c["salud"] == 0
    assert c["brazos"] == 4


# ─────────────────────────────────────────────── niveles (función pura)

def _candidato(nid, x, siniestros=0, generadores=0, tramo=0, entradas=()):
    return {
        "nodo_id": nid, "nodos": [nid], "x": x, "y": 0, "lon": 0, "lat": 0, "calles": [],
        "rango_principal": 4, "clase_principal": "tertiary", "clase_secundaria": "residential",
        "entradas": list(entradas), "siniestros": siniestros, "generadores": generadores,
        "generadores_nombres": [], "tramo_m": tramo, "distancia_semaforo_m": 500,
    }


def _analisis(candidatos):
    # semaforizados de referencia: siniestros p50 = 10, p75 = 20
    return {
        "candidatos": candidatos, "hay_siniestros": True, "hay_pois": True,
        "semaforizados": [{"entradas": [], "siniestros": s} for s in (0, 10, 10, 20, 20)],
    }


@pytest.mark.parametrize("cand, nivel", [
    (_candidato("a", 0, siniestros=25, tramo=900), "prioritario"),
    (_candidato("b", 0, siniestros=25), "recomendado"),
    (_candidato("c", 0, siniestros=12, generadores=1), "recomendado"),   # mediana + generador
    (_candidato("d", 0, generadores=2), "observacion"),
])
def test_niveles(cand, nivel):
    resultado, umbrales = puntuar(_analisis([cand]))
    assert resultado[0].nivel == nivel
    assert umbrales["siniestros_p75"] == 20


def test_sin_evidencia_no_se_devuelve():
    resultado, _ = puntuar(_analisis([_candidato("x", 0)]))
    assert resultado == []


def test_volumen_como_evidencia():
    from collections import Counter

    analisis = _analisis([_candidato("v", 0, siniestros=25, entradas=["e1"])])
    analisis["semaforizados"] = [{"entradas": ["r"], "siniestros": s} for s in (0, 10, 10, 20, 20)]
    vols = {"e1": Counter(auto=900), "r": Counter(auto=100)}
    resultado, umbrales = puntuar(analisis, vols)
    assert umbrales["volumen_p75"] == 100
    assert resultado[0].nivel == "prioritario" and resultado[0].volumen == 900


def test_vecinos_del_mismo_nivel_se_estudian_juntos():
    cercanos = [_candidato("a", 0, siniestros=40, tramo=900), _candidato("b", 60, siniestros=25, tramo=900)]
    resultado, _ = puntuar(_analisis(cercanos))
    niveles = {r.nodo_id: r.nivel for r in resultado}
    assert niveles == {"a": "prioritario", "b": "recomendado"}
    assert resultado[0].puntaje_total > resultado[1].puntaje_total


def test_textos_para_no_tecnicos():
    cand = {**_candidato("t", 0, siniestros=25, generadores=1), "calles": ["Avenida X", "Calle Y"],
            "colegios": 1, "brazos": 3, "carriles_principal": 2, "siniestros_heridos": 4}
    r = puntuar(_analisis([cand]))[0][0]
    assert r.clase_principal == "tertiary" and r.medida
    assert r.tipo_vias == "Colectora × Residencial"
    assert "4 con heridos o muertos" in r.evidencias[0]
    assert "1 colegio o jardín a menos de 200 m" in r.evidencias
    assert r.contexto[0] == "Vía colectora (Avenida X) que cruza una vía residencial (Calle Y)"
    assert "Intersección en T (3 accesos)" in r.contexto
