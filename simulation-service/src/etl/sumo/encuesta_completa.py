"""
Complemento de la encuesta: los viajes en vehículo que la demanda interna deja por fuera.

La demanda de las corridas (`viajes_usaquen_internos.tsv`) tiene solo los viajes con
origen y destino en Usaquén, y cada fila se replica a lo sumo MAX_COPIAS (50) veces aunque
su factor de expansión sea mayor (la mediana en la mañana es 123). Medido en la Encuesta
de Movilidad 2023, ventana de la mañana: los viajes internos en auto son 21.800, pero los que
entran o salen de Usaquén son 61.500 más. Con eso fuera, la corrida lleva ~6 % del
volumen aforado.

Este módulo arma, con el módulo de viajes procesado de la encuesta (carpeta EODH de SIMUR):
1. los viajes en vehículo con un extremo en Usaquén y el otro fuera. El extremo externo se
   lleva a una "puerta": la vía arterial (troncal, primaria, secundaria o terciaria) que
   cruza el borde de la red cerca del centroide de la ZAT externa: se reparte entre las
   PUERTAS_POR_ZAT más cercanas, con peso carriles / distancia² (con una sola puerta, unas
   pocas recibían miles de vehículos por hora y la mayoría no alcanzaba a entrar). La salida en la
   puerta es la hora de la encuesta más la parte del viaje recorrida fuera de la red
   (proporcional a la distancia);
2. las copias que el tope MAX_COPIAS les quita a los viajes internos en vehículo.
Las copias de una fila se reparten en ±15 min alrededor de su hora (la encuesta redondea la
hora a la media hora y cientos de vehículos en el mismo segundo bloquean la inserción).

No incluye a los peatones ni a los pasajeros del transporte público que entran o salen (no
suman vehículos en los aforos) ni el tráfico que atraviesa Usaquén sin parar, que la
encuesta no puede ubicar en la red (para eso está trafico_paso.py).

Salida versionada: scenarios/default/complemento_encuesta_<am|pm>.rou.xml.gz, ya ruteada.
Sus vehículos usan vTypes propios, `<modo>_enc` (SUFIJO_VTYPE), iguales a los de la demanda
principal: duarouter escribe cada vType justo antes de su primer vehículo y SUMO lee los
archivos de rutas por tramos de tiempo, así que un vType de la demanda principal (p. ej.
`otro`) puede no existir aún cuando llega un vehículo del complemento; y definirlo con el
mismo id en los dos archivos es un error. Conteos y kepler los agrupan con su modo.

Uso: python -m etl.sumo.encuesta_completa "<carpeta 2.PublicacionSIMUR>"   (necesita .[datos])
"""
import argparse
import csv
import gzip
import json
import math
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import DEFAULT_SCENARIO, MAX_COPIAS, VENTANAS, ScenarioPaths
from .demanda import mayor_resto
from .duarouter import DuarouterConfig, run_duarouter
from .enums.survey_mode import SurveyMode
from .trips import TripGenerationConfig, TripGenerationStats, _add_vtypes, read_trips
from .vtypes import VTYPES

RUTA_VIAJES = Path("EODH") / "05_Base datos procesada" / "CSV" / "d. Modulo viajes.csv"
RUTA_ZAT = Path("EODH") / "03_Zonificacion" / "b. Shapefile ZAT.zip"
TIPOS_PUERTA = {"highway.trunk", "highway.primary", "highway.secondary", "highway.tertiary"}
SUFIJO_VTYPE = "_enc"            # vTypes propios del complemento (ver arriba)
LOCALIDAD = "usaqu"                # localidad_ori/des normalizada empieza así
DISPERSION_S = 15 * 60             # las copias de una fila se reparten en ±15 min
PUERTAS_POR_ZAT = 4                # el extremo externo se reparte entre las 4 puertas más cercanas


class EncuestaCompletaError(RuntimeError):
    """Falta un insumo de la encuesta o duarouter no pudo rutear el complemento."""


@dataclass(frozen=True)
class EncuestaCompletaConfig:
    carpeta_simur: Path
    escenario: str = DEFAULT_SCENARIO

    @property
    def viajes(self) -> Path:
        return self.carpeta_simur / RUTA_VIAJES

    @property
    def zat(self) -> Path:
        return self.carpeta_simur / RUTA_ZAT


