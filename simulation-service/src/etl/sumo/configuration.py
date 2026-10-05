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

# Ventana horaria de la simulación (segundos desde las 00:00)
HORA_INI = 7 * 3600
HORA_FIN = 10 * 3600

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
            sumo_log=output / "usaquen_am.sumo.log"
        )


def escribir_sumocfg_corrida(paths: ScenarioPaths) -> Path:
    """Copia la plantilla .sumocfg al directorio de la corrida apuntando a sus insumos.

    Red, TAZ y rutas quedan con ruta absoluta; las salidas (output/...) siguen
    relativas, así que SUMO las escribe junto al .sumocfg de la corrida.
    """
    tree = ET.parse(paths.sumocfg_template)
    valores = {
        "net-file": paths.net,
        "route-files": paths.routes,
        "additional-files": paths.taz,
    }
    for elem in tree.getroot().iter():
        if elem.tag in valores:
            elem.set("value", str(valores[elem.tag].resolve()))

    paths.sumocfg.parent.mkdir(parents=True, exist_ok=True)
    tree.write(paths.sumocfg, encoding="UTF-8", xml_declaration=True)
    return paths.sumocfg
