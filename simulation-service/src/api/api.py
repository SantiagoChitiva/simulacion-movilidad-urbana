from fastapi import FastAPI, HTTPException, Query

from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths
from etl.sumo.geojson_reader import read_first_features

app = FastAPI(title="Simulation Service")


@app.get("/health")
def root() -> dict:
    return {"msg": "healthy"}


@app.get("/simulation-output")
def simulation_output(limit: int = Query(3, ge=1, le=100)) -> dict:
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)

    if not paths.geojson.is_file():
        raise HTTPException(
            status_code=404,
            detail="Aún no hay salida de simulación. Ejecuta el pipeline primero.",
        )

    return {
        "type": "FeatureCollection",
        "features": read_first_features(paths.geojson, limit),
    }
