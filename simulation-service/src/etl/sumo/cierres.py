"""
Cierres viales: generan un rerouter de SUMO que bloquea edges durante una ventana horaria.

Un CierreVial indica qué edge se cierra, en qué franja horaria y para qué modos.
La función escribir_rerouter() genera el additional.xml que se incluye en el sumocfg.
"""
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

# Modos de transporte de SUMO que se afectan por defecto (todos salvo emergency)
MODOS_DEFAULT = "passenger motorcycle taxi bus bicycle pedestrian evehicle"


@dataclass
class CierreVial:
    edge_id: str
    hora_inicio_s: float   # segundos desde las 00:00 (ej. 25200 = 07:00)
    hora_fin_s: float      # segundos desde las 00:00 (ej. 32400 = 09:00)
    modos_afectados: str = MODOS_DEFAULT   # cadena de vClasses separados por espacio


def escribir_rerouter(
    cierres: list[CierreVial],
    destino_xml: Path,
) -> None:
    """Genera el additional.xml con un <rerouter> por cierre vial.

    Cada rerouter bloquea un edge durante la ventana indicada usando <closingReroute>.
    Los vehículos afectados buscan ruta alternativa; si no encuentran, esperan o se
    teletransportan (comportamiento por defecto de SUMO con --time-to-teleport).
    """
    if not cierres:
        raise ValueError("La lista de cierres está vacía.")

    raiz = ET.Element("additional")
    for idx, cierre in enumerate(cierres):
        rerouter = ET.SubElement(raiz, "rerouter",
                                  id=f"cierre_{idx}",
                                  edges=cierre.edge_id,
                                  pos="0")
        intervalo = ET.SubElement(rerouter, "interval",
                                   begin=str(cierre.hora_inicio_s),
                                   end=str(cierre.hora_fin_s))
        ET.SubElement(intervalo, "closingReroute",
                       id=cierre.edge_id,
                       disallow=cierre.modos_afectados)

    destino_xml.parent.mkdir(parents=True, exist_ok=True)
    tree = ET.ElementTree(raiz)
    ET.indent(tree, space="  ")
    tree.write(str(destino_xml), encoding="UTF-8", xml_declaration=True)
