import json

import pytest
from pyproj import Transformer

from etl.sumo.intersecciones import (
    catalogo, clase_via, con_volumenes, extraer_nombres_vias, leer_semaforos, luz_de, volumenes_por_edge,
)

PROJ = "+proj=utm +zone=18 +ellps=WGS84 +datum=WGS84 +units=m +no_defs"
OFFSET = (-604416.25, -515587.58)
LON, LAT = -74.0300, 4.7000   # dónde debe quedar el cruce


def _xy(lon, lat):
    e, n = Transformer.from_crs("EPSG:4326", PROJ, always_xy=True).transform(lon, lat)
    return e + OFFSET[0], n + OFFSET[1]


def _red(tmp_path):
    x, y = _xy(LON, LAT)
    net = f"""<net>
  <location netOffset="{OFFSET[0]},{OFFSET[1]}" projParameter="{PROJ}"/>
  <edge id=":J_0" function="internal"><lane id=":J_0_0" speed="5"/></edge>
  <edge id="100#0" from="A" to="J" type="highway.primary" name="Avenida Carrera 9">
    <lane id="100#0_0" speed="16.67"/><lane id="100#0_1" speed="16.67"/>
  </edge>
  <edge id="-200#1" from="B" to="J" type="highway.residential_link">
    <lane id="-200#1_0" speed="8.33"/>
  </edge>
  <tlLogic id="J" type="static" programID="0" offset="0">
    <phase duration="30" state="GGr"/>
    <phase duration="3" state="yyr"/>
    <phase duration="27" state="rrG"/>
  </tlLogic>
  <junction id="J" type="traffic_light" x="{x}" y="{y}" z="2560.5"/>
  <junction id="A" type="dead_end" x="{x - 100}" y="{y}" z="2560"/>
  <junction id="B" type="dead_end" x="{x}" y="{y + 100}" z="2561"/>
  <connection from="100#0" to="x" fromLane="0" toLane="0" tl="J" linkIndex="0" dir="s"/>
  <connection from="100#0" to="y" fromLane="1" toLane="0" tl="J" linkIndex="1" dir="r"/>
  <connection from="-200#1" to="x" fromLane="0" toLane="0" tl="J" linkIndex="2" dir="l"/>
  <connection from=":J_0" to="x" fromLane="0" toLane="0"/>
</net>"""
    path = tmp_path / "red.net.xml"
    path.write_text(net, encoding="utf-8")
    return path


def test_leer_semaforos(tmp_path):
    [s] = leer_semaforos(_red(tmp_path), nombres_vias={"200": "Calle 147"})

    assert s.id == "J"
    assert s.lon == pytest.approx(LON, abs=1e-5)
    assert s.lat == pytest.approx(LAT, abs=1e-5)
    assert s.ciclo == 60
    assert s.movimientos == 3
    assert s.nombre == "Avenida Carrera 9 × Calle 147"   # el nombre del OSM completa el que falta
    accesos = {a.edge: a for a in s.accesos}
    assert accesos["100#0"].carriles == 2
    assert accesos["100#0"].velocidad_kmh == 60
    assert accesos["100#0"].clase == "arterial principal"
    assert accesos["-200#1"].clase == "enlace de local residencial"
    assert s.fases[0].luces == {"100#0": "verde", "-200#1": "rojo"}
    assert s.fases[1].luces == {"100#0": "amarillo", "-200#1": "rojo"}
    assert s.fases[2].luces == {"100#0": "rojo", "-200#1": "verde"}


def test_luces_y_clases():
    assert luz_de("rGr") == "verde"
    assert luz_de("ryr") == "amarillo"
    assert luz_de("rrs") == "rojo"
    assert luz_de("") == "apagado"
    assert clase_via("highway.tertiary") == "colectora"
    assert clase_via(None) == "sin clase"


VEHROUTE = """<routes>
  <vehicle id="auto_1" type="auto" depart="25200.00"><route edges="100#0 x"/></vehicle>
  <vehicle id="auto_2" type="auto" depart="25300.00">
    <routeDistribution last="1">
      <route replacedOnEdge="100#0" edges="-200#1 y"/>
      <route edges="100#0 y"/>
    </routeDistribution>
  </vehicle>
  <vehicle id="bici_1" type="bici" depart="25400.00"><route edges="-200#1 x"/></vehicle>
</routes>"""


def test_volumenes(tmp_path):
    vehroute = tmp_path / "vehroute.xml"
    vehroute.write_text(VEHROUTE, encoding="utf-8")

    vols = volumenes_por_edge(vehroute)

    assert vols["100#0"] == {"auto": 2}   # auto_2 cuenta por su última ruta
    assert vols["-200#1"] == {"bici": 1}

    [s] = leer_semaforos(_red(tmp_path))
    accesos = {a.edge: a for a in con_volumenes(s, vols).accesos}
    assert accesos["100#0"].volumen == 2
    assert accesos["100#0"].volumen_hora == pytest.approx(2 / 3, abs=0.05)
    assert con_volumenes(s, None).accesos[0].volumen is None


def test_catalogo_usa_cache(tmp_path, monkeypatch):
    red, cache = _red(tmp_path), tmp_path / "cache" / "semaforos.json"
    primero = catalogo(red, cache)

    import etl.sumo.intersecciones as mod
    monkeypatch.setattr(mod, "leer_semaforos", lambda *a, **k: pytest.fail("debía usar la caché"))
    segundo = catalogo(red, cache)

    assert [s.id for s in segundo] == [s.id for s in primero]
    assert segundo[0].fases[0].luces == primero[0].fases[0].luces


def test_extraer_nombres_vias(tmp_path):
    osm = tmp_path / "x.osm"
    osm.write_text(
        '<osm><node id="1" lat="4.7" lon="-74"/>'
        '<way id="200"><nd ref="1"/><tag k="name" v="Calle 147"/></way>'
        '<way id="300"><tag k="ref" v="AK 9"/></way><way id="400"><tag k="highway" v="service"/></way></osm>',
        encoding="utf-8",
    )
    assert extraer_nombres_vias(osm) == {"200": "Calle 147", "300": "AK 9"}
