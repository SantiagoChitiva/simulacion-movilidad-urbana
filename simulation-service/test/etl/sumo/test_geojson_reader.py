import json
from etl.sumo.geojson_reader import read_first_features


def test_reads_only_requested_features(tmp_path):
    features = [{"type": "Feature", "properties": {"id": i}} for i in range(10)]
    path = tmp_path / "out.geojson"
    path.write_text(
        json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":")),
        encoding="utf-8",
    )

    result = read_first_features(path, limit=3, chunk_size=16)  # chunk pequeño: fuerza lecturas parciales

    assert [f["properties"]["id"] for f in result] == [0, 1, 2]
