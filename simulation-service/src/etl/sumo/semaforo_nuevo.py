"""
Semáforo propuesto en un cruce que hoy no lo tiene.

Para el simulador 3D comparativo: a partir de la zona recortada (zona.net.xml) se genera
una variante zona_tls.net.xml idéntica salvo en el cruce elegido, donde netconvert
instala un semáforo con un programa de tiempos fijos calculado por él mismo a partir de
la geometría y las conexiones del cruce.

Un cruce real puede ser varios nodos de SUMO (las dos calzadas de una avenida): se
marcan todos con un parche de nodos (`-n parche.nod.xml`, type="traffic_light" y el
mismo `tl`), así que quedan controlados por un único programa coordinado.

Los ids de edges, carriles y nodos no cambian entre las dos redes, así que la misma
demanda corre en ambas y los mismos actores se pueden seguir lado a lado.
"""
import shutil
import threading
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from xml.sax.saxutils import escape
from pathlib import Path

from .proceso import ejecutar, revisar_cancelacion

# Tipos de nodo de SUMO que ya están controlados por un semáforo
_TIPOS_CON_SEMAFORO = {"traffic_light", "traffic_light_unregulated", "traffic_light_right_on_red"}


class SemaforoNuevoError(RuntimeError):
    """netconvert no está disponible, el cruce no existe o ya tiene semáforo."""


@dataclass(frozen=True)
class SemaforoNuevoConfig:
    net_zona: Path             # red sin el semáforo (escenario actual)
    nodo_id: str               # junction representativo; también es el id del tlLogic
    destino: Path              # zona_tls.net.xml
    tipo: str = "static"       # static | actuated (tipo de tlLogic de SUMO)
    ciclo_s: int | None = None   # duración del ciclo; None = la que calcule netconvert
    nodos: tuple[str, ...] = ()  # todos los nodos del cruce (vacío = solo nodo_id)

    @property
    def parche(self) -> Path:
        return self.destino.with_name("semaforo_propuesto.nod.xml")

    @property
    def todos_los_nodos(self) -> tuple[str, ...]:
        return tuple(dict.fromkeys((self.nodo_id, *self.nodos)))

    def escribir_parche(self, presentes: set[str] | None = None) -> Path:
        """Nodos del cruce como semáforo con un tl común (los que no están en la zona se omiten)."""
        lineas = ["<nodes>"]
        for nodo in self.todos_los_nodos:
            if presentes is None or nodo in presentes:
                lineas.append(f'    <node id="{escape(nodo)}" type="traffic_light" tl="{escape(self.nodo_id)}"/>')
        lineas.append("</nodes>")
        self.parche.parent.mkdir(parents=True, exist_ok=True)
        self.parche.write_text("\n".join(lineas) + "\n", encoding="utf-8")
        return self.parche

    def to_args(self, executable: str) -> list[str]:
        args = [
            executable,
            "-s", str(self.net_zona),
            "-n", str(self.parche),
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


def tipos_nodos(net: Path, ids: set[str]) -> dict[str, str]:
    """Tipo de cada junction de `ids` que está en la red."""
    tipos: dict[str, str] = {}
    for _, elem in ET.iterparse(net, events=("end",)):
        if elem.tag == "junction":
            if elem.get("id") in ids:
                tipos[elem.get("id")] = elem.get("type")
            elem.clear()
        elif elem.tag in ("edge", "connection"):
            elem.clear()
    return tipos


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

    tipos = tipos_nodos(cfg.net_zona, set(cfg.todos_los_nodos))
    tipo = tipos.get(cfg.nodo_id)
    if tipo is None:
        raise SemaforoNuevoError(f"El cruce '{cfg.nodo_id}' no está en la zona recortada.")
    con_semaforo = [n for n, t in tipos.items() if t in _TIPOS_CON_SEMAFORO]
    if con_semaforo:
        raise SemaforoNuevoError(f"El cruce '{cfg.nodo_id}' ya tiene semáforo (nodos {', '.join(con_semaforo)}).")

    revisar_cancelacion(cancelar)
    cfg.destino.parent.mkdir(parents=True, exist_ok=True)
    cfg.escribir_parche(set(tipos))
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
