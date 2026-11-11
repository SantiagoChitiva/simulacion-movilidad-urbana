#import "uml.typ": *

== Estructura del sistema <sec-estructura>

Esta sección presenta, para cada componente de software de la @sec-vista-logica, un diagrama de clases con su explicación. Se usa la notación UML con estas convenciones:

- Cada recuadro tiene tres compartimentos (nombre, atributos y métodos). El estereotipo indica el tipo: «dataclass» (clase de datos de Python), «módulo» (funciones agrupadas en un archivo, sin instanciarse), «componente» y «hook» (React), «modelo» (esquema Pydantic) y «enum».
- `+` es público y `-` es de uso interno (en el código, con prefijo `_`).
- Flecha continua: asociación (el origen guarda o usa una referencia al destino). Flecha con rombo: composición (el origen contiene al destino y controla su ciclo de vida). Flecha punteada: dependencia (el origen invoca al destino o lo recibe como parámetro).
- Los atributos se muestran con su tipo de Python o de JavaScript; `?` indica que puede ser nulo.

Todos los módulos de `etl/sumo/` siguen un mismo patrón para ser predecibles y fáciles de probar: un `*Config` inmutable (`dataclass(frozen=True)`) con los parámetros y, si invoca una herramienta de SUMO, un método `to_args()`; un `*Result` con lo producido; y un `*Stats` mutable que se pasa y se incrementa durante el proceso. Los envoltorios de subprocesos buscan el binario con `shutil.which` y lanzan una excepción propia (`*Error(RuntimeError)`). Los procesos largos aceptan `on_avance` y `cancelar` y los ejecutan a través de `proceso.ejecutar`, que consulta ambos cada 0,5 s.

=== Visor web (`kepler/src`) <sec-clases-visor>

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (7mm, 9mm),
      clase((1, 1), "Visor", est: "componente", attrs: ("-modos, precalculadas", "-corridaMapa", "-carga, aviso", "-pestana: demanda|interseccion|cierres|semaforizar", "-interseccion, cruceCandidato", "-candidatos, simulador", "-cierres"), metodos: ("-cargarCorrida()", "-cancelarCarga()", "-descartarAviso()", "-limpiarInteraccion()"), name: <visor>),
      clase((0, 0), "useCorridas", est: "hook", attrs: ("+corridas (historial)", "+corrida activa"), metodos: ("+refrescar()", "+lanzar()", "+cancelar()", "+descartar()"), name: <hc>),
      clase((1, 0), "ClienteApi", est: "módulo", metodos: ("+pedir(ruta, opciones)", "+descargarJson(url, progreso)", "+crearSimulacion(solicitud)", "+obtenerIntersecciones(corrida)", "+guardarPrograma(...)", "+calcularWebster(...)", "+crearComparacion3D(...)"), name: <api>),
      clase((2, 0), "useTamanoVentana", est: "hook", attrs: ("+tamano: {ancho, alto}",), name: <ht>),
      clase((0, 1), "PanelDemanda", est: "componente", attrs: ("+presets, modos, conteos", "+semilla, estilo"), metodos: ("-elegirPreset()", "-aplicarEscala()", "-verCorrida()", "-ejecutar()"), name: <pd>),
      clase((2, 1), "PanelCierres", est: "componente", attrs: ("+cierres: lista",), metodos: ("-agregar()", "-eliminar()"), name: <pc>),
      clase((0, 2), "TarjetaActividad", est: "componente", attrs: ("+corrida, carga, aviso",), metodos: ("+onCancelar()", "+onDescartar()"), name: <ta>),
      clase((1, 2), "FichaInterseccion", est: "componente", attrs: ("+id, corrida",), metodos: ("-cambiarFase()", "-guardar()", "-aplicarWebster()", "-restaurar()"), name: <fi>),
      clase((2, 2), "PanelSemaforizacion", est: "componente", attrs: ("+seleccionado, candidatos", "+INTENSIDADES_DEFECTO"), name: <ps>),
      clase((3, 0), "LeyendaModos", est: "componente", attrs: ("+modos, presentes",), name: <lm>),
      clase((1, 3), "TablaComparacion", est: "componente", attrs: ("+id, corrida",), metodos: ("-lanzar()",), name: <tc>),
      edge(<visor>, <hc>, "-->"),
      edge(<visor>, <ht>, "-->"),
      edge(<visor>, <api>, "-->"),
      edge(<hc>, <api>, "-->"),
      edge(<visor>, <pd>, "*->"),
      edge(<visor>, <pc>, "*->"),
      edge(<visor>, <ps>, "*->"),
      edge(<visor>, <ta>, "*->"),
      edge(<visor>, <fi>, "*->"),
      edge(<visor>, <lm>, "*->"),
      edge(<fi>, <tc>, "*->"),
    ))
  ],
  caption: [Diagrama de clases del visor: contenedor, hooks, cliente de la API y paneles.],
) <fig-clases-visor>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase], [Responsabilidad, atributos y métodos]),
    [`Visor` (`App.jsx`)], [Dueño del mapa y del estado global de la pantalla. Descarga los viajes con progreso y `AbortController`, reemplaza el conjunto de datos de kepler.gl, activa las capas de semáforos y de priorización y abre la ficha de intersección leyendo `visState.clicked`. *Atributos:* `modos` y `precalculadas` (catálogos de la API), `corridaMapa` (corrida mostrada; nulo es la corrida por defecto), `carga` y `aviso` (progreso y mensaje de la descarga), `pestana` (panel activo), `interseccion` (semáforo abierto), `cruceCandidato` y `candidatos` (priorización), `simulador` (parámetros del 3D abierto) y `cierres`. *Métodos:* `cargarCorrida` baja y muestra los viajes de una corrida; `cancelarCarga` aborta la descarga en curso; `descartarAviso` oculta el aviso; `limpiarInteraccion` cierra la ficha y el candidato elegidos.],
    [`useCorridas`], [Hook que maneja el historial de corridas, la corrida activa, la consulta cada 2 s y la cancelación. *Métodos:* `refrescar` consulta la API; `lanzar` crea una corrida; `cancelar` pide cancelarla; `descartar` la quita de la tarjeta de actividad.],
    [`useTamanoVentana`], [Hook que mantiene el ancho y alto de la ventana, que kepler.gl necesita de forma explícita (el `body` tiene `overflow: hidden`).],
    [`ClienteApi` (`api.js`)], [Cliente HTTP único; todas las rutas son relativas a `/api`. `pedir` ejecuta la petición y convierte los errores de la API en mensajes legibles; `descargarJson` descarga con barra de progreso (usa `X-Tamano-Original` en las precalculadas). Las demás funciones corresponden una a una a los endpoints de la @tab-endpoints.],
    [`PanelDemanda`], [Presets, conteos por modo, escala, semilla y estilo. `elegirPreset` carga los conteos del preset; `aplicarEscala` multiplica los conteos; `verCorrida` muestra una corrida del historial; `ejecutar` decide entre «Simular» y «Cargar simulación».],
    [`PanelCierres`], [Define cierres viales (edge y horario). `agregar` y `eliminar` modifican la lista, que viaja en la solicitud de simulación.],
    [`TarjetaActividad`], [Tarjeta inferior derecha con barras de progreso de la corrida y de la descarga, avisos y botón de cancelar.],
    [`FichaInterseccion`], [Accesos, volúmenes y fases del semáforo, edición del programa (`cambiarFase`, `guardar`, `restaurar`), cálculo de Webster (`aplicarWebster`) y comparación de programas.],
    [`PanelSemaforizacion`], [Pestaña «Semaforizar»: lista de cruces candidatos por puntaje, tráfico de fondo por modo (`INTENSIDADES_DEFECTO`) y botón para abrir el simulador 3D.],
    [`LeyendaModos`], [Leyenda de colores por modo y conmutador de la capa «Semáforos».],
    [`TablaComparacion`], [Compara los programas de un semáforo por sus métricas; `lanzar` pide la comparación a la API.],
  ),
  caption: [Clases del visor y su explicación.],
)

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Asociación], [Significado]),
    [`Visor` ◆→ paneles], [El visor contiene y renderiza `PanelDemanda`, `PanelCierres`, `PanelSemaforizacion`, `TarjetaActividad`, `FichaInterseccion` y `LeyendaModos`; les pasa propiedades y recibe eventos.],
    [`FichaInterseccion` ◆→ `TablaComparacion`], [La ficha incluye la tabla de comparación de programas.],
    [`Visor` ⇢ `useCorridas`, `useTamanoVentana`], [El visor usa los hooks para el historial de corridas y el tamaño de la ventana.],
    [`Visor`, `useCorridas` ⇢ `ClienteApi`], [Todo acceso a la API pasa por el cliente único.],
  ),
  caption: [Asociaciones del diagrama del visor.],
)

