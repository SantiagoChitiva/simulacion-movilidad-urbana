#import "uml.typ": *

== Vista lógica del sistema <sec-vista-logica>

La vista lógica identifica los componentes más gruesos del sistema, sin considerar en qué máquina se instalan, junto con las interfaces que los conectan. Incluye también las librerías, los entornos de ejecución y el software externo que el sistema necesita para funcionar.

=== Diagrama de componentes

El sistema es una aplicación cliente--servidor local. El navegador carga el visor (`kepler`); el servidor de desarrollo de Vite reenvía `/api/*` (HTTP y WebSocket) a la API de `simulation-service`, que orquesta las herramientas de SUMO como subprocesos o mediante TraCI y lee y escribe en el sistema de archivos.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (7mm, 5mm),
      // Navegador (filas 0-1)
      rotulo((1, 0), [Navegador web (motor JavaScript)], name: <ln>),
      componente((0, 1), [*Visor web*\ `App`, paneles, hooks\ React 18], name: <visor>),
      componente((1, 1), [*kepler.gl*\ Redux, react-palm,\ styled-components], name: <kgl>),
      componente((2, 1), [*Simulador 3D*\ three.js,\ maplibre-gl], name: <s3d>),
      node(enclose: (<visor>, <kgl>, <s3d>, <ln>), snap: false, inset: 6pt, stroke: (dash: "dashed", paint: luma(100)), name: <nav>),
      // Servidor Vite (fila 2)
      componente((1, 2), [*Servidor Vite*\ proxy `/api/*`\ Node.js], name: <vite>),
      // Servicio (filas 3-5)
      rotulo((1, 3), [Servicio `simulation-service` (intérprete Python ≥ 3.11)], name: <ls>),
      componente((1, 4), [*API*\ FastAPI, Pydantic, uvicorn\ `api.api`], name: <api>),
      componente((0, 5), [*Orquestación*\ `GestorCorridas`\ `GestorComparaciones`], name: <orq>),
      componente((1, 5), [*ETL y dominio*\ demanda, ruteo, simulación,\ exportación, escena 3D,\ telemetría], name: <etl>),
      componente((2, 5), [*Análisis de\ intersecciones*\ catálogo, priorización,\ programas, Webster], name: <ana>),
      componente((0, 6), [*Clientes de SUMO*\ `traci`, `sumolib`,\ `pyproj`], name: <lib>),
      node(enclose: (<api>, <orq>, <etl>, <ana>, <lib>, <ls>), snap: false, inset: 6pt, stroke: (dash: "dashed", paint: luma(100)), name: <srv>),
      // Motor y datos (fila 7)
      componente((1, 7), [*SUMO 1.27.1*\ `sumo`, `duarouter`, `netconvert`,\ `cutRoutes.py`, `randomTrips.py`], name: <sumo>, fill: luma(235)),
      componente((2, 7), [*Sistema de archivos*\ `scenarios/`, `runs/`, `cache/`,\ `precalculadas/`, `data/processed/`], name: <fs>, fill: luma(235)),
      // Externos
      componente((3.3, 1), [*Teselas de mapa*\ Mapbox, OSM], name: <tiles>, fill: luma(235)),
      componente((3.3, 5), [*Datos abiertos*\ SDM (ArcGIS),\ Overpass (OSM)], name: <abiertos>, fill: luma(235)),
      // Interfaces
      edge(<nav>, <vite>, "<->", label: [HTTP / WS], label-side: left),
      edge(<vite>, <srv>, "<->", label: [REST / WS], label-side: left),
      edge(<api>, <orq>, "->"),
      edge(<api>, <etl>, "->"),
      edge(<api>, <ana>, "->"),
      edge(<orq>, <etl>, "->"),
      edge(<orq>, <lib>, "->"),
      edge(<etl>, <lib>, "->"),
      edge(<lib>, <sumo>, "<->", label: [TraCI /\ subproceso], label-side: right),
      edge(<etl>, <sumo>, "->"),
      edge(<etl>, <fs>, "<->"),
      edge(<ana>, <fs>, "<->"),
      edge(<sumo>, <fs>, "<->"),
      edge(<nav>, <tiles>, "->", label: [HTTPS]),
      edge(<ana>, <abiertos>, "<-", label: [HTTPS\ (una vez)], label-side: right),
    ))
  ],
  caption: [Diagrama de componentes: librerías, entornos de ejecución y software externo.],
) <fig-componentes>

