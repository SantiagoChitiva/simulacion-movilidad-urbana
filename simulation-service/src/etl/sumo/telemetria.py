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


# ─────────────────────────────── viaje del actor seguido y balance del cruce

FRENADA_EN_SECO = 4.5   # m/s² de desaceleración: frenada brusca (más que un frenado normal, ~3 m/s²)
V_DETENIDO = 0.3        # m/s


def acumular_viaje(viaje: dict | None, tele: dict, t: float, dt: float) -> dict:
    """Suma un frame de telemetría del actor seguido a las cifras de su viaje en un lado."""
    if viaje is None:
        # arranca "detenido" para que la salida desde cero no cuente como parada
        viaje = {"inicio_t": t, "fin_t": t, "detenido_s": 0.0, "paradas": 0, "frenadas": 0,
                 "riesgo_max": 0.0, "co2_g": 0.0, "distancia_m": 0.0, "perdida_s": 0.0,
                 "_detenido": True, "_frenando": False}
    v = (tele.get("velocidad_kmh") or 0.0) / 3.6
    detenido = v < V_DETENIDO
    if detenido:
        viaje["detenido_s"] += dt
        if not viaje["_detenido"]:
            viaje["paradas"] += 1
    a = tele.get("aceleracion")
    frenando = a is not None and a <= -FRENADA_EN_SECO
    if frenando and not viaje["_frenando"]:
        viaje["frenadas"] += 1
    viaje["_detenido"], viaje["_frenando"] = detenido, frenando
    riesgo = (tele.get("riesgo") or {}).get("indice")
    if riesgo is not None:
        viaje["riesgo_max"] = max(viaje["riesgo_max"], riesgo)
    viaje["co2_g"] += (tele.get("co2_mg_s") or 0.0) * dt / 1000
    if tele.get("distancia_m") is not None:
        viaje["distancia_m"] = tele["distancia_m"]
    else:   # los peatones no reportan distancia: se integra la velocidad
        viaje["distancia_m"] += v * dt
    if tele.get("perdida_s") is not None:
        viaje["perdida_s"] = tele["perdida_s"]
    # con frames largos (simulación acelerada) el muestreo se pierde paradas cortas: SUMO
    # lleva la cuenta exacta de lo que el vehículo ha estado detenido
    if tele.get("espera_acum_s") is not None:
        viaje["detenido_s"] = max(viaje["detenido_s"], tele["espera_acum_s"])
    viaje["fin_t"] = t
    return viaje


def resumen_viaje(viaje: dict | None, terminado: bool) -> dict | None:
    """Cifras para mostrar de un viaje (sin los campos internos)."""
    if viaje is None:
        return None
    duracion = viaje["fin_t"] - viaje["inicio_t"]
    return {
        "terminado": terminado,
        "duracion_s": round(duracion, 1),
        "detenido_s": round(viaje["detenido_s"], 1),
        "paradas": viaje["paradas"],
        "frenadas": viaje["frenadas"],
        "riesgo_max": round(viaje["riesgo_max"]),
        "co2_g": round(viaje["co2_g"], 1),
        "distancia_m": round(viaje["distancia_m"]),
        "perdida_s": round(viaje["perdida_s"], 1),
        "velocidad_media_kmh": round(3.6 * viaje["distancia_m"] / duracion, 1) if duracion > 0 else None,
    }