==== Simulador 3D (`kepler/src/components/simulador3d`)

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((1, 0), "Simulador3D", est: "componente", attrs: ("+cruce, candidatos", "+corrida, intensidades", "-estado: preparando|lista|error", "-socket: WebSocket"), metodos: ("-enviar(cmd)", "-alternarManual()", "-lanzarActor()", "-seguir(id)", "-masCercano()", "-irAVia(nombre)"), name: <s3d>),
      clase((0, 1), "Escena3D", est: "clase JS", attrs: ("-escena, camara, render", "-actores: Map", "+conSemaforo: bool"), metodos: ("+actualizarLuces(luces)", "+actualizarActores(veh, per, ego)", "+posicionActor(id)", "+setModoCamara(modo)", "+mirarA(x, y, z)", "+render(dt)", "+redimensionar()", "+destruir()"), name: <esc>),
      clase((1, 1), "HUD", est: "componente", attrs: ("+conSemaforo, lado", "+egoId, manual, subtitulo"), name: <hud>),
      clase((2, 1), "Minimapa", est: "componente", attrs: ("+nodo, bbox", "+ego, egoId, rumbo, seguir"), name: <mm>),
      clase((2, 0), "LimiteErrores", est: "componente", metodos: ("+render()",), attrs: ("-error",), name: <le>),
      edge(<s3d>, <esc>, "*->", label: [2 (lados A y B)], label-side: left),
      edge(<s3d>, <hud>, "*->"),
      edge(<s3d>, <mm>, "*->"),
      edge(<le>, <s3d>, "->", label: [envuelve], label-side: left),
    ))
  ],
  caption: [Diagrama de clases del simulador 3D.],
) <fig-clases-3d>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase], [Responsabilidad, atributos y métodos]),
    [`Simulador3D`], [Ciclo de vida: crear la comparación → consultar su estado → obtener la geometría → conectar el WebSocket; pantalla dividida «sin semáforo» y «con semáforo propuesto». *Atributos:* parámetros recibidos (`cruce`, `candidatos`, `corrida`, `intensidades`), estado de la preparación y socket. *Métodos:* `enviar` manda un comando por el WebSocket; `alternarManual` entra o sale de la conducción manual; `lanzarActor` inyecta un actor propio; `seguir` cambia el actor seguido; `masCercano` elige el actor más próximo al cruce; `irAVia` mueve la vista a una vía por nombre.],
    [`Escena3D` (`escena.js`)], [Una escena three.js por lado. Convierte las coordenadas de SUMO a three como $(x, z - z_0, -(y - y_0))$ con el origen en el nodo; funde las mallas estáticas por material; interpola los actores entre frames; ofrece cámara de persecución con colisión contra edificios o aérea. *Métodos:* `actualizarLuces` fija el estado del semáforo; `actualizarActores` recibe vehículos, personas y el ego de un frame; `posicionActor` devuelve la posición de un actor; `setModoCamara` y `mirarA` controlan la cámara; `render` dibuja un cuadro; `redimensionar` ajusta el lienzo; `destruir` libera recursos de WebGL.],
    [`HUD`], [Píldora superior (tiempo, velocidad, pausa) y tarjeta inferior con la telemetría del actor seguido, el índice de riesgo y la comparación de métricas por lado.],
    [`Minimapa`], [Minimapa con teselas OSM (maplibre-gl, sin token). maplibre fuerza `position: relative` en su contenedor, por lo que el posicionamiento absoluto vive en un `div` envoltorio.],
    [`LimiteErrores`], [Barrera de errores (_error boundary_): un fallo gráfico no tumba el mapa.],
  ),
  caption: [Clases del simulador 3D y su explicación.],
)

