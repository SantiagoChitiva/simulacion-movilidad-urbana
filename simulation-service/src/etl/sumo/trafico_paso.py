"""
Tráfico de paso calibrado con los aforos.

La encuesta solo tiene los viajes que empiezan y terminan en Usaquén. En las avenidas eso
es una fracción pequeña del tráfico: la corrida de la encuesta lleva ~6 % de los vehículos
aforados en la hora de máxima demanda y ningún punto cumple el GEH. Falta el tráfico que
entra, sale o atraviesa la localidad (Autopista Norte, carreras 7, 9 y 19, calles 116,
134, 170 y 183), que la encuesta no captura.

Este módulo lo estima con routeSampler.py de SUMO:
1. rutas candidatas: randomTrips + duarouter sobre la red completa, con origen y destino
   casi siempre en el borde de la red (--fringe-factor), es decir, viajes de paso o que
   entran o salen de Usaquén;
2. meta por edge aforado y modo: lo que falta para llegar al aforo, aforo − volumen de la
   corrida interna (la de la encuesta), en cada hora de la ventana;
3. routeSampler elige, para cada modo, el conjunto de rutas candidatas que mejor reproduce
   esas metas.

Para que la validación no sea circular, las estaciones se separan en dos grupos fijos:
solo las de "calibracion" entran en las metas; las de "control" quedan fuera y su GEH es la
validación independiente (validacion.py reporta los dos grupos).

Supuesto: el aforo es la hora de máxima demanda de su periodo y se usa como meta en cada
hora de la ventana; en las horas fuera del pico eso sobreestima el tráfico de paso.

Resultado medido (mañana, preset encuesta, 2026-11-03): la simulación pasa de llevar el
6 % del volumen aforado a 27 % (38 % en las estaciones de calibración), pero solo 2 de 33
puntos quedan con GEH < 5. La red no alcanza a mover esos volúmenes: hay 3.790
teletransportes y ~10.000 vehículos atascados al final. Lo que falta es calibrar la capacidad
de la red (programas reales de los semáforos, carriles), no más demanda. Por eso es una
opción y las precalculadas no lo incluyen por defecto.

El resultado se versiona en scenarios/default/trafico_paso_<periodo>.rou.xml.gz y se agrega a
la demanda cuando DemandaConfig.trafico_paso está activo.

Uso: python -m etl.sumo.trafico_paso <run_id de una corrida de la encuesta con conteos>
"""
import argparse
import gzip
import json
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from .aforos import cargar_aforos, grupo_estacion
from .configuration import AFOROS_JSON, DEFAULT_SCENARIO, HORA_FIN, HORA_INI, ScenarioPaths
from .proceso import ejecutar
from .subred import encontrar_herramienta
from .validacion import BINS_HORA, MODOS_ESTACION, PERIODO_BIN_S, leer_conteos, periodo_de

# modos de paso que se generan (los de una estación de transporte privado) y su vClass
MODOS_PASO: dict[str, str] = {"auto": "passenger", "moto": "motorcycle", "taxi": "taxi", "especial": "passenger"}


class TraficoPasoError(RuntimeError):
    """randomTrips, duarouter o routeSampler terminaron con error."""


@dataclass(frozen=True)
class TraficoPasoConfig:
    run_base: str                        # corrida de la encuesta con conteos (sin tráfico de paso)
    inicio: float = HORA_INI
    fin: float = HORA_FIN
    candidatos_por_hora: int = 6000      # rutas candidatas por vClass
    semilla: int = 42
    aforos: Path = AFOROS_JSON

    @property
    def periodo(self) -> str:
        return periodo_de(self.inicio)

    @property
    def destino(self) -> Path:
        return ScenarioPaths.from_name(DEFAULT_SCENARIO).root / f"trafico_paso_{self.periodo.lower()}.rou.xml.gz"


@dataclass
class TraficoPasoStats:
    puntos_calibracion: int = 0
    puntos_control: int = 0
    meta_por_modo: dict[str, float] = field(default_factory=dict)
    vehiculos_por_modo: dict[str, int] = field(default_factory=dict)


def metas(puntos: list[dict], conteos_internos: dict, periodo: str, inicio: float, fin: float) -> dict[str, dict]:
    """modo -> {(edge, inicio_hora): vehículos que faltan}, solo con estaciones de calibración."""
    salida: dict[str, dict] = defaultdict(dict)
    for punto in puntos:
        if grupo_estacion(punto["id"]) != "calibracion":
            continue
        real = punto["volumenes"].get(periodo, {})
        modos = [m for m in MODOS_ESTACION.get(punto["id"].split("_")[0], ()) if m in MODOS_PASO]
        for modo in modos:
            serie = conteos_internos.get(modo, {}).get(punto["edge"], {})
            for hora in range(int(inicio), int(fin), 3600):
                interno = sum(serie.get(float(hora + k * PERIODO_BIN_S), 0.0) for k in range(BINS_HORA))
                falta = max(0.0, real.get(modo, 0.0) - interno)
                clave = (punto["edge"], hora)
                # dos sentidos de estaciones distintas pueden caer en el mismo edge: el mayor
                salida[modo][clave] = max(salida[modo].get(clave, 0.0), falta)
    return salida


def escribir_metas(metas_modo: dict, destino: Path) -> Path:
    """Metas en el formato edgeData que lee routeSampler (atributo entered por hora)."""
    raiz = ET.Element("data")
    por_hora: dict[int, list] = defaultdict(list)
    for (edge, hora), n in metas_modo.items():
        por_hora[hora].append((edge, n))
    for hora in sorted(por_hora):
        intervalo = ET.SubElement(raiz, "interval", id="meta", begin=str(hora), end=str(hora + 3600))
        for edge, n in sorted(por_hora[hora]):
            ET.SubElement(intervalo, "edge", id=edge, entered=f"{n:.0f}")
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    arbol.write(str(destino), encoding="UTF-8", xml_declaration=True)
    return destino


