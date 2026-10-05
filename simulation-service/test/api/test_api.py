from collections import Counter
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from api import api
from api.jobs import GestorCorridas
from etl.sumo import configuration
from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths


def _pipeline_falso(scenario, *, seed, demanda, run_id, exportar_puntos, on_etapa):
    """Hace lo mínimo que el gestor espera de run_pipeline, sin SUMO."""
    for etapa in ("generando_demanda", "ruteando", "simulando", "exportando"):
        on_etapa(etapa)
    paths = ScenarioPaths.from_name(scenario, run_id)
    paths.kepler_trips.parent.mkdir(parents=True, exist_ok=True)
    paths.kepler_trips.write_text('{"type":"FeatureCollection","features":[]}', encoding="utf-8")
    paths.fcd.write_text("<fcd-export/>", encoding="utf-8")
    por_modo = Counter({m.value: n for m, n in demanda.conteos.items()})
    return SimpleNamespace(
        etl=SimpleNamespace(trips=SimpleNamespace(stats=SimpleNamespace(
            viajes_generados=sum(por_modo.values()), por_modo=por_modo))),
        kepler=SimpleNamespace(stats=SimpleNamespace(trips_escritos=0)),
    )


def _pipeline_que_falla(*args, **kwargs):
    raise RuntimeError("SUMO falló")


@pytest.fixture
def cliente(tmp_path, monkeypatch):
    monkeypatch.setattr(configuration, "RUNS_DIR", tmp_path)
    gestor = GestorCorridas(ejecutar=_pipeline_falso)
    api.app.dependency_overrides[api.obtener_gestor] = lambda: gestor
    yield TestClient(api.app), gestor
    api.app.dependency_overrides.clear()


def test_modos_incluye_transporte_publico_con_nota(cliente):
    c, _ = cliente
    modos = {m["id"]: m for m in c.get("/demanda/modos").json()}

    assert len(modos) == 10
    assert "caminata" in modos["transporte_publico"]["nota"]


def test_presets(cliente):
    c, _ = cliente
    presets = {p["id"]: p for p in c.get("/demanda/presets").json()}

    assert set(presets) == {"encuesta", "mas_vehiculos", "mas_peatones", "dia_sin_carro"}
    assert sum(presets["encuesta"]["conteos"].values()) == 24647
    assert presets["dia_sin_carro"]["conteos"]["auto"] == 0


@pytest.mark.parametrize("cuerpo", [
    {"preset": "encuesta", "conteos": {"auto": -1}},
    {"preset": "encuesta", "conteos": {"auto": 0}},
    {"preset": "encuesta", "conteos": {"avion": 10}},
    {"preset": "no_existe", "conteos": {"auto": 10}},
    {"preset": "encuesta", "conteos": {"auto": configuration.MAX_VIAJES + 1}},
])
def test_solicitudes_invalidas(cliente, cuerpo):
    c, _ = cliente
    assert c.post("/simulaciones", json=cuerpo).status_code == 422


def test_corrida_completa(cliente):
    c, gestor = cliente
    r = c.post("/simulaciones", json={"preset": "dia_sin_carro", "conteos": {"bici": 30, "peaton": 5}, "semilla": 7})
    assert r.status_code == 202
    run_id = r.json()["id"]

    gestor.esperar(run_id, timeout=10)

    estado = c.get(f"/simulaciones/{run_id}").json()
    assert estado["estado"] == "terminado"
    assert estado["resultado"]["viajes_generados"] == 35
    assert not gestor.paths(run_id).fcd.exists()   # el FCD se borra tras exportar
    assert c.get(f"/simulaciones/{run_id}/kepler-trips").json()["type"] == "FeatureCollection"
    assert [s["id"] for s in c.get("/simulaciones").json()] == [run_id]


def test_corrida_con_error(tmp_path, monkeypatch):
    monkeypatch.setattr(configuration, "RUNS_DIR", tmp_path)
    gestor = GestorCorridas(ejecutar=_pipeline_que_falla)
    api.app.dependency_overrides[api.obtener_gestor] = lambda: gestor
    try:
        c = TestClient(api.app)
        run_id = c.post("/simulaciones", json={"conteos": {"auto": 10}}).json()["id"]
        gestor.esperar(run_id, timeout=10)

        estado = c.get(f"/simulaciones/{run_id}").json()
        assert estado["estado"] == "error"
        assert "SUMO falló" in estado["error"]
        assert c.get(f"/simulaciones/{run_id}/kepler-trips").status_code == 409
    finally:
        api.app.dependency_overrides.clear()


def test_historial_sobrevive_reinicio(cliente):
    c, gestor = cliente
    run_id = c.post("/simulaciones", json={"conteos": {"taxi": 3}}).json()["id"]
    gestor.esperar(run_id, timeout=10)

    nuevo = GestorCorridas(ejecutar=_pipeline_falso)   # lee runs/*/estado.json

    assert nuevo.obtener(run_id).estado == "terminado"


def test_simulacion_inexistente(cliente):
    c, _ = cliente
    assert c.get("/simulaciones/nada").status_code == 404
