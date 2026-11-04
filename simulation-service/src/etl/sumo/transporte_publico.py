"""
Transporte público real (buses del SITP) a partir del GTFS de SIMUR.

La encuesta trae viajes en transporte público pero la red no tenía buses: esos viajes se
simulaban como caminatas. Con el GTFS se generan, una sola vez, las paradas y los buses
programados que pasan por Usaquén, y los viajes en transporte público pasan a ser
`<personTrip modes="public">`: la persona camina a una parada, espera, se sube al bus que
le sirva y camina hasta su destino (SUMO elige la combinación con el router intermodal).

1. `filtrar_gtfs` reduce el GTFS de toda Bogotá (~550 MB descomprimido) a los viajes de un
   día hábil que tienen al menos dos paradas dentro de la caja de Usaquén, sin TransMiCable.
   La troncal de TransMilenio (agencia 1) usa los carriles exclusivos de la Autopista Norte
   y su vType es bus_tm (articulado); los aforos de transporte público no la cuentan.
2. `generar_por_paradas` (por defecto) ubica cada parada en el carril con buses más cercano
   y deja que duarouter rutee cada viaje pasando por sus paradas. Escribe, versionados en
   scenarios/default/: pt_paradas.add.xml (paradas) y pt_vehiculos.rou.xml (un bus por
   viaje programado, con la hora de cada parada). `generar_transporte_publico` hace lo mismo
   con gtfs2pt.py de SUMO, que además ajusta el recorrido a la forma (shape) de la línea,
   pero su map matching en Python tarda horas con esta red (--gtfs2pt).

Uso: python -m etl.sumo.transporte_publico data/raw/gtfs/GTFS-2026-04-29.zip [--fecha AAAAMMDD]
GTFS: https://storage.googleapis.com/gtfs-estaticos/GTFS-2026-04-29.zip (SIMUR, vía Mobility Database).
"""
import argparse
import csv
import gzip
import io
import re
import math
import shutil
import sys
import zipfile
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from .configuration import DEFAULT_SCENARIO, ScenarioPaths
from .proceso import ejecutar
from .subred import SubredError, encontrar_herramienta
from .vtypes import AGENCIA_TRONCAL, BUS_SITP_ID, BUS_TM_ID, PARAMS_BUS_SITP, VTYPE_BUS_SITP, VTYPE_BUS_TM

# agency_id del GTFS de SIMUR: 1 Transmilenio-Troncal, 2 Alimentadores, 3 Zonal-Urbano,
# 4 Zonal-Complementario, 5 Zonal-Especial, 6 Transmilenio-Dual, 7 TransMiCable
AGENCIAS_SIMULADAS = ("1", "2", "3", "4", "5", "6")
# caja (oeste, sur, este, norte) de la red de Usaquén (origBoundary de usaquen_3d.net.xml)
BBOX_USAQUEN = (-74.058552, 4.663887, -73.996799, 4.851830)
DEPURAR = False
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
        # comprimido: sin comprimir pesa ~25 MB (SUMO y duarouter lo leen así)
        return self.destino_dir / "pt_vehiculos.rou.xml.gz"

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
    troncales: int = 0
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


