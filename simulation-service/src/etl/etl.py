import threading
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .sumo.aforos import cargar_aforos
from .sumo.asignacion import AsignacionConfig, run_asignacion
from .sumo.cierres import CierreVial, escribir_rerouter
from .sumo.comparacion_programas import (
    ComparacionProgramaConfig, ComparacionProgramaStats, agregar_semillas, correr_programa,
)
from .sumo.configuration import (
    DEFAULT_SCENARIO, HORA_FIN, HORA_INI, PREFIJO_SALIDAS, RUNS_DIR, ScenarioPaths, escribir_sumocfg_corrida,
)
from .sumo.demanda import DemandaConfig
from .sumo.duarouter import DuarouterConfig, DuarouterResult, run_duarouter
from .sumo.enums.vehicle_type import VehicleType
from .sumo.estilos import EstiloConductor, PARAMS_ESTILO
from .sumo.fcd import FcdConversionResult, FcdToGeoJsonConfig, convert_fcd_to_geojson
from .sumo.kepler import KeplerTripsConfig, KeplerTripsResult, convert_fcd_to_kepler_trips
from .sumo.proceso import Cancelado, revisar_cancelacion
from .sumo.simulation import SimulationConfig, SimulationResult, leer_estadisticas, run_simulation
from .sumo.demanda_zona import DemandaZonaConfig, DemandaZonaResult, DemandaZonaStats, generar_demanda_zona
from .sumo.programas_tls import ProgramaTLS
from .sumo.semaforo_nuevo import (
    SemaforoNuevoConfig, accesos_semaforo, agregar_semaforo, programa_webster_propuesto, volumenes_accesos,
)
from .sumo.subred import (
    SubredConfig, SubredDemandaConfig, SubredStats, caminatas_por_origen_destino, recortar_demanda, recortar_red,
)
from .sumo.trafico_paso import archivo_trafico_paso
from .sumo.transporte_publico import archivos_transporte_publico
from .sumo.trips import TripGenerationConfig, TripGenerationResult, generate_trips
from .sumo.validacion import ValidacionConfig, escribir_conteos, periodo_de, validar

__all__ = [
    "Cancelado", "run_pipeline", "run_etl", "simulate", "export_geojson", "export_kepler_trips",
    "resumen_corrida", "run_recorte", "run_escenario_semaforo", "run_comparacion_programas",
]

# Recibe la etapa en curso ("generando_demanda", "ruteando", "simulando" o "exportando")
# y su avance (0-1), o None si la etapa no informa avance
OnProgreso = Callable[[str, float | None], None]

# tope de vehículos a la vez en la red cuando se suma el tráfico de paso (la plantilla tiene 5000)
MAX_VEHICULOS_PASO = 25000


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
    validacion: dict | None = None        # resumen del GEH (validacion.py), si hay aforos


def run_etl(
    scenario_name: str = DEFAULT_SCENARIO,
    demanda: DemandaConfig | None = None,
    run_id: str | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
    reutilizar_rutas: bool = False,
) -> EtlResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    demanda = demanda or DemandaConfig()
    hora_ini, hora_fin = demanda.horas
    publico = archivos_transporte_publico(paths) if demanda.transporte_publico else None

    on_progreso("generando_demanda", None)
    trips = generate_trips(
        TripGenerationConfig(
            tsv_path=paths.tsv, output_path=paths.trips, demanda=demanda,
            hora_ini=hora_ini, hora_fin=hora_fin, transporte_publico_real=publico is not None,
        )
    )
    revisar_cancelacion(cancelar)

    on_progreso("ruteando", 0.0)
    if reutilizar_rutas and _rutas_completas(paths.routes):
        # reanudación: el ruteo ya había terminado (los viajes se regeneran igual, son deterministas)
        return EtlResult(trips, DuarouterResult(output_file=paths.routes, stdout="", stderr=""))
    if demanda.asignacion_iterativa:
        if publico is not None:
            raise ValueError("La asignación iterativa todavía no admite transporte público real; desactiva una de las dos.")
        routes = run_asignacion(
            AsignacionConfig(paths.net, paths.trips, paths.taz, paths.routes, ventana=(hora_ini, hora_fin)),
            on_avance=lambda a: on_progreso("ruteando", a),
            cancelar=cancelar,
        )
    else:
        routes = run_duarouter(
            DuarouterConfig(
                net_file=paths.net,
                trips_file=paths.trips,
                taz_file=paths.taz,
                output_file=paths.routes,
                ventana=(hora_ini, hora_fin),
                # los buses salen de duarouter junto con los viajes que los usan
                rutas_extra=(publico.vehiculos,) if publico else (),
                adicionales_extra=(publico.paradas,) if publico else (),
            ),
            on_avance=lambda a: on_progreso("ruteando", a),
            cancelar=cancelar,
        )
    return EtlResult(trips, routes)


