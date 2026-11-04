"""Histograma de la hora de salida de los viajes: encuesta vs. simulación SUMO.

Compara, en la ventana 7:00-10:00 y con intervalos de 10 min, la distribución de
la hora de inicio de los viajes de:

- Encuesta (expandida): cada fila pesa `fexp_vj`.
- Encuesta (insumo de SUMO): cada fila se replica `round(fexp_vj)` veces con
  tope `MAX_COPIAS`, que es lo que se le entrega realmente al simulador.
- Simulación: `inicio_s` de cada viaje en el `trips.geojson.gz` de una corrida
  (por defecto la precalculada `encuesta`).

Como la simulación y la encuesta tienen totales distintos, el panel inferior
normaliza cada serie a porcentaje para comparar solo la forma de la curva.

Uso (desde simulation-service/):
    python validation/histograma_salidas.py
    python validation/histograma_salidas.py --trips runs/<id>/trips.geojson.gz
"""
import argparse
import csv
import gzip
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ / "src"))

from etl.sumo.configuration import HORA_FIN, HORA_INI, MAX_COPIAS  # noqa: E402

TSV = RAIZ / "src/etl/sumo/scenarios/default/viajes_usaquen_internos.tsv"
TRIPS = RAIZ / "precalculadas/encuesta/trips.geojson.gz"
SALIDA = Path(__file__).with_name("histograma_salidas.png")
INTERVALO_MIN = 10


def _indice(segundos: float, intervalo_s: int) -> int | None:
    if not (HORA_INI <= segundos < HORA_FIN):
        return None
    return int((segundos - HORA_INI) // intervalo_s)


def leer_encuesta(tsv: Path, intervalo_s: int, n: int) -> tuple[list[float], list[float]]:
    """Devuelve (expandida por fexp, replicada como la recibe SUMO) por intervalo."""
    expandida, para_sumo = [0.0] * n, [0.0] * n
    with open(tsv, encoding="utf-8", newline="") as f:
        for fila in csv.DictReader(f, delimiter="\t"):
            try:
                i = _indice(float(fila["hora_ini_seg"]), intervalo_s)
            except (ValueError, TypeError):
                continue
            if i is None:
                continue
            try:
                fexp = float(fila["fexp_vj"]) if fila["fexp_vj"] else 1.0
            except ValueError:
                fexp = 1.0
            expandida[i] += fexp
            para_sumo[i] += min(max(round(fexp), 1), MAX_COPIAS)
    return expandida, para_sumo


def leer_simulacion(trips: Path, intervalo_s: int, n: int) -> list[float]:
    conteo = [0.0] * n
    with gzip.open(trips, "rt", encoding="utf-8") as f:
        datos = json.load(f)
    for feature in datos["features"]:
        i = _indice(feature["properties"]["inicio_s"], intervalo_s)
        if i is not None:
            conteo[i] += 1
    return conteo


def porcentaje(serie: list[float]) -> list[float]:
    total = sum(serie)
    return [100 * v / total if total else 0.0 for v in serie]


def etiquetas(intervalo_s: int, n: int) -> list[str]:
    def hhmm(s: int) -> str:
        return f"{s // 3600:02d}:{s % 3600 // 60:02d}"
    return [hhmm(HORA_INI + i * intervalo_s) for i in range(n)]


def graficar(series: dict[str, list[float]], intervalo_s: int, salida: Path) -> None:
    n = len(next(iter(series.values())))
    x = range(n)
    ancho = 0.8 / len(series)
    colores = ["#4c78a8", "#9ecae9", "#e45756"]

    fig, (arriba, abajo) = plt.subplots(2, 1, figsize=(13, 9), sharex=True)
    for j, (nombre, valores) in enumerate(series.items()):
        desplazamiento = [i - 0.4 + ancho * (j + 0.5) for i in x]
        arriba.bar(desplazamiento, valores, ancho, label=f"{nombre} (n={sum(valores):,.0f})",
                   color=colores[j])
        abajo.plot(x, porcentaje(valores), marker="o", label=nombre, color=colores[j])

    arriba.set_ylabel("Viajes por intervalo")
    arriba.set_title(f"Hora de salida de los viajes, 7:00-10:00 (intervalos de {intervalo_s // 60} min)")
    arriba.set_yscale("log")
    arriba.grid(axis="y", alpha=0.3)
    arriba.legend()

    abajo.set_ylabel("% de los viajes de la serie")
    abajo.set_xlabel("Hora de salida")
    abajo.set_xticks(list(x), etiquetas(intervalo_s, n), rotation=45)
    abajo.grid(alpha=0.3)
    abajo.legend()

    fig.tight_layout()
    fig.savefig(salida, dpi=150)
    plt.close(fig)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--tsv", type=Path, default=TSV)
    p.add_argument("--trips", type=Path, default=TRIPS, help="trips.geojson.gz de la simulación")
    p.add_argument("--salida", type=Path, default=SALIDA)
    p.add_argument("--intervalo", type=int, default=INTERVALO_MIN, help="minutos por intervalo")
    args = p.parse_args()

    intervalo_s = args.intervalo * 60
    n = (HORA_FIN - HORA_INI) // intervalo_s
    expandida, para_sumo = leer_encuesta(args.tsv, intervalo_s, n)
    simulada = leer_simulacion(args.trips, intervalo_s, n)

    graficar(
        {
            "Encuesta (expandida)": expandida,
            "Encuesta (insumo SUMO)": para_sumo,
            "Simulación SUMO": simulada,
        },
        intervalo_s,
        args.salida,
    )

    print(f"{'intervalo':>9} {'encuesta':>10} {'insumo':>8} {'SUMO':>7}")
    for e, a, b, c in zip(etiquetas(intervalo_s, n), expandida, para_sumo, simulada):
        print(f"{e:>9} {a:>10,.0f} {b:>8,.0f} {c:>7,.0f}")
    print(f"Gráfica: {args.salida}")


if __name__ == "__main__":
    main()
