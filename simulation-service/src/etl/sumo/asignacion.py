"""
Asignación iterativa de rutas (equilibrio dinámico de usuario) con duaIterate.py de SUMO.

duarouter en una sola pasada asigna a cada viaje la ruta más corta con la red vacía: todos
eligen las mismas avenidas aunque se congestionen. duaIterate alterna simulación y
ruteo: tras cada simulación recalcula los tiempos por edge y reparte los viajes entre
rutas alternativas (modelo de Gawron), hasta acercarse al equilibrio de Wardrop, en el
que ningún conductor ganaría cambiando de ruta.

Las iteraciones se simulan con el modelo mesoscópico (colas por edge), que es mucho más
rápido; la corrida final usa el microscópico con las rutas de la última iteración. Aun así
multiplica el tiempo de ruteo, así que es una opción (DemandaConfig.asignacion_iterativa).
"""
import shutil
import sys
import threading
from dataclasses import dataclass
from pathlib import Path

from .configuration import HORA_FIN, HORA_INI
from .duarouter import DuarouterResult
from .proceso import OnAvance, ejecutar
from .subred import encontrar_herramienta

ITERACIONES = 5


class AsignacionError(RuntimeError):
    """duaIterate.py terminó con error o no dejó rutas."""


@dataclass(frozen=True)
class AsignacionConfig:
    net_file: Path
    trips_file: Path
    taz_file: Path
    output_file: Path
    iteraciones: int = ITERACIONES
    ventana: tuple[int, int] = (HORA_INI, HORA_FIN)
    mesosim: bool = True

    @property
    def trabajo(self) -> Path:
        return self.output_file.parent / "asignacion"

    def to_args(self, script: str) -> list[str]:
        args = [
            sys.executable, script,
            "-n", str(self.net_file.resolve()),
            "-t", str(self.trips_file.resolve()),
            "-+", str(self.taz_file.resolve()),
            "-b", str(self.ventana[0]),
            "-e", str(self.ventana[1]),
            "-l", str(self.iteraciones),
            "--disable-summary", "--disable-tripinfos", "--clean-alt",
        ]
        if self.mesosim:
            args.append("--mesosim")
        # las opciones sumo--* van al final (así las lee duaIterate)
        return args + ["sumo--ignore-route-errors", "true", "duarouter--ignore-errors", "true",
                       "duarouter--repair", "true", "duarouter--routing-threads", "4"]


def rutas_ultima_iteracion(trabajo: Path, trips: Path, iteraciones: int) -> Path | None:
    """Rutas (no las alternativas) que dejó la última iteración de duaIterate."""
    ultima = trabajo / f"{iteraciones - 1:03d}"
    candidatos = sorted(p for p in ultima.glob(f"{trips.stem.removesuffix('.trips')}*.rou.xml") if ".alt." not in p.name)
    return candidatos[-1] if candidatos else None


def run_asignacion(
    config: AsignacionConfig,
    on_avance: OnAvance | None = None,
    cancelar: threading.Event | None = None,
) -> DuarouterResult:
    script = encontrar_herramienta("assign/duaIterate.py")
    shutil.rmtree(config.trabajo, ignore_errors=True)
    config.trabajo.mkdir(parents=True)

    def sondear() -> float:
        # una carpeta 000, 001, ... por iteración empezada
        hechas = sum(1 for p in config.trabajo.iterdir() if p.is_dir() and p.name.isdigit())
        return max(0, hechas - 1) / config.iteraciones

    salida = ejecutar(config.to_args(script), cwd=config.trabajo, sondear=sondear, on_avance=on_avance, cancelar=cancelar)
    rutas = rutas_ultima_iteracion(config.trabajo, config.trips_file, config.iteraciones)
    if salida.returncode != 0 or rutas is None:
        raise AsignacionError(f"duaIterate.py falló (código {salida.returncode}):\n{salida.stderr[-2000:]}")
    shutil.copyfile(rutas, config.output_file)
    # las iteraciones intermedias (rutas, alternativas, dumps) pesan cientos de MB
    shutil.rmtree(config.trabajo, ignore_errors=True)
    return DuarouterResult(output_file=config.output_file, stdout=salida.stdout[-4000:], stderr=salida.stderr[-4000:])