@dataclass
class EncuestaCompletaStats:
    filas_externas: int = 0
    sin_zat: int = 0
    por_tipo: Counter = field(default_factory=Counter)     # entran / salen / tope
    por_modo: Counter = field(default_factory=Counter)
    vehiculos_por_ventana: dict[str, int] = field(default_factory=dict)


@dataclass(frozen=True)
class Puerta:
    edge: str
    sentido: str       # "entra" o "sale"
    x: float
    y: float
    carriles: int


# ------------------------------------------------------------------ red

def puertas(net) -> list[Puerta]:
    """Vías arteriales que cruzan el borde de la red, en los dos sentidos."""
    salida = []
    for e in net.getEdges():
        if e.getType() not in TIPOS_PUERTA or not e.allows("passenger"):
            continue
        origen, destino = e.getFromNode(), e.getToNode()
        # entra: al nodo de origen no llega nada salvo su contrario; sale: al revés
        if all(i.getFromNode() == destino for i in origen.getIncoming()):
            x, y = origen.getCoord()[:2]
            salida.append(Puerta(e.getID(), "entra", x, y, e.getLaneNumber()))
        if all(o.getToNode() == origen for o in destino.getOutgoing()):
            x, y = destino.getCoord()[:2]
            salida.append(Puerta(e.getID(), "sale", x, y, e.getLaneNumber()))
    return salida


def reparto_puertas(x: float, y: float, candidatas: list[Puerta]) -> list[tuple[Puerta, float]]:
    """Las PUERTAS_POR_ZAT puertas más cercanas a (x, y), con peso carriles / distancia²."""
    cercanas = sorted(((math.hypot(p.x - x, p.y - y), p) for p in candidatas), key=lambda dp: dp[0])
    pesos = [(p, p.carriles / max(d, 100.0) ** 2) for d, p in cercanas[:PUERTAS_POR_ZAT]]
    total = sum(w for _, w in pesos)
    return [(p, w / total) for p, w in pesos]


# ------------------------------------------------------------- encuesta

def _numero(texto: str | None) -> float | None:
    try:
        return float(str(texto).strip().replace(",", "."))
    except (TypeError, ValueError):
        return None


def _es_usaquen(localidad: str | None) -> bool:
    return str(localidad or "").strip().lower().startswith(LOCALIDAD)


def leer_externos(csv_path: Path) -> list[dict]:
    """Viajes en vehículo de la encuesta con exactamente un extremo en Usaquén."""
    filas = []
    with open(csv_path, encoding="latin-1", newline="") as f:
        lector = csv.DictReader(f, delimiter=";")
        lector.fieldnames = [c.strip() for c in lector.fieldnames]
        for fila in lector:
            ori, des = _es_usaquen(fila["localidad_ori"]), _es_usaquen(fila["localidad_des"])
            if ori == des:
                continue
            # el CSV viene en latin-1 pero SurveyMode espera las etiquetas con tilde
            modo = SurveyMode.parse(fila["modo_principal_agrupado"].strip())
            hora, fexp = _numero(fila["hora_ini"]), _numero(fila["fexp_vj"])
            if modo is None or not modo.transport_mode.is_vehicle or hora is None or not fexp:
                continue
            filas.append({
                "modo": modo.transport_mode.value, "sale_de_usaquen": ori,
                "zat_ori": str(fila["zat_ori"]).strip(), "zat_des": str(fila["zat_des"]).strip(),
                "hora_s": round(hora * 60) * 60, "duracion_s": (_numero(fila["duracion_min"]) or 0) * 60,
                "copias": max(1, round(fexp)),
            })
    return filas


def centroides_zat(zip_zat: Path, net) -> dict[str, tuple[float, float]]:
    """ZAT -> centroide en coordenadas de la red."""
    import geopandas as gpd   # extra .[datos]

    with tempfile.TemporaryDirectory() as tmp:
        # GDAL no abre /vsizip/ con tildes en la ruta (p. ej. "PLANEACIÓN"): se extrae
        with zipfile.ZipFile(zip_zat) as z:
            z.extractall(tmp)
        shp = next(Path(tmp).rglob("*.shp"))
        zonas = gpd.read_file(shp).to_crs(4326)
        zonas = zonas[zonas["ZAT"].notna()]
        puntos = zonas.geometry.representative_point()
        return {
            str(int(z)): net.convertLonLat2XY(p.x, p.y)
            for z, p in zip(zonas["ZAT"], puntos)
        }


