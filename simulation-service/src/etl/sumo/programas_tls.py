"""
Lectura, edición y cálculo (Webster) de programas de semáforo.

Fase C del módulo de semáforos: expone los programas que tiene la red (tlLogic),
permite editarlos (generar un additional.xml) y calcular tiempos óptimos por Webster.
"""
import shutil
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .proceso import ejecutar


class ProgramasTLSError(RuntimeError):
    """netconvert no está disponible o el programa es inválido."""


# ─────────────────────────────────────── estructuras de datos

@dataclass
class FasePrograma:
    duracion_s: float
    estado: str          # una letra por linkIndex, ej. "GGrrrGGrrr"


@dataclass
class ProgramaTLS:
    tl_id: str
    program_id: str
    tipo: str            # "static" | "actuated" | "delay_based"
    offset: float
    fases: list[FasePrograma]

    @property
    def ciclo_s(self) -> float:
        return sum(f.duracion_s for f in self.fases)

    def to_dict(self) -> dict[str, Any]:
        return {
            "tl_id": self.tl_id,
            "program_id": self.program_id,
            "tipo": self.tipo,
            "offset": self.offset,
            "ciclo_s": self.ciclo_s,
            "fases": [{"duracion_s": f.duracion_s, "estado": f.estado} for f in self.fases],
        }


# ─────────────────────────────────────── lectura desde la red

def leer_programas(net_path: Path, tl_id: str) -> list[ProgramaTLS]:
    """Devuelve todos los tlLogic de un semáforo (normalmente uno con programID="0")."""
    programas: list[ProgramaTLS] = []
    for _, elem in ET.iterparse(net_path, events=("end",)):
        if elem.tag == "tlLogic" and elem.get("id") == tl_id:
            fases = [
                FasePrograma(
                    duracion_s=float(ph.get("duration", 0)),
                    estado=ph.get("state", ""),
                )
                for ph in elem.findall("phase")
            ]
            programas.append(ProgramaTLS(
                tl_id=tl_id,
                program_id=elem.get("programID", "0"),
                tipo=elem.get("type", "static"),
                offset=float(elem.get("offset", 0)),
                fases=fases,
            ))
            elem.clear()
        elif elem.tag == "connection":
            elem.clear()
    return programas


def leer_programa(net_path: Path, tl_id: str, program_id: str = "0") -> ProgramaTLS | None:
    """Devuelve un programa específico, o None si no existe."""
    for prog in leer_programas(net_path, tl_id):
        if prog.program_id == program_id:
            return prog
    return None


# ─────────────────────────────────────── escritura de additional.xml

def escribir_programa(prog: ProgramaTLS, destino_xml: Path) -> None:
    """Genera un <additional><tlLogic programID="...">…</tlLogic></additional>.

    Este archivo se incluye en el sumocfg como additional-file para sobreescribir
    el programa de fábrica con el programa editado por el usuario.
    """
    raiz = ET.Element("additional")
    tl = ET.SubElement(raiz, "tlLogic",
                        id=prog.tl_id,
                        type=prog.tipo,
                        programID=prog.program_id,
                        offset=str(prog.offset))
    for fase in prog.fases:
        ET.SubElement(tl, "phase", duration=str(fase.duracion_s), state=fase.estado)

    destino_xml.parent.mkdir(parents=True, exist_ok=True)
    tree = ET.ElementTree(raiz)
    ET.indent(tree, space="  ")
    tree.write(str(destino_xml), encoding="UTF-8", xml_declaration=True)


# ─────────────────────────────────────── validación

def validar_programa(prog: ProgramaTLS, movimientos: int) -> list[str]:
    """Retorna lista de errores de validación (vacía = válido).

    Reglas:
    - Todas las fases deben tener un estado con exactamente `movimientos` caracteres.
    - Las fases con verde ('G'/'g') deben ir acompañadas de una fase de amarillo ≥ 3 s.
    - El ciclo total debe ser ≥ 15 s.
    """
    errores: list[str] = []
    if not prog.fases:
        errores.append("El programa no tiene fases.")
        return errores

    for i, fase in enumerate(prog.fases):
        if len(fase.estado) != movimientos:
            errores.append(
                f"Fase {i + 1}: el estado tiene {len(fase.estado)} caracteres "
                f"pero la intersección tiene {movimientos} movimientos."
            )

    # Verificar que haya al menos una fase de amarillo ≥ 3 s por cada acceso con verde
    fases_amarillo = [f for f in prog.fases if "y" in f.estado.lower() and f.duracion_s >= 3]
    fases_verde = [f for f in prog.fases if "G" in f.estado or "g" in f.estado]
    if fases_verde and not fases_amarillo:
        errores.append("Debe haber al menos una fase de amarillo (≥ 3 s) entre el verde y el rojo.")

    if prog.ciclo_s < 15:
        errores.append(f"El ciclo total ({prog.ciclo_s} s) es demasiado corto (mínimo 15 s).")

    return errores


