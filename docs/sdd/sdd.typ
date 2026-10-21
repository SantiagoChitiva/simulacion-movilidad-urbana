// Documento de Diseño de Software (SDD) del proyecto, según la plantilla de la PUJ (vistas 4+1 de Kruchten).
// Compilar desde docs/: python -c "import typst; typst.compile('sdd/sdd.typ', output='sdd/sdd.pdf', root='sdd')"

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#let info = (
  nombreProyecto: "Generación de Escenarios de Movilidad Urbana para la Toma de Decisiones en Localidades de Bogotá",
  nombreEmpresa: "Grupo 3",
  version: "1.0",
  fecha: "20 de octubre de 2026",
  autores: ("Erick Salazar Suárez", "Felipe Andrés Garrido Flores", "Samuel Esteban Campos", "Santiago Chitiva Contreras"),
)

#set document(title: "SDD – " + info.nombreProyecto, author: info.autores)
#set text(lang: "es", size: 11pt)
#show raw: set text(font: "Libertinus Serif", size: 1.25em)
#set par(justify: true)

// ─────────────────────────────────────────── ayudas para los diagramas

#let caja(pos, cuerpo, ..args) = node(pos, cuerpo, stroke: 0.8pt, corner-radius: 3pt, inset: 7pt, ..args)
#let externo(pos, cuerpo, ..args) = node(pos, cuerpo, stroke: (paint: gray, dash: "dashed"), corner-radius: 3pt, inset: 7pt, fill: luma(245), ..args)
#let clase(pos, nombre, atributos, ..args) = node(pos, align(left)[
  #align(center)[*#nombre*]
  #line(length: 100%, stroke: 0.5pt)
  #set text(size: 8pt)
  #atributos
], stroke: 0.8pt, inset: 6pt, width: 4.2cm, ..args)
#let estado(pos, cuerpo, ..args) = node(pos, cuerpo, stroke: 0.8pt, corner-radius: 10pt, inset: 6pt, ..args)

// Diagrama de secuencia sencillo: participantes en columnas y mensajes en filas
#let secuencia(participantes, mensajes, ancho: 2.5cm) = {
  let n = mensajes.len() + 1
  diagram(
    spacing: (0.6cm, 0.62cm),
    node-stroke: 0.8pt,
    ..participantes.enumerate().map(((i, p)) => node((i, 0), text(size: 8.5pt, p), inset: 5pt, corner-radius: 2pt, width: ancho)),
    ..participantes.enumerate().map(((i, _)) => edge((i, 0), (i, n), stroke: (paint: gray, dash: "dashed"))),
    ..mensajes.enumerate().map(((k, m)) => {
      let (desde, hasta, texto) = m
      let estilo = if desde > hasta { "-->" } else { "->" }
      if desde == hasta {
        edge((desde, k + 1), (desde + 0.35, k + 1), (desde, k + 1.4), estilo, text(size: 7.5pt, texto), label-side: left)
      } else {
        edge((desde, k + 1), (hasta, k + 1), estilo, text(size: 7.5pt, texto), label-pos: 0.5)
      }
    }),
  )
}

#let figura(cuerpo, leyenda) = figure({
  set par(justify: false)
  set text(size: 9pt)
  cuerpo
}, caption: leyenda, kind: image, supplement: [Figura])

// ─────────────────────────────────────────── portada

#align(center)[
  #v(2cm)
  #text(size: 18pt, weight: "bold")[#info.nombreProyecto]

  #text(size: 12pt)[#info.nombreEmpresa]
  #v(3.5cm)
  #text(size: 13pt, weight: "bold")[DOCUMENTO DE DISEÑO DE SOFTWARE (SDD)]

  #text(size: 12pt)[#info.fecha]

  #text(size: 12pt)[versión #info.version]
  #v(3cm)
  #image("figures/logo_javeriana.png", width: 9%)
  #v(3cm)
  #text(size: 12pt)[#info.autores.join("\n")]

  #v(1fr)
  #text(size: 11pt)[Pontificia Universidad Javeriana · Facultad de Ingeniería · Ingeniería de Sistemas]
]

#pagebreak()

#set heading(numbering: "1.")
#set page(
  margin: 2.5cm,
  header: context {
    grid(columns: (auto, 1fr), align: (left, right),
      image("figures/logo_javeriana.png", height: 0.9cm),
      text(size: 9pt)[SDD: #info.nombreProyecto])
    line(length: 100%)
  },
  footer: context {
    line(length: 100%)
    grid(columns: (1fr, auto), text(size: 9pt)[*Grupo 3* · Ingeniería de Sistemas PUJ], counter(page).display())
  },
)
#counter(page).update(1)
#show figure.where(kind: table): set figure(supplement: [Tabla])
#set table(align: left)
#show figure.where(kind: table): set block(breakable: true)

= Historial de Cambios

#figure(
  table(
    columns: (auto, auto, 1fr, auto),
    table.header([*Versión*], [*Fecha*], [*Descripción*], [*Responsables*]),
    [1.0], [20/10/2026], [Primera versión del SDD. Describe la arquitectura del sistema tal como está implementada al cierre del Sprint 9:
    pipeline ETL, API, visor web, módulo de semáforos, simulador 3D comparativo y las mejoras de usabilidad de la versión 2.2 del SRS.],
    [Todos],
  ),
  caption: [Historial de cambios.],
)