def _dispersar(t: float, copias: int) -> list[float]:
    """`copias` salidas repartidas de forma pareja en t ± DISPERSION_S."""
    if copias == 1:
        return [t]
    return [t - DISPERSION_S + 2 * DISPERSION_S * (i + 0.5) / copias for i in range(copias)]


def viajes_complemento(externos: list[dict], internos, centroides: dict, lista_puertas: list[Puerta],
                       tazs: set[str], stats: EncuestaCompletaStats) -> list[dict]:
    """Lista de viajes {id, tipo, depart, fromTaz, toTaz} del complemento, sin ordenar."""
    entran = [p for p in lista_puertas if p.sentido == "entra"]
    salen = [p for p in lista_puertas if p.sentido == "sale"]
    viajes = []
    for fila in externos:
        interna = fila["zat_ori"] if fila["sale_de_usaquen"] else fila["zat_des"]
        externa = fila["zat_des"] if fila["sale_de_usaquen"] else fila["zat_ori"]
        if interna not in tazs or externa not in centroides or interna not in centroides:
            stats.sin_zat += 1
            continue
        stats.filas_externas += 1
        ex, ey = centroides[externa]
        reparto = reparto_puertas(ex, ey, salen if fila["sale_de_usaquen"] else entran)
        copias = mayor_resto([w for _, w in reparto], fila["copias"])
        ix, iy = centroides[interna]
        for (puerta, _), n in zip(reparto, copias):
            if n == 0:
                continue
            t = fila["hora_s"]
            if not fila["sale_de_usaquen"]:
                # entra a la red después de recorrer el tramo de fuera
                fuera = math.hypot(puerta.x - ex, puerta.y - ey)
                dentro = math.hypot(puerta.x - ix, puerta.y - iy)
                t += fila["duracion_s"] * fuera / max(fuera + dentro, 1.0)
            taz_puerta = f"puerta_{puerta.sentido}_{puerta.edge}"
            tipo = "sale" if fila["sale_de_usaquen"] else "entra"
            for salida in _dispersar(t, n):
                viajes.append({"tipo": fila["modo"], "depart": salida,
                               "fromTaz": interna if fila["sale_de_usaquen"] else taz_puerta,
                               "toTaz": taz_puerta if fila["sale_de_usaquen"] else interna})
                stats.por_tipo[tipo] += 1
                stats.por_modo[fila["modo"]] += 1
    # copias que el tope les quita a los viajes internos en vehículo
    for t in internos:
        faltan = max(1, round(t.fexp)) - min(max(1, round(t.fexp)), MAX_COPIAS)
        if faltan <= 0 or not t.mode.is_vehicle:
            continue
        for salida in _dispersar(t.depart, faltan):
            viajes.append({"tipo": t.mode.value, "depart": salida,
                           "fromTaz": t.origin_taz, "toTaz": t.destination_taz})
            stats.por_tipo["tope"] += 1
            stats.por_modo[t.mode.value] += 1
    return viajes


# ------------------------------------------------------------ escritura

def escribir_puertas(lista: list[Puerta], destino: Path) -> Path:
    raiz = ET.Element("additional")
    for p in lista:
        ET.SubElement(raiz, "taz", id=f"puerta_{p.sentido}_{p.edge}", edges=p.edge)
    ET.ElementTree(raiz).write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


def escribir_viajes(viajes: list[dict], destino: Path, prefijo: str) -> Path:
    raiz = ET.Element("routes")
    _add_vtypes(raiz)   # duarouter necesita los vTypes para rutear (luego se quitan)
    for i, v in enumerate(sorted(viajes, key=lambda v: v["depart"])):
        ET.SubElement(raiz, "trip", id=f"{prefijo}{v['tipo']}_{i}", type=v["tipo"],
                      depart=f"{v['depart']:.2f}", fromTaz=v["fromTaz"], toTaz=v["toTaz"],
                      departLane="best", departSpeed="max")
    ET.ElementTree(raiz).write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


