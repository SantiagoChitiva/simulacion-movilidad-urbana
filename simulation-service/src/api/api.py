import asyncio
import json
import threading
import time
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
from etl.etl import run_comparacion_programas, run_recorte
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
from etl.sumo.priorizacion import a_geojson, analisis_con_cache, puntuar
from etl.sumo.vias import vias_con_cache
from etl.sumo.programas_tls import (
    ProgramaTLS, ProgramasTLSError, FasePrograma, leer_programas, leer_programa,
    escribir_programa, programa_webster, validar_programa,
)

from .jobs import GestorCorridas
from .comparacion3d import Comparacion, GestorComparaciones, correr_comparacion, mensaje_json

app = FastAPI(title="Simulation Service")

_SIN_SALIDA = "Aún no hay salida de simulación. Ejecuta el pipeline primero."

_gestor: GestorCorridas | None = None
_gestor_comparaciones: GestorComparaciones = GestorComparaciones()


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
    """Cruces sin semáforo candidatos a uno nuevo, por niveles (reglas + evidencia)."""
    vols = _volumenes_corrida(gestor, run_id, precalculada)
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    analisis = analisis_con_cache(paths.net, paths.nombres_vias, CACHE_DIR / "priorizacion.json")
    cruces, umbrales = puntuar(analisis, vols)
    notas = []
    if not analisis["hay_siniestros"]:
        notas.append("Sin datos de siniestros: ejecuta python -m etl.sumo.evidencia siniestros")
    if not analisis["hay_pois"]:
        notas.append("Sin colegios ni centros de salud: ejecuta python -m etl.sumo.evidencia pois")
    if vols is None:
        notas.append("La corrida no tiene vehroute-output: el volumen no cuenta como evidencia.")
    return {**a_geojson(cruces, umbrales, notas), "descartes": analisis["descartes"]}


@app.get("/red/vias")
def listar_vias() -> dict:
    """Edges vehiculares de la red como LineStrings (para elegir cierres en el mapa)."""
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    return vias_con_cache(paths.net, paths.nombres_vias, CACHE_DIR / "vias.json")


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
    de_red = [
        {"program_id": p.program_id, "tipo": p.tipo, "ciclo_s": p.ciclo_s, "guardado": False}
        for p in leer_programas(paths.net, tl_id)
    ]
    guardados = [
        {"program_id": p.program_id, "tipo": p.tipo, "ciclo_s": p.ciclo_s, "guardado": True}
        for archivo in sorted(paths.root.glob(f"programa_{tl_id}_*.xml"))
        for p in leer_programas(archivo, tl_id)
    ]
    return de_red + guardados


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


def _programa_guardado(tl_id: str, program_id: str) -> ProgramaTLS | None:
    archivo = ScenarioPaths.from_name(DEFAULT_SCENARIO).root / f"programa_{tl_id}_{program_id}.xml"
    programas = leer_programas(archivo, tl_id) if archivo.is_file() else []
    return programas[0] if programas else None


def _webster(semaforo: Semaforo, vols: dict[str, Counter] | None) -> tuple[ProgramaTLS, dict]:
    """Programa de Webster con los volúmenes por acceso de una corrida (veh/h)."""
    if not vols:
        raise HTTPException(
            status_code=409,
            detail="La corrida no tiene volúmenes por acceso (vehroute-output): no se puede calcular Webster.",
        )
    base = leer_programa(ScenarioPaths.from_name(DEFAULT_SCENARIO).net, semaforo.id, semaforo.programa)
    if base is None:
        raise HTTPException(status_code=404, detail=f"El semáforo '{semaforo.id}' no tiene programa en la red")
    volumenes_hora = {
        a.edge: sum(n for tipo, n in vols.get(a.edge, Counter()).items() if tipo not in ("peaton", "transporte_publico"))
        / HORAS_VENTANA
        for a in semaforo.accesos
    }
    try:
        programa, info = programa_webster(
            base, [f.luces for f in semaforo.fases], volumenes_hora, {a.edge: a.carriles for a in semaforo.accesos},
        )
    except ProgramasTLSError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return programa, {**info, "volumenes_hora": {k: round(v) for k, v in volumenes_hora.items()}}


class SolicitudWebster(BaseModel):
    run_id: str | None = None
    precalculada: Preset | None = None