#pagebreak()
= Tabla de Contenidos
#outline(title: none, depth: 3)

#pagebreak()
= Lista de Figuras
#outline(title: none, target: figure.where(kind: image))

= Lista de Tablas
#outline(title: none, target: figure.where(kind: table))

#pagebreak()

= Introducción

Este documento describe cómo está construido el sistema de generación de escenarios de movilidad para Usaquén. El SRS @ieee830 dice _qué_ debe
hacer el sistema; el SDD explica _cómo_ lo hace: en qué componentes se divide, dónde corre cada uno, cómo se comunican, qué clases tiene cada
componente, qué guarda en disco y cómo navega el usuario por la interfaz. Sigue la estructura de la plantilla de la carrera, que a su vez toma las
vistas 4+1 de Kruchten @kruchten y el estándar IEEE 1016 @ieee1016.

*Alcance.* Se cubre todo lo que está en el repositorio a octubre de 2026:
- los notebooks de exploración que producen la red y la evidencia en `data/processed/`;
- el paquete `simulation-service` (pipeline ETL sobre SUMO @sumo y API en FastAPI @fastapi);
- el visor web `kepler/` (React, kepler.gl @keplergl y three.js @threejs).

El transporte público con GTFS y la validación GEH, que siguen pendientes según el SRS, se mencionan solo donde el diseño ya deja el lugar para
ellos.

*Convenciones.* Los nombres de módulos, clases y funciones se escriben como en el código (`GestorCorridas`, `run_pipeline`). El código y sus
comentarios están en español, igual que este documento. En los diagramas, las cajas con borde punteado son sistemas o servicios externos.

*Relación con otros documentos.* Los requerimientos citados (RF-xxx, RNF-xxx) son los del SRS versión 2.2. Los paquetes de trabajo (F1.1 a F5.6)
son los del SPMP versión 2.2.

= Arquitectura

El sistema es una aplicación local de tres capas con un motor de simulación externo:

+ *Datos y preparación:* notebooks de Jupyter que limpian la encuesta, construyen la red 3D y descargan la evidencia (CRISP-DM, Fases 1 y 2).
+ *Servicio de simulación:* un paquete de Python que genera la demanda, llama a SUMO y expone los resultados por HTTP y WebSocket.
+ *Visor web:* una aplicación de React que muestra los viajes en un mapa, deja parametrizar corridas, analizar semáforos y abrir el simulador 3D.

SUMO no es parte del código del proyecto: se instala con el paquete `eclipse-sumo` de pip y se usa como proceso externo (`sumo`, `duarouter`,
`netconvert`) o controlado por TraCI @traci.

== Vista Lógica

La @figComponentes muestra los componentes y sus dependencias. Las flechas van del componente que usa al usado.

#figura(
  diagram(
    spacing: (0.7cm, 0.62cm),
    edge-stroke: 0.7pt,
    caja((1, 0), [*Visor web* `kepler/src` \ React 18 · Redux], width: 4.2cm),
    caja((0, 1), [Mapa y paneles \ `App.jsx` y paneles], width: 3.8cm),
    caja((2, 1), [Simulador 3D \ three.js · maplibre-gl], width: 3.8cm),
    externo((0, 2), [kepler.gl 3.1 (deck.gl)], width: 3.8cm),
    externo((2, 2), [Teselas OSM, CARTO, Esri \ Street View (embed)], width: 3.8cm),
    caja((1, 3), [*API* `api/api.py` \ FastAPI · REST + WebSocket], width: 4.2cm),
    caja((0, 4), [`GestorCorridas` \ `api/jobs.py`], width: 3.8cm),
    caja((2, 4), [`GestorComparaciones`, `Lado` \ `api/comparacion3d.py`], width: 3.8cm),
    caja((1, 5), [*Pipeline ETL* `etl/etl.py`], width: 4.2cm),
    caja((0, 6), [Demanda y simulación \ `trips`, `demanda`, `duarouter`, `simulation`, `fcd`, `kepler`], width: 3.8cm),
    caja((2, 6), [Semáforos y zonas \ `intersecciones`, `programas_tls`, `priorizacion`, `subred`, `vias`, `telemetria`], width: 3.8cm),
    externo((1, 7), [*SUMO 1.27* \ sumo · duarouter · netconvert \ TraCI · cutRoutes · randomTrips], width: 4.2cm),
    externo((0, 8), [`data/processed/` \ red 3D, TAZ, evidencia], width: 3.8cm),
    externo((2, 8), [Notebooks CRISP-DM], width: 3.8cm),
    edge((1, 0), (0, 1), "->"), edge((1, 0), (2, 1), "->"),
    edge((0, 1), (0, 2), "->"), edge((2, 1), (2, 2), "->"),
    edge((0, 1), (1, 3), "->", [HTTP], label-side: right, label-pos: 0.75),
    edge((2, 1), (1, 3), "->", [WebSocket], label-side: left, label-pos: 0.75),
    edge((1, 3), (0, 4), "->"), edge((1, 3), (2, 4), "->"),
    edge((0, 4), (1, 5), "->"), edge((2, 4), (1, 5), "->"),
    edge((1, 5), (0, 6), "->"), edge((1, 5), (2, 6), "->"),
    edge((0, 6), (1, 7), "->", [subprocesos], label-side: right),
    edge((2, 6), (1, 7), "->", [subprocesos y TraCI], label-side: left),
    edge((0, 6), (0, 8), "->", [lee], label-side: right, bend: -35deg),
    edge((2, 8), (0, 8), "->", [genera]),
  ),
  [Diagrama de componentes.],
) <figComponentes>

