#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

= Análisis del Problema

Este capítulo resume la especificación de requisitos. El SRS (versión 2.2, anexo B) tiene cada requisito con su descripción, criterio de medición,
módulo y estado.

== Requerimientos

Los requisitos funcionales se agruparon en diez funcionalidades. Las cinco primeras corresponden a la propuesta original; las demás aparecieron
cuando el director pidió que el sistema sirviera para decisiones concretas de control de tránsito. La @tabRequisitos resume cada grupo y su estado al
cierre del proyecto.

#figure(
  table(
    columns: (25%, 1fr, 15%),
    table.header([*Funcionalidad*], [*Qué exige*], [*Estado*]),
    [F1–F4 Ingestión, demanda, red y archivos de simulación], [Leer la encuesta limpia, expandirla por modo, construir la red 3D y las zonas, y
    generar viajes, rutas y configuración válidos para SUMO, con los viajes ordenados por hora de salida.], [Implementado (ventana AM)],
    [F5 Escenarios], [Presets de cambio modal que conservan el total de viajes, conteos por modo, semilla, estilos de conducción, cierres viales y
    simulaciones precalculadas.], [Implementado],
    [F6 Módulo web], [Ver los viajes animados por modo, lanzar corridas desde el navegador con avance real y poder cancelarlas.], [Implementado],
    [F7 Validación], [Comparar volúmenes simulados con aforos (GEH) y registrar la ejecución.], [Pendiente (GEH)],
    [F8 Intersecciones], [Ficha de cada semáforo, edición de su programa, tiempos de Webster, comparación de programas con métricas reales y
    priorización de cruces sin semáforo.], [Implementado],
    [F9 Simulador 3D], [Mismo cruce sin y con semáforo propuesto, en paralelo y con la misma demanda; seguir a un actor, medir su riesgo, manejarlo a
    mano y comparar su viaje.], [Implementado (falta exportar el reporte)],
    [F10 Usabilidad], [Tarjeta de cruce al estilo Barranquilla, cierres con un clic, lenguaje sin jerga, tema claro y oscuro.], [Implementado],
  ),
  caption: [Requerimientos por funcionalidad.],
) <tabRequisitos>

Tres requisitos pesaron más que el resto en el diseño:

- *RF-012 (rutas y orden de salida).* SUMO descarta, en lugar de reordenar, cualquier viaje cuya hora de salida sea menor que la del último que ya cargó.
  Como la encuesta no viene ordenada, la primera corrida perdió unos 23.000 de los 24.600 viajes. Desde entonces los viajes se escriben ordenados y
  hay una prueba que lo verifica.
- *RF-047 (actor simultáneo).* Para que la comparación 3D sea justa, el actor seguido tiene que entrar en los dos escenarios en el mismo instante. Si
  la cola del semáforo bloquea la entrada en un lado, la comparación deja de valer.
- *RNF-USA-001 y RNF-USA-002 (usabilidad).* Toda la operación se hace desde el navegador, en español, con el avance visible en las tareas largas y sin
  mostrar ids ni cadenas de SUMO fuera de las opciones avanzadas.

== Restricciones

- *Datos públicos y abiertos.* Solo se usaron la Encuesta de Movilidad 2023, OpenStreetMap @osm, los siniestros de la Secretaría @siniestros, los POI de
  OSM y las huellas de edificios de Microsoft @msfootprints. No se tuvo acceso a los programas reales de los semáforos de la ciudad; los de la red
  son los que genera netconvert a partir de OpenStreetMap.
- *Herramientas sin costo.* Todo el software es libre: SUMO 1.27, Python 3.11, FastAPI, React, kepler.gl y three.js.
- *Equipos personales.* La simulación completa de Usaquén debía correr en un portátil en minutos; el simulador 3D, en tiempo real.
- *Ventana y alcance.* Se simuló la mañana de 7:00 a 10:00 y solo los viajes con origen y destino en Usaquén. El transporte público se representó
  como caminata, porque modelar buses reales exigía el GTFS del SITP y TransMilenio y quedó fuera del calendario.
- *Calendario académico.* Dieciséis semanas con cuatro integrantes, de las cuales se planearon diez efectivas y se dejó el resto como margen.

== Especificación funcional

El sistema tiene un solo tipo de usuario final, que interactúa desde el navegador, y un desarrollador que corre el pipeline y las pruebas. La
@tabCasosUso resume los casos de uso. La @figFlujoDecision muestra el flujo principal para la decisión de semaforizar, que es el que más se trabajó en
la segunda mitad del proyecto.

#figure(
  table(
    columns: (12%, 25%, 1fr),
    table.header([*Caso*], [*Nombre*], [*Descripción*]),
    [CU-01 a CU-04], [Preparar el escenario base], [El desarrollador corre los notebooks y el pipeline: encuesta limpia, red 3D, zonas y una corrida por
    defecto.],
    [CU-05], [Definir un escenario], [El usuario elige un preset, ajusta conteos, estilo de conducción y cierres viales.],
    [CU-06], [Validar], [Comparar volúmenes con aforos (pendiente).],
    [CU-07], [Ver una simulación], [Cargar una simulación precalculada o una corrida terminada y ver los viajes animados por modo.],
    [CU-08], [Lanzar una corrida], [Ejecutar el escenario definido, seguir su avance y cancelarlo si hace falta.],
    [CU-09], [Consultar una intersección], [Ver los accesos, el tráfico simulado y cómo cambian las luces de un semáforo.],
    [CU-10], [Ajustar un semáforo], [Editar las fases o calcular tiempos óptimos y comparar los programas en una hora punta simulada.],
    [CU-11], [Priorizar cruces], [Ver qué cruces sin semáforo conviene estudiar primero y por qué.],
    [CU-12], [Comparar con y sin semáforo], [Abrir el simulador 3D de un cruce, seguir o manejar un actor y leer el resumen del viaje.],
  ),
  caption: [Casos de uso.],
) <tabCasosUso>

#figure(
  diagram(
    spacing: (0.5cm, 0.55cm),
    node-stroke: 0.8pt,
    node-corner-radius: 3pt,
    node((0, 0), [Abrir el visor (se carga la simulación de la encuesta)]),
    node((0, 1), [Pestaña Semaforizar: lista de cruces por nivel]),
    node((0, 2), [Elegir un cruce (en la lista o en el mapa)]),
    node((0, 3), [Leer el porqué, las cifras y verlo en Street View]),
    node((0, 4), [¿Vale la pena simularlo?], shape: fletcher.shapes.diamond, inset: 3pt),
    node((0, 5), [Ver simulación: hoy y con semáforo (3D)]),
    node((0, 6), [Lanzar y seguir un actor]),
    node((0, 7), [Resumen del viaje y balance del cruce]),
    node((1.6, 4), [Volver a la lista]),
    node((1.6, 7), [Lanzar otro viaje]),
    edge((0, 0), (0, 1), "->"), edge((0, 1), (0, 2), "->"), edge((0, 2), (0, 3), "->"), edge((0, 3), (0, 4), "->"),
    edge((0, 4), (0, 5), "->", [sí]), edge((0, 4), (1.6, 4), "->", [no]), edge((1.6, 4), (0, 1), "->", bend: -40deg),
    edge((0, 5), (0, 6), "->"), edge((0, 6), (0, 7), "->"), edge((0, 7), (1.6, 7), "->"), edge((1.6, 7), (0, 6), "->", bend: 40deg),
  ),
  caption: [Flujo del usuario para estudiar un semáforo nuevo.],
) <figFlujoDecision>
