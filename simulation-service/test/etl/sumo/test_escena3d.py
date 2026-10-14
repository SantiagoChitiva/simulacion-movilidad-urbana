import json

from etl.sumo import escena3d
from etl.sumo.escena3d import _altura_edificio, _puntos, edificios_zona


def _cuadro(x, y):
    return [[x, y], [x + 0.001, y], [x + 0.001, y + 0.001], [x, y + 0.001], [x, y]]


def test_puntos_agrega_z():
    assert _puntos("1,2 3,4,5") == [[1.0, 2.0, 0.0], [3.0, 4.0, 5.0]]


def test_altura_edificio():
    assert _altura_edificio({"height": 12.5}, (0, 0)) == 12.5
    h = _altura_edificio({"height": -1}, (-74.04, 4.71))
    assert 6 <= h <= 21 and h == _altura_edificio({"height": -1}, (-74.04, 4.71))


def test_edificios_zona_filtra_por_bbox(tmp_path):
    escena3d._edificios_lonlat.cache_clear()
    path = tmp_path / "edificios.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [_cuadro(0, 0)]}, "properties": {"height": 9}},
        {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [_cuadro(5, 5)]}, "properties": {}},
    ]}), encoding="utf-8")

    edificios = edificios_zona((-1, -1, 1, 1), lambda lon, lat: (lon * 1000, lat * 1000), lambda x, y: 7.0, path)

    assert len(edificios) == 1
    assert edificios[0]["altura"] == 9 and edificios[0]["z"] == 7.0
    assert edificios[0]["contorno"][1] == [1.0, 0.0]
    escena3d._edificios_lonlat.cache_clear()


def test_sin_archivo_de_edificios(tmp_path):
    escena3d._edificios_lonlat.cache_clear()
    assert edificios_zona((-1, -1, 1, 1), lambda a, b: (a, b), lambda x, y: 0, tmp_path / "no.geojson") == []
