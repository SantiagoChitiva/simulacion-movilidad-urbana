#import "@preview/fletcher:0.5.8": diagram, node, edge

= Arquitectura del sistema

== Diagrama arquitectónico

El sistema es una aplicación cliente--servidor local. El navegador carga el visor (`kepler`); el servidor de desarrollo de Vite reenvía `/api/*` (HTTP y WebSocket) a la API de `simulation-service` en el puerto 8000. La API orquesta herramientas de SUMO como subprocesos y lee y escribe en el sistema de archivos.

#figure(
  diagram(
    node-stroke: 0.6pt,
    node-inset: 6pt,
    spacing: (9mm, 10mm),
    node((0, 0), [*Navegador*\ React + kepler.gl\ three.js + maplibre], name: <nav>),
    node((1, 0), [*Vite dev server*\ proxy `/api/*`\ (HTTP y WS)], name: <vite>),
    node((2, 0), [*API FastAPI*\ `api.api` :8000], name: <api>),
    node((0, 1), [*Análisis de red*\ intersecciones,\ priorización, Webster], name: <ana>),
    node((1, 1), [*GestorComparaciones*\ hilos + TraCI], name: <comp>),
    node((2, 1), [*GestorCorridas*\ `ThreadPool(1)`], name: <jobs>),
    node((1, 2), [*SUMO*\ sumo, duarouter, netconvert,\ cutRoutes, randomTrips], name: <sumo>),
    node((2, 2), [*Pipeline ETL*\ `etl.etl`], name: <etl>),
    node((0, 2), [], stroke: none, name: <vacio>),
    node((1, 3), [*Sistema de archivos*\ `scenarios/` `runs/` `cache/`\ `precalculadas/` `data/processed/`], name: <fs>),
    edge(<nav>, <vite>, "<->", [HTTP / WS]),
    edge(<vite>, <api>, "<->"),
    edge(<api>, <jobs>, "->"),
    edge(<api>, <comp>, "->"),
    edge(<api>, <ana>, "->"),
    edge(<jobs>, <etl>, "->"),
    edge(<comp>, <sumo>, "<->", [TraCI]),
    edge(<etl>, <sumo>, "->", [subproceso]),
    edge(<ana>, <fs>, "<-"),
    edge(<sumo>, <fs>, "<->"),
    edge(<etl>, <fs>, "->"),
  ),
  caption: [Vista de componentes y conexiones del sistema.],
) <fig-arquitectura>

La @fig-arquitectura se organiza en cuatro capas:

#figure(
  table(
    columns: (auto, 1fr),
    [Capa], [Responsabilidad],
    [Presentación], [`kepler/`: mapa kepler.gl, paneles de demanda, ficha de intersección, semaforización y simulador 3D (carga diferida).],
    [Interfaz (API)], [`api/api.py`: validación de peticiones (Pydantic), códigos HTTP, WebSocket. No contiene lógica de negocio pesada.],
    [Orquestación], [`api/jobs.py` (corridas en segundo plano) y `api/comparacion3d.py` (comparaciones 3D con TraCI).],
    [Dominio y datos], [`etl/`: generación de demanda, ruteo, simulación, exportación, análisis de intersecciones y priorización, escena 3D, telemetría.],
  ),
  caption: [Capas de la arquitectura.],
)

== Estilo de arquitectura

*Cliente--servidor con servicio monolítico modular.* Se eligió un único proceso FastAPI con módulos internos bien separados (API → orquestación → ETL) en lugar de microservicios, porque el sistema se ejecuta en una sola máquina, lo costoso es SUMO y no el enrutamiento, y un solo proceso simplifica la cancelación, el reparto de rutas de archivos y las pruebas (@sec-adrs, ADR-01).

Dentro del servicio conviven tres estilos:

- *Tubería de etapas (_pipes and filters_)* para el ETL: cada etapa lee archivos de la anterior y escribe los propios (TSV → `trips.xml` → `rou.xml` → FCD → GeoJSON). Las etapas son funciones con `Config`/`Result`/`Stats` y se pueden ejecutar solas.
- *Trabajos asíncronos con cola de un solo trabajador* para las corridas largas: la API responde `202 Accepted` y el cliente consulta el estado cada 2 s (_polling_).
- *Flujo en tiempo real por WebSocket* para el simulador 3D: dos instancias de SUMO avanzan en _lockstep_ y el servidor emite un _frame_ por paso.

Del lado del visor se usa una arquitectura de componentes React con estado local (`useState`) y un _store_ Redux solo para kepler.gl, que lo exige. El componente `App.jsx` (`Visor`) es el dueño de los datos del mapa; los paneles reciben propiedades y devuelven eventos.

== Flujos globales

=== Simulación parametrizada