*Visor web.* `App.jsx` (componente `Visor`) es dueño del mapa de kepler.gl y del estado global de la pantalla: la corrida cargada, la pestaña
abierta, el cruce elegido, los cierres viales y el tema. Los paneles reciben ese estado por propiedades y avisan los cambios con funciones
(`onElegir`, `onChange`, `onEjecutar`). `api.js` concentra todas las llamadas a la API; `hooks.js` lleva el historial de corridas y el sondeo cada
2 s. El simulador 3D se carga en diferido (`React.lazy`), porque three.js y maplibre pesan varios megabytes y la mayoría de las sesiones no lo
abren.

*API.* Es una sola aplicación FastAPI. Los endpoints se agrupan por tema (@tabEndpoints). Las tareas largas no bloquean la petición:
`GestorCorridas` corre una corrida a la vez en un `ThreadPoolExecutor(1)`, `GestorComparaciones` prepara cada comparación 3D en un hilo y la
comparación de programas corre en un hilo propio. Las pruebas reemplazan los gestores con `app.dependency_overrides`.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Grupo*], [*Endpoints*]),
    [Demanda y corridas], [`GET /demanda/modos`, `/demanda/presets`, `/demanda/estilos`; `POST /simulaciones`, `GET /simulaciones[/{id}]`,
    `POST /simulaciones/{id}/cancelar`, `GET /simulaciones/{id}/kepler-trips`],
    [Precalculadas], [`GET /precalculadas`, `GET /precalculadas/{preset}/kepler-trips` (gzip tal cual, con `X-Tamano-Original`)],
    [Intersecciones], [`GET /intersecciones[/{id}]`, `GET /intersecciones/priorizacion`, `POST /intersecciones/{id}/escenarios`],
    [Programas], [`GET /intersecciones/{id}/programas[/{prog}]`, `PUT .../programas/{prog}`, `POST .../programas/webster`,
    `POST /intersecciones/{id}/comparaciones`, `GET /comparaciones/{id}`],
    [Red], [`GET /red/vias` (vías para elegir cierres)],
    [Simulador 3D], [`POST /cruces/{nodo}/comparacion3d`, `GET /comparacion3d/{id}[/geometria]`, `DELETE /comparacion3d/{id}`,
    `WS /comparacion3d/{id}`],
  ),
  caption: [Endpoints de la API por grupo.],
) <tabEndpoints>

*Pipeline ETL.* `etl/etl.py` orquesta los pasos y los módulos de `etl/sumo/` hacen cada uno. Todos siguen el mismo patrón: un `*Config` inmutable
con los parámetros (y `to_args()` cuando llama a una herramienta de SUMO), un `*Result` con lo producido, un `*Stats` que se va llenando mientras
corre y una excepción `*Error(RuntimeError)` propia. `configuration.py` es la única fuente de rutas y constantes (`ScenarioPaths`, `HORA_INI`,
`HORA_FIN`, `MAX_COPIAS`).

*Bibliotecas principales.* En Python: FastAPI y Pydantic, `traci` y `sumolib` (fijados a la versión 1.27.1 de SUMO), `pyproj` para pasar las
coordenadas de la red a longitud y latitud, `pandas` y `geopandas` en los notebooks. En el visor: React 18, Redux con el reductor de kepler.gl,
three.js 0.169 para la escena 3D y maplibre-gl 4.7 para los minimapas y las vistas del cruce.

== Vista Física

Todo corre en el computador del usuario (@figDespliegue). No hay base de datos ni servidor remoto: el estado vive en archivos. Los únicos servicios
externos son de solo lectura y se usan desde el navegador: las teselas de los mapas base y el Street View embebido. La evidencia de priorización
(siniestros, colegios, edificios) se descarga una vez con `python -m etl.sumo.evidencia` y queda versionada.

