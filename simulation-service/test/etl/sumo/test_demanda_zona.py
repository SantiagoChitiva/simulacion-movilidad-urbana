import xml.etree.ElementTree as ET

from etl.sumo.demanda_zona import DemandaZonaConfig, contar_viajes, escribir_vtypes
from etl.sumo.vtypes import VTYPES


def test_args_random_trips_vehiculos(tmp_path):
    cfg = DemandaZonaConfig(tmp_path / "z.net.xml", tmp_path, intensidades={"moto": 360})
    args = cfg.args_random_trips("randomTrips.py", "moto", tmp_path / "m.xml")
    assert args[args.index("-p") + 1] == "10.000"           # 360 veh/h -> uno cada 10 s
    assert args[args.index("--vclass") + 1] == "motorcycle"
    assert 'type="moto"' in args[args.index("--trip-attributes") + 1]
    assert "--pedestrians" not in args


def test_args_random_trips_peatones(tmp_path):
    cfg = DemandaZonaConfig(tmp_path / "z.net.xml", tmp_path, intensidades={"peaton": 1200})
    args = cfg.args_random_trips("randomTrips.py", "peaton", tmp_path / "p.xml")
    assert "--pedestrians" in args
    assert args[args.index("-p") + 1] == "3.000"


def test_escribir_vtypes(tmp_path):
    destino = escribir_vtypes(tmp_path / "vtypes.add.xml")
    ids = {v.get("id") for v in ET.parse(destino).getroot().iter("vType")}
    assert ids == set(VTYPES)


def test_contar_viajes(tmp_path):
    path = tmp_path / "r.xml"
    path.write_text('<routes><trip id="1"/><vehicle id="2"/><person id="3"/></routes>', encoding="utf-8")
    assert contar_viajes(path) == 3
    assert contar_viajes(tmp_path / "no.xml") == 0
