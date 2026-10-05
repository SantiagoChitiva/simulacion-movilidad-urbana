# -*- coding: utf-8 -*-
"""
Geocodifica las LOCALIZACIÓN únicas del aforo HMD (F1.1) y determina cuáles
caen dentro del polígono oficial de Usaquén.

Usado por `02_limpieza_aforos_hmd_usaquen.ipynb` (F2.1). Se ejecuta como
script aparte (no dentro del notebook) porque hace ~300-600 solicitudes
secuenciales a Overpass/Nominatim respetando sus políticas de uso (1
solicitud cada ~2s), lo que toma varios minutos.

Dos métodos, elegidos automáticamente según el patrón del texto:
  - "interseccion": para strings tipo "AC 80 X KR 116A" -> normaliza ambas
    vías a la nomenclatura que usa OpenStreetMap (Avenida Calle, Avenida
    Carrera, Carrera, Transversal, Diagonal, avenidas con nombre propio) y
    calcula la intersección geométrica real de las dos vías vía Overpass API.
  - "lugar": para nombres de estación/portal/lugar (ej. "Alquería",
    "Toberín") -> geocodifica como lugar/POI vía Nominatim.

El resultado se cachea incrementalmente en
`data/processed/geocoding_usaquen_cache.json` para poder reanudar si se
interrumpe y para no repetir solicitudes en corridas futuras del notebook.

Uso:
    python geocoding_usaquen.py
"""
import json
import re
import time
from pathlib import Path

import geopandas as gpd
import pandas as pd
import requests
from shapely.geometry import LineString, Point
from shapely.ops import unary_union

NOTEBOOKS_DIR = Path(__file__).resolve().parent
ROOT = NOTEBOOKS_DIR.parent
RAW_XLSX = ROOT / "data" / "raw" / "a. Base de datos aforos hora de maxima demanda.xlsx"
LIMITES = ROOT / "data" / "raw" / "limites" / "loca.json"
CACHE_PATH = ROOT / "data" / "processed" / "geocoding_usaquen_cache.json"

HEADERS = {"User-Agent": "tesis-movilidad-usaquen-javeriana/1.0 (contacto: equipo del proyecto)"}
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
BBOX = "4.45,-74.25,4.85,-73.95"  # lat_min,lon_min,lat_max,lon_max (Bogotá + margen)

SLEEP_OVERPASS = 2.2
SLEEP_NOMINATIM = 1.1

# --- normalización de abreviaturas viales de Bogotá -> nomenclatura OSM ---
PREFIX_MAP = [
    (r"^AC\s*(\d)", r"Avenida Calle \1"),
    (r"^AK\s*(\d)", r"Avenida Carrera \1"),
    (r"^KR\s*(\d)", r"Carrera \1"),
    (r"^CRA\s*(\d)", r"Carrera \1"),
    (r"^CL\s*(\d)", r"Calle \1"),
    (r"^TV\.?\s*(\d)", r"Transversal \1"),
    (r"^DG\s*(\d)", r"Diagonal \1"),
    (r"^CA\s*(\d)", r"Calle \1"),  # variante observada "CA 19 S"
    (r"^AV\.\s*(\d)", r"Avenida \1"),
]

NAMED_AVENUE_MAP = {
    "BOYACÁ": "Avenida Boyacá",
    "BOYACA": "Avenida Boyacá",
    "CARACAS": "Avenida Caracas",
    "CIRCUNVALAR": "Avenida Circunvalar",
    "CIRCUNVAR": "Avenida Circunvalar",
    "EL DORADO": "Avenida El Dorado",
    "AMÉRICAS": "Avenida de las Américas",
    "AMERICAS": "Avenida de las Américas",
    "AMÉRCIAS": "Avenida de las Américas",
    "SUBA": "Avenida Suba",
    "VILLAVICENCIO": "Avenida Villavicencio",
    "1 MAYO": "Avenida Primero de Mayo",
    "1 DE MAYO": "Avenida Primero de Mayo",
    "CALI": "Avenida Ciudad de Cali",
    "AUTOSUR": "Autopista Sur",
    "AUTONORTE": "Autopista Norte",
    "NQS": "Avenida NQS",
    "TERREROS": "Avenida Terreros",
    "CHILE": "Avenida Chile",
    "JIMÉNEZ": "Avenida Jiménez",
    "JIMENEZ": "Avenida Jiménez",
    "LA CONEJERA": "Avenida La Conejera",
}

STREET_TOKEN_RE = re.compile(
    r"^(AC|AK|KR|CL|TV|DG|CRA|CA|AV\.?|AUTOSUR|AUTONORTE|NQS|SUBA|BOYAC|CARACAS|"
    r"CIRCUNVA|AMÉRI|AMERI|AMÉRC|VILLAVICENCIO|CALI|CHILE|JIM[EÉ]NEZ)\b",
    re.IGNORECASE,
)


def normalize_token(tok: str) -> str:
    tok = tok.strip()
    key = tok.upper()
    if key in NAMED_AVENUE_MAP:
        return NAMED_AVENUE_MAP[key]
    for pat, repl in PREFIX_MAP:
        new = re.sub(pat, repl, tok, flags=re.IGNORECASE)
        if new != tok:
            tok = new
            break
    return re.sub(r"\s+", " ", tok).strip()


