import gzip
import json
from collections import Counter
from types import SimpleNamespace

import pytest

from etl import precalculadas
from etl.sumo import configuration
from etl.sumo.configuration import ArchivosPrecalculada, ScenarioPaths
from etl.sumo.demanda import Preset

GEOJSON = '{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"mode":"auto"}}]}'


def _pipeline_falso(scenario, *, seed, demanda, run_id, exportar_puntos, on_progreso, cancelar):
    """Escribe lo que run_pipeline deja para el visor, sin SUMO."""
    on_progreso("simulando", 1.0)
    paths = ScenarioPaths.from_name(scenario, run_id)
    paths.kepler_trips.parent.mkdir(parents=True, exist_ok=True)
    paths.kepler_trips.write_text(GEOJSON, encoding="utf-8")
    paths.vehroute.write_text(
        '<routes><vehicle id="auto_1" type="auto"><route edges="e1 e2"/></vehicle></routes>',
        encoding="utf-8",
    )
    por_modo = Counter({m.value: n for m, n in demanda.conteos.items()})
    return SimpleNamespace(
        etl=SimpleNamespace(trips=SimpleNamespace(stats=SimpleNamespace(
            viajes_generados=sum(por_modo.values()), por_modo=por_modo))),
        kepler=SimpleNamespace(stats=SimpleNamespace(trips_escritos=1)),
    )


@pytest.fixture
def directorios(tmp_path, monkeypatch):
    monkeypatch.setattr(configuration, "RUNS_DIR", tmp_path / "runs")
    monkeypatch.setattr(configuration, "PRECALCULADAS_DIR", tmp_path / "precalculadas")
    return tmp_path


def test_generar_guarda_lo_que_usa_el_visor(directorios):
    meta = precalculadas.generar(Preset.DIA_SIN_CARRO, ejecutar=_pipeline_falso)
    archivos = ArchivosPrecalculada.from_preset("dia_sin_carro")

    with gzip.open(archivos.trips_gz, "rt", encoding="utf-8") as f:
        assert f.read() == GEOJSON
    assert precalculadas.leer_volumenes(Preset.DIA_SIN_CARRO) == {"e1": Counter(auto=1), "e2": Counter(auto=1)}
    assert meta["conteos"]["auto"] == 0   # los conteos por defecto del preset
    assert meta["tamano_original"] == len(GEOJSON)
    assert meta["resultado"]["viajes_generados"] == sum(meta["conteos"].values())
    assert json.loads(archivos.meta.read_text(encoding="utf-8")) == meta
    assert not (directorios / "runs" / "precalculada-dia_sin_carro").exists()   # se borró la corrida


def test_el_gz_es_reproducible(directorios):
    precalculadas.generar(Preset.ENCUESTA, ejecutar=_pipeline_falso)
    primero = ArchivosPrecalculada.from_preset("encuesta").trips_gz.read_bytes()
    precalculadas.generar(Preset.ENCUESTA, ejecutar=_pipeline_falso)

    assert ArchivosPrecalculada.from_preset("encuesta").trips_gz.read_bytes() == primero


def test_listar_marca_las_desactualizadas(directorios):
    assert precalculadas.listar() == []
    precalculadas.generar(Preset.ENCUESTA, ejecutar=_pipeline_falso)
    precalculadas.generar(Preset.MAS_PEATONES, ejecutar=_pipeline_falso)

    meta = ArchivosPrecalculada.from_preset("mas_peatones").meta
    datos = json.loads(meta.read_text(encoding="utf-8"))
    meta.write_text(json.dumps({**datos, "insumos": "otra-red"}), encoding="utf-8")

    lista = {p["preset"]: p for p in precalculadas.listar()}
    assert set(lista) == {"encuesta", "mas_peatones"}
    assert lista["encuesta"]["nombre"] == "Encuesta"
    assert not lista["encuesta"]["desactualizada"]
    assert lista["mas_peatones"]["desactualizada"]


def test_huella_ignora_fines_de_linea(tmp_path):
    lf, crlf = tmp_path / "lf.xml", tmp_path / "crlf.xml"
    lf.write_bytes(b"<a>\n<b/>\n</a>\n")
    crlf.write_bytes(b"<a>\r\n<b/>\r\n</a>\r\n")
    firma = lambda p: ((str(p), 0.0, 0),)

    assert precalculadas._huella(firma(lf)) == precalculadas._huella(firma(crlf))
