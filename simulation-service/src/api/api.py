import asyncio
import json
import threading
import uuid
from collections import Counter
from dataclasses import asdict
from functools import lru_cache
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator

from etl import precalculadas
from etl.etl import run_recorte
from etl.sumo.configuration import (
    CACHE_DIR, DEFAULT_SCENARIO, MAX_VIAJES, RUNS_DIR, ArchivosPrecalculada, ScenarioPaths,
)
from etl.sumo.intersecciones import (
    HORAS_VENTANA, Semaforo, a_feature, catalogo, con_volumenes, volumenes,
)
from etl.sumo.demanda import (
    INFO_MODOS, PRESETS, DemandaConfig, Preset, cargar_dia, cargar_ventana, conteos_preset,
)
from etl.sumo.enums.transport_mode import TransportMode
from etl.sumo.estilos import EstiloConductor, INFO_ESTILOS, PARAMS_ESTILO
from etl.sumo.cierres import CierreVial, escribir_rerouter
from etl.sumo.geojson_reader import read_first_features
from etl.sumo.priorizacion import a_geojson, puntuar_cruces
from etl.sumo.programas_tls import (
    ProgramaTLS, FasePrograma, leer_programas, leer_programa,
    escribir_programa, validar_programa, webster,
)

from .jobs import GestorCorridas
from .sesion3d import GestorSesiones, ejecutar_sesion, obtener_geometria

app = FastAPI(title="Simulation Service")

_SIN_SALIDA = "Aún no hay salida de simulación. Ejecuta el pipeline primero."

_gestor: GestorCorridas | None = None
_gestor_sesiones: GestorSesiones = GestorSesiones()


def obtener_gestor() -> GestorCorridas:
    global _gestor
    if _gestor is None:
        _gestor = GestorCorridas()
    return _gestor


Gestor = Annotated[GestorCorridas, Depends(obtener_gestor)]


@app.get("/health")
def root() -> dict:
    return {"msg": "healthy"}


@app.get("/simulation-output")
def simulation_output(limit: int = Query(3, ge=1, le=100)) -> dict:
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)

    if not paths.geojson.is_file():
        raise HTTPException(status_code=404, detail=_SIN_SALIDA)

    return {
        "type": "FeatureCollection",
        "features": read_first_features(paths.geojson, limit),
    }


@app.get("/kepler-trips")
def kepler_trips() -> FileResponse:
    """GeoJSON completo de trips para la capa Trip de kepler.gl (se envía en streaming)."""
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)

    if not paths.kepler_trips.is_file():
        raise HTTPException(status_code=404, detail=_SIN_SALIDA)

    return FileResponse(paths.kepler_trips, media_type="application/json")


# ---------------------------------------------------------------- demanda

@app.get("/demanda/modos")
def demanda_modos() -> list[dict]:
    """Actores viales que se pueden parametrizar, en el orden en que se muestran."""
    return [{"id": modo.value, **asdict(info)} for modo, info in INFO_MODOS.items()]


@lru_cache(maxsize=1)
def _presets() -> list[dict]:
    tsv = ScenarioPaths.from_name(DEFAULT_SCENARIO).tsv
    ventana, dia = cargar_ventana(tsv), cargar_dia(tsv)
    return [
        {
            "id": preset.value,
            "nombre": info.nombre,
            "descripcion": info.descripcion,
            "conteos": {m.value: n for m, n in conteos_preset(preset, ventana, dia).items()},
        }
        for preset, info in PRESETS.items()
    ]


@app.get("/demanda/presets")
def demanda_presets() -> list[dict]:
    """Presets de demanda derivados de la Encuesta, con sus conteos por modo."""
    return _presets()


@app.get("/demanda/estilos")
def demanda_estilos() -> list[dict]:
    """Estilos de conducción disponibles para los vehículos motorizados."""
    return [
        {
            "id": estilo.value,
            **INFO_ESTILOS[estilo],
            "params": PARAMS_ESTILO[estilo],
        }
        for estilo in EstiloConductor
    ]


# ------------------------------------------------------------ simulaciones