=== Descripción de los componentes

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    table.header([Componente], [Responsabilidad], [Interfaces]),
    [Visor web], [Dueño del mapa y de los paneles de usuario: descarga y anima los viajes, edita la demanda, consulta intersecciones y abre el simulador 3D.], [*Requiere:* API REST y WebSocket (vía `/api`), teselas de mapa. *Ofrece:* la interfaz gráfica.],
    [kepler.gl], [Biblioteca de visualización geoespacial; su capa _Trip_ anima los viajes con marca de tiempo. Impone Redux para su estado.], [*Requiere:* GeoJSON de `LineString` con `[lon, lat, z, t]`.],
    [Simulador 3D], [Dos escenas three.js (sin y con semáforo propuesto), HUD y minimapa; se carga de forma diferida.], [*Requiere:* `GET .../geometria` y `WS /comparacion3d/{id}`.],
    [Servidor Vite], [Sirve el visor y reenvía `/api/*` a `localhost:8000`, retirando el prefijo.], [*Ofrece:* HTTP y WebSocket del mismo origen para el navegador.],
    [API], [Valida las peticiones (Pydantic), traduce errores a códigos HTTP y publica los recursos REST y el WebSocket. No contiene lógica de negocio pesada.], [*Ofrece:* REST/JSON y WebSocket (@sec-interfaces-api). *Requiere:* Orquestación, ETL y Análisis.],
    [Orquestación], [`GestorCorridas` ejecuta una corrida pesada a la vez, con avance y cancelación; `GestorComparaciones` prepara y corre las comparaciones 3D (máximo 2).], [*Requiere:* `run_pipeline`, TraCI y el sistema de archivos.],
    [ETL y dominio], [Pipeline encuesta → viajes → rutas → simulación → GeoJSON; demanda parametrizada; semáforo propuesto, demanda de zona, escena 3D y telemetría de riesgo.], [*Requiere:* SUMO y el sistema de archivos. *Ofrece:* funciones `run_pipeline`, `run_escenario_semaforo`.],
    [Análisis de intersecciones], [Catálogo de semáforos de la red, priorización de cruces sin semáforo, lectura y validación de programas `tlLogic` y cálculo de Webster.], [*Requiere:* red SUMO, evidencia versionada y volúmenes de una corrida.],
    [Clientes de SUMO], [Librerías Python que hablan con SUMO: `traci` (control en vivo), `sumolib` (puertos libres y lectura de redes) y `pyproj` (UTM a lon/lat).], [*Requiere:* binarios de SUMO.],
    [SUMO], [Simulador microscópico (`sumo`), ruteador (`duarouter`), constructor de redes (`netconvert`) y herramientas Python (`cutRoutes.py`, `randomTrips.py`).], [*Ofrece:* línea de comandos y TraCI por socket local.],
    [Sistema de archivos], [Almacén único de datos: insumos, corridas, cachés y precalculadas (@sec-persistencia).], [Lectura y escritura local.],
    [Teselas de mapa], [Mapbox (base de kepler.gl, requiere `VITE_MAPBOX_TOKEN`) y OSM (minimapa del 3D, sin token).], [HTTPS desde el navegador.],
    [Datos abiertos], [SDM (siniestros) y Overpass de OSM (POI, edificios, nombres de vías). Solo se consultan al ejecutar `python -m etl.sumo.evidencia`; los resultados se versionan, así que el sistema funciona sin red.], [HTTPS desde el servicio.],
  ),
  caption: [Componentes del sistema, sus responsabilidades e interfaces.],
)

=== Interfaces entre componentes <sec-interfaces>

