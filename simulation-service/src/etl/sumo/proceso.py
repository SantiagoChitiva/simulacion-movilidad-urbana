"""
Ejecución de herramientas de SUMO (duarouter, sumo) con avance y cancelación.

Cuando su salida va a un pipe (no a una consola), SUMO y duarouter la acumulan en un
buffer y la sueltan al terminar, así que su "step log" no sirve para medir el avance en
vivo. En su lugar:
- duarouter escribe las rutas en orden de salida: el último `depart` escrito en el
  .rou.xml dice hasta qué hora de la ventana va (ver `ultimo_depart`).
- SUMO se controla por TraCI (ver simulation.py), que da el tiempo simulado exacto.
"""
import re
import subprocess
import tempfile
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from .configuration import HORA_FIN, HORA_INI

# Recibe el avance de la etapa (0-1)
OnAvance = Callable[[float], None]

_DEPART = re.compile(rb'depart="(\d+(?:\.\d+)?)"')
_BYTES_COLA = 64 * 1024


class Cancelado(Exception):
    """El usuario canceló la corrida."""


def avance_ventana(t: float, ini: float = HORA_INI, fin: float = HORA_FIN) -> float:
    """Fracción de la ventana simulada que ya pasó, acotada a [0, 1]."""
    return min(max((t - ini) / (fin - ini), 0.0), 1.0)


def revisar_cancelacion(cancelar: threading.Event | None) -> None:
    if cancelar is not None and cancelar.is_set():
        raise Cancelado()


def ultimo_depart(path: Path) -> float | None:
    """Último `depart` escrito en un archivo de rutas (lee solo el final del archivo)."""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(f.tell() - _BYTES_COLA, 0))
            encontrados = _DEPART.findall(f.read())
    except OSError:
        return None
    return float(encontrados[-1]) if encontrados else None


@dataclass(frozen=True)
class SalidaProceso:
    returncode: int
    stdout: str
    stderr: str


def ejecutar(
    args: list[str],
    *,
    cwd: Path | None = None,
    timeout: float | None = None,
    sondear: Callable[[], float | None] | None = None,
    on_avance: OnAvance | None = None,
    cancelar: threading.Event | None = None,
    intervalo: float = 0.5,
) -> SalidaProceso:
    """Corre `args`; cada `intervalo` s consulta `sondear()` (avance 0-1) y revisa la cancelación.

    Lanza Cancelado o subprocess.TimeoutExpired; el código de salida lo revisa quien llama.
    """
    with tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as out, \
         tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as err:
        proc = subprocess.Popen(args, cwd=cwd, stdout=out, stderr=err, text=True)
        inicio = time.monotonic()
        ultimo: float | None = None
        try:
            while True:
                try:
                    proc.wait(timeout=intervalo)
                    break
                except subprocess.TimeoutExpired:
                    pass
                revisar_cancelacion(cancelar)
                if timeout is not None and time.monotonic() - inicio > timeout:
                    raise subprocess.TimeoutExpired(args, timeout)
                if sondear and on_avance:
                    avance = sondear()
                    if avance is not None and avance != ultimo:
                        ultimo = avance
                        on_avance(avance)
        except BaseException:
            proc.kill()
            proc.wait()
            raise

        out.seek(0)
        err.seek(0)
        return SalidaProceso(proc.returncode, out.read(), err.read())