#figura(
  diagram(
    spacing: (1.4cm, 1.1cm),
    edge-stroke: 0.7pt,
    node((0, 0), [*Navegador* (Chrome, Edge, Firefox) \ visor React + kepler.gl + three.js], stroke: 0.8pt, inset: 8pt, width: 5.4cm),
    node((2, 0), [*Servicios de mapas* \ CARTO · OSM · Esri · Google], stroke: (paint: gray, dash: "dashed"), fill: luma(245), inset: 8pt, width: 4.6cm),
    node((0, 1.3), [*Vite* (desarrollo, puerto 5173) \ sirve el visor y reenvía `/api/*`], stroke: 0.8pt, inset: 8pt, width: 5.4cm),
    node((0, 2.6), [*uvicorn* (puerto 8000) \ `api.api:app` + hilos de corridas y comparaciones], stroke: 0.8pt, inset: 8pt, width: 5.4cm),
    node((2, 2.6), [*Procesos SUMO* \ uno por corrida o por programa; \ dos por comparación 3D (TraCI)], stroke: 0.8pt, inset: 8pt, width: 4.6cm),
    node((0, 3.9), [*Sistema de archivos* \ `scenarios/`, `runs/`, `cache/`, `precalculadas/`, `data/processed/`], stroke: 0.8pt, inset: 8pt, width: 5.4cm),
    edge((0, 0), (2, 0), "->", [teselas, embed]),
    edge((0, 0), (0, 1.3), "<->", [HTTP / WebSocket]),
    edge((0, 1.3), (0, 2.6), "<->", [proxy]),
    edge((0, 2.6), (2, 2.6), "<->", [TraCI]),
    edge((0, 2.6), (0, 3.9), "<->"),
    edge((2, 2.6), (0, 3.9), "->", [salidas XML]),
  ),
  [Diagrama de despliegue.],
) <figDespliegue>

Para usar el sistema se instalan dos entornos independientes: el de Python 3.11 del servicio (`pip install -e ".[dev]"`, que trae SUMO) y el de
Node del visor (`npm install`). El visor necesita una clave de Mapbox en `kepler/.env` solo para los estilos de mapa de Mapbox; los estilos por
defecto del tema claro y del oscuro (CARTO Positron y Dark Matter) no la piden.

== Vista de Procesos

*Corrida parametrizada.* La @figPipeline muestra los pasos de `run_pipeline`. Cada etapa informa su avance a `GestorCorridas`, que lo traduce a
una franja del avance global y lo guarda en `estado.json` (como máximo una escritura cada 2 s). Una señal de cancelación (`threading.Event`) llega
hasta los subprocesos. Si se activa, el trabajador borra todo lo de la corrida menos `estado.json`.

#figura(
  diagram(
    spacing: (0.55cm, 0.75cm),
    edge-stroke: 0.7pt,
    node((0, 0), [], shape: circle, fill: black, radius: 5pt),
    caja((0, 1), [Generar viajes (`trips.generate_trips`): encuesta × `fexp`, preset y conteos, ordenados por salida]),
    caja((0, 2), [Rutas con `duarouter` (`--ignore-errors --repair`); avance por el último `depart` escrito]),
    caja((0, 3), [SUMO por TraCI en saltos de 60 s; cierres y estilo como _additional files_]),
    caja((0, 4), [FCD #sym.arrow GeoJSON de trayectorias para kepler (`[lon, lat, z, t]`); se borra el FCD]),
    caja((0, 5), [`estado.json` = terminado; el visor descarga los viajes]),
    node((1.6, 3), [¿cancelada?], shape: fletcher.shapes.diamond, stroke: 0.8pt, inset: 4pt),
    caja((3, 3), [Borrar la corrida \ (salvo `estado.json`)]),
    edge((0, 0), (0, 1), "->"), edge((0, 1), (0, 2), "->"), edge((0, 2), (0, 3), "->"), edge((0, 3), (0, 4), "->"),
    edge((0, 4), (0, 5), "->"),
    edge((0, 2), (1.6, 3), "-->", bend: 20deg), edge((1.6, 3), (3, 3), "->", [sí]),
  ),
  [Actividades de una corrida del pipeline.],
) <figPipeline>

Los estados de una corrida y sus transiciones están en la @figEstadosCorrida. El visor consulta el estado cada 2 s y, al llegar a `terminado`,
carga la corrida en el mapa.

#figura(
  diagram(
    spacing: (1.1cm, 0.9cm),
    edge-stroke: 0.7pt,
    estado((0, 0), [en_cola]), estado((1, 0), [generando_demanda]), estado((2, 0), [ruteando]), estado((3, 0), [simulando]),
    estado((4, 0), [exportando]), estado((4, 1), [terminado]), estado((2, 1), [cancelando]), estado((2, 2), [cancelada]),
    estado((3, 2), [error]),
    edge((0, 0), (1, 0), "->"), edge((1, 0), (2, 0), "->"), edge((2, 0), (3, 0), "->"), edge((3, 0), (4, 0), "->"),
    edge((4, 0), (4, 1), "->"), edge((3, 0), (2, 1), "->", [cancelar]), edge((2, 1), (2, 2), "->"),
    edge((3, 0), (3, 2), "->", [falla], label-side: left),
  ),
  [Estados de una corrida.],
) <figEstadosCorrida>

