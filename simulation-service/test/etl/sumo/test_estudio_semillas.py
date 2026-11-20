import xml.etree.ElementTree as ET

import pytest

from etl.sumo.comparacion_programas import ComparacionProgramaConfig, centro_nodos, leer_conflictos
from etl.sumo.demanda_zona import variar_salidas
from etl.sumo.estudio_semillas import diferencia_pareada, resumir_cruce, t95, veredicto


def test_variar_salidas_conserva_viajes_y_reordena(tmp_path):
    rou = tmp_path / "zona.rou.xml"
    rou.write_text(
        '<routes><vType id="x"/>'
        '<vehicle id="a" depart="25200.00"><route edges="e"/></vehicle>'
        '<person id="p" depart="25210.00"><walk edges="e"/></person>'
        '<vehicle id="b" depart="25220.00"><route edges="e"/></vehicle>'
        '<vehicle id="t" depart="triggered"><route edges="e"/></vehicle></routes>', encoding="utf-8",
    )
    uno = variar_salidas(rou, tmp_path / "s1.rou.xml", semilla=1, inicio=25200, fin=28800)
    raiz = ET.parse(uno).getroot()
    entidades = [e for e in raiz if e.tag in ("vehicle", "person") and e.get("depart") != "triggered"]
    salidas = [float(e.get("depart")) for e in entidades]
    assert {e.get("id") for e in entidades} == {"a", "p", "b"}
    assert salidas == sorted(salidas) and all(25200 <= s < 28800 for s in salidas)
    assert all(abs(float(e.get("depart")) - {"a": 25200, "p": 25210, "b": 25220}[e.get("id")]) <= 300 for e in entidades)
    assert raiz[0].tag == "vType" and raiz.find("vehicle[@id='t']") is not None
    # misma semilla, mismo resultado; otra semilla, otras salidas
    assert uno.read_text() == variar_salidas(rou, tmp_path / "s1b.rou.xml", semilla=1, inicio=25200, fin=28800).read_text()
    assert uno.read_text() != variar_salidas(rou, tmp_path / "s2.rou.xml", semilla=2, inicio=25200, fin=28800).read_text()


def test_leer_conflictos_cuenta_pares_una_vez_y_solo_cerca(tmp_path):
    ssm = tmp_path / "ssm.xml"
    ssm.write_text(
        "<SSMLog>"
        # el mismo encuentro registrado por los dos vehículos: cuenta una vez
        '<conflict begin="10" end="12" ego="a" foe="b"><minTTC time="11" position="5,5" type="2" value="1.0"/>'
        '<maxDRAC time="11" position="5,5" value="2.0"/><PET time="NA" position="NA" value="NA"/></conflict>'
        '<conflict begin="11" end="12" ego="b" foe="a"><minTTC time="11" position="5,5" type="3" value="1.2"/>'
        '<maxDRAC time="11" position="5,5" value="NA"/><PET time="NA" position="NA" value="NA"/></conflict>'
        # PET grave cerca
        '<conflict begin="40" end="41" ego="c" foe="d"><minTTC time="NA" position="NA" value="NA"/>'
        '<maxDRAC time="NA" position="NA" value="NA"/><PET time="40" position="-20,10,2600.5" type="17" value="0.8"/></conflict>'
        # grave pero lejos del cruce
        '<conflict begin="50" end="51" ego="e" foe="f"><minTTC time="50" position="300,0" value="0.5"/>'
        '<maxDRAC time="50" position="300,0" value="5.0"/><PET time="NA" position="NA" value="NA"/></conflict>'
        # registrado pero no grave
        '<conflict begin="60" end="61" ego="g" foe="h"><minTTC time="60" position="1,1" value="2.5"/>'
        '<maxDRAC time="60" position="1,1" value="1.0"/><PET time="NA" position="NA" value="NA"/></conflict>'
        "</SSMLog>", encoding="utf-8",
    )
    cerca = leer_conflictos(ssm, (0.0, 0.0))
    assert cerca == {"conflictos": 2, "conflictos_cruce": 1, "conflictos_alcance": 1,
                     "conflictos_ttc": 1, "conflictos_drac": 0, "conflictos_pet": 1}
    toda_la_zona = leer_conflictos(ssm, None)
    assert toda_la_zona["conflictos"] == 3 and toda_la_zona["conflictos_drac"] == 1
    assert leer_conflictos(tmp_path / "no_existe.xml", (0, 0))["conflictos"] == 0


