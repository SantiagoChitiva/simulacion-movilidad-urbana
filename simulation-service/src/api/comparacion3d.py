"""
Simulador 3D comparativo: "sin semáforo (actual)" vs "con semáforo propuesto".

Cada comparación prepara una zona alrededor de un cruce sin semáforo
(`etl.run_escenario_semaforo`) y, cuando el visor se conecta por WebSocket, corre dos
SUMO en lockstep controlados por TraCI:
- lado A: zona.net.xml, el cruce como está hoy,
- lado B: zona_tls.net.xml, el mismo cruce con el semáforo propuesto.
Ambos cargan la misma demanda con la misma semilla, así que los mismos actores aparecen
en los dos lados y se pueden seguir a la vez.

Cada actor viaja como [id, tipo, x, y, z, ángulo, velocidad, edge]. Cada frame lleva, por lado, la posición de todos los actores, el estado de las luces,
métricas agregadas y la telemetría del actor seguido (velocidad, aceleración, líder,
riesgo, acción que está tomando y decisiones posibles en el próximo cruce).

Comandos del cliente (JSON): {"pausa": bool}, {"velocidad": x}, {"periodo_riesgo": s},
{"seguir": id}, {"inyectar": {"tipo": "auto", "acceso": edge, "giro": "s", "estilo": "normal"}}.
"""
import asyncio
import json
import logging
import queue
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from etl.sumo.configuration import DEFAULT_SCENARIO, HORA_INI, RUNS_DIR, ScenarioPaths
from etl.sumo.escena3d import geometria_escena
from etl.sumo.estilos import PARAMS_ESTILO, EstiloConductor
from etl.sumo.telemetria import (
    clasificar_accion, drac, indice_riesgo, opcion_enlace, pet_cruce, riesgo_peaton, ttc,
)

logger = logging.getLogger(__name__)

MAX_COMPARACIONES = 2
TIMEOUT_SIN_ACTIVIDAD = 180.0   # s sin mensajes ni conexión -> se libera
PASO_S = 0.2                    # step-length de SUMO
CALENTAMIENTO_S = 240           # tiempo simulado antes de empezar a transmitir
DURACION_S = 3600               # duración simulable de la comparación
HISTORIAL_RIESGO = 40           # muestras de riesgo que se guardan por lado
RADIO_CRUCE_M = 60              # vehículos a esta distancia del cruce entran en las métricas

# motivos de cambio de carril de SUMO (getLaneChangeStatePretty) que se muestran en el HUD
_MOTIVOS_CAMBIO = {
    "strategic": "seguir su ruta", "speedGain": "ganar velocidad", "keepRight": "mantenerse a la derecha",
    "cooperative": "dejar pasar a otro", "sublane": "acomodarse en el carril", "urgent": "urgente",
}

TIPOS_VEHICULO = ("auto", "moto", "taxi", "bici", "bus_pt", "escolar", "especial", "informal", "otro")


@dataclass
class Comparacion:
    cid: str
    nodo_id: str
    run_dir: Path
    estado: str = "preparando"          # preparando | lista | error
    etapa: str | None = None
    info: dict[str, Any] = field(default_factory=dict)
    geometria: dict[str, Any] | None = None
    error: str | None = None
    creada: float = field(default_factory=time.monotonic)
    ultimo_ping: float = field(default_factory=time.monotonic)
    # control en vivo
    conectada: bool = False
    pausada: bool = False
    velocidad: float = 1.0
    periodo_riesgo: float = 2.0
    comandos: "queue.Queue[dict]" = field(default_factory=queue.Queue)
    activa: bool = True

    def resumen(self) -> dict:
        info = {k: v for k, v in self.info.items() if k != "geometria_accesos"}
        return {
            "id": self.cid, "nodo_id": self.nodo_id, "estado": self.estado, "etapa": self.etapa,
            "error": self.error, "info": info, "conectada": self.conectada,
        }


