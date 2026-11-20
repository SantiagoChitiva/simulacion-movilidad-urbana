"""
Estudio de semillas: ¿conviene el semáforo propuesto en los cruces priorizados?

El simulador 3D compara un cruce sin y con semáforo con una sola semilla, así que sus
indicadores son ilustrativos. Este estudio repite esa comparación muchas veces por cruce,
sin interfaz, y resume en qué proporción de las repeticiones el semáforo mejora cada
métrica y con qué intervalo de confianza.

Por cruce (los de nivel prioritario y recomendado de la priorización):
1. Se prepara la zona una vez, como el simulador 3D (`etl.run_escenario_semaforo`): la red
   tal cual (A), la misma con el semáforo propuesto y su programa de Webster (B), y los
   viajes reales recortados de una corrida de la encuesta.
2. En cada semilla cambia lo que la encuesta no fija: el instante exacto de salida de cada
   viaje real (±5 min, `demanda_zona.variar_salidas`) y el tráfico de fondo sintético
   (randomTrips con otra semilla). A y B reciben exactamente la misma demanda.
3. Una hora de SUMO por lado (`comparacion_programas.correr_programa`) con demoras, colas,
   espera de peatones y conflictos graves a menos de 60 m del cruce (dispositivo SSM),
   separados en conflictos de cruce (trayectorias que se cruzan o convergen: los que un
   semáforo busca evitar) y de alcance (uno detrás del otro: aumentan con las colas).

El veredicto se toma con los conflictos de cruce y se reporta su costo: más demora o más
conflictos en total (ver `veredicto`).

Uso (desde simulation-service/, después de una corrida de la encuesta que conserve rutas):
    python -m etl.sumo.estudio_semillas --origen <run_id> [--semillas 30] [--procesos 3]
        [--niveles prioritario recomendado] [--limite N]
Se puede interrumpir y volver a lanzar: retoma las semillas que faltan. El resumen queda
en `estudios/semillas/` (versionado) y el detalle por semilla en `runs/estudio-semillas/`.
"""
import argparse
import csv
import json
import shutil
import statistics
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

from .comparacion_programas import ComparacionProgramaConfig, correr_programa
from .configuration import CACHE_DIR, DEFAULT_SCENARIO, PRECALCULADAS_DIR, RUNS_DIR, ScenarioPaths
from .demanda_zona import DemandaZonaConfig, generar_demanda_zona, variar_salidas
from .semaforo_nuevo import accesos_semaforo

TRABAJO_DIR = RUNS_DIR / "estudio-semillas"
RESULTADOS_DIR = PRECALCULADAS_DIR.parent / "estudios" / "semillas"
DURACION_S = 3600
# más demora que esto (s por vehículo) se reporta como costo del semáforo: del orden de un
# nivel de servicio en las bandas de demora del HCM para cruces semaforizados
COSTO_DEMORA_S = 10.0
METRICAS = (
    "vehiculos", "demora_media_s", "espera_media_s", "cola_max_veh", "detenciones",
    "peatones", "demora_peaton_s", "teleports",
    "conflictos", "conflictos_cruce", "conflictos_alcance", "conflictos_ttc", "conflictos_drac", "conflictos_pet",
)
# métricas donde menos es mejor (las que se resumen)
COMPARADAS = (
    "demora_media_s", "espera_media_s", "cola_max_veh", "demora_peaton_s",
    "conflictos", "conflictos_cruce", "conflictos_alcance", "conflictos_ttc", "conflictos_pet", "teleports",
)
COLUMNAS = ("nodo_id", "nivel", "calles", "semilla", "lado", *METRICAS)
# t de Student al 95 % (dos colas) por grados de libertad; desde 30, la normal
_T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262,
        10: 2.228, 12: 2.179, 15: 2.131, 20: 2.086, 25: 2.060, 29: 2.045}


def t95(gl: int) -> float:
    """t crítico al 95 % (el de la fila tabulada más cercana por debajo, conservador)."""
    if gl >= 30:
        return 1.96
    return _T95[max(k for k in _T95 if k <= max(gl, 1))]


def diferencia_pareada(sin: list[float], con: list[float]) -> dict:
    """Con menos sin, semilla a semilla: media, IC 95 % y cuántas veces mejora (con < sin)."""
    difs = [c - s for s, c in zip(sin, con)]
    n = len(difs)
    if n == 0:
        return {"n": 0}
    media = statistics.fmean(difs)
    margen = t95(n - 1) * statistics.stdev(difs) / n ** 0.5 if n > 1 else float("inf")
    return {
        "n": n,
        "sin": round(statistics.fmean(sin), 2),
        "con": round(statistics.fmean(con), 2),
        "diferencia": round(media, 2),
        "ic95": [round(media - margen, 2), round(media + margen, 2)],
        "mejora_en": sum(1 for d in difs if d < 0),
        "empeora_en": sum(1 for d in difs if d > 0),
    }


