from etl.sumo.enums.transport_mode import TransportMode
from etl.sumo.vtypes import VTYPES


def test_every_vehicle_mode_has_vtype():
    for mode in TransportMode:
        if mode.is_vehicle:
            assert mode.value in VTYPES, f"Falta VTypeConfig para {mode.name}"

def test_no_pedestrian_or_pt_in_vtypes():
    """Peatón y transporte público no son vehículos, no deben tener vType por modo."""
    for mode in (TransportMode.PEATON, TransportMode.TRANSPORTE_PUBLICO):
        assert mode.value not in VTYPES


def test_vtype_ids_match_dict_keys():
    for key, cfg in VTYPES.items():
        assert key == cfg.id


def test_xml_attrs_include_max_speed():
    attrs = VTYPES["auto"].to_xml_attrs()
    assert attrs["maxSpeed"] == "16.7"