class GestorComparaciones:
    """Comparaciones activas; prepara cada zona en un hilo y libera las abandonadas."""

    def __init__(self, preparar=None, runs_dir: Path | None = None) -> None:
        self._runs_dir = runs_dir or RUNS_DIR
        self._comparaciones: dict[str, Comparacion] = {}
        self._lock = threading.Lock()
        # inyectable en las pruebas: (comparación, nodo, lon, lat, run_id_origen, intensidades) -> info
        self._preparar = preparar or _preparar_zona

    def crear(
        self, nodo_id: str, lon: float, lat: float,
        run_id_origen: str | None = None, intensidades: dict[str, float] | None = None,
    ) -> Comparacion:
        with self._lock:
            self._limpiar_expiradas()
            if len(self._comparaciones) >= MAX_COMPARACIONES:
                raise RuntimeError(
                    f"Ya hay {MAX_COMPARACIONES} comparaciones 3D abiertas. Cierra una antes de abrir otra."
                )
            cid = f"sem-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}"
            comp = Comparacion(cid=cid, nodo_id=nodo_id, run_dir=self._runs_dir / cid)
            self._comparaciones[cid] = comp

        def _trabajo() -> None:
            try:
                comp.info = self._preparar(comp, nodo_id, lon, lat, run_id_origen, intensidades)
                comp.estado = "lista"
            except Exception as exc:   # noqa: BLE001 - el error se muestra en el visor
                logger.exception("Falló la preparación de %s", cid)
                comp.estado, comp.error = "error", str(exc)[:500]

        threading.Thread(target=_trabajo, daemon=True, name=f"prep-{cid}").start()
        return comp

    def obtener(self, cid: str) -> Comparacion | None:
        comp = self._comparaciones.get(cid)
        if comp is not None:
            comp.ultimo_ping = time.monotonic()
        return comp

    def cerrar(self, cid: str) -> None:
        with self._lock:
            comp = self._comparaciones.pop(cid, None)
        if comp is not None:
            comp.activa = False
            _borrar_en_segundo_plano(comp.run_dir)

    def listar(self) -> list[dict]:
        with self._lock:
            self._limpiar_expiradas()
            return [c.resumen() for c in self._comparaciones.values()]

    def _limpiar_expiradas(self) -> None:
        ahora = time.monotonic()
        for cid, comp in list(self._comparaciones.items()):
            if not comp.conectada and ahora - comp.ultimo_ping > TIMEOUT_SIN_ACTIVIDAD:
                self._comparaciones.pop(cid)
                comp.activa = False
                _borrar_en_segundo_plano(comp.run_dir)


def _borrar_en_segundo_plano(directorio: Path, intentos: int = 5) -> None:
    """Borra el directorio de una comparación. En Windows, SUMO puede tardar unos segundos en
    soltar sus archivos después de cerrar la conexión, así que se reintenta."""
    def _borrar() -> None:
        for _ in range(intentos):
            shutil.rmtree(directorio, ignore_errors=True)
            if not directorio.exists():
                return
            time.sleep(1.0)

    threading.Thread(target=_borrar, daemon=True, name=f"borrar-{directorio.name}").start()


def _preparar_zona(comp: Comparacion, nodo_id: str, lon: float, lat: float,
                   run_id_origen: str | None, intensidades: dict[str, float] | None) -> dict:
    from etl.etl import run_escenario_semaforo

    def _progreso(etapa: str, _avance: float | None) -> None:
        comp.etapa = etapa

    info = run_escenario_semaforo(
        nodo_id, lon, lat, comp.cid, run_id_origen=run_id_origen,
        intensidades=intensidades, on_progreso=_progreso,
    )
    comp.etapa = "armando_escena"
    comp.geometria = geometria_escena(comp.run_dir, nodo_id, _nombres_vias())
    info["nodo"] = {k: comp.geometria["nodo"][k] for k in ("x", "y", "z", "lon", "lat", "tipo_actual")}
    info["geometria_accesos"] = comp.geometria["accesos"]
    return info


def _nombres_vias() -> dict[str, str]:
    path = ScenarioPaths.from_name(DEFAULT_SCENARIO).nombres_vias
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}


# ─────────────────────────────────────────────────────────── un lado de la comparación

