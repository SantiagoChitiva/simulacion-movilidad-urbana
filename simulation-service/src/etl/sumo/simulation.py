import shutil
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

from .proceso import Cancelado, OnAvance, avance_ventana, ejecutar, revisar_cancelacion

# Con TraCI la simulación avanza en saltos de este tamaño (s simulados): pocos llamados
# por corrida, así que el costo de TraCI es despreciable
_SALTO_TRACI = 60


class SimulationError(RuntimeError):
    """SUMO no está disponible o la simulación terminó con error."""


@dataclass(frozen=True)
class SimulationConfig:
    sumocfg: Path
    log_file: Path | None = None   # para mostrar el final del log si falla
    seed: int | None = None        # sobreescribe el seed del .sumocfg
    begin: int | None = None       # segundos; sobreescribe <time><begin>
    end: int | None = None         # segundos; sobreescribe <time><end>

    def to_args(self) -> list[str]:
        args = ["-c", str(self.sumocfg), "--no-step-log", "true"]

        if self.seed is not None: args += ["--seed", str(self.seed)]
        if self.begin is not None: args += ["--begin", str(self.begin)]
        if self.end is not None: args += ["--end", str(self.end)]

        return args

    def ventana(self) -> tuple[float, float]:
        """Inicio y fin de la simulación: los del config o los del .sumocfg."""
        tiempo = {e.tag: float(e.get("value")) for e in ET.parse(self.sumocfg).getroot().iter()
                  if e.tag in ("begin", "end")}
        ini = self.begin if self.begin is not None else tiempo.get("begin", 0.0)
        fin = self.end if self.end is not None else tiempo.get("end")
        if fin is None:
            raise SimulationError("El .sumocfg no define <end>: no se puede medir el avance")
        return ini, fin


@dataclass(frozen=True)
class SimulationResult:
    sumocfg: Path
    stdout: str
    stderr: str


def _tail(path: Path | None, lines: int = 20) -> str:
    if path is None or not path.is_file():
        return ""
    content = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(content[-lines:])


def _error(config: SimulationConfig, returncode: int, stderr: str) -> SimulationError:
    # Con <log value=.../> en el .sumocfg, SUMO manda los mensajes al archivo
    # de log y stderr puede quedar casi vacío; por eso se lee el final del log.
    details = stderr.strip()[-3000:] or _tail(config.log_file)
    return SimulationError(f"SUMO falló (código {returncode}):\n{details}")


def run_simulation(
    config: SimulationConfig,
    timeout: float | None = None,
    on_avance: OnAvance | None = None,
    cancelar: threading.Event | None = None,
) -> SimulationResult:
    # Headless: 'sumo', NO 'sumo-gui' (abre ventana, inútil en un backend)

    executable = shutil.which("sumo")
    if executable is None:
        raise SimulationError(
            "No se encontró 'sumo' en el PATH. ¿Está SUMO instalado y SUMO_HOME configurado?"
        )

    if not config.sumocfg.is_file():
        raise FileNotFoundError(f"No existe el .sumocfg: {config.sumocfg}")

    if on_avance is not None or cancelar is not None:
        return _run_traci(executable, config, timeout, on_avance, cancelar)

    try:
        result = ejecutar(
            [executable, *config.to_args()],
            timeout=timeout,
            # SUMO resuelve rutas relativas respecto al .sumocfg;
            # fijar el cwd evita sorpresas con archivos auxiliares
            cwd=config.sumocfg.parent,
        )
    except subprocess.TimeoutExpired as exc:
        raise SimulationError(f"La simulación excedió el timeout de {timeout} s") from exc

    if result.returncode != 0:
        raise _error(config, result.returncode, result.stderr)

    return SimulationResult(config.sumocfg, result.stdout, result.stderr)


def _run_traci(
    executable: str,
    config: SimulationConfig,
    timeout: float | None,
    on_avance: OnAvance | None,
    cancelar: threading.Event | None,
) -> SimulationResult:
    """Corre SUMO controlado por TraCI para conocer el tiempo simulado y poder cancelar.

    La simulación y sus archivos de salida son los mismos que sin TraCI: solo cambia
    quién decide cuándo avanzar.
    """
    import traci   # de SUMO_HOME/tools o del paquete `traci`
    from sumolib.miscutils import getFreeSocketPort

    ini, fin = config.ventana()
    puerto = getFreeSocketPort()
    inicio = time.monotonic()

    with tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as out, \
         tempfile.TemporaryFile("w+", encoding="utf-8", errors="replace") as err:
        proc = subprocess.Popen(
            [executable, *config.to_args(), "--remote-port", str(puerto)],
            cwd=config.sumocfg.parent, stdout=out, stderr=err, text=True,
        )
        conexion = None
        try:
            conexion = traci.connect(puerto, numRetries=120, proc=proc, label=f"sumo-{puerto}")
            t = conexion.simulation.getTime()
            while t < fin:
                revisar_cancelacion(cancelar)
                if timeout is not None and time.monotonic() - inicio > timeout:
                    raise SimulationError(f"La simulación excedió el timeout de {timeout} s")
                try:
                    conexion.simulationStep(min(t + _SALTO_TRACI, fin))
                except traci.exceptions.FatalTraCIError:
                    break   # SUMO terminó por su cuenta (p. ej. llegó a <end>)
                t = conexion.simulation.getTime()
                if on_avance is not None:
                    on_avance(avance_ventana(t, ini, fin))
            conexion.close()   # SUMO cierra y escribe sus salidas
            conexion = None
            proc.wait()
        except (Cancelado, SimulationError, KeyboardInterrupt):
            proc.kill()
            proc.wait()
            raise
        except (traci.exceptions.TraCIException, traci.exceptions.FatalTraCIError) as exc:
            # p. ej. SUMO murió al cargar la red y TraCI no pudo conectarse
            proc.kill()
            proc.wait()
            err.seek(0)
            raise _error(config, proc.returncode, err.read() or str(exc)) from exc
        finally:
            if conexion is not None:
                try:
                    conexion.close(False)
                except Exception:
                    pass

        out.seek(0)
        err.seek(0)
        stdout, stderr = out.read(), err.read()
        if proc.returncode != 0:
            raise _error(config, proc.returncode, stderr)
        return SimulationResult(config.sumocfg, stdout, stderr)