*Asociaciones.* `Simulador3D` contiene dos `Escena3D` (una por lado), un `HUD` y un `Minimapa`, y los alimenta con los frames del WebSocket. `LimiteErrores` envuelve a `Simulador3D`, que se carga de forma diferida (`lazy`) porque three.js y maplibre pesan.

=== API y orquestación de corridas (`simulation-service/src/api`) <sec-clases-api>

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((0, 0), "SolicitudSimulacion", est: "modelo", attrs: ("+preset: Preset", "+conteos: dict[TransportMode,int]", "+semilla: int?", "+estilo: EstiloConductor", "+cierres: SolicitudCierre[]"), name: <ssim>),
      clase((0, 1), "SolicitudCierre", est: "modelo", attrs: ("+edge_id: str", "+hora_inicio: float", "+hora_fin: float", "+modos_afectados: str?"), name: <scie>),
      clase((1, 0), "api.api", est: "módulo", metodos: ("+crear_simulacion()", "+cancelar_simulacion()", "+listar_simulaciones()", "+obtener_simulacion()", "+kepler_trips_simulacion()", "+obtener_gestor()"), name: <api>),
      clase((2, 0), "GestorCorridas", attrs: ("-_corridas: dict[str, Corrida]", "-_cancelaciones: dict[str, Event]", "-_futuros: dict", "-_pool: ThreadPoolExecutor(1)", "-_ejecutar: Callable"), metodos: ("+crear(demanda, semilla, estilo, cierres)", "+cancelar(run_id)", "+obtener(run_id)", "+listar()", "+paths(run_id)", "+esperar(run_id)", "-_correr(...)", "-_progreso(run_id, etapa, avance)", "-_guardar(corrida)", "-_cargar_existentes()", "-_borrar_archivos_pesados(run_id)"), name: <gc>),
      clase((2, 1), "Corrida", est: "dataclass", attrs: ("+id, preset: str", "+conteos: dict[str,int]", "+semilla: int?", "+estilo: str", "+cierres: list", "+estado: str", "+avance: float", "+avance_etapa: float?", "+creada, iniciada, actualizada", "+error: str?", "+resultado: dict?"), name: <cor>),
      clase((1, 1), "run_pipeline", est: "módulo etl", metodos: ("+run_pipeline(..., on_progreso, cancelar)",), name: <rp>),
      edge(<api>, <ssim>, "-->", label: [valida], label-side: left),
      edge(<ssim>, <scie>, "*->"),
      edge(<api>, <gc>, "-->", label: [`Depends`], label-side: left),
      edge(<gc>, <cor>, "*->", label: [0..\*], label-side: left),
      edge(<gc>, <rp>, "-->", label: [ejecuta en el hilo], label-side: right),
    ))
  ],
  caption: [Diagrama de clases de la API y de la orquestación de corridas.],
) <fig-clases-api>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase], [Responsabilidad, atributos y métodos]),
    [`SolicitudSimulacion`], [Cuerpo de `POST /simulaciones`. Valida con Pydantic que cada conteo esté entre 0 y 100.000 y que el total esté entre 1 y 100.000 viajes (si no, `422`), y que la semilla sea ≥ 0. `preset`, `estilo` y las claves de `conteos` son enumerados: rechazan cualquier otro texto.],
    [`SolicitudCierre`], [Un cierre vial: `edge_id` del tramo, hora de inicio y fin en segundos, y modos afectados. El ETL lo convierte en un `rerouter` de SUMO.],
    [`api.api`], [Aplicación FastAPI: define las rutas HTTP y el WebSocket, traduce errores a códigos HTTP y obtiene los gestores por inyección de dependencias (`obtener_gestor`, `obtener_gestor_comparaciones`), sustituibles en pruebas con `dependency_overrides`. Los métodos mostrados atienden las rutas de corridas de la @tab-endpoints.],
    [`GestorCorridas`], [Cola de un solo trabajador (`ThreadPoolExecutor(1)`): solo una corrida pesada corre a la vez y las demás quedan `en_cola`. *Métodos:* `crear` genera el id (`AAAAMMDD-HHMMSS-<6 hex>`), persiste la corrida y la encola; `cancelar` activa el `threading.Event` de la corrida (si aún no empezaba, la marca `cancelada`; si no, `cancelando`) y lanza `ValueError` si ya terminó; `obtener` y `listar` consultan (la más reciente primero); `paths` devuelve los `ScenarioPaths` de la corrida; `esperar` bloquea hasta que termine (pruebas); `_correr` es el trabajo del hilo: llama a `run_pipeline`, borra el FCD y registra el estado final; `_progreso` traduce el avance de la etapa a la franja global (`FRANJAS_ETAPA`); `_guardar` escribe `estado.json` (como mucho cada 2 s mientras avanza); `_cargar_existentes` reconstruye el historial al arrancar y marca como `error` las corridas que estaban activas («Interrumpida: el servicio se reinició»); `_borrar_archivos_pesados` deja solo `estado.json` en una corrida cancelada.],
    [`Corrida`], [Estado persistente de una corrida (se serializa a `estado.json`, @sec-persistencia-corrida). El `estado` recorre `en_cola` → `generando_demanda` → `ruteando` → `simulando` → `exportando` → `terminado`, o termina en `cancelando`, `cancelada` o `error`.],
    [`run_pipeline`], [Función del ETL (@sec-clases-etl), único punto de entrada de una corrida; recibe `on_progreso(etapa, avance|None)` y `cancelar`.],
  ),
  caption: [Clases de la API y de la orquestación de corridas.],
)

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Asociación], [Significado]),
    [`api.api` ⇢ `SolicitudSimulacion`], [La ruta valida el cuerpo con el modelo antes de crear la corrida.],
    [`SolicitudSimulacion` ◆→ `SolicitudCierre` (0..\*)], [La solicitud contiene sus cierres viales.],
    [`api.api` ⇢ `GestorCorridas`], [La ruta recibe el gestor inyectado con `Depends`.],
    [`GestorCorridas` ◆→ `Corrida` (0..\*)], [El gestor guarda todas las corridas y controla su ciclo de vida.],
    [`GestorCorridas` ⇢ `run_pipeline`], [El hilo trabajador invoca el pipeline (inyectable como `_ejecutar` para usar uno falso en las pruebas).],
  ),
  caption: [Asociaciones del diagrama de la API.],
)

