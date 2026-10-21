= Resultados

Este capítulo presenta los resultados del control de calidad definido en la metodología. Primero van las pruebas del software. Después, lo que
produjo el sistema con los datos de Usaquén: las simulaciones de los presets, la priorización de cruces y dos comparaciones de semáforos. Al final se
analiza qué se puede concluir de esos números y qué no.

== Pruebas del software

*Pruebas automatizadas.* El servicio de simulación tiene 139 pruebas con pytest y todas pasan (@tabPruebas). Cubren las funciones puras (demanda,
priorización, telemetría, Webster, métricas) con datos pequeños hechos a mano, y la API con gestores falsos que reemplazan a SUMO. Las que necesitan la
red real (catálogo de semáforos, vías) la leen del escenario versionado.

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([*Módulo*], [*Pruebas*], [*Qué verifican*]),
    [API (`test_api.py`, `test_comparacion3d.py`)], [29], [Corridas con pipeline falso, cancelación, precalculadas comprimidas, fichas, vías,
    comparación de programas y ciclo de vida de la comparación 3D.],
    [Telemetría], [23], [TTC, DRAC, PET, índice de riesgo, acciones, viaje del actor (paradas, frenadas), veredictos y balance por hora.],
    [Priorización], [16], [Doble calzada como un cruce, exclusiones por reglas, niveles por evidencia, textos para no técnicos.],
    [Demanda], [12], [Presets que conservan el total y reproducción exacta de la encuesta con sus conteos por defecto.],
    [Escena 3D, semáforo nuevo, comparación de programas], [23], [Geometría y edificios, instalación del semáforo propuesto, Webster por fases,
    detectores y métricas.],
    [Resto del pipeline], [36], [Viajes, rutas, FCD, trayectorias para kepler, tipos de vehículo, configuración, avance y precalculadas.],
    [*Total*], [*139*], [],
  ),
  caption: [Pruebas automatizadas del servicio de simulación.],
) <tabPruebas>

*Pruebas de integración con SUMO real.* Se probaron tres flujos de punta a punta:
- *Comparación 3D por WebSocket.* Un script lanzó seis actores por los tres accesos del cruce Avenida Calle 161 × Carrera 8 y midió cuándo entraba
  cada uno en cada escenario. Los seis entraron en el mismo paso en los dos lados. Antes de la corrección de la entrada simultánea (RF-047), un actor
  podía quedarse esperando en un lado mientras en el otro ya circulaba.
- *Visor en un navegador sin interfaz.* Un recorrido automático con Chrome eligió un cruce de la lista, cambió entre Street View, satélite y mapa,
  alternó el tema, cerró una vía con un clic, abrió el simulador 3D, lanzó un actor y esperó el resumen. Las figuras del capítulo VI salieron de ese
  recorrido.
- *Comparación de programas.* La comparación del programa actual con el de Webster en la Avenida Calle 134 × Avenida Carrera 9 corrió las dos
  simulaciones y devolvió métricas distintas para cada programa (sección 4).

El visor compila sin errores para producción. La prueba de usuario con el director (RNF-USA-001) queda por hacer antes de la sustentación.

== Simulaciones de los presets

Cada preset reparte los mismos 24.647 viajes de la mañana entre los modos de forma distinta. La @tabPresets resume la corrida de cada uno.

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto, auto),
    table.header([*Preset*], [*Vehículos cargados*], [*Insertados*], [*Personas*], [*Teleports*], [*Colisiones*]),
    [Encuesta], [10.324], [9.592 (92,9 %)], [14.123], [209], [80],
    [Más vehículos], [15.213], [14.404 (94,7 %)], [9.234], [254], [58],
    [Más peatones], [6.462], [6.125 (94,8 %)], [17.985], [141], [123],
    [Día sin carro], [5.190], [4.945 (95,3 %)], [19.257], [106], [134],
  ),
  caption: [Resultados de las simulaciones precalculadas (7:00–10:00).],
) <tabPresets>

Entre el 93 % y el 95 % de los vehículos programados logró entrar a la red antes de las 10:00. El resto quedó esperando en el borde de una vía llena, lo
cual es esperable en las horas más cargadas. Los teleports (vehículos que SUMO retira tras cinco minutos atascados) rondan el 2 % de los
insertados en todos los presets.

Las colisiones merecen una lectura cuidadosa. Crecen cuando hay más peatones (80 con la encuesta frente a 134 el día sin carro), lo que apunta a
cruces peatonales que netconvert generó con una geometría imperfecta. Son un indicador de dónde revisar la red, no un pronóstico de siniestros.

== Priorización de cruces

La red de Usaquén tiene 220 semáforos (programas `tlLogic`), que al agruparse por cruce dan 150 cruces semaforizados. Esos 150 sirven de referencia
para calibrar la evidencia: con los siniestros de 2015 a 2021, la mediana de un cruce semaforizado es de 16 siniestros a menos de 30 m y el percentil 75
es de 33. El volumen simulado que entra a un cruce semaforizado tiene un percentil 75 de 356 vehículos en la mañana.

Las reglas duras descartaron la mayoría de los nodos (@tabDescartes). Con la evidencia, quedaron 5 cruces prioritarios, 56 recomendados y 146 en
observación. Los cinco prioritarios son Calle 163A × Carrera 13B, Avenida Calle 153 × Carrera 8A, Avenida Calle 161 × Carrera 8, Calle 163A ×
Carrera 17 y Avenida Calle 192 × Carrera 11A. En todos coinciden dos señales: un tramo largo sin semáforo (entre 673 y 1.402 m) y siniestros o
tráfico por encima de los cruces que ya tienen semáforo, varios con colegios o centros de salud cerca.

