#import "uml.typ": *

== Vista física del sistema <sec-vista-fisica>

La vista física muestra el hardware que interviene y en qué nodo se instala cada componente de la @sec-vista-logica. El sistema es una herramienta local: casi todo corre en un único equipo (estación de trabajo del usuario o del desarrollador), y solo las teselas de mapa y los datos abiertos vienen de servidores externos.

=== Diagrama de despliegue

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (6mm, 5mm),
      rotulo((1, 0), [«dispositivo» Equipo del usuario (Linux o Windows)], name: <lequipo>),
      // Navegador (filas 1-2)
      rotulo((1, 1), [«entorno de ejecución» Navegador web], name: <lnav>),
      componente((0, 2), [*Visor web*\ React, `App`,\ paneles], name: <bvisor>),
      componente((1, 2), [*kepler.gl*\ Redux,\ styled-components], name: <bkgl>),
      componente((2, 2), [*Simulador 3D*\ three.js,\ maplibre-gl], name: <b3d>),
      node(enclose: (<bvisor>, <bkgl>, <b3d>, <lnav>), snap: false, inset: 5pt, stroke: 0.6pt, name: <bnav>),
      // Node.js (filas 3-4)
      rotulo((1, 3), [«entorno» Node.js], name: <lnode>),
      componente((1, 4), [*Vite dev server*\ proxy `/api/*`\ puerto 5173 (por defecto)], name: <bvite>),
      node(enclose: (<bvite>, <lnode>), snap: false, inset: 5pt, stroke: 0.6pt, name: <bnode>),
      // Python (filas 5-6)
      rotulo((1, 5), [«entorno» Python ≥ 3.11 (venv)], name: <lpy>),
      componente((0, 6), [*API FastAPI*\ `api.api` (uvicorn)\ puerto 8000], name: <bapi>),
      componente((1, 6), [*Gestores*\ `GestorCorridas`\ `GestorComparaciones`], name: <bges>),
      componente((2, 6), [*ETL y análisis*\ `etl/`, `etl/sumo/`\ `traci`, `sumolib`, `pyproj`], name: <betl>),
      node(enclose: (<bapi>, <bges>, <betl>, <lpy>), snap: false, inset: 5pt, stroke: 0.6pt, name: <bpy>),
      // SUMO y disco (filas 7-8)
      rotulo((0.5, 7), [«binarios» SUMO 1.27.1 (`eclipse-sumo`)], name: <lsm>),
      componente((0, 8), [*Procesos SUMO*\ `sumo` (1 por corrida,\ 2 por comparación 3D)], name: <bsumo>, fill: luma(235)),
      componente((1, 8), [*Herramientas*\ `duarouter`, `netconvert`,\ `cutRoutes.py`,\ `randomTrips.py`], name: <bher>, fill: luma(235)),
      node(enclose: (<bsumo>, <bher>, <lsm>), snap: false, inset: 5pt, stroke: 0.6pt, name: <bsm>),
      rotulo((2, 7), [«disco local» Sistema de archivos], name: <ldisco>),
      componente((2, 8), [*Directorios*\ `scenarios/`, `runs/`, `cache/`,\ `precalculadas/`,\ `data/processed/`], name: <bfs>, fill: luma(235)),
      node(enclose: (<bfs>, <ldisco>), snap: false, inset: 5pt, stroke: 0.6pt, name: <bdisco>),
      node(enclose: (<bnav>, <bnode>, <bpy>, <bsm>, <bdisco>, <lequipo>), snap: false, inset: 8pt, stroke: 1.2pt, name: <equipo>),
      // Externos
      componente((3.7, 2), [*Mapbox y OSM*\ servidores\ de teselas], name: <btiles>, fill: luma(235)),
      componente((3.7, 6), [*SDM (ArcGIS) y\ Overpass (OSM)*\ datos abiertos], name: <bsdm>, fill: luma(235)),
      edge(<bnav>, <bnode>, "<->", label: [HTTP / WS], label-side: left),
      edge(<bnode>, <bpy>, "<->", label: [HTTP / WS :8000], label-side: left),
      edge(<bapi>, <bges>, "<->"),
      edge(<bges>, <betl>, "<->"),
      edge(<bpy>, <bsm>, "<->", label: [TraCI / subproceso], label-side: left),
      edge(<bpy>, <bdisco>, "<->"),
      edge(<bsm>, <bdisco>, "<->"),
      edge(<bnav>, <btiles>, "->", label: [HTTPS]),
      edge(<betl>, <bsdm>, "<-", label: [HTTPS], label-side: left),
    ))
  ],
  caption: [Diagrama de despliegue: nodos, entornos de ejecución y artefactos instalados.],
) <fig-despliegue>

=== Descripción de los nodos

#figure(
  table(
    columns: (1fr, 2fr, 2fr),
    table.header([Nodo], [Componentes instalados], [Observaciones]),
    [Equipo del usuario (Linux o Windows)], [Navegador, Node.js, entorno virtual de Python y binarios de SUMO.], [Un solo equipo ejecuta todo. El mismo código corre en Linux y Windows (se contempla el bloqueo de archivos de Windows al borrar el directorio de una comparación y se normalizan los saltos de línea al calcular la huella de insumos).],
    [Navegador web], [Visor web (React), kepler.gl, simulador 3D (three.js, maplibre-gl).], [El bundle lo sirve Vite; el simulador 3D se descarga de forma diferida al abrirse. Debe poder manejar la encuesta completa (~24.600 viajes, ~64 MB de GeoJSON sin comprimir; 11,7 MB comprimido).],
    [Node.js], [Servidor de desarrollo de Vite con el proxy `/api/*`.], [Retira el prefijo `/api` y reenvía HTTP y WebSocket a `localhost:8000`.],
    [Python ≥ 3.11 (venv)], [API (uvicorn), gestores, ETL, análisis y los clientes `traci`, `sumolib` y `pyproj`.], [Un solo proceso de API con hilos: un trabajador para las corridas y un hilo por comparación 3D.],
    [Binarios de SUMO], [`sumo`, `duarouter`, `netconvert` y las herramientas `cutRoutes.py` y `randomTrips.py`.], [Paquete `eclipse-sumo`, que deja los binarios en el `PATH` del entorno virtual. Cada corrida lanza un `sumo`; cada comparación 3D lanza dos (lado A y lado B), que se comunican por sockets locales de TraCI.],
    [Sistema de archivos], [`scenarios/`, `runs/`, `cache/`, `precalculadas/`, `data/processed/`.], [Ver @sec-persistencia. Es la única persistencia del sistema.],
    [Mapbox y OSM (externo)], [Servidores de teselas de mapa.], [Mapbox exige `VITE_MAPBOX_TOKEN` en `kepler/.env`; OSM (minimapa del 3D) no necesita token.],
    [SDM y Overpass (externo)], [ArcGIS FeatureServer y Overpass de OSM.], [Solo al ejecutar `python -m etl.sumo.evidencia`; los resultados se versionan, así que el sistema funciona sin red.],
  ),
  caption: [Nodos físicos y componentes instalados en cada uno.],
)

*Puesta en marcha.* Los componentes se instalan y arrancan así:

```bash
# Servicio (desde simulation-service/)
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
python -m etl.etl                 # pipeline completo (varios minutos)
python -m etl.precalculadas       # regenerar presets precalculados
uvicorn api.api:app --reload      # API en :8000, documentación en /docs

# Visor (desde kepler/)
npm install && npm run dev        # requiere la API en :8000 y VITE_MAPBOX_TOKEN en .env
```
