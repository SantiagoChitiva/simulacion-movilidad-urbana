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


# ─── viaje del actor seguido y balance del cruce

from etl.sumo.telemetria import (  # noqa: E402
    acumular_viaje, actualizar_balance, comparar_viajes, nuevo_balance, resumen_balance, resumen_viaje,
)


def _frame(kmh, a=0.0, riesgo=None, distancia=None, co2=0.0):
    return {"velocidad_kmh": kmh, "aceleracion": a, "riesgo": {"indice": riesgo} if riesgo is not None else None,
            "distancia_m": distancia, "co2_mg_s": co2, "perdida_s": 4.0}


def test_viaje_cuenta_paradas_frenadas_y_tiempo_detenido():
    v = None
    for i, (kmh, a) in enumerate([(0, 0), (20, 1), (30, 0), (10, -5), (0, -5), (0, 0), (25, 2)]):
        v = acumular_viaje(v, _frame(kmh, a, riesgo=10 * i, distancia=10.0 * i, co2=2000), t=100 + i, dt=1.0)
    r = resumen_viaje(v, terminado=True)
    assert r["paradas"] == 1            # salir desde cero no es parada; la de los segundos 4-5 sí
    assert r["frenadas"] == 1           # dos frames seguidos frenando son una sola frenada
    assert r["detenido_s"] == 3.0 and r["duracion_s"] == 6.0
    assert r["riesgo_max"] == 60 and r["distancia_m"] == 60 and r["co2_g"] == 14.0
    assert r["velocidad_media_kmh"] == 36.0


def test_viaje_de_peaton_integra_la_distancia():
    v = acumular_viaje(None, {"velocidad_kmh": 3.6}, t=0, dt=1.0)
    v = acumular_viaje(v, {"velocidad_kmh": 3.6}, t=1, dt=1.0)
    assert resumen_viaje(v, True)["distancia_m"] == 2


def _resumen(duracion, riesgo, frenadas, terminado=True):
    return {"terminado": terminado, "duracion_s": duracion, "riesgo_max": riesgo, "frenadas": frenadas}


def test_veredicto_semaforo_mas_seguro_con_espera_corta():
    c = comparar_viajes(_resumen(40, 70, 2), _resumen(55, 20, 0))
    assert c["tono"] == "bueno" and c["diferencia_s"] == 15
    assert "15 s más" in c["veredicto"] and "bajó de 70 a 20" in c["veredicto"]


def test_veredicto_semaforo_solo_agrega_espera():
    c = comparar_viajes(_resumen(40, 20, 0), _resumen(80, 22, 0))
    assert c["tono"] == "malo" and "sin una mejora clara" in c["veredicto"]


def test_veredicto_sin_diferencias_no_afirma_mejoras():
    c = comparar_viajes(_resumen(100, 100, 1), _resumen(101, 100, 1))
    assert c["tono"] == "neutro" and "no cambió ni el tiempo ni el riesgo" in c["veredicto"]


def test_viaje_usa_la_espera_acumulada_de_sumo():
    v = acumular_viaje(None, {"velocidad_kmh": 30, "espera_acum_s": 7.5}, t=0, dt=4)
    assert resumen_viaje(v, True)["detenido_s"] == 7.5


def test_veredicto_sin_datos_o_viaje_incompleto():
    assert comparar_viajes(None, _resumen(1, 1, 0))["diferencia_s"] is None
    assert "parciales" in comparar_viajes(_resumen(1, 1, 0), _resumen(1, 1, 0, terminado=False))["veredicto"]


def test_balance_por_hora():
    b = nuevo_balance()
    # 30 min con un carro frenando en seco en la principal y dos detenidos en la lateral
    actualizar_balance(b, [("p1", 8.0, -6.0, 0.0, "principal"), ("l1", 0.0, 0.0, 20.0, "lateral"),
                           ("l2", 0.1, 0.0, 10.0, "lateral")], dt=900)
    actualizar_balance(b, [("p1", 4.0, -6.0, 0.0, "principal"), ("l1", 0.0, 0.0, 40.0, "lateral")], dt=900)
    r = resumen_balance(b, conflictos=3, colisiones=0)
    assert r["minutos"] == 30.0
    assert r["frenadas_hora"] == 2 and r["frenadas_principal_hora"] == 2   # la misma frenada no se cuenta dos veces
    assert r["conflictos_hora"] == 6
    assert r["cola_max_lateral"] == 2 and r["cola_max_principal"] == 0
    assert r["espera_lateral_s"] == 25.0   # (40 + 10) / 2: la mayor espera de cada vehículo
