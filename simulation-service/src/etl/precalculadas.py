"""
Simulaciones precalculadas de los presets de demanda.

Una corrida completa tarda ~12 min, así que los cuatro presets (con sus conteos por
defecto) se simulan una vez en local y sus resultados se versionan en
precalculadas/<preset>/:
- trips.geojson.gz: el GeoJSON de kepler comprimido. La API lo envía tal cual con
  Content-Encoding: gzip y el navegador lo descomprime al recibirlo, así que nunca
  existe descomprimido en disco.
- volumenes.json: volúmenes por edge para la ficha de intersecciones.
- meta.json: parámetros, resumen y la huella de los insumos con que se generó.

Uso: python -m etl.precalculadas [preset ...] [--semilla N]   (sin presets: los cuatro)
"""
import argparse
import gzip
import hashlib
import json
import shutil
from collections import Counter
from collections.abc import Callable
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from typing import Any

from .etl import OnProgreso, resumen_corrida, run_pipeline
from .sumo.configuration import DEFAULT_SCENARIO, ArchivosPrecalculada, ScenarioPaths
from .sumo.demanda import PRESETS, DemandaConfig, Preset, cargar_dia, cargar_ventana, conteos_preset
from .sumo.intersecciones import volumenes_por_edge


def _sin_aviso(_etapa: str, _avance: float | None) -> None:
    pass


# ----------------------------------------------------------------- huella

def _insumos(paths: ScenarioPaths) -> tuple[Path, ...]:
    return (paths.tsv, paths.net, paths.taz, paths.sumocfg_template)


@lru_cache(maxsize=4)
def _huella(firmas: tuple[tuple[str, float, int], ...]) -> str:
    sha = hashlib.sha256()
    for ruta, _, _ in firmas:
        # git con autocrlf cambia los fines de línea al clonar en Windows
        sha.update(Path(ruta).read_bytes().replace(b"\r\n", b"\n"))
    return sha.hexdigest()[:16]


def huella_insumos(paths: ScenarioPaths | None = None) -> str:
    """Huella del contenido de encuesta, red, TAZ y plantilla sumocfg.

    Es de contenido (no de mtime) porque un clon nuevo no conserva las fechas; la
    firma por mtime/tamaño solo evita volver a leer ~60 MB en cada consulta.
    """
    paths = paths or ScenarioPaths.from_name(DEFAULT_SCENARIO)
    firmas = tuple((str(p), p.stat().st_mtime, p.stat().st_size) for p in _insumos(paths))
    return _huella(firmas)


# ---------------------------------------------------------------- generar

def _comprimir(origen: Path, destino: Path) -> None:
    # mtime=0 y sin nombre: el mismo GeoJSON da el mismo .gz y git no ve cambios
    tmp = destino.with_name(destino.name + ".tmp")
    with tmp.open("wb") as crudo, \
         gzip.GzipFile(filename="", mode="wb", fileobj=crudo, compresslevel=9, mtime=0) as gz, \
         origen.open("rb") as entrada:
        shutil.copyfileobj(entrada, gz, 1 << 20)
    tmp.replace(destino)


def generar(
    preset: Preset,
    semilla: int | None = None,
    on_progreso: OnProgreso = _sin_aviso,
    ejecutar: Callable[..., Any] = run_pipeline,
) -> dict[str, Any]:
    """Simula un preset con sus conteos por defecto y guarda lo que necesita el visor."""
    escenario = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    conteos = conteos_preset(preset, cargar_ventana(escenario.tsv), cargar_dia(escenario.tsv))
    run_id = f"precalculada-{preset.value}"
    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO, run_id)
    shutil.rmtree(paths.run_dir, ignore_errors=True)   # restos de un intento anterior

    resultado = ejecutar(
        DEFAULT_SCENARIO,
        seed=semilla,
        demanda=DemandaConfig(preset, conteos),
        run_id=run_id,
        exportar_puntos=False,
        on_progreso=on_progreso,
        cancelar=None,
    )

    archivos = ArchivosPrecalculada.from_preset(preset.value)
    archivos.dir.mkdir(parents=True, exist_ok=True)
    _comprimir(paths.kepler_trips, archivos.trips_gz)
    vols = volumenes_por_edge(paths.vehroute) if paths.vehroute.is_file() else {}
    archivos.volumenes.write_text(json.dumps(vols, sort_keys=True), encoding="utf-8")

    meta = {
        "preset": preset.value,
        "conteos": {m.value: n for m, n in conteos.items()},
        "semilla": semilla,
        "generada": datetime.now().astimezone().isoformat(timespec="seconds"),
        "insumos": huella_insumos(escenario),
        "tamano_original": paths.kepler_trips.stat().st_size,
        "tamano_gz": archivos.trips_gz.stat().st_size,
        "resultado": resumen_corrida(resultado, paths),
    }
    archivos.meta.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    # solo se borra si todo salió bien: ante un error queda el log de SUMO para revisar
    shutil.rmtree(paths.run_dir, ignore_errors=True)
    return meta


# ----------------------------------------------------------------- leer

def cargar(preset: Preset) -> dict[str, Any] | None:
    """meta.json de un preset, o None si no está precalculado."""
    archivos = ArchivosPrecalculada.from_preset(preset.value)
    if not (archivos.trips_gz.is_file() and archivos.meta.is_file()):
        return None
    try:
        return json.loads(archivos.meta.read_text(encoding="utf-8"))
    except ValueError:
        return None


def listar() -> list[dict[str, Any]]:
    """Presets precalculados, con su nombre y si se generaron con otros insumos."""
    huella = huella_insumos()
    salida = []
    for preset, info in PRESETS.items():
        meta = cargar(preset)
        if meta is not None:
            salida.append({**meta, "nombre": info.nombre, "desactualizada": meta.get("insumos") != huella})
    return salida


def leer_volumenes(preset: Preset) -> dict[str, Counter] | None:
    archivo = ArchivosPrecalculada.from_preset(preset.value).volumenes
    if not archivo.is_file():
        return None
    return {e: Counter(t) for e, t in json.loads(archivo.read_text(encoding="utf-8")).items()}


# ------------------------------------------------------------------- CLI

def _imprimir_avance(nombre: str) -> OnProgreso:
    ultimo: dict[str, int] = {}

    def aviso(etapa: str, avance: float | None) -> None:
        decil = int((avance or 0) * 10)
        if ultimo.get(etapa, -1) < decil:
            ultimo[etapa] = decil
            print(f"  [{nombre}] {etapa} {decil * 10} %", flush=True)

    return aviso


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Genera las simulaciones precalculadas de los presets.")
    parser.add_argument("presets", nargs="*", choices=[p.value for p in Preset], metavar="preset",
                        help=f"presets a generar (por defecto todos): {', '.join(p.value for p in Preset)}")
    parser.add_argument("--semilla", type=int, default=None, help="semilla de SUMO (por defecto la del .sumocfg)")
    args = parser.parse_args(argv)

    for valor in args.presets or [p.value for p in Preset]:
        preset = Preset(valor)
        print(f"Generando '{valor}'...", flush=True)
        meta = generar(preset, args.semilla, _imprimir_avance(valor))
        mb = lambda n: f"{n / 1e6:.1f} MB"
        # solo ASCII: la consola de Windows suele estar en cp1252
        print(f"  listo: {meta['resultado'].get('trips_kepler', 0)} trips, "
              f"{mb(meta['tamano_original'])} -> {mb(meta['tamano_gz'])} comprimido", flush=True)


if __name__ == "__main__":
    main()