#figure(
  table(
    columns: (1fr, 2fr, 3fr),
    table.header([Interfaz], [Medio], [Uso]),
    [Visor ↔ API], [HTTP/JSON y WebSocket, por el proxy de Vite (`/api`)], [Toda la comunicación del visor; el detalle está en @sec-interfaces-api.],
    [API ↔ Orquestación y ETL], [Llamadas a funciones de Python, con inyección de dependencias (`Depends`)], [Los gestores se sustituyen en las pruebas con `app.dependency_overrides`.],
    [Orquestación ↔ ETL], [`run_pipeline(..., on_progreso, cancelar)`], [Único punto de entrada de una corrida. `on_progreso(etapa, avance | None)` y `cancelar` (`threading.Event`) cruzan todas las capas hasta el subproceso.],
    [ETL ↔ SUMO], [Subprocesos (`sumo`, `duarouter`, `netconvert`) y TraCI por socket local], [Binarios del paquete `eclipse-sumo` en el `PATH` del entorno virtual. `cutRoutes.py` y `randomTrips.py` se buscan en `$SUMO_HOME/tools` y, si no, en el paquete pip.],
    [Servicio ↔ Sistema de archivos], [Lectura y escritura local], [Insumos, corridas y cachés (@sec-persistencia).],
    [Hilo de simulación ↔ hilo de eventos], [`asyncio.Queue` con `call_soon_threadsafe`; `queue.Queue` para comandos], [`correr_comparacion` corre en un hilo y publica frames; los comandos del cliente entran por la cola (pausa, velocidad y aceleración se leen directamente del objeto `Comparacion`).],
    [Navegador ↔ teselas], [HTTPS], [Mapbox (token en `kepler/.env`, ignorado por Git) y OSM.],
    [Servicio ↔ datos abiertos], [HTTPS (solo al ejecutar `python -m etl.sumo.evidencia`)], [SDM (ArcGIS FeatureServer) y Overpass con un espejo de respaldo.],
  ),
  caption: [Interfaces entre los componentes del sistema.],
)

==== API del servicio de simulación <sec-interfaces-api>

La API es REST sobre JSON más un WebSocket. Se sirve en `http://localhost:8000` (documentación interactiva autogenerada en `/docs`). El visor la usa a través del prefijo `/api`, que el proxy de Vite retira. Los errores usan `{"detail": ...}` con los códigos: `404` (no existe), `409` (recurso no listo o en estado incompatible), `422` (validación), `429` (límite de comparaciones abiertas).

