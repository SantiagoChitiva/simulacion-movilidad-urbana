import threading
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .sumo.cierres import CierreVial, escribir_rerouter
from .sumo.configuration import DEFAULT_SCENARIO, RUNS_DIR, ScenarioPaths, escribir_sumocfg_corrida
from .sumo.demanda import DemandaConfig
from .sumo.duarouter import DuarouterConfig, DuarouterResult, run_duarouter
from .sumo.enums.vehicle_type import VehicleType
from .sumo.estilos import EstiloConductor, PARAMS_ESTILO
from .sumo.fcd import FcdConversionResult, FcdToGeoJsonConfig, convert_fcd_to_geojson
from .sumo.kepler import KeplerTripsConfig, KeplerTripsResult, convert_fcd_to_kepler_trips
from .sumo.proceso import Cancelado, revisar_cancelacion
from .sumo.simulation import SimulationConfig, SimulationResult, leer_estadisticas, run_simulation
from .sumo.demanda_zona import DemandaZonaConfig, DemandaZonaStats, generar_demanda_zona
from .sumo.semaforo_nuevo import SemaforoNuevoConfig, agregar_semaforo
from .sumo.subred import SubredConfig, SubredDemandaConfig, SubredStats, recortar_demanda, recortar_red
from .sumo.trips import TripGenerationConfig, TripGenerationResult, generate_trips

__all__ = [
    "Cancelado", "run_pipeline", "run_etl", "simulate", "export_geojson", "export_kepler_trips",
    "resumen_corrida", "run_recorte", "run_escenario_semaforo",
]

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
    additional_files: list[Path] | None = None,
) -> SimulationResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)

    if not paths.routes.is_file():
        raise FileNotFoundError(f"Falta {paths.routes}. Ejecuta run_etl() antes de simular.")

    if paths.sumocfg != paths.sumocfg_template:
        escribir_sumocfg_corrida(paths, additional_files=additional_files)

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
    estilo: EstiloConductor | None = None,
    cierres: list[CierreVial] | None = None,
) -> PipelineResult:
    """Encuesta → trips → duarouter → SUMO → GeoJSON. Lanza Cancelado si se activa `cancelar`."""
    # Preparar archivos adicionales para el sumocfg
    additional_files: list[Path] = []

    if run_id:
        run_dir = RUNS_DIR / run_id
        run_dir.mkdir(parents=True, exist_ok=True)

        # Estilo de conducción: genera vtypes adicional con parámetros modificados
        if estilo is not None and estilo != EstiloConductor.normal:
            from .sumo.vtypes import VTYPES
            params = PARAMS_ESTILO[estilo]
            raiz = ET.Element("additional")
            for vt in VTYPES.values():
                attrs = vt.to_xml_attrs()
                if attrs.get("vClass") not in ("pedestrian", "bicycle"):
                    attrs.update(params)
                ET.SubElement(raiz, "vType", attrs)
            estilo_xml = run_dir / "vtypes_estilo.xml"
            tree = ET.ElementTree(raiz)
            ET.indent(tree, space="  ")
            tree.write(str(estilo_xml), encoding="UTF-8", xml_declaration=True)
            additional_files.append(estilo_xml)

        # Cierres viales: genera rerouter XML
        if cierres:
            cierres_xml = run_dir / "cierres.xml"
            escribir_rerouter(cierres, cierres_xml)
            additional_files.append(cierres_xml)

    etl = run_etl(scenario_name, demanda, run_id, on_progreso, cancelar)
    revisar_cancelacion(cancelar)
    simulation = simulate(
        scenario_name, seed, run_id, on_progreso, cancelar,
        additional_files=additional_files if additional_files else None,
    )
    revisar_cancelacion(cancelar)
    geojson = export_geojson(scenario_name, sample_every, run_id) if exportar_puntos else None
    kepler = export_kepler_trips(scenario_name, run_id=run_id, on_progreso=on_progreso, cancelar=cancelar)
    return PipelineResult(etl, simulation, geojson, kepler)


def resumen_corrida(resultado: PipelineResult, paths: ScenarioPaths) -> dict[str, Any]:
    """Lo que se muestra de una corrida terminada: viajes, trips y estadísticas de SUMO."""
    return {
        "viajes_generados": resultado.etl.trips.stats.viajes_generados,
        "viajes_por_modo": dict(resultado.etl.trips.stats.por_modo),
        "trips_kepler": resultado.kepler.stats.trips_escritos,
        **leer_estadisticas(paths.statistics),
    }