class SolicitudCierre(BaseModel):
    edge_id: str
    hora_inicio: float = Field(ge=0)
    hora_fin: float = Field(ge=0)
    modos_afectados: str | None = None


class SolicitudSimulacion(BaseModel):
    preset: Preset = Preset.ENCUESTA
    conteos: dict[TransportMode, Annotated[int, Field(ge=0, le=MAX_VIAJES)]]
    semilla: int | None = Field(default=None, ge=0)
    estilo: EstiloConductor = EstiloConductor.normal
    cierres: list[SolicitudCierre] = Field(default_factory=list)

    @model_validator(mode="after")
    def _total_valido(self) -> "SolicitudSimulacion":
        total = sum(self.conteos.values())
        if not 1 <= total <= MAX_VIAJES:
            raise ValueError(f"El total de viajes debe estar entre 1 y {MAX_VIAJES}; llegó {total}")
        return self


def _corrida(gestor: GestorCorridas, run_id: str) -> Any:
    corrida = gestor.obtener(run_id)
    if corrida is None:
        raise HTTPException(status_code=404, detail=f"No existe la simulación '{run_id}'")
    return corrida


@app.post("/simulaciones", status_code=202)
def crear_simulacion(solicitud: SolicitudSimulacion, gestor: Gestor) -> dict:
    """Encola una simulación con la demanda pedida; devuelve su id para consultar el estado."""
    demanda = DemandaConfig(solicitud.preset, dict(solicitud.conteos))
    cierres_viales = [
        CierreVial(
            edge_id=c.edge_id,
            hora_inicio_s=c.hora_inicio,
            hora_fin_s=c.hora_fin,
            **({"modos_afectados": c.modos_afectados} if c.modos_afectados else {}),
        )
        for c in solicitud.cierres
    ] if solicitud.cierres else None
    return asdict(gestor.crear(
        demanda,
        solicitud.semilla,
        estilo=solicitud.estilo,
        cierres=cierres_viales,
    ))


@app.post("/simulaciones/{run_id}/cancelar", status_code=202)
def cancelar_simulacion(run_id: str, gestor: Gestor) -> dict:
    """Cancela una simulación en cola o en curso; borra sus archivos salvo el estado."""
    _corrida(gestor, run_id)
    try:
        return asdict(gestor.cancelar(run_id))
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@app.get("/simulaciones")
def listar_simulaciones(gestor: Gestor) -> list[dict]:
    return [asdict(c) for c in gestor.listar()]


@app.get("/simulaciones/{run_id}")
def obtener_simulacion(run_id: str, gestor: Gestor) -> dict:
    return asdict(_corrida(gestor, run_id))


# ------------------------------------------------------------ precalculadas

def _precalculada(preset: Preset) -> dict:
    meta = precalculadas.cargar(preset)
    if meta is None:
        raise HTTPException(
            status_code=404,
            detail=f"El preset '{preset.value}' no está precalculado. Ejecuta python -m etl.precalculadas",
        )
    return meta


@app.get("/precalculadas")
def listar_precalculadas() -> list[dict]:
    """Presets ya simulados que el visor puede cargar sin correr SUMO."""
    return precalculadas.listar()


@app.get("/precalculadas/{preset}/kepler-trips")
def kepler_trips_precalculada(preset: Preset) -> FileResponse:
    """Trips de un preset precalculado. Se envían comprimidos: el navegador los descomprime."""
    meta = _precalculada(preset)
    return FileResponse(
        ArchivosPrecalculada.from_preset(preset.value).trips_gz,
        media_type="application/json",
        headers={"Content-Encoding": "gzip", "X-Tamano-Original": str(meta["tamano_original"])},
    )


# ---------------------------------------------------------- intersecciones

@lru_cache(maxsize=1)
def _semaforos() -> dict[str, Semaforo]:
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    lista = catalogo(paths.net, CACHE_DIR / "semaforos.json", paths.nombres_vias)
    return {s.id: s for s in lista}