#figure(
  table(
    columns: (2fr, 1fr, 2fr),
    table.header([Método y ruta], [Códigos], [Descripción]),
    [`GET /health`], [200], [Comprobación de vida: `{"msg": "healthy"}`.],
    [`GET /demanda/modos`], [200], [Modos de viaje con etiqueta, color y conteo por defecto.],
    [`GET /demanda/presets`], [200], [Presets con descripción y conteos por defecto.],
    [`GET /demanda/estilos`], [200], [Estilos de conducción con sus parámetros de SUMO.],
    [`POST /simulaciones`], [202, 422], [Cuerpo: `{preset, conteos{modo:n}, semilla?, estilo, cierres[]}`. Encola una corrida; devuelve su estado inicial con `id`.],
    [`GET /simulaciones`], [200], [Historial, la más reciente primero.],
    [`GET /simulaciones/{id}`], [200, 404], [Estado, avance y resultado de una corrida.],
    [`POST /simulaciones/{id}/cancelar`], [202, 404, 409], [Cancela una corrida en cola o en curso.],
    [`GET /simulaciones/{id}/kepler-trips`], [200, 404, 409], [GeoJSON de trips de una corrida terminada.],
    [`GET /precalculadas`], [200], [Presets ya simulados (metadatos).],
    [`GET /precalculadas/{preset}/kepler-trips`], [200, 404], [Trips comprimidos (`Content-Encoding: gzip`, `X-Tamano-Original`).],
    [`GET /simulation-output?limit=`, `GET /kepler-trips`], [200, 404], [Salidas de la corrida por defecto (herencia del pipeline por línea de comandos).],
    [`GET /intersecciones?run_id=&precalculada=`], [200, 404, 409], [Semáforos como GeoJSON de puntos, con volumen de la corrida.],
    [`GET /intersecciones/{tl_id}`], [200, 404], [Ficha: accesos, fases, volúmenes, notas sobre el origen del programa.],
    [`GET /intersecciones/priorizacion`], [200], [Cruces sin semáforo por nivel y puntaje, umbrales, notas y descartes.],
    [`GET /intersecciones/{tl_id}/programas[/{pid}]`], [200, 404], [Lista o detalle de programas `tlLogic`.],
    [`PUT /intersecciones/{tl_id}/programas/{pid}`], [200, 404, 422], [Valida y guarda un programa editado en el escenario.],
    [`POST /intersecciones/{tl_id}/programas/webster`], [200, 422], [Calcula ciclo y verdes de Webster con los volúmenes de una corrida.],
    [`POST /intersecciones/{tl_id}/escenarios`], [202, 404], [Recorta red y demanda de una zona (radio 50--2.000 m).],
    [`GET /escenarios/{run_id}`], [200, 404], [Estado de un recorte de zona.],
    [`POST /intersecciones/{tl_id}/comparaciones`, `GET /comparaciones/{id}`], [202, 200, 404], [Compara varios programas de un semáforo por métricas de corridas de zona.],
    [`POST /cruces/{nodo}/comparacion3d`], [202, 422, 429], [Cuerpo: `{lon, lat, run_id?, intensidades?, nodos?}`; intensidades 0--3.000 por hora. Prepara la comparación en segundo plano.],
    [`GET /comparacion3d`, `GET /comparacion3d/{id}`], [200, 404], [Lista y estado (`preparando`, `lista`, `error`) con la etapa en curso.],
    [`GET /comparacion3d/{id}/geometria`], [200, 404, 409], [Geometría de la escena; solo cuando la comparación está `lista`.],
    [`DELETE /comparacion3d/{id}`], [204, 404], [Cierra la comparación y borra sus archivos.],
    [`WS /comparacion3d/{id}`], [101, cierre 1008], [Transmisión en vivo (ver abajo). Se rechaza si no existe, no está lista o ya hay una ventana conectada.],
  ),
  caption: [Endpoints de la API.],
) <tab-endpoints>

*Ejemplo: creación de una simulación.*

```http
POST /simulaciones
{"preset": "mas_peatones",
 "conteos": {"auto": 3000, "peaton": 12000, "bici": 2500, "moto": 1557},
 "semilla": 42, "estilo": "normal", "cierres": []}

202 Accepted
{"id": "20261015-101533-a1b2c3", "estado": "en_cola", "avance": 0.0, ...}
```

==== Protocolo del WebSocket de la comparación 3D

Los mensajes son JSON de texto. Una sola ventana puede estar conectada a la vez; el servidor envía un `ping` cada 5 s de inactividad.

#figure(
  table(
    columns: (1fr, 2fr, 3fr),
    table.header([Sentido], [Mensaje], [Significado]),
    [Servidor → cliente], [`{tipo:"estado", mensaje}`], [Progreso del arranque y del calentamiento.],
    [], [`{tipo:"frame", t, dt, ego, manual, lados:{a, b}}`], [Un paso de simulación con actores, luces, métricas y telemetría (ver @sec-datos-frame).],
    [], [`{tipo:"ego", id}`], [Se inyectó un nuevo actor seguido.],
    [], [`{tipo:"giro", direccion}`], [Se aceptó un giro en modo manual.],
    [], [`{tipo:"aviso", mensaje}`], [Comando no aplicable (p. ej. giro imposible desde el acceso actual).],
    [], [`{tipo:"fin"}`, `{tipo:"error", mensaje}`, `{tipo:"ping"}`], [Fin de la simulación, fallo (con el _stderr_ de SUMO) y latido.],
    [Cliente → servidor], [`{pausa: bool}`], [Pausar o reanudar.],
    [], [`{velocidad: x}`], [Factor de velocidad, acotado a 0,25--20.],
    [], [`{periodo_riesgo: s}`], [Cada cuántos segundos simulados se mide el riesgo (0,4--30).],
    [], [`{seguir: id}`], [Cambiar el actor seguido.],
    [], [`{inyectar:{tipo, acceso, giro, estilo}}`], [Insertar un actor propio con la ruta del acceso y giro elegidos.],
    [], [`{manual: bool}`, `{control:{acelerar:-1|0|1}}`, `{giro:"s"|"l"|"r"}`], [Conducción manual: tomar el control, acelerar/frenar y elegir el próximo giro.],
  ),
  caption: [Mensajes del WebSocket `/comparacion3d/{id}`.],
)

