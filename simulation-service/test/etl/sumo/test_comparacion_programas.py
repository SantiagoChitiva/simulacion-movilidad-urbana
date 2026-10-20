import pytest

from etl.sumo.comparacion_programas import escribir_detectores, leer_metricas
from etl.sumo.programas_tls import FasePrograma, ProgramaTLS, ProgramasTLSError, es_fase_verde, programa_webster


def _base():
    # dos fases verdes (norte-sur y oriente-occidente) con su amarillo de 4 s
    return ProgramaTLS("tl", "0", "static", 0.0, [
        FasePrograma(30, "GGrr"), FasePrograma(4, "yyrr"), FasePrograma(30, "rrGG"), FasePrograma(4, "rryy"),
    ])


LUCES = [
    {"ns": "verde", "eo": "rojo"}, {"ns": "amarillo", "eo": "rojo"},
    {"ns": "rojo", "eo": "verde"}, {"ns": "rojo", "eo": "amarillo"},
]


def test_fase_de_cambio_con_giros_permitidos_no_es_verde():
    assert es_fase_verde("GGrrg")
    assert not es_fase_verde("yyrrg")   # amarillo aunque un giro siga permitido


def test_webster_da_mas_verde_al_acceso_mas_cargado():
    programa, info = programa_webster(_base(), LUCES, {"ns": 900, "eo": 300}, {"ns": 1, "eo": 1})
    verde_ns, verde_eo = programa.fases[0].duracion_s, programa.fases[2].duracion_s
    assert verde_ns > verde_eo
    assert programa.fases[1].duracion_s == 4 and programa.fases[3].duracion_s == 4   # amarillos intactos
    assert info["Y"] == pytest.approx(900 / 1800 + 300 / 1800, abs=1e-3)
    assert programa.ciclo_s == info["ciclo_optimo_s"] and not info["saturado"]
    assert programa.program_id == "webster"


def test_webster_saturado_usa_el_ciclo_maximo():
    programa, info = programa_webster(_base(), LUCES, {"ns": 1700, "eo": 1700}, {"ns": 1, "eo": 1})
    assert info["saturado"] and programa.ciclo_s == 150


def test_webster_sin_fases_verdes_falla():
    base = ProgramaTLS("tl", "0", "static", 0.0, [FasePrograma(4, "yy")])
    with pytest.raises(ProgramasTLSError):
        programa_webster(base, [{"a": "amarillo"}], {"a": 100}, {"a": 1})


def test_detectores_uno_por_carril_de_acceso(tmp_path):
    net = tmp_path / "zona.net.xml"
    net.write_text(
        '<net><edge id="a"><lane id="a_0" length="50"/><lane id="a_1" length="50"/></edge>'
        '<edge id="b"><lane id="b_0" length="40"/></edge><edge id="c"><lane id="c_0" length="1"/></edge></net>',
        encoding="utf-8",
    )
    n = escribir_detectores(net, ["a", "c", "no-esta"], tmp_path / "det.add.xml", tmp_path / "e2.xml")
    texto = (tmp_path / "det.add.xml").read_text(encoding="utf-8")
    assert n == 2 and "a_1" in texto and "b_0" not in texto and "c_0" not in texto   # c es demasiado corto


def test_metricas_de_una_corrida(tmp_path):
    (tmp_path / "tripinfo.xml").write_text(
        '<tripinfos><tripinfo id="v1" timeLoss="20" waitingTime="10"/>'
        '<tripinfo id="v2" timeLoss="40" waitingTime="30"/>'
        '<personinfo id="p1"><walk timeLoss="5"/><walk timeLoss="3"/></personinfo></tripinfos>',
        encoding="utf-8",
    )
    (tmp_path / "e2.xml").write_text(
        '<detector><interval maxJamLengthInVehicles="3" startedHalts="2"/>'
        '<interval maxJamLengthInVehicles="7" startedHalts="1"/></detector>',
        encoding="utf-8",
    )
    (tmp_path / "statistics.xml").write_text('<statistics><teleports total="1"/></statistics>', encoding="utf-8")
    m = leer_metricas(tmp_path / "tripinfo.xml", tmp_path / "e2.xml", tmp_path / "statistics.xml")
    assert m == {
        "vehiculos": 2, "demora_media_s": 30.0, "espera_media_s": 20.0, "cola_max_veh": 7, "detenciones": 3,
        "peatones": 1, "demora_peaton_s": 8.0, "teleports": 1,
    }


def test_metricas_sin_archivos(tmp_path):
    m = leer_metricas(tmp_path / "a", tmp_path / "b", tmp_path / "c")
    assert m["vehiculos"] == 0 and m["demora_media_s"] is None
