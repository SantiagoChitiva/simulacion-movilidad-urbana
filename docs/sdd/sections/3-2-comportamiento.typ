#import "uml.typ": *
#import "@preview/chronos:0.2.1" as chronos

== Comportamiento del sistema <sec-comportamiento>

Esta sección describe cómo cambia el sistema en el tiempo. Para cada acción compleja de la @sec-vista-procesos hay un diagrama de secuencia que usa las instancias y los métodos de las clases de la @sec-estructura; no se describe lo que sucede dentro de las librerías de terceros (FastAPI, TraCI, SUMO). Las acciones con pocas llamadas (por ejemplo, consultar una intersección o cargar una precalculada, que solo devuelve un archivo) no se diagraman. Al final se explican los algoritmos más complejos como guía de implementación.

=== Simulación parametrizada <sec-seq-simulacion>

Corresponde a los pasos 4 a 8 del proceso P1 (@fig-proceso-simular). La API responde enseguida y la corrida avanza en un hilo aparte mientras el visor consulta su estado.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(chronos.diagram({
      import chronos: *
      _par("V", display-name: "Visor")
      _par("A", display-name: "api.api")
      _par("G", display-name: "GestorCorridas")
      _par("H", display-name: "Hilo _correr")
      _par("P", display-name: "run_pipeline")
      _par("S", display-name: "SUMO")
      _seq("V", "A", comment: "POST /simulaciones")
      _seq("A", "A", comment: "valida la solicitud")
      _seq("A", "G", comment: "crear(demanda, ...)")
      _seq("G", "G", comment: "estado.json (en_cola)")
      _seq("G", "H", comment: "submit(_correr)", dashed: true)
      _seq("A", "V", comment: "202 {id}", dashed: true)
      _seq("H", "P", comment: "run_pipeline(...)")
      _seq("P", "P", comment: "viajes ordenados por depart")
      _seq("P", "S", comment: "duarouter")
      _seq("P", "S", comment: "sumo (TraCI, 60 s)")
      _seq("P", "P", comment: "exportar trips de kepler")
      _seq("P", "H", comment: "on_progreso(etapa, avance)", dashed: true)
      _seq("H", "G", comment: "_progreso -> estado.json", dashed: true)
      _loop("cada 2 s", {
        _seq("V", "A", comment: "GET /simulaciones/{id}")
        _seq("A", "G", comment: "obtener(id)")
        _seq("A", "V", comment: "estado, avance", dashed: true)
      })
      _seq("P", "H", comment: "PipelineResult", dashed: true)
      _seq("H", "H", comment: "borrar FCD; terminado")
      _alt("el usuario cancela", {
        _seq("V", "A", comment: "POST .../cancelar")
        _seq("A", "G", comment: "cancelar(id)")
        _seq("G", "H", comment: "Event.set()", dashed: true)
        _seq("H", "H", comment: "borrar todo salvo estado.json")
      })
    }))
  ],
  caption: [Diagrama de secuencia de una simulación parametrizada.],
) <fig-seq-simulacion>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Mensaje], [Explicación]),
    [`POST /simulaciones`], [La API valida el cuerpo (`SolicitudSimulacion`): total de viajes entre 1 y 100.000; si falla responde `422` sin crear nada.],
    [`crear(...)`], [`GestorCorridas.crear` genera el `id`, guarda `runs/<id>/estado.json` en estado `en_cola` y envía `_correr` al `ThreadPoolExecutor(1)`; solo corre una a la vez y las demás esperan en cola. La API devuelve `202` con el estado inicial.],
    [`run_pipeline`], [Genera los viajes (ordenados por hora de salida), llama a `duarouter`, simula con SUMO bajo TraCI y exporta los trips de kepler. Entre etapas revisa la cancelación (`revisar_cancelacion`).],
    [`on_progreso(etapa, avance)`], [Cada etapa informa su avance; `_progreso` lo mapea a la franja global (`FRANJAS_ETAPA`: demanda 0--2 %, ruteo 2--15 %, simulación 15--85 %, exportación 85--100 %) y `_guardar` escribe `estado.json` como mucho cada 2 s.],
    [`GET /simulaciones/{id}`], [El visor consulta cada 2 s hasta que el estado sea final (@fig-estados-corrida).],
    [`cancelar(id)`], [Activa el `threading.Event` de la corrida; este llega hasta el subproceso, que se termina. El trabajador lanza `Cancelado` y borra todos los archivos de la corrida menos `estado.json`.],
    [Al terminar], [`_correr` elimina el FCD (muy pesado, ~1,4 GB con la demanda completa) y marca la corrida `terminado` con el resumen (`resumen_corrida`).],
  ),
  caption: [Mensajes relevantes de la simulación parametrizada.],
)