def veredicto(resumen: dict) -> str:
    """Conclusión del cruce: seguridad con los conflictos de cruce, costo con la demora y el total.

    - conviene: reduce los conflictos de cruce (IC 95 % por debajo de 0), el total de
      conflictos no sube y la demora sube a lo sumo COSTO_DEMORA_S por vehículo;
    - conviene_con_costo: reduce los de cruce, pero sube el total (más alcances por las
      colas) o la demora sube más que eso;
    - no_conviene: no reduce los de cruce y sube el total de conflictos;
    - no_se_justifica: no reduce los de cruce y sube la demora;
    - indiferente: lo demás.
    """
    cruce, total = resumen.get("conflictos_cruce", {}), resumen.get("conflictos", {})
    demora = resumen.get("demora_media_s", {})
    if not cruce.get("n") or not total.get("n") or not demora.get("n"):
        return "sin_datos"
    sube_total = total["ic95"][0] > 0
    if cruce["ic95"][1] < 0:
        return "conviene" if not sube_total and demora["diferencia"] <= COSTO_DEMORA_S else "conviene_con_costo"
    if sube_total:
        return "no_conviene"
    if demora["ic95"][0] > 0:
        return "no_se_justifica"
    return "indiferente"


TEXTO_VEREDICTO = {
    "conviene": "Conviene: reduce los conflictos de cruce sin aumentar el total ni mucho la demora.",
    "conviene_con_costo": "Reduce los conflictos de cruce, pero aumenta el total de conflictos o más de 10 s la demora.",
    "no_conviene": "No conviene: no reduce los conflictos de cruce y aumenta el total.",
    "no_se_justifica": "No se justifica: no reduce los conflictos de cruce y aumenta la demora.",
    "indiferente": "Indiferente: no hay diferencias claras.",
    "sin_datos": "Sin datos suficientes.",
}


def resumir_cruce(filas: list[dict]) -> dict:
    """Diferencias pareadas por métrica y veredicto, con las filas (semilla, lado) de un cruce."""
    por_lado: dict[str, dict[int, dict]] = {"sin": {}, "con": {}}
    for f in filas:
        por_lado[f["lado"]][int(f["semilla"])] = f
    semillas = sorted(set(por_lado["sin"]) & set(por_lado["con"]))
    resumen = {}
    for m in COMPARADAS:
        pares = [(por_lado["sin"][k].get(m), por_lado["con"][k].get(m)) for k in semillas]
        pares = [(float(s), float(c)) for s, c in pares if s not in (None, "") and c not in (None, "")]
        resumen[m] = diferencia_pareada([s for s, _ in pares], [c for _, c in pares])
    resumen["veredicto"] = veredicto(resumen)
    return resumen


