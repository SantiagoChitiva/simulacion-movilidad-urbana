#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

= Diseño de la Solución

El SDD (anexo C) documenta el diseño completo con las vistas 4+1 @kruchten. Aquí se resumen la arquitectura, las decisiones que más condicionaron
el resultado y la selección de herramientas.

== Arquitectura

El sistema tiene tres capas y un motor externo (@figArquitectura):
- los *notebooks* de exploración producen una sola vez los insumos estables (la red 3D, las zonas y la evidencia descargada);
- el *servicio de simulación*, un paquete de Python, genera la demanda, controla SUMO y expone todo por HTTP y WebSocket;
- el *visor web*, en React, es lo único que ve el usuario.

Todo corre en el mismo computador y el estado vive en archivos, sin base de datos.

#figure(
  diagram(
    spacing: (0.9cm, 0.8cm),
    node-stroke: 0.8pt,
    node-corner-radius: 3pt,
    node((1, 0), [*Visor web* (React, kepler.gl, three.js)], width: 6.5cm),
    node((1, 1), [*API* FastAPI: REST para corridas, semáforos y priorización; WebSocket para el 3D], width: 6.5cm),
    node((0, 2), [Gestor de corridas \ (una a la vez)], width: 3.6cm),
    node((2, 2), [Gestor de comparaciones 3D \ (dos SUMO en paralelo)], width: 3.6cm),
    node((1, 3), [*Pipeline ETL* y módulos de `etl/sumo/`], width: 6.5cm),
    node((1, 4), [*SUMO 1.27* (sumo, duarouter, netconvert, TraCI)], stroke: (dash: "dashed"), fill: luma(245), width: 6.5cm),
    node((0, 5), [Archivos: escenario, corridas, cachés, precalculadas], stroke: (dash: "dashed"), fill: luma(245), width: 4.6cm),
    node((2, 5), [Notebooks CRISP-DM \ (red 3D, zonas, evidencia)], stroke: (dash: "dashed"), fill: luma(245), width: 4.2cm),
    edge((1, 0), (1, 1), "<->", [HTTP / WebSocket]),
    edge((1, 1), (0, 2), "->"), edge((1, 1), (2, 2), "->"),
    edge((0, 2), (1, 3), "->"), edge((2, 2), (1, 3), "->"),
    edge((1, 3), (1, 4), "->"),
    edge((1, 3), (0, 5), "<->"), edge((2, 5), (0, 5), "->", [generan]),
  ),
  caption: [Arquitectura del sistema.],
) <figArquitectura>

== Decisiones de diseño

*Un patrón para cada paso del pipeline.* Cada módulo de `etl/sumo/` sigue la misma forma:
- un `Config` inmutable con sus parámetros;
- un `Result` con lo que produjo;
- un `Stats` que se va llenando mientras corre;
- una excepción propia.

Gracias a eso las pruebas pueden reemplazar cualquier paso por uno falso, y cada error dice en qué paso ocurrió.

*SUMO controlado por TraCI, en saltos.* SUMO y duarouter escriben su avance en bloques cuando su salida va a un archivo, así que no servía para
mostrar una barra de progreso. La simulación se corre con TraCI en saltos de 60 s simulados, con lo que el avance es exacto y el costo es despreciable.
Las rutas informan su avance por la última hora de salida escrita en el archivo.

*Precalculadas comprimidas en el repositorio.* Una corrida completa tarda varios minutos. Cada preset se simuló una vez y sus trayectorias se guardaron
comprimidas (entre 10 y 16 MB por preset), junto con una huella de los insumos. El visor abre la simulación de la encuesta en segundos y avisa si una
precalculada quedó desactualizada.

*Dos SUMO a la par para comparar.* La comparación 3D no simula un escenario y luego el otro. Arranca dos instancias de SUMO con la misma demanda y la
misma semilla y las avanza juntas en pasos de 0,2 s. Así el usuario ve en el mismo segundo qué pasa sin semáforo y con él, y el actor que sigue está
en los dos lados a la vez.

*La comparación de programas corre de verdad.* La primera versión de la pestaña "Comparar" leía el programa elegido pero no lo cargaba en SUMO. El
rediseño cargó cada programa como un archivo adicional (SUMO usa el último programa cargado de cada semáforo) sobre la misma zona y la misma demanda,
con detectores por carril en los accesos para medir colas.

*Archivos en lugar de base de datos.* El sistema es monousuario y SUMO trabaja con archivos. Cada corrida y cada comparación tienen su carpeta, y las
cachés guardan una firma (fecha y tamaño) del archivo del que salen, de modo que se recalculan solas cuando la red cambia.

== Selección de herramientas

La @tabHerramientas compara las alternativas consideradas para las piezas principales con los criterios que salieron del análisis: costo, si encaja
con SUMO y Python, si resuelve lo que se necesitaba sin reimplementarlo y si el equipo podía aprenderla a tiempo.

#figure(
  table(
    columns: (13%, 22%, 1fr, 14%),
    table.header([*Pieza*], [*Alternativas*], [*Criterio decisivo*], [*Elegida*]),
    [Simulador], [SUMO, MATSim, Vissim, Aimsun], [Microscópico, gratuito, controlable desde Python (TraCI) e importa OSM con netconvert. MATSim no ve
    semáforos en detalle; Vissim y Aimsun cuestan licencias.], [SUMO],
    [API], [FastAPI, Flask, Django], [Valida las solicitudes con Pydantic, documenta en `/docs` y trae WebSocket nativo, que el simulador 3D necesita.
    Django era más de lo necesario y Flask exigía piezas adicionales.], [FastAPI @fastapi],
    [Mapa de viajes], [kepler.gl, Leaflet, deck.gl directo], [kepler.gl ya trae la capa de trayectorias animadas, la línea de tiempo y los filtros;
    con Leaflet o deck.gl había que construirlos.], [kepler.gl @keplergl],
    [Escena 3D], [three.js, deck.gl, sumo-gui], [three.js permite una cámara que persigue al actor y construir la escena desde la geometría de la red;
    deck.gl está pensado para vistas cartográficas y sumo-gui no corre en el navegador.], [three.js @threejs],
    [Documentos], [Typst, LaTeX, Word], [Texto plano versionado junto al código, revisable en GitHub y más simple que LaTeX.], [Typst],
  ),
  caption: [Selección de herramientas.],
) <tabHerramientas>
