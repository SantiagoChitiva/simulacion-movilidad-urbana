import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

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


def run_duarouter(config: DuarouterConfig, timeout: float | None = None) -> DuarouterResult:
    executable = shutil.which("duarouter")
    if executable is None:
        raise DuarouterError(
            "No se encontró 'duarouter' en el PATH. ¿Está SUMO instalado y SUMO_HOME configurado?"
        )

    missing = [p for p in config.required_inputs() if not p.is_file()]
    if missing:
        raise FileNotFoundError(f"Faltan archivos de entrada: {', '.join(map(str, missing))}")

    config.output_file.parent.mkdir(parents=True, exist_ok=True)

    result = subprocess.run(
        [executable, *config.to_args()],
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    if result.returncode != 0:
        raise DuarouterError(f"duarouter falló (código {result.returncode}):\n{result.stderr}")

    return DuarouterResult(config.output_file, result.stdout, result.stderr)
