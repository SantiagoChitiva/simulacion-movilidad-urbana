"""
Sesiones de simulación 3D en vivo controladas por TraCI.

Fase E: cada sesión abre SUMO con TraCI en un puerto libre, suscribe vehículos,
personas y semáforos y emite frames por WebSocket. El cliente puede pausar, cambiar
la velocidad y editar el programa del semáforo en tiempo real.

Límites:
- Máximo MAX_SESIONES simultáneas (por consumo de recursos).
- Timeout de TIMEOUT_SIN_ACTIVIDAD segundos sin mensajes del cliente → la sesión se cierra.
"""
import asyncio
import json
import logging
import subprocess
import tempfile
import threading
import time
import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from etl.sumo.configuration import DEFAULT_SCENARIO, RUNS_DIR, ScenarioPaths
from etl.sumo.programas_tls import ProgramaTLS, escribir_programa

logger = logging.getLogger(__name__)

MAX_SESIONES = 2
TIMEOUT_SIN_ACTIVIDAD = 120.0   # segundos
_PASOS_POR_SEGUNDO = 5          # cuántos pasos de simulación por segundo de tiempo real


@dataclass
class EstadoSesion:
    sid: str
    tl_id: str
    escenario_run_id: str | None
    programa_id: str
    creada: float = field(default_factory=time.monotonic)
    ultimo_ping: float = field(default_factory=time.monotonic)
    pausada: bool = False
    velocidad: float = 1.0
    tiempo_sim: float = 0.0
    activa: bool = True


class GestorSesiones:
    """Gestiona las sesiones 3D activas; máximo MAX_SESIONES simultáneas."""

    def __init__(self) -> None:
        self._sesiones: dict[str, EstadoSesion] = {}
        self._lock = threading.Lock()

    def crear(self, tl_id: str, escenario_run_id: str | None, programa_id: str) -> EstadoSesion:
        with self._lock:
            self._limpiar_expiradas()
            if len(self._sesiones) >= MAX_SESIONES:
                raise RuntimeError(
                    f"Ya hay {MAX_SESIONES} sesiones 3D activas. "
                    "Cierra una antes de abrir otra."
                )
            sid = uuid.uuid4().hex[:12]
            sesion = EstadoSesion(
                sid=sid,
                tl_id=tl_id,
                escenario_run_id=escenario_run_id,
                programa_id=programa_id,
            )
            self._sesiones[sid] = sesion
            return sesion

    def obtener(self, sid: str) -> EstadoSesion | None:
        return self._sesiones.get(sid)

    def cerrar(self, sid: str) -> None:
        with self._lock:
            sesion = self._sesiones.pop(sid, None)
            if sesion:
                sesion.activa = False

    def _limpiar_expiradas(self) -> None:
        ahora = time.monotonic()
        expiradas = [
            sid for sid, s in self._sesiones.items()
            if ahora - s.ultimo_ping > TIMEOUT_SIN_ACTIVIDAD
        ]
        for sid in expiradas:
            self._sesiones.pop(sid).activa = False

    def listar(self) -> list[dict]:
        with self._lock:
            self._limpiar_expiradas()
            return [
                {
                    "sid": s.sid,
                    "tl_id": s.tl_id,
                    "escenario_run_id": s.escenario_run_id,
                    "pausada": s.pausada,
                    "velocidad": s.velocidad,
                    "tiempo_sim": s.tiempo_sim,
                }
                for s in self._sesiones.values()
            ]


# ─────────────────────────────────────── preparación de archivos