def escribir_sumocfg_lado(destino: Path, net: Path, demanda: list[str], vtypes: str) -> Path:
    raiz = ET.Element("configuration")
    entrada = ET.SubElement(raiz, "input")
    ET.SubElement(entrada, "net-file", value=str(Path(net).resolve()))
    ET.SubElement(entrada, "route-files", value=",".join(str(Path(d).resolve()) for d in demanda))
    ET.SubElement(entrada, "additional-files", value=str(Path(vtypes).resolve()))
    tiempo = ET.SubElement(raiz, "time")
    ET.SubElement(tiempo, "begin", value=str(HORA_INI))
    ET.SubElement(tiempo, "end", value=str(HORA_INI + DURACION_S + CALENTAMIENTO_S))
    ET.SubElement(tiempo, "step-length", value=str(PASO_S))
    proc = ET.SubElement(raiz, "processing")
    ET.SubElement(proc, "ignore-route-errors", value="true")
    ET.SubElement(proc, "time-to-teleport", value="120")
    ET.SubElement(proc, "collision.action", value="warn")
    ET.SubElement(proc, "collision.check-junctions", value="true")
    ET.SubElement(proc, "default.action-step-length", value="0.4")
    alea = ET.SubElement(raiz, "random_number")
    ET.SubElement(alea, "seed", value="42")
    reporte = ET.SubElement(raiz, "report")
    ET.SubElement(reporte, "no-step-log", value="true")
    ET.SubElement(reporte, "no-warnings", value="true")
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