def leer_filas(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


class _Registro:
    """CSV de filas compartido por los hilos (una fila por semilla y lado)."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.is_file():
            with path.open("w", newline="", encoding="utf-8") as f:
                csv.DictWriter(f, COLUMNAS).writeheader()

    def agregar(self, filas: list[dict]) -> None:
        with self._lock, self.path.open("a", newline="", encoding="utf-8") as f:
            escritor = csv.DictWriter(f, COLUMNAS, extrasaction="ignore")
            escritor.writerows(filas)


def preparar_cruce(cruce, origen: str, cruce_dir: Path) -> dict:
    """Zona A/B y viajes reales del cruce (una vez; si ya está preparada, se reutiliza)."""
    from ..etl import run_escenario_semaforo   # import tardío: etl.etl importa este paquete

    info_path = cruce_dir / "zona.json"
    if info_path.is_file():
        return json.loads(info_path.read_text(encoding="utf-8"))
    run_id = f"{TRABAJO_DIR.name}/{cruce_dir.name}"
    try:
        info = run_escenario_semaforo(cruce.nodo_id, cruce.lon, cruce.lat, run_id, run_id_origen=origen,
                                      nodos=cruce.nodos, programa="webster")
    except Exception as exc:   # Webster necesita volúmenes en los accesos: si falla, programa de netconvert
        print(f"  {cruce.nodo_id}: sin Webster ({exc.__class__.__name__}); se usa el programa de netconvert", flush=True)
        info = run_escenario_semaforo(cruce.nodo_id, cruce.lon, cruce.lat, run_id, run_id_origen=origen,
                                      nodos=cruce.nodos, programa="netconvert")
    enlaces, _ = accesos_semaforo(Path(info["zona_tls_net"]), info["tl_id"])
    info["accesos"] = sorted(enlaces)
    reales = [p for p in info["demanda"] if Path(p).name == "zona.rou.xml"]
    info["rutas_reales"] = reales[0] if reales else None
    info_path.write_text(json.dumps(info, ensure_ascii=False, indent=1), encoding="utf-8")
    return info


def correr_semilla(info: dict, semilla: int, cruce_dir: Path) -> dict[str, dict]:
    """La misma demanda (variada con `semilla`) en A y en B; devuelve las métricas por lado."""
    sem_dir = cruce_dir / f"semilla_{semilla}"
    inicio = info["inicio"]
    reales = None
    if info.get("rutas_reales"):
        reales = variar_salidas(Path(info["rutas_reales"]), sem_dir / "zona.rou.xml", semilla,
                                inicio=inicio, fin=inicio + DURACION_S)
    demanda = generar_demanda_zona(
        DemandaZonaConfig(zona_net=Path(info["zona_net"]), destino_dir=sem_dir, inicio=inicio,
                          semilla=100 + 10 * semilla),
        reales,
    )
    metricas = {}
    for lado, net, extra in (
        ("sin", info["zona_net"], ()),
        ("con", info["zona_tls_net"], tuple(Path(p) for p in info.get("programa_adicional") or ())),
    ):
        resultado = correr_programa(ComparacionProgramaConfig(
            zona_net=Path(net), demanda=demanda.archivos, vtypes=demanda.vtypes, accesos=info["accesos"],
            destino_dir=sem_dir / lado, semilla=semilla, inicio=inicio, adicionales=extra,
            ssm=True, nodos=tuple(info["nodos"]),
        ))
        metricas[lado] = resultado.metricas
    shutil.rmtree(sem_dir, ignore_errors=True)   # salidas de SUMO: lo que importa ya está en el CSV
    return metricas


def estudiar_cruce(cruce, origen: str, semillas: int, registro: _Registro, hechas: set) -> str:
    cruce_dir = TRABAJO_DIR / cruce.nodo_id
    t = time.monotonic()
    info = preparar_cruce(cruce, origen, cruce_dir)
    nuevas = 0
    for k in range(1, semillas + 1):
        if (cruce.nodo_id, k) in hechas:
            continue
        metricas = correr_semilla(info, k, cruce_dir)
        base = {"nodo_id": cruce.nodo_id, "nivel": cruce.nivel, "calles": " × ".join(cruce.calles), "semilla": k}
        registro.agregar([{**base, "lado": lado, **m} for lado, m in metricas.items()])
        nuevas += 1
    return f"{cruce.nodo_id} ({' × '.join(cruce.calles)}): {nuevas} semillas en {time.monotonic() - t:.0f} s"


def cruces_a_estudiar(niveles: list[str], limite: int | None):
    from .priorizacion import analisis_con_cache, puntuar

    paths = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    analisis = analisis_con_cache(paths.net, paths.nombres_vias, CACHE_DIR / "priorizacion.json")
    cruces, _ = puntuar(analisis, None)
    orden = {nivel: i for i, nivel in enumerate(niveles)}
    elegidos = sorted((c for c in cruces if c.nivel in orden), key=lambda c: (orden[c.nivel], -c.puntaje_total))
    return elegidos[:limite] if limite else elegidos


def escribir_resumen(filas: list[dict], cruces, semillas: int, origen: str, destino: Path) -> dict:
    """Resumen por cruce y conteo de veredictos; JSON y CSV en `destino`."""
    por_cruce: dict[str, list[dict]] = {}
    for f in filas:
        por_cruce.setdefault(f["nodo_id"], []).append(f)
    info_cruce = {c.nodo_id: c for c in cruces}
    resultados = []
    for nodo_id, filas_cruce in por_cruce.items():
        c = info_cruce.get(nodo_id)
        resumen = resumir_cruce(filas_cruce)
        resultados.append({
            "nodo_id": nodo_id,
            "nivel": filas_cruce[0]["nivel"],
            "calles": filas_cruce[0]["calles"],
            "lon": c.lon if c else None,
            "lat": c.lat if c else None,
            "veredicto": resumen.pop("veredicto"),
            "metricas": resumen,
        })
    resultados.sort(key=lambda r: (r["nivel"] != "prioritario", r["veredicto"], r["nodo_id"]))
    conteo: dict[str, int] = {}
    for r in resultados:
        conteo[r["veredicto"]] = conteo.get(r["veredicto"], 0) + 1
    salida = {
        "generado": datetime.now().astimezone().isoformat(timespec="seconds"),
        "corrida_origen": origen,
        "semillas_por_cruce": semillas,
        "cruces": len(resultados),
        "criterio": {
            "conflicto": "TTC < 1,5 s, DRAC > 3,35 m/s² o PET < 1,5 s, a menos de 60 m del cruce",
            "clases": "cruce: trayectorias que se cruzan o convergen; alcance: uno detrás del otro",
            "costo_demora_s": COSTO_DEMORA_S,
            "veredictos": TEXTO_VEREDICTO,
        },
        "veredictos": conteo,
        "resultados": resultados,
    }
    destino.mkdir(parents=True, exist_ok=True)
    (destino / "resumen.json").write_text(json.dumps(salida, ensure_ascii=False, indent=1), encoding="utf-8")
    with (destino / "resumen.csv").open("w", newline="", encoding="utf-8") as f:
        escritor = csv.writer(f)
        escritor.writerow(["nodo_id", "nivel", "calles", "veredicto", "semillas",
                           "conflictos_sin", "conflictos_con", "conflictos_dif", "conflictos_ic95",
                           "conflictos_mejora_en", "cruce_sin", "cruce_con", "cruce_ic95", "cruce_mejora_en",
                           "alcance_sin", "alcance_con", "demora_sin_s", "demora_con_s", "demora_dif_s", "demora_ic95",
                           "demora_peaton_dif_s"])
        for r in resultados:
            m = r["metricas"]
            conf, dem, pea = m["conflictos"], m["demora_media_s"], m["demora_peaton_s"]
            cru, alc = m["conflictos_cruce"], m["conflictos_alcance"]
            escritor.writerow([r["nodo_id"], r["nivel"], r["calles"], r["veredicto"], conf.get("n"),
                               conf.get("sin"), conf.get("con"), conf.get("diferencia"), conf.get("ic95"),
                               conf.get("mejora_en"), cru.get("sin"), cru.get("con"), cru.get("ic95"),
                               cru.get("mejora_en"), alc.get("sin"), alc.get("con"), dem.get("sin"), dem.get("con"), dem.get("diferencia"),
                               dem.get("ic95"), pea.get("diferencia")])
    return salida


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[1])
    parser.add_argument("--origen", required=True, help="corrida de la encuesta con rutas (runs/<id>)")
    parser.add_argument("--semillas", type=int, default=30)
    parser.add_argument("--procesos", type=int, default=3, help="cruces que se simulan a la vez")
    parser.add_argument("--niveles", nargs="+", default=["prioritario", "recomendado"])
    parser.add_argument("--limite", type=int, default=None, help="solo los primeros N cruces")
    parser.add_argument("--solo-resumen", action="store_true", help="no simula: rehace el resumen con lo que hay")
    args = parser.parse_args(argv)

    cruces = cruces_a_estudiar(args.niveles, args.limite)
    registro = _Registro(TRABAJO_DIR / "filas.csv")
    hechas = {}
    for f in leer_filas(registro.path):
        hechas.setdefault((f["nodo_id"], int(f["semilla"])), set()).add(f["lado"])
    hechas = {k for k, lados in hechas.items() if lados == {"sin", "con"}}
    print(f"{len(cruces)} cruces × {args.semillas} semillas; ya hechas: {len(hechas)}", flush=True)

    if not args.solo_resumen:
        t = time.monotonic()
        with ThreadPoolExecutor(max_workers=max(1, args.procesos)) as pool:
            futuros = {pool.submit(estudiar_cruce, c, args.origen, args.semillas, registro, hechas): c for c in cruces}
            for i, futuro in enumerate(as_completed(futuros), 1):
                c = futuros[futuro]
                try:
                    print(f"[{i}/{len(cruces)}] {futuro.result()}  ({(time.monotonic() - t) / 60:.0f} min)", flush=True)
                except Exception as exc:   # un cruce que falla no detiene el estudio
                    print(f"[{i}/{len(cruces)}] {c.nodo_id}: ERROR {exc.__class__.__name__}: {str(exc)[:300]}", flush=True)
                # el resumen se rehace con cada cruce terminado: si el estudio se corta, ya hay resultados
                _resumir(cruces, registro, args)

    salida = _resumir(cruces, registro, args)
    print("veredictos:", salida["veredictos"], flush=True)


def _resumir(cruces, registro: _Registro, args) -> dict:
    nodos = {c.nodo_id for c in cruces}
    filas = [f for f in leer_filas(registro.path) if f["nodo_id"] in nodos]
    return escribir_resumen(filas, cruces, args.semillas, args.origen, RESULTADOS_DIR)


if __name__ == "__main__":
    main()
