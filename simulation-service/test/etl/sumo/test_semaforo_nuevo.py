from pathlib import Path

import pytest

from etl.sumo import semaforo_nuevo
from etl.sumo.semaforo_nuevo import (
    SemaforoNuevoConfig, SemaforoNuevoError, _resumen_programa, agregar_semaforo, tipo_nodo,
)

_RED = """<net>
  <edge id="a" from="1" to="2"><lane id="a_0" shape="0,0 10,0"/></edge>
  <tlLogic id="9" type="static" programID="0" offset="0">
    <phase duration="30" state="Gr"/><phase duration="3" state="yr"/>
    <phase duration="30" state="rG"/><phase duration="3" state="ry"/>
  </tlLogic>
  <junction id="2" type="priority" x="10" y="0"/>
  <junction id="9" type="traffic_light" x="20" y="0"/>
  <connection from="a" to="b" fromLane="0" toLane="0" tl="9" linkIndex="0"/>
  <connection from="a" to="c" fromLane="0" toLane="0" tl="9" linkIndex="1"/>
</net>"""


@pytest.fixture
def red(tmp_path) -> Path:
    path = tmp_path / "zona.net.xml"
    path.write_text(_RED, encoding="utf-8")
    return path


def test_to_args(tmp_path):
    cfg = SemaforoNuevoConfig(tmp_path / "z.net.xml", "123", tmp_path / "t.net.xml", ciclo_s=90)
    args = cfg.to_args("netconvert")
    assert args[args.index("-n") + 1] == str(tmp_path / "semaforo_propuesto.nod.xml")
    assert args[args.index("--tls.default-type") + 1] == "static"
    assert args[args.index("--tls.cycle.time") + 1] == "90"


def test_parche_un_tl_para_todos_los_nodos(tmp_path):
    cfg = SemaforoNuevoConfig(tmp_path / "z.net.xml", "1", tmp_path / "t.net.xml", nodos=("1", "2", "3"))
    texto = cfg.escribir_parche({"1", "2"}).read_text(encoding="utf-8")
    assert texto.count('type="traffic_light" tl="1"') == 2
    assert 'id="3"' not in texto   # fuera de la zona


def test_tipo_nodo(red):
    assert tipo_nodo(red, "2") == "priority"
    assert tipo_nodo(red, "no-existe") is None


def test_resumen_programa(red):
    assert _resumen_programa(red, "9") == (4, 66.0, 2)


def test_sin_netconvert(red, tmp_path, monkeypatch):
    monkeypatch.setattr(semaforo_nuevo.shutil, "which", lambda _: None)
    with pytest.raises(SemaforoNuevoError, match="netconvert"):
        agregar_semaforo(SemaforoNuevoConfig(red, "2", tmp_path / "t.net.xml"))


@pytest.mark.parametrize("nodo,mensaje", [("9", "ya tiene semáforo"), ("x", "no está")])
def test_rechaza_cruces_invalidos(red, tmp_path, monkeypatch, nodo, mensaje):
    monkeypatch.setattr(semaforo_nuevo.shutil, "which", lambda _: "netconvert")
    with pytest.raises(SemaforoNuevoError, match=mensaje):
        agregar_semaforo(SemaforoNuevoConfig(red, nodo, tmp_path / "t.net.xml"))
