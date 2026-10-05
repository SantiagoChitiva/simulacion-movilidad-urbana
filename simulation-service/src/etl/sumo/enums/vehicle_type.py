from enum import Enum

class VehicleType(str, Enum):
    PASSENGER  = "passenger"
    BICYCLE    = "bicycle"
    MOTORCYCLE = "motorcycle"
    TAXI       = "taxi"
    BUS        = "bus"