def test_centro_nodos(tmp_path):
    net = tmp_path / "zona.net.xml"
    net.write_text('<net><junction id="n1" x="0" y="0"/><junction id="n2" x="10" y="4"/>'
                   '<junction id="otro" x="99" y="99"/></net>', encoding="utf-8")
    assert centro_nodos(net, ["n1", "n2"]) == (5.0, 2.0)
    assert centro_nodos(net, ["nada"]) is None


def test_args_ssm_solo_si_se_pide(tmp_path):
    base = dict(zona_net=tmp_path / "n.xml", demanda=[tmp_path / "r.xml"], vtypes=tmp_path / "v.xml",
                accesos=[], destino_dir=tmp_path)
    assert "--device.ssm.probability" not in ComparacionProgramaConfig(**base).to_args([])
    args = ComparacionProgramaConfig(**base, ssm=True).to_args([])
    assert args[args.index("--device.ssm.measures") + 1] == "TTC DRAC PET"
    assert args[args.index("--device.ssm.thresholds") + 1] == "1.5 3.35 1.5"


def test_diferencia_pareada_y_t95():
    r = diferencia_pareada([10, 10, 10, 10], [8, 9, 7, 8])
    assert r["diferencia"] == -2.0 and r["mejora_en"] == 4 and r["empeora_en"] == 0
    assert r["ic95"][1] < 0
    assert t95(29) == pytest.approx(2.045) and t95(100) == 1.96 and t95(11) == 2.228


def _resumen(cruce_ic, total_ic, demora_dif, demora_ic):
    return {"conflictos_cruce": {"n": 30, "ic95": cruce_ic}, "conflictos": {"n": 30, "ic95": total_ic},
            "demora_media_s": {"n": 30, "diferencia": demora_dif, "ic95": demora_ic}}


def test_veredicto():
    assert veredicto(_resumen([-3, -1], [-4, 0], 4, [3, 5])) == "conviene"
    assert veredicto(_resumen([-3, -1], [-4, 0], 25, [20, 30])) == "conviene_con_costo"
    assert veredicto(_resumen([-3, -1], [2, 9], 4, [3, 5])) == "conviene"   # más alcances: se reportan, no deciden
    assert veredicto(_resumen([-1, 1], [2, 9], 4, [3, 5])) == "no_conviene"
    assert veredicto(_resumen([-1, 1], [-1, 1], 4, [3, 5])) == "no_se_justifica"
    assert veredicto(_resumen([-1, 1], [-1, 1], 0.5, [-1, 2])) == "indiferente"
    assert veredicto({}) == "sin_datos"


def test_resumir_cruce_empareja_por_semilla():
    filas = []
    for k in range(1, 6):
        filas.append({"semilla": str(k), "lado": "sin", "conflictos": "5", "conflictos_cruce": str(4 + k % 2),
                      "demora_media_s": "16.0"})
        filas.append({"semilla": str(k), "lado": "con", "conflictos": "2", "conflictos_cruce": "1",
                      "demora_media_s": "20.0"})
    filas.append({"semilla": "6", "lado": "sin", "conflictos": "9", "demora_media_s": "16.0"})  # sin pareja: no cuenta
    r = resumir_cruce(filas)
    assert r["conflictos"]["n"] == 5 and r["conflictos"]["diferencia"] == -3.0
    assert r["demora_media_s"]["diferencia"] == 4.0
    assert r["veredicto"] == "conviene"
