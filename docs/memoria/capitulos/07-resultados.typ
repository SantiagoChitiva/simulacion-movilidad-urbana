= Resultados

Este capítulo presenta los resultados del control de calidad definido en la metodología. Primero van las pruebas del software. Después, lo que
produjo el sistema con los datos de Usaquén: las simulaciones de los presets, la priorización de cruces y dos comparaciones de semáforos. Al final se
analiza qué se puede concluir de esos números y qué no.

== Pruebas del software

*Pruebas automatizadas.* El servicio de simulación tiene 177 pruebas con pytest y todas pasan (@tabPruebas). Cubren las funciones puras (demanda,
priorización, telemetría, Webster, métricas) con datos pequeños hechos a mano, y la API con gestores falsos que reemplazan a SUMO. Las que necesitan la
red real (catálogo de semáforos, vías) la leen del escenario versionado.

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([*Módulo*], [*Pruebas*], [*Qué verifican*]),
    [API (`test_api.py`, `test_comparacion3d.py`)], [35], [Corridas con pipeline falso, cancelación y reanudación, precalculadas comprimidas,
    fichas, vías, comparación de programas, ciclo de vida de la comparación 3D y conteo de choques (cada pareja una vez).],
    [Telemetría], [24], [TTC, DRAC, PET, índice de riesgo, acciones, viaje del actor (paradas, frenadas), veredictos, balance por hora y choques
    frente a roces.],
    [Priorización], [18], [Doble calzada como un cruce, exclusiones por reglas (también con semáforos reales de la SDM), niveles por evidencia,
    textos para no técnicos.],
    [Demanda], [12], [Presets que conservan el total y reproducción exacta de la encuesta con sus conteos por defecto.],
    [Escena 3D, semáforo nuevo, comparación de programas], [26], [Geometría, andenes y cebras, rutas transitables por tipo de vehículo,
    instalación del semáforo propuesto, Webster por fases, detectores y métricas.],
    [Validación y demanda ampliada], [21], [Aforos ubicados por rumbo, GEH, encuesta completa (puertas y tope), GTFS, ventanas, argumentos de
    duaIterate y rangos con varias semillas.],
    [Resto del pipeline], [41], [Viajes, rutas, FCD, trayectorias para kepler, tipos de vehículo, configuración, avance, recortes y precalculadas.],
    [*Total*], [*177*], [],
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

En el simulador 3D el contador llegó a mostrar cientos de choques por sesión. Tenía dos fallas. Sumaba en cada paso los vehículos en colisión, así
que un mismo choque que duraba varios pasos se contaba varias veces y con sus dos vehículos. Además, contaba como choque lo que en la calle no lo es.
En un cruce medido (20 minutos simulados), 88 parejas en colisión del lado sin semáforo se repartían así: 65 sobre una cebra y 57 a menos de
5 km/h. La mayoría eran peatones que, tras esperar en una cebra bloqueada por un carro detenido, el modelo de franjas de SUMO deja pasar "a través" del
vehículo. Ahora cada pareja se cuenta una vez y se separan los choques (5 km/h o más de velocidad relativa) de esos roces. Aun así quedan
choques del modelo, porque SUMO no está libre de colisiones en cruces con peatones. Por eso la comparación de seguridad se apoya en los casi
choques (PET), una medida sustituta usual, y no en los choques simulados.

== Priorización de cruces

La red de Usaquén tiene 220 semáforos (programas `tlLogic`), que al agruparse por cruce dan 150 cruces semaforizados. Esos 150 sirven de referencia
para calibrar la evidencia: con los siniestros de 2015 a 2021, la mediana de un cruce semaforizado es de 16 siniestros a menos de 30 m y el percentil 75
es de 33. El volumen simulado que entra a un cruce semaforizado tiene un percentil 75 de 356 vehículos en la mañana.

OpenStreetMap no tiene todos los semáforos de la ciudad. Por eso las reglas también usan los 199 semáforos reales de la Secretaría de Movilidad en el
área de la red (capa de intersecciones semafóricas de su servidor ArcGIS). Dos candidatos resultaron estar ya semaforizados y uno más quedó a menos
de 80 m de un semáforo real.

Las reglas duras descartaron la mayoría de los nodos (@tabDescartes). Con la evidencia y los volúmenes de la precalculada de la encuesta (con los buses
del SITP), quedaron 4 cruces prioritarios, 58 recomendados y 144 en observación. Los cuatro prioritarios son Calle 163A × Carrera 13B, Avenida
Calle 153 × Carrera 8A, Avenida Calle 161 × Carrera 8 y Calle 163A × Carrera 17. En todos coinciden dos señales: un tramo largo sin semáforo (entre 673 y 1.402 m) y siniestros o
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
    [Semáforo a menos de 80 m (de la red o de la SDM)], [27],
    [Ya tiene semáforo según la SDM, aunque OpenStreetMap no lo tenga], [2],
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

