from enum import Enum

from .transport_mode import TransportMode

class SurveyMode(str, Enum):
    """Etiquetas crudas de la columna modo_principal_agrupado de la encuesta."""
    AUTO = "AUTO"
    BICICLETA = "BICICLETA"
    A_PIE_MAS_15 = "A PIE > 15 MIN"
    A_PIE_MENOS_15 = "A PIE <15 MIN"
    TRANSPORTE_PUBLICO = "TRANSPORTE PÚBLICO"
    MOTO = "MOTO"
    TAXI = "TAXI OCUPADO"
    ESCOLAR = "TRANSPORTE ESCOLAR"
    ESPECIAL = "ESPECIAL OCUPADO"
    INFORMAL = "INFORMAL"
    OTRO = "OTRO"

    @classmethod
    def parse(cls, raw: str) -> "SurveyMode | None":
        """Devuelve el SurveyMode o None si la etiqueta es desconocida."""
        try:
            return cls(raw.strip())
        except ValueError:
            return None

    @property
    def transport_mode(self) -> TransportMode:
        return SURVEY_TO_TRANSPORT[self]


SURVEY_TO_TRANSPORT: dict[SurveyMode, TransportMode] = {
    SurveyMode.AUTO: TransportMode.AUTO,
    SurveyMode.BICICLETA: TransportMode.BICI,
    SurveyMode.A_PIE_MAS_15: TransportMode.PEATON,
    SurveyMode.A_PIE_MENOS_15: TransportMode.PEATON,
    SurveyMode.TRANSPORTE_PUBLICO: TransportMode.TRANSPORTE_PUBLICO,
    SurveyMode.MOTO: TransportMode.MOTO,
    SurveyMode.TAXI: TransportMode.TAXI,
    SurveyMode.ESCOLAR: TransportMode.ESCOLAR,
    SurveyMode.ESPECIAL: TransportMode.ESPECIAL,
    SurveyMode.INFORMAL: TransportMode.INFORMAL,
    SurveyMode.OTRO: TransportMode.OTRO,
}