def _preparar_sumocfg(
    tl_id: str,
    escenario_run_id: str | None,
    programa_id: str,
    programa_tls: ProgramaTLS | None,
    trabajo_dir: Path,
) -> Path:
    """Prepara el sumocfg para la sesión 3D.

    Si hay un ProgramaTLS personalizado, escribe el additional.xml en trabajo_dir
    e incluye ese archivo en el sumocfg.
    """
    if escenario_run_id and (RUNS_DIR / escenario_run_id / "zona.net.xml").is_file():
        zona_net = RUNS_DIR / escenario_run_id / "zona.net.xml"
        zona_rou = RUNS_DIR / escenario_run_id / "zona.rou.xml"
    else:
        # fallback: usar la red completa del escenario por defecto
        paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
        zona_net = paths.net
        zona_rou = paths.routes if paths.routes.is_file() else None

    trabajo_dir.mkdir(parents=True, exist_ok=True)
    additional_files = []

    if programa_tls is not None:
        additional_xml = trabajo_dir / f"programa_{programa_id}.xml"
        escribir_programa(programa_tls, additional_xml)
        additional_files.append(str(additional_xml))

    # Generar el sumocfg mínimo
    import xml.etree.ElementTree as ET
    raiz = ET.Element("configuration")
    entrada = ET.SubElement(raiz, "input")
    ET.SubElement(entrada, "net-file", value=str(zona_net.resolve()))
    if zona_rou is not None and zona_rou.is_file():
        ET.SubElement(entrada, "route-files", value=str(zona_rou.resolve()))
    if additional_files:
        ET.SubElement(entrada, "additional-files", value=",".join(additional_files))

    tiempo = ET.SubElement(raiz, "time")
    from etl.sumo.configuration import HORA_INI, HORA_FIN
    ET.SubElement(tiempo, "begin", value=str(HORA_INI))
    ET.SubElement(tiempo, "end", value=str(HORA_FIN))

    salida_cfg = trabajo_dir / "sesion3d.sumocfg"
    tree = ET.ElementTree(raiz)
    ET.indent(tree, space="  ")
    tree.write(str(salida_cfg), encoding="UTF-8", xml_declaration=True)
    return salida_cfg


# ─────────────────────────────────────── loop TraCI asíncrono

async def ejecutar_sesion(
    sesion: EstadoSesion,
    programa_tls: ProgramaTLS | None,
    cola_salida: asyncio.Queue,
) -> None:
    """Corre SUMO con TraCI y emite frames en cola_salida.

    Se ejecuta en un thread separado (asyncio.to_thread) para no bloquear el bucle
    de eventos. Los frames son dicts con la posición de entidades y estado de semáforos.
    """
    trabajo_dir = RUNS_DIR / f"sesion3d-{sesion.sid}"
    try:
        sumocfg = _preparar_sumocfg(
            sesion.tl_id,
            sesion.escenario_run_id,
            sesion.programa_id,
            programa_tls,
            trabajo_dir,
        )
        await asyncio.to_thread(_loop_traci, sesion, sumocfg, cola_salida)
    except Exception as exc:
        await cola_salida.put({"tipo": "error", "mensaje": str(exc)[:500]})
    finally:
        # limpiar directorio de trabajo
        import shutil
        shutil.rmtree(trabajo_dir, ignore_errors=True)


def _loop_traci(
    sesion: EstadoSesion,
    sumocfg: Path,
    cola_salida: asyncio.Queue,
) -> None:
    """Bucle TraCI sincrónico. Corre en un thread del ThreadPoolExecutor."""
    import shutil as sh
    import traci
    from sumolib.miscutils import getFreeSocketPort

    executable = sh.which("sumo")
    if executable is None:
        raise RuntimeError("'sumo' no está en el PATH.")

    puerto = getFreeSocketPort()

    with tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as err_f:
        proc = subprocess.Popen(
            [executable, "-c", str(sumocfg), "--remote-port", str(puerto),
             "--no-step-log", "true", "--start"],
            cwd=sumocfg.parent, stderr=err_f, text=True,
        )
        conexion = None
        try:
            conexion = traci.connect(puerto, numRetries=120, proc=proc,
                                     label=f"3d-{sesion.sid}")

            from etl.sumo.configuration import HORA_INI, HORA_FIN
            t = conexion.simulation.getTime()
            sesion.tiempo_sim = t

            while sesion.activa and t < HORA_FIN:
                if sesion.pausada:
                    time.sleep(0.1)
                    continue

                try:
                    paso = max(1.0, sesion.velocidad)
                    conexion.simulationStep(min(t + paso, HORA_FIN))
                except traci.exceptions.FatalTraCIError:
                    break

                t = conexion.simulation.getTime()
                sesion.tiempo_sim = t
                sesion.ultimo_ping = time.monotonic()

                frame = _construir_frame(conexion, sesion.tl_id, t)
                # poner en cola sin bloquear: si está llena, descartar el frame antiguo
                try:
                    cola_salida.put_nowait(frame)
                except asyncio.QueueFull:
                    try:
                        cola_salida.get_nowait()
                        cola_salida.put_nowait(frame)
                    except Exception:
                        pass

                intervalo = 1.0 / (_PASOS_POR_SEGUNDO * max(sesion.velocidad, 0.1))
                time.sleep(intervalo)

            cola_salida.put_nowait({"tipo": "fin", "tiempo": t})
            conexion.close()
            conexion = None
            proc.wait()
        except Exception:
            proc.kill()
            proc.wait()
            raise
        finally:
            if conexion is not None:
                try:
                    conexion.close(False)
                except Exception:
                    pass


