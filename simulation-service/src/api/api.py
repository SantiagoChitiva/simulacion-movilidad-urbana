from dataclasses import asdict
from functools import lru_cache
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator

from etl import precalculadas
from etl.sumo.configuration import (
    CACHE_DIR, DEFAULT_SCENARIO, MAX_VIAJES, ArchivosPrecalculada, ScenarioPaths,
)
from etl.sumo.intersecciones import (
    HORAS_VENTANA, Semaforo, a_feature, catalogo, con_volumenes, volumenes,
)
from etl.sumo.demanda import (
    INFO_MODOS, PRESETS, DemandaConfig, Preset, cargar_dia, cargar_ventana, conteos_preset,
)
from etl.sumo.enums.transport_mode import TransportMode
from etl.sumo.geojson_reader import read_first_features

from .jobs import GestorCorridas

app = FastAPI(title="Simulation Service")

_SIN_SALIDA = "Aún no hay salida de simulación. Ejecuta el pipeline primero."

_gestor: GestorCorridas | None = None


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


# ------------------------------------------------------------ simulaciones

class SolicitudSimulacion(BaseModel):
    preset: Preset = Preset.ENCUESTA
    conteos: dict[TransportMode, Annotated[int, Field(ge=0, le=MAX_VIAJES)]]
    semilla: int | None = Field(default=None, ge=0)

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
    return asdict(gestor.crear(demanda, solicitud.semilla))


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
        # Content-Length es el tamaño comprimido; el visor mide el avance con el original
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


@app.get("/simulaciones/{run_id}/kepler-trips")
def kepler_trips_simulacion(run_id: str, gestor: Gestor) -> FileResponse:
    corrida = _corrida(gestor, run_id)
    if corrida.estado != "terminado":
        raise HTTPException(status_code=409, detail=f"La simulación está en estado '{corrida.estado}'")

    paths = gestor.paths(run_id)
    if not paths.kepler_trips.is_file():
        raise HTTPException(status_code=404, detail="La simulación no tiene trips para kepler")
    return FileResponse(paths.kepler_trips, media_type="application/json")
