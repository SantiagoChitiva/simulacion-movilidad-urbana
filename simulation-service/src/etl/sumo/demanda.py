"""
Demanda parametrizable: cuántos viajes de cada modo se simulan y de qué preset salen.

Todo se deriva de la Encuesta de Movilidad (el TSV del escenario):
- El origen, el destino y la hora de cada viaje salen de la encuesta.
- Un preset es una *transferencia modal*: ciertos viajes cambian de modo y se reparten
  entre los modos destino según P(modo | duración del viaje), calculada con la misma
  encuesta (todo el día, ponderada por fexp_vj). Así no se inventan distribuciones; el
  único supuesto de cada preset es qué viajes pueden cambiar de modo (ver PRESETS).
- Los conteos por modo que pide el usuario se reparten entre los viajes de ese modo en
  proporción a su peso, con el método del mayor resto: es determinista y conserva el total.
"""
from collections import Counter, defaultdict
from collections.abc import Iterable
from dataclasses import dataclass, field, replace
from enum import Enum
from functools import lru_cache
from pathlib import Path

from .configuration import HORA_FIN, HORA_INI
from .enums.transport_mode import TransportMode as M
from .trips import TripGenerationConfig, TripGenerationStats, TripRecord, read_trips

# Rangos de duración (min): <=15, 15-30, 30-60, >60
LIMITES_DURACION = (15, 30, 60)

MOTORIZADOS = frozenset({M.AUTO, M.MOTO, M.TAXI, M.ESPECIAL, M.ESCOLAR, M.INFORMAL, M.OTRO})
PARTICULARES = frozenset({M.AUTO, M.MOTO, M.INFORMAL, M.OTRO})
ACTIVOS = frozenset({M.PEATON, M.BICI})
# Día sin carro y sin moto en Bogotá: siguen taxis, servicio especial y escolar
PERMITIDOS_DIA_SIN_CARRO = frozenset(M) - PARTICULARES


@dataclass(frozen=True)
class InfoModo:
    etiqueta: str
    categoria: str          # "vehiculo" | "bici" | "persona"
    grupo: str              # agrupación para el frontend
    nota: str | None = None


INFO_MODOS: dict[M, InfoModo] = {
    M.AUTO: InfoModo("Auto", "vehiculo", "particulares"),
    M.MOTO: InfoModo("Moto", "vehiculo", "particulares"),
    M.TAXI: InfoModo("Taxi", "vehiculo", "servicio"),
    M.ESPECIAL: InfoModo("Servicio especial", "vehiculo", "servicio"),
    M.ESCOLAR: InfoModo("Transporte escolar", "vehiculo", "servicio"),
    M.INFORMAL: InfoModo("Informal", "vehiculo", "otros"),
    M.OTRO: InfoModo("Otro", "vehiculo", "otros"),
    M.PEATON: InfoModo("Peatón", "persona", "activos"),
    M.BICI: InfoModo("Bicicleta", "bici", "activos"),
    M.TRANSPORTE_PUBLICO: InfoModo(
        "Transporte público", "persona", "publico",
        nota="Aproximado como caminata: aún no hay buses ni paraderos en la red",
    ),
}


# ---------------------------------------------------------------- presets

@dataclass(frozen=True)
class ReglaTransferencia:
    """Qué viajes cambian de modo y entre qué modos se reparten."""
    origen: frozenset[M]
    destinos: frozenset[M]
    duracion_mayor_a: float | None = None   # solo viajes con duración > este valor (min)
    duracion_hasta: float | None = None     # solo viajes con duración <= este valor (min)

    def aplica(self, trip: TripRecord) -> bool:
        if trip.mode not in self.origen:
            return False
        d = trip.duracion_min
        if self.duracion_mayor_a is not None and (d is None or d <= self.duracion_mayor_a):
            return False
        if self.duracion_hasta is not None and (d is None or d > self.duracion_hasta):
            return False
        return True


class Preset(str, Enum):
    ENCUESTA = "encuesta"
    MAS_VEHICULOS = "mas_vehiculos"
    MAS_PEATONES = "mas_peatones"
    DIA_SIN_CARRO = "dia_sin_carro"


@dataclass(frozen=True)
class InfoPreset:
    nombre: str
    descripcion: str
    regla: ReglaTransferencia | None


PRESETS: dict[Preset, InfoPreset] = {
    Preset.ENCUESTA: InfoPreset(
        "Encuesta",
        "Demanda de la Encuesta de Movilidad 2023, 07:00-10:00, sin cambios.",
        None,
    ),
    Preset.MAS_VEHICULOS: InfoPreset(
        "Más vehículos",
        "Los viajes a pie de más de 15 min pasan a modos motorizados, repartidos según "
        "cómo se hacen en la encuesta los viajes de esa duración.",
        ReglaTransferencia(frozenset({M.PEATON}), MOTORIZADOS, duracion_mayor_a=15),
    ),
    Preset.MAS_PEATONES: InfoPreset(
        "Más peatones",
        "Los viajes en auto, moto, informal u otro de hasta 30 min pasan a pie o en "
        "bicicleta, repartidos según la encuesta para esa duración.",
        ReglaTransferencia(PARTICULARES, ACTIVOS, duracion_hasta=30),
    ),
    Preset.DIA_SIN_CARRO: InfoPreset(
        "Día sin carro",
        "Sin auto, moto, informal ni otro. Sus viajes pasan a los modos permitidos "
        "(a pie, bici, transporte público, taxi, especial, escolar) según la duración.",
        ReglaTransferencia(PARTICULARES, PERMITIDOS_DIA_SIN_CARRO),
    ),
}


