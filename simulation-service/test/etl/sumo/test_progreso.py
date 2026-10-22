import sys
import threading
import time

import pytest

from etl.sumo.kepler import KeplerTripsConfig, convert_fcd_to_kepler_trips
from etl.sumo.proceso import Cancelado, avance_ventana, ejecutar, ultimo_depart


def test_avance_ventana_acotado():
    assert avance_ventana(25200) == 0.0
    assert avance_ventana(30600) == pytest.approx(0.5)
    assert avance_ventana(40000) == 1.0


def test_ultimo_depart(tmp_path):
    rutas = tmp_path / "r.rou.xml"
    assert ultimo_depart(rutas) is None   # aún no existe

    rutas.write_text(
        '<routes><vehicle id="a" depart="25200.00"/>'
        + '<x/>' * 30000   # más grande que la cola que se lee
        + '<person id="p" depart="30600.00"/><vehicle id="b" depart="31000.50">',
        encoding="utf-8",
    )
    assert ultimo_depart(rutas) == 31000.5


def test_ejecutar_sondea_avance():
    avances = iter([0.1, 0.1, 0.5, 0.9])
    vistos = []

    salida = ejecutar(
        [sys.executable, "-c", "import time; time.sleep(1.2)"],
        sondear=lambda: next(avances, 0.9),
        on_avance=vistos.append,
        intervalo=0.2,
    )

    assert salida.returncode == 0
    assert vistos == [0.1, 0.5, 0.9]   # solo cuando cambia


def test_ejecutar_cancelado_termina_el_proceso():
    cancelar = threading.Event()
    threading.Timer(0.3, cancelar.set).start()
    inicio = time.monotonic()

    with pytest.raises(Cancelado):
        ejecutar([sys.executable, "-c", "import time; time.sleep(30)"], cancelar=cancelar, intervalo=0.1)

    assert time.monotonic() - inicio < 5


FCD = "<fcd-export>" + "".join(
    f'<timestep time="{25200 + i}"><vehicle id="auto_1" x="{-74.03 - i * 1e-4}" y="4.70" z="2560" angle="90" type="auto"/></timestep>'
    for i in range(450)
) + "</fcd-export>"


def test_exportar_kepler_reporta_avance(tmp_path):
    fcd = tmp_path / "fcd.xml"
    fcd.write_text(FCD, encoding="utf-8")
    avances = []

    convert_fcd_to_kepler_trips(KeplerTripsConfig(fcd, tmp_path / "t.geojson"), on_avance=avances.append)

    assert len(avances) >= 3   # cada 200 timesteps + final
    assert avances == sorted(avances)
    assert avances[-1] == 1.0


def test_exportar_kepler_cancelado(tmp_path):
    fcd = tmp_path / "fcd.xml"
    fcd.write_text(FCD, encoding="utf-8")
    cancelar = threading.Event()
    cancelar.set()

    with pytest.raises(Cancelado):
        convert_fcd_to_kepler_trips(KeplerTripsConfig(fcd, tmp_path / "t.geojson"), cancelar=cancelar)
