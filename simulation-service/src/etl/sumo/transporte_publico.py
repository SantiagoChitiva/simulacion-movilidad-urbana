"""
Transporte público real (buses del SITP) a partir del GTFS de SIMUR.

La encuesta trae viajes en transporte público pero la red no tenía buses: esos viajes se
simulaban como caminatas. Con el GTFS se generan, una sola vez, las paradas y los buses
programados que pasan por Usaquén, y los viajes en transporte público pasan a ser
`<personTrip modes="public">`: la persona camina a una parada, espera, se sube al bus que
le sirva y camina hasta su destino (SUMO elige la combinación con el router intermodal).

1. `filtrar_gtfs` reduce el GTFS de toda Bogotá (~550 MB descomprimido) a los viajes de un
   día hábil que tienen al menos dos paradas dentro de la caja de Usaquén, sin TransMilenio
   troncal ni TransMiCable (van por carriles exclusivos que la red no modela como tales y
   los aforos de transporte público tampoco los cuentan).
2. `generar_transporte_publico` corre gtfs2pt.py de SUMO sobre ese GTFS reducido: ubica las
   paradas en la red, rutea cada línea entre sus paradas y escribe, versionados en
   scenarios/default/: pt_paradas.add.xml (paradas y rutas de las líneas),
   pt_vehiculos.rou.xml (un bus por viaje programado) y pt_vtypes.add.xml.

Uso: python -m etl.sumo.transporte_publico data/raw/gtfs/GTFS-2026-04-29.zip [--fecha AAAAMMDD]
GTFS: https://storage.googleapis.com/gtfs-estaticos/GTFS-2026-04-29.zip (SIMUR, vía Mobility Database).
"""
import argparse
import csv
import io
import shutil
import sys
import zipfile
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from .configuration import DEFAULT_SCENARIO, ScenarioPaths
from .proceso import ejecutar
from .subred import SubredError, encontrar_herramienta
from .vtypes import BUS_PT_ID

# agency_id del GTFS de SIMUR: 1 Transmilenio-Troncal, 2 Alimentadores, 3 Zonal-Urbano,
# 4 Zonal-Complementario, 5 Zonal-Especial, 6 Transmilenio-Dual, 7 TransMiCable
AGENCIAS_SIMULADAS = ("2", "3", "4", "5", "6")
# caja (oeste, sur, este, norte) de la red de Usaquén (origBoundary de usaquen_3d.net.xml)
BBOX_USAQUEN = (-74.058552, 4.663887, -73.996799, 4.851830)
FECHA_HABIL = "20260506"   # miércoles sin festivo dentro de la vigencia del GTFS
# los buses que salen un poco antes de la ventana ya están en la red cuando empieza
INICIO_S = 6 * 3600
FIN_S = 20 * 3600
_DIAS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")


class TransportePublicoError(RuntimeError):
    """El GTFS no se pudo leer o gtfs2pt.py terminó con error."""


@dataclass(frozen=True)
class TransportePublicoConfig:
    gtfs: Path
    net: Path = ScenarioPaths.from_name(DEFAULT_SCENARIO).net
    destino_dir: Path = ScenarioPaths.from_name(DEFAULT_SCENARIO).root
    fecha: str = FECHA_HABIL
    bbox: tuple[float, float, float, float] = BBOX_USAQUEN
    agencias: tuple[str, ...] = AGENCIAS_SIMULADAS
    inicio_s: int = INICIO_S
    fin_s: int = FIN_S

    @property
    def gtfs_reducido(self) -> Path:
        return self.destino_dir / "gtfs_usaquen.zip"

    @property
    def paradas(self) -> Path:
        return self.destino_dir / "pt_paradas.add.xml"

    @property
    def vehiculos(self) -> Path:
        return self.destino_dir / "pt_vehiculos.rou.xml"

    @property
    def vtypes(self) -> Path:
        return self.destino_dir / "pt_vtypes.add.xml"

    def args_gtfs2pt(self, script: str) -> list[str]:
        w, s, e, n = self.bbox
        return [
            sys.executable, script,
            "--gtfs", str(self.gtfs_reducido),
            "--date", self.fecha,
            "-n", str(self.net),
            "--modes", "bus",
            f"--bbox={w},{s},{e},{n}",   # con "=": la caja empieza con "-74" y argparse la toma por una opción
            "--begin", str(self.inicio_s),
            "--end", str(self.fin_s),
            "--route-output", str(self.vehiculos),
            "--additional-output", str(self.paradas),
            "--vtype-output", str(self.vtypes),
            "--repair",
            "--sort",
        ]


