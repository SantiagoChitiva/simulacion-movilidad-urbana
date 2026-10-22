import csv
import xml.etree.ElementTree as ET
from collections import Counter
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

from .configuration import HORA_FIN, HORA_INI, MAX_COPIAS
from .enums.survey_mode import SurveyMode
from .enums.transport_mode import TransportMode
from .vtypes import VTYPES

if TYPE_CHECKING:
    from .demanda import DemandaConfig

XSI = "http://www.w3.org/2001/XMLSchema-instance"
ROUTES_XSD = "http://sumo.dlr.de/xsd/routes_file.xsd"


@dataclass(frozen=True)
class TripGenerationConfig:
    tsv_path: Path
    output_path: Path
    hora_ini: int = HORA_INI
    hora_fin: int = HORA_FIN
    max_copias: int = MAX_COPIAS
    demanda: "DemandaConfig | None" = None   # None = demanda de la encuesta tal cual


@dataclass
class TripGenerationStats:
    filas_totales: int = 0
    filas_invalidas: int = 0
    fuera_de_ventana: int = 0
    modos_desconocidos: int = 0
    viajes_originales: int = 0
    viajes_generados: int = 0
    vehiculos_generados: int = 0
    personas_generadas: int = 0
    por_modo: Counter = field(default_factory=Counter)


@dataclass(frozen=True)
class TripRecord:
    """Un viaje de la encuesta ya validado, antes de expandirse en copias."""
    depart: float
    mode: TransportMode
    copies: int
    origin_taz: str
    destination_taz: str
    duracion_min: float | None = None   # duración reportada en la encuesta
    fexp: float = 1.0                   # factor de expansión sin tope


@dataclass(frozen=True)
class TripGenerationResult:
    output_path: Path
    stats: TripGenerationStats


# ---------------------------------------------------------------- lectura

def _parse_fexp(raw: str | None) -> float:
    try:
        return float(raw) if raw else 1.0
    except ValueError:
        return 1.0


def _parse_copies(raw: str | None, max_copias: int) -> int:
    return min(max(round(_parse_fexp(raw)), 1), max_copias)


def _parse_duracion(raw: str | None) -> float | None:
    try:
        return float(raw) if raw else None
    except ValueError:
        return None


def read_trips(config: TripGenerationConfig, stats: TripGenerationStats) -> Iterator[TripRecord]:
    """Lee el TSV, filtra filas inválidas y actualiza stats."""
    with open(config.tsv_path, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            stats.filas_totales += 1

            try:
                depart = float(row["hora_ini_seg"])
            except (ValueError, TypeError):
                stats.filas_invalidas += 1
                continue

            if not (config.hora_ini <= depart < config.hora_fin):
                stats.fuera_de_ventana += 1
                continue

            survey_mode = SurveyMode.parse(row["modo_principal_agrupado"])
            if survey_mode is None:
                stats.modos_desconocidos += 1
                continue

            stats.viajes_originales += 1
            yield TripRecord(
                depart=depart,
                mode=survey_mode.transport_mode,
                copies=_parse_copies(row.get("fexp_vj"), config.max_copias),
                origin_taz=row["zat_ori"].strip(),
                destination_taz=row["zat_des"].strip(),
                duracion_min=_parse_duracion(row.get("duracion_min")),
                fexp=_parse_fexp(row.get("fexp_vj")),
            )


# -------------------------------------------------------------------- XML

def _create_root() -> ET.Element:
    return ET.Element(
        "routes",
        {
            "xmlns:xsi": XSI,
            "xsi:noNamespaceSchemaLocation": ROUTES_XSD,
        },
    )


def _add_vtypes(root: ET.Element) -> None:
    for vtype in VTYPES.values():
        ET.SubElement(root, "vType", vtype.to_xml_attrs())


def _add_vehicle_trip(root: ET.Element, trip_id: str, trip: TripRecord) -> None:
    ET.SubElement(
        root,
        "trip",
        {
            "id": trip_id,
            "type": trip.mode.value,
            "depart": f"{trip.depart:.2f}",
            "fromTaz": trip.origin_taz,
            "toTaz": trip.destination_taz,
        },
    )


def _add_person_walk(root: ET.Element, person_id: str, trip: TripRecord) -> None:
    person = ET.SubElement(
        root,
        "person",
        {"id": person_id, "depart": f"{trip.depart:.2f}"},
    )
    ET.SubElement(
        person,
        "walk",
        {"fromTaz": trip.origin_taz, "toTaz": trip.destination_taz},
    )


def _add_trip(root: ET.Element, trip_id: str, trip: TripRecord) -> None:
    if trip.mode.is_vehicle:
        _add_vehicle_trip(root, trip_id, trip)
    else:
        # PEATON y TRANSPORTE_PUBLICO: ambos se modelan como <person><walk>.
        # Limitación: el transporte público aún no usa <ride> ni paradas.
        _add_person_walk(root, trip_id, trip)


def _build_xml(trips: Iterable[TripRecord], stats: TripGenerationStats) -> ET.ElementTree:
    root = _create_root()
    _add_vtypes(root)

    for trip in trips:
        for _ in range(trip.copies):
            stats.viajes_generados += 1
            stats.por_modo[trip.mode.value] += 1

            if trip.mode.is_vehicle:
                stats.vehiculos_generados += 1
                number = stats.vehiculos_generados
            else:
                stats.personas_generadas += 1
                number = stats.personas_generadas

            _add_trip(root, f"{trip.mode.value}_{number}", trip)

    tree = ET.ElementTree(root)
    ET.indent(tree, space="    ")
    return tree


# --------------------------------------------------------------- pública

def generate_trips(config: TripGenerationConfig) -> TripGenerationResult:
    if not config.tsv_path.is_file():
        raise FileNotFoundError(f"No existe el TSV de viajes: {config.tsv_path}")

    stats = TripGenerationStats()
    registros = list(read_trips(config, stats))

    if config.demanda is not None:
        # import diferido: demanda.py importa este módulo
        from .demanda import asignar, cargar_dia
        registros = asignar(registros, cargar_dia(config.tsv_path), config.demanda)

    # El TSV no viene ordenado por hora_ini_seg y duarouter conserva el orden del
    # .trips.xml; SUMO descarta (no reordena) todo depart menor al máximo ya leído
    # ("Route file should be sorted by departure time, ignoring ..."). Por eso se
    # ordena aquí: sorted es estable, así que empates conservan el orden del TSV.
    trips = sorted(registros, key=lambda t: t.depart)
    tree = _build_xml(trips, stats)

    config.output_path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(config.output_path, encoding="UTF-8", xml_declaration=True)

    return TripGenerationResult(config.output_path, stats)
