"""Pruebas de las piezas nuevas: semillas, ventana, transporte público, tráfico de paso y asignación."""
import io
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import pytest

from etl.sumo.asignacion import AsignacionConfig
from etl.sumo.comparacion_programas import agregar_semillas
from etl.sumo.configuration import VENTANAS, ScenarioPaths, escribir_sumocfg_corrida
from etl.sumo.demanda import DemandaConfig
from etl.sumo.enums.transport_mode import TransportMode
from etl.sumo.semaforo_nuevo import luces_por_fase
from etl.sumo.trafico_paso import metas
from etl.sumo.transporte_publico import TransportePublicoConfig, filtrar_gtfs, servicios_activos
from etl.sumo.trips import TripRecord, _build_xml, TripGenerationStats


def test_agregar_semillas_media_y_rango():
    r = agregar_semillas([{"demora_media_s": 10.0, "vehiculos": 100}, {"demora_media_s": 14.0, "vehiculos": 110}])
    assert r["demora_media_s"] == 12 and r["vehiculos"] == 105
    assert r["rangos"]["demora_media_s"] == [10.0, 14.0] and r["repeticiones"] == 2


def test_luces_por_fase():
    luces = luces_por_fase(["GGrr", "yyrr", "rrGg"], {"a": [0, 1], "b": [2, 3]})
    assert luces == [{"a": "verde", "b": "rojo"}, {"a": "rojo", "b": "rojo"}, {"a": "rojo", "b": "verde"}]


def test_demanda_ventana():
    assert DemandaConfig().horas == VENTANAS["am"]
    assert DemandaConfig(ventana="pm").horas == (16 * 3600, 19 * 3600)


def test_sumocfg_con_ventana_y_rutas_extra(tmp_path, monkeypatch):
    base = ScenarioPaths.from_name()
    paths = ScenarioPaths(**{**base.__dict__, "run_dir": tmp_path, "sumocfg": tmp_path / "s.sumocfg",
                              "routes": tmp_path / "r.rou.xml"})
    cfg = escribir_sumocfg_corrida(paths, route_files=[tmp_path / "paso.rou.xml.gz"], ventana=(57600, 68400),
                                   max_vehiculos=25000)
    raiz = ET.parse(cfg).getroot()
    assert raiz.find("time/begin").get("value") == "57600" and raiz.find("time/end").get("value") == "68400"
    assert raiz.find("input/route-files").get("value").endswith("paso.rou.xml.gz")
    assert raiz.find("processing/max-num-vehicles").get("value") == "25000"


def test_transporte_publico_como_person_trip():
    viaje = TripRecord(depart=25200, mode=TransportMode.TRANSPORTE_PUBLICO, copies=1, origin_taz="1", destination_taz="2")
    con = ET.tostring(_build_xml([viaje], TripGenerationStats(), transporte_publico_real=True).getroot(), encoding="unicode")
    sin = ET.tostring(_build_xml([viaje], TripGenerationStats()).getroot(), encoding="unicode")
    assert 'modes="public"' in con and "<personTrip" in con
    assert "<walk" in sin and "personTrip" not in sin


def _gtfs(path: Path) -> Path:
    archivos = {
        "agency.txt": "agency_id,agency_name\n1,Troncal\n3,Zonal\n",
        "calendar.txt": "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n"
                        "1,1,1,1,1,1,0,0,20260101,20261231\n2,0,0,0,0,0,1,0,20260101,20261231\n",
        "calendar_dates.txt": "service_id,date,exception_type\n",
        "routes.txt": "agency_id,route_id,route_short_name,route_type\n1,R1,B1,3\n3,R2,Z2,3\n",
        "trips.txt": "route_id,service_id,shape_id,trip_id\nR1,1,S1,t1\nR2,1,S2,t2\nR2,2,S2,t3\n",
        "stops.txt": "stop_id,stop_lat,stop_lon\nA,4.70,-74.03\nB,4.71,-74.03\nC,4.60,-74.10\n",
        "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n"
                          "t1,07:00:00,07:00:00,A,1\nt1,07:05:00,07:05:00,B,2\n"
                          "t2,07:10:00,07:10:00,A,1\nt2,07:15:00,07:15:00,B,2\nt2,07:30:00,07:30:00,C,3\n"
                          "t3,07:00:00,07:00:00,A,1\nt3,07:05:00,07:05:00,B,2\n",
        "shapes.txt": "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\nS2,4.7,-74.03,1\nS1,4.7,-74.03,1\n",
    }
    with zipfile.ZipFile(path, "w") as zf:
        for nombre, texto in archivos.items():
            zf.writestr(nombre, texto)
    return path


def test_filtrar_gtfs(tmp_path):
    cfg = TransportePublicoConfig(gtfs=_gtfs(tmp_path / "g.zip"), destino_dir=tmp_path, fecha="20260506",
                                  bbox=(-74.06, 4.66, -74.0, 4.85), agencias=("3",))
    with zipfile.ZipFile(cfg.gtfs) as zf:
        assert servicios_activos(zf, "20260506") == {"1"}   # miércoles
    filtrar_gtfs(cfg)
    with zipfile.ZipFile(cfg.gtfs_reducido) as zf:
        viajes = zf.read("trips.txt").decode()
        horarios = zf.read("stop_times.txt").decode()
    # t1 es troncal y t3 es de sábado; de t2 queda solo lo que está dentro de la caja
    assert "t2" in viajes and "t1" not in viajes and "t3" not in viajes
    assert ",C," not in horarios and horarios.count("t2") == 2


def test_metas_trafico_paso(monkeypatch):
    monkeypatch.setattr("etl.sumo.trafico_paso.grupo_estacion", lambda _id: "calibracion")
    puntos = [{"id": "TP_1", "edge": "e", "volumenes": {"AM": {"auto": 1000, "moto": 50}}}]
    internos = {"auto": {"e": {25200.0: 100, 26100.0: 100, 27000.0: 100, 27900.0: 100}}}
    m = metas(puntos, internos, "AM", 25200, 32400)
    assert m["auto"][("e", 25200)] == 600 and m["auto"][("e", 28800)] == 1000
    assert m["moto"][("e", 25200)] == 50


def test_asignacion_args(tmp_path):
    cfg = AsignacionConfig(tmp_path / "n.net.xml", tmp_path / "t.trips.xml", tmp_path / "taz.xml",
                           tmp_path / "r.rou.xml", iteraciones=4, ventana=(57600, 68400))
    args = cfg.to_args("duaIterate.py")
    assert args[args.index("-l") + 1] == "4" and args[args.index("-b") + 1] == "57600"
    assert "--mesosim" in args
    # las TAZ llegan a duarouter solo con -D; duaIterate ya le pasa --ignore-errors y --no-warnings
    # y repetirlos hace fallar al router ("A value for the option ... was already set")
    assert args[args.index("-D") + 1].endswith("taz.xml") and "-+" not in args
    assert "duarouter--ignore-errors" not in args and "duarouter--no-warnings" not in args
    assert "--continue-on-unbuild" in args
    # las opciones sumo--/duarouter-- van al final
    assert all(not a.startswith("-") or a.startswith(("sumo--", "duarouter--")) for a in args[args.index("--mesosim") + 1:]
               if a.startswith("-"))
