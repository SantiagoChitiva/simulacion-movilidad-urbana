// @brief: especificacion de la seccion anexos y sus subsecciones correspondientes
#let anexos() = [
= Anexos

== Descripción de la Encuesta de Movilidad de Bogotá 2023

La *Encuesta de Movilidad de Bogotá 2023* es el instrumento oficial de caracterización de los patrones de desplazamiento de la población capitalina.
Es llevada a cabo por la Secretaría Distrital de Movilidad y constituye la principal fuente de datos de demanda del presente proyecto.

#table(
  columns: (auto, 1fr),
  inset: 8pt,
  align: (left, left),
  stroke: 0.5pt,
  [*Atributo*],               [*Descripción*],
  [Cobertura geográfica],     [Las 20 localidades urbanas del Distrito Capital de Bogotá.],
  [Unidad de muestreo],       [Hogar residente en Bogotá.],
  [Variables de viaje],       [Modo de transporte, hora de salida y llegada, propósito del viaje, zona origen y zona destino (codificadas por UPZ).],
  [Variables socioeconómicas],[Tamaño del hogar, estrato socioeconómico, tenencia de vehículo particular y bicicleta.],
  [Factor de expansión],      [Ponderador estadístico que permite proyectar la muestra al universo poblacional de la ciudad.],
  [Uso en el proyecto],       [Construcción de matrices O/D por UPZ para la hora de máxima demanda AM, segmentadas por modo de transporte.],
)

// ─────────────────────────────────────────────────
== Posición de Bogotá en el TomTom Traffic Index 2025

El *TomTom Traffic Index* es un informe anual que clasifica ciudades del mundo según su nivel de congestión vehicular, medido como el tiempo adicional
de viaje respecto a condiciones de tráfico libre.

#table(
  columns: (auto, 1fr),
  inset: 8pt,
  align: (left, left),
  stroke: 0.5pt,
  [*Indicador*],                    [*Valor reportado (2025)*],
  [Posición global],                [7.° lugar entre las ciudades más congestionadas del mundo.],
  [Índice de congestión],           [69,9 %.],
  [Velocidad promedio en hora pico],[Aproximadamente 15 km/h.],
  [Implicación para el proyecto],   [El alto nivel de congestión evidencia la necesidad de herramientas de simulación que permitan evaluar políticas de movilidad antes de su implementación.],
)

]