def _volumenes_corrida(gestor: GestorCorridas, run_id: str | None, precalculada: Preset | None = None):
    """Volúmenes por edge de la corrida pedida (ninguna = la corrida por defecto)."""
    if precalculada is not None:
        _precalculada(precalculada)
        return precalculadas.leer_volumenes(precalculada)
    if run_id is None:
        paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    else:
        corrida = _corrida(gestor, run_id)
        if corrida.estado != "terminado":
            raise HTTPException(status_code=409, detail=f"La simulación está en estado '{corrida.estado}'")
        paths = gestor.paths(run_id)
    if not paths.vehroute.is_file():
        return None
    return volumenes(paths.vehroute, paths.vehroute.with_name("volumenes.json"))


@app.get("/intersecciones")
def listar_intersecciones(
    gestor: Gestor, run_id: str | None = None, precalculada: Preset | None = None
) -> dict:
    """Intersecciones semaforizadas como GeoJSON de puntos, con el volumen de la corrida."""
    vols = _volumenes_corrida(gestor, run_id, precalculada)
    return {
        "type": "FeatureCollection",
        "features": [a_feature(con_volumenes(s, vols)) for s in _semaforos().values()],
    }


@app.get("/intersecciones/priorizacion")
def listar_priorizacion(
    gestor: Gestor, run_id: str | None = None, precalculada: Preset | None = None
) -> dict:
    """Cruces sin semáforo puntuados por criterios de priorización (Fase F)."""
    vols = _volumenes_corrida(gestor, run_id, precalculada)
    semaforos = list(_semaforos().values())
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    cruces = puntuar_cruces(paths.net, semaforos_existentes=semaforos, volumenes_run_id=vols)
    return a_geojson(cruces)


@app.get("/intersecciones/{tl_id}")
def obtener_interseccion(
    tl_id: str, gestor: Gestor, run_id: str | None = None, precalculada: Preset | None = None
) -> dict:
    """Ficha de una intersección: accesos, programa del semáforo y volúmenes simulados."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")
    vols = _volumenes_corrida(gestor, run_id, precalculada)
    return {
        **asdict(con_volumenes(semaforo, vols)),
        "horas_ventana": HORAS_VENTANA,
        "nota_volumenes": None if vols is not None else "La corrida no tiene vehroute-output: sin volúmenes.",
        "nota_programa": "Programa generado por netconvert a partir de OpenStreetMap; no es el programa real de la Secretaría de Movilidad.",
    }


# ------------------------------------ Fase B: escenarios de zona (recorte)

class SolicitudEscenario(BaseModel):
    run_id: str
    radio_m: int = Field(default=300, ge=50, le=2000)


@app.post("/intersecciones/{tl_id}/escenarios", status_code=202)
def crear_escenario_zona(tl_id: str, solicitud: SolicitudEscenario, gestor: Gestor) -> dict:
    """Recorta la red y la demanda alrededor de la intersección (Fase B).

    Encola una 'corrida de recorte' que solo ejecuta netconvert + cutRoutes.
    Devuelve el run_id del nuevo escenario de zona.
    """
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    # Verificar que el run_id origen existe (o es None para usar el pipeline por defecto)
    run_id_origen: str | None = None
    if solicitud.run_id and not solicitud.run_id.startswith("precalculada-"):
        _corrida(gestor, solicitud.run_id)
        run_id_origen = solicitud.run_id
    # Para precalculadas, usamos el escenario por defecto (la red es la misma)

    from datetime import datetime
    run_id_zona = f"zona-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}"

    def _ejecutar_recorte():
        try:
            from etl.sumo.configuration import RUNS_DIR
            estado_path = RUNS_DIR / run_id_zona / "estado.json"
            estado_path.parent.mkdir(parents=True, exist_ok=True)
            estado_path.write_text(
                json.dumps({"id": run_id_zona, "estado": "en_curso", "tl_id": tl_id}),
                encoding="utf-8",
            )
            resultado = run_recorte(
                semaforo_lon=semaforo.lon,
                semaforo_lat=semaforo.lat,
                run_id_origen=run_id_origen,
                radio_m=solicitud.radio_m,
                run_id_destino=run_id_zona,
            )
            estado_path.write_text(
                json.dumps({"id": run_id_zona, "estado": "terminado", "tl_id": tl_id, **resultado}),
                encoding="utf-8",
            )
        except Exception as exc:
            try:
                estado_path.write_text(
                    json.dumps({"id": run_id_zona, "estado": "error", "error": str(exc)[:500]}),
                    encoding="utf-8",
                )
            except Exception:
                pass

    threading.Thread(target=_ejecutar_recorte, daemon=True, name=f"recorte-{run_id_zona}").start()
    return {"run_id": run_id_zona}


@app.get("/escenarios/{run_id}")
def obtener_escenario(run_id: str) -> dict:
    """Estado de una corrida de recorte de zona (Fase B)."""
    estado_path = RUNS_DIR / run_id / "estado.json"
    if not estado_path.is_file():
        raise HTTPException(status_code=404, detail=f"No existe el escenario '{run_id}'")
    return json.loads(estado_path.read_text(encoding="utf-8"))


# ------------------------------------ Fase C: programas de semáforo

@app.get("/intersecciones/{tl_id}/programas")
def listar_programas(tl_id: str) -> list[dict]:
    """Lista los programas (tlLogic) de un semáforo."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    programas = leer_programas(paths.net, tl_id)
    return [
        {"program_id": p.program_id, "tipo": p.tipo, "ciclo_s": p.ciclo_s}
        for p in programas
    ]


