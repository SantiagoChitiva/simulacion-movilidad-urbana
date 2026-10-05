from dataclasses import dataclass
from pathlib import Path

SUMO_DIR = Path(__file__).parent
SCENARIOS_DIR = SUMO_DIR / "scenarios"
DEFAULT_SCENARIO = "default"

# Ventana horaria de la simulación (segundos desde las 00:00)
HORA_INI = 7 * 3600
HORA_FIN = 10 * 3600

# Tope de copias por viaje de la encuesta (factor de expansión)
MAX_COPIAS = 50


@dataclass(frozen=True)
class ScenarioPaths:
    """Rutas de los archivos de un escenario."""
    root: Path
    tsv: Path
    net: Path
    taz: Path
    trips: Path
    routes: Path
    sumocfg: Path
    fcd: Path       # salida de SUMO
    geojson: Path   # salida del conversor
    kepler_trips: Path   # trips (LineString) para la capa Trip de kepler.gl
    sumo_log: Path

    @classmethod
    def from_name(cls, name: str = DEFAULT_SCENARIO) -> "ScenarioPaths":
        root = SCENARIOS_DIR / name
        output = root / "output"
        return cls(
            root=root,
            tsv=root / "viajes_usaquen_internos.tsv",
            net=root / "usaquen_3d.net.xml",   # red con elevación: SUMO escribe z en el FCD
            taz=root / "usaquen.taz.xml",
            trips=root / "usaquen_am_multimodal.trips.xml",
            routes=root / "usaquen_am_multimodal.rou.xml",
            sumocfg=root / "usaquen-sim.sumocfg",
            fcd=output / "usaquen_am.fcd.xml",   # con el prefijo del sumocfg
            geojson=output / "usaquen_am.fcd.geojson",
            kepler_trips=output / "usaquen_am.kepler.geojson",
            sumo_log=output / "usaquen_am.sumo.log"
        )
