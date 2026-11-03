from dataclasses import dataclass

from .enums.vehicle_type import VehicleType
from .enums.transport_mode import TransportMode

BUS_PT_ID = "bus_pt"  # vehículo del servicio, no es un modo de viaje
# buses del SITP (GTFS, transporte_publico.py). Su vType va dentro del archivo de buses: la
# demanda de la encuesta ya define bus_pt y SUMO no admite el mismo vType en dos archivos.
BUS_SITP_ID = "bus_sitp"
VTYPE_BUS_SITP = {"id": BUS_SITP_ID, "vClass": "bus", "length": "12", "maxSpeed": "13.9", "color": "0,0.4,0.8"}
# los buses siguen su línea: sin el dispositivo de re-ruteo que la plantilla da a todos
# (re-rutear un bus con paradas hacía caer a SUMO 1.27 con un acceso inválido a memoria)
PARAMS_BUS_SITP = {"has.rerouting.device": "false"}

@dataclass(frozen=True)
class VTypeConfig:
    id: str
    v_class: VehicleType
    length: float          # metros
    max_speed: float       # m/s = metro/segundo
    color: str             # r,g,b  dado por valores de 0 a 1, e.g., (0.5, 1, 0.25)

    def to_xml_attrs(self) -> dict[str, str]:
        """ atributos listos para ET.SubElement(root, 'vType', attrs) """
        return {
            "id": self.id,
            "vClass": self.v_class.value,
            "length": str(self.length),
            "maxSpeed": str(self.max_speed),
            "color": self.color
        }

VTYPES: dict[str, VTypeConfig] = {
    cfg.id: cfg for cfg in [
        VTypeConfig(TransportMode.AUTO.value, VehicleType.PASSENGER, 4.5, 16.7, "1,1,1"),
        VTypeConfig(TransportMode.BICI.value, VehicleType.BICYCLE, 1.8, 5.5, "0,1,0"),
        VTypeConfig(TransportMode.MOTO.value, VehicleType.MOTORCYCLE, 2.2, 16.7, "1,0.5,0"),
        VTypeConfig(TransportMode.TAXI.value, VehicleType.TAXI, 4.5, 16.7, "1,1,0"),
        VTypeConfig(TransportMode.ESCOLAR.value, VehicleType.BUS, 9, 13.9, "1,0.6,0.8"),
        VTypeConfig(TransportMode.ESPECIAL.value, VehicleType.PASSENGER, 4.5, 16.7, "0.5,0,0.5"),
        VTypeConfig(TransportMode.INFORMAL.value, VehicleType.PASSENGER, 4.5, 16.7, "0.6,0.3,0"),
        VTypeConfig(TransportMode.OTRO.value, VehicleType.PASSENGER, 4.5, 16.7, "0.5,0.5,0.5"),
        VTypeConfig(BUS_PT_ID, VehicleType.BUS, 10, 13.9, "0,0,1"),
    ]
}