@app.post("/intersecciones/{tl_id}/programas/webster")
def calcular_webster(tl_id: str, solicitud: SolicitudWebster, gestor: Gestor) -> dict:
    """Tiempos de verde de Webster con los volúmenes simulados que llegan por cada acceso."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")
    programa, info = _webster(semaforo, _volumenes_corrida(gestor, solicitud.run_id, solicitud.precalculada))
    nota = (
        "La demanda supera lo que el cruce puede despachar: se usa el ciclo máximo (150 s)."
        if info["saturado"] else
        "Cada fase recibe verde en proporción al acceso más cargado que atiende."
    )
    return {"tl_id": tl_id, **info, "programa": programa.to_dict(), "nota": nota}


# ------------------------------------ Fase D: comparaciones de programas

ETIQUETA_PROGRAMA = {"actual": "Programa actual", "webster": "Optimizado (Webster)"}


class SolicitudComparacion(BaseModel):
    run_id: str | None = None               # corrida de la que se recortan los viajes reales
    precalculada: Preset | None = None      # solo para los volúmenes de Webster
    # "actual" (el de la red), "webster" o el program_id de un programa guardado
    programas: list[str] = Field(default_factory=lambda: ["actual", "webster"], min_length=1, max_length=4)
    semilla: int = 42


_comparaciones: dict[str, dict] = {}


@app.post("/intersecciones/{tl_id}/comparaciones", status_code=202)
def crear_comparacion(tl_id: str, solicitud: SolicitudComparacion, gestor: Gestor) -> dict:
    """Corre la zona del semáforo una vez por programa, con la misma demanda (Fase D)."""
    semaforo = _semaforos().get(tl_id)
    if semaforo is None:
        raise HTTPException(status_code=404, detail=f"No existe la intersección '{tl_id}'")

    programas: dict[str, ProgramaTLS | None] = {}
    for nombre in dict.fromkeys(solicitud.programas):
        if nombre == "actual":
            programas[nombre] = None
        elif nombre == "webster":
            vols = _volumenes_corrida(gestor, solicitud.run_id, solicitud.precalculada)
            programas[nombre] = _webster(semaforo, vols)[0]
        else:
            guardado = _programa_guardado(tl_id, nombre)
            if guardado is None:
                raise HTTPException(status_code=404, detail=f"No hay un programa guardado '{nombre}' para '{tl_id}'")
            programas[nombre] = guardado

    comparacion_id = uuid.uuid4().hex[:12]
    comp = {
        "id": comparacion_id,
        "tl_id": tl_id,
        "estado": "en_curso",
        "etapa": "preparando",
        "programas": [
            {"nombre": n, "etiqueta": ETIQUETA_PROGRAMA.get(n, f"Tu programa ({n})"),
             "ciclo_s": p.ciclo_s if p else semaforo.ciclo, "estado": "en_cola", "metricas": None}
            for n, p in programas.items()
        ],
        "error": None,
    }
    _comparaciones[comparacion_id] = comp

    def _marcar(nombre: str, **cambios) -> None:
        comp["programas"] = [{**p, **cambios} if p["nombre"] == nombre else p for p in comp["programas"]]

    def _progreso(etapa: str, _avance: float | None) -> None:
        comp["etapa"] = etapa
        if etapa.startswith("simulando:"):
            _marcar(etapa.split(":", 1)[1], estado="simulando")

    def _correr() -> None:
        try:
            run_comparacion_programas(
                semaforo.lon, semaforo.lat, [a.edge for a in semaforo.accesos], programas,
                run_id_destino=f"comp-{comparacion_id}", run_id_origen=solicitud.run_id,
                semilla=solicitud.semilla,
                on_programa=lambda n, m: _marcar(n, estado="terminado", metricas=m),
                on_progreso=_progreso,
            )
            comp["estado"] = "terminado"
        except Exception as exc:  # el error se muestra en el visor
            comp["estado"] = "error"
            comp["error"] = str(exc)[:500]

    threading.Thread(target=_correr, daemon=True).start()
    return {"comparacion_id": comparacion_id}


@app.get("/comparaciones/{comparacion_id}")
def obtener_comparacion(comparacion_id: str) -> dict:
    """Estado y métricas de una comparación de programas (Fase D)."""
    comp = _comparaciones.get(comparacion_id)
    if comp is None:
        raise HTTPException(status_code=404, detail=f"No existe la comparación '{comparacion_id}'")
    return comp


# ------------------------------------ Simulador 3D comparativo (semáforo propuesto)

class SolicitudComparacion3D(BaseModel):
    lon: float
    lat: float
    run_id: str | None = None
    # tráfico de fondo por modo (veh/h; "peaton" en personas/h)
    intensidades: dict[str, float] | None = None
    # todos los nodos de SUMO del cruce (los da la priorización); vacío = solo nodo_id
    nodos: list[str] | None = None

    @model_validator(mode="after")
    def _validar_intensidades(self) -> "SolicitudComparacion3D":
        for modo, valor in (self.intensidades or {}).items():
            if not 0 <= valor <= 3000:
                raise ValueError(f"Intensidad fuera de rango para '{modo}': {valor} (0 a 3000 por hora)")
        return self


def obtener_gestor_comparaciones() -> GestorComparaciones:
    return _gestor_comparaciones


GestorComp = Annotated[GestorComparaciones, Depends(obtener_gestor_comparaciones)]


def _comparacion(gestor: GestorComparaciones, cid: str) -> Comparacion:
    comp = gestor.obtener(cid)
    if comp is None:
        raise HTTPException(status_code=404, detail=f"No existe la comparación '{cid}'")
    return comp


@app.post("/cruces/{nodo_id}/comparacion3d", status_code=202)
def crear_comparacion_3d(nodo_id: str, solicitud: SolicitudComparacion3D, gestor: GestorComp) -> dict:
    """Prepara la comparación 3D de un cruce sin semáforo: el actual vs. con semáforo propuesto.

    Recorta la zona, arma la demanda y genera la variante con semáforo en segundo plano;
    el estado se consulta en GET /comparacion3d/{id}.
    """
    run_id = solicitud.run_id if solicitud.run_id and not solicitud.run_id.startswith("precalculada-") else None
    try:
        comp = gestor.crear(
            nodo_id, solicitud.lon, solicitud.lat, run_id, solicitud.intensidades, nodos=solicitud.nodos,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    return comp.resumen()


@app.get("/comparacion3d")
def listar_comparaciones_3d(gestor: GestorComp) -> list[dict]:
    return gestor.listar()


@app.get("/comparacion3d/{cid}")
def obtener_comparacion_3d(cid: str, gestor: GestorComp) -> dict:
    return _comparacion(gestor, cid).resumen()


@app.get("/comparacion3d/{cid}/geometria")
def obtener_geometria_3d(cid: str, gestor: GestorComp) -> dict:
    """Carriles, cruces, luces del semáforo propuesto, edificios, vías y accesos de la zona."""
    comp = _comparacion(gestor, cid)
    if comp.estado != "lista" or comp.geometria is None:
        raise HTTPException(status_code=409, detail="La comparación todavía no está lista.")
    return comp.geometria


@app.delete("/comparacion3d/{cid}", status_code=204)
def cerrar_comparacion_3d(cid: str, gestor: GestorComp) -> None:
    _comparacion(gestor, cid)
    gestor.cerrar(cid)


@app.websocket("/comparacion3d/{cid}")
async def ws_comparacion_3d(websocket: WebSocket, cid: str) -> None:
    """Corre los dos lados en lockstep y emite un frame por paso; recibe comandos de control."""
    gestor = app.dependency_overrides.get(obtener_gestor_comparaciones, obtener_gestor_comparaciones)()
    comp = gestor.obtener(cid)
    if comp is None or comp.estado != "lista":
        await websocket.close(code=1008, reason="Comparación inexistente o no lista")
        return
    if comp.conectada:
        await websocket.close(code=1008, reason="La comparación ya está abierta en otra ventana")
        return

    await websocket.accept()
    comp.conectada, comp.activa = True, True
    cola: asyncio.Queue = asyncio.Queue(maxsize=8)
    hilo = threading.Thread(
        target=correr_comparacion, args=(comp, cola, asyncio.get_running_loop()),
        daemon=True, name=f"comp-{cid}",
    )
    hilo.start()

    async def _recibir() -> None:
        try:
            async for texto in websocket.iter_text():
                cmd = mensaje_json(texto)
                if cmd is None:
                    continue
                comp.ultimo_ping = time.monotonic()
                if "pausa" in cmd:
                    comp.pausada = bool(cmd["pausa"])
                if "velocidad" in cmd:
                    comp.velocidad = max(0.25, min(float(cmd["velocidad"]), 20.0))
                if "periodo_riesgo" in cmd:
                    comp.periodo_riesgo = max(0.4, min(float(cmd["periodo_riesgo"]), 30.0))
                if "control" in cmd:
                    # se lee en cada paso del bucle: no hace falta pasar por la cola
                    try:
                        comp.acelerar = max(-1, min(1, int((cmd["control"] or {}).get("acelerar", 0))))
                    except (TypeError, ValueError, AttributeError):
                        pass
                if "seguir" in cmd or "inyectar" in cmd or "manual" in cmd or "giro" in cmd:
                    comp.comandos.put(cmd)
        except WebSocketDisconnect:
            pass

    tarea_recibir = asyncio.create_task(_recibir())
    try:
        while True:
            try:
                msg = await asyncio.wait_for(cola.get(), timeout=5.0)
            except asyncio.TimeoutError:
                if tarea_recibir.done():
                    break
                await websocket.send_json({"tipo": "ping"})
                continue
            await websocket.send_json(msg)
            if msg.get("tipo") in ("fin", "error"):
                break
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        comp.activa = False
        comp.conectada = False
        comp.ultimo_ping = time.monotonic()
        tarea_recibir.cancel()
        await asyncio.to_thread(hilo.join, 10)
        try:
            await websocket.close()
        except RuntimeError:
            pass


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