def split_intersection(raw: str):
    """Devuelve (calle_a, calle_b) si raw luce como una intersección de dos vías, si no None."""
    s = raw.strip()
    for sep_pat in (r"\s+X\s+", r"_X_"):
        parts = re.split(sep_pat, s, flags=re.IGNORECASE)
        if len(parts) == 2:
            return parts[0].strip(), parts[1].strip()
    if " - " in s:
        a, b = s.split(" - ", 1)
        if STREET_TOKEN_RE.match(a.strip()) and STREET_TOKEN_RE.match(b.strip()):
            return a.strip(), b.strip()
    m = re.match(
        r"^((?:AC|AK|KR|CL|TV|DG|CRA|CA)\s*\d+[A-Z]*(?:\s+[SN])?)\s+"
        r"((?:AC|AK|KR|CL|TV|DG|CRA|CA)\s*\d+[A-Z]*(?:\s+[SN])?)$",
        s,
        re.IGNORECASE,
    )
    if m:
        return m.group(1), m.group(2)
    return None


def overpass_ways(name_a, name_b, retries=4):
    q = f"""
    [out:json][timeout:60];
    (
      way["highway"]["name"="{name_a}"]({BBOX});
      way["highway"]["name"="{name_b}"]({BBOX});
    );
    out geom;
    """
    for attempt in range(retries):
        try:
            r = requests.post(OVERPASS_URL, data={"data": q}, headers=HEADERS, timeout=90)
        except requests.RequestException:
            time.sleep(5 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(8 * (attempt + 1))
            continue
        if r.status_code != 200:
            time.sleep(5 * (attempt + 1))
            continue
        try:
            els = r.json()["elements"]
        except Exception:
            time.sleep(5 * (attempt + 1))
            continue
        lines_a, lines_b = [], []
        for el in els:
            geom = el.get("geometry")
            if not geom:
                continue
            line = LineString([(pt["lon"], pt["lat"]) for pt in geom])
            nm = el.get("tags", {}).get("name")
            if nm == name_a:
                lines_a.append(line)
            elif nm == name_b:
                lines_b.append(line)
        return lines_a, lines_b
    return [], []


def nominatim_place(query, retries=3):
    params = {
        "format": "jsonv2",
        "q": f"{query}, Bogotá, Colombia",
        "limit": 3,
        "countrycodes": "co",
    }
    for attempt in range(retries):
        try:
            r = requests.get(NOMINATIM_URL, params=params, headers=HEADERS, timeout=20)
        except requests.RequestException:
            time.sleep(5 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(8 * (attempt + 1))
            continue
        if r.status_code != 200:
            time.sleep(5 * (attempt + 1))
            continue
        try:
            return r.json()
        except Exception:
            time.sleep(5 * (attempt + 1))
            continue
    return []


def geocode_localizacion(raw, usaquen_polygon):
    result = {"raw": raw, "method": None, "candidates": [], "in_usaquen": None, "note": None}
    pair = split_intersection(raw)

    if pair:
        street_a, street_b = normalize_token(pair[0]), normalize_token(pair[1])
        result.update(method="interseccion", street_a=street_a, street_b=street_b)
        lines_a, lines_b = overpass_ways(street_a, street_b)
        time.sleep(SLEEP_OVERPASS)
        if lines_a and lines_b:
            inter = unary_union(lines_a).intersection(unary_union(lines_b))
            pts = []
            if not inter.is_empty:
                if inter.geom_type == "Point":
                    pts = [(inter.x, inter.y)]
                elif hasattr(inter, "geoms"):
                    for g in inter.geoms:
                        p = g if g.geom_type == "Point" else g.centroid
                        pts.append((p.x, p.y))
            result["candidates"] = pts
            if pts:
                result["in_usaquen"] = any(usaquen_polygon.contains(Point(x, y)) for x, y in pts)
            else:
                result["note"] = "vías encontradas pero sin cruce geométrico"
        else:
            result["note"] = (
                f"no se encontraron segmentos OSM para una o ambas vías "
                f"(a={len(lines_a)}, b={len(lines_b)})"
            )
    else:
        result["method"] = "lugar"
        places = nominatim_place(raw)
        time.sleep(SLEEP_NOMINATIM)
        pts = [(float(p["lon"]), float(p["lat"])) for p in places]
        result["candidates"] = pts
        if pts:
            result["in_usaquen"] = any(usaquen_polygon.contains(Point(x, y)) for x, y in pts)
        else:
            result["note"] = "sin resultados en Nominatim"

    return result


def main():
    bd = pd.read_excel(RAW_XLSX, sheet_name="BD")
    uniq = sorted(loc.strip() for loc in bd["LOCALIZACIÓN"].dropna().unique() if loc.strip())
    print(f"Total LOCALIZACIÓN únicas: {len(uniq)}")

    usaquen_gdf = gpd.read_file(LIMITES)
    usaquen_gdf = usaquen_gdf[usaquen_gdf["LocNombre"] == "USAQUEN"].to_crs(epsg=4326)
    usaquen_polygon = usaquen_gdf.geometry.iloc[0]

    cache = json.loads(CACHE_PATH.read_text(encoding="utf-8")) if CACHE_PATH.exists() else {}
    print(f"Cache existente: {len(cache)} entradas")

    for i, raw in enumerate(uniq):
        if raw in cache:
            continue
        result = geocode_localizacion(raw, usaquen_polygon)
        cache[raw] = result
        print(f"[{i + 1}/{len(uniq)}] {raw!r} -> method={result['method']} "
              f"in_usaquen={result['in_usaquen']} n_cand={len(result['candidates'])}")
        if (i + 1) % 10 == 0:
            CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")

    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Listo.")


if __name__ == "__main__":
    main()
