"""
Evidencia externa para priorizar cruces sin semáforo.

Se descarga una sola vez y se versiona en data/processed/ (son archivos pequeños):

- siniestros_usaquen.geojson: siniestros viales georreferenciados de la Secretaría
  Distrital de Movilidad (Histórico de siniestros Bogotá D.C., servicio ArcGIS publicado
  en datosabiertos.bogota.gov.co), filtrados a la localidad de Usaquén.
- pois_usaquen.geojson: generadores de viajes peatonales sensibles (colegios, jardines,
  universidades, hospitales y clínicas) de OpenStreetMap vía Overpass.
- edificios_osm.geojson: huellas de edificios de OpenStreetMap (con altura o pisos si los
  tienen) para la escena 3D; complementan las de Microsoft, que en Usaquén son incompletas.

Uso: python -m etl.sumo.evidencia [siniestros|pois|edificios ...]

Si un archivo no existe, la priorización simplemente no usa esa evidencia.
"""
import argparse
import json
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

from .configuration import EDIFICIOS_OSM_GEOJSON, POIS_GEOJSON, SINIESTROS_GEOJSON

URL_SINIESTROS = (
    "https://services2.arcgis.com/NEwhEo9GGSHXcRXV/arcgis/rest/services/HistoricoSiniestros/FeatureServer/0/query"
)
URL_OVERPASS = "https://overpass-api.de/api/interpreter"
# espejos de Overpass por si el principal está saturado
URLS_OVERPASS = (URL_OVERPASS, "https://maps.mail.ru/osm/tools/overpass/api/interpreter")
# bbox (s, w, n, e) de la red de Usaquén (origBoundary de usaquen_3d.net.xml)
BBOX_USAQUEN = (4.663887, -74.058552, 4.851830, -73.996799)
AMENIDADES = ("school", "kindergarten", "college", "university", "hospital", "clinic")
CAMPOS_SINIESTRO = ("FORMULARIO", "ANO_OCURRENCIA_ACC", "GRAVEDAD", "CLASE_ACC", "DIRECCION")
_AGENTE = "simulacion-movilidad-urbana/1.0 (tesis PUJ)"


class EvidenciaError(RuntimeError):
    """No se pudo descargar una fuente de evidencia."""


@dataclass(frozen=True)
class EvidenciaConfig:
    siniestros: Path = SINIESTROS_GEOJSON
    pois: Path = POIS_GEOJSON
    edificios: Path = EDIFICIOS_OSM_GEOJSON
    localidad: str = "USAQUEN"
    pagina: int = 2000          # maxRecordCount del servicio
    timeout_s: int = 120


@dataclass
class EvidenciaStats:
    siniestros: int = 0
    pois: int = 0
    edificios: int = 0
    paginas: int = 0
    pois_por_tipo: dict[str, int] = field(default_factory=dict)


def _leer_json(url: str, datos: bytes | None, timeout: int, intentos: int = 3) -> dict:
    ultimo: Exception | None = None
    for intento in range(intentos):
        try:
            req = urllib.request.Request(url, data=datos, headers={"User-Agent": _AGENTE})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (OSError, ValueError) as exc:
            ultimo = exc
            time.sleep(2 * (intento + 1))
    raise EvidenciaError(f"No se pudo descargar {url}: {ultimo}")


def _escribir(path: Path, features: list[dict], fuente: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    datos = {"type": "FeatureCollection", "fuente": fuente, "features": features}
    path.write_text(json.dumps(datos, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def descargar_siniestros(cfg: EvidenciaConfig = EvidenciaConfig(), stats: EvidenciaStats | None = None) -> Path:
    """Siniestros de la localidad, paginados de a `cfg.pagina`."""
    stats = stats if stats is not None else EvidenciaStats()
    features, offset = [], 0
    while True:
        params = {
            "where": f"LOCALIDAD='{cfg.localidad}'",
            "outFields": ",".join(CAMPOS_SINIESTRO),
            "outSR": "4326",
            "orderByFields": "OBJECTID",
            "resultOffset": str(offset),
            "resultRecordCount": str(cfg.pagina),
            "f": "geojson",
        }
        datos = _leer_json(f"{URL_SINIESTROS}?{urllib.parse.urlencode(params)}", None, cfg.timeout_s)
        if "error" in datos:
            raise EvidenciaError(f"El servicio de siniestros respondió con error: {datos['error']}")
        pagina = datos.get("features", [])
        stats.paginas += 1
        for f in pagina:
            geom = f.get("geometry") or {}
            if geom.get("type") != "Point":
                continue
            lon, lat = geom["coordinates"][:2]
            props = f.get("properties") or {}
            features.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]},
                "properties": {
                    "anio": props.get("ANO_OCURRENCIA_ACC"),
                    "gravedad": props.get("GRAVEDAD"),
                    "clase": props.get("CLASE_ACC"),
                    "direccion": props.get("DIRECCION"),
                },
            })
        if len(pagina) < cfg.pagina and not datos.get("properties", {}).get("exceededTransferLimit"):
            break
        offset += len(pagina)
        if not pagina:
            break
    stats.siniestros = len(features)
    _escribir(cfg.siniestros, features, "SDM Bogotá - Histórico de siniestros (datosabiertos.bogota.gov.co)")
    return cfg.siniestros


