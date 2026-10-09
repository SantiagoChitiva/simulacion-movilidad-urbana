import gzip
import json
import threading
from collections import Counter
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from api import api
from api.jobs import GestorCorridas, avance_global
from etl.etl import Cancelado
from etl.sumo import configuration
from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths


def _pipeline_falso(scenario, *, seed, demanda, run_id, exportar_puntos, on_progreso, cancelar):
    """Hace lo mínimo que el gestor espera de run_pipeline, sin SUMO."""
    for etapa in ("generando_demanda", "ruteando", "simulando", "exportando"):
        on_progreso(etapa, 0.5)
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
    assert c.post("/simulaciones/nada/cancelar").status_code == 404


# ----------------------------------------------------------------- intersecciones

@pytest.fixture
def con_catalogo(cliente, tmp_path, monkeypatch):
    """Catálogo de la red real del escenario, con la caché en tmp."""
    monkeypatch.setattr(api, "CACHE_DIR", tmp_path / "cache")
    api._semaforos.cache_clear()
    yield cliente
    api._semaforos.cache_clear()


def test_intersecciones_de_la_red(con_catalogo):
    c, _ = con_catalogo
    features = c.get("/intersecciones").json()["features"]

    assert len(features) == 220
    lon, lat = features[0]["geometry"]["coordinates"]
    assert -74.06 < lon < -74.0 and 4.66 < lat < 4.83   # dentro de Usaquén


def test_ficha_con_volumenes_de_una_corrida(con_catalogo):
    c, gestor = con_catalogo
    tl_id = c.get("/intersecciones").json()["features"][0]["properties"]["id"]
    ficha = c.get(f"/intersecciones/{tl_id}").json()
    acceso = ficha["accesos"][0]["edge"]

    run_id = c.post("/simulaciones", json={"conteos": {"auto": 10}}).json()["id"]
    gestor.esperar(run_id, timeout=10)
    vehroute = gestor.paths(run_id).vehroute
    vehroute.write_text(
        f'<routes><vehicle id="auto_1" type="auto"><route edges="{acceso}"/></vehicle></routes>',
        encoding="utf-8",
    )

    ficha = c.get(f"/intersecciones/{tl_id}", params={"run_id": run_id}).json()
    assert ficha["fases"] and ficha["ciclo"] > 0
    assert {a["edge"]: a["volumen"] for a in ficha["accesos"]}[acceso] == 1
    assert c.get("/intersecciones/no-existe").status_code == 404
    assert c.get("/intersecciones", params={"run_id": "nada"}).status_code == 404


# ------------------------------------------------------------ precalculadas

@pytest.fixture
def con_precalculada(con_catalogo, tmp_path, monkeypatch):
    """Un preset 'encuesta' precalculado a mano en un directorio temporal."""
    monkeypatch.setattr(configuration, "PRECALCULADAS_DIR", tmp_path / "precalculadas")
    archivos = configuration.ArchivosPrecalculada.from_preset("encuesta")
    archivos.dir.mkdir(parents=True)
    geojson = b'{"type":"FeatureCollection","features":[]}'
    archivos.trips_gz.write_bytes(gzip.compress(geojson))
    archivos.meta.write_text(json.dumps({
        "preset": "encuesta", "conteos": {"auto": 10}, "semilla": None, "insumos": "x",
        "tamano_original": len(geojson), "resultado": {"viajes_generados": 10},
    }), encoding="utf-8")
    return con_catalogo, archivos


def test_precalculadas_listado_y_trips_comprimidos(con_precalculada):
    (c, _), _ = con_precalculada
    lista = c.get("/precalculadas").json()
    assert [p["preset"] for p in lista] == ["encuesta"]
    assert lista[0]["desactualizada"]   # la huella "x" no es la de los insumos reales

    r = c.get("/precalculadas/encuesta/kepler-trips")
    assert r.headers["content-encoding"] == "gzip"
    assert r.headers["x-tamano-original"] == str(len(r.content))   # el cliente ya lo descomprimió
    assert r.json()["type"] == "FeatureCollection"

    assert c.get("/precalculadas/mas_peatones/kepler-trips").status_code == 404
    assert c.get("/precalculadas/no_existe/kepler-trips").status_code == 422