==== Comparación 3D (`api/comparacion3d.py`)

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((0, 0), "GestorComparaciones", attrs: ("-_comparaciones: dict[str, Comparacion]", "-_lock: Lock", "-_runs_dir: Path", "-_preparar: Callable"), metodos: ("+crear(nodo_id, lon, lat, run_id, intensidades, nodos)", "+obtener(cid)", "+cerrar(cid)", "+listar()", "-_limpiar_expiradas()"), name: <gcmp>),
      clase((1, 0), "Comparacion", est: "dataclass", attrs: ("+cid, nodo_id: str", "+run_dir: Path", "+nodos: list[str]", "+estado: preparando|lista|error", "+etapa: str?", "+info, geometria: dict", "+error: str?", "+conectada, activa: bool", "+pausada: bool", "+velocidad, periodo_riesgo: float", "+manual: bool, acelerar: int", "+comandos: Queue"), metodos: ("+resumen()",), name: <cmp>),
      clase((2, 0), "Lado", attrs: ("+nombre: A|B", "+nodo: dict, tl_id: str?", "+con: conexión TraCI", "+proc: Popen (sumo)", "+colisiones, conflictos: int", "+riesgo: dict?, max_riesgo: float", "+historial: list"), metodos: ("+avanzar(hasta)", "+tiempo()", "+actores()", "+luces()", "+contar_conflictos()", "+ruta(ego)", "+existe(ego)", "+telemetria(ego, actores, medir)", "+tomar_control(ego, manual)", "+controlar(ego, acelerar, dt)", "+girar(ego, destino)", "+inyectar(ego_id, tipo, edges, estilo)", "+stderr()", "+cerrar()"), name: <lado>),
      clase((1, 1), "correr_comparacion", est: "módulo", metodos: ("+correr_comparacion(comp, cola, bucle)", "-_ruta_inyeccion(accesos, acceso, giro)", "-_destino_giro(accesos, ruta, giro)", "+mensaje_json(texto)"), name: <cc>),
      clase((0, 1), "run_escenario_semaforo", est: "módulo etl", metodos: ("+run_escenario_semaforo(...)",), name: <res>),
      edge(<gcmp>, <cmp>, "*->", label: [0..2], label-side: left),
      edge(<cc>, <cmp>, "->", label: [lee y escribe], label-side: left),
      edge(<cc>, <lado>, "->", label: [2 (A y B)], label-side: right),
      edge(<gcmp>, <res>, "-->", label: [prepara], label-side: left),
    ))
  ],
  caption: [Diagrama de clases de la comparación 3D.],
) <fig-clases-comparacion>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase], [Responsabilidad, atributos y métodos]),
    [`GestorComparaciones`], [Mantiene las comparaciones abiertas (máximo 2, si no `429`), prepara cada zona en un hilo y libera las abandonadas. *Métodos:* `crear` registra la comparación (`sem-AAAAMMDD-HHMMSS-<6 hex>`) y lanza el hilo de preparación, que al terminar la deja `lista` o `error`; `obtener` devuelve una comparación y renueva su `ultimo_ping`; `cerrar` la desactiva y borra su directorio en segundo plano (hasta 5 reintentos por el bloqueo de archivos de Windows); `listar` devuelve los resúmenes; `_limpiar_expiradas` elimina las que nadie conectó en 180 s. `_preparar` es inyectable en pruebas.],
    [`Comparacion`], [Estado de una comparación y mandos en vivo. `estado`, `etapa`, `info`, `geometria` y `error` describen la preparación; `conectada` impide que haya dos ventanas; `pausada`, `velocidad`, `periodo_riesgo`, `manual` y `acelerar` se leen en cada paso del bucle; `comandos` es la cola de los comandos que no son simples banderas (seguir, inyectar, manual, giro). `resumen` entrega el estado sin la geometría de accesos.],
    [`Lado`], [Una instancia de SUMO con TraCI y el estado que se le sigue por frame. El constructor lanza `sumo` con un puerto libre y se conecta. *Métodos:* `avanzar` lleva la simulación a un instante (filtra con `getIDList()` los actores que ya salieron antes de suscribirse); `tiempo` da el instante actual; `actores` devuelve vehículos y personas como `[id, tipo, x, y, z, ángulo, v, edge]`; `luces` el estado del semáforo (nulo en el lado A); `contar_conflictos` cuenta cruces con PET < 1,5 s; `ruta` y `existe` consultan al ego; `telemetria` arma la telemetría y el riesgo del ego; `tomar_control` y `controlar` implementan la conducción manual con `setSpeed`; `girar` cambia el destino con `changeTarget`; `inyectar` agrega un actor propio; `stderr` devuelve el final del _stderr_ de SUMO; `cerrar` termina la conexión y el proceso.],
    [`correr_comparacion`], [Bucle síncrono (en un hilo) que avanza A y B a la par y publica frames en una `asyncio.Queue` (@sec-seq-3d). `_ruta_inyeccion` y `_destino_giro` calculan la ruta de un actor inyectado y el último _edge_ de un giro; `mensaje_json` interpreta un mensaje de texto del cliente.],
    [`run_escenario_semaforo`], [Función del ETL que prepara `zona.net.xml`, `zona_tls.net.xml` y la demanda compartida (@sec-clases-escena).],
  ),
  caption: [Clases de la comparación 3D.],
)

