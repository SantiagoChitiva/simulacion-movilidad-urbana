= Descripción General

== Oportunidad, problema

=== Contexto del problema

Bogotá cerró 2025 como una de las diez ciudades con más tráfico del mundo. Según el TomTom Traffic Index @tomtom, el nivel de congestión llegó al
69,9 %, 7,7 puntos más que el año anterior, y un conductor perdió en promedio unas 153 horas en horas pico @eltiempo. En esas horas la velocidad media
apenas pasa de 15 km/h @portafolio2025, y recorrer cinco kilómetros puede tomar 40 minutos @infobae. El problema no es solo de carros: TransMilenio
mueve más de cuatro millones de viajes al día @alcaldia y una parte grande de los bogotanos se desplaza a pie o en transporte público
@portafolio2023.

Para decidir qué hacer con ese tránsito, la ciudad cuenta con buena información. Cada cuatro años la Secretaría Distrital de Movilidad hace una
encuesta de movilidad; la de 2023 @encuesta registró 100.174 viajes con su origen, destino, hora, modo y un factor de expansión que dice a cuántos
viajes reales equivale cada respuesta. También publica los siniestros viales georreferenciados @siniestros. Por otro lado, existen simuladores
microscópicos de código abierto como SUMO @sumo @krajzewicz2012, que reproducen el movimiento de cada vehículo y peatón sobre una red vial y permiten
probar una medida antes de construirla.

Usaquén, en el nororiente de la ciudad, fue el caso de estudio. Tiene 9 UTAM y 89 zonas de análisis de tránsito (ZAT); en la encuesta, 9.341 viajes
tocan la localidad y 2.648 empiezan y terminan dentro de ella. Mezcla avenidas arteriales como la Calle 134, la Carrera 7 y la Autopista Norte con
barrios residenciales, colegios y clínicas, lo que la hacía un buen terreno para estudiar decisiones de semaforización.

=== Formulación del problema

Al empezar el proyecto, usar esos datos en una simulación tenía tres obstáculos.

El primero era la *transformación de los datos*. No había una herramienta que llevara la encuesta a los formatos de SUMO. Había que limpiar los
registros, expandirlos con los factores muestrales, asignar cada viaje a una zona de la red, generar las rutas y escribir la configuración, todo a
mano y con muchas oportunidades de error.

El segundo era la *barrera técnica de SUMO*. El simulador se maneja con archivos XML y herramientas de línea de comandos (netconvert, duarouter,
randomTrips, cutRoutes), y su interfaz gráfica está pensada para quien ya lo conoce. Un planificador de movilidad no podía lanzar un escenario por su
cuenta.

El tercero apareció a mitad del proyecto, al mostrar los primeros resultados: *los resultados no hablaban el idioma de quien decide*. Un mapa con
miles de puntos en movimiento impresiona, pero no responde preguntas como "¿vale la pena un semáforo en esta esquina?". Las métricas de SUMO
(teleports, demora media, cadenas de estado de los semáforos) eran claras para el equipo y opacas para un directivo.

La pregunta que guió el trabajo fue: _¿cómo usar los datos que describen la movilidad de Bogotá, con un simulador como SUMO, para generar escenarios
de forma automática y presentar sus resultados de manera que apoyen las decisiones de quienes planean y gestionan la movilidad?_

=== Propuesta de solución

La solución fue un sistema de software de dos partes, dentro del área de ingeniería de software con un componente fuerte de ingeniería de datos:

- *Un servicio de simulación* que automatiza el camino de la encuesta a SUMO: genera los viajes, los rutea, corre la simulación y exporta las
  trayectorias. También prepara variantes del escenario, como cambios en la mezcla de modos, cierres viales, estilos de conducción o un semáforo
  nuevo en un cruce. SUMO quedó como una caja negra al final del proceso; el aporte del proyecto está en todo lo que lo rodea.
- *Un visor web* que muestra las simulaciones en un mapa animado y deja parametrizar nuevas sin tocar archivos. Sobre esa base se construyó el
  módulo de semáforos: la ficha de cada semáforo existente, la comparación de programas, la priorización de cruces sin semáforo y un simulador 3D
  comparativo con un resumen final en lenguaje sencillo.

=== Justificación de la solución

