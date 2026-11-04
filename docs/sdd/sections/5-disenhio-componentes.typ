= Diseño de componentes (diseño detallado)

== Desglose de módulos

=== Convenciones comunes del servicio

Todos los módulos de `etl/sumo/` siguen el mismo patrón, para que sean predecibles y fáciles de probar:

- Un `*Config` (`dataclass(frozen=True)`) con los parámetros y, si invoca una herramienta de SUMO, un método `to_args()`.
- Un `*Result` con lo producido y un `*Stats` mutable que se pasa y se incrementa durante el proceso (contadores de filas inválidas, viajes generados, etc.).
- Los envoltorios de subprocesos buscan el binario con `shutil.which` y lanzan una excepción propia (`*Error(RuntimeError)`).
- Los procesos largos aceptan `on_avance` (callback con el avance 0--1) y `cancelar` (`threading.Event`), y los ejecutan a través de `proceso.ejecutar`, que consulta ambos cada 0,5 s.

=== Servicio de simulación (`simulation-service/src`)

#figure(
  table(
    columns: (auto, 1fr),
    [Módulo], [Responsabilidad],
    [`api/api.py`], [Aplicación FastAPI: modelos Pydantic de entrada, rutas HTTP y WebSocket, traducción de errores a códigos HTTP. Las dependencias (`obtener_gestor`, `obtener_gestor_comparaciones`) son sustituibles en pruebas con `dependency_overrides`.],
    [`api/jobs.py`], [`GestorCorridas`: cola de un trabajador, estado persistido, avance por franjas, cancelación, recuperación tras reinicio (las corridas no finales pasan a `error`, «Interrumpida: el servicio se reinició»).],
    [`api/comparacion3d.py`], [`GestorComparaciones` (máx. 2 abiertas, expiración a los 180 s sin conexión), `Comparacion` (estado y comandos en vivo), `Lado` (una instancia de SUMO con TraCI) y `correr_comparacion` (bucle en lockstep).],
    [`etl/etl.py`], [Orquesta `run_etl`, `simulate`, `export_geojson`, `export_kepler_trips`, `run_pipeline`; además `run_recorte` y `run_escenario_semaforo` para zonas.],
    [`etl/precalculadas.py`], [Genera, comprime, lista y carga los presets precalculados; calcula la huella de insumos.],
    [`etl/sumo/configuration.py`], [Única fuente de rutas y constantes: `ScenarioPaths`, `ArchivosPrecalculada`, ventana 07:00--10:00, `MAX_COPIAS` = 50, `MAX_VIAJES` = 100.000, `escribir_sumocfg_corrida`.],
    [`etl/sumo/trips.py`], [Lee el TSV, valida, expande por `fexp`, ordena por `depart` y escribe `*.trips.xml` (vehículos como `<trip>`, peatones y transporte público como `<person><walk>`).],
    [`etl/sumo/demanda.py`], [Demanda parametrizada: presets como `ReglaTransferencia`, probabilidades P(modo | duración), reparto por mayor resto.],
    [`etl/sumo/duarouter.py`], [Ejecuta `duarouter` con `--ignore-errors --repair`; el avance sale del último `depart` escrito en el `.rou.xml`.],
    [`etl/sumo/simulation.py`], [Ejecuta SUMO. Si hay `on_avance` o `cancelar`, lo maneja con TraCI (saltos de 60 s); si no, como subproceso simple.],
    [`etl/sumo/fcd.py`, `kepler.py`], [Conversión en streaming del FCD a GeoJSON de puntos (`fcd`) y a `LineString` por actor para la capa Trip (`kepler`).],
    [`etl/sumo/vtypes.py`, `enums/`], [Mapeos `SurveyMode` → `TransportMode` → `VTypeConfig` (clase de vehículo, largo, velocidad máxima, color).],
    [`etl/sumo/estilos.py`], [Estilos de conducción: `sigma`, `speedFactor`, `tau`, `lcSpeedGain` aplicados a los vTypes motorizados.],
    [`etl/sumo/cierres.py`], [Escribe un `rerouter` de SUMO para cierres viales por edge y horario.],
    [`etl/sumo/intersecciones.py`], [Catálogo de `Semaforo` desde la red (accesos, fases, enlaces), nombres de vías, volúmenes por acceso, cachés.],
    [`etl/sumo/priorizacion.py`], [Agrupación de cruces, reglas duras, evidencia, niveles y puntaje (@sec-alg-priorizacion).],
    [`etl/sumo/evidencia.py`], [Descarga única de siniestros (SDM), POI y edificios (OSM) hacia `data/processed/`.],
    [`etl/sumo/programas_tls.py`], [Lectura, validación y escritura de programas `tlLogic`; cálculo de Webster.],
    [`etl/sumo/subred.py`], [Recorta la red (`netconvert`) y la demanda (`cutRoutes.py`) alrededor de un punto.],
    [`etl/sumo/semaforo_nuevo.py`], [Crea la variante con semáforo: parche de nodos `type="traffic_light"` con el mismo `tl` y `netconvert`.],
    [`etl/sumo/demanda_zona.py`], [Demanda de una zona: viajes reales recortados más tráfico de fondo con `randomTrips.py` por modo.],
    [`etl/sumo/escena3d.py`], [Geometría de la escena 3D: calzadas, andenes, cebras, postes, terreno IDW, edificios, rutas por acceso.],
    [`etl/sumo/telemetria.py`], [Funciones puras de riesgo (TTC, DRAC, PET), índice de riesgo y clasificación de la acción del conductor.],
    [`etl/sumo/proceso.py`], [Ejecución de subprocesos con sondeo de avance, cancelación y tiempo máximo; excepción `Cancelado`.],
  ),
  caption: [Módulos de `simulation-service` y su responsabilidad.],
)