def generar_por_paradas(
    cfg: TransportePublicoConfig, stats: TransportePublicoStats | None = None, radio_m: float = 40.0,
) -> TransportePublicoResult:
    """Buses y paradas sin el map matching de gtfs2pt (horas en Python con esta red).

    Cada parada del GTFS reducido va al carril más cercano (a menos de `radio_m`) que admite
    buses, como un <busStop> de 20 m. Cada viaje programado es un <trip> de bus_sitp con sus
    <stop busStop until=hora> en orden, y duarouter (C++) arma la ruta pasando por las paradas
    en segundos. Las paradas que no quedan sobre una vía con buses se omiten; un viaje con
    menos de dos paradas ubicadas se descarta.
    """
    import xml.etree.ElementTree as ET

    import sumolib

    stats = stats if stats is not None else TransportePublicoStats()
    filtrar_gtfs(cfg, stats)
    net = sumolib.net.readNet(str(cfg.net))
    with zipfile.ZipFile(cfg.gtfs_reducido) as zf:
        paradas_gtfs = {p["stop_id"]: p for p in _leer(zf, "stops.txt")}
        rutas = {r["route_id"]: r for r in _leer(zf, "routes.txt")}
        viajes = {v["trip_id"]: v for v in _leer(zf, "trips.txt")}
        horarios: dict[str, list[dict]] = {}
        for fila in _leer(zf, "stop_times.txt"):
            horarios.setdefault(fila["trip_id"], []).append(fila)

    # paradas -> carriles candidatos: el carril con buses más a la derecha de cada edge a
    # menos de `radio_m`. Una parada en una avenida de doble calzada queda cerca de las dos;
    # cada viaje usa la que va en su sentido (la que apunta hacia la parada siguiente).
    candidatas: dict[str, list[tuple]] = {}
    raiz_paradas = ET.Element("additional")
    for stop_id, parada in sorted(paradas_gtfs.items()):
        x, y = net.convertLonLat2XY(float(parada["stop_lon"]), float(parada["stop_lat"]))
        cercanos = sorted(
            ((e, d) for e, d in net.getNeighboringEdges(x, y, radio_m)
             if e.getFunction() != "internal" and e.allows("bus") and e.getLength() >= 5),
            key=lambda ed: ed[1],
        )[:4]
        for k, (edge, _dist) in enumerate(cercanos):
            carril = next(l for l in edge.getLanes() if l.allows("bus"))   # el de más a la derecha
            pos, _ = carril.getClosestLanePosAndDist((x, y))
            largo = carril.getLength()
            inicio = max(0.0, min(pos - 10, largo - 20))
            id_parada = f"pt_{stop_id}_{k}"
            ET.SubElement(raiz_paradas, "busStop", {
                "id": id_parada, "lane": carril.getID(), "startPos": f"{inicio:.1f}",
                "endPos": f"{min(largo, inicio + 20):.1f}", "name": parada.get("stop_name", stop_id),
                "friendlyPos": "true",
            })
            forma = edge.getShape()
            rumbo_edge = (forma[-1][0] - forma[0][0], forma[-1][1] - forma[0][1])
            solo_bus = not edge.allows("passenger")   # carril exclusivo (troncal)
            candidatas.setdefault(stop_id, []).append((id_parada, edge.getID(), inicio, rumbo_edge, (x, y), solo_bus))
    arbol = ET.ElementTree(raiz_paradas)
    ET.indent(arbol, space="  ")
    arbol.write(str(cfg.paradas), encoding="UTF-8", xml_declaration=True)
    stats.paradas = len(candidatas)

    def elegir(opciones: list[tuple], hacia: tuple[float, float], troncal: bool = False) -> tuple:
        """La candidata cuyo edge apunta más hacia `hacia` (dirección del viaje).

        La troncal para en las estaciones del separador: si la parada tiene un carril
        exclusivo cerca, solo compiten esos (las calzadas mixtas quedan a la misma distancia).
        """
        exclusivas = [o for o in opciones if o[5]]
        if troncal and exclusivas:
            opciones = exclusivas
        def alineacion(o):
            (dx, dy), norma = o[3], math.hypot(*o[3]) or 1.0
            return (dx * hacia[0] + dy * hacia[1]) / (norma * (math.hypot(*hacia) or 1.0))
        return max(opciones, key=alineacion)

    # viajes -> trips con paradas, ordenados por salida
    trips = []
    for trip_id, filas in horarios.items():
        ruta = rutas.get(viajes[trip_id]["route_id"], {})
        troncal = ruta.get("agency_id") == AGENCIA_TRONCAL
        filas = [f for f in sorted(filas, key=lambda f: int(f["stop_sequence"]))
                 if f["stop_id"] in candidatas and f["departure_time"]]
        paradas_viaje = []
        for i, f in enumerate(filas):
            opciones = candidatas[f["stop_id"]]
            xy = opciones[0][4]
            otra = candidatas[filas[i + 1]["stop_id"]][0][4] if i + 1 < len(filas) else None
            previa = candidatas[filas[i - 1]["stop_id"]][0][4] if i > 0 else None
            hacia = (otra[0] - xy[0], otra[1] - xy[1]) if otra else (xy[0] - previa[0], xy[1] - previa[1]) if previa else (0, 0)
            id_parada, edge, inicio, _rumbo, _xy, _solo = elegir(opciones, hacia, troncal)
            # dos paradas seguidas en el mismo edge hacia atrás obligarían a dar la vuelta
            if paradas_viaje and paradas_viaje[-1][1] == edge and inicio <= paradas_viaje[-1][2]:
                continue
            paradas_viaje.append((id_parada, edge, inicio, _segundos(f["departure_time"])))
        if len(paradas_viaje) < 2:
            continue
        salida = paradas_viaje[0][3] - 30
        if not cfg.inicio_s <= salida <= cfg.fin_s:
            continue
        linea = ruta.get("route_short_name", "")
        tipo = BUS_TM_ID if troncal else BUS_SITP_ID
        trips.append((salida, trip_id, linea, paradas_viaje, tipo))
    trips.sort()
    duarouter = shutil.which("duarouter")
    if duarouter is None:
        raise TransportePublicoError("No se encontró 'duarouter' en el PATH.")
    trabajo = cfg.destino_dir / ".pt_paradas"
    trabajo.mkdir(parents=True, exist_ok=True)
    pendientes = {f"{'tm' if tipo == BUS_TM_ID else 'bus'}_{linea}_{trip_id}".replace(" ", "_"):
                  (salida, linea or trip_id, paradas, tipo)
                  for salida, trip_id, linea, paradas, tipo in trips}
    rutados: list = []
    try:
        # la red tiene tramos sin conexión para buses entre algunas paradas: duarouter avisa qué
        # edge obligatorio no alcanzó y en la ronda siguiente el viaje va sin esa parada
        for ronda in range(4):
            if not pendientes:
                break
            log = trabajo / f"duarouter_{ronda}.log"
            salida_xml = trabajo / f"buses_{ronda}.rou.xml"
            _escribir_trips_bus(pendientes, trabajo / f"pt_{ronda}.trips.xml")
            resultado = ejecutar([
                duarouter, "-n", str(cfg.net), "--route-files", str(trabajo / f"pt_{ronda}.trips.xml"),
                "--additional-files", str(cfg.paradas), "-o", str(salida_xml),
                # sin --ptline-routing duarouter toma los vehículos con `line` como horario y no los rutea
                "--ignore-errors", "--routing-threads", "4", "--ptline-routing", "--log", str(log),
            ], cwd=trabajo)
            if resultado.returncode != 0 or not salida_xml.is_file():
                raise TransportePublicoError(
                    f"duarouter falló con los buses (código {resultado.returncode}): {resultado.stderr[-2000:]}"
                )
            for _, elem in ET.iterparse(salida_xml, events=("end",)):
                if elem.tag == "vehicle":
                    rutados.append(elem)
                    pendientes.pop(elem.get("id"), None)
            inalcanzables = {}
            for linea_log in log.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"Warning: Mandatory edge '([^']+)' not reachable by vehicle '([^']+)'", linea_log)
                if m:
                    inalcanzables[m.group(2)] = m.group(1)
            for vid in list(pendientes):
                edge = inalcanzables.get(vid)
                salida, linea, paradas, tipo = pendientes[vid]
                paradas = [pa for pa in paradas if pa[1] != edge] if edge else []
                if len(paradas) < 2:
                    del pendientes[vid]
                else:
                    pendientes[vid] = (paradas[0][3] - 30, linea, paradas, tipo)
    finally:
        if not DEPURAR:
            shutil.rmtree(trabajo, ignore_errors=True)
    rutados.sort(key=lambda v: float(v.get("depart", 0)))
    raiz = ET.Element("routes")
    _vtype_bus(raiz)
    for v in rutados:
        raiz.append(v)
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    with cfg.vehiculos.open("wb") as crudo, gzip.GzipFile(filename="", mode="wb", fileobj=crudo, mtime=0) as gz:
        arbol.write(gz, encoding="UTF-8", xml_declaration=True)
    stats.buses = len(rutados)
    stats.troncales = sum(v.get("type") == BUS_TM_ID for v in rutados)
    return TransportePublicoResult(cfg.paradas, cfg.vehiculos, cfg.vtypes)