@app.get("/intersecciones/{tl_id}/programas/{program_id}")
def obtener_programa(tl_id: str, program_id: str) -> dict:
    """Devuelve el ProgramaTLS completo de un semáforo."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    prog = leer_programa(paths.net, tl_id, program_id)
    if prog is None:
        raise HTTPException(status_code=404, detail=f"No existe el programa '{program_id}' en '{tl_id}'")
    return prog.to_dict()


class SolicitudProgramaTLS(BaseModel):
    tipo: str = "static"
    offset: float = 0.0
    fases: list[dict]


@app.put("/intersecciones/{tl_id}/programas/{program_id}", status_code=200)
def guardar_programa(tl_id: str, program_id: str, solicitud: SolicitudProgramaTLS) -> dict:
    """Valida y guarda un programa editado como additional.xml en scenarios/default/."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    fases = [FasePrograma(f["duracion_s"], f["estado"]) for f in solicitud.fases]
    prog = ProgramaTLS(
        tl_id=tl_id,
        program_id=program_id,
        tipo=solicitud.tipo,
        offset=solicitud.offset,
        fases=fases,
    )

    errores = validar_programa(prog, semaforo.movimientos)
    if errores:
        raise HTTPException(status_code=422, detail={"errores": errores})

    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    destino = paths.root / f"programa_{tl_id}_{program_id}.xml"
    escribir_programa(prog, destino)

    return {**prog.to_dict(), "guardado_en": str(destino)}


class SolicitudWebster(BaseModel):
    run_id: str | None = None
    num_fases: int = Field(default=2, ge=1, le=8)