# ─────────────────────────────────────── cálculo Webster

def webster(
    volumenes_por_acceso: dict[str, int],
    num_fases: int,
    flujo_saturacion: int = 1800,
    perdida_por_fase: float = 3.0,
) -> dict[str, Any]:
    """Calcula el ciclo óptimo de Webster y el reparto de verdes.

    Args:
        volumenes_por_acceso: {edge_id: veh/h} de cada acceso del semáforo.
        num_fases: número de fases vehiculares (sin contar las de amarillo).
        flujo_saturacion: flujo de saturación por carril (veh/h, por defecto 1800).
        perdida_por_fase: tiempo de pérdida por fase en segundos (por defecto 3 s).

    Returns:
        {
            "ciclo_optimo_s": float,
            "perdida_total_s": float,
            "Y": float,                    # suma de relaciones de flujo crítico
            "verdes_s": [float, ...],      # duración de verde efectivo por fase
            "tiempos_fase_s": [float, ...] # verde + amarillo (3 s) por fase
        }
    """
    if not volumenes_por_acceso or num_fases < 1:
        raise ProgramasTLSError("Se necesitan volúmenes y al menos una fase para calcular Webster.")

    # Asignamos los accesos a fases de forma circular (simplificado)
    accesos = list(volumenes_por_acceso.items())
    por_fase: list[list[tuple[str, int]]] = [[] for _ in range(num_fases)]
    for idx, item in enumerate(accesos):
        por_fase[idx % num_fases].append(item)

    # Flujo crítico por fase: el acceso con mayor relación v/s
    y_por_fase: list[float] = []
    for grupo in por_fase:
        if not grupo:
            y_por_fase.append(0.0)
        else:
            y_max = max(vol / flujo_saturacion for _, vol in grupo)
            y_por_fase.append(y_max)

    Y = sum(y_por_fase)
    L = num_fases * perdida_por_fase   # pérdida total por ciclo (s)

    # Fórmula de Webster: C = (1.5L + 5) / (1 - Y)
    if Y >= 1.0:
        raise ProgramasTLSError(
            f"La relación de flujo crítico Y={Y:.2f} ≥ 1.0: la intersección está sobresaturada."
        )
    ciclo = (1.5 * L + 5) / (1 - Y)
    ciclo = max(round(ciclo), 30)  # mínimo 30 s

    verde_total = ciclo - L
    verdes: list[float] = []
    for yi in y_por_fase:
        g = round(verde_total * (yi / Y) if Y > 0 else verde_total / num_fases, 1)
        verdes.append(max(g, 5.0))  # verde mínimo 5 s

    return {
        "ciclo_optimo_s": ciclo,
        "perdida_total_s": L,
        "Y": round(Y, 3),
        "verdes_s": verdes,
        "tiempos_fase_s": [v + 3.0 for v in verdes],  # verde + amarillo fijo 3 s
    }


# ─────────────────────────────────────── agregar semáforo (netconvert)

def agregar_semaforo(
    zona_net_xml: Path,
    nodo_id: str,
    destino_net_xml: Path,
) -> None:
    """Usa netconvert para forzar un semáforo en un nodo que actualmente no lo tiene."""
    executable = shutil.which("netconvert")
    if executable is None:
        raise ProgramasTLSError(
            "No se encontró 'netconvert' en el PATH. ¿Está SUMO instalado?"
        )

    destino_net_xml.parent.mkdir(parents=True, exist_ok=True)

    resultado = ejecutar(
        [
            executable,
            "-s", str(zona_net_xml),
            "--tls.set", nodo_id,
            "-o", str(destino_net_xml),
        ],
    )
    if resultado.returncode != 0:
        raise ProgramasTLSError(
            f"netconvert falló al agregar semáforo (código {resultado.returncode}):\n"
            f"{resultado.stderr[-2000:]}"
        )
