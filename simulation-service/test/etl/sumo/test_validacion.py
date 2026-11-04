import json

import pytest

from etl.sumo.validacion import (
    PERIODO_BIN_S, ValidacionConfig, _hora_pico, escribir_conteos, geh, leer_conteos, periodo_de, validar,
)


def test_geh_valores_conocidos():
    assert geh(100, 100) == 0
    assert geh(0, 0) == 0
    # M=150, C=100: sqrt(2*2500/250) = sqrt(20)
    assert geh(150, 100) == pytest.approx(20 ** 0.5)
    assert geh(150, 100) == geh(100, 150)


def test_periodo_de():
    assert periodo_de(7 * 3600) == "AM"
    assert periodo_de(16 * 3600) == "PM"


def test_hora_pico_toma_cuatro_cuartos_seguidos():
    t0 = 25200
    serie = {t0 + k * PERIODO_BIN_S: v for k, v in enumerate([1, 10, 10, 10, 10, 1])}
    inicio, total = _hora_pico(serie)
    assert inicio == t0 + PERIODO_BIN_S and total == 40
    assert _hora_pico({}) == (None, 0.0)


def _conteos(path, datos):
    """datos: {modo: {edge: {inicio: entered}}} -> XML como el de SUMO."""
    lineas = ["<meandata>"]
    for modo, edges in datos.items():
        inicios = sorted({t for serie in edges.values() for t in serie})
        for t in inicios:
            lineas.append(f'<interval begin="{t}" end="{t + PERIODO_BIN_S}" id="conteo_{modo}">')
            for edge, serie in edges.items():
                if t in serie:
                    lineas.append(f'<edge id="{edge}" entered="{serie[t]}"/>')
            lineas.append("</interval>")
    lineas.append("</meandata>")
    path.write_text("\n".join(lineas), encoding="utf-8")
    return path


def test_validar(tmp_path):
    aforos = tmp_path / "aforos.json"
    aforos.write_text(json.dumps({"puntos": [
        {"id": "TP_1", "direccion": "A X B", "sentido": "N-S", "edge": "e1", "lon": 0, "lat": 0,
         "volumenes": {"AM": {"auto": 80, "moto": 20, "bus": 999}}},
        {"id": "TP_2", "direccion": "C X D", "sentido": "S-N", "edge": "e2", "lon": 0, "lat": 0,
         "volumenes": {"AM": {"auto": 1000}}},
        {"id": "TPU_3", "direccion": "E X F", "sentido": "S-N", "edge": "e3", "lon": 0, "lat": 0,
         "volumenes": {"AM": {"bus": 500}}},
        {"id": "TP_4", "direccion": "G X H", "sentido": "S-N", "edge": "e4", "lon": 0, "lat": 0,
         "volumenes": {"PM": {"auto": 10}}},
    ]}), encoding="utf-8")
    t0 = 25200
    conteos = _conteos(tmp_path / "c.xml", {
        "auto": {"e1": {t0 + k * PERIODO_BIN_S: 20 for k in range(8)}, "e2": {t0: 10}},
        "moto": {"e1": {t0 + k * PERIODO_BIN_S: 5 for k in range(8)}},
    })
    resumen = validar(ValidacionConfig(conteos=conteos, destino=tmp_path / "v.json", destino_csv=tmp_path / "v.csv",
                                       aforos=aforos)).resumen
    filas = {f["id"]: f for f in resumen["filas"]}
    # el bus no se simula: ni se compara en TP_1 ni cuenta la estación de transporte público
    assert set(filas) == {"TP_1", "TP_2"}
    assert filas["TP_1"]["simulado"] == 100 and filas["TP_1"]["real"] == 100 and filas["TP_1"]["cumple"]
    assert not filas["TP_2"]["cumple"]
    assert resumen["porcentaje"] == 50.0 and not resumen["cumple_criterio"]
    assert "TPU_3" in resumen["estaciones_no_simuladas"]
    assert (tmp_path / "v.csv").read_text(encoding="utf-8").startswith("id,direccion")


def test_escribir_y_leer_conteos(tmp_path):
    add = escribir_conteos([{"edge": "b"}, {"edge": "a"}], tmp_path / "c.add.xml", tmp_path / "c.xml", 25200, 36000)
    texto = add.read_text(encoding="utf-8")
    assert 'edges="a b"' in texto and 'id="conteo_auto"' in texto and 'vTypes="auto informal otro auto_enc informal_enc otro_enc"' in texto
    _conteos(tmp_path / "c.xml", {"moto": {"a": {25200: 3}}})
    assert leer_conteos(tmp_path / "c.xml")["moto"]["a"][25200.0] == 3
