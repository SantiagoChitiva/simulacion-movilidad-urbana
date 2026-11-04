import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

SUMO_DIR = Path(__file__).parent
SCENARIOS_DIR = SUMO_DIR / "scenarios"
DEFAULT_SCENARIO = "default"

# Corridas lanzadas desde la API: simulation-service/runs/<run_id>/ (ignorado por git)
RUNS_DIR = SUMO_DIR.parents[2] / "runs"

# Datos derivados de la red que conviene no recalcular (ignorado por git)
CACHE_DIR = SUMO_DIR.parents[2] / "cache"

# Resultados de los presets ya simulados (versionados): simulation-service/precalculadas/<preset>/
PRECALCULADAS_DIR = SUMO_DIR.parents[2] / "precalculadas"

# Huellas de edificios (Microsoft Building Footprints) para la escena 3D (versionado en la raíz)
EDIFICIOS_GEOJSON = SUMO_DIR.parents[3] / "data" / "processed" / "edificios_ms.geojson"
# huellas de OpenStreetMap (python -m etl.sumo.evidencia edificios); se combinan con las de Microsoft
EDIFICIOS_OSM_GEOJSON = SUMO_DIR.parents[3] / "data" / "processed" / "edificios_osm.geojson"

# Evidencia para priorizar cruces (python -m etl.sumo.evidencia): siniestros SDM y POIs OSM
SINIESTROS_GEOJSON = SUMO_DIR.parents[3] / "data" / "processed" / "siniestros_usaquen.geojson"
POIS_GEOJSON = SUMO_DIR.parents[3] / "data" / "processed" / "pois_usaquen.geojson"
SEMAFOROS_SDM_GEOJSON = SUMO_DIR.parents[3] / "data" / "processed" / "semaforos_sdm_usaquen.geojson"

# Aforos de la hora de máxima demanda (EODI 2023) ubicados en la red (python -m etl.sumo.aforos)
AFOROS_JSON = SUMO_DIR.parents[3] / "data" / "processed" / "aforos_usaquen.json"

# output-prefix de la plantilla .sumocfg: SUMO lo antepone a todas las salidas
PREFIJO_SALIDAS = "usaquen_am."

# Ventanas horarias simulables (segundos desde las 00:00): la punta de la mañana y la de la
# tarde, que es la otra con aforos (16:00-19:00). HORA_INI/HORA_FIN son la de la mañana,
# la ventana por defecto.
VENTANAS: dict[str, tuple[int, int]] = {"am": (7 * 3600, 10 * 3600), "pm": (16 * 3600, 19 * 3600)}
HORA_INI, HORA_FIN = VENTANAS["am"]

# Tope de copias por viaje de la encuesta (factor de expansión)
MAX_COPIAS = 50

# Tope de viajes que se aceptan en una demanda parametrizada (la encuesta da ~24.600)
MAX_VIAJES = 100_000


