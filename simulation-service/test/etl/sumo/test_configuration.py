import xml.etree.ElementTree as ET

from etl.sumo import configuration
from etl.sumo.configuration import ScenarioPaths, escribir_sumocfg_corrida


def test_sin_run_id_usa_el_escenario():
    paths = ScenarioPaths.from_name()
    assert paths.sumocfg == paths.sumocfg_template
    assert paths.trips.parent == paths.root


def test_sumocfg_de_corrida(tmp_path, monkeypatch):
    monkeypatch.setattr(configuration, "RUNS_DIR", tmp_path)
    paths = ScenarioPaths.from_name(run_id="abc")

    escribir_sumocfg_corrida(paths)

    assert paths.sumocfg == tmp_path / "abc" / "usaquen-sim.sumocfg"
    root = ET.parse(paths.sumocfg).getroot()
    valor = lambda tag: next(root.iter(tag)).get("value")
    assert valor("net-file") == str(paths.net.resolve())
    assert valor("route-files") == str(paths.routes.resolve())
    assert valor("fcd-output") == "output/fcd.xml"   # las salidas siguen relativas a la corrida