@dataclass(frozen=True)
class TransportePublicoResult:
    paradas: Path
    vehiculos: Path
    vtypes: Path


@dataclass
class TransportePublicoStats:
    viajes_gtfs: int = 0
    viajes_en_zona: int = 0
    paradas_en_zona: int = 0
    lineas: set[str] = field(default_factory=set)
    buses: int = 0
    paradas: int = 0


def _leer(zf: zipfile.ZipFile, nombre: str):
    with zf.open(nombre) as crudo:
        yield from csv.DictReader(io.TextIOWrapper(crudo, encoding="utf-8-sig"))


def _segundos(hhmmss: str) -> int:
    h, m, s = (int(x) for x in hhmmss.split(":"))
    return h * 3600 + m * 60 + s


def servicios_activos(zf: zipfile.ZipFile, fecha: str) -> set[str]:
    """service_id que operan en `fecha` según calendar.txt y calendar_dates.txt."""
    dia = _DIAS[date(int(fecha[:4]), int(fecha[4:6]), int(fecha[6:])).weekday()]
    activos = {
        c["service_id"] for c in _leer(zf, "calendar.txt")
        if c[dia] == "1" and c["start_date"] <= fecha <= c["end_date"]
    }
    if "calendar_dates.txt" in zf.namelist():
        for c in _leer(zf, "calendar_dates.txt"):
            if c["date"] == fecha:
                (activos.add if c["exception_type"] == "1" else activos.discard)(c["service_id"])
    return activos


def _escribir_csv(destino: zipfile.ZipFile, nombre: str, filas: list[dict], campos: list[str]) -> None:
    salida = io.StringIO()
    escritor = csv.DictWriter(salida, fieldnames=campos, lineterminator="\n")
    escritor.writeheader()
    escritor.writerows(filas)
    destino.writestr(nombre, salida.getvalue())


def filtrar_gtfs(cfg: TransportePublicoConfig, stats: TransportePublicoStats | None = None) -> Path:
    """GTFS reducido a los viajes del día que pasan por la caja de Usaquén (≥ 2 paradas)."""
    stats = stats if stats is not None else TransportePublicoStats()
    if not cfg.gtfs.is_file():
        raise TransportePublicoError(f"No está el GTFS: {cfg.gtfs}")
    w, s, e, n = cfg.bbox
    with zipfile.ZipFile(cfg.gtfs) as zf:
        activos = servicios_activos(zf, cfg.fecha)
        rutas = {r["route_id"]: r for r in _leer(zf, "routes.txt") if r["agency_id"] in cfg.agencias}
        viajes = {}
        for v in _leer(zf, "trips.txt"):
            stats.viajes_gtfs += 1
            if v["route_id"] in rutas and v["service_id"] in activos:
                viajes[v["trip_id"]] = v
        paradas = {
            p["stop_id"]: p for p in _leer(zf, "stops.txt")
            if w <= float(p["stop_lon"]) <= e and s <= float(p["stop_lat"]) <= n
        }
        # stop_times pesa ~500 MB: se lee una vez en streaming y solo se guardan las filas
        # dentro de la caja de los viajes que interesan
        por_viaje: dict[str, list[dict]] = {}
        with zf.open("stop_times.txt") as crudo:
            lector = csv.DictReader(io.TextIOWrapper(crudo, encoding="utf-8-sig"))
            campos_horarios = lector.fieldnames
            for fila in lector:
                if fila["trip_id"] in viajes and fila["stop_id"] in paradas:
                    por_viaje.setdefault(fila["trip_id"], []).append(fila)
        horarios = []
        for trip_id, filas in por_viaje.items():
            salidas = [_segundos(f["departure_time"]) for f in filas if f["departure_time"]]
            if len(filas) < 2 or not salidas or max(salidas) < cfg.inicio_s or min(salidas) > cfg.fin_s:
                del viajes[trip_id]
                continue
            horarios.extend(sorted(filas, key=lambda f: int(f["stop_sequence"])))
        viajes = {t: v for t, v in viajes.items() if t in por_viaje}
        usadas = {f["stop_id"] for f in horarios}
        formas = {v["shape_id"] for v in viajes.values() if v.get("shape_id")}
        rutas_usadas = {v["route_id"] for v in viajes.values()}
        stats.viajes_en_zona = len(viajes)
        stats.paradas_en_zona = len(usadas)
        stats.lineas = {rutas[r]["route_short_name"] for r in rutas_usadas}

        cfg.gtfs_reducido.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(cfg.gtfs_reducido, "w", zipfile.ZIP_DEFLATED) as destino:
            for nombre in ("agency.txt", "calendar.txt", "calendar_dates.txt", "feed_info.txt"):
                if nombre in zf.namelist():
                    destino.writestr(nombre, zf.read(nombre))
            _escribir_csv(destino, "routes.txt", [rutas[r] for r in sorted(rutas_usadas)], list(next(iter(rutas.values())).keys()))
            _escribir_csv(destino, "trips.txt", list(viajes.values()), list(next(iter(viajes.values())).keys()))
            _escribir_csv(destino, "stops.txt", [paradas[p] for p in sorted(usadas)], list(next(iter(paradas.values())).keys()))
            _escribir_csv(destino, "stop_times.txt", horarios, campos_horarios)
            filas_formas = [f for f in _leer(zf, "shapes.txt") if f["shape_id"] in formas]
            if filas_formas:
                _escribir_csv(destino, "shapes.txt", filas_formas, list(filas_formas[0].keys()))
    return cfg.gtfs_reducido