def _vtype_bus(raiz) -> None:
    import xml.etree.ElementTree as ET

    for atributos in (VTYPE_BUS_SITP, VTYPE_BUS_TM):
        vtype = ET.SubElement(raiz, "vType", atributos)
        for clave, valor in PARAMS_BUS_SITP.items():
            ET.SubElement(vtype, "param", key=clave, value=valor)


def _escribir_trips_bus(pendientes: dict, destino: Path) -> None:
    import xml.etree.ElementTree as ET

    raiz = ET.Element("routes")
    _vtype_bus(raiz)
    for vid, (salida, linea, paradas, tipo) in sorted(pendientes.items(), key=lambda kv: kv[1][0]):
        trip = ET.SubElement(raiz, "trip", {
            "id": vid, "type": tipo, "depart": f"{salida:.0f}",
            "from": paradas[0][1], "to": paradas[-1][1], "line": linea,
        })
        for id_parada, _edge, _pos, hora in paradas:
            ET.SubElement(trip, "stop", {"busStop": id_parada, "duration": "10", "until": f"{hora:.0f}"})
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)


def usar_vtype_del_proyecto(vehiculos: Path) -> None:
    """gtfs2pt usa un vType "bus" genérico: los buses pasan al bus_sitp del proyecto (vtypes.py),
    que cuenta como "bus" en la validación y tiene su color en el visor."""
    import xml.etree.ElementTree as ET

    arbol = ET.parse(vehiculos)
    raiz = arbol.getroot()
    for vtype in raiz.findall("vType"):
        raiz.remove(vtype)
    vtype = ET.Element("vType", VTYPE_BUS_SITP)
    for clave, valor in PARAMS_BUS_SITP.items():
        ET.SubElement(vtype, "param", key=clave, value=valor)
    raiz.insert(0, vtype)
    for elem in raiz.iter():
        if elem.tag in ("vehicle", "flow") and elem.get("type") in (None, "bus"):
            elem.set("type", BUS_SITP_ID)
    arbol.write(str(vehiculos), encoding="UTF-8", xml_declaration=True)