def _correr(args: list[str], que: str, cwd: Path) -> None:
    salida = ejecutar(args, cwd=cwd)
    if salida.returncode != 0:
        raise TraficoPasoError(f"{que} falló (código {salida.returncode}):\n{salida.stderr[-2000:]}")


def generar_trafico_paso(cfg: TraficoPasoConfig, stats: TraficoPasoStats | None = None) -> Path:
    stats = stats if stats is not None else TraficoPasoStats()
    base = ScenarioPaths.from_name(DEFAULT_SCENARIO, cfg.run_base)
    if not base.conteos.is_file():
        raise TraficoPasoError(f"La corrida {cfg.run_base} no tiene conteos ({base.conteos}).")
    puntos = cargar_aforos(cfg.aforos)
    stats.puntos_calibracion = sum(1 for p in puntos if grupo_estacion(p["id"]) == "calibracion")
    stats.puntos_control = len(puntos) - stats.puntos_calibracion
    objetivos = metas(puntos, leer_conteos(base.conteos), cfg.periodo, cfg.inicio, cfg.fin)

    escenario = ScenarioPaths.from_name(DEFAULT_SCENARIO)
    trabajo = escenario.root / f".trafico_paso_{cfg.periodo.lower()}"
    trabajo.mkdir(parents=True, exist_ok=True)
    random_trips = encontrar_herramienta("randomTrips.py")
    sampler = encontrar_herramienta("routeSampler.py")
    salidas = []
    duracion = cfg.fin - cfg.inicio
    for i, (modo, vclase) in enumerate(MODOS_PASO.items()):
        meta = objetivos.get(modo)
        if not meta or not sum(meta.values()):
            continue
        stats.meta_por_modo[modo] = round(sum(meta.values()))
        candidatos = trabajo / f"candidatos_{vclase}.rou.xml"
        if not candidatos.is_file():
            # rutas candidatas por vClass (auto, taxi y especial comparten las de passenger)
            n = cfg.candidatos_por_hora * duracion / 3600
            _correr([
                sys.executable, random_trips, "-n", str(escenario.net), "-r", str(candidatos),
                "-o", str(trabajo / f"candidatos_{vclase}.trips.xml"),
                "-b", "0", "-e", str(duracion), "-p", f"{duracion / n:.4f}",
                "--fringe-factor", "max", "--min-distance", "1200", "--vclass", vclase,
                "--seed", str(cfg.semilla + i), "--validate", "--prefix", f"cand_{vclase}_",
            ], f"randomTrips ({modo})", trabajo)
        objetivo = escribir_metas(meta, trabajo / f"metas_{modo}.xml")
        salida = trabajo / f"paso_{modo}.rou.xml"
        _correr([
            sys.executable, sampler, "-r", str(candidatos), "-d", str(objetivo), "-o", str(salida),
            "--prefix", f"paso_{modo}_", "-a", f'type="{modo}" departLane="best" departSpeed="max"',
            "--seed", str(cfg.semilla + i), "--min-count", "1",
        ], f"routeSampler ({modo})", trabajo)
        salidas.append(salida)

    vehiculos = []
    for salida in salidas:
        for _, elem in ET.iterparse(salida, events=("end",)):
            if elem.tag == "vehicle":
                vehiculos.append(elem)
    for v in vehiculos:
        modo = v.get("type")
        stats.vehiculos_por_modo[modo] = stats.vehiculos_por_modo.get(modo, 0) + 1
    # un solo archivo ordenado por salida (SUMO descarta lo que llega desordenado)
    vehiculos.sort(key=lambda v: float(v.get("depart", 0)))
    raiz = ET.Element("routes")
    for v in vehiculos:
        raiz.append(v)
    arbol = ET.ElementTree(raiz)
    ET.indent(arbol, space="  ")
    # comprimido (SUMO lo lee así): sin comprimir pesa ~45 MB; mtime=0 para que sea reproducible
    with cfg.destino.open("wb") as crudo, gzip.GzipFile(filename="", mode="wb", fileobj=crudo, mtime=0) as gz:
        arbol.write(gz, encoding="UTF-8", xml_declaration=True)
    (trabajo / "resumen.json").write_text(json.dumps({
        "run_base": cfg.run_base, "periodo": cfg.periodo, **stats.__dict__,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    return cfg.destino


def archivo_trafico_paso(inicio: float = HORA_INI) -> Path | None:
    """Tráfico de paso de la ventana que empieza en `inicio`, o None si no se ha generado."""
    path = ScenarioPaths.from_name(DEFAULT_SCENARIO).root / f"trafico_paso_{periodo_de(inicio).lower()}.rou.xml.gz"
    return path if path.is_file() else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("run_base", help="run_id de una corrida de la encuesta con conteos (sin tráfico de paso)")
    parser.add_argument("--inicio", type=float, default=HORA_INI)
    parser.add_argument("--fin", type=float, default=HORA_FIN)
    args = parser.parse_args()
    stats = TraficoPasoStats()
    destino = generar_trafico_paso(TraficoPasoConfig(args.run_base, args.inicio, args.fin), stats)
    print(f"{sum(stats.vehiculos_por_modo.values())} vehículos de paso {stats.vehiculos_por_modo} -> {destino}")
    print(f"metas {stats.meta_por_modo}; {stats.puntos_calibracion} puntos de calibración, {stats.puntos_control} de control")


if __name__ == "__main__":
    main()