@dataclass(frozen=True)
class ScenarioPaths:
    """Rutas de los archivos de un escenario.

    Los insumos (TSV, red, TAZ, plantilla .sumocfg) están en scenarios/<name>/. Los
    archivos generados van ahí mismo, o en runs/<run_id>/ si se trata de una corrida
    lanzada desde la API, para que varias corridas no se pisen.
    """
    root: Path
    tsv: Path
    net: Path
    taz: Path
    nombres_vias: Path   # id de vía OSM -> nombre (la red no trae nombres de calles)
    sumocfg_template: Path
    run_dir: Path        # donde se escriben los archivos generados
    trips: Path
    routes: Path
    sumocfg: Path
    fcd: Path       # salida de SUMO
    geojson: Path   # salida del conversor
    kepler_trips: Path   # trips (LineString) para la capa Trip de kepler.gl
    statistics: Path
    vehroute: Path       # rutas recorridas: base de los volúmenes por acceso
    sumo_log: Path
    conteos_add: Path    # edgeData en los puntos de aforo (additional de la corrida)
    conteos: Path        # vehículos que entran a cada edge aforado, cada 15 min
    validacion: Path     # GEH por punto de aforo (resumen y filas)
    validacion_csv: Path

    @classmethod
    def from_name(cls, name: str = DEFAULT_SCENARIO, run_id: str | None = None) -> "ScenarioPaths":
        root = SCENARIOS_DIR / name
        run_dir = RUNS_DIR / run_id if run_id else root
        output = run_dir / "output"
        return cls(
            root=root,
            tsv=root / "viajes_usaquen_internos.tsv",
            net=root / "usaquen_3d.net.xml",   # red con elevación: SUMO escribe z en el FCD
            taz=root / "usaquen.taz.xml",
            nombres_vias=root / "nombres_vias.json",
            sumocfg_template=root / "usaquen-sim.sumocfg",
            run_dir=run_dir,
            trips=run_dir / "usaquen_am_multimodal.trips.xml",
            routes=run_dir / "usaquen_am_multimodal.rou.xml",
            sumocfg=run_dir / "usaquen-sim.sumocfg",
            fcd=output / "usaquen_am.fcd.xml",   # con el prefijo del sumocfg
            geojson=output / "usaquen_am.fcd.geojson",
            kepler_trips=output / "usaquen_am.kepler.geojson",
            statistics=output / "usaquen_am.statistics.xml",
            vehroute=output / "usaquen_am.vehroute.xml",
            sumo_log=output / "usaquen_am.sumo.log",
            conteos_add=run_dir / "conteos.add.xml",
            conteos=output / "usaquen_am.conteos.xml",
            validacion=output / "validacion.json",
            validacion_csv=output / "validacion.csv",
        )


@dataclass(frozen=True)
class ArchivosPrecalculada:
    """Lo que se guarda de un preset ya simulado: solo lo que necesita el visor."""
    dir: Path
    trips_gz: Path      # GeoJSON de kepler comprimido; la API lo sirve sin descomprimir
    volumenes: Path     # volúmenes por edge (reemplaza al vehroute, que pesa ~22 MB)
    meta: Path          # parámetros, resumen y huella de los insumos
    validacion: Path    # GEH contra los aforos (validacion.py)

    @classmethod
    def from_preset(cls, preset: str) -> "ArchivosPrecalculada":
        d = PRECALCULADAS_DIR / preset
        return cls(dir=d, trips_gz=d / "trips.geojson.gz", volumenes=d / "volumenes.json", meta=d / "meta.json",
                   validacion=d / "validacion.json")


def escribir_sumocfg_corrida(
    paths: "ScenarioPaths",
    additional_files: list[Path] | None = None,
    route_files: list[Path] | None = None,
    ventana: tuple[int, int] | None = None,
    max_vehiculos: int | None = None,
    periodo_fcd: int | None = None,
) -> Path:
    """Copia la plantilla .sumocfg al directorio de la corrida apuntando a sus insumos.

    Red, TAZ y rutas quedan con ruta absoluta; las salidas (output/...) siguen
    relativas, así que SUMO las escribe junto al .sumocfg de la corrida.

    `additional_files` permite añadir archivos adicionales (vtypes de estilo, rerouters de
    cierre vial, paradas de bus) además del TAZ, y `route_files` demanda adicional (buses
    del GTFS, tráfico de paso); se concatenan separados por comas. `ventana` cambia el
    begin/end de la plantilla (la mañana) y `max_vehiculos` su tope de vehículos en la red.
    """
    tree = ET.parse(paths.sumocfg_template)
    extras: list[Path] = additional_files or []
    all_additionals = [paths.taz] + extras
    valores = {
        "net-file": str(paths.net.resolve()),
        "route-files": ",".join(str(p.resolve()) for p in [paths.routes, *(route_files or [])]),
        "additional-files": ",".join(str(p.resolve()) for p in all_additionals),
    }
    if ventana is not None:
        valores["begin"], valores["end"] = str(ventana[0]), str(ventana[1])
    if max_vehiculos is not None:
        valores["max-num-vehicles"] = str(max_vehiculos)
    if periodo_fcd is not None:
        valores["device.fcd.period"] = str(periodo_fcd)
    for elem in tree.getroot().iter():
        if elem.tag in valores:
            elem.set("value", valores[elem.tag])

    paths.sumocfg.parent.mkdir(parents=True, exist_ok=True)
    tree.write(paths.sumocfg, encoding="UTF-8", xml_declaration=True)
    return paths.sumocfg
