import shutil
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path

from .proceso import OnAvance, avance_ventana, ejecutar, ultimo_depart

class DuarouterError(RuntimeError):
    """duarouter no está disponible o terminó con error."""

@dataclass(frozen=True)
class DuarouterConfig:
    net_file: Path
    trips_file: Path
    taz_file: Path
    output_file: Path
    threads: int = 4
    ignore_errors: bool = True
    repair: bool = True

    def required_inputs(self) -> list[Path]:
        return [self.net_file, self.trips_file, self.taz_file]

    def to_args(self) -> list[str]:
        args = [
            "-n", str(self.net_file),
            "--route-files", str(self.trips_file),
            "--additional-files", str(self.taz_file),
            "-o", str(self.output_file),
            "--routing-threads", str(self.threads),
        ]
        if self.ignore_errors:
            args.append("--ignore-errors")
        if self.repair:
            args.append("--repair")
        return args


@dataclass(frozen=True)
class DuarouterResult:
    output_file: Path
    stdout: str
    stderr: str   # aquí salen los warnings de rutas no encontradas


def run_duarouter(
    config: DuarouterConfig,
    timeout: float | None = None,
    on_avance: OnAvance | None = None,
    cancelar: threading.Event | None = None,
) -> DuarouterResult:
    executable = shutil.which("duarouter")
    if executable is None:
        raise DuarouterError(
            "No se encontró 'duarouter' en el PATH. ¿Está SUMO instalado y SUMO_HOME configurado?"
        )

    missing = [p for p in config.required_inputs() if not p.is_file()]
    if missing:
        raise FileNotFoundError(f"Faltan archivos de entrada: {', '.join(map(str, missing))}")

    config.output_file.parent.mkdir(parents=True, exist_ok=True)

    config.output_file.unlink(missing_ok=True)   # que el sondeo no lea una corrida anterior

    def sondear() -> float | None:
        # duarouter escribe las rutas en orden de salida: el último depart marca el avance
        t = ultimo_depart(config.output_file)
        return None if t is None else avance_ventana(t)

    result = ejecutar(
        [executable, *config.to_args()],
        timeout=timeout,
        sondear=sondear,
        on_avance=on_avance,
        cancelar=cancelar,
    )

    if result.returncode != 0:
        raise DuarouterError(f"duarouter falló (código {result.returncode}):\n{result.stderr}")

    return DuarouterResult(config.output_file, result.stdout, result.stderr)
