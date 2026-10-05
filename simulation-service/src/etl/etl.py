from dataclasses import dataclass

from .sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths
from .sumo.duarouter import DuarouterConfig, DuarouterResult, run_duarouter
from .sumo.fcd import FcdConversionResult, FcdToGeoJsonConfig, convert_fcd_to_geojson
from .sumo.kepler import KeplerTripsConfig, KeplerTripsResult, convert_fcd_to_kepler_trips
from .sumo.simulation import SimulationConfig, SimulationResult, run_simulation
from .sumo.trips import TripGenerationConfig, TripGenerationResult, generate_trips


@dataclass(frozen=True)
class EtlResult:
    trips: TripGenerationResult
    routes: DuarouterResult


@dataclass(frozen=True)
class PipelineResult:
    etl: EtlResult
    simulation: SimulationResult
    geojson: FcdConversionResult
    kepler: KeplerTripsResult


def run_etl(scenario_name: str = DEFAULT_SCENARIO) -> EtlResult:
    paths = ScenarioPaths.from_name(scenario_name)

    trips = generate_trips(
        TripGenerationConfig(tsv_path=paths.tsv, output_path=paths.trips)
    )
    routes = run_duarouter(
        DuarouterConfig(
            net_file=paths.net,
            trips_file=paths.trips,
            taz_file=paths.taz,
            output_file=paths.routes,
        )
    )
    return EtlResult(trips, routes)


def simulate(scenario_name: str = DEFAULT_SCENARIO, seed: int | None = None) -> SimulationResult:
    paths = ScenarioPaths.from_name(scenario_name)

    if not paths.routes.is_file():
        raise FileNotFoundError(f"Falta {paths.routes}. Ejecuta run_etl() antes de simular.")

    paths.fcd.parent.mkdir(parents=True, exist_ok=True)  # SUMO no crea output/

    return run_simulation(
        SimulationConfig(sumocfg=paths.sumocfg, log_file=paths.sumo_log, seed=seed)
    )


def export_geojson(
    scenario_name: str = DEFAULT_SCENARIO, sample_every: int = 1
) -> FcdConversionResult:
    paths = ScenarioPaths.from_name(scenario_name)
    return convert_fcd_to_geojson(
        FcdToGeoJsonConfig(
            fcd_path=paths.fcd,
            output_path=paths.geojson,
            sample_every=sample_every,
        )
    )


def export_kepler_trips(
    scenario_name: str = DEFAULT_SCENARIO, step: float = 8.0, z_scale: float = 1.0
) -> KeplerTripsResult:
    # step=8: con la demanda completa (~16k trips) step=5 deja un GeoJSON muy pesado para kepler
    paths = ScenarioPaths.from_name(scenario_name)
    return convert_fcd_to_kepler_trips(
        KeplerTripsConfig(
            fcd_path=paths.fcd,
            output_path=paths.kepler_trips,
            step=step,
            z_scale=z_scale,
        )
    )


def run_pipeline(
    scenario_name: str = DEFAULT_SCENARIO,
    sample_every: int = 10,
    seed: int | None = None,
) -> PipelineResult:
    etl = run_etl(scenario_name)
    simulation = simulate(scenario_name, seed)
    geojson = export_geojson(scenario_name, sample_every)
    kepler = export_kepler_trips(scenario_name)
    return PipelineResult(etl, simulation, geojson, kepler)


if __name__ == "__main__":
    result = run_pipeline()
    print("Trips   :", result.etl.trips.stats)
    print("Rutas   :", result.etl.routes.output_file)
    print("GeoJSON :", result.geojson.output_path)
    print("Features:", result.geojson.stats.features_escritos)
    print("Kepler  :", result.kepler.output_path)
    print("Stats   :", result.kepler.stats)
