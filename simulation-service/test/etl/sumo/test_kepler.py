import json

import pytest

from etl.sumo.kepler import KeplerTripsConfig, convert_fcd_to_kepler_trips

BASE_2000 = 946684800   # 2000-01-01T00:00:00Z

FCD = """<fcd-export>
  <timestep time="25200.00">
    <vehicle id="auto_1" x="-74.030" y="4.70" z="2560" angle="90" type="auto" speed="5"/>
    <person id="peaton_1" x="-74.040" y="4.71" z="2550" angle="0" speed="0"/>
    <person id="transporte_publico_2" x="-74.050" y="4.72" z="2555" angle="90" speed="1.2"/>
  </timestep>
  <timestep time="25201.00">
    <vehicle id="auto_1" x="-74.031" y="4.70" z="2561" angle="90" type="auto" speed="5"/>
    <person id="peaton_1" x="-74.040" y="4.71" z="2550" angle="0" speed="0"/>
    <person id="transporte_publico_2" x="inf" y="inf" z="-1073741824" angle="90" speed="1.2"/>
  </timestep>
  <timestep time="25202.00">
    <vehicle id="auto_1" x="-74.032" y="4.70" z="2562" angle="90" type="auto" speed="5"/>
    <person id="peaton_1" x="-74.040" y="4.71" z="2550" angle="0" speed="0"/>
    <person id="transporte_publico_2" x="-74.051" y="4.72" z="2555" angle="90" speed="1.2"/>
  </timestep>
</fcd-export>"""


def _convert(tmp_path, **kwargs):
    fcd = tmp_path / "fcd.xml"
    fcd.write_text(FCD, encoding="utf-8")
    out = tmp_path / "trips.geojson"
    result = convert_fcd_to_kepler_trips(KeplerTripsConfig(fcd, out, **kwargs))
    data = json.loads(out.read_text(encoding="utf-8"))
    return result, {f["properties"]["id"]: f for f in data["features"]}


def test_trip_coordinates_lon_lat_z_unix_time(tmp_path):
    result, features = _convert(tmp_path)

    auto = features["auto_1"]
    assert auto["geometry"]["type"] == "LineString"
    # z relativa a la mínima del FCD (2550); el punto intermedio se descarta por step=5
    assert auto["geometry"]["coordinates"] == [
        [-74.03, 4.7, 10.0, BASE_2000 + 25200],
        [-74.032, 4.7, 12.0, BASE_2000 + 25202],
    ]
    assert auto["properties"]["mode"] == "auto"
    assert auto["properties"]["category"] == "vehiculo"
    assert result.stats.z_min == 2550


def test_person_mode_from_id_and_invalid_points(tmp_path):
    result, features = _convert(tmp_path)

    tp = features["transporte_publico_2"]
    assert tp["properties"]["mode"] == "transporte_publico"
    assert tp["properties"]["category"] == "persona"
    assert len(tp["geometry"]["coordinates"]) == 2
    assert result.stats.puntos_invalidos == 1


def test_still_entities_are_dropped(tmp_path):
    result, features = _convert(tmp_path)

    assert "peaton_1" not in features
    assert result.stats.descartados["peaton"] == 1
    assert result.stats.trips_escritos == 2


def test_without_z(tmp_path):
    _, features = _convert(tmp_path, include_z=False)

    assert all(c[2] == 0 for c in features["auto_1"]["geometry"]["coordinates"])


def test_missing_fcd_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        convert_fcd_to_kepler_trips(KeplerTripsConfig(tmp_path / "no.xml", tmp_path / "o.json"))
