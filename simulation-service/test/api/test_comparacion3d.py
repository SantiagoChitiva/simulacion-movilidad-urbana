import time

import pytest
from fastapi.testclient import TestClient

from api import api
from api.comparacion3d import GestorComparaciones, _ruta_inyeccion

_ACCESOS = [
    {"edge": "e1", "giros": [{"direccion": "s", "edges": ["a", "e1", "x"]}, {"direccion": "l", "edges": ["a", "e1", "y"]}]},
    {"edge": "e2", "giros": [{"direccion": "r", "edges": ["b", "e2", "z"]}]},
]


def _preparar_falso(comp, nodo_id, lon, lat, run_id_origen, intensidades):
    if nodo_id == "malo":
        raise RuntimeError("netconvert falló")
    comp.geometria = {"nodo": {"id": nodo_id}, "accesos": _ACCESOS}
    return {"nodo_id": nodo_id, "fuente_demanda": "sintetica", "geometria_accesos": _ACCESOS}


@pytest.fixture
def cliente(tmp_path):
    gestor = GestorComparaciones(preparar=_preparar_falso, runs_dir=tmp_path)
    api.app.dependency_overrides[api.obtener_gestor_comparaciones] = lambda: gestor
    yield TestClient(api.app), gestor
    api.app.dependency_overrides.clear()


def _esperar(c, cid):
    for _ in range(100):
        estado = c.get(f"/comparacion3d/{cid}").json()
        if estado["estado"] != "preparando":
            return estado
        time.sleep(0.02)
    raise AssertionError("no terminó de preparar")


def test_crear_y_consultar(cliente):
    c, _ = cliente
    r = c.post("/cruces/123/comparacion3d", json={"lon": -74.0, "lat": 4.7})
    assert r.status_code == 202
    estado = _esperar(c, r.json()["id"])

    assert estado["estado"] == "lista"
    assert "geometria_accesos" not in estado["info"]
    assert c.get(f"/comparacion3d/{estado['id']}/geometria").json()["accesos"] == _ACCESOS


def test_error_de_preparacion(cliente):
    c, _ = cliente
    cid = c.post("/cruces/malo/comparacion3d", json={"lon": 0, "lat": 0}).json()["id"]
    estado = _esperar(c, cid)
    assert estado["estado"] == "error" and "netconvert" in estado["error"]
    assert c.get(f"/comparacion3d/{cid}/geometria").status_code == 409


def test_limite_de_comparaciones(cliente):
    c, _ = cliente
    for _ in range(2):
        assert c.post("/cruces/1/comparacion3d", json={"lon": 0, "lat": 0}).status_code == 202
    assert c.post("/cruces/1/comparacion3d", json={"lon": 0, "lat": 0}).status_code == 429


def test_intensidades_fuera_de_rango(cliente):
    c, _ = cliente
    r = c.post("/cruces/1/comparacion3d", json={"lon": 0, "lat": 0, "intensidades": {"auto": 99999}})
    assert r.status_code == 422


def test_cerrar(cliente):
    c, gestor = cliente
    cid = c.post("/cruces/1/comparacion3d", json={"lon": 0, "lat": 0}).json()["id"]
    assert c.delete(f"/comparacion3d/{cid}").status_code == 204
    assert c.get(f"/comparacion3d/{cid}").status_code == 404
    assert gestor.listar() == []


def test_websocket_rechaza_comparacion_inexistente(cliente):
    c, _ = cliente
    from starlette.websockets import WebSocketDisconnect
    with pytest.raises(WebSocketDisconnect):
        with c.websocket_connect("/comparacion3d/no-existe") as ws:
            ws.receive_json()


def test_ruta_inyeccion():
    assert _ruta_inyeccion(_ACCESOS, "e1", "l") == ["a", "e1", "y"]
    assert _ruta_inyeccion(_ACCESOS, "e2", "s") == ["b", "e2", "z"]   # giro no disponible: el primero
    with pytest.raises(ValueError):
        _ruta_inyeccion(_ACCESOS, "nada", "s")