def comprimir_vehiculos(rutas: Path, destino: Path) -> int:
    """Los <vehicle> con vTypes `<modo>_enc` definidos al principio, en gzip reproducible."""
    raiz = ET.Element("routes")
    for vtype in VTYPES.values():
        atributos = vtype.to_xml_attrs()
        ET.SubElement(raiz, "vType", {**atributos, "id": atributos["id"] + SUFIJO_VTYPE})
    n = 0
    for _, elem in ET.iterparse(rutas, events=("end",)):
        if elem.tag == "vehicle":
            elem.set("type", elem.get("type") + SUFIJO_VTYPE)
            raiz.append(elem)
            n += 1
    with destino.open("wb") as crudo, gzip.GzipFile(filename="", mode="wb", fileobj=crudo, mtime=0) as gz:
        ET.ElementTree(raiz).write(gz, encoding="UTF-8", xml_declaration=True)
    return n


def archivo_complemento(ventana: str = "am", escenario: str = DEFAULT_SCENARIO) -> Path | None:
    """Complemento ya ruteado de la ventana, o None si no se ha generado."""
    path = ScenarioPaths.from_name(escenario).root / f"complemento_encuesta_{ventana}.rou.xml.gz"
    return path if path.is_file() else None


def generar_complemento(cfg: EncuestaCompletaConfig, stats: EncuestaCompletaStats | None = None) -> list[Path]:
    import sumolib

    stats = stats if stats is not None else EncuestaCompletaStats()
    for insumo in (cfg.viajes, cfg.zat):
        if not insumo.is_file():
            raise EncuestaCompletaError(f"No existe {insumo}")
    escenario = ScenarioPaths.from_name(cfg.escenario)
    net = sumolib.net.readNet(str(escenario.net))
    lista = puertas(net)
    tazs = {t.get("id") for t in ET.parse(escenario.taz).getroot().iter("taz")}
    centroides = centroides_zat(cfg.zat, net)
    externos = leer_externos(cfg.viajes)
    trabajo = escenario.root / ".complemento_encuesta"
    trabajo.mkdir(exist_ok=True)
    taz_puertas = escribir_puertas(lista, trabajo / "puertas.taz.xml")
    salidas = []
    for ventana, (ini, fin) in VENTANAS.items():
        st = TripGenerationStats()
        internos = list(read_trips(TripGenerationConfig(escenario.tsv, Path(), hora_ini=ini, hora_fin=fin), st))
        # media hora antes: los que salen a las 6:45 siguen en la red a las 7:00
        externos_ventana = [f for f in externos if ini - 1800 <= f["hora_s"] < fin]
        viajes = viajes_complemento(externos_ventana, internos, centroides, lista, tazs, stats)
        viajes = [v for v in viajes if ini - 1800 <= v["depart"] < fin]
        trips = escribir_viajes(viajes, trabajo / f"complemento_{ventana}.trips.xml", f"enc_{ventana}_")
        rutas = trabajo / f"complemento_{ventana}.rou.xml"
        run_duarouter(DuarouterConfig(escenario.net, trips, escenario.taz, rutas,
                                      ventana=(ini - 1800, fin), adicionales_extra=(taz_puertas,)))
        destino = escenario.root / f"complemento_encuesta_{ventana}.rou.xml.gz"
        stats.vehiculos_por_ventana[ventana] = comprimir_vehiculos(rutas, destino)
        salidas.append(destino)
    (trabajo / "resumen.json").write_text(json.dumps({
        "puertas": len(lista), **{k: (dict(v) if isinstance(v, Counter) else v) for k, v in stats.__dict__.items()},
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    return salidas


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("carpeta_simur", type=Path, help="carpeta 2.PublicacionSIMUR (con EODH/)")
    args = parser.parse_args()
    stats = EncuestaCompletaStats()
    salidas = generar_complemento(EncuestaCompletaConfig(args.carpeta_simur), stats)
    print(f"{stats.filas_externas} filas externas ({stats.sin_zat} sin ZAT); viajes {dict(stats.por_tipo)}")
    print(f"por modo {dict(stats.por_modo)}; vehículos ruteados {stats.vehiculos_por_ventana}")
    for s in salidas:
        print("->", s)


if __name__ == "__main__":
    main()