#figure(
  table(
    columns: (1fr, auto),
    table.header([*Motivo de descarte*], [*Cruces*]),
    [Sin vía colectora o de mayor jerarquía], [2.415],
    [No es un cruce de dos calles distintas], [899],
    [Vía secundaria de servicio o peatonal], [332],
    [Sin movimientos que crucen la vía principal], [300],
    [Autopista o troncal de acceso controlado], [109],
    [Rampa o glorieta a menos de 40 m], [77],
    [Semáforo a menos de 80 m], [26],
  ),
  caption: [Cruces descartados por las reglas duras.],
) <tabDescartes>

== Comparación de programas en un semáforo existente

En la Avenida Calle 134 × Avenida Carrera 9 se comparó el programa que trae la red (ciclo de 90 s) con el que propuso Webster a partir del tráfico de
la encuesta (ciclo de 64 s), en una hora punta simulada con los mismos 813 vehículos (@tabProgramas).

#figure(
  table(
    columns: (1fr, auto, auto),
    table.header([*Métrica*], [*Programa actual*], [*Webster*]),
    [Tiempo perdido por vehículo], [327 s], [276 s],
    [Tiempo detenido por vehículo], [272 s], [210 s],
    [Cola más larga en un acceso], [5 veh], [5 veh],
    [Detenciones en los accesos], [278], [316],
    [Tiempo perdido por peatón], [134 s], [131 s],
  ),
  caption: [Programa actual frente a Webster en la Av. Calle 134 × Av. Carrera 9.],
) <tabProgramas>

Con el ciclo más corto, cada vehículo perdió 51 s menos en la zona (un 16 %), aunque se detuvo más veces: los ciclos cortos hacen esperar menos, pero
cortan el paso más a menudo. Que el tiempo perdido sea alto en los dos casos (más de cuatro minutos) se explica porque la métrica cubre toda la zona
de 300 m, con sus otras intersecciones, y no solo el semáforo estudiado.

== Comparación con y sin semáforo en 3D

En la Avenida Calle 161 × Carrera 8, uno de los cruces prioritarios, se lanzó un carro desde la Carrera 8 y se dejó terminar su recorrido. La @tabViaje
compara su viaje en los dos escenarios y el balance del cruce durante los tres minutos simulados de la sesión.

#figure(
  table(
    columns: (1fr, auto, auto),
    table.header([*Indicador*], [*Sin semáforo*], [*Con semáforo*]),
    table.cell(colspan: 3)[_Viaje del carro seguido_],
    [Duración], [1 min 36 s], [1 min 32 s],
    [Tiempo detenido], [2 s], [0 s],
    [Riesgo máximo (0–100)], [100], [100],
    [CO₂ emitido], [171 g], [162 g],
    table.cell(colspan: 3)[_Balance del cruce (por hora)_],
    [Frenadas en seco cerca del cruce], [112], [75],
    [Casi choques (PET < 1,5 s)], [112], [56],
    [Cola más larga en la vía que cede], [1 veh], [7 veh],
    [Espera media en la vía que cede], [0 s], [9 s],
  ),
  caption: [Un viaje y el balance del cruce en la Av. Calle 161 × Carrera 8.],
) <tabViaje>

Para ese viaje el semáforo no tuvo costo: el carro llegó 4 s antes. En el balance, el semáforo redujo a la mitad los casi choques y bajó las frenadas
en seco, a cambio de colas y esperas en la vía que cede. El riesgo máximo del viaje fue alto en los dos escenarios. El índice toma el peor momento del
recorrido, y un frenazo detrás de otro vehículo basta para llevarlo a 100. Tres minutos son pocos para generalizar; el sistema lo advierte y sugiere
lanzar varios viajes.

== Análisis de los resultados

Los resultados muestran que el sistema hace lo que prometió: lleva la encuesta a SUMO sin pasos manuales, produce escenarios distintos que se
comparan en el mismo visor y responde preguntas concretas sobre semáforos. Las dos comparaciones de la sección anterior van en la dirección que la
teoría espera. Webster acorta el ciclo y baja la demora cuando el tráfico es moderado. Un semáforo cambia conflictos por espera.

Al mismo tiempo, los números no deben leerse como predicciones de la calle, por cuatro razones:
- *Sin calibración.* Sin el GEH no hay evidencia de que los volúmenes simulados se parezcan a los aforos. Lo que el sistema compara bien es una
  alternativa contra otra con la misma demanda; los valores absolutos pueden estar lejos de la realidad.
- *Demanda incompleta.* Solo entran los viajes internos de Usaquén, con un tope de 50 copias por respuesta. Falta el tráfico que atraviesa la
  localidad por la Autopista Norte o la Séptima, que en la mañana es grande.
- *Rutas en una sola pasada.* Cada viaje toma la ruta más rápida con la red vacía, sin el equilibrio que buscaría una asignación iterativa. En las
  vías más congestionadas eso exagera las colas.
- *Fondo supuesto en el 3D.* El tráfico de fondo de las comparaciones 3D se agrega para que la zona no quede vacía; no es un aforo. El resumen lo
  dice explícitamente.
