from pathlib import Path

from etl.sumo.subred import SubredConfig, caminatas_por_origen_destino


def test_args_peatonales_solo_con_la_opcion():
    base = SubredConfig(Path("n.net.xml"), (-74.0, 4.7), 300, Path("z.net.xml"))
    assert base.args_peatonales() == []
    args = SubredConfig(Path("n.net.xml"), (-74.0, 4.7), 300, Path("z.net.xml"), peatonal=True).args_peatonales()
    assert "--sidewalks.guess" in args and "--crossings.guess" in args and "--walkingareas" in args


def test_caminatas_por_origen_destino(tmp_path):
    rou = tmp_path / "zona.rou.xml"
    rou.write_text(
        '<routes><person id="p" depart="0"><walk edges="a b c"/></person>'
        '<person id="q" depart="1"><walk edges="d"/></person></routes>', encoding="utf-8",
    )
    assert caminatas_por_origen_destino(rou) == 1
    texto = rou.read_text(encoding="utf-8")
    assert 'from="a"' in texto and 'to="c"' in texto and 'edges="d"' in texto


def test_sin_paradas_de_bus(tmp_path):
    from etl.sumo.subred import sin_paradas_de_bus

    rou = tmp_path / "zona.rou.xml"
    rou.write_text(
        '<routes><vehicle id="b" type="bus_sitp" depart="0"><route edges="a b"/><stop busStop="pt_1" duration="10"/></vehicle>'
        '<person id="p" depart="0"><walk edges="a"/><ride busStop="pt_1" lines="T1"/></person>'
        '<person id="q" depart="0"><walk edges="a b"/></person></routes>', encoding="utf-8",
    )
    assert sin_paradas_de_bus(rou) == (1, 1)
    texto = rou.read_text(encoding="utf-8")
    assert "busStop" not in texto and 'id="q"' in texto and 'id="b"' in texto


def test_encuentra_duaiterate_en_tools_assign():
    from etl.sumo.subred import encontrar_herramienta
    assert encontrar_herramienta("duaIterate.py").replace("\\", "/").endswith("tools/assign/duaIterate.py")