=== Visor web (`kepler/src`)

#figure(
  table(
    columns: (auto, 1fr),
    [Componente], [Responsabilidad],
    [`App.jsx` (`Visor`)], [Dueño del mapa. Descarga los trips con progreso y `AbortController`, reemplaza el dataset de kepler, activa las capas de semáforos y de priorización, y abre la ficha de intersección leyendo `visState.clicked`.],
    [`api.js`], [Cliente HTTP único (`pedir`, `descargarJson` con progreso, URLs de WebSocket). Todas las rutas son relativas a `/api`.],
    [`hooks.js`], [`useCorridas` (historial, corrida activa, consulta cada 2 s, cancelación) y `useTamanoVentana` (kepler necesita ancho y alto explícitos).],
    [`PanelDemanda`], [Presets, conteos por modo, escala, semilla y estilo de conducción; decide entre «Simular» y «Cargar simulación».],
    [`PanelCierres`], [Define cierres viales (edge y horario).],
    [`TarjetaActividad`], [Tarjeta inferior derecha con barras de progreso y botón de cancelar.],
    [`LeyendaModos`], [Leyenda de colores por modo y alternancia de la capa «Semáforos».],
    [`FichaInterseccion`], [Accesos, volúmenes, fases, edición del programa, cálculo de Webster y comparación de programas (`TablaComparacion`).],
    [`PanelSemaforizacion`], [Pestaña «Semaforizar»: elige un cruce candidato (clic en la capa o lista por puntaje), configura el tráfico de fondo y abre el simulador 3D.],
    [`simulador3d/Simulador3D`], [Ciclo de vida: crear → consultar → geometría → WebSocket; pantalla dividida «sin semáforo» y «con semáforo propuesto».],
    [`simulador3d/escena.js`], [Una escena three.js por lado: mallas estáticas fusionadas por material, actores interpolados entre frames, cámara de persecución con colisión contra edificios o aérea, conducción automática o manual por teclado.],
    [`simulador3d/HUD`, `Minimapa`], [Superposición con métricas y telemetría; minimapa OSM con maplibre (sin token).],
    [`modos.js`], [Colores por modo; el rango se arma en orden alfabético de los modos presentes porque así los asigna la escala ordinal de kepler.],
    [`LimiteError`, `LimiteErrores`], [Barreras de error (_error boundaries_) para que un fallo del visor o del 3D no tumbe la aplicación.],
  ),
  caption: [Componentes del visor y su responsabilidad.],
)