*Comparación 3D en vivo.* Al abrir el simulador, `run_escenario_semaforo` recorta la zona (350 m), arma la demanda (viajes reales recortados con
`cutRoutes.py` más tráfico de fondo de `randomTrips.py`) e instala el semáforo propuesto con netconvert. Cuando el visor se conecta por WebSocket,
`correr_comparacion` arranca dos SUMO, uno por escenario, y los avanza a la par en pasos de 0,2 s (@figLockstep). La ejecución tiene tres
partes:
+ 240 s de calentamiento;
+ en cada vuelta: aplicar los comandos del visor, avanzar los dos lados, armar el frame y enviarlo;
+ acumular el viaje del actor seguido; cuando termina en los dos lados, mandar el resumen.

#figura(
  diagram(
    spacing: (0.8cm, 0.55cm),
    edge-stroke: 0.7pt,
    caja((1, 0), [Arrancar SUMO A (sin semáforo) y SUMO B (con semáforo), semilla 42], width: 8cm),
    caja((1, 1), [Calentamiento: 240 s simulados en saltos de 20 s], width: 8cm),
    caja((1, 2), [Leer comandos: pausa, velocidad, seguir, manual, giro, *inyectar*], width: 8cm),
    caja((1, 3), [Avanzar A y B (pasos de 0,2 s según la velocidad)], width: 8cm),
    caja((1, 4), [Por lado: actores, luces, métricas, balance y telemetría del actor], width: 8cm),
    caja((1, 5), [Publicar el frame (cola de 8; si está llena se descarta el más viejo)], width: 8cm),
    caja((1, 6), [Acumular el viaje; si terminó en A y B, publicar `resumen_viaje`], width: 8cm),
    externo((2, 2), [`inyectar_en_lados`: validar la ruta en A y B, liberar la entrada y agregar en los dos o en ninguno], width: 4.2cm),
    node((0, 2), []), node((0, 6), []),
    edge((1, 0), (1, 1), "->"), edge((1, 1), (1, 2), "->"), edge((1, 2), (1, 3), "->"), edge((1, 3), (1, 4), "->"),
    edge((1, 4), (1, 5), "->"), edge((1, 5), (1, 6), "->"),
    edge((1, 6), (0, 6), (0, 2), (1, 2), "->", [mientras siga activa], label-side: left, label-pos: 0.45),
    edge((1, 2), (2, 2), "->"),
  ),
  [Bucle sincronizado (lockstep) de la comparación 3D.],
) <figLockstep>

= Diseño Detallado

== Estructura

*Pipeline y demanda.* La @figClasesEtl muestra las clases que definen una corrida. `DemandaConfig` combina un preset (una lista de reglas de
transferencia modal) con los conteos que pide el usuario; `TripGenerationConfig` la usa para expandir la encuesta. `ScenarioPaths` resuelve dónde
queda cada archivo: en `scenarios/<nombre>/` para la corrida por defecto o en `runs/<id>/` para una corrida lanzada desde la API.

#figura(
  diagram(
    spacing: (1.4cm, 1.1cm),
    edge-stroke: 0.7pt,
    clase((0, 0), [ScenarioPaths], [
      root, run\_dir: Path \ tsv, net, taz, routes, vehroute, fcd, kepler\_trips \ + from\_name(nombre, run\_id)
    ]),
    clase((1, 0), [TripGenerationConfig], [
      tsv\_path, output\_path: Path \ hora\_ini, hora\_fin: int \ max\_copias: int \ demanda: DemandaConfig
    ]),
    clase((2, 0), [DemandaConfig], [
      preset: Preset \ conteos: dict[TransportMode, int]
    ]),
    clase((2, 1), [ReglaTransferencia], [
      desde, hacia: TransportMode \ fraccion: float \ rango de duración
    ]),
    clase((0, 1), [Corrida], [
      id, preset, estado, avance \ conteos, semilla, estilo, cierres \ resultado, error
    ]),
    clase((1, 1), [GestorCorridas], [
      \- ejecutor: ThreadPoolExecutor(1) \ + crear(...) #sym.arrow Corrida \ + cancelar(id) \ + paths(id)
    ]),
    clase((1, 2), [CierreVial], [
      edge\_id: str \ hora\_inicio\_s, hora\_fin\_s \ modos\_afectados
    ]),
    edge((1, 0), (2, 0), "->", [usa]), edge((2, 0), (2, 1), "-|>", [preset = reglas], label-side: left),
    edge((1, 1), (0, 1), "->", [administra]), edge((1, 1), (0, 0), "->", [rutas]), edge((0, 1), (1, 2), "->", [0..\*]),
  ),
  [Clases del pipeline y de las corridas.],
) <figClasesEtl>

