import pytest

from etl.sumo.telemetria import (
    clasificar_accion, drac, indice_riesgo, nivel_riesgo, opcion_enlace, pet_cruce, riesgo_peaton, ttc,
)


def test_ttc_solo_si_se_acerca_al_lider():
    assert ttc(20, 10, 5) == pytest.approx(4.0)
    assert ttc(20, 5, 10) is None
    assert ttc(None, 10, 0) is None


def test_drac():
    assert drac(10, 10, 0) == pytest.approx(5.0)
    assert drac(10, 3, 5) is None


def test_pet_cruce():
    assert pet_cruce(20, 10, 30, 10) == pytest.approx(1.0)
    assert pet_cruce(20, 0.1, 30, 10) is None   # detenido: no hay conflicto de paso


def test_indice_riesgo_manda_el_indicador_mas_grave():
    sin = indice_riesgo(None, None, None)
    assert (sin.indice, sin.nivel, sin.causa) == (0, "bajo", "sin conflictos")

    critico = indice_riesgo(1.0, 0.5)
    assert critico.indice == 100 and critico.nivel == "alto"
    assert "TTC" in critico.causa

    cruce = indice_riesgo(5.5, 0.2, 2.0)
    assert "PET" in cruce.causa and cruce.nivel == "alto"


def test_niveles():
    assert [nivel_riesgo(x) for x in (0, 29, 30, 59, 60, 100)] == ["bajo", "bajo", "medio", "medio", "alto", "alto"]


def test_riesgo_peaton():
    assert riesgo_peaton(None, 0).indice == 0
    assert riesgo_peaton(10, 10).nivel == "alto"     # el vehículo llega en 1 s


@pytest.mark.parametrize("args,codigo", [
    ((0.0, 0.0, 12, "r", 10), "espera_semaforo"),
    ((0.0, 0.0, 5, None, None, None, None, True), "cede_paso"),
    ((0.0, 0.0, 5, None, None, 4.0), "en_cola"),
    ((8.0, -1.0, 0, "r", 30), "frena_semaforo"),
    ((8.0, -3.0, 0), "frenada_fuerte"),
    ((8.0, 1.0, 0), "acelera"),
    ((8.0, 0.0, 0), "crucero"),
    ((8.0, 0.0, 0, None, None, None, "izquierda"), "cambia_carril"),
])
def test_clasificar_accion(args, codigo):
    assert clasificar_accion(*args)[0] == codigo


def test_opcion_enlace_etiqueta_direccion_y_estado():
    o = opcion_enlace("l", "m", False, True, True)
    assert o["etiqueta"] == "izquierda"
    assert "cede" in o["estado_etiqueta"]
    assert o["conflicto"] is True
