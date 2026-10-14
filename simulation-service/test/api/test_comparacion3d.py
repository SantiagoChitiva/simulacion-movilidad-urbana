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
