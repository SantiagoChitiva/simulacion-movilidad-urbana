import xml.etree.ElementTree as ET

from etl.sumo.trips import TripGenerationConfig, generate_trips

HEADER = "hora_ini_seg\tmodo_principal_agrupado\tfexp_vj\tzat_ori\tzat_des\n"
# filas desordenadas por hora, como viene el TSV de la encuesta
ROWS = [
    "27000\tAUTO\t1\t10\t20\n",
    "25300\tA PIE <15 MIN\t2\t11\t21\n",
    "26000\tBICICLETA\t1\t12\t22\n",
    "40000\tAUTO\t1\t13\t23\n",   # fuera de la ventana 07:00-10:00
]


def test_trips_sorted_by_departure(tmp_path):
    tsv = tmp_path / "viajes.tsv"
    tsv.write_text(HEADER + "".join(ROWS), encoding="utf-8")
    out = tmp_path / "out.trips.xml"

    result = generate_trips(TripGenerationConfig(tsv, out))

    root = ET.parse(out).getroot()
    departs = [float(e.get("depart")) for e in root if e.tag in ("trip", "person")]
    # SUMO descarta todo depart menor al máximo ya leído: debe salir ordenado
    assert departs == sorted(departs)
    assert departs == [25300, 25300, 26000, 27000]
    assert result.stats.fuera_de_ventana == 1
    assert result.stats.viajes_generados == 4