def descargar_pois(cfg: EvidenciaConfig = EvidenciaConfig(), stats: EvidenciaStats | None = None) -> Path:
    """Colegios y centros de salud de OSM dentro del bbox de la red."""
    stats = stats if stats is not None else EvidenciaStats()
    s, w, n, e = BBOX_USAQUEN
    regex = "|".join(AMENIDADES)
    consulta = (
        f'[out:json][timeout:{cfg.timeout_s}];'
        f'(nwr["amenity"~"^({regex})$"]({s},{w},{n},{e}););'
        'out center tags;'
    )
    datos = _overpass(consulta, cfg.timeout_s)
    features = []
    for el in datos.get("elements", []):
        lon = el.get("lon", el.get("center", {}).get("lon"))
        lat = el.get("lat", el.get("center", {}).get("lat"))
        if lon is None or lat is None:
            continue
        tags = el.get("tags", {})
        tipo = tags.get("amenity")
        stats.pois_por_tipo[tipo] = stats.pois_por_tipo.get(tipo, 0) + 1
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [round(lon, 6), round(lat, 6)]},
            "properties": {"tipo": tipo, "nombre": tags.get("name")},
        })
    stats.pois = len(features)
    _escribir(cfg.pois, features, "OpenStreetMap (Overpass), ODbL")
    return cfg.pois


def _overpass(consulta: str, timeout: int) -> dict:
    ultimo: Exception | None = None
    for url in URLS_OVERPASS:
        try:
            datos = _leer_json(url, urllib.parse.urlencode({"data": consulta}).encode(), timeout, intentos=2)
            if "elements" in datos:
                return datos
        except EvidenciaError as exc:
            ultimo = exc
    raise EvidenciaError(f"Ningún servidor Overpass respondió: {ultimo}")


def _altura_osm(tags: dict) -> float | None:
    """Altura en metros: `height` si existe; si no, `building:levels` x 3 m."""
    for clave, factor in (("height", 1.0), ("building:levels", 3.0)):
        valor = (tags.get(clave) or "").replace(",", ".").split(" ")[0].removesuffix("m")
        try:
            numero = float(valor) * factor
        except ValueError:
            continue
        if 2 <= numero <= 250:
            return round(numero, 1)
    return None


def descargar_edificios(cfg: EvidenciaConfig = EvidenciaConfig(), stats: EvidenciaStats | None = None) -> Path:
    """Huellas de edificios de OSM dentro del bbox de la red."""
    stats = stats if stats is not None else EvidenciaStats()
    s, w, n, e = BBOX_USAQUEN
    consulta = f'[out:json][timeout:{cfg.timeout_s * 2}];way["building"]({s},{w},{n},{e});out tags geom;'
    datos = _overpass(consulta, cfg.timeout_s * 3)
    features = []
    for el in datos.get("elements", []):
        anillo = [[round(p["lon"], 7), round(p["lat"], 7)] for p in el.get("geometry", [])]
        if len(anillo) < 4 or anillo[0] != anillo[-1]:
            continue
        tags = el.get("tags", {})
        features.append({
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [anillo]},
            "properties": {"height": _altura_osm(tags) or -1, "building": tags.get("building")},
        })
    stats.edificios = len(features)
    _escribir(cfg.edificios, features, "OpenStreetMap (Overpass), ODbL")
    return cfg.edificios


def leer_puntos(path: Path) -> list[tuple[float, float, dict]]:
    """(lon, lat, propiedades) de un GeoJSON de puntos; vacío si el archivo no existe."""
    if not path.is_file():
        return []
    datos = json.loads(path.read_text(encoding="utf-8"))
    return [
        (f["geometry"]["coordinates"][0], f["geometry"]["coordinates"][1], f.get("properties") or {})
        for f in datos.get("features", [])
        if (f.get("geometry") or {}).get("type") == "Point"
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Descarga la evidencia para priorizar cruces.")
    parser.add_argument("fuentes", nargs="*", choices=["siniestros", "pois", "edificios"])
    args = parser.parse_args()
    args.fuentes = args.fuentes or ["siniestros", "pois", "edificios"]
    stats = EvidenciaStats()
    if "siniestros" in args.fuentes:
        print(f"siniestros -> {descargar_siniestros(stats=stats)} ({stats.siniestros})")
    if "pois" in args.fuentes:
        print(f"pois -> {descargar_pois(stats=stats)} ({stats.pois}: {stats.pois_por_tipo})")
    if "edificios" in args.fuentes:
        print(f"edificios -> {descargar_edificios(stats=stats)} ({stats.edificios})")


if __name__ == "__main__":
    main()
