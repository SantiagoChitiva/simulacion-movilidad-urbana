from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse

from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths
from etl.sumo.geojson_reader import read_first_features

app = FastAPI(title="Simulation Service")

_SIN_SALIDA = "Aún no hay salida de simulación. Ejecuta el pipeline primero."


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
