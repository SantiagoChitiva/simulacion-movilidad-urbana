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
