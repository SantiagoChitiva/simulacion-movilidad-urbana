"""
Semáforo propuesto en un cruce que hoy no lo tiene.

Para el simulador 3D comparativo: a partir de la zona recortada (zona.net.xml) se genera
una variante zona_tls.net.xml idéntica salvo en el cruce elegido, donde netconvert
instala un semáforo (`--tls.set`) con un programa de tiempos fijos calculado por él
mismo a partir de la geometría y las conexiones del cruce.

Los ids de edges, carriles y nodos no cambian entre las dos redes, así que la misma
demanda corre en ambas y los mismos actores se pueden seguir lado a lado.
"""
import shutil
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from .proceso import ejecutar, revisar_cancelacion

# Tipos de nodo de SUMO que ya están controlados por un semáforo
_TIPOS_CON_SEMAFORO = {"traffic_light", "traffic_light_unregulated", "traffic_light_right_on_red"}


class SemaforoNuevoError(RuntimeError):
    """netconvert no está disponible, el cruce no existe o ya tiene semáforo."""


@dataclass(frozen=True)
class SemaforoNuevoConfig:
    net_zona: Path             # red sin el semáforo (escenario actual)
    nodo_id: str               # junction donde se instala
    destino: Path              # zona_tls.net.xml
    tipo: str = "static"       # static | actuated (tipo de tlLogic de SUMO)
    ciclo_s: int | None = None   # duración del ciclo; None = la que calcule netconvert

    def to_args(self, executable: str) -> list[str]:
        args = [
            executable,
            "-s", str(self.net_zona),
            "--tls.set", self.nodo_id,
            "--tls.default-type", self.tipo,
            "--geometry.remove", "false",
            "-o", str(self.destino),
        ]
        if self.ciclo_s is not None:
            args += ["--tls.cycle.time", str(self.ciclo_s)]
        return args


@dataclass(frozen=True)
class SemaforoNuevoResult:
    net: Path
    tl_id: str
    fases: int
    ciclo_s: float


@dataclass
class SemaforoNuevoStats:
    conexiones_controladas: int = 0


def tipo_nodo(net: Path, nodo_id: str) -> str | None:
    """Tipo del junction `nodo_id` en la red (None si no existe)."""
    for _, elem in ET.iterparse(net, events=("end",)):
        if elem.tag == "junction" and elem.get("id") == nodo_id:
            return elem.get("type")
        if elem.tag in ("edge", "junction", "connection"):
            elem.clear()
    return None


def agregar_semaforo(
    cfg: SemaforoNuevoConfig,
    stats: SemaforoNuevoStats | None = None,
    cancelar: threading.Event | None = None,
) -> SemaforoNuevoResult:
    """Escribe cfg.destino: la red de la zona con un semáforo nuevo en cfg.nodo_id."""
    executable = shutil.which("netconvert")
    if executable is None:
        raise SemaforoNuevoError("No se encontró 'netconvert' en el PATH. ¿Está SUMO instalado?")
    if not cfg.net_zona.is_file():
        raise FileNotFoundError(f"Red de la zona no encontrada: {cfg.net_zona}")

    tipo = tipo_nodo(cfg.net_zona, cfg.nodo_id)
    if tipo is None:
        raise SemaforoNuevoError(f"El cruce '{cfg.nodo_id}' no está en la zona recortada.")
    if tipo in _TIPOS_CON_SEMAFORO:
        raise SemaforoNuevoError(f"El cruce '{cfg.nodo_id}' ya tiene semáforo.")

    revisar_cancelacion(cancelar)
    cfg.destino.parent.mkdir(parents=True, exist_ok=True)
    salida = ejecutar(cfg.to_args(executable), cancelar=cancelar)
    if salida.returncode != 0:
        raise SemaforoNuevoError(
            f"netconvert falló (código {salida.returncode}):\n{salida.stderr[-2000:]}"
        )

    fases, ciclo, controladas = _resumen_programa(cfg.destino, cfg.nodo_id)
    if fases == 0:
        raise SemaforoNuevoError(
            f"netconvert no generó un programa para '{cfg.nodo_id}' (¿el cruce no tiene conflictos?)."
        )
    if stats is not None:
        stats.conexiones_controladas = controladas
    return SemaforoNuevoResult(net=cfg.destino, tl_id=cfg.nodo_id, fases=fases, ciclo_s=ciclo)


def _resumen_programa(net: Path, tl_id: str) -> tuple[int, float, int]:
    """(número de fases, duración del ciclo, conexiones controladas) del tlLogic `tl_id`."""
    fases, ciclo, controladas = 0, 0.0, 0
    for _, elem in ET.iterparse(net, events=("end",)):
        if elem.tag == "tlLogic" and elem.get("id") == tl_id:
            for fase in elem.findall("phase"):
                fases += 1
                ciclo += float(fase.get("duration", 0))
            elem.clear()
        elif elem.tag == "connection":
            if elem.get("tl") == tl_id:
                controladas += 1
            elem.clear()
        elif elem.tag in ("edge", "junction"):
            elem.clear()
    return fases, ciclo, controladas