=== Ciclo de vida de una corrida <sec-estados-corrida>

El atributo `estado` de `Corrida` evoluciona así:

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (9mm, 12mm),
      inicio((0, 0), name: <ini>),
      accion((1, 0), [`en_cola`], name: <cola>),
      accion((2, 0), [`generando_demanda`], name: <dem>),
      accion((3, 0), [`ruteando`], name: <rut>),
      accion((4, 0), [`simulando`], name: <sim>),
      accion((5, 0), [`exportando`], name: <exp>),
      accion((6, 0), [`terminado`], name: <ter>),
      accion((3.5, 1.3), [`cancelando`], name: <cng>),
      accion((1, 2.4), [`cancelada`], name: <can>),
      accion((5.5, 2.4), [`error`], name: <err>),
      fin((6, 1.2), name: <f1>),
      fin((0, 2.4), name: <f2>),
      fin((6.5, 2.4), name: <f3>),
      edge(<ini>, <cola>, "->", label: [`crear()`], label-side: left),
      edge(<cola>, <dem>, "->"),
      edge(<dem>, <rut>, "->"),
      edge(<rut>, <sim>, "->"),
      edge(<sim>, <exp>, "->"),
      edge(<exp>, <ter>, "->"),
      edge(<cola>, <can>, "->", label: [`cancelar()` (aún no empezaba)], label-side: left),
      edge(<dem>, <cng>, "->"),
      edge(<rut>, <cng>, "->"),
      edge(<sim>, <cng>, "->", label: [`cancelar()`], label-side: right),
      edge(<exp>, <cng>, "->"),
      edge(<cng>, <can>, "->", label: [`Cancelado`], label-side: left),
      edge(<sim>, <err>, "->", label: [excepción en\ cualquier etapa], label-side: right),
      edge(<ter>, <f1>, "->"),
      edge(<can>, <f2>, "->"),
      edge(<err>, <f3>, "->"),
    ))
  ],
  caption: [Diagrama de estados de una corrida.],
) <fig-estados-corrida>

Desde cualquier etapa activa (`generando_demanda`, `ruteando`, `simulando`, `exportando`) se puede pasar a `cancelando` con `cancelar()` o a `error` si una etapa lanza una excepción (se guarda el mensaje, últimos 2.000 caracteres). Tras un reinicio del servicio, las corridas que no estaban en un estado final (`terminado`, `error`, `cancelada`) pasan a `error` con el mensaje «Interrumpida: el servicio se reinició».

=== Preparación de la comparación 3D <sec-seq-prep3d>