El usuario ajusta la demanda y lanza una corrida. El flujo atraviesa las cuatro etapas del pipeline, con el avance global repartido en franjas.

#figure(
  diagram(
    node-stroke: 0.6pt,
    node-inset: 5pt,
    spacing: (8mm, 10mm),
    node((0, 0), [Visor\ `POST /simulaciones`], name: <a>),
    node((1, 0), [API valida y encola\ → `202 {id}`], name: <b>),
    node((2, 0), [Generar demanda\ 0--2 %], name: <c>),
    node((3, 0), [`duarouter`\ 2--15 %], name: <d>),
    node((3, 1), [SUMO / TraCI\ 15--85 %], name: <e>),
    node((2, 1), [Exportar kepler\ 85--100 %], name: <f>),
    node((1, 1), [Visor descarga\ `GET .../kepler-trips`], name: <h>),
    node((0, 1), [Visor consulta\ `GET /simulaciones/{id}`\ cada 2 s], name: <g>),
    edge(<a>, <b>, "->"),
    edge(<b>, <c>, "->"),
    edge(<c>, <d>, "->"),
    edge(<d>, <e>, "->"),
    edge(<e>, <f>, "->"),
    edge(<f>, <h>, "->"),
    edge(<g>, <a>, "-->"),
  ),
  caption: [Flujo de una simulación parametrizada y franjas de avance (`FRANJAS_ETAPA`).],
) <fig-flujo-sim>

+ `POST /simulaciones` valida el cuerpo (total de viajes entre 1 y 100.000) y devuelve `202` con el `id` de la corrida.
+ `GestorCorridas` guarda `runs/<id>/estado.json` y envía el trabajo a un `ThreadPoolExecutor(1)`: solo una corrida pesada corre a la vez y las demás quedan en estado `en_cola`.
+ `run_pipeline` genera los viajes (ordenados por hora de salida), llama a `duarouter`, simula con SUMO bajo TraCI y exporta el GeoJSON de kepler.
+ En cada etapa se informa el avance, que se mapea a la franja global. Una cancelación (`threading.Event`) llega hasta el subproceso y borra todos los archivos de la corrida menos `estado.json`.
+ Al terminar, el FCD (muy pesado) se elimina; el visor descarga los viajes y los reemplaza en kepler.

=== Simulación precalculada

Los cuatro presets con conteos por defecto se simulan una vez (`python -m etl.precalculadas`) y se versionan en `simulation-service/precalculadas/<preset>/`. El visor, al abrir, consulta `GET /precalculadas`; si el panel de demanda coincide exactamente con una, ofrece «Cargar simulación» y la API entrega el `.gz` tal cual con `Content-Encoding: gzip`, de modo que el navegador descomprime y no hay que simular.

=== Análisis de intersecciones y priorización

`GET /intersecciones` y `GET /intersecciones/priorizacion` combinan un análisis de la red que no depende de la corrida (catálogo de semáforos, agrupación de cruces, evidencia), guardado en `cache/`, con los volúmenes de la corrida elegida. Los cálculos que dependen de la corrida (puntaje y niveles) se rehacen en cada consulta porque son baratos.

=== Comparación 3D de un cruce

#figure(
  diagram(
    node-stroke: 0.6pt,
    node-inset: 5pt,
    spacing: (8mm, 12mm),
    node((0, 0), [`POST /cruces/{nodo}/`\ `comparacion3d` → `202 {id}`], name: <a>),
    node((1, 0), [Hilo de preparación:\ recorte de red, demanda,\ semáforo, geometría], name: <b>),
    node((2, 0), [`GET /comparacion3d/{id}`\ hasta `lista`], name: <c>),
    node((2, 1), [`GET .../geometria`\ → escena three.js], name: <d>),
    node((1, 1), [`WS /comparacion3d/{id}`\ frames y comandos], name: <e>),
    node((0, 1), [Hilo `comp`: lado A y\ lado B en lockstep], name: <f>),
    edge(<a>, <b>, "->"),
    edge(<b>, <c>, "-->"),
    edge(<c>, <d>, "->"),
    edge(<d>, <e>, "->"),
    edge(<e>, <f>, "<->"),
  ),
  caption: [Flujo de preparación y ejecución del simulador 3D comparativo.],
) <fig-flujo-3d>

La preparación (`netconvert`, `cutRoutes.py`, `randomTrips.py`) corre en un hilo aparte y puede tardar decenas de segundos. Al conectarse el WebSocket se arranca un segundo hilo que lanza los dos SUMO, los calienta 240 s simulados y emite un _frame_ por paso (0,2 s simulados). Al cerrar la ventana, el directorio `runs/sem-<id>/` se borra; si nadie se conecta en 180 s, la comparación expira.
