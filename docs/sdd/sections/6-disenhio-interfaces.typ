= Diseño de interfaces

== Interfaces internas y externas

=== Interfaces externas

#figure(
  table(
    columns: (1fr, 2fr, 3fr),
    [Interfaz], [Medio], [Uso],
    [SUMO], [Subprocesos (`sumo`, `duarouter`, `netconvert`) y TraCI por socket local], [Binarios del paquete `eclipse-sumo` (1.27.1) en el `PATH` del entorno virtual; `traci==1.27.1` para el control. Las herramientas `cutRoutes.py` y `randomTrips.py` se buscan en `$SUMO_HOME/tools` y, si no, en el paquete pip `eclipse-sumo`.],
    [Servicios de datos abiertos], [HTTPS (solo al ejecutar `python -m etl.sumo.evidencia`)], [SDM (ArcGIS FeatureServer, siniestros) y Overpass de OSM, con un espejo de respaldo (POI, edificios, nombres de vías). Los resultados se versionan, así que el sistema funciona sin red.],
    [Teselas de mapa], [HTTPS desde el navegador], [Mapbox (base de kepler.gl, requiere `VITE_MAPBOX_TOKEN`) y OSM (minimapa del 3D, sin token).],
    [Sistema de archivos], [Lectura/escritura local], [Insumos, corridas y cachés (@sec-almacenamiento-ref).],
  ),
  caption: [Interfaces externas del sistema.],
)

=== API del servicio de simulación

La API es REST sobre JSON más un WebSocket. Se sirve en `http://localhost:8000` (documentación interactiva autogenerada en `/docs`). El visor la usa a través del prefijo `/api`, que el proxy de Vite retira. Los errores usan `{"detail": ...}` con los códigos: `404` (no existe), `409` (recurso no listo o en estado incompatible), `422` (validación), `429` (límite de comparaciones abiertas).

#figure(
  table(
    columns: (2fr, 1fr, 2fr),
    [Método y ruta], [Códigos], [Descripción],
    [`GET /health`], [200], [Comprobación de vida: `{"msg": "healthy"}`.],
    [`GET /demanda/modos`], [200], [Modos de viaje con etiqueta, color y conteo por defecto.],
    [`GET /demanda/presets`], [200], [Presets con descripción y conteos por defecto.],
    [`GET /demanda/estilos`], [200], [Estilos de conducción con sus parámetros de SUMO.],
    [`POST /simulaciones`], [202, 422], [Cuerpo: `{preset, conteos{modo:n}, semilla?, estilo, cierres[]}`. Encola una corrida; devuelve su estado inicial con `id`.],
    [`GET /simulaciones`], [200], [Historial, la más reciente primero.],
    [`GET /simulaciones/{id}`], [200, 404], [Estado, avance y resultado de una corrida.],
    [`POST /simulaciones/{id}/cancelar`], [202, 404, 409], [Cancela una corrida en cola o en curso.],
    [`GET /simulaciones/{id}/kepler-trips`], [200, 404, 409], [GeoJSON de trips de una corrida terminada (`FileResponse`).],
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

=== Protocolo del WebSocket de la comparación 3D

Los mensajes son JSON de texto. Una sola ventana puede estar conectada a la vez; el servidor envía un `ping` cada 5 s de inactividad.

#figure(
  table(
    columns: (1fr, 2fr, 3fr),
    [Sentido], [Mensaje], [Significado],
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

=== Interfaz interna entre capas

- *API → orquestación.* Los gestores se inyectan con `Depends`; las pruebas los reemplazan con `app.dependency_overrides` (un pipeline falso en `GestorCorridas`, una función `preparar` falsa en `GestorComparaciones`).
- *Orquestación → ETL.* `run_pipeline(scenario, sample_every, seed, demanda, run_id, exportar_puntos, on_progreso, cancelar, estilo, cierres)` es el único punto de entrada de una corrida. `on_progreso(etapa, avance | None)` y `cancelar` (`threading.Event`) cruzan todas las capas hasta el subproceso.
- *Hilo de simulación → hilo de eventos del WebSocket.* `correr_comparacion` corre en un hilo y publica en una `asyncio.Queue` mediante `call_soon_threadsafe`; los comandos del cliente entran por una `queue.Queue` (pausa, velocidad y aceleración se leen directamente del objeto `Comparacion` en cada paso).

== Interfaces de usuario

La interfaz es una única pantalla a pantalla completa (`overflow: hidden`): el mapa de kepler.gl ocupa toda la ventana y los paneles flotan encima. Los colores por modo se definen en `modos.js` y se usan en el mapa, la leyenda y el panel.

#figure(
  block(width: 100%, height: 8.2cm, stroke: 0.6pt + luma(120), radius: 3pt, inset: 0pt)[
    #set par(justify: false)
    #set text(size: 8.5pt)
    #place(top + left, dx: 6pt, dy: 6pt, rect(width: 4.6cm, height: 7.6cm, stroke: 0.5pt, radius: 2pt, inset: 5pt, fill: luma(245))[
      *Panel lateral*\
      pestañas: Demanda · Cierres · Semaforizar\
      #v(2pt)
      presets, conteos por modo, escala y semilla, estilo de conducción\
      #v(2pt)
      #box(stroke: 0.5pt, inset: 3pt)[Simular / Cargar simulación]
    ])
    #place(top + center, dx: -0.6cm, dy: 6pt, rect(width: 4.6cm, height: 1cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Leyenda de modos* y conmutador «Semáforos»
    ])
    #place(center + horizon, dx: 0.4cm, text(size: 9pt, fill: luma(100))[mapa kepler.gl con viajes animados])
    #place(top + right, dx: -6pt, dy: 6pt, rect(width: 3.8cm, height: 2.6cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Ficha de intersección*\ accesos, volúmenes, fases, Webster
    ])
    #place(bottom + right, dx: -6pt, dy: -30pt, rect(width: 3.8cm, height: 1.8cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Tarjeta de actividad* barras de progreso, cancelar
    ])
    #place(bottom + left, dx: 5cm, dy: -4pt, rect(width: 9cm, height: 0.6cm, stroke: 0.5pt, radius: 2pt, inset: 3pt, fill: luma(245))[
      #align(center)[línea de tiempo de kepler.gl]
    ])
  ],
  caption: [Esquema de la pantalla principal del visor.],
) <fig-ui-principal>