En la propuesta se compararon cuatro enfoques alternativos: modelos analíticos y teoría de colas, aprendizaje automático, datos en tiempo real de
plataformas comerciales y el modelo clásico de cuatro pasos @mcnally. La simulación microscópica fue la única opción que cumplía los cinco
criterios a la vez:
- resolución vehículo a vehículo;
- posibilidad de evaluar escenarios que nunca han ocurrido;
- independencia de datos privados;
- multimodalidad;
- costo cero en herramientas.

Durante el desarrollo apareció una razón más. La simulación microscópica permite seguir a un actor concreto y medir sobre su trayectoria
indicadores de seguridad como el tiempo a la colisión @gettman. Eso fue lo que hizo posible el simulador 3D y su resumen, que traducen un resultado
técnico a una experiencia que se entiende sin formación en tránsito.

== Descripción del proyecto

=== Objetivo general

Diseñar e implementar un módulo de procesamiento de datos que automatice la transformación de las fuentes de datos de movilidad disponibles para
Bogotá en archivos de entrada válidos para el simulador SUMO, con el fin de eliminar la intervención manual en la generación de redes viales, matrices
origen–destino y archivos de rutas, y facilitar el análisis de movilidad urbana a entidades públicas, investigadores y consultores mediante una
interfaz web que permita visualizar los resultados y configurar nuevos escenarios de forma accesible.

=== Objetivos específicos

+ Analizar y comparar las fuentes de datos de movilidad disponibles para Bogotá para determinar cuáles permiten construir una demanda
  suficientemente representativa para la simulación, reconociendo sus limitaciones de periodicidad y cobertura.
+ Desarrollar un módulo de procesamiento que automatice la transformación de la encuesta en archivos válidos para SUMO, sin intervención manual en
  la generación de la red, la demanda y las rutas.
+ Validar el módulo generando los insumos de al menos una localidad, verificando su coherencia con los patrones de la encuesta y ejecutando el
  escenario en SUMO.
+ Desarrollar un módulo web que permita visualizar los resultados de SUMO y parametrizar nuevas simulaciones sin usar la línea de comandos ni editar
  archivos XML.
+ Incorporar al módulo web el análisis de intersecciones y un simulador 3D comparativo para evaluar la instalación de un semáforo en un cruce sin
  señalizar, con indicadores de fluidez y de seguridad (objetivo agregado en la versión 2.0 de la propuesta).

=== Marco metodológico, entregables, estándares y justificación

El proyecto siguió un ciclo de vida híbrido. Las fases de datos (1 y 2) se hicieron con CRISP-DM @crispdm, porque eran exploratorias: había que
entender la encuesta, la red y los aforos antes de saber qué se podía construir. La construcción del sistema (fase 3) se hizo con Scrum @scrum en
nueve sprints cortos (de una semana, en su mayoría), cada uno terminado en algo que se podía ver funcionando en el visor. La fase 4, de evaluación, retomó CRISP-DM. Un
tablero Kanban en GitHub Projects mantuvo visible el trabajo de las dos metodologías. La @tabEntregables resume los entregables.

#figure(
  table(
    columns: (17%, 27%, 1fr),
    table.header([*Entregable*], [*Estándar*], [*Justificación*]),
    [SPMP], [IEEE 1058 @ieee1058, ISO/IEC 12207 @iso12207, BPMN 2.0 @bpmn], [Estructura del plan (alcance, calendario, recursos, riesgos) y
    procesos del ciclo de vida; BPMN para modelar los procesos internos.],
    [SRS], [IEEE 830 @ieee830], [Requisitos atómicos, verificables y trazables, cada uno con su estado de implementación.],
    [SDD], [IEEE 1016 @ieee1016, vistas 4+1 @kruchten], [Arquitectura por vistas (lógica, física y de procesos) y diseño detallado de estructura,
    comportamiento, persistencia e interfaz.],
    [Código fuente], [PEP 8 @pep8, API TraCI @traci], [Código legible y uniforme en Python; TraCI para controlar SUMO en vivo desde el simulador 3D.],
    [Pruebas], [ISO/IEC/IEEE 29119 @iso29119], [Casos de prueba trazados a los requisitos, automatizados con pytest donde fue posible.],
    [Memoria], [Formato TG del programa], [Documento final del trabajo de grado.],
  ),
  caption: [Entregables, estándares y justificación.],
) <tabEntregables>