def _xml_cerrado(path: Path, cierre: bytes) -> bool:
    """El archivo existe y ya tiene su etiqueta de cierre (SUMO y duarouter escriben en streaming
    y crean el archivo al empezar, así que existir no basta)."""
    if not path.is_file() or path.stat().st_size < 100:
        return False
    with path.open("rb") as f:
        f.seek(max(0, path.stat().st_size - 200))
        return cierre in f.read()


def _rutas_completas(rutas: Path) -> bool:
    return _xml_cerrado(rutas, b"</routes>")


def simulate(
    scenario_name: str = DEFAULT_SCENARIO,
    seed: int | None = None,
    run_id: str | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
    additional_files: list[Path] | None = None,
    demanda: DemandaConfig | None = None,
) -> SimulationResult:
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    demanda = demanda or DemandaConfig()

    if not paths.routes.is_file():
        raise FileNotFoundError(f"Falta {paths.routes}. Ejecuta run_etl() antes de simular.")

    if paths.sumocfg != paths.sumocfg_template:
        rutas_extra, adicionales = [], list(additional_files or [])
        publico = archivos_transporte_publico(paths) if demanda.transporte_publico else None
        if publico is not None:
            adicionales.append(publico.paradas)   # los buses ya vienen en las rutas de duarouter
        paso = archivo_trafico_paso(demanda.horas[0]) if demanda.trafico_paso else None
        if demanda.trafico_paso and paso is None:
            raise FileNotFoundError("No hay tráfico de paso para esta ventana. Ejecuta python -m etl.sumo.trafico_paso.")
        if paso is not None:
            rutas_extra.append(paso)
        escribir_sumocfg_corrida(
            paths, additional_files=adicionales, route_files=rutas_extra, ventana=demanda.horas,
            # con el tráfico de paso hay varias veces más vehículos a la vez en la red
            max_vehiculos=MAX_VEHICULOS_PASO if paso is not None else None,
            # el FCD con el tráfico de paso pasa de 4 GB; kepler muestrea cada 8 s, así que 4 s basta
            periodo_fcd=4 if paso is not None else None,
        )

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
    reanudar: bool = False,
) -> PipelineResult:
    """Encuesta → trips → duarouter → SUMO → GeoJSON. Lanza Cancelado si se activa `cancelar`.

    Con `reanudar` se aprovecha lo que una corrida interrumpida ya terminó: las rutas si
    duarouter alcanzó a cerrarlas y la simulación si SUMO escribió sus estadísticas finales.
    """
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

        # Conteos en los puntos de aforo, para validar con el GEH al terminar
        puntos_aforo = cargar_aforos()
        if puntos_aforo:
            paths_run = ScenarioPaths.from_name(scenario_name, run_id)
            # SUMO antepone el output-prefix del sumocfg ("usaquen_am.") también a esta salida
            salida = paths_run.conteos.with_name(paths_run.conteos.name.removeprefix(PREFIJO_SALIDAS))
            additional_files.append(escribir_conteos(
                puntos_aforo, paths_run.conteos_add, salida.resolve(), *(demanda or DemandaConfig()).horas,
            ))

    etl = run_etl(scenario_name, demanda, run_id, on_progreso, cancelar, reutilizar_rutas=reanudar)
    revisar_cancelacion(cancelar)
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    if reanudar and _xml_cerrado(paths.statistics, b"</statistics>") and _xml_cerrado(paths.fcd, b"</fcd-export>"):
        # SUMO cierra el statistic-output y el FCD solo al terminar: la simulación estaba completa
        simulation = SimulationResult(sumocfg=paths.sumocfg, stdout="", stderr="")
    else:
        simulation = simulate(
            scenario_name, seed, run_id, on_progreso, cancelar,
            additional_files=additional_files if additional_files else None,
            demanda=demanda,
        )
    revisar_cancelacion(cancelar)
    geojson = export_geojson(scenario_name, sample_every, run_id) if exportar_puntos else None
    kepler = export_kepler_trips(scenario_name, run_id=run_id, on_progreso=on_progreso, cancelar=cancelar)
    validacion = validar_corrida(scenario_name, run_id, demanda)
    return PipelineResult(etl, simulation, geojson, kepler, validacion)