=== Librerías, entornos de ejecución y software requerido

#figure(
  table(
    columns: (auto, 2fr, 3fr),
    table.header([Categoría], [Software y versión], [Uso]),
    [Entorno de ejecución], [Python ≥ 3.11; Node.js (para Vite); navegador web moderno], [Ejecutan el servicio, el servidor de desarrollo y el visor.],
    [Simulación], [SUMO 1.27.1 (`eclipse-sumo`), `traci` 1.27.1, `sumolib`], [Simulación microscópica, ruteo, construcción de red y control en vivo.],
    [Servicio], [FastAPI 0.136.3 (`fastapi[standard]`), Pydantic, `uvicorn`], [API REST/WebSocket y validación.],
    [Geodesia], [`pyproj` 3.8.0], [Coordenadas UTM de la red a lon/lat.],
    [Visor], [React 18.3, Vite 6, `vite-plugin-node-polyfills`], [Aplicación de una página con proxy `/api`.],
    [Mapa], [kepler.gl 3.1 (`@kepler.gl/*`), Redux 4, `react-palm`, `styled-components` 6.1.8, `react-intl`], [Mapa y capa Trip.],
    [3D], [three.js 0.169, maplibre-gl 4.7.1], [Escena comparativa y minimapa OSM.],
    [Calidad y pruebas], [`pytest` 9.1.1, `matplotlib` (validación), ESLint 10, pylint], [Pruebas y análisis estático.],
    [Datos], [Encuesta de Movilidad 2023 (TSV), OSM, siniestros SDM, edificios OSM y Microsoft], [Insumos versionados en `data/processed/` y `scenarios/`.],
  ),
  caption: [Librerías, máquinas virtuales y software de terceros requeridos.],
)

=== Patrones y decisiones arquitectónicas

*Cliente--servidor con servicio monolítico modular.* Se eligió un único proceso FastAPI con módulos internos separados (API → orquestación → ETL) en lugar de microservicios, porque el sistema corre en una sola máquina, lo costoso es SUMO y no el enrutamiento, y un solo proceso simplifica la cancelación, el reparto de rutas de archivos y las pruebas.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Capa], [Responsabilidad]),
    [Presentación], [`kepler/`: mapa kepler.gl, paneles de demanda, ficha de intersección, semaforización y simulador 3D (carga diferida).],
    [Interfaz (API)], [`api/api.py`: validación de peticiones, códigos HTTP y WebSocket.],
    [Orquestación], [`api/jobs.py` (corridas en segundo plano) y `api/comparacion3d.py` (comparaciones 3D con TraCI).],
    [Dominio y datos], [`etl/`: generación de demanda, ruteo, simulación, exportación, análisis de intersecciones y priorización, escena 3D, telemetría.],
  ),
  caption: [Capas del patrón arquitectónico por capas.],
)

Dentro del servicio conviven tres estilos adicionales:

- *Tubería de etapas (_pipes and filters_)* para el ETL: cada etapa lee archivos de la anterior y escribe los propios (TSV → `trips.xml` → `rou.xml` → FCD → GeoJSON) y puede ejecutarse sola.
- *Trabajos asíncronos con un solo trabajador* para las corridas largas: la API responde `202 Accepted` y el cliente consulta el estado cada 2 s (_polling_).
- *Flujo en tiempo real por WebSocket* para el simulador 3D: dos instancias de SUMO avanzan en _lockstep_ y el servidor emite un _frame_ por paso.

*Persistencia en archivos.* El sistema no usa un motor de base de datos: los resultados de SUMO ya son archivos, hay un único escenario y así se evita instalar y operar otro servicio. *Una instancia.* El estado de las corridas vive en memoria y en disco local, por lo que el sistema no escala en usuarios simultáneos ni tiene autenticación; es una herramienta local de investigación. *SUMO como ejecutable externo.* El servicio solo orquesta procesos y archivos; no integra SUMO como biblioteca.
