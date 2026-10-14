"""
Indicadores de seguridad y comportamiento del actor seguido en el simulador 3D.

Funciones puras (sin TraCI) para poder probarlas: reciben lo que TraCI reporta de un
vehículo o peatón y devuelven el riesgo y la acción que está tomando.

Medidas sustitutas de seguridad (SSM) que se usan:
- TTC (time to collision): segundos hasta alcanzar al líder si nadie cambia de velocidad.
- DRAC (deceleration rate to avoid collision): frenado necesario para no alcanzarlo (m/s²).
- PET aproximado en el cruce: diferencia entre los tiempos de llegada del actor y de un
  vehículo en conflicto al punto de cruce (getJunctionFoes de TraCI).
Umbrales usuales en la literatura: TTC < 1,5 s es un conflicto serio, DRAC > 3,35 m/s²
exige un frenado fuerte y PET < 1,5 s es un cruce peligroso.
"""
import math
from dataclasses import dataclass

TTC_CRITICO = 1.5       # s
TTC_SEGURO = 6.0        # s: por encima no aporta riesgo
DRAC_CRITICO = 3.35     # m/s²
PET_CRITICO = 1.5       # s
PET_SEGURO = 5.0        # s

# Dirección de una conexión de SUMO -> etiqueta
DIRECCIONES = {
    "s": "recto", "l": "izquierda", "r": "derecha", "t": "retorno",
    "L": "izquierda leve", "R": "derecha leve", "invalid": "sin salida",
}

# Estado de una conexión (luz o regla de prioridad) -> etiqueta
ESTADOS_ENLACE = {
    "G": "verde con prioridad", "g": "verde sin prioridad (cede)", "y": "amarillo",
    "Y": "amarillo", "r": "rojo", "R": "rojo", "u": "rojo-amarillo", "o": "semáforo apagado",
    "O": "semáforo apagado (prioridad)", "M": "vía principal", "m": "vía secundaria (cede)",
    "=": "todos ceden", "s": "pare", "w": "zona peatonal", "Z": "zipper",
}


def ttc(gap: float | None, v: float, v_lider: float) -> float | None:
    """Tiempo a la colisión con el líder; None si no hay líder o no se le acerca."""
    if gap is None or v <= v_lider:
        return None
    return max(gap, 0.0) / (v - v_lider)


def drac(gap: float | None, v: float, v_lider: float) -> float | None:
    """Desaceleración necesaria para no alcanzar al líder (m/s²)."""
    if gap is None or v <= v_lider:
        return None
    return (v - v_lider) ** 2 / (2 * max(gap, 0.1))


def pet_cruce(dist_ego: float, v_ego: float, dist_rival: float, v_rival: float) -> float | None:
    """Diferencia de tiempos de llegada al punto de conflicto (PET aproximado)."""
    if dist_ego < 0 or dist_rival < 0 or v_ego < 0.5 or v_rival < 0.5:
        return None
    return abs(dist_ego / v_ego - dist_rival / v_rival)


def _escala(valor: float | None, critico: float, seguro: float) -> float:
    """0 en `seguro`, 100 en `critico` o peor (sirve para escalas crecientes o decrecientes)."""
    if valor is None:
        return 0.0
    frac = (valor - seguro) / (critico - seguro)
    return 100.0 * min(max(frac, 0.0), 1.0)


@dataclass(frozen=True)
class Riesgo:
    indice: float          # 0-100
    nivel: str             # bajo | medio | alto
    causa: str             # qué indicador lo explica
    ttc: float | None
    drac: float | None
    pet: float | None

    def to_dict(self) -> dict:
        r = lambda x: None if x is None else round(x, 2)   # noqa: E731
        return {
            "indice": round(self.indice), "nivel": self.nivel, "causa": self.causa,
            "ttc": r(self.ttc), "drac": r(self.drac), "pet": r(self.pet),
        }


def nivel_riesgo(indice: float) -> str:
    return "alto" if indice >= 60 else "medio" if indice >= 30 else "bajo"


def indice_riesgo(ttc_s: float | None, drac_ms2: float | None, pet_s: float | None = None) -> Riesgo:
    """Combina TTC, DRAC y PET en un índice 0-100: manda el indicador más grave."""
    componentes = {
        "alcance al vehículo de adelante (TTC)": _escala(ttc_s, TTC_CRITICO, TTC_SEGURO),
        "frenado brusco necesario (DRAC)": _escala(drac_ms2, DRAC_CRITICO, 0.0),
        "conflicto con tráfico cruzado (PET)": _escala(pet_s, PET_CRITICO, PET_SEGURO),
    }
    causa, indice = max(componentes.items(), key=lambda kv: kv[1])
    if indice == 0:
        causa = "sin conflictos"
    return Riesgo(indice, nivel_riesgo(indice), causa, ttc_s, drac_ms2, pet_s)


def riesgo_peaton(dist_vehiculo: float | None, v_acercamiento: float) -> Riesgo:
    """Riesgo de un peatón: tiempo hasta que el vehículo más cercano lo alcance."""
    t = None
    if dist_vehiculo is not None and v_acercamiento > 0.3:
        t = dist_vehiculo / v_acercamiento
    indice = _escala(t, TTC_CRITICO, TTC_SEGURO)
    causa = "vehículo acercándose" if indice > 0 else "sin conflictos"
    return Riesgo(indice, nivel_riesgo(indice), causa, t, None, None)


def clasificar_accion(
    v: float,
    aceleracion: float,
    espera: float,
    luz_proxima: str | None = None,
    dist_luz: float | None = None,
    gap_lider: float | None = None,
    cambiando_carril: str | None = None,
    cede_paso: bool = False,
) -> tuple[str, str]:
    """(código, descripción) de lo que está haciendo el conductor en este instante."""
    if cambiando_carril:
        return "cambia_carril", f"Cambiando de carril hacia la {cambiando_carril}"
    detenido = v < 0.3
    luz_roja = luz_proxima in ("r", "R", "u", "y", "Y") and dist_luz is not None and dist_luz < 40
    if detenido:
        if luz_roja:
            return "espera_semaforo", f"Detenido en el semáforo ({math.ceil(espera)} s)"
        if cede_paso:
            return "cede_paso", f"Cediendo el paso en el cruce ({math.ceil(espera)} s)"
        if gap_lider is not None and gap_lider < 10:
            return "en_cola", f"Detenido en la cola ({math.ceil(espera)} s)"
        return "detenido", "Detenido"
    if luz_roja and aceleracion < -0.5:
        return "frena_semaforo", "Frenando por el semáforo"
    if cede_paso and aceleracion < -0.3:
        return "frena_cruce", "Reduciendo para ceder el paso"
    if aceleracion < -2.5:
        return "frenada_fuerte", "Frenada fuerte"
    if aceleracion < -0.3:
        return "frena", "Frenando"
    if aceleracion > 0.3:
        return "acelera", "Acelerando"
    return "crucero", "Velocidad constante"


def opcion_enlace(direccion: str, estado: str, prioridad: bool, abierto: bool, conflicto: bool) -> dict:
    """Una de las decisiones posibles en el próximo cruce, lista para el HUD."""
    return {
        "direccion": direccion,
        "etiqueta": DIRECCIONES.get(direccion, direccion),
        "estado": estado,
        "estado_etiqueta": ESTADOS_ENLACE.get(estado, estado),
        "prioridad": prioridad,
        "puede_pasar": abierto,
        "conflicto": conflicto,
    }
