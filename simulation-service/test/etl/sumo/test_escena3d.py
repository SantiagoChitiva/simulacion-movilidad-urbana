import json

from etl.sumo import escena3d
from etl.sumo.escena3d import _altura_edificio, _puntos, altura_terreno, edificios_zona, giro_por_rumbos, terreno


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

    # 10 x 10 m; el suelo baja hacia el este: el edificio se apoya en lo más bajo
    edificios = edificios_zona((-1, -1, 1, 1), lambda lon, lat: (lon * 10000, lat * 10000), lambda x, y: 7.0 - x / 10, path)

    assert len(edificios) == 1
    assert edificios[0]["altura"] == 9 and edificios[0]["z"] == 6.0
    assert edificios[0]["contorno"][1] == [10.0, 0.0]
    assert len(edificios[0]["contorno"]) == 4   # sin el punto de cierre repetido
    escena3d._edificios_lonlat.cache_clear()


def test_sin_archivo_de_edificios(tmp_path):
    escena3d._edificios_lonlat.cache_clear()
    assert edificios_zona((-1, -1, 1, 1), lambda a, b: (a, b), lambda x, y: 0, tmp_path / "no.geojson") == []


def test_descarta_edificios_diminutos(tmp_path):
    escena3d._edificios_lonlat.cache_clear()
    path = tmp_path / "edificios.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [_cuadro(0, 0)]}, "properties": {}},
    ]}), encoding="utf-8")
    # 1 x 1 m: ruido de la huella, no un edificio
    assert edificios_zona((-1, -1, 1, 1), lambda lon, lat: (lon * 1000, lat * 1000), lambda x, y: 0, path) == []
    escena3d._edificios_lonlat.cache_clear()


def test_giro_por_rumbos():
    assert giro_por_rumbos(0, 10) == "s"
    assert giro_por_rumbos(0, 90) == "r"      # de norte a este: horario
    assert giro_por_rumbos(350, 260) == "l"
    assert giro_por_rumbos(0, 180) == "t"


def test_terreno_interpola_la_pendiente():
    muestras = [(x, y, x / 10) for x in range(0, 101, 20) for y in range(0, 101, 20)]
    t = terreno(muestras, [0, 0, 100, 100])
    assert abs(altura_terreno(t, 50, 50) - 5) < 1.0
    assert altura_terreno(t, 90, 50) > altura_terreno(t, 10, 50)
