"""
Vías de la red como GeoJSON, para elegir cierres viales haciendo clic en el mapa.

Cada edge vehicular de la red sale como un LineString con su nombre (de la red o de
nombres_vias.json), clase, carriles y el edge del sentido contrario si existe (los
edges de OSM de doble sentido son "123#4" y "-123#4"). Se omiten los peatonales,
ciclorrutas, las vías de servicio (parqueaderos, accesos a predios) y los edges de solo
buses (TransMilenio).
"""
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from .intersecciones import _firma, _transformador, _via_osm, clase_via

# clases OSM por las que no circulan carros (cerrarlas no cambia la simulación vehicular)
# y las de servicio, que llenarían el mapa de tramos que casi nadie va a cerrar
_NO_VEHICULARES = {"footway", "pedestrian", "path", "steps", "cycleway", "track", "bridleway", "corridor", "service"}
_SOLO_BUS = {"bus", "psv", "bus psv"}


def _vehicular(elem: ET.Element) -> bool:
    base = (elem.get("type") or "").split("|")[0].split(".")[-1].removesuffix("_link")
    if not base or base in _NO_VEHICULARES:
        return False
    carriles = elem.findall("lane")
    return bool(carriles) and not all(l.get("allow", "") in _SOLO_BUS for l in carriles) \
        and any("passenger" not in l.get("disallow", "") for l in carriles)


def leer_vias(net_path: Path, nombres_vias: dict[str, str] | None = None) -> dict[str, Any]:
    """FeatureCollection con un LineString por edge vehicular de la red."""
    nombres_vias = nombres_vias or {}
    a_lonlat = None
    crudas: list[tuple[str, dict[str, Any], list[tuple[float, float]]]] = []
    for _, elem in ET.iterparse(net_path, events=("end",)):
        if elem.tag == "location":
            a_lonlat = _transformador(elem)
        elif elem.tag == "edge":
            if elem.get("function") is None and _vehicular(elem):
                carriles = elem.findall("lane")
                forma = elem.get("shape") or carriles[0].get("shape", "")
                puntos = [tuple(map(float, p.split(",")[:2])) for p in forma.split()]
                eid = elem.get("id")
                if len(puntos) >= 2:
                    crudas.append((eid, {
                        "id": eid,
                        "nombre": elem.get("name") or nombres_vias.get(_via_osm(eid)),
                        "clase": clase_via(elem.get("type")),
                        "carriles": len(carriles),
                    }, puntos))
            elem.clear()
    if a_lonlat is None:
        raise ValueError(f"La red {net_path} no tiene <location>")

    ids = {eid for eid, _, _ in crudas}
    features = []
    for eid, props, puntos in crudas:
        contrario = eid[1:] if eid.startswith("-") else f"-{eid}"
        props["contrario"] = contrario if contrario in ids else None
        coords = [[round(c, 6) for c in a_lonlat(x, y)] for x, y in puntos]
        features.append({"type": "Feature", "geometry": {"type": "LineString", "coordinates": coords}, "properties": props})
    return {"type": "FeatureCollection", "features": features}


def vias_con_cache(net_path: Path, nombres_path: Path | None, cache_path: Path) -> dict[str, Any]:
    """leer_vias con caché en disco (se invalida si cambia la red o los nombres)."""
    hay_nombres = nombres_path is not None and nombres_path.is_file()
    firma = _firma(net_path) + (_firma(nombres_path) if hay_nombres else [])
    if cache_path.is_file():
        try:
            datos = json.loads(cache_path.read_text(encoding="utf-8"))
            if datos.get("firma") == firma:
                return datos["vias"]
        except (ValueError, KeyError, TypeError):
            pass
    nombres = json.loads(nombres_path.read_text(encoding="utf-8")) if hay_nombres else None
    vias = leer_vias(net_path, nombres)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps({"firma": firma, "vias": vias}, ensure_ascii=False), encoding="utf-8")
    return vias