def contar(path: Path, etiqueta: str) -> int:
    import xml.etree.ElementTree as ET

    if not path.is_file():
        return 0
    n = 0
    fuente = gzip.open(path) if path.suffix == ".gz" else path
    for _, elem in ET.iterparse(fuente, events=("end",)):
        if elem.tag == etiqueta:
            n += 1
        elem.clear()
    return n


def archivos_transporte_publico(paths: ScenarioPaths | None = None) -> TransportePublicoResult | None:
    """Paradas, buses y vTypes generados, o None si el escenario aún no tiene transporte público."""
    paths = paths or ScenarioPaths.from_name(DEFAULT_SCENARIO)
    resultado = TransportePublicoResult(
        paradas=paths.root / "pt_paradas.add.xml",
        vehiculos=paths.root / "pt_vehiculos.rou.xml.gz",
        vtypes=paths.root / "pt_vtypes.add.xml",
    )
    if not (resultado.paradas.is_file() and resultado.vehiculos.is_file()):
        return None
    return resultado


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("gtfs", type=Path, help="GTFS de SIMUR (.zip)")
    parser.add_argument("--fecha", default=FECHA_HABIL, help="día hábil a importar (AAAAMMDD)")
    parser.add_argument("--gtfs2pt", action="store_true",
                        help="usar gtfs2pt de SUMO (map matching de los recorridos; tarda horas con esta red)")
    args = parser.parse_args()
    stats = TransportePublicoStats()
    generar = generar_transporte_publico if args.gtfs2pt else generar_por_paradas
    try:
        resultado = generar(TransportePublicoConfig(gtfs=args.gtfs, fecha=args.fecha), stats)
    except (TransportePublicoError, SubredError) as exc:
        sys.exit(str(exc))
    print(f"{stats.viajes_en_zona} viajes de {len(stats.lineas)} líneas pasan por Usaquén; "
          f"{stats.buses} buses ({stats.troncales} de TransMilenio troncal) y {stats.paradas} paradas en la red -> {resultado.vehiculos.parent}")


if __name__ == "__main__":
    main()
