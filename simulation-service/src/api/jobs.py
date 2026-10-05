"""
Corridas de simulación lanzadas desde la API.

SUMO es pesado (una corrida completa tarda 10-15 min), así que se ejecuta una sola a la
vez y las demás esperan en cola. El estado de cada corrida se guarda en
runs/<id>/estado.json para que el historial sobreviva a un reinicio del servicio.
"""
import json
import threading
import uuid
import xml.etree.ElementTree as ET
from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

from etl.etl import run_pipeline
from etl.sumo import configuration
from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths
from etl.sumo.demanda import DemandaConfig

ESTADOS_FINALES = {"terminado", "error"}


@dataclass
class Corrida:
    id: str
    preset: str
    conteos: dict[str, int]
    semilla: int | None
    creada: str
    actualizada: str
    estado: str = "en_cola"   # en_cola | generando_demanda | ruteando | simulando | exportando | terminado | error
    error: str | None = None
    resultado: dict[str, Any] | None = None


def _ahora() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def _leer_estadisticas(paths: ScenarioPaths) -> dict[str, Any]:
    """Resumen del statistic-output de SUMO (insertados, teleports, colisiones)."""
    if not paths.statistics.is_file():
        return {}
    root = ET.parse(paths.statistics).getroot()
    attrs = lambda tag: root.find(tag).attrib if root.find(tag) is not None else {}
    vehiculos, personas = attrs("vehicles"), attrs("persons")
    return {
        "vehiculos_cargados": int(vehiculos.get("loaded", 0)),
        "vehiculos_insertados": int(vehiculos.get("inserted", 0)),
        "personas_cargadas": int(personas.get("loaded", 0)),
        "teleports": int(attrs("teleports").get("total", 0)),
        "colisiones": int(attrs("safety").get("collisions", 0)),
    }


class GestorCorridas:
    def __init__(self, ejecutar: Callable[..., Any] = run_pipeline):
        self._ejecutar = ejecutar
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="sumo")
        self._lock = threading.Lock()
        self._corridas: dict[str, Corrida] = {}
        self._futuros: dict[str, Future] = {}
        self._cargar_existentes()

    # ---------------------------------------------------------- estado

    def _archivo(self, run_id: str):
        return configuration.RUNS_DIR / run_id / "estado.json"

    def _guardar(self, corrida: Corrida) -> None:
        archivo = self._archivo(corrida.id)
        archivo.parent.mkdir(parents=True, exist_ok=True)
        archivo.write_text(json.dumps(asdict(corrida), ensure_ascii=False, indent=2), encoding="utf-8")

    def _actualizar(self, run_id: str, **cambios: Any) -> None:
        with self._lock:
            corrida = self._corridas[run_id]
            for k, v in cambios.items():
                setattr(corrida, k, v)
            corrida.actualizada = _ahora()
            self._guardar(corrida)

    def _cargar_existentes(self) -> None:
        if not configuration.RUNS_DIR.is_dir():
            return
        for archivo in configuration.RUNS_DIR.glob("*/estado.json"):
            try:
                corrida = Corrida(**json.loads(archivo.read_text(encoding="utf-8")))
            except (ValueError, TypeError):
                continue
            self._corridas[corrida.id] = corrida
            if corrida.estado not in ESTADOS_FINALES:
                # el proceso que la corría ya no existe
                self._actualizar(corrida.id, estado="error", error="Interrumpida: el servicio se reinició")

    # --------------------------------------------------------- pública

    def crear(self, demanda: DemandaConfig, semilla: int | None = None) -> Corrida:
        run_id = f"{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}"
        ahora = _ahora()
        corrida = Corrida(
            id=run_id,
            preset=demanda.preset.value,
            conteos={m.value: n for m, n in demanda.conteos.items()},
            semilla=semilla,
            creada=ahora,
            actualizada=ahora,
        )
        with self._lock:
            self._corridas[run_id] = corrida
            self._guardar(corrida)
        self._futuros[run_id] = self._pool.submit(self._correr, run_id, demanda, semilla)
        return corrida

    def obtener(self, run_id: str) -> Corrida | None:
        return self._corridas.get(run_id)

    def listar(self) -> list[Corrida]:
        return sorted(self._corridas.values(), key=lambda c: c.creada, reverse=True)

    def paths(self, run_id: str) -> ScenarioPaths:
        return ScenarioPaths.from_name(DEFAULT_SCENARIO, run_id)

    def esperar(self, run_id: str, timeout: float | None = None) -> None:
        """Bloquea hasta que la corrida termine (útil en tests)."""
        futuro = self._futuros.get(run_id)
        if futuro is not None:
            futuro.result(timeout)

    # ---------------------------------------------------------- worker

    def _correr(self, run_id: str, demanda: DemandaConfig, semilla: int | None) -> None:
        paths = self.paths(run_id)
        try:
            resultado = self._ejecutar(
                DEFAULT_SCENARIO,
                seed=semilla,
                demanda=demanda,
                run_id=run_id,
                exportar_puntos=False,   # el visor solo usa los trips de kepler
                on_etapa=lambda etapa: self._actualizar(run_id, estado=etapa),
            )
            resumen = {
                "viajes_generados": resultado.etl.trips.stats.viajes_generados,
                "viajes_por_modo": dict(resultado.etl.trips.stats.por_modo),
                "trips_kepler": resultado.kepler.stats.trips_escritos,
                **_leer_estadisticas(paths),
            }
            # el FCD pesa ~1,4 GB con la demanda completa y ya quedó convertido para kepler
            paths.fcd.unlink(missing_ok=True)
            self._actualizar(run_id, estado="terminado", resultado=resumen)
        except Exception as exc:   # la corrida falla, el servicio sigue
            self._actualizar(run_id, estado="error", error=str(exc)[-2000:])
