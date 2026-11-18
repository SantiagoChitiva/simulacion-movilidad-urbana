from etl.sumo.encuesta_completa import (
    EncuestaCompletaStats, Puerta, _es_usaquen, reparto_puertas, viajes_complemento,
)
from etl.sumo.trips import radio_redondeo, salidas_dispersas
from etl.sumo.enums.transport_mode import TransportMode
from etl.sumo.trips import TripRecord


def test_es_usaquen_tolera_tildes_y_espacios():
    assert _es_usaquen(" Usaquen ") and _es_usaquen("USAQUÉN") and not _es_usaquen("Teusaquillo")


def test_radio_segun_el_redondeo_de_la_hora():
    assert radio_redondeo(25200) == 1800 and radio_redondeo(27000) == 900 and radio_redondeo(25440) == 300


def test_salidas_dispersas_parejas_y_dentro_de_la_ventana():
    salidas = salidas_dispersas(28800.0, 4, 25200, 36000)        # 8:00 en punto: 7:30-8:30
    assert len(salidas) == 4 and min(salidas) > 27000 and max(salidas) < 30600
    assert abs(sum(salidas) / 4 - 28800) < 1e-6
    borde = salidas_dispersas(25200.0, 10, 25200, 36000)         # 7:00 al abrir la ventana
    assert min(borde) >= 25200 and max(borde) < 27000 and len(borde) == 10
    assert salidas_dispersas(5.0, 1, 0, 10) == [5.0]


def test_reparto_puertas_pondera_por_carriles_y_distancia():
    cerca = Puerta("a", "entra", 0, 0, 3)            # a 100 m
    casi = Puerta("b", "entra", 0, 100, 1)           # a 200 m
    lejos = [Puerta(f"l{i}", "entra", 0, 5000 + i, 2) for i in range(3)]
    reparto = dict((p.edge, w) for p, w in reparto_puertas(0, -100, [cerca, casi, *lejos]))
    assert len(reparto) == 4 and abs(sum(reparto.values()) - 1) < 1e-9
    assert reparto["a"] > reparto["b"] > reparto["l0"]
    assert abs(reparto["a"] / reparto["b"] - 12) < 1e-6   # 3/100² frente a 1/200²


def test_complemento_entra_sale_y_tope():
    puertas = [Puerta("pe", "entra", 0, 0, 1), Puerta("ps", "sale", 0, 0, 1)]
    centroides = {"10": (0, -1000), "1": (0, 1000)}
    externos = [
        {"modo": "auto", "sale_de_usaquen": False, "zat_ori": "10", "zat_des": "1", "hora_s": 25200,
         "duracion_s": 1200, "copias": 3},
        {"modo": "moto", "sale_de_usaquen": True, "zat_ori": "1", "zat_des": "10", "hora_s": 25200,
         "duracion_s": 600, "copias": 2},
        {"modo": "auto", "sale_de_usaquen": True, "zat_ori": "99", "zat_des": "10", "hora_s": 0,
         "duracion_s": 0, "copias": 1},   # ZAT interna fuera de las TAZ
    ]
    internos = [TripRecord(26000, TransportMode.AUTO, 50, "1", "1", fexp=53.4),
                TripRecord(26000, TransportMode.PEATON, 50, "1", "1", fexp=80)]
    stats = EncuestaCompletaStats()
    viajes = viajes_complemento(externos, internos, centroides, puertas, {"1"}, stats)
    entran = [v for v in viajes if v["fromTaz"] == "puerta_entra_pe"]
    assert len(entran) == 3 and all(v["toTaz"] == "1" for v in entran)
    # entra a la red a mitad del viaje (la puerta está a medio camino): 25200 + 600 s
    assert abs(sum(v["depart"] for v in entran) / 3 - 25800) < 1e-6
    assert sum(v["toTaz"] == "puerta_sale_ps" for v in viajes) == 2
    assert stats.sin_zat == 1
    assert stats.por_tipo == {"entra": 3, "sale": 2, "tope": 3}   # 53 - 50 copias, solo vehículos
