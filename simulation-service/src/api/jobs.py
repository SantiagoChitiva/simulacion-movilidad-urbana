"""
Corridas de simulación lanzadas desde la API.

SUMO es pesado (una corrida completa tarda 10-15 min), así que se ejecuta una sola a la
vez y las demás esperan en cola. El estado de cada corrida se guarda en
runs/<id>/estado.json para que el historial sobreviva a un reinicio del servicio.
"""
import json
import shutil
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any

from etl.etl import Cancelado, run_pipeline
from etl.sumo import configuration
from etl.sumo.configuration import DEFAULT_SCENARIO, ScenarioPaths
from etl.sumo.demanda import DemandaConfig

ESTADOS_FINALES = {"terminado", "error", "cancelada"}

# Franja del avance global que ocupa cada etapa, según la duración medida de corridas
# completas (~12 min: duarouter ~1,5 min, SUMO ~8 min, exportar ~2 min)
FRANJAS_ETAPA: dict[str, tuple[float, float]] = {
    "generando_demanda": (0.00, 0.02),
    "ruteando": (0.02, 0.15),
    "simulando": (0.15, 0.85),
    "exportando": (0.85, 1.00),
}

# estado.json se reescribe como mucho cada tantos segundos mientras avanza una etapa
_SEGUNDOS_ENTRE_GUARDADOS = 2.0


def avance_global(etapa: str, avance_etapa: float | None) -> float:
    ini, fin = FRANJAS_ETAPA.get(etapa, (0.0, 0.0))
    return ini + (fin - ini) * (avance_etapa or 0.0)


@dataclass
class Corrida:
    id: str
    preset: str
    conteos: dict[str, int]
    semilla: int | None
    creada: str
    actualizada: str
    # en_cola | generando_demanda | ruteando | simulando | exportando | cancelando
    # | terminado | error | cancelada
    estado: str = "en_cola"
    iniciada: str | None = None             # cuando salió de la cola
    avance: float = 0.0                     # avance global, 0-1
    avance_etapa: float | None = None       # None = la etapa no informa avance
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
        self._cancelaciones: dict[str, threading.Event] = {}
        self._ultimo_guardado: dict[str, float] = {}
        self._cargar_existentes()

    # ---------------------------------------------------------- estado

    def _archivo(self, run_id: str):
        return configuration.RUNS_DIR / run_id / "estado.json"

    def _guardar(self, corrida: Corrida) -> None:
        archivo = self._archivo(corrida.id)
        archivo.parent.mkdir(parents=True, exist_ok=True)
        archivo.write_text(json.dumps(asdict(corrida), ensure_ascii=False, indent=2), encoding="utf-8")
        self._ultimo_guardado[corrida.id] = time.monotonic()

    def _actualizar(self, run_id: str, guardar: bool = True, **cambios: Any) -> None:
        with self._lock:
            corrida = self._corridas[run_id]
            for k, v in cambios.items():
                setattr(corrida, k, v)
            corrida.actualizada = _ahora()
            if guardar:
                self._guardar(corrida)

    def _progreso(self, run_id: str, etapa: str, avance_etapa: float | None) -> None:
        corrida = self._corridas[run_id]
        cambia_etapa = corrida.estado != etapa
        reciente = time.monotonic() - self._ultimo_guardado.get(run_id, 0) < _SEGUNDOS_ENTRE_GUARDADOS
        cambios: dict[str, Any] = {"avance": avance_global(etapa, avance_etapa), "avance_etapa": avance_etapa}
        if corrida.estado != "cancelando":   # no tapar la cancelación pedida
            cambios["estado"] = etapa
        self._actualizar(run_id, guardar=cambia_etapa or not reciente, **cambios)

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

    def _borrar_archivos_pesados(self, run_id: str) -> None:
        """Deja solo estado.json en el directorio de una corrida cancelada."""
        run_dir = configuration.RUNS_DIR / run_id
        for hijo in run_dir.iterdir() if run_dir.is_dir() else []:
            if hijo.name == "estado.json":
                continue
            if hijo.is_dir():
                shutil.rmtree(hijo, ignore_errors=True)
            else:
                hijo.unlink(missing_ok=True)

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
        self._cancelaciones[run_id] = threading.Event()
        self._futuros[run_id] = self._pool.submit(self._correr, run_id, demanda, semilla)
        return corrida

    def cancelar(self, run_id: str) -> Corrida:
        """Cancela una corrida en cola o en curso. ValueError si ya terminó."""
        corrida = self._corridas[run_id]
        if corrida.estado in ESTADOS_FINALES:
            raise ValueError(f"La simulación ya está en estado '{corrida.estado}'")

        evento = self._cancelaciones.get(run_id)
        if evento is not None:
            evento.set()
        futuro = self._futuros.get(run_id)
        if futuro is not None and futuro.cancel():   # aún no empezaba
            self._borrar_archivos_pesados(run_id)
            self._actualizar(run_id, estado="cancelada")
        else:
            self._actualizar(run_id, estado="cancelando")
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
        if futuro is not None and not futuro.cancelled():
            futuro.result(timeout)

    # ---------------------------------------------------------- worker

    def _correr(self, run_id: str, demanda: DemandaConfig, semilla: int | None) -> None:
        paths = self.paths(run_id)
        cancelar = self._cancelaciones[run_id]
        try:
            if cancelar.is_set():
                raise Cancelado()
            self._actualizar(run_id, iniciada=_ahora())
            resultado = self._ejecutar(
                DEFAULT_SCENARIO,
                seed=semilla,
                demanda=demanda,
                run_id=run_id,
                exportar_puntos=False,   # el visor solo usa los trips de kepler
                on_progreso=lambda etapa, avance: self._progreso(run_id, etapa, avance),
                cancelar=cancelar,
            )
            resumen = {
                "viajes_generados": resultado.etl.trips.stats.viajes_generados,
                "viajes_por_modo": dict(resultado.etl.trips.stats.por_modo),
                "trips_kepler": resultado.kepler.stats.trips_escritos,
                **_leer_estadisticas(paths),
            }
            # el FCD pesa ~1,4 GB con la demanda completa y ya quedó convertido para kepler
            paths.fcd.unlink(missing_ok=True)
            self._actualizar(run_id, estado="terminado", avance=1.0, avance_etapa=1.0, resultado=resumen)
        except Cancelado:
            self._borrar_archivos_pesados(run_id)
            self._actualizar(run_id, estado="cancelada")
        except Exception as exc:   # la corrida falla, el servicio sigue
            self._actualizar(run_id, estado="error", error=str(exc)[-2000:])