class Lado:
    """Una instancia de SUMO con TraCI y el estado que se le sigue por frame."""

    def __init__(self, nombre: str, sumocfg: Path, nodo: dict, tl_id: str | None) -> None:
        import traci
        from sumolib.miscutils import getFreeSocketPort
        import traci.constants as tc

        self.nombre = nombre
        self.nodo = nodo
        self.tl_id = tl_id
        self._tc = tc
        self._traci_error = traci.exceptions.TraCIException
        sumo = shutil.which("sumo")
        if sumo is None:
            raise RuntimeError("'sumo' no está en el PATH.")
        puerto = getFreeSocketPort()
        self._err = tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace")
        self.proc = subprocess.Popen(
            [sumo, "-c", str(sumocfg.resolve()), "--remote-port", str(puerto), "--start"],
            cwd=sumocfg.parent, stdout=subprocess.DEVNULL, stderr=self._err,
        )
        self.con = traci.connect(puerto, numRetries=120, proc=self.proc, label=f"{nombre}-{uuid.uuid4().hex[:6]}")
        self._vars_veh = [tc.VAR_POSITION3D, tc.VAR_ANGLE, tc.VAR_SPEED, tc.VAR_TYPE, tc.VAR_WAITING_TIME, tc.VAR_ROAD_ID]
        self._vars_per = [tc.VAR_POSITION3D, tc.VAR_ANGLE, tc.VAR_SPEED, tc.VAR_WAITING_TIME, tc.VAR_ROAD_ID]
        self.colisiones = 0
        self.historial: list[dict] = []
        self.riesgo: dict | None = None
        self.max_riesgo = 0.0
        self.conflictos = 0
        self.espera_cruce: dict[str, float] = {}
        self._carril_previo: dict[str, tuple[int, str | None, float]] = {}

    # -- simulación
    def avanzar(self, hasta: float) -> None:
        self.con.simulationStep(hasta)
        # en un salto largo (calentamiento) un actor puede entrar y salir en el mismo paso
        for vid in self.con.simulation.getDepartedIDList():
            try:
                self.con.vehicle.subscribe(vid, self._vars_veh)
            except self._traci_error:
                pass
        for pid in self.con.simulation.getDepartedPersonIDList():
            try:
                self.con.person.subscribe(pid, self._vars_per)
            except self._traci_error:
                pass
        self.colisiones += self.con.simulation.getCollidingVehiclesNumber()

    def tiempo(self) -> float:
        return self.con.simulation.getTime()

    def cerrar(self) -> None:
        try:
            self.con.close(False)
        except Exception:   # noqa: BLE001
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self._err.close()

    # -- frame
    def actores(self) -> tuple[list, list, dict]:
        tc = self._tc
        vehiculos, personas = [], []
        nx, ny = self.nodo["x"], self.nodo["y"]
        cerca, detenidos, espera, suma_v = 0, 0, 0.0, 0.0
        for vid, d in self.con.vehicle.getAllSubscriptionResults().items():
            x, y, z = d[tc.VAR_POSITION3D]
            v = d[tc.VAR_SPEED]
            vehiculos.append([vid, d[tc.VAR_TYPE].split("@")[0], round(x, 2), round(y, 2), round(z, 2),
                              round(d[tc.VAR_ANGLE], 1), round(v, 2), d[tc.VAR_ROAD_ID]])
            if (x - nx) ** 2 + (y - ny) ** 2 < RADIO_CRUCE_M ** 2:
                cerca += 1
                suma_v += v
                if v < 0.3:
                    detenidos += 1
                espera += d[tc.VAR_WAITING_TIME]
                self.espera_cruce[vid] = max(self.espera_cruce.get(vid, 0.0), d[tc.VAR_WAITING_TIME])
        for pid, d in self.con.person.getAllSubscriptionResults().items():
            x, y, z = d[tc.VAR_POSITION3D]
            personas.append([pid, "peaton", round(x, 2), round(y, 2), round(z, 2),
                             round(d[tc.VAR_ANGLE], 1), round(d[tc.VAR_SPEED], 2), d[tc.VAR_ROAD_ID]])
        esperas = list(self.espera_cruce.values())
        metricas = {
            "vehiculos": len(vehiculos), "peatones": len(personas),
            "en_cruce": cerca, "detenidos_cruce": detenidos,
            "velocidad_media_cruce_kmh": round(3.6 * suma_v / cerca, 1) if cerca else None,
            "espera_media_cruce_s": round(sum(esperas) / len(esperas), 1) if esperas else 0.0,
            "colisiones": self.colisiones, "conflictos": self.conflictos,
            "riesgo_max": round(self.max_riesgo),
        }
        return vehiculos, personas, metricas

    def luces(self) -> dict | None:
        if self.tl_id is None:
            return None
        try:
            t = self.con.simulation.getTime()
            return {
                "estado": self.con.trafficlight.getRedYellowGreenState(self.tl_id),
                "fase": self.con.trafficlight.getPhase(self.tl_id),
                "restante": round(self.con.trafficlight.getNextSwitch(self.tl_id) - t, 1),
            }
        except Exception:   # noqa: BLE001
            return None

    def contar_conflictos(self) -> None:
        """Conflictos de cruce (PET < 1,5 s) entre los vehículos que se acercan al nodo."""
        try:
            ids = self.con.vehicle.getIDList()
        except Exception:   # noqa: BLE001
            return
        nx, ny = self.nodo["x"], self.nodo["y"]
        vistos = set()
        for vid in ids:
            x, y = self.con.vehicle.getPosition(vid)
            if (x - nx) ** 2 + (y - ny) ** 2 > RADIO_CRUCE_M ** 2:
                continue
            v = self.con.vehicle.getSpeed(vid)
            try:
                rivales = self.con.vehicle.getJunctionFoes(vid, 50)
            except Exception:   # noqa: BLE001
                continue
            for rival in rivales:
                foe_id, dist_ego, dist_rival = rival[0], rival[1], rival[2]
                par = tuple(sorted((vid, foe_id)))
                if par in vistos:
                    continue
                try:
                    v_rival = self.con.vehicle.getSpeed(foe_id)
                except Exception:   # noqa: BLE001
                    continue
                pet = pet_cruce(dist_ego, v, dist_rival, v_rival)
                if pet is not None and pet < 1.5:
                    vistos.add(par)
        self.conflictos += len(vistos)

    # -- actor seguido
    def existe(self, ego: str) -> str | None:
        """'vehiculo', 'persona' o None."""
        if ego in self.con.vehicle.getAllSubscriptionResults():
            return "vehiculo"
        if ego in self.con.person.getAllSubscriptionResults():
            return "persona"
        return None

    def telemetria(self, ego: str, actores_veh: list, medir_riesgo: bool) -> dict | None:
        clase = self.existe(ego)
        if clase is None:
            return None
        try:
            if clase == "vehiculo":
                datos = self._telemetria_vehiculo(ego, medir_riesgo)
            else:
                datos = self._telemetria_persona(ego, actores_veh, medir_riesgo)
        except Exception as exc:   # noqa: BLE001 - el actor puede salir de la red en este paso
            logger.debug("telemetría de %s: %s", ego, exc)
            return None
        datos["riesgo"] = self.riesgo
        datos["historial_riesgo"] = self.historial[-HISTORIAL_RIESGO:]
        return datos

    def _registrar_riesgo(self, riesgo) -> None:
        self.riesgo = {**riesgo.to_dict(), "t": round(self.tiempo(), 1)}
        self.historial.append({"t": self.riesgo["t"], "indice": self.riesgo["indice"]})
        self.max_riesgo = max(self.max_riesgo, riesgo.indice)

    def _telemetria_vehiculo(self, vid: str, medir_riesgo: bool) -> dict:
        veh = self.con.vehicle
        v = veh.getSpeed(vid)
        a = veh.getAcceleration(vid)
        x, y = veh.getPosition(vid)
        lon, lat = self.con.simulation.convertGeo(x, y)
        lider = veh.getLeader(vid, 120)
        gap = v_lider = None
        if lider and lider[0]:
            gap, v_lider = lider[1], veh.getSpeed(lider[0])
        ttc_s = ttc(gap, v, v_lider or 0.0) if gap is not None else None
        drac_s = drac(gap, v, v_lider or 0.0) if gap is not None else None

        prox_tls = veh.getNextTLS(vid)
        luz = dist_luz = None
        if prox_tls:
            _tl, _idx, dist_luz, luz = prox_tls[0]
        enlaces = veh.getNextLinks(vid)
        siguiente = enlaces[0] if enlaces else None
        cede = bool(siguiente and not siguiente[2] and siguiente[4])
        # sin modelo sublane el cambio de carril es instantáneo: se detecta por el índice
        indice = veh.getLaneIndex(vid)
        previo = self._carril_previo.get(vid)
        if previo is not None and previo[0] != indice:
            self._carril_previo[vid] = (indice, "izquierda" if indice > previo[0] else "derecha", time.monotonic())
        elif previo is None:
            self._carril_previo[vid] = (indice, None, 0.0)
        _, sentido_cambio, cuando = self._carril_previo[vid]
        lado_cambio = sentido_cambio if time.monotonic() - cuando < 1.5 else None
        intenciones = []
        for sentido, etiqueta in ((1, "izquierda"), (-1, "derecha")):
            try:
                motivos = veh.getLaneChangeStatePretty(vid, sentido)[0]
            except Exception:   # noqa: BLE001
                continue
            quiere = [m for m in motivos if m in _MOTIVOS_CAMBIO]
            if quiere:
                bloqueado = any(m.startswith("blocked") for m in motivos)
                intenciones.append({
                    "hacia": etiqueta,
                    "motivo": ", ".join(_MOTIVOS_CAMBIO[m] for m in quiere),
                    "bloqueado": bloqueado,
                })
        codigo, accion = clasificar_accion(
            v, a, veh.getWaitingTime(vid), luz, dist_luz, gap, lado_cambio, cede,
        )

        carril = veh.getLaneID(vid)
        opciones = []
        try:
            for l in self.con.lane.getLinks(carril, extended=True):
                opciones.append(opcion_enlace(l[6], l[5], l[1], l[2], l[3]))
        except Exception:   # noqa: BLE001 - carril interno del cruce
            pass
        elegida = siguiente[6] if siguiente else None

        if medir_riesgo:
            pet = None
            try:
                for rival in veh.getJunctionFoes(vid, 60):
                    p = pet_cruce(rival[1], v, rival[2], veh.getSpeed(rival[0]))
                    if p is not None and (pet is None or p < pet):
                        pet = p
            except Exception:   # noqa: BLE001
                pass
            self._registrar_riesgo(indice_riesgo(ttc_s, drac_s, pet))

        r = lambda x, n=1: None if x is None else round(x, n)   # noqa: E731
        return {
            "id": vid, "clase": "vehiculo", "tipo": veh.getTypeID(vid).split("@")[0],
            "lon": lon, "lat": lat,
            "velocidad_kmh": r(3.6 * v), "limite_kmh": r(3.6 * veh.getAllowedSpeed(vid)),
            "aceleracion": r(a, 2), "carril": carril, "edge": veh.getRoadID(vid),
            "lider": lider[0] if lider and lider[0] else None, "gap_m": r(gap),
            "espera_s": r(veh.getWaitingTime(vid)), "espera_acum_s": r(veh.getAccumulatedWaitingTime(vid)),
            "perdida_s": r(veh.getTimeLoss(vid)), "distancia_m": r(veh.getDistance(vid), 0),
            "semaforo": None if luz is None else {"estado": luz, "distancia_m": r(dist_luz)},
            "accion": {"codigo": codigo, "texto": accion},
            "opciones": opciones, "giro_elegido": elegida,
            "cede_paso": cede, "intenciones_cambio": intenciones,
        }

    def _telemetria_persona(self, pid: str, actores_veh: list, medir_riesgo: bool) -> dict:
        per = self.con.person
        v = per.getSpeed(pid)
        x, y = per.getPosition(pid)
        lon, lat = self.con.simulation.convertGeo(x, y)
        espera = per.getWaitingTime(pid)
        cercano, dist_min, v_acerc = None, None, 0.0
        for vid, _tipo, vx, vy, _vz, _ang, vv, _edge in actores_veh:
            d = ((vx - x) ** 2 + (vy - y) ** 2) ** 0.5
            if d < 25 and (dist_min is None or d < dist_min):
                cercano, dist_min, v_acerc = vid, d, vv
        if medir_riesgo:
            self._registrar_riesgo(riesgo_peaton(dist_min, v_acerc))
        if v < 0.1:
            codigo, accion = ("espera_cruzar", f"Esperando para cruzar ({int(espera)} s)") if espera > 0 else ("detenido", "Detenido")
        else:
            codigo, accion = "camina", "Caminando"
        r = lambda x, n=1: None if x is None else round(x, n)   # noqa: E731
        return {
            "id": pid, "clase": "persona", "tipo": "peaton", "lon": lon, "lat": lat,
            "velocidad_kmh": r(3.6 * v), "limite_kmh": None, "aceleracion": None,
            "edge": per.getRoadID(pid), "espera_s": r(espera),
            "vehiculo_cercano": cercano, "dist_vehiculo_m": r(dist_min),
            "accion": {"codigo": codigo, "texto": accion}, "opciones": [], "giro_elegido": None,
        }

    # -- inyección
    def _permite_peatones(self, edge: str) -> bool:
        try:
            n = self.con.edge.getLaneNumber(edge)
            for i in range(n):
                carril = f"{edge}_{i}"
                permitidos = self.con.lane.getAllowed(carril)
                if "pedestrian" in permitidos or (not permitidos and "pedestrian" not in self.con.lane.getDisallowed(carril)):
                    return True
        except Exception:   # noqa: BLE001
            return False
        return False

    def inyectar(self, ego_id: str, tipo: str, edges: list[str], estilo: EstiloConductor) -> None:
        if tipo == "peaton":
            caminables = [e for e in edges if self._permite_peatones(e)]
            ruta = None
            # de lo más lejos a lo más cerca del cruce hasta encontrar una ruta caminable
            for desde in caminables[: len(caminables) // 2 + 1]:
                for hasta in reversed(caminables[len(caminables) // 2:]):
                    if desde == hasta:
                        continue
                    etapas = self.con.simulation.findIntermodalRoute(desde, hasta)
                    if etapas and any(et.edges for et in etapas):
                        ruta = (desde, etapas)
                        break
                if ruta:
                    break
            if ruta is None:
                raise RuntimeError("No hay ruta peatonal por ese acceso; prueba otro acceso o giro.")
            desde, etapas = ruta
            self.con.person.add(ego_id, desde, 0.0)
            for etapa in etapas:
                self.con.person.appendStage(ego_id, etapa)
            self.con.person.subscribe(ego_id, self._vars_per)
            return
        ruta_id = f"r_{ego_id}"
        self.con.route.add(ruta_id, edges)
        self.con.vehicle.add(ego_id, ruta_id, typeID=tipo, depart="now", departLane="best", departSpeed="max")
        params = PARAMS_ESTILO[estilo]
        self.con.vehicle.setImperfection(ego_id, float(params["sigma"]))
        self.con.vehicle.setSpeedFactor(ego_id, float(params["speedFactor"]))
        self.con.vehicle.setTau(ego_id, float(params["tau"]))
        self.con.vehicle.setParameter(ego_id, "laneChangeModel.lcSpeedGain", params["lcSpeedGain"])
        self.con.vehicle.subscribe(ego_id, self._vars_veh)


# ─────────────────────────────────────────────────────────── bucle de la comparación

def correr_comparacion(comp: Comparacion, cola: asyncio.Queue, bucle: asyncio.AbstractEventLoop) -> None:
    """Bucle sincrónico (en un hilo): avanza A y B a la par y publica frames en `cola`."""
    def publicar(msg: dict) -> None:
        def _poner() -> None:
            if cola.full():
                try:
                    cola.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            cola.put_nowait(msg)
        bucle.call_soon_threadsafe(_poner)

    info = comp.info
    nodo = info["nodo"]
    cfg_a = escribir_sumocfg_lado(comp.run_dir / "lado_a.sumocfg", Path(info["zona_net"]), info["demanda"], info["vtypes"])
    cfg_b = escribir_sumocfg_lado(comp.run_dir / "lado_b.sumocfg", Path(info["zona_tls_net"]), info["demanda"], info["vtypes"])

    lados: list[Lado] = []
    try:
        publicar({"tipo": "estado", "mensaje": "Iniciando las dos simulaciones…"})
        lados = [Lado("a", cfg_a, nodo, None), Lado("b", cfg_b, nodo, comp.nodo_id)]
        t = lados[0].tiempo()
        fin_calentamiento = t + CALENTAMIENTO_S
        while comp.activa and t < fin_calentamiento:
            t = min(t + 20, fin_calentamiento)
            for lado in lados:
                lado.avanzar(t)
            publicar({"tipo": "estado", "mensaje": f"Calentando la simulación ({int(100 * (t - HORA_INI) / CALENTAMIENTO_S)} %)…"})

        ego: str | None = None
        n_ego = 0
        proximo_riesgo = t
        fin = HORA_INI + CALENTAMIENTO_S + DURACION_S
        while comp.activa and t < fin:
            # comandos del visor
            while True:
                try:
                    cmd = comp.comandos.get_nowait()
                except queue.Empty:
                    break
                if "seguir" in cmd:
                    ego = cmd["seguir"] or None
                    for lado in lados:
                        lado.historial.clear()
                        lado.riesgo = None
                elif "inyectar" in cmd:
                    datos = cmd["inyectar"]
                    n_ego += 1
                    nuevo = f"ego_{n_ego}"
                    try:
                        estilo = EstiloConductor(datos.get("estilo", "normal"))
                        tipo = datos.get("tipo", "auto")
                        if tipo not in TIPOS_VEHICULO and tipo != "peaton":
                            raise ValueError(f"Tipo de actor desconocido: {tipo}")
                        edges = _ruta_inyeccion(info["geometria_accesos"], datos.get("acceso"), datos.get("giro"))
                        for lado in lados:
                            lado.inyectar(nuevo, tipo, edges, estilo)
                        ego = nuevo
                        for lado in lados:
                            lado.historial.clear()
                            lado.riesgo = None
                        publicar({"tipo": "ego", "id": nuevo})
                    except Exception as exc:   # noqa: BLE001
                        publicar({"tipo": "aviso", "mensaje": f"No se pudo inyectar el actor: {exc}"})

            if comp.pausada:
                time.sleep(0.1)
                continue

            pasos = max(1, round(comp.velocidad))
            inicio_real = time.monotonic()
            t = round(t + pasos * PASO_S, 3)
            for lado in lados:
                lado.avanzar(t)

            medir = t >= proximo_riesgo
            if medir:
                proximo_riesgo = t + comp.periodo_riesgo
            frame = {"tipo": "frame", "t": t, "dt": round(pasos * PASO_S, 3), "lados": {}}
            for lado in lados:
                if medir:
                    lado.contar_conflictos()
                vehiculos, personas, metricas = lado.actores()
                frame["lados"][lado.nombre] = {
                    "vehiculos": vehiculos, "personas": personas, "metricas": metricas,
                    "luces": lado.luces(),
                    "ego": lado.telemetria(ego, vehiculos, medir) if ego else None,
                }
            frame["ego"] = ego
            publicar(frame)

            # ritmo de tiempo real: pasos * PASO_S segundos simulados a la velocidad pedida
            espera = pasos * PASO_S / comp.velocidad - (time.monotonic() - inicio_real)
            if espera > 0:
                time.sleep(espera)

        publicar({"tipo": "fin", "t": t})
    except Exception as exc:   # noqa: BLE001
        logger.exception("Falló la comparación %s", comp.cid)
        publicar({"tipo": "error", "mensaje": str(exc)[:500]})
    finally:
        for lado in lados:
            lado.cerrar()


def _ruta_inyeccion(accesos: list[dict], acceso: str | None, giro: str | None) -> list[str]:
    """Edges de la ruta del actor inyectado según el acceso y el giro elegidos."""
    candidatos = [a for a in accesos if acceso is None or a["edge"] == acceso]
    if not candidatos:
        raise ValueError(f"El acceso '{acceso}' no llega al cruce.")
    giros = candidatos[0]["giros"]
    elegido = next((g for g in giros if g["direccion"] == giro), None) or giros[0]
    return elegido["edges"]


def mensaje_json(texto: str) -> dict | None:
    try:
        cmd = json.loads(texto)
    except json.JSONDecodeError:
        return None
    return cmd if isinstance(cmd, dict) else None
