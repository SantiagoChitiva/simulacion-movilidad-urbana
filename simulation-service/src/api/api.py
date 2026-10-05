from dataclasses import asdict
from functools import lru_cache
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator

from etl.sumo.configuration import DEFAULT_SCENARIO, MAX_VIAJES, ScenarioPaths
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


@app.get("/simulaciones")
def listar_simulaciones(gestor: Gestor) -> list[dict]:
    return [asdict(c) for c in gestor.listar()]


@app.get("/simulaciones/{run_id}")
def obtener_simulacion(run_id: str, gestor: Gestor) -> dict:
    return asdict(_corrida(gestor, run_id))


@app.get("/simulaciones/{run_id}/kepler-trips")
def kepler_trips_simulacion(run_id: str, gestor: Gestor) -> FileResponse:
    corrida = _corrida(gestor, run_id)
    if corrida.estado != "terminado":
        raise HTTPException(status_code=409, detail=f"La simulación está en estado '{corrida.estado}'")

    paths = gestor.paths(run_id)
    if not paths.kepler_trips.is_file():
        raise HTTPException(status_code=404, detail="La simulación no tiene trips para kepler")
    return FileResponse(paths.kepler_trips, media_type="application/json")