*Pantalla principal (@fig-ui-principal).*

- *Panel de demanda:* elige un preset, ajusta viajes por modo (el total se valida contra el máximo de 100.000), semilla y estilo. Si los valores coinciden con una precalculada, el botón principal es «Cargar simulación» y la carga es inmediata; si no, «Simular» lanza una corrida.
- *Tarjeta de actividad:* muestra la etapa actual, el avance global y el de la etapa, y permite cancelar. Al terminar una corrida bien, el visor carga sus trips solo.
- *Capas de intersecciones:* «Semáforos» (puntos con la ficha al hacer clic) y «Priorización» (cruces candidatos por nivel: prioritario, recomendado, observación). Las notas de la API (por ejemplo, «sin datos de siniestros») se muestran al usuario.
- *Barra de progreso de descarga:* el visor calcula el avance con `X-Tamano-Original` de las precalculadas.

#figure(
  block(width: 100%, height: 8cm, stroke: 0.6pt + luma(120), radius: 3pt, inset: 0pt)[
    #set par(justify: false)
    #set text(size: 8.5pt)
    #place(top + left, rect(width: 50%, height: 100%, stroke: 0.5pt, inset: 6pt, fill: luma(250))[
      #align(center)[*Sin semáforo (actual)*]
      #v(1fr)
      #align(center)[escena three.js lado A]
      #v(1fr)
    ])
    #place(top + right, rect(width: 50%, height: 100%, stroke: 0.5pt, inset: 6pt, fill: luma(250))[
      #align(center)[*Con semáforo propuesto*]
      #v(1fr)
      #align(center)[escena three.js lado B]
      #v(1fr)
    ])
    #place(top + center, dy: 30pt, rect(width: 6.4cm, height: 0.8cm, stroke: 0.5pt, radius: 8pt, inset: 4pt, fill: white)[
      #align(center)[píldora: tiempo · velocidad · pausa]
    ])
    #place(bottom + center, dy: -6pt, rect(width: 10cm, height: 1.7cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: white)[
      *Tarjeta inferior:* telemetría del actor seguido (velocidad, aceleración, líder, riesgo TTC/DRAC/PET, acción) · comparación de métricas por lado · pestañas Comparar / Sin / Con
    ])
    #place(bottom + left, dx: 6pt, dy: -6pt, rect(width: 2.2cm, height: 1.7cm, stroke: 0.5pt, radius: 2pt, inset: 3pt, fill: white)[
      #align(center)[Minimapa OSM]
    ])
  ],
  caption: [Esquema del simulador 3D comparativo.],
) <fig-ui-3d>

*Simulador 3D (@fig-ui-3d).* Se abre en pantalla dividida (pestañas Comparar, Sin y Con). El HUD sigue el patrón de una píldora superior con el control de tiempo y una tarjeta inferior con la telemetría y el índice de riesgo de cada lado. El actor seguido se puede cambiar o inyectar (auto, moto, taxi, bici, peatón, entre otros) eligiendo el acceso, el giro y el estilo de conducción. En modo manual, el teclado acelera, frena y elige el giro (los comandos se aplican igual en los dos lados). La cámara puede ser de persecución, con colisión contra edificios, o aérea. El componente se carga de forma diferida (`lazy`) porque three.js y maplibre pesan, y queda envuelto en `LimiteErrores`, de modo que un fallo gráfico no tumba el mapa.