def validar_corrida(
    scenario_name: str = DEFAULT_SCENARIO, run_id: str | None = None, demanda: DemandaConfig | None = None,
) -> dict | None:
    """GEH contra los aforos si la corrida escribió los conteos (None si no hay aforos)."""
    paths = ScenarioPaths.from_name(scenario_name, run_id)
    demanda = demanda or DemandaConfig()
    if not paths.conteos.is_file():
        return None
    modos = ["auto", "moto", "taxi", "especial", "escolar", "bici"]
    if demanda.transporte_publico and archivos_transporte_publico(paths) is not None:
        modos.append("bus")
    resultado = validar(ValidacionConfig(
        conteos=paths.conteos, destino=paths.validacion, destino_csv=paths.validacion_csv,
        periodo=periodo_de(demanda.horas[0]), modos_simulados=tuple(modos),
        etiqueta="con tráfico de paso calibrado con aforos" if demanda.trafico_paso else "solo viajes de la encuesta",
    ))
    return resultado.resumen


def resumen_corrida(resultado: PipelineResult, paths: ScenarioPaths) -> dict[str, Any]:
    """Lo que se muestra de una corrida terminada: viajes, trips y estadísticas de SUMO."""
    resumen = {
        "viajes_generados": resultado.etl.trips.stats.viajes_generados,
        "viajes_por_modo": dict(resultado.etl.trips.stats.por_modo),
        "trips_kepler": resultado.kepler.stats.trips_escritos,
        **leer_estadisticas(paths.statistics),
    }
    validacion = getattr(resultado, "validacion", None)
    if validacion is not None:
        resumen["validacion"] = {k: v for k, v in validacion.items() if k != "filas"}
    return resumen


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


@dataclass(frozen=True)
class _Zona:
    net: Path
    red: Any                      # SubredResult
    demanda: DemandaZonaResult
    stats: DemandaZonaStats
    origen: ScenarioPaths | None
    rutas_reales: Path | None