*Semáforos.* Un `Semaforo` sale de cada `tlLogic` de la red: sus accesos (`Acceso`), sus fases (`Fase`, con la luz de cada acceso) y los enlaces
que relacionan cada letra del estado con un acceso y un giro. Esa relación es la que permite describir las fases en palabras y editar con un clic
la luz de un acceso. `ProgramaTLS` es la versión editable y se guarda como _additional file_. `programa_webster` construye uno nuevo sobre las
mismas fases. `PuntajeCruce` es el resultado de la priorización para un cruce sin semáforo (@figClasesSemaforos).

#figura(
  diagram(
    spacing: (1.3cm, 1.1cm),
    edge-stroke: 0.7pt,
    clase((0, 0), [Semaforo], [
      id, tipo, programa, ciclo \ lon, lat, calles, nombre \ enlaces: [{indice, acceso, giro}]
    ]),
    clase((1, 0), [Acceso], [
      edge, calle, clase \ carriles, velocidad\_kmh \ volumen, volumen\_hora
    ]),
    clase((0, 1), [Fase], [
      duracion: float \ estado: str (una letra por enlace) \ luces: {edge #sym.arrow luz}
    ]),
    clase((1, 1), [ProgramaTLS], [
      tl\_id, program\_id, tipo, offset \ fases: [FasePrograma] \ + ciclo\_s
    ]),
    clase((2, 0), [PuntajeCruce], [
      nodo\_id, nivel, puntaje\_total \ evidencias, contexto, medida \ tipo\_vias, brazos, siniestros \ colegios, salud, distancia\_semaforo\_m
    ]),
    clase((2, 1), [ComparacionProgramaConfig], [
      zona\_net, demanda, vtypes \ accesos, programa \ semilla, inicio, duracion\_s
    ]),
    edge((0, 0), (1, 0), "->", [1..\*]), edge((0, 0), (0, 1), "->", [1..\*]),
    edge((1, 1), (0, 1), "-->", [se lee de]), edge((2, 1), (1, 1), "->", [0..1]),
  ),
  [Clases del módulo de semáforos.],
) <figClasesSemaforos>

*Simulador 3D.* `GestorComparaciones` crea y cierra las comparaciones (máximo dos a la vez) y libera las que llevan 180 s sin actividad. Cada
`Comparacion` guarda su carpeta, el estado de preparación, la cola de comandos del visor y los parámetros en vivo. Durante la conexión, cada
`Lado` envuelve un SUMO con su conexión TraCI y lleva lo que se mide en ese escenario. `_ViajeEgo` acumula el viaje del actor seguido en los dos
lados. Las funciones de `telemetria.py` son puras (sin TraCI), lo que permite probarlas con datos inventados (@figClases3d).

#figura(
  diagram(
    spacing: (1.3cm, 1.1cm),
    edge-stroke: 0.7pt,
    clase((0, 0), [GestorComparaciones], [
      \+ crear(nodo, lon, lat, ...) \ + obtener(id) / cerrar(id) \ máximo 2, timeout 180 s
    ]),
    clase((1, 0), [Comparacion], [
      cid, run\_dir, estado, etapa, info \ comandos: Queue \ velocidad, pausada, manual
    ]),
    clase((0, 1), [Lado], [
      nombre ("a" | "b"), con: TraCI \ balance, conflictos, colisiones \ + avanzar(t), actores(dt) \ + telemetria(ego) \ + despejar\_entrada(edge)
    ]),
    clase((1, 1), [\_ViajeEgo], [
      ego, entrada, reintentos \ viajes: {lado #sym.arrow viaje} \ + reintentar\_entrada(...) \ + actualizar(...) #sym.arrow resumen
    ]),
    clase((2, 1), [telemetria.py], [
      ttc, drac, pet\_cruce \ indice\_riesgo, clasificar\_accion \ acumular\_viaje, comparar\_viajes \ actualizar\_balance
    ]),
    edge((0, 0), (1, 0), "->", [0..2]), edge((1, 0), (0, 1), "->", [2 en vivo]), edge((0, 1), (1, 1), "<-", [alimenta]),
    edge((1, 1), (2, 1), "->", [usa]), edge((0, 1), (2, 1), "->", [usa], bend: -25deg),
  ),
  [Clases del simulador 3D comparativo.],
) <figClases3d>