== Lógica y algoritmos

=== Generación de viajes y orden de salida

Para cada fila válida del TSV se crea un `TripRecord` con `copies = min(round(fexp), MAX_COPIAS)`. Las copias se emiten con ids únicos y *se ordenan por `depart`* antes de escribir el XML. El orden es indispensable: el TSV no está ordenado, `duarouter` conserva el orden de entrada y SUMO *descarta* (no reordena) cualquier entidad cuya salida sea menor que la máxima ya cargada. Sin el orden se perdían cerca de 23.000 de ~24.600 viajes.

=== Demanda parametrizada por presets <sec-alg-demanda>

Un preset es una regla de transferencia modal `ReglaTransferencia(origen, destinos, duracion_mayor_a, duracion_hasta)`. Con los viajes de *todo el día* se calcula $P(m | r)$: la probabilidad de cada modo $m$ en cada rango de duración $r$ (≤ 15, 15--30, 30--60 y > 60 min), ponderada por `fexp`. Después:

+ Para cada viaje de la ventana que cumple la regla, su peso (`copies`) se reparte entre los modos destino en proporción a $P(m | r)$ restringida a esos destinos; los demás viajes conservan su modo.
+ Resultan _pools_ por modo con pares (viaje, peso).
+ Para cada modo con conteo pedido $n_m$, se asignan copias a los viajes del _pool_ con el método del *mayor resto* (Hamilton): $n_m w_i / sum_j w_j$ se trunca y las unidades que faltan se dan a las partes decimales mayores. La suma es exacta y el resultado es determinista.
+ Si un modo no tiene _pool_ en el preset (p. ej. autos en «día sin carro»), se usa el _pool_ base de la encuesta.

Propiedades verificadas por pruebas: los presets conservan el total; un viaje transferido mantiene su origen/destino y su hora de salida; y con `encuesta` y sus conteos por defecto se reproduce exactamente la expansión simple de la encuesta.

=== Ejecución de SUMO bajo TraCI

`simulation._run_traci` lanza `sumo` con `--remote-port` libre, se conecta con reintentos y avanza con `simulationStep` en saltos de 60 s hasta `<end>`. Tras cada salto calcula el avance de la ventana y revisa la cancelación; ante cancelación o tiempo máximo mata el proceso. Los archivos de salida son los mismos que sin TraCI. Se usa TraCI, y no el registro de SUMO, porque con la salida redirigida a un _pipe_ SUMO y `duarouter` almacenan su bitácora por bloques y esta solo llega al terminar.

=== Reducción de puntos para kepler

`kepler.reduce_points` primero colapsa cada tramo quieto (misma posición en puntos consecutivos) a su primer y último punto y luego muestrea lo que queda: siempre conserva el primer y el último punto de la entidad, y entre ellos guarda un punto cada `step` segundos (8 s en el pipeline; 5 s por defecto del módulo) o cuando el rumbo cambia al menos 20°. Las entidades que se mueven menos de `min_move` = 20 m se descartan y se cuentan. Las posiciones con `inf` o `z` fuera de ±100.000 se ignoran como inválidas.

=== Priorización de cruces sin semáforo <sec-alg-priorizacion>

El análisis de la red (independiente de la corrida) y el puntaje (dependiente de los volúmenes) se separan para poder cachear la parte costosa.

*Análisis (con caché `priorizacion.json`):*