def _preparar_zona(
    lon: float, lat: float, radio_m: float, destino_dir: Path, run_id_origen: str | None,
    intensidades: dict[str, float] | None, on_progreso: OnProgreso, cancelar: threading.Event | None,
    peatonal: bool = False, inicio: float = HORA_INI,
) -> _Zona:
    """Red recortada y demanda de una zona: viajes reales que pasan por ella más fondo sintético.

    Con `peatonal` la zona lleva andenes y cebras, y las caminatas reales se rutean de nuevo
    sobre ellos (`caminatas_por_origen_destino`).
    """
    paths_net = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    zona_net = destino_dir / "zona.net.xml"
    zona_rou = destino_dir / "zona.rou.xml"

    on_progreso("recortando_red", None)
    resultado_red = recortar_red(
        SubredConfig(paths_net.net, (lon, lat), radio_m, zona_net, peatonal=peatonal), cancelar=cancelar,
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
            if peatonal:
                caminatas_por_origen_destino(zona_rou)
        except (RuntimeError, FileNotFoundError):
            rutas_reales = None   # sin viajes reales: la zona queda solo con fondo sintético

    on_progreso("generando_fondo", None)
    stats_demanda = DemandaZonaStats()
    cfg_demanda = DemandaZonaConfig(zona_net=zona_net, destino_dir=destino_dir, inicio=inicio)
    if intensidades is not None:
        cfg_demanda = DemandaZonaConfig(zona_net=zona_net, destino_dir=destino_dir, intensidades=intensidades, inicio=inicio)
    demanda = generar_demanda_zona(cfg_demanda, rutas_reales, stats=stats_demanda, cancelar=cancelar)
    return _Zona(zona_net, resultado_red, demanda, stats_demanda, origen, rutas_reales)


def run_comparacion_programas(
    lon: float,
    lat: float,
    accesos: list[str],
    programas: dict[str, ProgramaTLS | None],
    run_id_destino: str,
    run_id_origen: str | None = None,
    radio_m: float = 300,
    semilla: int = 42,
    on_programa: Callable[[str, dict], None] = lambda _n, _m: None,
    on_progreso: OnProgreso = _sin_aviso,
    cancelar: threading.Event | None = None,
    repeticiones: int = 1,
    inicio: float = HORA_INI,
) -> dict[str, dict]:
    """Corre la misma zona y demanda una vez por programa y semilla, y devuelve sus métricas.

    `programas` va de un nombre ("actual", "webster", ...) al programa que se carga encima
    del de la red (None: el de la red). Cada programa se simula con `repeticiones` semillas
    seguidas desde `semilla` y se reporta la media y el rango (agregar_semillas).
    `on_programa` recibe las métricas de cada uno apenas terminan, para mostrar resultados
    parciales. `inicio` es la hora (s) en que empieza la hora simulada: la de la ventana de
    la corrida de la que se recortan los viajes.
    """
    destino_dir = RUNS_DIR / run_id_destino
    destino_dir.mkdir(parents=True, exist_ok=True)
    # con viajes reales no se suma fondo sintético: Webster se calcula con esos mismos
    # volúmenes, y el fondo inventado cambiaría la demanda contra la que se optimizó
    hay_reales = _corrida_con_rutas(run_id_origen) is not None
    zona = _preparar_zona(lon, lat, radio_m, destino_dir, run_id_origen, {} if hay_reales else None,
                          on_progreso, cancelar, inicio=inicio)
    stats = ComparacionProgramaStats()
    resultados: dict[str, dict] = {}
    for nombre, programa in programas.items():
        on_progreso(f"simulando:{nombre}", None)
        corridas = []
        for k in range(max(1, repeticiones)):
            revisar_cancelacion(cancelar)
            resultado = correr_programa(ComparacionProgramaConfig(
                zona_net=zona.net, demanda=zona.demanda.archivos, vtypes=zona.demanda.vtypes,
                accesos=accesos, destino_dir=destino_dir / nombre / f"semilla_{semilla + k}", programa=programa,
                semilla=semilla + k, inicio=inicio,
            ), stats=stats, cancelar=cancelar)
            corridas.append(resultado.metricas)
        resultados[nombre] = agregar_semillas(corridas)
        on_programa(nombre, resultados[nombre])
    return resultados


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
    nodos: list[str] | None = None,
    inicio: float = HORA_INI,
    programa: str = "netconvert",
) -> dict[str, Any]:
    """Prepara la comparación "sin semáforo / con semáforo propuesto" de un cruce.

    `nodos` son todos los nodos de SUMO del cruce (p. ej. las dos calzadas de una
    avenida); el semáforo propuesto los controla a todos con un único programa.

    Deja en runs/<run_id_destino>/:
    - zona.net.xml: la red recortada tal como está (escenario actual, sin semáforo),
    - zona_tls.net.xml: la misma red con un semáforo nuevo en `nodo_id`,
    - zona.rou.xml (si alguna corrida tiene rutas), fondo_*.trips.xml y vtypes.add.xml:
      la demanda, idéntica para los dos lados.
    """
    destino_dir = RUNS_DIR / run_id_destino
    destino_dir.mkdir(parents=True, exist_ok=True)
    zona = _preparar_zona(nodo_lon, nodo_lat, radio_m, destino_dir, run_id_origen, intensidades, on_progreso, cancelar,
                          peatonal=True, inicio=inicio)
    zona_net, resultado_red, demanda = zona.net, zona.red, zona.demanda
    stats_demanda, origen, rutas_reales = zona.stats, zona.origen, zona.rutas_reales

    on_progreso("instalando_semaforo", None)
    semaforo = agregar_semaforo(
        SemaforoNuevoConfig(
            zona_net, nodo_id, destino_dir / "zona_tls.net.xml", ciclo_s=ciclo_s, nodos=tuple(nodos or ()),
        ),
        cancelar=cancelar,
    )
    fases, ciclo, programa_adicional, webster_info = semaforo.fases, semaforo.ciclo_s, None, None
    if programa == "webster":
        # los verdes de Webster con los volúmenes que de verdad llegan por cada acceso en
        # una hora de esta misma demanda (sobre la red sin semáforo)
        on_progreso("calculando_webster", None)
        enlaces, _ = accesos_semaforo(semaforo.net, semaforo.tl_id)
        volumenes = volumenes_accesos(
            zona_net, demanda.archivos, demanda.vtypes, sorted(enlaces), destino_dir / "webster", inicio,
            cancelar=cancelar,
        )
        ruta, webster_info = programa_webster_propuesto(
            semaforo.net, semaforo.tl_id, volumenes, destino_dir / "programa_propuesto.add.xml",
        )
        programa_adicional = [str(ruta)]
        fases, ciclo = webster_info["fases"], webster_info["ciclo_s"]

    return {
        "inicio": inicio,
        "programa": programa,
        "programa_adicional": programa_adicional,
        "webster": webster_info,
        "nodo_id": nodo_id,
        "nodos": list(dict.fromkeys([nodo_id, *(nodos or [])])),
        "tl_id": semaforo.tl_id,
        "zona_net": str(zona_net),
        "zona_tls_net": str(semaforo.net),
        "demanda": [str(a) for a in demanda.archivos],
        "vtypes": str(demanda.vtypes),
        "fuente_demanda": demanda.fuente,
        "corrida_origen": origen.run_dir.name if origen is not None and rutas_reales else None,
        "viajes_reales": stats_demanda.viajes_reales,
        "viajes_sinteticos": stats_demanda.viajes_sinteticos,
        "bbox": resultado_red.bbox,
        "fases": fases,
        "ciclo_s": ciclo,
    }


if __name__ == "__main__":
    result = run_pipeline()
    print("Trips   :", result.etl.trips.stats)
    print("Rutas   :", result.etl.routes.output_file)
    print("GeoJSON :", result.geojson.output_path)
    print("Features:", result.geojson.stats.features_escritos)
    print("Kepler  :", result.kepler.output_path)
    print("Stats   :", result.kepler.stats)
