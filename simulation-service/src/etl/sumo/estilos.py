"""
Estilos de conducción: modifican los parámetros de comportamiento de los vTypes motorizados.

Los parámetros de SUMO que se ajustan son:
- sigma: desviación estándar de la velocidad (0 = robot, 1 = muy aleatorio)
- speedFactor: factor sobre la velocidad máxima del carril
- tau: tiempo de reacción / headway mínimo (s)
- lcSpeedGain: agresividad al cambiar de carril por velocidad
"""
import xml.etree.ElementTree as ET
from enum import Enum
from pathlib import Path


class EstiloConductor(str, Enum):
    agresivo = "agresivo"
    normal = "normal"
    cauteloso = "cauteloso"


PARAMS_ESTILO: dict[EstiloConductor, dict[str, str]] = {
    EstiloConductor.agresivo: {
        "sigma": "0.7",
        "speedFactor": "1.2",
        "tau": "0.8",
        "lcSpeedGain": "2.0",
    },
    EstiloConductor.normal: {
        "sigma": "0.5",
        "speedFactor": "1.0",
        "tau": "1.0",
        "lcSpeedGain": "1.0",
    },
    EstiloConductor.cauteloso: {
        "sigma": "0.3",
        "speedFactor": "0.85",
        "tau": "1.5",
        "lcSpeedGain": "0.5",
    },
}

INFO_ESTILOS: dict[EstiloConductor, dict[str, str]] = {
    EstiloConductor.agresivo: {
        "etiqueta": "Agresivo",
        "descripcion": "Conductores que superan el límite y aceptan menores brechas. Mayor flujo, más colisiones.",
    },
    EstiloConductor.normal: {
        "etiqueta": "Normal",
        "descripcion": "Parámetros por defecto de SUMO, calibrados para comportamiento promedio.",
    },
    EstiloConductor.cauteloso: {
        "etiqueta": "Cauteloso",
        "descripcion": "Velocidades más bajas, mayor distancia de seguimiento. Menor flujo, más seguro.",
    },
}

# vClasses que NO se modifican (peatones y bicicletas no son "motorizados" en este contexto)
_CLASES_NO_MOTORIZADAS = {"pedestrian", "bicycle"}


def aplicar_estilo(vtypes_xml_path: Path, estilo: EstiloConductor, destino: Path | None = None) -> str:
    """Lee el archivo de vTypes, aplica los parámetros del estilo a los vTypes motorizados
    y devuelve el XML resultante (cadena). Si `destino` se especifica, también lo escribe.

    Solo modifica vTypes cuya vClass NO esté en _CLASES_NO_MOTORIZADAS.
    """
    params = PARAMS_ESTILO[estilo]

    tree = ET.parse(vtypes_xml_path)
    raiz = tree.getroot()

    for vtype in raiz.findall(".//vType"):
        v_class = vtype.get("vClass", "passenger")
        if v_class in _CLASES_NO_MOTORIZADAS:
            continue
        for attr, valor in params.items():
            vtype.set(attr, valor)

    ET.indent(tree, space="  ")
    if destino is not None:
        destino.parent.mkdir(parents=True, exist_ok=True)
        tree.write(str(destino), encoding="UTF-8", xml_declaration=True)

    from io import StringIO
    buf = StringIO()
    tree.write(buf, encoding="unicode", xml_declaration=True)
    return buf.getvalue()
