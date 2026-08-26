"""
etl/validation.py

Modulo de Validacion (RF-014 del SRS): compara los volumenes vehiculares
simulados por SUMO en los puntos de aforo de Usaquen contra los volumenes
reales de la base de datos HMD, calculando el estadistico GEH para cada
punto de aforo, y RMSE agregado (ver docs/srs/sections/01-introduccion.typ).

Alcance de esta primera version (documentado explicitamente, no es un
supuesto oculto):

- Solo periodo AM: es el unico periodo con .rou.xml generado hasta ahora.
- Solo trafico motorizado general (AUTO, TAXI OCUPADO, ESPECIAL OCUPADO,
  MOTO, CG, CP). La simulacion SUMO actual usa un unico tipo de vehiculo
  generico (no hay .vtype.xml ni distincion de clase por viaje), asi que
  solo es comparable contra las categorias de aforo que circulan en la
  red vial general sin infraestructura dedicada. BRT/TPC_URBANO/
  TPC_INTERMUNICIPAL/TRONCAL (transporte publico con rutas/paraderos
  fijos) y BICICLETA EN CALZADA/CICLORUTA (requieren red ciclista
  modelada aparte) quedan fuera de alcance por ahora. ESCOLAR tambien
  se excluye por ambiguedad (puede operar con rutas cerradas no
  representadas en la demanda actual).
- De las 40 estaciones de aforo geocodificadas en Usaquen, solo 5
  (TP_67, TP_70, TP_73, TP_75, TP_90) miden alguna de esas categorias
  motorizadas generales -- las otras 35 estaciones son de proposito
  especifico (ciclorruta, BRT, etc.) y no tienen contraparte en esta
  simulacion. Esto se reporta explicitamente, no se oculta.

Requiere que la simulacion se haya corrido con salida edgeData
(ver "SUMO t"/detectors.add.xml + usaquen_am.sumocfg), que genera
edgeData_am.xml con el atributo `entered` = numero de vehiculos que
entraron a cada arco durante el intervalo simulado -- esa es la medida
de volumen comparable a un conteo fisico de aforo.
"""

import argparse
import csv
import math
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

CATEGORIAS_MOTORIZADAS_GENERALES = {
    "AUTO", "TAXI OCUPADO", "ESPECIAL OCUPADO", "MOTO", "CG", "CP",
}


def geh(simulado: float, real: float) -> float:
    """GEH de Geoffrey E. Havers, metrica estandar de calibracion de
    modelos de trafico (ver RF-014). GEH < 5 se considera un buen ajuste
    punto a punto; el criterio de aceptacion del SRS es GEH < 5 en al
    menos el 85% de los puntos de aforo."""
    if simulado + real == 0:
        return 0.0
    return math.sqrt(2 * (simulado - real) ** 2 / (simulado + real))


def cargar_volumenes_reales(mapeo_csv: Path, periodo: str = "AM"):
    """Agrupa el mapeo estacion->arco por punto de aforo (ID + SENTIDO),
    sumando el VOLUMEN de todas las categorias motorizadas generales
    presentes en ese punto. Devuelve dict punto_aforo -> {volumen_real, edge_id, ...}."""
    puntos = defaultdict(lambda: {"volumen_real": 0.0, "edge_id": None,
                                   "localizacion": None, "categorias": []})
    with open(mapeo_csv, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["PERIODO"] != periodo:
                continue
            if row["TIPOLOGIA"] not in CATEGORIAS_MOTORIZADAS_GENERALES:
                continue
            if not row["edge_id"]:
                continue
            punto_id = f"{row['ID']}_{row['SENTIDO']}"
            p = puntos[punto_id]
            p["volumen_real"] += float(row["VOLUMEN"])
            p["edge_id"] = row["edge_id"]
            p["localizacion"] = row["LOCALIZACIÓN"]
            p["categorias"].append(row["TIPOLOGIA"])
    return puntos


def cargar_volumenes_simulados(edgedata_xml: Path):
    """Lee el <meandata> generado por SUMO (edgeData) y devuelve
    dict edge_id -> vehiculos 'entered' durante el intervalo simulado."""
    tree = ET.parse(edgedata_xml)
    root = tree.getroot()
    volumenes = {}
    for interval in root.findall("interval"):
        for edge in interval.findall("edge"):
            eid = edge.get("id")
            entered = edge.get("entered")
            volumenes[eid] = float(entered) if entered is not None else 0.0
    return volumenes


def validar(mapeo_csv: Path, edgedata_xml: Path, salida_csv: Path, periodo: str = "AM"):
    puntos_reales = cargar_volumenes_reales(mapeo_csv, periodo=periodo)
    volumenes_sim = cargar_volumenes_simulados(edgedata_xml)

    filas = []
    sin_dato_simulado = []
    for punto_id, info in sorted(puntos_reales.items()):
        eid = info["edge_id"]
        if eid not in volumenes_sim:
            sin_dato_simulado.append(punto_id)
            vol_sim = 0.0
        else:
            vol_sim = volumenes_sim[eid]
        vol_real = info["volumen_real"]
        g = geh(vol_sim, vol_real)
        filas.append({
            "punto_aforo": punto_id,
            "volumen_simulado": round(vol_sim, 2),
            "volumen_real": round(vol_real, 2),
            "GEH": round(g, 3),
        })

    salida_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(salida_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["punto_aforo", "volumen_simulado", "volumen_real", "GEH"])
        w.writeheader()
        w.writerows(filas)

    n = len(filas)
    n_ok = sum(1 for r in filas if r["GEH"] < 5)
    pct_ok = 100 * n_ok / n if n else 0.0
    rmse = math.sqrt(sum((r["volumen_simulado"] - r["volumen_real"]) ** 2 for r in filas) / n) if n else float("nan")

    print(f"Puntos de aforo evaluados (periodo {periodo}, categorias motorizadas generales): {n}")
    if sin_dato_simulado:
        print(f"AVISO: {len(sin_dato_simulado)} punto(s) sin dato simulado (arco sin trafico en la corrida, "
              f"volumen_simulado=0): {', '.join(sin_dato_simulado)}")
    print(f"Puntos con GEH < 5: {n_ok}/{n} ({pct_ok:.1f}%) -- umbral de aceptacion del SRS (RF-014): >= 85%")
    print(f"RMSE agregado (volumen_simulado vs volumen_real): {rmse:.2f}")
    print(f"CSV de validacion escrito en: {salida_csv}")

    for r in filas:
        print(f"  {r['punto_aforo']:>12}  sim={r['volumen_simulado']:>8}  real={r['volumen_real']:>8}  GEH={r['GEH']:>6}")

    return filas, pct_ok, rmse


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mapeo", type=Path, default=Path("data/processed/mapeo_aforos_arcos.csv"))
    ap.add_argument("--edgedata", type=Path, required=True,
                     help='ruta a edgeData_am.xml generado por la corrida SUMO (carpeta "SUMO t")')
    ap.add_argument("--salida", type=Path, default=Path("data/processed/validacion_geh.csv"))
    ap.add_argument("--periodo", default="AM")
    args = ap.parse_args()
    validar(args.mapeo, args.edgedata, args.salida, periodo=args.periodo)