def generar_transporte_publico(
    cfg: TransportePublicoConfig, stats: TransportePublicoStats | None = None,
) -> TransportePublicoResult:
    stats = stats if stats is not None else TransportePublicoStats()
    filtrar_gtfs(cfg, stats)
    script = encontrar_herramienta("gtfs2pt.py")
    # gtfs2pt deja trazas intermedias (fcd/, gpsdat/, rutas de duarouter) en su directorio
    trabajo = cfg.destino_dir / ".gtfs2pt"
    trabajo.mkdir(parents=True, exist_ok=True)
    try:
        salida = ejecutar(cfg.args_gtfs2pt(script), cwd=trabajo)
    finally:
        shutil.rmtree(trabajo, ignore_errors=True)
    if salida.returncode != 0 or not cfg.vehiculos.is_file():
        raise TransportePublicoError(f"gtfs2pt.py falló (código {salida.returncode}):\n{salida.stderr[-2000:]}")
    usar_vtype_del_proyecto(cfg.vehiculos)
    stats.buses = contar(cfg.vehiculos, "vehicle")
    stats.paradas = contar(cfg.paradas, "busStop")
    return TransportePublicoResult(cfg.paradas, cfg.vehiculos, cfg.vtypes)


def usar_vtype_del_proyecto(vehiculos: Path) -> None:
    """gtfs2pt usa un vType "bus" genérico: los buses pasan al bus_pt del proyecto (vtypes.py),
    que ya está en todas las demandas, cuenta como "bus" en la validación y tiene su color en
    el visor."""
    import xml.etree.ElementTree as ET

    arbol = ET.parse(vehiculos)
    raiz = arbol.getroot()
    for vtype in raiz.findall("vType"):
        raiz.remove(vtype)
    for elem in raiz.iter():
        if elem.tag in ("vehicle", "flow") and elem.get("type") in (None, "bus"):
            elem.set("type", BUS_PT_ID)
    arbol.write(str(vehiculos), encoding="UTF-8", xml_declaration=True)


def contar(path: Path, etiqueta: str) -> int:
    import xml.etree.ElementTree as ET

    if not path.is_file():
        return 0
    n = 0
    for _, elem in ET.iterparse(path, events=("end",)):
        if elem.tag == etiqueta:
            n += 1
        elem.clear()
    return n


def archivos_transporte_publico(paths: ScenarioPaths | None = None) -> TransportePublicoResult | None:
    """Paradas, buses y vTypes generados, o None si el escenario aún no tiene transporte público."""
    paths = paths or ScenarioPaths.from_name(DEFAULT_SCENARIO)
    resultado = TransportePublicoResult(
        paradas=paths.root / "pt_paradas.add.xml",
        vehiculos=paths.root / "pt_vehiculos.rou.xml",
        vtypes=paths.root / "pt_vtypes.add.xml",
    )
    if not (resultado.paradas.is_file() and resultado.vehiculos.is_file()):
        return None
    return resultado


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("gtfs", type=Path, help="GTFS de SIMUR (.zip)")
    parser.add_argument("--fecha", default=FECHA_HABIL, help="día hábil a importar (AAAAMMDD)")
    args = parser.parse_args()
    stats = TransportePublicoStats()
    try:
        resultado = generar_transporte_publico(TransportePublicoConfig(gtfs=args.gtfs, fecha=args.fecha), stats)
    except (TransportePublicoError, SubredError) as exc:
        sys.exit(str(exc))
    print(f"{stats.viajes_en_zona} viajes de {len(stats.lineas)} líneas pasan por Usaquén; "
          f"{stats.buses} buses y {stats.paradas} paradas en la red -> {resultado.vehiculos.parent}")


if __name__ == "__main__":
    main()