+ Se agrupan nodos de SUMO a menos de 20 m (extensión máxima 45 m) y se fusionan los grupos del mismo par de calles a menos de 150 m (las dos calzadas de una avenida; extensión máxima 200 m). Un cruce requiere dos calles distintas que se corten a más de 35°.
+ *Reglas duras, todas obligatorias:* participa una vía colectora (`tertiary`) o superior, sin autopistas ni troncales; la otra vía es al menos residencial; sin rampas ni glorietas a menos de 40 m; conflicto real (la vía secundaria cruza de frente o gira a la izquierda); sin semáforo a menos de 80 m.
+ *Evidencia*, calibrada contra los cruces ya semaforizados de la propia red (_backtest_): siniestros a menos de 30 m ≥ p75 (mínimo 3), o ≥ mediana con un generador cerca; tramo de la vía principal sin semáforo ≥ 600 m; volumen simulado de entrada ≥ p75. Generadores: colegios, jardines, universidades, hospitales y clínicas a menos de 200 m.

*Puntaje (en cada consulta):* número de evidencias «fuertes» $e$ → nivel `prioritario` ($e >= 2$), `recomendado` ($e = 1$) u `observacion` (solo generador o siniestros ≥ mediana). El puntaje es un piso por nivel (75 / 50 / 25) más hasta 25 puntos:

$ "puntaje" = "piso" + 25 (0,35 s + 0,30 v + 0,15 g + 0,10 t + 0,10 h) $

con $s$ el rango percentil de siniestros, $v$ el de volumen, $g = min(g_"n" / 3, 1)$ los generadores, $t = min("tramo" / 1200, 1)$ y $h$ la jerarquía. Finalmente, una _supresión de no máximos_ (NMS): dos cruces del mismo nivel a menos de 120 m se estudian juntos y el de menor puntaje baja un nivel. La lógica sigue la del proyecto Semáforos de Barranquilla, sin su modelo de lenguaje.

=== Programas de semáforo y Webster <sec-alg-webster>

`validar_programa` exige que cada fase tenga tantos caracteres como movimientos controlados, que haya al menos una fase amarilla ≥ 3 s si hay verdes y un ciclo ≥ 15 s. El cálculo de Webster usa:

$ C_0 = (1,5 L + 5) / (1 - Y), quad L = n_"fases" dot 3 "s", quad Y = sum_i max_j (q_j / s) $

con flujo de saturación $s$ = 1.800 veh/h por carril. Los verdes se reparten en proporción a $y_i / Y$ (mínimo 5 s) y el ciclo mínimo es 30 s; si $Y >= 1$ la intersección está sobresaturada y se devuelve un error. *Limitación conocida:* los accesos se asignan a las fases de forma circular (no según los movimientos compatibles reales), y si no hay volumen simulado se usa un valor de demostración de 300 veh/h. La API lo advierte en la respuesta (`nota`).

=== Variante con semáforo propuesto

`agregar_semaforo` verifica que ningún nodo del cruce tenga ya semáforo, escribe un parche `semaforo_propuesto.nod.xml` que da a *todos* los nodos del cruce `type="traffic_light"` y el mismo `tl` (un solo `tlLogic` controla el cruce completo, p. ej. las dos calzadas) y ejecuta `netconvert` con `--tls.default-type` sobre la red de la zona (`--geometry.remove false`). Luego comprueba que se generó un programa con fases.

=== Comparación 3D en lockstep <sec-alg-lockstep>

