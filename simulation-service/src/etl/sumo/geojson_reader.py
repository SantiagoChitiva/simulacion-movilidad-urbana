import json
from pathlib import Path
from typing import Any

_FEATURES_MARKER = '"features":['


def read_first_features(
    path: Path, limit: int = 3, chunk_size: int = 64 * 1024
) -> list[dict[str, Any]]:
    """Lee solo los primeros `limit` features, sin cargar el archivo completo."""
    decoder = json.JSONDecoder()
    features: list[dict[str, Any]] = []

    with open(path, encoding="utf-8") as f:
        buffer = ""

        # 1) saltar la cabecera hasta el inicio del arreglo "features"
        while _FEATURES_MARKER not in buffer:
            chunk = f.read(chunk_size)
            if not chunk:
                return features
            buffer += chunk
        buffer = buffer.split(_FEATURES_MARKER, 1)[1]

        # 2) decodificar feature por feature
        while len(features) < limit:
            buffer = buffer.lstrip(" \n\r\t,")
            if buffer.startswith("]"):
                break
            try:
                feature, end = decoder.raw_decode(buffer)
            except json.JSONDecodeError:
                # el feature está incompleto en el buffer: leer más
                chunk = f.read(chunk_size)
                if not chunk:
                    break
                buffer += chunk
                continue
            features.append(feature)
            buffer = buffer[end:]

    return features
