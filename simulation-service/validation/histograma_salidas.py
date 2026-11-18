"""Histograma de la hora de salida de los viajes: encuesta vs. simulación SUMO.

Compara, en la ventana 7:00-10:00 y con intervalos de 10 min, la distribución de
la hora de inicio de los viajes de:

- Encuesta (expandida): cada fila pesa `fexp_vj`.
- Encuesta repartida (insumo de SUMO): cada fila se replica `round(fexp_vj)`
  veces con tope `MAX_COPIAS` y las copias se reparten alrededor de la hora
  reportada con `trips.salidas_dispersas` (±30 min en horas en punto), que es
  exactamente lo que se le entrega al simulador.
- Simulación: `inicio_s` de cada viaje en el `trips.geojson.gz` de una corrida
  (por defecto la precalculada `encuesta`).

Como la simulación y la encuesta tienen totales distintos, los paneles de
porcentaje normalizan cada serie para comparar solo la forma de la curva: el
del medio por intervalo y el inferior por hora.

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
from etl.sumo.trips import salidas_dispersas  # noqa: E402

TSV = RAIZ / "src/etl/sumo/scenarios/default/viajes_usaquen_internos.tsv"
TRIPS = RAIZ / "precalculadas/encuesta/trips.geojson.gz"
SALIDA = Path(__file__).with_name("histograma_salidas.png")
INTERVALO_MIN = 10


def _indice(segundos: float, intervalo_s: int) -> int | None:
    if not (HORA_INI <= segundos < HORA_FIN):
        return None
    return int((segundos - HORA_INI) // intervalo_s)


def leer_encuesta(tsv: Path, intervalo_s: int, n: int) -> tuple[list[float], list[float]]:
    """Devuelve (expandida por fexp, replicada y repartida como la recibe SUMO) por intervalo."""
    expandida, para_sumo = [0.0] * n, [0.0] * n
    with open(tsv, encoding="utf-8", newline="") as f:
        for fila in csv.DictReader(f, delimiter="\t"):
            try:
                salida = float(fila["hora_ini_seg"])
            except (ValueError, TypeError):
                continue
            i = _indice(salida, intervalo_s)
            if i is None:
                continue
            try:
                fexp = float(fila["fexp_vj"]) if fila["fexp_vj"] else 1.0
            except ValueError:
                fexp = 1.0
            expandida[i] += fexp
            copias = min(max(round(fexp), 1), MAX_COPIAS)
            # mismo reparto que trips._build_xml: la ventana es [HORA_INI, HORA_FIN)
            for t in salidas_dispersas(salida, copias, HORA_INI, HORA_FIN):
                para_sumo[_indice(t, intervalo_s)] += 1
    return expandida, para_sumo


def leer_simulacion(trips: Path, intervalo_s: int, n: int) -> list[float]:
    conteo = [0.0] * n
    with gzip.open(trips, "rt", encoding="utf-8") as f:
        datos = json.load(f)
    for feature in datos["features"]:
        # los buses del GTFS (bus_sitp, bus_tm) siguen su horario, no son viajes de la encuesta
        if feature["properties"].get("mode", "").startswith("bus_"):
            continue
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


def por_hora(serie: list[float], intervalo_s: int) -> list[float]:
    por = 3600 // intervalo_s
    return [sum(serie[k:k + por]) for k in range(0, len(serie), por)]


def graficar(series: dict[str, list[float]], intervalo_s: int, salida: Path) -> None:
    n = len(next(iter(series.values())))
    x = range(n)
    ancho = 0.8 / len(series)
    colores = ["#4c78a8", "#9ecae9", "#e45756"]

    fig, (arriba, medio, abajo) = plt.subplots(
        3, 1, figsize=(13, 12), gridspec_kw={"height_ratios": [3, 3, 2]})
    for j, (nombre, valores) in enumerate(series.items()):
        desplazamiento = [i - 0.4 + ancho * (j + 0.5) for i in x]
        arriba.bar(desplazamiento, valores, ancho, label=f"{nombre} (n={sum(valores):,.0f})",
                   color=colores[j])
        medio.plot(x, porcentaje(valores), marker="o", label=nombre, color=colores[j])
        horas = porcentaje(por_hora(valores, intervalo_s))
        barras = abajo.bar([h - 0.4 + ancho * (j + 0.5) for h in range(len(horas))], horas, ancho,
                           label=nombre, color=colores[j])
        abajo.bar_label(barras, fmt="%.0f %%", fontsize=8)

    arriba.set_ylabel("Viajes por intervalo")
    arriba.set_title(f"Hora de salida de los viajes, 7:00-10:00 (intervalos de {intervalo_s // 60} min)")
    arriba.set_yscale("log")
    arriba.grid(axis="y", alpha=0.3)
    arriba.legend()

    for eje in (arriba, medio):
        eje.set_xticks(list(x), etiquetas(intervalo_s, n), rotation=45)
    medio.set_ylabel("% de los viajes de la serie")
    medio.grid(alpha=0.3)
    medio.legend()

    horas = etiquetas(3600, n * intervalo_s // 3600)
    abajo.set_xticks(range(len(horas)), [f"{h} a {int(h[:2]) + 1:02d}:00" for h in horas])
    abajo.set_ylabel("% por hora")
    abajo.set_xlabel("Hora de salida")
    abajo.set_ylim(0, 55)
    abajo.grid(axis="y", alpha=0.3)
    abajo.legend(loc="upper right")

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
            "Encuesta repartida (insumo SUMO)": para_sumo,
            "Simulación SUMO": simulada,
        },
        intervalo_s,
        args.salida,
    )

    print(f"{'intervalo':>9} {'encuesta':>10} {'insumo':>8} {'SUMO':>7}")
    for e, a, b, c in zip(etiquetas(intervalo_s, n), expandida, para_sumo, simulada):
        print(f"{e:>9} {a:>10,.0f} {b:>8,.0f} {c:>7,.0f}")
    pe, pi, ps = porcentaje(expandida), porcentaje(para_sumo), porcentaje(simulada)
    print(f"Diferencia máxima por intervalo, insumo vs. SUMO: "
          f"{max(abs(a - b) for a, b in zip(pi, ps)):.1f} puntos porcentuales")
    for nombre, serie in (("encuesta", expandida), ("insumo", para_sumo), ("SUMO", simulada)):
        print(f"% por hora {nombre:>8}: " + "  ".join(f"{v:.1f}" for v in porcentaje(por_hora(serie, intervalo_s))))
    print(f"Gráfica: {args.salida}")


if __name__ == "__main__":
    main()