def run_recorte(
    semaforo_lon: float,
    semaforo_lat: float,
    run_id_origen: str | None,
    radio_m: float,
    run_id_destino: str,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> dict[str, Any]:
    """Recorta la red y la demanda alrededor de un semáforo y deja el resultado en runs/<run_id_destino>/.

    Retorna un dict con las rutas de los archivos creados.
    """
    paths_origen = ScenarioPaths.from_name(DEFAULT_SCENARIO, run_id_origen) if run_id_origen else ScenarioPaths.from_name(DEFAULT_SCENARIO)
    destino_dir = RUNS_DIR / run_id_destino
    destino_dir.mkdir(parents=True, exist_ok=True)

    zona_net = destino_dir / "zona.net.xml"
    zona_rou = destino_dir / "zona.rou.xml"

    stats = SubredStats()

    on_progreso("recortando_red", None)
    cfg_red = SubredConfig(
        net_origen=paths_origen.net,
        centro_lonlat=(semaforo_lon, semaforo_lat),
        radio_m=radio_m,
        destino=zona_net,
    )
    resultado_red = recortar_red(cfg_red, stats=stats, cancelar=cancelar)
    revisar_cancelacion(cancelar)

    on_progreso("recortando_demanda", None)
    if paths_origen.routes.is_file():
        cfg_demanda = SubredDemandaConfig(
            zona_net=zona_net,
            rou_xml=paths_origen.routes,
            destino=zona_rou,
            net_orig=paths_origen.net,
            vehroute_xml=paths_origen.vehroute if paths_origen.vehroute.is_file() else None,
        )
        recortar_demanda(cfg_demanda, stats=stats, cancelar=cancelar)

    return {
        "zona_net": str(zona_net),
        "zona_rou": str(zona_rou) if zona_rou.is_file() else None,
        "bbox": resultado_red.bbox,
        "demanda_recortada": stats.demanda_recortada,
    }


def _corrida_con_rutas(run_id_preferida: str | None) -> ScenarioPaths | None:
    """La corrida cuyas rutas se recortan: la pedida o, si no tiene, la más reciente que sí."""
    candidatas: list[str] = [run_id_preferida] if run_id_preferida else []
    if RUNS_DIR.is_dir():
        otras = sorted(
            (d for d in RUNS_DIR.iterdir() if d.is_dir() and not d.name.startswith(("zona-", "sem-", "sesion"))),
            key=lambda d: d.stat().st_mtime, reverse=True,
        )
        candidatas += [d.name for d in otras]
    for run_id in candidatas:
        paths = ScenarioPaths.from_name(DEFAULT_SCENARIO, run_id)
        if paths.vehroute.is_file() or paths.routes.is_file():
            return paths
    return None


def run_escenario_semaforo(
    nodo_id: str,
    nodo_lon: float,
    nodo_lat: float,
    run_id_destino: str,
    run_id_origen: str | None = None,
    radio_m: float = 350,
    intensidades: dict[str, float] | None = None,
    ciclo_s: int | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
) -> dict[str, Any]:
    """Prepara la comparación "sin semáforo / con semáforo propuesto" de un cruce.

    Deja en runs/<run_id_destino>/:
    - zona.net.xml: la red recortada tal como está (escenario actual, sin semáforo),
    - zona_tls.net.xml: la misma red con un semáforo nuevo en `nodo_id`,
    - zona.rou.xml (si alguna corrida tiene rutas), fondo_*.trips.xml y vtypes.add.xml:
      la demanda, idéntica para los dos lados.
    """
    paths_net = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    destino_dir = RUNS_DIR / run_id_destino
    destino_dir.mkdir(parents=True, exist_ok=True)
    zona_net = destino_dir / "zona.net.xml"
    zona_rou = destino_dir / "zona.rou.xml"

    on_progreso("recortando_red", None)
    resultado_red = recortar_red(
        SubredConfig(paths_net.net, (nodo_lon, nodo_lat), radio_m, zona_net), cancelar=cancelar,
    )

    on_progreso("recortando_demanda", None)
    origen = _corrida_con_rutas(run_id_origen)
    rutas_reales: Path | None = None
    if origen is not None:
        try:
            recortar_demanda(SubredDemandaConfig(
                zona_net=zona_net, rou_xml=origen.routes, destino=zona_rou, net_orig=paths_net.net,
                vehroute_xml=origen.vehroute if origen.vehroute.is_file() else None,
            ), cancelar=cancelar)
            rutas_reales = zona_rou
        except (RuntimeError, FileNotFoundError):
            rutas_reales = None   # sin viajes reales: la zona queda solo con fondo sintético

    on_progreso("generando_fondo", None)
    stats_demanda = DemandaZonaStats()
    cfg_demanda = DemandaZonaConfig(zona_net=zona_net, destino_dir=destino_dir)
    if intensidades is not None:
        cfg_demanda = DemandaZonaConfig(zona_net=zona_net, destino_dir=destino_dir, intensidades=intensidades)
    demanda = generar_demanda_zona(cfg_demanda, rutas_reales, stats=stats_demanda, cancelar=cancelar)

    on_progreso("instalando_semaforo", None)
    semaforo = agregar_semaforo(
        SemaforoNuevoConfig(zona_net, nodo_id, destino_dir / "zona_tls.net.xml", ciclo_s=ciclo_s),
        cancelar=cancelar,
    )

    return {
        "nodo_id": nodo_id,
        "zona_net": str(zona_net),
        "zona_tls_net": str(semaforo.net),
        "demanda": [str(a) for a in demanda.archivos],
        "vtypes": str(demanda.vtypes),
        "fuente_demanda": demanda.fuente,
        "corrida_origen": origen.run_dir.name if origen is not None and rutas_reales else None,
        "viajes_reales": stats_demanda.viajes_reales,
        "viajes_sinteticos": stats_demanda.viajes_sinteticos,
        "bbox": resultado_red.bbox,
        "fases": semaforo.fases,
        "ciclo_s": semaforo.ciclo_s,
    }


if __name__ == "__main__":
    result = run_pipeline()
    print("Trips   :", result.etl.trips.stats)
    print("Rutas   :", result.etl.routes.output_file)
    print("GeoJSON :", result.geojson.output_path)
    print("Features:", result.geojson.stats.features_escritos)
    print("Kepler  :", result.kepler.output_path)
    print("Stats   :", result.kepler.stats)
