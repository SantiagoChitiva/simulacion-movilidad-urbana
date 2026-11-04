import shutil
import subprocess

import pytest

from etl.sumo.aforos import _modos, _normalizar, diferencia_angular, rumbo, ubicar_sentido


def test_rumbo_y_diferencia():
    assert rumbo((0, 0), (0, 10)) == pytest.approx(0)
    assert rumbo((0, 0), (10, 0)) == pytest.approx(90)
    assert rumbo((0, 0), (0, -10)) == pytest.approx(180)
    assert diferencia_angular(350, 10) == pytest.approx(20)


def test_modos_suma_tipologias_y_descarta_las_no_simuladas():
    modos = _modos({"AUTO": 10, "TAXI OCUPADO": 2, "BICICLETA EN CALZADA": 3, "BICICLETA EN CICLORUTA": 4, "CG": 50})
    assert modos == {"auto": 10, "taxi": 2, "bici": 7}


def test_normalizar():
    assert "usaquen" in _normalizar("Usaquén")


@pytest.fixture
def red(tmp_path):
    if shutil.which("netconvert") is None:
        pytest.skip("netconvert no está en el PATH")
    (tmp_path / "r.nod.xml").write_text(
        '<nodes><node id="S" x="0" y="-200"/><node id="N" x="0" y="200"/>'
        '<node id="W" x="-200" y="5"/><node id="E" x="200" y="5"/><node id="C" x="0" y="5"/></nodes>', encoding="utf-8")
    (tmp_path / "r.edg.xml").write_text(
        '<edges><edge id="SN" from="S" to="N" priority="5"/><edge id="NS" from="N" to="S" priority="5"/>'
        '<edge id="WC" from="W" to="C" priority="1"/><edge id="CE" from="C" to="E" priority="1"/></edges>', encoding="utf-8")
    net = tmp_path / "r.net.xml"
    subprocess.run(["netconvert", "-n", str(tmp_path / "r.nod.xml"), "-e", str(tmp_path / "r.edg.xml"), "-o", str(net)],
                   check=True, capture_output=True)
    import sumolib

    return sumolib.net.readNet(str(net))


def test_ubicar_sentido_por_rumbo(red):
    x, y = red.getNode("C").getCoord()[:2]
    y -= 5   # entre la vía norte-sur y la este-oeste
    assert ubicar_sentido(red, x, y, "S-N", "passenger", 60, 40)[0].getID() == "SN"
    assert ubicar_sentido(red, x, y, "N-S", "passenger", 60, 40)[0].getID() == "NS"
    assert ubicar_sentido(red, x, y, "W-E", "passenger", 60, 40)[0].getID() in ("WC", "CE")
    assert ubicar_sentido(red, x, y, "E-W", "passenger", 60, 40) is None   # no hay vía hacia el oeste
    assert ubicar_sentido(red, x, y, "INGRESO", "passenger", 60, 40) is None


def test_pasa_al_lado_distingue_calzada_paralela_de_tramo_siguiente():
    from etl.sumo.aforos import pasa_al_lado
    paralela = [(0, 10), (100, 10)]          # pasa junto al punto (50, 0)
    siguiente = [(60, 0), (160, 0)]          # empieza después del punto
    anterior = [(-100, 0), (40, 0)]          # termina antes
    assert pasa_al_lado(paralela, 50, 0)
    assert not pasa_al_lado(siguiente, 50, 0) and not pasa_al_lado(anterior, 50, 0)