== Validación con aforos

Cada corrida cuenta los vehículos por modo en los 33 puntos de aforo HMD que caen en la red y compara su hora pico con la aforada (@tabGEH). Las
estaciones se dividen de forma fija en un grupo de calibración (18 puntos) y uno de control (15), que nunca se usa para ajustar la demanda. La
validación se calcula en el servicio (`output/validacion.json` y `.csv` de cada corrida) y se documenta aquí; el visor no la muestra, porque
mientras ningún escenario cumpla el criterio una pestaña de validación no ayuda a decidir nada.

#figure(
  table(
    columns: (1fr, auto, auto, auto),
    table.header([*Demanda (mañana)*], [*Vehículos que entran*], [*Simulado / aforado*], [*GEH < 5*]),
    [Viajes internos de la encuesta (tope de 50 copias)], [9.592], [6 %], [0 de 33],
    [+ tráfico de paso calibrado con routeSampler], [—], [27 %], [2 de 33],
    [Encuesta completa (entran, salen y sin tope), mesoscópico], [54.984 de 145.014], [22 %], [2 de 33],
    [Encuesta completa con rutas de duaIterate], [54.944 de 145.014], [22 %], [2 de 33],
    [Encuesta completa sin control de cruces (diagnóstico)], [66.678 de 145.014], [33 %], [2 de 33],
  ),
  caption: [GEH de la simulación frente a los aforos HMD con distintas demandas.],
) <tabGEH>

La primera fila explica por qué la demanda interna sola no puede pasar el GEH. Solo tiene los viajes que empiezan y terminan en Usaquén, y la mediana
del factor de expansión en la mañana es 123 frente al tope de 50. La encuesta completa corrige las dos cosas con los datos de la propia encuesta:
agrega los vehículos que entran o salen por las vías arteriales del borde (unos 61.500 autos frente a 21.800 internos) y las copias que el tope
quitaba. Con eso la demanda ya es del orden de los aforos, pero la red no la mueve. Menos de la mitad de los vehículos alcanza a entrar en 15
minutos y a las 10:00 quedan más de 20.000 atrapados adentro.

Las dos últimas filas descartan las explicaciones más simples. Repartir las rutas según la congestión no cambia nada, y quitar las reglas de los
cruces solo sube el volumen al 33 %. El límite es la capacidad de la red construida desde OpenStreetMap: carriles y conexiones de las avenidas,
programas de semáforo estimados por netconvert y aforos que cubren varias calzadas paralelas, como la Autopista Norte con sus laterales, que en la
red son edges distintos. Ese es el trabajo de calibración que queda.

== Análisis de los resultados

Los resultados muestran que el sistema hace lo que prometió: lleva la encuesta a SUMO sin pasos manuales, produce escenarios distintos que se
comparan en el mismo visor y responde preguntas concretas sobre semáforos. Las dos comparaciones de la sección anterior van en la dirección que la
teoría espera. Webster acorta el ciclo y baja la demora cuando el tráfico es moderado. Un semáforo cambia conflictos por espera.

Al mismo tiempo, los números no deben leerse como predicciones de la calle, por cuatro razones:
- *Sin calibración.* El GEH muestra que los volúmenes simulados están lejos de los aforos: 2 de 33 puntos cumplen. Lo que el sistema compara bien
  es una alternativa contra otra con la misma demanda; los valores absolutos pueden estar lejos de la realidad.
- *Demanda interna por defecto.* Las corridas del visor usan los viajes internos de Usaquén con un tope de 50 copias por respuesta y los buses
  del GTFS. La encuesta completa y el tráfico de paso solo se usaron para los experimentos de validación (por línea de comandos o la API) y no
  se ofrecen en el visor: la red no alcanza a moverlos y la corrida se vuelve varias veces más lenta.
- *Capacidad de la red sin calibrar.* Con la demanda completa la red se llena aunque las rutas se repartan con asignación iterativa. Las colas en
  las avenidas más cargadas son, en parte, un efecto del modelo de red.
- *Fondo supuesto en el 3D.* El tráfico de fondo de las comparaciones 3D se agrega para que la zona no quede vacía; no es un aforo. El resumen lo
  dice explícitamente.