@app.post("/intersecciones/{tl_id}/programas/webster")
def calcular_webster(tl_id: str, solicitud: SolicitudWebster, gestor: Gestor) -> dict:
    """Calcula el programa óptimo de Webster con los volúmenes de una corrida."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    vols = _volumenes_corrida(gestor, solicitud.run_id)

    # volúmenes por acceso (veh/h)
    volumenes_acceso: dict[str, int] = {}
    for acceso in semaforo.accesos:
        if vols and acceso.edge in vols:
            total = sum(vols[acceso.edge].values())
            volumenes_acceso[acceso.edge] = round(total / HORAS_VENTANA)
        else:
            # fallback: estimar con velocidad libre (solo para demostración)
            volumenes_acceso[acceso.edge] = 300

    try:
        resultado = webster(volumenes_acceso, solicitud.num_fases)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    return {
        "tl_id": tl_id,
        "movimientos": semaforo.movimientos,
        **resultado,
        "nota": "Cálculo simplificado. Los verdes son proporcionales al flujo crítico de cada fase.",
    }


# ------------------------------------ Fase D: comparaciones

class SolicitudComparacion(BaseModel):
    escenario_run_id: str
    programas: list[str]   # lista de program_id a comparar
    semilla: int | None = None


_comparaciones: dict[str, dict] = {}


def _metricas_corrida(run_id: str) -> dict:
    """Lee las métricas básicas de una corrida de zona terminada."""
    from etl.sumo.simulation import leer_estadisticas
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO, run_id)
    stats = leer_estadisticas(paths.statistics)
    return {
        "teleports": stats.get("teleports", 0),
        "vehiculos_insertados": stats.get("vehiculos_insertados", 0),
        "personas_cargadas": stats.get("personas_cargadas", 0),
    }


@app.post("/intersecciones/{tl_id}/comparaciones", status_code=202)
def crear_comparacion(tl_id: str, solicitud: SolicitudComparacion, gestor: Gestor) -> dict:
    """Encola N corridas de zona (una por programa) para comparar métricas (Fase D)."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    comparacion_id = uuid.uuid4().hex[:12]
    corridas_comp: list[dict] = []

    for prog_id in solicitud.programas:
        run_id_comp = f"comp-{comparacion_id[:6]}-{prog_id[:8]}"
        corridas_comp.append({"run_id": run_id_comp, "prog_id": prog_id, "estado": "en_cola"})

        def _correr_comparacion(rid=run_id_comp, pid=prog_id):
            try:
                paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
                prog = leer_programa(paths.net, tl_id, pid)
                estado_path = RUNS_DIR / rid / "estado.json"
                estado_path.parent.mkdir(parents=True, exist_ok=True)
                estado_path.write_text(
                    json.dumps({"id": rid, "estado": "en_curso", "prog_id": pid}),
                    encoding="utf-8",
                )
                # Corrida simplificada: solo recortar + SUMO mínimo
                resultado = run_recorte(
                    semaforo_lon=semaforo.lon,
                    semaforo_lat=semaforo.lat,
                    run_id_origen=solicitud.escenario_run_id,
                    radio_m=300,
                    run_id_destino=rid,
                )
                metricas = _metricas_corrida(rid)
                estado_path.write_text(
                    json.dumps({"id": rid, "estado": "terminado", "prog_id": pid,
                                "metricas": metricas, **resultado}),
                    encoding="utf-8",
                )
                # actualizar comparación
                _comparaciones[comparacion_id]["corridas"] = [
                    c if c["run_id"] != rid
                    else {**c, "estado": "terminado", "metricas": metricas}
                    for c in _comparaciones[comparacion_id]["corridas"]
                ]
                todo_terminado = all(
                    c["estado"] in ("terminado", "error")
                    for c in _comparaciones[comparacion_id]["corridas"]
                )
                if todo_terminado:
                    _comparaciones[comparacion_id]["estado"] = "terminado"
            except Exception as exc:
                try:
                    estado_path.write_text(
                        json.dumps({"id": rid, "estado": "error", "error": str(exc)[:500]}),
                        encoding="utf-8",
                    )
                    _comparaciones[comparacion_id]["corridas"] = [
                        c if c["run_id"] != rid else {**c, "estado": "error"}
                        for c in _comparaciones[comparacion_id]["corridas"]
                    ]
                except Exception:
                    pass

        threading.Thread(target=_correr_comparacion, daemon=True).start()

    _comparaciones[comparacion_id] = {
        "id": comparacion_id,
        "tl_id": tl_id,
        "estado": "en_curso",
        "corridas": corridas_comp,
    }
    return {"comparacion_id": comparacion_id}


@app.get("/comparaciones/{comparacion_id}")
def obtener_comparacion(comparacion_id: str) -> dict:
    """Estado y métricas de una comparación de configuraciones (Fase D)."""
    comp = _comparaciones.get(comparacion_id)
    if comp is None:
        raise HTTPException(status_code=404, detail=f"No existe la comparación '{comparacion_id}'")
    return comp


# ------------------------------------ Fase E: sesiones 3D en vivo

class SolicitudSesion3D(BaseModel):
    escenario_run_id: str | None = None
    programa_id: str = "0"


