from etl.sumo.fcd import FcdToGeoJsonConfig, convert_fcd_to_geojson
import json

FCD = """<fcd-export>
  <timestep time="25200.00">
    <vehicle id="auto_1" x="-74.03" y="4.70" angle="90" type="auto" speed="5.5"/>
    <person id="peaton_1" x="-74.04" y="4.71" angle="10" speed="1.2"/>
  </timestep>
  <timestep time="25201.00">
    <vehicle id="auto_1" x="-74.031" y="4.70" angle="90" type="auto" speed="6"/>
  </timestep>
</fcd-export>"""

def test_fcd_to_geojson(tmp_path):
    fcd = tmp_path / "fcd.xml"
    fcd.write_text(FCD, encoding="utf-8")
    out = tmp_path / "out.geojson"

    result = convert_fcd_to_geojson(FcdToGeoJsonConfig(fcd, out))

    data = json.loads(out.read_text(encoding="utf-8"))
    assert result.stats.features_escritos == 3
    first = data["features"][0]
    assert first["geometry"]["coordinates"] == [-74.03, 4.7]   # [lon, lat]
    assert first["properties"]["id"] == "auto_1"

def test_sampling_skips_timesteps(tmp_path):
    fcd = tmp_path / "fcd.xml"
    fcd.write_text(FCD, encoding="utf-8")
    out = tmp_path / "out.geojson"

    result = convert_fcd_to_geojson(FcdToGeoJsonConfig(fcd, out, sample_every=2))

    assert result.stats.timesteps_exportados == 1   # solo t=25200