*Asociaciones.* `GestorComparaciones` contiene hasta dos `Comparacion` y delega la preparación de la zona en `run_escenario_semaforo`. `correr_comparacion` lee y escribe una `Comparacion` (mandos y estado) y maneja exactamente dos `Lado`: A (red sin semáforo) y B (red con el semáforo propuesto).

=== ETL de demanda y simulación (`simulation-service/src/etl`) <sec-clases-etl>

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (7mm, 9mm),
      clase((0, 0), "ScenarioPaths", est: "dataclass", attrs: ("+root, run_dir: Path", "+tsv, net, taz: Path", "+trips, routes, sumocfg: Path", "+fcd, kepler_trips: Path", "+statistics, vehroute: Path"), metodos: ("+from_name(name, run_id)",), name: <sp>),
      clase((1, 0), "TripGenerationConfig", est: "dataclass", attrs: ("+tsv_path, output_path: Path", "+hora_ini, hora_fin: int", "+max_copias: int", "+demanda: DemandaConfig?"), name: <tgc>),
      clase((2, 0), "DemandaConfig", est: "dataclass", attrs: ("+preset: Preset", "+conteos: dict[M,int]"), name: <dc>),
      clase((3, 0), "Preset", est: "enum", attrs: ("encuesta", "mas_vehiculos", "mas_peatones", "dia_sin_carro"), name: <pr>),
      clase((0, 1), "TripGenerationStats", est: "dataclass", attrs: ("+filas_totales, filas_invalidas", "+fuera_de_ventana", "+modos_desconocidos", "+viajes_generados", "+por_modo: Counter"), name: <tgs>),
      clase((1, 1), "TripRecord", est: "dataclass", attrs: ("+depart: float", "+mode: TransportMode", "+copies: int", "+origin_taz, destination_taz", "+duracion_min: float?", "+fexp: float"), name: <tr>),
      clase((2, 1), "ReglaTransferencia", est: "dataclass", attrs: ("+origen: set[M]", "+destinos: set[M]", "+duracion_mayor_a: float?", "+duracion_hasta: float?"), metodos: ("+aplica(trip)",), name: <rt>),
      clase((3, 1), "InfoPreset", est: "dataclass", attrs: ("+nombre, descripcion: str", "+regla: ReglaTransferencia?"), name: <ip>),
      clase((0, 2), "DuarouterConfig", est: "dataclass", attrs: ("+net_file, trips_file: Path", "+taz_file, output_file: Path", "+threads: int", "+ignore_errors, repair: bool"), metodos: ("+to_args()", "+required_inputs()"), name: <dr>),
      clase((1, 2), "SimulationConfig", est: "dataclass", attrs: ("+sumocfg: Path", "+seed, begin, end: int?", "+log_file: Path?"), metodos: ("+to_args()", "+ventana()"), name: <sc>),
      clase((2, 2), "KeplerTripsConfig", est: "dataclass", attrs: ("+fcd_path, output_path: Path", "+step, angle, min_move: float", "+base_date: str", "+z_scale, z_base: float?"), name: <kc>),
      clase((1, 3), "PipelineResult", est: "dataclass", attrs: ("+etl: EtlResult", "+simulation: SimulationResult", "+geojson: FcdConversionResult?", "+kepler: KeplerTripsResult"), name: <pres>),
      edge(<sp>, <tgc>, "-->", label: [rutas], label-side: left),
      edge(<tgc>, <dc>, "->"),
      edge(<dc>, <pr>, "->"),
      edge(<tgc>, <tr>, "-->", label: [genera], label-side: right),
      edge(<tgc>, <tgs>, "-->"),
      edge(<ip>, <pr>, "->", label: [`PRESETS`], label-side: right),
      edge(<ip>, <rt>, "->", label: [0..1], label-side: right),
      edge(<rt>, <tr>, "-->", label: [`aplica`], label-side: left),
      edge(<dr>, <pres>, "-->"),
      edge(<sc>, <pres>, "-->"),
      edge(<kc>, <pres>, "-->"),
    ))
  ],
  caption: [Diagrama de clases del ETL: configuraciones, demanda parametrizada y resultado del pipeline.],
) <fig-clases-etl>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase o módulo], [Responsabilidad, atributos y métodos]),
    [`ScenarioPaths`], [Única fuente de verdad para las rutas de un escenario. Los insumos están en `scenarios/<nombre>/`; los archivos generados van ahí o, si se da `run_id`, en `runs/<run_id>/` para que las corridas no se pisen. `from_name(name, run_id)` arma todas las rutas; los nombres de salida deben coincidir con el `.sumocfg` (p. ej. `output-prefix="usaquen_am."`).],
    [`TripGenerationConfig`], [Parámetros de la generación de viajes: TSV de entrada, XML de salida, ventana horaria (07:00--10:00), tope de copias por viaje (`MAX_COPIAS` = 50) y la `demanda` parametrizada (nulo = encuesta tal cual).],
    [`TripGenerationStats`], [Contadores mutables: `filas_invalidas`, `fuera_de_ventana` y `modos_desconocidos` se cuentan, no se descartan en silencio; `viajes_generados` y `por_modo` resumen la salida. La clase `TripGenerationResult` agrupa el XML escrito y las estadísticas.],
    [`TripRecord`], [Un viaje de la encuesta ya validado, antes de expandirse en `copies` copias (`min(round(fexp), MAX_COPIAS)`).],
    [`DemandaConfig`], [Preset elegido y viajes por modo a generar.],
    [`Preset`, `InfoPreset`], [Los cuatro presets (`encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`); cada `InfoPreset` tiene nombre, descripción y una `ReglaTransferencia` opcional (`encuesta` no tiene).],
    [`ReglaTransferencia`], [Qué viajes cambian de modo (`origen`), hacia cuáles (`destinos`) y en qué rango de duración. `aplica(trip)` indica si un viaje cumple la regla.],
    [`DuarouterConfig`], [Parámetros de `duarouter`: red, viajes, TAZ y salida; `--ignore-errors` y `--repair`. `to_args()` arma la línea de comandos y `required_inputs()` lista los archivos que deben existir. El resultado (`DuarouterResult`) trae la salida estándar y los avisos de rutas no encontradas.],
    [`SimulationConfig`], [Parámetros de SUMO: `.sumocfg`, semilla y ventana. `to_args()` arma la línea de comandos y `ventana()` devuelve inicio y fin (los del config o los del `.sumocfg`). `SimulationResult` guarda la bitácora.],
    [`KeplerTripsConfig`], [Parámetros de la exportación a kepler.gl: FCD de entrada, salida, paso temporal (`step`), cambio mínimo de rumbo (`angle`), movimiento mínimo (`min_move`), fecha ancla y altura base. `KeplerTripsStats` cuenta entidades, puntos leídos y exportados y descartados; `KeplerTripsResult` agrupa la salida.],
    [`PipelineResult`], [Resultado completo de una corrida: `EtlResult` (viajes y rutas), `SimulationResult`, la conversión opcional a puntos y los trips de kepler.],
    [`etl.etl` (módulo)], [Orquesta las etapas: `run_etl` (viajes y `duarouter`), `simulate` (SUMO, con TraCI si hay `on_avance` o `cancelar`), `export_geojson`, `export_kepler_trips` y `run_pipeline` (las cuatro en secuencia, con cancelación entre etapas); `resumen_corrida` arma lo que se muestra de una corrida; `run_recorte` y `run_escenario_semaforo` preparan zonas.],
    [`etl.precalculadas` (módulo)], [`generar` simula un preset una vez y guarda `trips.geojson.gz` (`mtime=0`), `volumenes.json` y `meta.json`; `cargar`, `listar` y `leer_volumenes` los consultan; `huella_insumos` calcula la huella SHA-256 de TSV, red, TAZ y `.sumocfg` para detectar precalculadas obsoletas.],
    [Módulos auxiliares], [`trips` (lee el TSV, valida, expande, ordena por `depart` y escribe `*.trips.xml`), `demanda` (probabilidades P(modo | duración), reparto por mayor resto), `duarouter`, `simulation` (`run_simulation`, TraCI), `kepler` (`reduce_points`, `convert_fcd_to_kepler_trips`), `fcd`, `vtypes`, `estilos`, `cierres` (`CierreVial`, `escribir_rerouter`), `proceso` (`ejecutar`, `Cancelado`, `ultimo_depart`).],
  ),
  caption: [Clases y módulos del ETL.],
)

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Asociación], [Significado]),
    [`TripGenerationConfig` → `DemandaConfig`], [La configuración de viajes incluye opcionalmente la demanda parametrizada.],
    [`DemandaConfig` → `Preset`], [Cada demanda nombra uno de los presets.],
    [`Preset` ← `InfoPreset` (`PRESETS`)], [El diccionario `PRESETS` asocia cada preset con su información.],
    [`InfoPreset` → `ReglaTransferencia` (0..1)], [Un preset tiene a lo sumo una regla de transferencia modal.],
    [`ReglaTransferencia` ⇢ `TripRecord`], [`aplica` evalúa si un viaje cumple la regla.],
    [`TripGenerationConfig` ⇢ `TripRecord`, `TripGenerationStats`], [La generación produce registros de viaje y actualiza las estadísticas.],
    [`ScenarioPaths` ⇢ `TripGenerationConfig`], [Las rutas del escenario alimentan las configuraciones de cada etapa.],
    [`SimulationConfig` ⇢ `PipelineResult`], [El resultado de cada etapa (`*Result`) se agrega al `PipelineResult`.],
  ),
  caption: [Asociaciones del diagrama del ETL.],
)

