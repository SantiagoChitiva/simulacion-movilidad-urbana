from enum import Enum

class TransportMode(str, Enum):
    AUTO               = "auto"
    BICI               = "bici"
    PEATON             = "peaton"
    TRANSPORTE_PUBLICO = "transporte_publico"
    MOTO               = "moto"
    TAXI               = "taxi"
    ESCOLAR            = "escolar"
    ESPECIAL           = "especial"
    INFORMAL           = "informal"
    OTRO               = "otro"

    @property
    def is_vehicle(self) -> bool:
        return self not in { TransportMode.PEATON, TransportMode.TRANSPORTE_PUBLICO }
