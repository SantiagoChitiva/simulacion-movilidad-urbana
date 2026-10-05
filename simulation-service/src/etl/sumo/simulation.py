import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


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


def run_simulation(config: SimulationConfig, timeout: float | None = None) -> SimulationResult:
    # Headless: 'sumo', NO 'sumo-gui' (abre ventana, inútil en un backend)

    executable = shutil.which("sumo")
    if executable is None:
        raise SimulationError(
            "No se encontró 'sumo' en el PATH. ¿Está SUMO instalado y SUMO_HOME configurado?"
        )

    if not config.sumocfg.is_file():
        raise FileNotFoundError(f"No existe el .sumocfg: {config.sumocfg}")

    try:
        result = subprocess.run(
            [executable, *config.to_args()],
            capture_output=True,
            text=True,
            timeout=timeout,
            # SUMO resuelve rutas relativas respecto al .sumocfg;
            # fijar el cwd evita sorpresas con archivos auxiliares
            cwd=config.sumocfg.parent,
        )
    except subprocess.TimeoutExpired as exc:
        raise SimulationError(f"La simulación excedió el timeout de {timeout} s") from exc

    if result.returncode != 0:
        # Con <log value=.../> en el .sumocfg, SUMO manda los mensajes al archivo
        # de log y stderr puede quedar casi vacío; por eso se lee el final del log.
        details = result.stderr.strip() or _tail(config.log_file)
        raise SimulationError(f"SUMO falló (código {result.returncode}):\n{details}")

    return SimulationResult(config.sumocfg, result.stdout, result.stderr)