def test_destino_giro():
    from api.comparacion3d import _destino_giro

    accesos = [{"edge": "a", "giros": [{"direccion": "s", "edges": ["a", "b", "c"]}, {"direccion": "l", "edges": ["a", "x", "y"]}]}]
    assert _destino_giro(accesos, ["a", "b", "c"], "l") == "y"
    with pytest.raises(ValueError, match="no se puede girar 'r'"):
        _destino_giro(accesos, ["a", "b"], "r")
    with pytest.raises(ValueError, match="ya no va"):
        _destino_giro(accesos, ["z"], "s")


def test_ruta_inyeccion_por_tipo_y_peaton():
    accesos = [{"edge": "e", "giros": [
        {"direccion": "s", "salida": "x", "edges": ["a", "b", "c", "e", "x", "y", "z", "w"], "tipos": ["auto"]},
        {"direccion": "r", "salida": "q", "edges": ["a", "e", "q"], "tipos": ["auto", "bici"]},
    ]}]
    # la bici no puede recorrer el recto: se le da el giro que sí puede
    assert _ruta_inyeccion(accesos, "e", "s", "bici") == ["a", "e", "q"]
    with pytest.raises(ValueError, match="no puede entrar"):
        _ruta_inyeccion(accesos, "e", "s", "bus_pt")
    # el peatón solo camina dos tramos antes y después del cruce
    assert _ruta_inyeccion(accesos, "e", "s", "peaton") == ["b", "c", "e", "x", "y", "z"]


def test_sumocfg_lado_simetrico(tmp_path):
    import xml.etree.ElementTree as ET

    from api.comparacion3d import escribir_sumocfg_lado

    cfg = escribir_sumocfg_lado(tmp_path / "lado_b.sumocfg", tmp_path / "z.net.xml", [str(tmp_path / "d.rou.xml")],
                                str(tmp_path / "vt.xml"), [str(tmp_path / "programa.xml")])
    raiz = ET.parse(cfg).getroot()
    valor = lambda ruta: raiz.find(ruta).get("value")   # noqa: E731
    assert valor("random_number/thread-rngs") == "1"
    assert valor("processing/pedestrian.striping.dawdling") == "0"
    assert valor("processing/ignore-junction-blocker")
    assert valor("input/additional-files").endswith("programa.xml")
    assert valor("report/log").endswith("lado_b.log")


def test_vtypes_deterministas(tmp_path):
    from api.comparacion3d import vtypes_deterministas
    from etl.sumo.demanda_zona import escribir_vtypes

    salida = vtypes_deterministas(escribir_vtypes(tmp_path / "vt.xml"), tmp_path / "vt3d.xml")
    texto = salida.read_text(encoding="utf-8")
    assert texto.count('sigma="0"') == texto.count("<vType")


class _Vehiculos:
    def __init__(self, ids):
        self.ids = set(ids)
        self.llamadas = []

    def getIDList(self):
        return list(self.ids)

    def unsubscribe(self, vid):
        self.llamadas.append(("unsubscribe", vid))

    def remove(self, vid):
        self.llamadas.append(("remove", vid))
        self.ids.discard(vid)


class _LadoFalso:
    def __init__(self, en_entrada, en_red):
        self._en_entrada = set(en_entrada)
        self.con = type("Con", (), {})()
        self.con.vehicle = _Vehiculos(en_red)

    def ids_entrada(self, _edge, _metros):
        return set(self._en_entrada)

    def retirar(self, ids):
        from api.comparacion3d import Lado

        self._traci_error = RuntimeError
        return Lado.retirar(self, ids)


def test_despejar_entrada_quita_los_mismos_en_ambos_lados():
    from api.comparacion3d import despejar_entrada

    a = _LadoFalso({"v1"}, {"v1", "v2", "v3"})
    b = _LadoFalso({"v2"}, {"v1", "v2", "v3"})
    assert despejar_entrada([a, b], "e") == 4
    assert a.con.vehicle.ids == b.con.vehicle.ids == {"v3"}
    # se cancela la suscripción antes de retirar (si no, TraCI imprime "vehicle is not known")
    for lado in (a, b):
        llamadas = lado.con.vehicle.llamadas
        for vid in ("v1", "v2"):
            assert llamadas.index(("unsubscribe", vid)) < llamadas.index(("remove", vid))