=== Análisis de intersecciones (`etl/sumo`) <sec-clases-analisis>

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((0, 0), "Semaforo", est: "dataclass", attrs: ("+id, tipo, programa: str", "+offset, ciclo: float", "+fases: list[Fase]", "+cruces: list[str]", "+lon, lat, z: float", "+accesos: list[Acceso]", "+calles: list[str]", "+movimientos: int", "+nombre: str", "+enlaces: list[dict]"), name: <sem>),
      clase((1, 0), "Fase", est: "dataclass", attrs: ("+duracion: float", "+estado: str", "+luces: dict[str,str]"), name: <fas>),
      clase((1, 1), "Acceso", est: "dataclass", attrs: ("+edge, calle: str", "+clase: str", "+carriles: int", "+velocidad_kmh: float", "+movimientos: int", "+volumen: int?", "+volumen_hora: float?", "+volumen_por_tipo: dict?"), name: <acc>),
      clase((2, 0), "ProgramaTLS", est: "dataclass", attrs: ("+tl_id, program_id, tipo: str", "+offset: float", "+fases: list[FasePrograma]"), metodos: ("+ciclo_s: float", "+to_dict()"), name: <ptls>),
      clase((3, 0), "FasePrograma", est: "dataclass", attrs: ("+duracion_s: float", "+estado: str"), name: <fprog>),
      clase((0, 1), "PuntajeCruce", est: "dataclass", attrs: ("+nodo_id: str, nodos: list", "+lon, lat: float", "+puntaje_total: float", "+nivel: str", "+detalle: dict[str,float]", "+siniestros, generadores: int", "+tramo_m: float", "+volumen: int?", "+evidencias: list[str]", "+distancia_semaforo_m: float?"), name: <pc>),
      clase((2, 1), "intersecciones", est: "módulo", metodos: ("+leer_semaforos(net, nombres)", "+catalogo(net, cache, nombres)", "+volumenes_por_edge(vehroute)", "+volumenes(vehroute, cache)", "+con_volumenes(semaforo, vols)", "+a_feature(semaforo)"), name: <mi>),
      clase((3, 1), "programas_tls", est: "módulo", metodos: ("+leer_programas(net, tl_id)", "+leer_programa(net, tl_id, pid)", "+escribir_programa(prog, xml)", "+validar_programa(prog, movimientos)", "+webster(...)"), name: <mp>),
      clase((1, 2), "priorizacion", est: "módulo", metodos: ("+analizar_red(...)", "+analisis_con_cache(net, nombres, cache, ...)", "+puntuar(analisis, volumenes)", "+a_geojson(cruces, umbrales, notas)"), name: <mz>),
      edge(<sem>, <fas>, "*->", label: [1..\*], label-side: left),
      edge(<sem>, <acc>, "*->", label: [1..\*], label-side: left),
      edge(<ptls>, <fprog>, "*->", label: [1..\*], label-side: left),
      edge(<mi>, <sem>, "-->", label: [produce], label-side: left),
      edge(<mp>, <ptls>, "-->", label: [produce], label-side: left),
      edge(<mz>, <pc>, "-->", label: [produce], label-side: left),
    ))
  ],
  caption: [Diagrama de clases del análisis de intersecciones.],
) <fig-clases-analisis>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase o módulo], [Responsabilidad, atributos y métodos]),
    [`Semaforo`], [Un `tlLogic` de la red con su ubicación (lon/lat por `pyproj`, altura `z`), su programa activo, sus accesos y los enlaces `linkIndex → acceso y giro`. `cruces` son los nodos de SUMO que controla; `movimientos` el número de conexiones controladas.],
    [`Fase`], [Una fase del programa: duración, `estado` (una letra por `linkIndex`) y el color resultante por acceso (verde, amarillo, rojo, apagado).],
    [`Acceso`], [Una entrada al cruce: `edge`, nombre de la calle (de `nombres_vias.json`), clase de vía, carriles, velocidad y movimientos que controla; los volúmenes (`volumen`, `volumen_hora`, `volumen_por_tipo`) se llenan solo si hay una corrida con `vehroute`.],
    [`ProgramaTLS`, `FasePrograma`], [Un programa editable: `ciclo_s` (propiedad) es la suma de las duraciones y `to_dict()` lo serializa para la API.],
    [`PuntajeCruce`], [Un cruce sin semáforo evaluado: puntaje 0--100, nivel (`prioritario`, `recomendado`, `observacion`), el detalle de cinco componentes en 0--1 y la evidencia que lo respalda.],
    [`intersecciones`], [`leer_semaforos` extrae un `Semaforo` por `tlLogic` de la red; `catalogo` lo hace con caché (`cache/semaforos.json`, invalidada por mtime y tamaño); `volumenes_por_edge` cuenta, desde `vehroute.xml`, la última ruta de cada `routeDistribution`; `volumenes` lo hace con caché; `con_volumenes` copia un semáforo con los volúmenes de una corrida; `a_feature` lo convierte en un _feature_ GeoJSON.],
    [`programas_tls`], [`leer_programas` y `leer_programa` leen los `tlLogic`; `escribir_programa` guarda un programa editado; `validar_programa` revisa que cada fase tenga un carácter por movimiento, un amarillo ≥ 3 s si hay verdes y un ciclo ≥ 15 s; `webster` calcula ciclo y verdes (@sec-alg-webster).],
    [`priorizacion`], [`analizar_red` agrupa nodos en cruces, aplica las reglas duras y reúne la evidencia (independiente de la corrida, con caché `priorizacion.json`); `analisis_con_cache` lo invalida por mtime, tamaño o `VERSION_ANALISIS`; `puntuar` calcula puntaje y niveles con los volúmenes de una corrida (@sec-alg-priorizacion); `a_geojson` arma la respuesta de la API.],
  ),
  caption: [Clases y módulos del análisis de intersecciones.],
)