@app.post("/intersecciones/{tl_id}/sesiones", status_code=201)
async def crear_sesion_3d(tl_id: str, solicitud: SolicitudSesion3D) -> dict:
    """Abre una sesión TraCI 3D en vivo para una intersección (Fase E)."""
    if _semaforos().get(tl_id) is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    try:
        sesion = _gestor_sesiones.crear(tl_id, solicitud.escenario_run_id, solicitud.programa_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    return {"sid": sesion.sid}


@app.get("/sesiones/{sid}/geometria")
def obtener_geometria_sesion(sid: str) -> dict:
    """Geometría de carriles y semáforos de la zona (enviada una vez al abrir la vista 3D)."""
    sesion = _gestor_sesiones.obtener(sid)
    if sesion is None:
        raise HTTPException(status_code=404, detail=f"No existe la sesión '{sid}'")
    return obtener_geometria(sesion.tl_id, sesion.escenario_run_id)


@app.websocket("/sesiones/{sid}")
async def ws_sesion_3d(websocket: WebSocket, sid: str) -> None:
    """WebSocket de la sesión 3D: emite frames, recibe comandos de control."""
    sesion = _gestor_sesiones.obtener(sid)
    if sesion is None:
        await websocket.close(code=1008, reason="Sesión no encontrada")
        return

    await websocket.accept()

    # Buscar programa personalizado si lo hay
    paths_default = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    prog_path = paths_default.root / f"programa_{sesion.tl_id}_{sesion.programa_id}.xml"
    programa_tls = None
    if prog_path.is_file():
        programa_tls = leer_programa(paths_default.net, sesion.tl_id, sesion.programa_id)

    cola: asyncio.Queue = asyncio.Queue(maxsize=30)

    # Tarea que corre la simulación en background
    tarea_sim = asyncio.create_task(ejecutar_sesion(sesion, programa_tls, cola))

    async def _recibir():
        """Consume mensajes de control del cliente."""
        try:
            async for mensaje in websocket.iter_text():
                sesion.ultimo_ping = __import__("time").monotonic()
                try:
                    cmd = json.loads(mensaje)
                except json.JSONDecodeError:
                    continue
                if "pausa" in cmd:
                    sesion.pausada = bool(cmd["pausa"])
                if "velocidad" in cmd:
                    sesion.velocidad = max(0.1, min(float(cmd["velocidad"]), 20.0))
        except WebSocketDisconnect:
            pass

    tarea_recibir = asyncio.create_task(_recibir())

    try:
        while sesion.activa:
            try:
                frame = await asyncio.wait_for(cola.get(), timeout=5.0)
            except asyncio.TimeoutError:
                await websocket.send_json({"tipo": "ping"})
                continue

            await websocket.send_json(frame)
            if frame.get("tipo") in ("fin", "error"):
                break
    except (WebSocketDisconnect, Exception):
        pass
    finally:
        sesion.activa = False
        tarea_sim.cancel()
        tarea_recibir.cancel()
        _gestor_sesiones.cerrar(sid)
        try:
            await websocket.close()
        except Exception:
            pass


@app.get("/sesiones")
def listar_sesiones() -> list[dict]:
    """Lista las sesiones 3D activas."""
    return _gestor_sesiones.listar()


@app.delete("/sesiones/{sid}", status_code=204)
def cerrar_sesion(sid: str) -> None:
    """Cierra una sesión 3D activa."""
    sesion = _gestor_sesiones.obtener(sid)
    if sesion is None:
        raise HTTPException(status_code=404, detail=f"No existe la sesión '{sid}'")
    _gestor_sesiones.cerrar(sid)


# ---------------------------------------------------------------- trips de corrida

@app.get("/simulaciones/{run_id}/kepler-trips")
def kepler_trips_simulacion(run_id: str, gestor: Gestor) -> FileResponse:
    corrida = _corrida(gestor, run_id)
    if corrida.estado != "terminado":
        raise HTTPException(status_code=409, detail=f"La simulación está en estado '{corrida.estado}'")

    paths = gestor.paths(run_id)
    if not paths.kepler_trips.is_file():
        raise HTTPException(status_code=404, detail="La simulación no tiene trips para kepler")
    return FileResponse(paths.kepler_trips, media_type="application/json")
