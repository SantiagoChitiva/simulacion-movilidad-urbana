import json
import xml.etree.ElementTree as ET
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class FcdToGeoJsonConfig:
    fcd_path: Path
    output_path: Path
    sample_every: int = 1            # segundos: 1 = todos los pasos, 10 = uno de cada 10
    include_persons: bool = True     # peatones / transporte público (<person>)


@dataclass
class FcdConversionStats:
    timesteps_leidos: int = 0
    timesteps_exportados: int = 0
    features_escritos: int = 0
    sin_coordenadas: int = 0


@dataclass(frozen=True)
class FcdConversionResult:
    output_path: Path
    stats: FcdConversionStats


def _feature(elem: ET.Element, time: float, kind: str) -> dict[str, Any] | None:
    x, y = elem.get("x"), elem.get("y")
    if x is None or y is None:
        return None

    return {
        "type": "Feature",
        "geometry": {
            "type": "Point",
            # con fcd-output.geo=true: x = longitud, y = latitud
            "coordinates": [round(float(x), 6), round(float(y), 6)],
        },
        "properties": {
            "time": time,                          # segundos desde las 00:00
            "id": elem.get("id"),
            "kind": kind,                          # "vehicle" | "person"
            "type": elem.get("type") or kind,      # vType (los person no lo traen)
            "speed": round(float(elem.get("speed", 0)), 2),   # m/s
            "angle": round(float(elem.get("angle", 0)), 1),
        },
    }


def _iter_features(
    config: FcdToGeoJsonConfig, stats: FcdConversionStats
) -> Iterator[dict[str, Any]]:
    kinds = {"vehicle"} | ({"person"} if config.include_persons else set())
    root: ET.Element | None = None

    for event, elem in ET.iterparse(config.fcd_path, events=("start", "end")):
        if event == "start":
            if root is None:
                root = elem          # <fcd-export>
            continue

        if elem.tag != "timestep":
            continue

        stats.timesteps_leidos += 1
        time = float(elem.get("time", 0))

        if round(time) % config.sample_every == 0:
            stats.timesteps_exportados += 1
            for child in elem:
                if child.tag not in kinds:
                    continue
                feature = _feature(child, time, child.tag)
                if feature is None:
                    stats.sin_coordenadas += 1
                    continue
                yield feature

        # libera memoria: el timestep ya fue procesado
        elem.clear()
        if root is not None:
            root.clear()


def convert_fcd_to_geojson(config: FcdToGeoJsonConfig) -> FcdConversionResult:
    if not config.fcd_path.is_file():
        raise FileNotFoundError(f"No existe el archivo FCD: {config.fcd_path}")
    if config.sample_every < 1:
        raise ValueError("sample_every debe ser >= 1")

    stats = FcdConversionStats()
    config.output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(config.output_path, "w", encoding="utf-8") as out:
        out.write('{"type":"FeatureCollection","features":[')
        first = True
        for feature in _iter_features(config, stats):
            if not first:
                out.write(",")
            out.write(json.dumps(feature, separators=(",", ":")))
            first = False
            stats.features_escritos += 1
        out.write("]}")

    return FcdConversionResult(config.output_path, stats)