Corresponde a los pasos 4 a 8 del proceso P3 (@fig-proceso-3d): la API responde enseguida y la zona se prepara en un hilo aparte, lo que puede tardar decenas de segundos.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(chronos.diagram({
      import chronos: *
      _par("V", display-name: "Visor")
      _par("A", display-name: "api.api")
      _par("G", display-name: "GestorComparaciones")
      _par("H", display-name: "Hilo prep")
      _par("R", display-name: "run_escenario_semaforo")
      _par("S", display-name: "SUMO tools")
      _seq("V", "A", comment: "POST /cruces/{nodo}/comparacion3d")
      _seq("A", "G", comment: "crear(nodo, lon, lat, ...)")
      _seq("G", "G", comment: "limpiar expiradas; máx. 2")
      _seq("G", "H", comment: "Thread(_trabajo)", dashed: true)
      _seq("A", "V", comment: "202 {id}", dashed: true)
      _seq("H", "R", comment: "_preparar(...)")
      _seq("R", "S", comment: "recortar_red")
      _seq("R", "S", comment: "agregar_semaforo")
      _seq("R", "S", comment: "demanda de zona")
      _seq("R", "R", comment: "geometria_escena")
      _seq("R", "H", comment: "info", dashed: true)
      _seq("H", "G", comment: "estado = lista", dashed: true)
      _loop("hasta lista o error", {
        _seq("V", "A", comment: "GET /comparacion3d/{id}")
        _seq("A", "V", comment: "estado, etapa", dashed: true)
      })
      _seq("V", "A", comment: "GET .../geometria")
      _seq("A", "V", comment: "geometría", dashed: true)
    }))
  ],
  caption: [Diagrama de secuencia de la preparación de una comparación 3D.],
) <fig-seq-prep3d>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Mensaje], [Explicación]),
    [`crear(...)`], [Registra la `Comparacion` en estado `preparando`; si ya hay dos abiertas lanza un error que la API traduce a `429`. Lanza un hilo de preparación y devuelve enseguida.],
    [`recortar_red`], [Recorta la red de Usaquén alrededor del cruce (radio de 350 m) con `netconvert`: `zona.net.xml` es el lado A (tal como está).],
    [`agregar_semaforo`], [Crea el lado B: parche que da `type="traffic_light"` y el mismo `tl` a todos los nodos del cruce, y `netconvert` genera `zona_tls.net.xml` (@sec-alg-semaforo-nuevo).],
    [Demanda de zona], [Viajes reales de la corrida pedida (o la más reciente con `vehroute`) recortados con `cutRoutes.py`, más tráfico de fondo por modo con `randomTrips.py`; la demanda es idéntica en los dos lados.],
    [`geometria_escena`], [Genera una sola vez el JSON de la escena (calzadas, andenes, terreno, edificios) que el visor convierte en geometría three.js.],
    [Si algo falla], [El hilo deja la comparación en `error` con el mensaje (máx. 500 caracteres) y el visor lo muestra.],
  ),
  caption: [Mensajes relevantes de la preparación.],
)

=== Ejecución en vivo de la comparación 3D <sec-seq-3d>

Corresponde a los pasos 8 a 12 del proceso P3. Al conectarse el WebSocket se arranca un hilo que lanza los dos SUMO, los calienta 240 s simulados y emite un frame por cada paso de 0,2 s simulados.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(chronos.diagram({
      import chronos: *
      _par("V", display-name: "Visor")
      _par("A", display-name: "ws_comparacion_3d")
      _par("H", display-name: "correr_comparacion")
      _par("C", display-name: "Comparacion")
      _par("LA", display-name: "Lado A")
      _par("LB", display-name: "Lado B")
      _seq("V", "A", comment: "WS /comparacion3d/{id}")
      _seq("A", "A", comment: "lista y sin conectar")
      _seq("A", "H", comment: "Thread(correr_comparacion)", dashed: true)
      _seq("H", "LA", comment: "Lado(A, zona.net.xml)")
      _seq("H", "LB", comment: "Lado(B, zona_tls.net.xml)")
      _loop("calentamiento 240 s", {
        _seq("H", "LA", comment: "avanzar(t)")
        _seq("H", "LB", comment: "avanzar(t)")
      })
      _loop("cada paso de 0,2 s", {
        _seq("H", "C", comment: "atender comandos")
        _seq("H", "LA", comment: "avanzar(t); controlar(ego)")
        _seq("H", "LB", comment: "avanzar(t); controlar(ego)")
        _alt("t >= próximo_riesgo", {
          _seq("H", "LA", comment: "telemetria; conflictos")
          _seq("H", "LB", comment: "telemetria; conflictos")
        })
        _seq("H", "A", comment: "frame (asyncio.Queue)", dashed: true)
        _seq("A", "V", comment: "frame JSON", dashed: true)
      })
      _seq("V", "A", comment: "comandos (pausa, manual, ...)")
      _seq("A", "C", comment: "atributos o comandos.put", dashed: true)
      _seq("H", "A", comment: "fin", dashed: true)
      _seq("H", "LA", comment: "cerrar()")
      _seq("H", "LB", comment: "cerrar()")
    }))
  ],
  caption: [Diagrama de secuencia de la ejecución en vivo de la comparación 3D.],
) <fig-seq-vivo3d>

El bucle de `correr_comparacion` es el siguiente:

#figure(
  block(width: 100%, inset: 8pt, stroke: 0.5pt + luma(150), radius: 3pt)[
    *correr_comparacion*(comp, cola, bucle):
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
- *Cierre.* Al cerrar la ventana el directorio `runs/sem-<id>/` se borra; si nadie se conecta en 180 s, la comparación expira.

=== Algoritmos de apoyo

Los siguientes algoritmos son la guía para implementar los métodos más complejos de las clases de la @sec-estructura.

==== Generación de viajes y orden de salida

Para cada fila válida del TSV se crea un `TripRecord` con `copies = min(round(fexp), MAX_COPIAS)`. Las copias se emiten con ids únicos y *se ordenan por `depart`* antes de escribir el XML. El orden es indispensable: el TSV no está ordenado, `duarouter` conserva el orden de entrada y SUMO *descarta* (no reordena) cualquier entidad cuya salida sea menor que la máxima ya cargada. Sin el orden se perdían cerca de 23.000 de ~24.600 viajes. Los vehículos se escriben como `<trip>`; los peatones y el transporte público, como `<person><walk>`.

==== Demanda parametrizada por presets <sec-alg-demanda>

Un preset es una regla de transferencia modal `ReglaTransferencia(origen, destinos, duracion_mayor_a, duracion_hasta)`. Con los viajes de *todo el día* se calcula $P(m | r)$: la probabilidad de cada modo $m$ en cada rango de duración $r$ (≤ 15, 15--30, 30--60 y > 60 min), ponderada por `fexp`. Después:

+ Para cada viaje de la ventana que cumple la regla, su peso (`copies`) se reparte entre los modos destino en proporción a $P(m | r)$ restringida a esos destinos; los demás viajes conservan su modo.
+ Resultan _pools_ por modo con pares (viaje, peso).
+ Para cada modo con conteo pedido $n_m$, se asignan copias a los viajes del _pool_ con el método del *mayor resto* (Hamilton): $n_m w_i / sum_j w_j$ se trunca y las unidades que faltan se dan a las partes decimales mayores. La suma es exacta y el resultado es determinista.
+ Si un modo no tiene _pool_ en el preset (p. ej. autos en «día sin carro»), se usa el _pool_ base de la encuesta.

Propiedades verificadas por pruebas: los presets conservan el total; un viaje transferido mantiene su origen/destino y su hora de salida; y con `encuesta` y sus conteos por defecto se reproduce exactamente la expansión simple de la encuesta.

==== Ejecución de SUMO bajo TraCI

`simulation._run_traci` lanza `sumo` con `--remote-port` libre, se conecta con reintentos y avanza con `simulationStep` en saltos de 60 s hasta `<end>`. Tras cada salto calcula el avance de la ventana y revisa la cancelación; ante cancelación o tiempo máximo mata el proceso. Los archivos de salida son los mismos que sin TraCI. Se usa TraCI, y no el registro de SUMO, porque con la salida redirigida a un _pipe_ SUMO y `duarouter` almacenan su bitácora por bloques y esta solo llega al terminar; por eso el avance de `duarouter` se mide con el último `depart` escrito en el `.rou.xml`.

==== Reducción de puntos para kepler

`kepler.reduce_points` primero colapsa cada tramo quieto (misma posición en puntos consecutivos) a su primer y último punto y luego muestrea lo que queda: siempre conserva el primer y el último punto de la entidad, y entre ellos guarda un punto cada `step` segundos (8 s en el pipeline; 5 s por defecto del módulo) o cuando el rumbo cambia al menos 20°. Las entidades que se mueven menos de `min_move` = 20 m se descartan y se cuentan. Las posiciones con `inf` o `z` fuera de ±100.000 se ignoran como inválidas.

==== Priorización de cruces sin semáforo <sec-alg-priorizacion>

El análisis de la red (independiente de la corrida) y el puntaje (dependiente de los volúmenes) se separan para poder cachear la parte costosa.

*Análisis (con caché `priorizacion.json`):*

+ Se agrupan nodos de SUMO a menos de 20 m (extensión máxima 45 m) y se fusionan los grupos del mismo par de calles a menos de 150 m (las dos calzadas de una avenida; extensión máxima 200 m). Un cruce requiere dos calles distintas que se corten a más de 35°.
+ *Reglas duras, todas obligatorias:* participa una vía colectora (`tertiary`) o superior, sin autopistas ni troncales; la otra vía es al menos residencial; sin rampas ni glorietas a menos de 40 m; conflicto real (la vía secundaria cruza de frente o gira a la izquierda); sin semáforo a menos de 80 m.
+ *Evidencia*, calibrada contra los cruces ya semaforizados de la propia red (_backtest_): siniestros a menos de 30 m ≥ p75 (mínimo 3), o ≥ mediana con un generador cerca; tramo de la vía principal sin semáforo ≥ 600 m; volumen simulado de entrada ≥ p75. Generadores: colegios, jardines, universidades, hospitales y clínicas a menos de 200 m.

*Puntaje (en cada consulta):* número de evidencias «fuertes» $e$ → nivel `prioritario` ($e >= 2$), `recomendado` ($e = 1$) u `observacion` (solo generador o siniestros ≥ mediana). El puntaje es un piso por nivel (75 / 50 / 25) más hasta 25 puntos:

$ "puntaje" = "piso" + 25 (0,35 s + 0,30 v + 0,15 g + 0,10 t + 0,10 h) $

con $s$ el rango percentil de siniestros, $v$ el de volumen, $g = min(g_"n" / 3, 1)$ los generadores, $t = min("tramo" / 1200, 1)$ y $h$ la jerarquía. Finalmente, una _supresión de no máximos_ (NMS): dos cruces del mismo nivel a menos de 120 m se estudian juntos y el de menor puntaje baja un nivel. La lógica sigue la del proyecto Semáforos de Barranquilla, sin su modelo de lenguaje.

==== Programas de semáforo y Webster <sec-alg-webster>

`validar_programa` exige que cada fase tenga tantos caracteres como movimientos controlados, que haya al menos una fase amarilla ≥ 3 s si hay verdes y un ciclo ≥ 15 s. El cálculo de Webster @webster usa:

$ C_0 = (1,5 L + 5) / (1 - Y), quad L = n_"fases" dot 3 "s", quad Y = sum_i max_j (q_j / s) $

con flujo de saturación $s$ = 1.800 veh/h por carril. Los verdes se reparten en proporción a $y_i / Y$ (mínimo 5 s) y el ciclo mínimo es 30 s; si $Y >= 1$ la intersección está sobresaturada y se devuelve un error. *Limitación conocida:* los accesos se asignan a las fases de forma circular (no según los movimientos compatibles reales), y si no hay volumen simulado se usa un valor de demostración de 300 veh/h. La API lo advierte en la respuesta (`nota`).

==== Variante con semáforo propuesto <sec-alg-semaforo-nuevo>

`agregar_semaforo` verifica que ningún nodo del cruce tenga ya semáforo, escribe un parche `semaforo_propuesto.nod.xml` que da a *todos* los nodos del cruce `type="traffic_light"` y el mismo `tl` (un solo `tlLogic` controla el cruce completo, p. ej. las dos calzadas) y ejecuta `netconvert` con `--tls.default-type` sobre la red de la zona (`--geometry.remove false`). Luego comprueba que se generó un programa con fases.

==== Indicadores de riesgo <sec-alg-riesgo>

Funciones puras en `telemetria.py`, calculadas sobre lo que TraCI reporta del actor seguido:

- $"TTC" = "gap" / (v - v_"líder")$ si el actor se acerca al líder.
- $"DRAC" = (v - v_"líder")^2 / (2 dot "gap")$ (m/s²).
- $"PET"$ aproximado en el cruce: diferencia entre las llegadas del ego y de un vehículo en conflicto (`getJunctionFoes`) al punto de cruce.

Cada indicador se normaliza de 0 (umbral seguro) a 100 (umbral crítico o peor): TTC 6 → 1,5 s; DRAC 0 → 3,35 m/s²; PET 5 → 1,5 s. El índice de riesgo es el *mayor* de los tres (manda el más grave, que además se informa como causa) y su nivel es bajo (< 30), medio (30--59) o alto (≥ 60); los umbrales provienen de la literatura de SSM @ssm. `clasificar_accion` traduce velocidad, aceleración, luz próxima, brecha y cesión de paso en una acción legible («Detenido en el semáforo», «Frenada fuerte», etc.). Las métricas por lado cuentan como conflicto un cruce con PET < 1,5 s entre vehículos a menos de 60 m del nodo.

==== Escena 3D

`geometria_escena` produce, una sola vez, el JSON que el visor convierte en geometría: calzadas, andenes, cebras y bocas de calle desde la red; un poste de semáforo por acceso; un terreno de rejilla por interpolación de distancia inversa (IDW) a partir de las alturas de calzadas y cruces; edificios de OSM y Microsoft deduplicados por solape, más un relleno ilustrativo (`relleno: true`) en los frentes de manzana vacíos que no se superponga con los reales. En el cliente, las coordenadas de SUMO se transforman como $(x, z - z_0, -(y - y_0))$ con el origen en el nodo, y las mallas estáticas se funden por material para reducir llamadas de dibujo.