*Visor.* Los componentes de React se organizan como un árbol con `Visor` en la raíz (@tabComponentes). No hay un almacén global propio: el único
estado en Redux es el de kepler.gl, y lo demás vive en `Visor` o en cada panel.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Componente*], [*Responsabilidad*]),
    [`Visor` (`App.jsx`)], [Mapa, capas (viajes, semáforos, priorización, anillo de selección, vías y cierres), tema, pestañas y apertura del
    simulador.],
    [`PanelDemanda`], [Presets, conteos por modo, escala, semilla, estilo, historial de corridas; avisa cuando hay cierres.],
    [`FichaInterseccion`, `TablaComparacion`], [Ficha del semáforo en palabras, editor visual de fases, Webster y comparación de programas.],
    [`PanelCierres`], [Cierres elegidos con un clic en la capa de vías, franjas horarias y lista.],
    [`PanelSemaforizacion`, `VistaCruce`, `MapaCruce`], [Lista de cruces por nivel, búsqueda, filtros y tarjeta con Street View, satélite y mapa.],
    [`Simulador3D`, `Escena3D`, `HUD`, `Minimapa`, `ResumenComparacion`], [Ciclo de vida de la comparación, dos escenas three.js, datos del
    actor, un minimapa por escenario y el resumen del viaje.],
    [`TarjetaActividad`, `LeyendaModos`], [Avance y cancelación de corridas y descargas; leyenda de modos y botones de capas.],
  ),
  caption: [Componentes del visor.],
) <tabComponentes>

== Comportamiento

*Lanzar una corrida parametrizada* (RF-021, RF-026). El visor no espera a que la corrida termine: recibe el identificador y pregunta por el estado
cada 2 s (@figSecCorrida).

#figura(
  secuencia(
    ([Usuario], [PanelDemanda], [API], [GestorCorridas], [run_pipeline]),
    (
      (0, 1, [Ejecutar simulación]),
      (1, 2, [POST /simulaciones]),
      (2, 3, [crear(preset, conteos, cierres)]),
      (3, 4, [submit (hilo)]),
      (3, 2, [Corrida(id, en_cola)]),
      (2, 1, [202 {id}]),
      (4, 3, [on_progreso(etapa, avance)]),
      (1, 2, [GET /simulaciones/{id} (cada 2 s)]),
      (2, 1, [estado, avance]),
      (4, 3, [fin: resultado]),
      (1, 2, [GET .../kepler-trips]),
      (1, 0, [viajes en el mapa]),
    ),
  ),
  [Secuencia de una corrida parametrizada.],
) <figSecCorrida>

*Comparar con y sin semáforo en 3D* (RF-033, RF-047, RF-048). La preparación es asíncrona; la simulación en vivo va por WebSocket. Al lanzar un
actor, el servidor lo agrega en los dos lados en el mismo paso o no lo agrega (@figSec3d).

#figura(
  secuencia(
    ([Simulador3D], [API], [GestorComp.], [correr_comparacion], [SUMO A / B]),
    (
      (0, 1, [POST /cruces/{n}/comparacion3d]),
      (1, 2, [crear (hilo: recorte, demanda, semáforo)]),
      (0, 1, [GET /comparacion3d/{id} hasta "lista"]),
      (0, 1, [GET .../geometria]),
      (0, 1, [WS /comparacion3d/{id}]),
      (1, 3, [hilo con cola de frames]),
      (3, 4, [arrancar dos SUMO + calentamiento]),
      (3, 0, [frame (cada paso)]),
      (0, 3, [{inyectar: tipo, acceso, giro}]),
      (3, 4, [validar ruta, despejar, vehicle.add ×2]),
      (3, 0, [{tipo: ego}]),
      (3, 4, [simulationStep ×2]),
      (3, 0, [{tipo: resumen_viaje, a, b, balance}]),
    ),
  ),
  [Secuencia de la comparación 3D.],
) <figSec3d>

*Comparar programas de un semáforo existente* (RF-031). Se recorta la zona una vez y se corre una hora punta por programa, con la misma demanda y
la misma semilla. Los resultados llegan programa por programa, así que el visor puede mostrar los primeros mientras los demás se simulan
(@figSecProgramas).

#figura(
  secuencia(
    ([Ficha (Comparar)], [API], [run_comparacion_programas], [correr_programa], [sumo]),
    (
      (0, 1, [POST .../comparaciones {actual, webster}]),
      (1, 1, [programa_webster(volúmenes)]),
      (1, 2, [hilo]),
      (2, 2, [recortar zona y demanda]),
      (2, 3, [programa = None (actual)]),
      (3, 4, [sumo -a detectores (E2)]),
      (3, 2, [métricas (tripinfo, E2)]),
      (2, 3, [programa = webster]),
      (3, 4, [sumo -a detectores, programa]),
      (3, 2, [métricas]),
      (0, 1, [GET /comparaciones/{id} (cada 2 s)]),
      (1, 0, [programas con métricas]),
    ),
  ),
  [Secuencia de la comparación de programas.],
) <figSecProgramas>

== Persistencia

El sistema no usa una base de datos (el SRS lo justifica en la sección 3.6): es monousuario y sus datos son archivos que SUMO lee y escribe. La
@figPersistencia los modela como clases con el estereotipo «archivo» o «carpeta» y la @tabArchivos explica cuáles se versionan.