def test_ficha_con_volumenes_de_una_precalculada(con_precalculada):
    (c, _), archivos = con_precalculada
    tl_id = c.get("/intersecciones").json()["features"][0]["properties"]["id"]
    acceso = c.get(f"/intersecciones/{tl_id}").json()["accesos"][0]["edge"]
    archivos.volumenes.write_text(json.dumps({acceso: {"auto": 7}}), encoding="utf-8")

    ficha = c.get(f"/intersecciones/{tl_id}", params={"precalculada": "encuesta"}).json()
    assert {a["edge"]: a["volumen"] for a in ficha["accesos"]}[acceso] == 7
    assert c.get("/intersecciones", params={"precalculada": "dia_sin_carro"}).status_code == 404


# ------------------------------------------------------------ avance y cancelación

def test_avance_global_por_franjas():
    assert avance_global("generando_demanda", None) == 0.0
    assert avance_global("simulando", 0.5) == pytest.approx(0.5)
    assert avance_global("exportando", 1.0) == pytest.approx(1.0)


class _PipelineBloqueado:
    """Reporta avance en 'simulando' y espera hasta que lo cancelen (o lo liberen)."""

    def __init__(self):
        self.simulando = threading.Event()
        self.liberar = threading.Event()

    def __call__(self, scenario, *, seed, demanda, run_id, exportar_puntos, on_progreso, cancelar):
        paths = ScenarioPaths.from_name(scenario, run_id)
        paths.routes.parent.mkdir(parents=True, exist_ok=True)
        paths.routes.write_text("<routes/>", encoding="utf-8")   # archivo "pesado" parcial
        on_progreso("simulando", 0.4)
        self.simulando.set()
        while not self.liberar.wait(0.05):
            if cancelar.is_set():
                raise Cancelado()
        return _pipeline_falso(scenario, seed=seed, demanda=demanda, run_id=run_id,
                               exportar_puntos=exportar_puntos, on_progreso=on_progreso,
                               cancelar=cancelar)


@pytest.fixture
def bloqueado(tmp_path, monkeypatch):
    monkeypatch.setattr(configuration, "RUNS_DIR", tmp_path)
    pipeline = _PipelineBloqueado()
    gestor = GestorCorridas(ejecutar=pipeline)
    api.app.dependency_overrides[api.obtener_gestor] = lambda: gestor
    yield TestClient(api.app), gestor, pipeline
    pipeline.liberar.set()
    api.app.dependency_overrides.clear()


def test_avance_visible_durante_la_corrida(bloqueado):
    c, gestor, pipeline = bloqueado
    run_id = c.post("/simulaciones", json={"conteos": {"auto": 10}}).json()["id"]
    assert pipeline.simulando.wait(5)

    estado = c.get(f"/simulaciones/{run_id}").json()
    assert estado["estado"] == "simulando"
    assert estado["avance"] == pytest.approx(0.15 + 0.70 * 0.4)
    assert estado["iniciada"] is not None


def test_cancelar_corrida_en_curso(bloqueado):
    c, gestor, pipeline = bloqueado
    run_id = c.post("/simulaciones", json={"conteos": {"auto": 10}}).json()["id"]
    assert pipeline.simulando.wait(5)

    r = c.post(f"/simulaciones/{run_id}/cancelar")
    assert r.status_code == 202
    assert r.json()["estado"] == "cancelando"
    gestor.esperar(run_id, timeout=5)

    assert c.get(f"/simulaciones/{run_id}").json()["estado"] == "cancelada"
    restantes = [p.name for p in (configuration.RUNS_DIR / run_id).iterdir()]
    assert restantes == ["estado.json"]   # se borraron los archivos parciales
    assert c.post(f"/simulaciones/{run_id}/cancelar").status_code == 409


def test_cancelar_corrida_en_cola(bloqueado):
    c, gestor, pipeline = bloqueado
    primera = c.post("/simulaciones", json={"conteos": {"auto": 10}}).json()["id"]
    assert pipeline.simulando.wait(5)
    segunda = c.post("/simulaciones", json={"conteos": {"taxi": 5}}).json()["id"]   # espera en cola

    assert c.post(f"/simulaciones/{segunda}/cancelar").json()["estado"] == "cancelada"
    assert c.get(f"/simulaciones/{primera}").json()["estado"] == "simulando"   # la otra sigue