def comparar_viajes(sin: dict | None, con: dict | None) -> dict:
    """Frase que resume el mismo viaje sin semáforo (`sin`) y con el semáforo propuesto (`con`)."""
    if not sin or not con:
        falta = "sin semáforo" if not sin else "con semáforo"
        return {"veredicto": f"El viaje no se pudo completar en el escenario {falta}: no hay comparación.",
                "tono": "neutro", "diferencia_s": None}
    if not (sin["terminado"] and con["terminado"]):
        return {"veredicto": "El viaje no terminó en los dos escenarios: las cifras son parciales.",
                "tono": "neutro", "diferencia_s": None}
    dt = con["duracion_s"] - sin["duracion_s"]
    d_riesgo = sin["riesgo_max"] - con["riesgo_max"]   # > 0: más seguro con semáforo
    d_frenadas = sin["frenadas"] - con["frenadas"]
    tiempo = (f"tardó {abs(dt):.0f} s más" if dt > 2 else f"tardó {abs(dt):.0f} s menos" if dt < -2
              else "tardó casi lo mismo")
    partes = [f"Con el semáforo el viaje {tiempo}"]
    if abs(d_riesgo) >= 10:
        partes.append(f"el riesgo máximo {'bajó' if d_riesgo > 0 else 'subió'} de {sin['riesgo_max']} a {con['riesgo_max']} sobre 100")
    if d_frenadas:
        partes.append(f"hubo {con['frenadas']} frenadas en seco frente a {sin['frenadas']}")
    frase = ", ".join(partes[:-1]) + (" y " if len(partes) > 1 else "") + partes[-1] + "."
    mas_seguro = d_riesgo >= 10 or d_frenadas > 0
    menos_seguro = d_riesgo <= -10 or d_frenadas < 0
    if menos_seguro and not mas_seguro:
        conclusion, tono = "Con el semáforo este viaje fue menos seguro: frenó más fuerte o pasó más cerca de otro.", "malo"
    elif mas_seguro and dt <= 2:
        conclusion, tono = "El semáforo hizo este viaje más seguro sin hacerlo más lento.", "bueno"
    elif mas_seguro and dt <= 30:
        conclusion, tono = "El semáforo hizo este viaje más seguro a cambio de una espera corta.", "bueno"
    elif mas_seguro:
        conclusion, tono = "Más seguro, pero con una espera larga: convendría revisar el ciclo del semáforo.", "neutro"
    elif dt < -2:
        conclusion, tono = "Con el semáforo este viaje fue más rápido.", "bueno"
    elif dt > 2:
        conclusion, tono = "Para este viaje el semáforo agregó espera sin una mejora clara de seguridad.", "malo"
    else:
        conclusion, tono = "Para este viaje el semáforo no cambió ni el tiempo ni el riesgo.", "neutro"
    return {"veredicto": f"{frase} {conclusion}", "tono": tono, "diferencia_s": round(dt, 1)}


def nuevo_balance() -> dict:
    return {"observado_s": 0.0, "frenadas": 0, "frenadas_principal": 0, "cola_max": {"principal": 0, "lateral": 0},
            "espera": {"principal": {}, "lateral": {}}, "_frenando": set()}


def actualizar_balance(balance: dict, vehiculos: list[tuple[str, float, float | None, float, str | None]], dt: float) -> dict:
    """Suma un frame al balance del cruce de un lado.

    `vehiculos`: (id, velocidad m/s, aceleración m/s² o None, espera s, grupo) de los
    vehículos cerca del cruce; grupo es "principal" o "lateral" si está en un acceso
    del cruce, None si ya lo cruzó o va por otra vía.
    """
    balance["observado_s"] += dt
    frenando = set()
    colas = {"principal": 0, "lateral": 0}
    for vid, v, a, espera, grupo in vehiculos:
        if a is not None and a <= -FRENADA_EN_SECO:
            frenando.add(vid)
            if vid not in balance["_frenando"]:
                balance["frenadas"] += 1
                balance["frenadas_principal"] += grupo == "principal"
        if grupo is not None:
            if v < V_DETENIDO:
                colas[grupo] += 1
            balance["espera"][grupo][vid] = max(balance["espera"][grupo].get(vid, 0.0), espera)
    balance["_frenando"] = frenando
    for grupo, n in colas.items():
        balance["cola_max"][grupo] = max(balance["cola_max"][grupo], n)
    return balance


def resumen_balance(balance: dict, conflictos: int, colisiones: int) -> dict:
    """Cifras por hora del cruce en un lado, como las de Semáforos de Barranquilla."""
    horas = balance["observado_s"] / 3600
    por_hora = lambda n: round(n / horas) if horas > 0 else None   # noqa: E731
    espera = {
        g: round(sum(e.values()) / len(e), 1) if e else None for g, e in balance["espera"].items()
    }
    return {
        "minutos": round(balance["observado_s"] / 60, 1),
        "frenadas_hora": por_hora(balance["frenadas"]),
        "frenadas_principal_hora": por_hora(balance["frenadas_principal"]),
        "conflictos_hora": por_hora(conflictos),
        "colisiones": colisiones,
        "cola_max_principal": balance["cola_max"]["principal"],
        "cola_max_lateral": balance["cola_max"]["lateral"],
        "espera_principal_s": espera["principal"],
        "espera_lateral_s": espera["lateral"],
    }