#figura(
  diagram(
    spacing: (1.3cm, 1.1cm),
    edge-stroke: 0.7pt,
    clase((0, 0), [«carpeta» scenarios/default], [
      usaquen\_3d.net.xml \ usaquen.taz.xml \ viajes\_usaquen\_internos.tsv \ usaquen-sim.sumocfg \ nombres\_vias.json \ programa\_<tl>\_<id>.xml
    ]),
    clase((1, 0), [«carpeta» runs/<id>], [
      estado.json \ \*.trips.xml, \*.rou.xml \ output/: vehroute, statistics \ kepler trips, volumenes.json
    ]),
    clase((2, 0), [«carpeta» precalculadas/<preset>], [
      trips.geojson.gz (mtime 0) \ volumenes.json \ meta.json (sha256 de insumos)
    ]),
    clase((0, 1), [«carpeta» cache/], [
      semaforos.json \ priorizacion.json \ vias.json \ (firma: fecha y tamaño)
    ]),
    clase((1, 1), [«carpeta» runs/sem-<id>], [
      zona.net.xml, zona\_tls.net.xml \ zona.rou.xml, fondo\_\*.trips.xml \ lado\_a/b.sumocfg
    ]),
    clase((2, 1), [«carpeta» runs/comp-<id>], [
      zona.net.xml, demanda \ <programa>/tripinfo.xml \ <programa>/e2.xml, programa.add.xml
    ]),
    edge((1, 0), (0, 0), "->", [usa la red y la encuesta]),
    edge((2, 0), (0, 0), "->", [huella de], bend: -20deg),
    edge((0, 1), (0, 0), "->", [se deriva de]),
    edge((1, 1), (1, 0), "->", [recorta rutas de]),
    edge((2, 1), (1, 0), "->", [recorta rutas de]),
  ),
  [Modelo de persistencia en archivos.],
) <figPersistencia>

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Ubicación*], [*¿Se versiona?*], [*Motivo*]),
    [`scenarios/default/`], [Sí (menos los programas del usuario)], [Insumos del escenario base; reproducen cualquier corrida.],
    [`precalculadas/`], [Sí, comprimido], [Abren el visor en segundos; `meta.json` dice si quedaron desactualizadas.],
    [`data/processed/`], [Sí], [Red 3D, TAZ y evidencia descargada una sola vez.],
    [`runs/`, `cache/`], [No], [Se regeneran; las corridas pueden pesar cientos de megabytes.],
  ),
  caption: [Archivos del sistema y control de versiones.],
) <tabArchivos>

Las cachés se invalidan solas: guardan una firma con la fecha y el tamaño del archivo del que salen (y una versión del análisis en el caso de la
priorización). Si la red cambia, la próxima consulta recalcula. Los procesos que escriben a la vez nunca comparten archivo: cada corrida y cada
comparación tienen su carpeta.

== Interfaz de Usuario

La @figNavegacion resume cómo se navega el visor. El mapa siempre está de fondo. La columna derecha tiene cuatro pestañas y el simulador 3D se
abre a pantalla completa encima de todo. La versión 2.2 del SRS (RNF-USA-002) agrega dos reglas a este diseño:
- *Tema:* claro por defecto y oscuro con un botón; el simulador 3D siempre es oscuro.
- *Lenguaje:* lo técnico (cadenas de SUMO, ids de edges, semillas) queda en "Opciones avanzadas".

#figura(
  diagram(
    spacing: (0.9cm, 0.85cm),
    edge-stroke: 0.7pt,
    caja((1, 0), [*Mapa* \ viajes animados · leyenda · tema]),
    caja((0, 1), [Demanda \ presets, conteos, corridas]),
    caja((1, 1), [Intersección \ (clic en un semáforo)]),
    caja((2, 1), [Cierres \ capa de vías]),
    caja((3, 1), [Semaforizar \ lista por nivel]),
    caja((1, 2), [Ficha · Configurar · Comparar]),
    caja((2, 2), [Vía elegida \ #sym.arrow lista de cierres]),
    caja((3, 2), [Tarjeta del cruce \ porqué · cifras · Street View]),
    caja((3, 3), [*Simulador 3D* \ sin semáforo | con semáforo]),
    caja((2, 4), [Lanzar y seguir \ (Auto / Manual)]),
    caja((3, 4), [Resumen \ viaje + balance del cruce]),
    edge((1, 0), (0, 1), "->"), edge((1, 0), (1, 1), "->"), edge((1, 0), (2, 1), "->"), edge((1, 0), (3, 1), "->"),
    edge((1, 1), (1, 2), "->"), edge((2, 1), (2, 2), "->"), edge((3, 1), (3, 2), "->", [clic en la lista \ o en el mapa]),
    edge((2, 2), (0, 1), "->", [Ir a simular], bend: 30deg),
    edge((3, 2), (3, 3), "->", [Ver simulación]), edge((3, 3), (2, 4), "->"), edge((2, 4), (3, 4), "->", [fin del viaje]),
    edge((3, 4), (2, 4), "->", [lanzar otro], bend: 30deg),
  ),
  [Navegación del visor.],
) <figNavegacion>

= Referencias

#bibliography("referencias.yml", title: none, style: "ieee", full: false)
