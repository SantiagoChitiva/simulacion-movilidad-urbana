import threading
from collections.abc import Callable
from dataclasses import dataclass

from .sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths, escribir_sumocfg_corrida
from .sumo.demanda import DemandaConfig
from .sumo.duarouter import DuarouterConfig, DuarouterResult, run_duarouter
from .sumo.fcd import FcdConversionResult, FcdToGeoJsonConfig, convert_fcd_to_geojson
from .sumo.kepler import KeplerTripsConfig, KeplerTripsResult, convert_fcd_to_kepler_trips
from .sumo.proceso import Cancelado, revisar_cancelacion
from .sumo.simulation import SimulationConfig, SimulationResult, run_simulation
from .sumo.trips import TripGenerationConfig, TripGenerationResult, generate_trips

__all__ = ["Cancelado", "run_pipeline", "run_etl", "simulate", "export_geojson", "export_kepler_trips"]

# Recibe la etapa en curso ("generando_demanda", "ruteando", "simulando" o "exportando")
# y su avance (0-1), o None si la etapa no informa avance
OnProgreso = Callable[[str, float | None], None]


def _sin_aviso(_etapa: str, _avance: float | None) -> None:
    pass


@dataclass(frozen=True)
class EtlResult:
    trips: TripGenerationResult
    routes: DuarouterResult


@dataclass(frozen=True)
class PipelineResult:
    etl: EtlResult
    simulation: SimulationResult
    geojson: FcdConversionResult | None   # None si no se exportan los puntos
    kepler: KeplerTripsResult


def run_etl(
    scenario_name: str = DEFAULT_SCENARIO,
    demanda: DemandaConfig | None = None,
    run_id: str | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> EtlResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)

    on_progreso("generando_demanda", None)
    trips = generate_trips(
        TripGenerationConfig(tsv_path=paths.tsv, output_path=paths.trips, demanda=demanda)
    )
    revisar_cancelacion(cancelar)

    on_progreso("ruteando", 0.0)
    routes = run_duarouter(
        DuarouterConfig(
            net_file=paths.net,
            trips_file=paths.trips,
            taz_file=paths.taz,
            output_file=paths.routes,
        ),
        on_avance=lambda a: on_progreso("ruteando", a),
        cancelar=cancelar,
    )
    return EtlResult(trips, routes)


def simulate(
    scenario_name: str = DEFAULT_SCENARIO,
    seed: int | None = None,
    run_id: str | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> SimulationResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)

    if not paths.routes.is_file():
        raise FileNotFoundError(f"Falta {paths.routes}. Ejecuta run_etl() antes de simular.")

    if paths.sumocfg != paths.sumocfg_template:
        escribir_sumocfg_corrida(paths)

    paths.fcd.parent.mkdir(parents=True, exist_ok=True)  # SUMO no crea output/

    on_progreso("simulando", 0.0)
    return run_simulation(
        SimulationConfig(sumocfg=paths.sumocfg, log_file=paths.sumo_log, seed=seed),
        on_avance=lambda a: on_progreso("simulando", a),
        cancelar=cancelar,
    )


def export_geojson(
    scenario_name: str = DEFAULT_SCENARIO, sample_every: int = 1, run_id: str | None = None
) -> FcdConversionResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    return convert_fcd_to_geojson(
        FcdToGeoJsonConfig(
            fcd_path=paths.fcd,
            output_path=paths.geojson,
            sample_every=sample_every,
        )
    )


def export_kepler_trips(
    scenario_name: str = DEFAULT_SCENARIO,
    step: float = 8.0,
    z_scale: float = 1.0,
    run_id: str | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> KeplerTripsResult:
    # step=8: con la demanda completa (~16k trips) step=5 deja un GeoJSON muy pesado para kepler
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    on_progreso("exportando", 0.0)
    return convert_fcd_to_kepler_trips(
        KeplerTripsConfig(
            fcd_path=paths.fcd,
            output_path=paths.kepler_trips,
            step=step,
            z_scale=z_scale,
        ),
        on_avance=lambda a: on_progreso("exportando", a),
        cancelar=cancelar,
    )


def run_pipeline(
    scenario_name: str = DEFAULT_SCENARIO,
    sample_every: int = 10,
    seed: int | None = None,
    demanda: DemandaConfig | None = None,
    run_id: str | None = None,
    exportar_puntos: bool = True,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> PipelineResult:
    """Encuesta → trips → duarouter → SUMO → GeoJSON. Lanza Cancelado si se activa `cancelar`."""
    etl = run_etl(scenario_name, demanda, run_id, on_progreso, cancelar)
    revisar_cancelacion(cancelar)
    simulation = simulate(scenario_name, seed, run_id, on_progreso, cancelar)
    revisar_cancelacion(cancelar)
    geojson = export_geojson(scenario_name, sample_every, run_id) if exportar_puntos else None
    kepler = export_kepler_trips(scenario_name, run_id=run_id, on_progreso=on_progreso, cancelar=cancelar)
    return PipelineResult(etl, simulation, geojson, kepler)


if __name__ == "__main__":
    result = run_pipeline()
    print("Trips   :", result.etl.trips.stats)
    print("Rutas   :", result.etl.routes.output_file)
    print("GeoJSON :", result.geojson.output_path)
    print("Features:", result.geojson.stats.features_escritos)
    print("Kepler  :", result.kepler.output_path)
    print("Stats   :", result.kepler.stats)