def _construir_frame(conexion: Any, tl_id: str, t: float) -> dict:
    """Lee el estado actual de la simulación y lo serializa para el WebSocket."""
    vehiculos = []
    for vid in conexion.vehicle.getIDList():
        x, y = conexion.vehicle.getPosition(vid)
        z = conexion.vehicle.getPosition3D(vid)[2] if hasattr(conexion.vehicle, "getPosition3D") else 0.0
        lon, lat = conexion.simulation.convertGeo(x, y)
        angulo = conexion.vehicle.getAngle(vid)
        vtype = conexion.vehicle.getTypeID(vid)
        vehiculos.append({
            "id": vid, "lon": round(lon, 6), "lat": round(lat, 6),
            "z": round(z, 1), "angulo": round(angulo, 1), "tipo": vtype,
        })

    personas = []
    for pid in conexion.person.getIDList():
        x, y = conexion.person.getPosition(pid)
        lon, lat = conexion.simulation.convertGeo(x, y)
        personas.append({
            "id": pid, "lon": round(lon, 6), "lat": round(lat, 6),
        })

    semaforos = []
    try:
        estado = conexion.trafficlight.getRedYellowGreenState(tl_id)
        fase = conexion.trafficlight.getPhase(tl_id)
        tiempo_fase = conexion.trafficlight.getNextSwitch(tl_id) - t
        semaforos.append({
            "id": tl_id, "estado": estado, "fase": fase,
            "tiempo_restante": round(tiempo_fase, 1),
        })
    except Exception:
        pass

    return {
        "tipo": "frame",
        "tiempo": round(t, 1),
        "vehiculos": vehiculos,
        "personas": personas,
        "semaforos": semaforos,
    }


# ─────────────────────────────────────── geometría de la zona

def obtener_geometria(tl_id: str, escenario_run_id: str | None) -> dict:
    """Devuelve la geometría de los carriles y posición de los semáforos en la zona.

    Los carriles vienen de zona.net.xml (o de la red completa como fallback).
    Las coordenadas se convierten a lon/lat/z.
    """
    import xml.etree.ElementTree as ET
    from etl.sumo.intersecciones import _transformador

    if escenario_run_id and (RUNS_DIR / escenario_run_id / "zona.net.xml").is_file():
        net_path = RUNS_DIR / escenario_run_id / "zona.net.xml"
    else:
        net_path = ScenarioPaths.from_name(DEFAULT_SCENARIO).net

    a_lonlat = None
    carriles_raw: list[dict] = []
    semaforos_raw: list[dict] = []
    tl_conexiones: list[tuple[int, str, str]] = []

    for _, elem in ET.iterparse(net_path, events=("end",)):
        tag = elem.tag
        if tag == "location":
            a_lonlat = _transformador(elem)
        elif tag == "lane":
            parent = elem.get("id", "")
            shape = elem.get("shape", "")
            puntos = []
            for par in shape.split():
                xy = par.split(",")
                if len(xy) >= 2:
                    puntos.append(xy)
            if puntos and a_lonlat:
                coords = []
                for xy in puntos:
                    lon, lat = a_lonlat(float(xy[0]), float(xy[1]))
                    z = float(xy[2]) if len(xy) > 2 else 0.0
                    coords.append([round(lon, 6), round(lat, 6), round(z, 1)])
                carriles_raw.append({"id": parent, "coords": coords})
            elem.clear()
        elif tag == "connection":
            tl = elem.get("tl")
            if tl == tl_id:
                tl_conexiones.append((
                    int(elem.get("linkIndex", 0)),
                    elem.get("from", ""),
                    elem.get("dir", ""),
                ))
            elem.clear()
        else:
            elem.clear()

    return {
        "carriles": carriles_raw[:500],   # limitar tamaño
        "semaforos": [
            {"tl_id": tl_id, "enlace": i, "acceso": d, "giro": g}
            for i, d, g in sorted(tl_conexiones)
        ],
    }