*Asociaciones.* Un `Semaforo` contiene al menos una `Fase` y un `Acceso`; un `ProgramaTLS` contiene al menos una `FasePrograma`. Los módulos `intersecciones`, `programas_tls` y `priorizacion` son fábricas: producen, respectivamente, `Semaforo`, `ProgramaTLS` y `PuntajeCruce` a partir de la red de SUMO, la evidencia versionada y los volúmenes de una corrida.

=== Semáforo propuesto, escena 3D y telemetría (`etl/sumo`) <sec-clases-escena>

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((0, 0), "SemaforoNuevoConfig", est: "dataclass", attrs: ("+net_zona, destino: Path", "+nodo_id: str", "+tipo: static|actuated", "+ciclo_s: int?", "+nodos: tuple[str]"), metodos: ("+parche: Path", "+todos_los_nodos", "+escribir_parche(presentes)", "+to_args(executable)"), name: <snc>),
      clase((1, 0), "SemaforoNuevoResult", est: "dataclass", attrs: ("+net: Path", "+tl_id: str", "+fases: int", "+ciclo_s: float"), name: <snr>),
      clase((2, 0), "Riesgo", est: "dataclass", attrs: ("+indice: float (0-100)", "+nivel: bajo|medio|alto", "+causa: str", "+ttc, drac, pet: float?"), metodos: ("+to_dict()",), name: <rie>),
      clase((0, 1), "semaforo_nuevo", est: "módulo", metodos: ("+agregar_semaforo(config)", "+tipos_nodos(net, ids)", "+tipo_nodo(net, nodo_id)"), name: <msn>),
      clase((1, 1), "telemetria", est: "módulo", metodos: ("+ttc(gap, v, v_lider)", "+drac(gap, v, v_lider)", "+pet_cruce(...)", "+indice_riesgo(ttc, drac, pet)", "+nivel_riesgo(indice)", "+riesgo_peaton(...)", "+clasificar_accion(...)", "+opcion_enlace(...)"), name: <mtl>),
      clase((2, 1), "escena3d", est: "módulo", metodos: ("+geometria_escena(...)", "+rutas_por_acceso(net, nodos, nombres)", "+edificios_zona(...)", "+relleno_edificios(...)", "+terreno(muestras, limites)", "+altura_terreno(t, x, y)", "+giro_por_rumbos(...)"), name: <mes>),
      clase((0, 2), "subred / demanda_zona", est: "módulo", metodos: ("+recortar_red(...)", "+recortar_demanda(...)", "+encontrar_herramienta(nombre)", "+generar_demanda_zona(...)"), name: <msz>),
      edge(<msn>, <snc>, "-->", label: [recibe], label-side: left),
      edge(<msn>, <snr>, "-->", label: [produce], label-side: left),
      edge(<mtl>, <rie>, "-->", label: [produce], label-side: left),
    ))
  ],
  caption: [Diagrama de clases del semáforo propuesto, la escena 3D y la telemetría.],
) <fig-clases-escena>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Clase o módulo], [Responsabilidad, atributos y métodos]),
    [`SemaforoNuevoConfig`], [Parámetros de la variante con semáforo: red de la zona sin semáforo, `nodo_id` (junction representativo y también id del `tlLogic`), `nodos` (todos los del cruce), tipo (`static` o `actuated`) y ciclo opcional. `escribir_parche` escribe `semaforo_propuesto.nod.xml` dando a *todos* los nodos presentes `type="traffic_light"` y el mismo `tl` (un solo `tlLogic` controla el cruce completo); `to_args` arma la línea de `netconvert` (`--tls.default-type`, `--geometry.remove false`); `parche` y `todos_los_nodos` son propiedades derivadas.],
    [`SemaforoNuevoResult`], [Red generada (`zona_tls.net.xml`), id del semáforo, número de fases y ciclo resultante. `SemaforoNuevoStats` cuenta las conexiones controladas.],
    [`semaforo_nuevo`], [`agregar_semaforo` verifica que ningún nodo del cruce tenga ya semáforo, escribe el parche, ejecuta `netconvert` y comprueba que se generó un programa con fases; `tipos_nodos` y `tipo_nodo` consultan el tipo de uno o varios _junctions_.],
    [`Riesgo`], [Resultado de evaluar un actor: índice 0--100, nivel, causa (el indicador que manda) y los valores de TTC, DRAC y PET. `to_dict` redondea para el frame.],
    [`telemetria`], [Funciones puras (@sec-alg-riesgo): `ttc`, `drac` y `pet_cruce` calculan los indicadores; `indice_riesgo` los combina (manda el mayor) y `nivel_riesgo` lo clasifica; `riesgo_peaton` evalúa a un peatón; `clasificar_accion` traduce velocidad, aceleración, luz, brecha y cesión de paso en una acción legible; `opcion_enlace` describe cada giro posible.],
    [`escena3d`], [`geometria_escena` produce el JSON de la escena una sola vez: calzadas, andenes, cebras y bocas de calle, un poste por acceso, terreno de rejilla IDW (`terreno`, `altura_terreno`) y edificios de OSM y Microsoft deduplicados (`edificios_zona`) más un relleno ilustrativo (`relleno_edificios`, `relleno: true`); `rutas_por_acceso` calcula las rutas de entrada y salida de cada acceso; `giro_por_rumbos` clasifica un giro.],
    [`subred`, `demanda_zona`], [Preparan la zona: `recortar_red` (`netconvert`) y `recortar_demanda` (`cutRoutes.py`) alrededor de un punto; `generar_demanda_zona` suma viajes reales recortados y tráfico de fondo por modo (`randomTrips.py`); `encontrar_herramienta` localiza los scripts de SUMO.],
  ),
  caption: [Clases y módulos del semáforo propuesto, la escena 3D y la telemetría.],
)

*Asociaciones.* `semaforo_nuevo` recibe un `SemaforoNuevoConfig` y produce un `SemaforoNuevoResult`; `telemetria` produce `Riesgo`. `run_escenario_semaforo` (@sec-clases-etl) encadena `subred`, `demanda_zona`, `semaforo_nuevo` y `escena3d` para dejar la zona lista, y `Lado` (@sec-clases-api) usa `telemetria` en cada frame.
