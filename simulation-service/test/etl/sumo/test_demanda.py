import xml.etree.ElementTree as ET
from collections import Counter

import pytest

from etl.sumo.configuration import ScenarioPaths
from etl.sumo.demanda import (
    MOTORIZADOS, PARTICULARES, DemandaConfig, Preset, asignar, cargar_dia, cargar_ventana,
    conteos_preset, mayor_resto,
)
from etl.sumo.enums.transport_mode import TransportMode as M
from etl.sumo.trips import TripGenerationConfig, generate_trips

TSV = ScenarioPaths.from_name().tsv


@pytest.fixture(scope="module")
def encuesta():
    return cargar_ventana(TSV), cargar_dia(TSV)


def _clave(t):
    return (t.depart, t.mode.value, t.copies, t.origin_taz, t.destination_taz)


def test_mayor_resto_conserva_total():
    assert mayor_resto([1, 1, 1], 10) == [4, 3, 3]
    assert sum(mayor_resto([0.2, 5.7, 3.3, 0.8], 7)) == 7
    assert mayor_resto([1, 2], 0) == [0, 0]


def test_preset_encuesta_reproduce_copias(encuesta):
    ventana, dia = encuesta
    conteos = conteos_preset(Preset.ENCUESTA, ventana, dia)
    salida = asignar(ventana, dia, DemandaConfig(Preset.ENCUESTA, conteos))

    assert sorted(map(_clave, salida)) == sorted(map(_clave, ventana))


@pytest.mark.parametrize("preset", list(Preset))
def test_presets_conservan_total(encuesta, preset):
    ventana, dia = encuesta
    total_encuesta = sum(t.copies for t in ventana)

    assert sum(conteos_preset(preset, ventana, dia).values()) == total_encuesta


def test_dia_sin_carro_sin_particulares(encuesta):
    conteos = conteos_preset(Preset.DIA_SIN_CARRO, *encuesta)

    assert all(conteos[m] == 0 for m in PARTICULARES)
    base = conteos_preset(Preset.ENCUESTA, *encuesta)
    assert conteos[M.BICI] > base[M.BICI]
    assert conteos[M.TRANSPORTE_PUBLICO] > base[M.TRANSPORTE_PUBLICO]


def test_mas_vehiculos_supera_a_peatones(encuesta):
    conteos = conteos_preset(Preset.MAS_VEHICULOS, *encuesta)
    vehiculos = sum(conteos[m] for m in MOTORIZADOS)

    assert vehiculos > conteos[M.PEATON] + conteos[M.TRANSPORTE_PUBLICO]


def test_mas_peatones_aumenta_activos(encuesta):
    base = conteos_preset(Preset.ENCUESTA, *encuesta)
    conteos = conteos_preset(Preset.MAS_PEATONES, *encuesta)

    assert conteos[M.PEATON] > base[M.PEATON]
    assert conteos[M.AUTO] < base[M.AUTO]


def test_conteos_del_usuario_se_cumplen(encuesta):
    pedido = {M.BICI: 3000, M.PEATON: 123, M.AUTO: 0}
    salida = asignar(*encuesta, DemandaConfig(Preset.DIA_SIN_CARRO, pedido))

    por_modo = Counter()
    for t in salida:
        por_modo[t.mode] += t.copies
    assert por_modo == Counter({M.BICI: 3000, M.PEATON: 123})


def test_autos_en_dia_sin_carro_usan_viajes_de_la_encuesta(encuesta):
    ventana, dia = encuesta
    salida = asignar(ventana, dia, DemandaConfig(Preset.DIA_SIN_CARRO, {M.AUTO: 40}))

    assert sum(t.copies for t in salida) == 40
    origenes_auto = {(t.origin_taz, t.destination_taz) for t in ventana if t.mode == M.AUTO}
    assert {(t.origin_taz, t.destination_taz) for t in salida} <= origenes_auto


def test_generate_trips_con_demanda(tmp_path):
    out = tmp_path / "out.trips.xml"
    demanda = DemandaConfig(Preset.DIA_SIN_CARRO, {M.BICI: 10, M.TAXI: 5, M.PEATON: 7})

    result = generate_trips(TripGenerationConfig(TSV, out, demanda=demanda))

    root = ET.parse(out).getroot()
    tipos = Counter(e.get("type") for e in root if e.tag == "trip")
    assert tipos == Counter({"bici": 10, "taxi": 5})
    assert sum(1 for e in root if e.tag == "person") == 7
    departs = [float(e.get("depart")) for e in root if e.tag in ("trip", "person")]
    assert departs == sorted(departs)
    assert result.stats.por_modo == Counter({"bici": 10, "taxi": 5, "peaton": 7})