# ----------------------------------------------------------- utilidades

def rango_duracion(duracion_min: float | None) -> int | None:
    if duracion_min is None:
        return None
    for i, limite in enumerate(LIMITES_DURACION):
        if duracion_min <= limite:
            return i
    return len(LIMITES_DURACION)


def mayor_resto(pesos: list[float], total: int) -> list[int]:
    """Reparte `total` enteros en proporción a `pesos` conservando la suma exacta."""
    suma = sum(pesos)
    if total <= 0 or suma <= 0:
        return [0] * len(pesos)
    exactos = [total * w / suma for w in pesos]
    enteros = [int(x) for x in exactos]
    faltan = total - sum(enteros)
    # los de mayor parte decimal reciben una unidad más; sorted es estable ante empates
    orden = sorted(range(len(pesos)), key=lambda i: exactos[i] - enteros[i], reverse=True)
    for i in orden[:faltan]:
        enteros[i] += 1
    return enteros


Probabilidades = dict[int, Counter]   # rango de duración -> modo -> suma de fexp


def probabilidades_por_duracion(registros: Iterable[TripRecord]) -> Probabilidades:
    pesos: Probabilidades = defaultdict(Counter)
    for t in registros:
        r = rango_duracion(t.duracion_min)
        if r is not None:
            pesos[r][t.mode] += t.fexp
    return pesos


def _reparto(P: Probabilidades, rango: int | None, destinos: frozenset[M]) -> dict[M, float]:
    """Fracción del viaje que va a cada modo destino (suma 1)."""
    if rango is not None and rango in P:
        base = P[rango]
    else:   # sin duración: se usa la mezcla de todos los rangos
        base = sum(P.values(), Counter())
    pesos = {m: base[m] for m in destinos}
    total = sum(pesos.values())
    if total <= 0:
        return {m: 1 / len(destinos) for m in destinos}
    return {m: w / total for m, w in pesos.items()}


Pools = dict[M, list[tuple[TripRecord, float]]]


def construir_pools(
    registros: Iterable[TripRecord], regla: ReglaTransferencia | None, P: Probabilidades
) -> Pools:
    """Por modo: los viajes (ya con ese modo) y su peso = copias x fracción transferida."""
    pools: Pools = defaultdict(list)
    for t in registros:
        if regla is not None and regla.aplica(t):
            for modo, fraccion in _reparto(P, rango_duracion(t.duracion_min), regla.destinos).items():
                if fraccion > 0:
                    pools[modo].append((replace(t, mode=modo), t.copies * fraccion))
        else:
            pools[t.mode].append((t, float(t.copies)))
    return pools


# ------------------------------------------------------------- encuesta

def _leer(tsv: Path, hora_ini: int, hora_fin: int) -> tuple[TripRecord, ...]:
    # read_trips no usa output_path
    config = TripGenerationConfig(tsv, Path(), hora_ini=hora_ini, hora_fin=hora_fin)
    return tuple(read_trips(config, TripGenerationStats()))


@lru_cache(maxsize=4)
def cargar_dia(tsv: Path) -> tuple[TripRecord, ...]:
    """Todos los viajes del día: base de P(modo | duración)."""
    return _leer(tsv, 0, 24 * 3600)


@lru_cache(maxsize=4)
def cargar_ventana(tsv: Path) -> tuple[TripRecord, ...]:
    """Viajes de la ventana simulada (07:00-10:00)."""
    return _leer(tsv, HORA_INI, HORA_FIN)


# ---------------------------------------------------------------- pública

@dataclass(frozen=True)
class DemandaConfig:
    preset: Preset = Preset.ENCUESTA
    conteos: dict[M, int] = field(default_factory=dict)   # viajes a generar por modo


def conteos_preset(
    preset: Preset, ventana: Iterable[TripRecord], dia: Iterable[TripRecord]
) -> dict[M, int]:
    """Conteos por modo que produce un preset; conservan el total de la encuesta."""
    pools = construir_pools(ventana, PRESETS[preset].regla, probabilidades_por_duracion(dia))
    modos = list(M)
    pesos = [sum(w for _, w in pools.get(m, [])) for m in modos]
    return dict(zip(modos, mayor_resto(pesos, round(sum(pesos)))))


def asignar(
    ventana: Iterable[TripRecord], dia: Iterable[TripRecord], demanda: DemandaConfig
) -> list[TripRecord]:
    """Viajes con sus copias para cumplir los conteos de `demanda`."""
    ventana = list(ventana)
    P = probabilidades_por_duracion(dia)
    pools = construir_pools(ventana, PRESETS[demanda.preset].regla, P)
    base: Pools | None = None

    salida: list[TripRecord] = []
    for modo, n in demanda.conteos.items():
        if n <= 0:
            continue
        pool = pools.get(modo)
        if not pool:
            # p. ej. autos en Día sin carro: se usan los viajes en auto de la encuesta
            base = base if base is not None else construir_pools(ventana, None, P)
            pool = base.get(modo)
        if not pool:
            raise ValueError(f"La encuesta no tiene viajes en '{modo.value}' en la ventana simulada")
        copias = mayor_resto([w for _, w in pool], n)
        salida.extend(replace(t, copies=c) for (t, _), c in zip(pool, copias) if c > 0)
    return salida