#figure(
  block(width: 100%, inset: 8pt, stroke: 0.5pt + luma(150), radius: 3pt)[
    *correr_comparacion*(comp, cola):
    + iniciar lado A (`zona.net.xml`) y lado B (`zona_tls.net.xml`) con la misma demanda y semilla 42
    + *mientras* t < t#sub[0] + 240 s: avanzar ambos de 20 en 20 s (calentamiento)
    + *mientras* comp.activa y t < fin:
      + atender comandos (`manual`, `control`, `giro`, `seguir`, `inyectar`)
      + si está en pausa: dormir 0,1 s y continuar
      + pasos ← max(1, round(velocidad)); t ← t + pasos · 0,2 s
      + *para cada lado*: avanzar a t; si manual, aplicar el mismo control al ego
      + si t ≥ próximo_riesgo: medir riesgo y contar conflictos
      + armar el frame (actores, luces, métricas, telemetría del ego) y publicarlo
      + dormir lo necesario para mantener el ritmo de tiempo real
    + publicar `fin`; cerrar ambos lados
  ],
  caption: [Pseudocódigo del bucle de la comparación 3D.],
)

Puntos de diseño del bucle:

- *Equidad de la comparación.* Misma demanda, misma semilla y mismo conjunto de comandos aplicados a los dos lados. El ego se inyecta con el mismo id y la misma ruta en ambos (`_ruta_inyeccion`); los peatones usan `findIntermodalRoute` entre _edges_ caminables.
- *Contrapresión.* La cola de frames tiene tamaño 8 y, si se llena, descarta el más antiguo: es preferible perder un frame que acumular retraso.
- *Suscripciones TraCI seguras.* Nunca se suscribe a un actor que ya salió de la red: SUMO 1.27 concatena los errores de suscripciones fallidas y falla (`Storage::writeUnsignedByte(): Invalid value`) cuando el mensaje pasa de 255 bytes. `Lado.avanzar` filtra los ids con `getIDList()`. Los vehículos inyectados que aún esperan entrar tienen `road id` vacío y se omiten.
- *Modo manual.* Acelerar y frenar se traducen a `setSpeed` (+1,8 m/s² y −3,5 m/s²), de modo que SUMO conserva sus chequeos de seguridad (no atraviesa un rojo ni choca). Los giros usan `changeTarget` hacia el último _edge_ de la ruta del giro elegido.

=== Indicadores de riesgo <sec-alg-riesgo>

Funciones puras en `telemetria.py`, calculadas sobre lo que TraCI reporta del actor seguido:

- $"TTC" = "gap" / (v - v_"líder")$ si el actor se acerca al líder.
- $"DRAC" = (v - v_"líder")^2 / (2 dot "gap")$ (m/s²).
- $"PET"$ aproximado en el cruce: diferencia entre las llegadas del ego y de un vehículo en conflicto (`getJunctionFoes`) al punto de cruce.

Cada indicador se normaliza de 0 (umbral seguro) a 100 (umbral crítico o peor): TTC 6 → 1,5 s; DRAC 0 → 3,35 m/s²; PET 5 → 1,5 s. El índice de riesgo es el *mayor* de los tres (manda el más grave, que además se informa como causa) y su nivel es bajo (< 30), medio (30--59) o alto (≥ 60); los umbrales provienen de la literatura de SSM @ssm. `clasificar_accion` traduce velocidad, aceleración, luz próxima, brecha y cesión de paso en una acción legible («Detenido en el semáforo», «Frenada fuerte», etc.). Las métricas por lado cuentan como conflicto un cruce con PET < 1,5 s entre vehículos a menos de 60 m del nodo.

=== Escena 3D

`geometria_escena` produce, una sola vez, el JSON que el visor convierte en geometría: calzadas, andenes, cebras y bocas de calle desde la red; un poste de semáforo por acceso; un terreno de rejilla por interpolación de distancia inversa (IDW) a partir de las alturas de calzadas y cruces; edificios de OSM y Microsoft deduplicados por solape, más un relleno ilustrativo (`relleno: true`) en los frentes de manzana vacíos que no se superponga con los reales. En el cliente, las coordenadas de SUMO se transforman como $(x, z - z_0, -(y - y_0))$ con el origen en el nodo, y las mallas estáticas se funden por material para reducir llamadas de dibujo.
