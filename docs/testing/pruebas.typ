// @brief: Documento de control de calidad (plan y reporte de pruebas) -- ISO/IEC/IEEE 29119
// Compilar: python -c "import typst; typst.compile('docs/testing/pruebas.typ', root='docs/testing')"

#let titulo = "Generación de Escenarios de Movilidad Urbana para la Toma de Decisiones en Localidades de Bogotá"
#let version = "1.0"
#let fecha = "22 de noviembre de 2026"

#set document(title: "Documento de control de calidad -- " + titulo)
#set text(lang: "es", size: 11pt)
#show raw: set text(font: "Libertinus Serif", size: 1.25em)
#set par(justify: true, leading: 0.7em)
#set page(
  margin: 2.5cm,
  numbering: "1",
  footer: context [
    #line(length: 100%, stroke: 0.4pt)
    #grid(columns: (1fr, auto), [Control de calidad -- ISIST-2610-03 -- versión #version], [#counter(page).display()])
  ],
)
#show figure.where(kind: table): set block(breakable: true)
#show figure.where(kind: table): set figure(supplement: [Tabla])
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: image): set figure(supplement: [Figura])
#set table(stroke: 0.5pt + luma(150), inset: 5pt, align: left)
#show table.cell.where(y: 0): set text(weight: "bold")
#show table: set par(justify: false)

// ───────────────────────────── portada

#page(numbering: none, footer: none)[
#align(center)[
  #v(3em)
  #image("/figures/logo_javeriana.png", height: 4.5cm)
  #v(3em)
  #text(size: 16pt)[
    *PONTIFICIA UNIVERSIDAD JAVERIANA* \
    Facultad de Ingeniería -- Departamento de Ingeniería de Sistemas
  ]
  #v(3em)
  #text(size: 14pt, weight: "bold")[
    DOCUMENTO DE CONTROL DE CALIDAD \
    (plan y reporte de pruebas)
  ]
  #v(1em)
  #text(size: 12pt, weight: "bold")[#titulo]
  #v(1em)
  #text(size: 12pt)[Proyecto ISIST-2610-03 -- Grupo 3]
  #v(2.5em)
  #text(size: 14pt)[*Estándar base:* ISO/IEC/IEEE 29119-1 y 29119-3]
  #v(3em)
  #text(size: 12pt)[
    Samuel Esteban Campos \
    Erick Salazar Suárez \
    Santiago Chitiva Contreras \
    Felipe Andrés Garrido Flores
  ]
  #v(1em)
  #text(size: 12pt)[*Director:* Ing. Andrés Oswaldo Calderón Romero, PhD.]
  #v(3em)
  #text(size: 12pt)[Bogotá D.C., #fecha \ Versión #version]
]
]
#counter(page).update(1)

#heading(outlined: false, numbering: none)[Historial de cambios]

#table(
  columns: (auto, auto, 1fr, auto),
  table.header([Versión], [Fecha], [Descripción del cambio], [Autor(es)]),
  [0.1], [20/11/2026], [Primer borrador con la estrategia de pruebas, el entorno y el inventario de pruebas automáticas.], [Todos],
  [0.5], [21/11/2026], [Se agregan los defectos encontrados durante el proyecto, la cobertura medida y la trazabilidad con el SRS.], [Todos],
  [1.0], [22/11/2026], [Versión de entrega, revisada contra la ejecución final de la suite (192 pruebas aprobadas).], [Todos],
)

#heading(outlined: false, numbering: none)[Contenido]
#outline(title: none, depth: 2)

#pagebreak()
#set heading(numbering: "1.1")

= Introducción

== Para qué sirve este documento

Este documento cuenta cómo comprobamos que el sistema hace lo que dice el SRS y qué tan confiables son sus resultados. Tiene dos partes que en otros proyectos van por separado. La primera es el plan, es decir, qué se iba a probar, de qué manera y con qué criterio se iba a dar por bueno. La segunda es el reporte, con lo que efectivamente se ejecutó, lo que salió bien, lo que falló en el camino y lo que quedó pendiente. Las juntamos porque, siendo un equipo de cuatro personas con sprints de dos semanas, el plan y la ejecución se fueron escribiendo casi al mismo tiempo.

Nos basamos en la familia ISO/IEC/IEEE 29119, en particular en los conceptos de la parte 1 (niveles, técnicas y criterios de salida) y en la estructura de documentos de la parte 3 (plan, especificación de casos y reporte de resultados). No seguimos el estándar al pie de la letra, porque varias de sus plantillas suponen un equipo de pruebas independiente que nosotros no teníamos, pero sí tomamos su idea central de que cada prueba debe poder rastrearse hasta un requerimiento y cada resultado debe poder repetirse.

== Qué se probó

El objeto de prueba es el sistema completo del proyecto ISIST-2610-03, que tiene tres partes.

- El servicio de simulación (`simulation-service`), que incluye el pipeline que convierte la encuesta en archivos de SUMO, la API y los módulos de intersecciones, priorización y simulador 3D.
- El visor web (`kepler`), hecho en React con kepler.gl y three.js.
- El modelo de simulación en sí, es decir, la red de Usaquén con la demanda de la Encuesta de Movilidad 2023, que no es código pero sí produce los números que se reportan.

Esta distinción importa, porque a cada parte se le aplicó un tipo de prueba distinto. El código del servicio se probó con pruebas automáticas, el visor con demostraciones guiadas y el modelo con validación estadística contra datos reales.

== Documentos relacionados

El SRS (versión 2.3) contiene los requerimientos y el plan original de casos de prueba (CP-001 a CP-049), y este documento reporta su ejecución. El SPMP define los roles y el proceso de control de calidad, el SDD describe los componentes que aquí se prueban y la memoria del trabajo de grado resume los resultados de validación.

= Estrategia de pruebas

== Niveles

Organizamos las pruebas en cuatro niveles. La @tabNiveles los resume.

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([Nivel], [Qué se busca y cómo], [Herramienta]),
    [Unitarias], [Que cada función haga su trabajo con entradas pequeñas y controladas, por ejemplo que el reparto de conteos por modo sea exacto o que el TTC dé 1 s cuando debe. Son la mayoría de las pruebas y corren en segundos.], [pytest],
    [Integración], [Que los módulos funcionen juntos y con SUMO de verdad. Algunas están en la suite automática con datos mínimos, y otras se corrieron como scripts aparte porque necesitan la red completa y tardan minutos.], [pytest, scripts por WebSocket],
    [Sistema y aceptación], [Que un usuario pueda hacer las tareas del SRS desde el visor, como lanzar una corrida, abrir una intersección o comparar un cruce en 3D. Se hicieron como demostraciones con un guion y, en algunos casos, con capturas automáticas.], [Navegador, Chrome sin interfaz],
    [Validación del modelo], [Que la simulación se parezca a la realidad. Se compararon la forma horaria de la demanda contra la encuesta y los volúmenes contra 33 puntos de aforo, y se repitió el estudio de semáforos con 30 semillas.], [Scripts de validación, SUMO],
  ),
  caption: [Niveles de prueba.],
) <tabNiveles>

== Técnicas

La mayoría de los casos se diseñaron por partición de equivalencia y valores límite. Por ejemplo, para la API se probaron peticiones válidas, con un total de viajes en cero, con más de 100.000 viajes y con un identificador que no existe. Para la demanda usamos además una prueba de referencia que nos dio mucha tranquilidad durante todo el proyecto, según la cual el preset “encuesta” con sus conteos por defecto tiene que reproducir exactamente la expansión simple de la encuesta. Si alguien cambiaba la lógica de transferencia modal y rompía ese caso base, la prueba lo detectaba de inmediato.

Para las partes que dependen de SUMO usamos dobles de prueba. Los gestores de corridas y de comparaciones 3D aceptan un pipeline o una función de preparación falsa que se inyecta en la API, de modo que se puede probar todo el ciclo de vida de una corrida (crear, avanzar, cancelar, reanudar) sin simular nada. Así la suite completa corre en unos 35 segundos y se puede ejecutar en cada cambio.

== Lo que decidimos no automatizar

No escribimos pruebas automáticas para el visor. Lo consideramos y lo descartamos porque kepler.gl y three.js dependen de WebGL, y en un navegador sin interfaz el clic sobre el mapa no funciona bien, así que las pruebas habrían sido frágiles y caras de mantener. En su lugar el visor se verificó con demostraciones y con capturas tomadas con Chrome sin interfaz, y lo dejamos anotado como trabajo futuro.

Tampoco automatizamos las corridas completas de SUMO en la integración continua. Una corrida de la encuesta tarda unos 12 minutos y escribe más de un gigabyte, lo que no tiene sentido en cada cambio. Esas corridas se hicieron a mano en cada sprint y sus resultados quedaron versionados como simulaciones precalculadas, con una huella de los insumos que avisa cuando quedan desactualizadas.

== Criterios de entrada y salida

Para empezar a probar un incremento bastaba con que el código compilara y que el autor hubiera corrido las pruebas localmente. Para darlo por terminado pedimos tres cosas, que todas las pruebas automáticas pasaran, que el flujo se hubiera mostrado en el visor y que, si el cambio tocaba la demanda o la red, se regeneraran las precalculadas y el histograma de salidas. Para el modelo, la propuesta fijó como criterio de salida un GEH menor que 5 en al menos el 85 % de los puntos de aforo. Ese criterio no se alcanzó, y lo explicamos en la sección 6.

= Entorno de pruebas

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Elemento], [Configuración]),
    [Máquina de desarrollo], [Portátiles del equipo con Windows 11, 8 a 16 GB de RAM y 4 a 8 núcleos.],
    [Integración continua], [GitHub Actions sobre Ubuntu, con Python 3.12. Se ejecuta en cada push a `main`, `develop` y ramas `feat/**` y en cada pull request.],
    [Python y dependencias], [Python 3.12 y las versiones fijadas en `pyproject.toml`, instaladas con `pip install -e ".[dev]"`.],
    [SUMO], [Versión 1.27 desde el paquete `eclipse-sumo` de pip, con `traci` 1.27.1.],
    [Datos de prueba], [Archivos mínimos creados en carpetas temporales dentro de cada prueba (redes de juguete, TSV de pocas filas, rutas de dos vehículos). Las pruebas no dependen de los datos crudos de la encuesta.],
    [Navegador], [Chrome reciente con WebGL 2 para las demostraciones del visor y del simulador 3D.],
  ),
  caption: [Entorno de pruebas.],
) <tabEntorno>

= Pruebas automáticas

== Inventario

La suite vive en `simulation-service/test/` y tiene 192 pruebas repartidas en 26 archivos. La @tabInventario dice qué verifica cada archivo y a qué requerimientos del SRS apunta.

#figure(
  table(
    columns: (27%, auto, 1fr, 15%),
    table.header([Archivo], [Pruebas], [Qué verifica], [Req.]),
    [`test_api.py`], [22], [Las rutas de la API, con códigos 200, 202, 404, 409 y 422, la creación, consulta, cancelación y reanudación de corridas con un pipeline falso, las vías de la red y la comparación de programas.], [RF-018, RF-020, RF-024, RF-026],
    [`test_comparacion3d.py`], [13], [El gestor de comparaciones 3D, sus estados (preparando, lista, error), el límite de dos comparaciones y la limpieza al borrar.], [RF-033, RF-034],
    [`test_telemetria.py`], [24], [TTC, DRAC y PET, el índice de riesgo, la clasificación de acciones, el resumen del viaje, el balance por hora y la separación entre choque y contacto.], [RF-037, RF-048],
    [`test_priorizacion.py`], [18], [Agrupación de nodos en cruces, doble calzada, reglas duras, niveles según evidencia, supresión de vecinos y textos del porqué.], [RF-032, RF-045, RF-046],
    [`test_demanda.py`], [12], [Presets de transferencia modal, conservación del total, reparto de conteos por mayor resto y el caso base que reproduce la encuesta.], [RF-021, RF-022],
    [`test_escena3d.py`], [12], [Geometría de la escena, edificios recortados a la zona, relleno marcado y postes por acceso.], [RF-034],
    [`test_cierre_pendientes.py`], [10], [Ventanas de mañana y tarde, transporte público como viaje con modos, filtrado del GTFS, tráfico de paso y asignación iterativa.], [RF-043, RF-019],
    [`test_comparacion_programas.py`], [7], [Webster por fases en verde, amarillos sin tocar y métricas de la comparación de programas.], [RF-030, RF-031],
    [`test_estudio_semillas.py`], [7], [Conflictos del dispositivo SSM, diferencias pareadas, intervalos de confianza y veredicto por cruce.], [OE5],
    [`test_semaforo_nuevo.py`], [7], [Instalación del semáforo propuesto con un solo controlador para todos los nodos del cruce, y errores claros si el cruce no sirve.], [RF-033, RF-044],
    [`test_intersecciones.py`], [6], [Un semáforo por controlador, accesos, nombres de vía, volúmenes por acceso y asociación con los semáforos de la SDM.], [RF-028],
    [`test_progreso.py`], [6], [Avance monótono por etapa, lectura del avance de duarouter y cancelación de subprocesos.], [RF-026],
    [`test_subred.py`], [6], [Recorte de red y de demanda alrededor de un cruce y limpieza de tipos de vehículo repetidos.], [RF-029],
    [`test_validacion.py`], [6], [Cálculo del GEH y del RMSE, suma de calzadas paralelas y grupos de calibración y control.], [RF-014],
    [`test_aforos.py`], [5], [Ubicación de los aforos en la red y asignación al grupo de calibración o de control.], [RF-014],
    [`test_encuesta_completa.py`], [5], [Lectura de la encuesta completa, horas decimales y puertas de entrada y salida.], [RF-005],
    [`test_kepler.py`], [5], [Conversión a trayectorias de kepler, modo derivado del identificador y descarte de entidades quietas.], [RF-017],
    [`test_demanda_zona.py`], [4], [Argumentos de randomTrips por modo y variación de salidas por semilla.], [RF-033],
    [`test_vtypes.py`], [4], [Un tipo de vehículo por modo con su clase de SUMO.], [RF-011],
    [`test_precalculadas.py`], [4], [Reproducibilidad de las precalculadas (mismo archivo comprimido y misma huella de insumos).], [RF-025],
    [Otros 6 archivos], [11], [Configuración y rutas de escenarios, duarouter, lectura del FCD y del GeoJSON, simulación y generación de viajes ordenados por hora de salida.], [RF-006, RF-008, RF-012],
  ),
  caption: [Inventario de pruebas automáticas.],
) <tabInventario>

== Resultado de la última ejecución

La última ejecución completa fue el 22 de noviembre de 2026 sobre la rama `develop`. Pasaron las 192 pruebas, sin fallas ni pruebas omitidas, en 32,6 segundos. Apareció una sola advertencia, de una biblioteca externa (Starlette avisa que su cliente de pruebas cambiará de dependencia), que no afecta los resultados.

El número de pruebas fue creciendo con el proyecto. En la versión 2.0 de la propuesta había 99, en la 2.2 del SRS había 121 y al cierre hay 192. Casi todo ese crecimiento vino de dos fuentes, el sprint de cierre de pendientes, que agregó validación, GTFS y ventanas, y el estudio de semillas.

== Cobertura

Medimos la cobertura de líneas con pytest-cov. El servicio completo está en 65 %, pero ese promedio esconde dos grupos muy distintos (@tabCobertura).

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([Módulo], [Cobertura], [Comentario]),
    [`validacion.py`, `vtypes.py`, `configuration.py`, `kepler.py`], [99--100 %], [Lógica pura, fácil de probar con datos mínimos.],
    [`demanda.py`, `jobs.py`, `proceso.py`], [96--98 %], [El corazón de la demanda y del ciclo de vida de las corridas.],
    [`intersecciones.py`, `telemetria.py`, `trips.py`, `priorizacion.py`, `fcd.py`], [91--94 %], [Bien cubiertos, con casos de borde.],
    [`api.py`, `escena3d.py`, `semaforo_nuevo.py`, `subred.py`], [64--74 %], [Lo que falta son ramas que llaman a SUMO o a netconvert.],
    [`etl.py`, `comparacion3d.py`, `evidencia.py`, `estudio_semillas.py`], [27--38 %], [Orquestan SUMO real o descargan datos de internet, y se verificaron con corridas de integración.],
  ),
  caption: [Cobertura de líneas por grupo de módulos.],
) <tabCobertura>

Somos conscientes de que el orquestador y el simulador 3D son justamente las piezas más complejas y las que menos cobertura automática tienen. Los compensamos con las pruebas de integración de la siguiente sección, pero si el proyecto continúa es lo primero que habría que mejorar, probablemente con una red de juguete pequeña que SUMO pueda simular en pocos segundos dentro de la integración continua.

= Pruebas de integración y de sistema

Estas pruebas no están en la suite porque necesitan SUMO con la red real o un navegador. Las corrimos al cerrar cada sprint y antes de las demostraciones con el director. La @tabIntegracion resume las más importantes con el caso del SRS al que corresponden.

#figure(
  table(
    columns: (auto, 1fr, 1fr, auto),
    table.header([Caso], [Procedimiento], [Resultado observado], [Estado]),
    [CP-017], [Pipeline completo de la encuesta en un portátil de 8 GB y 4 núcleos.], [Unos 12 minutos (1,5 de demanda y rutas, 8 de SUMO y 2 de exportación), frente a un límite de 4 horas.], [Pasa],
    [CP-037], [Comparación 3D en un cruce prioritario, lanzando una moto y luego un peatón por accesos distintos.], [El actor apareció en los dos lados en 149 de 150 cuadros, con la cámara siguiéndolo y métricas distintas por lado.], [Pasa],
    [CP-040], [Preparar una comparación sobre un cruce real y leer 150 cuadros por WebSocket.], [Preparación entre 14 y 40 s (límite 60 s) y 5 cuadros por segundo a velocidad 1×.], [Pasa],
    [CP-041], [Perfil del navegador durante 60 s de comparación 3D.], [No se midió formalmente en la máquina de referencia.], [Pendiente],
    [CP-044], [Comparación sobre un cruce de varios nodos con el actor en modo manual y cambio de giro.], [Un solo controlador para todo el cruce, el actor acelera y frena igual en ambos lados y el giro pedido se aplica.], [Pasa],
    [CP-046], [Seis actores lanzados por los tres accesos de un cruce prioritario.], [Todos entraron en el mismo paso en los dos escenarios.], [Pasa],
    [CP-049], [Comparación real de programas en la Av. Calle 134 con Av. Carrera 9.], [Corrieron las dos simulaciones y el visor mostró la diferencia de tiempo perdido por vehículo.], [Pasa],
    [CP-019b], [Desde el visor, elegir el preset “más vehículos”, cambiar un conteo y la semilla y simular.], [La corrida terminó con los parámetros elegidos y la tarjeta mostró el avance por etapa.], [Pasa],
    [CP-048], [Cerrar una calle con un clic en la pestaña Cierres.], [La vía se pintó en rojo con su sentido contrario disponible y su nombre en la lista.], [Pasa],
    [CP-042], [Sesión con el director para lanzar una corrida, abrir una intersección y una comparación 3D sin ayuda.], [Se hizo como demostración guiada y no como prueba de usabilidad formal.], [Parcial],
  ),
  caption: [Pruebas de integración y de sistema.],
) <tabIntegracion>

= Validación del modelo

Aquí la pregunta ya no es si el código funciona, sino si la simulación se parece a Usaquén. La respondimos en dos niveles.

*Forma horaria de la demanda.* Comparamos la hora de salida de los viajes en intervalos de 10 minutos entre la encuesta expandida, la encuesta tal como se le entrega a SUMO y la simulación (@figHistograma). La simulación reproduce su insumo con una diferencia máxima de 0,9 puntos porcentuales por intervalo, así que en este nivel el resultado es bueno.

#figure(image("/figures/histograma_salidas.png", width: 85%), caption: [Hora de salida de los viajes entre 7:00 y 10:00 en la encuesta, en el insumo de SUMO y en la simulación.]) <figHistograma>

*Volúmenes contra aforos.* Aquí el resultado no fue el esperado. El GEH se cumple en 2 de 33 puntos, muy lejos del 85 % que pedía la propuesta. Probamos varias demandas (solo viajes internos, con tráfico de paso, la encuesta completa, rutas iterativas e incluso quitando el control de los cruces) y ninguna pasó, porque la red construida desde OpenStreetMap no deja entrar a más de la mitad de los vehículos. Lo dejamos registrado como un defecto del modelo y no del software, con su causa identificada, y la memoria lo discute en detalle. La consecuencia práctica es que el sistema sirve para comparar escenarios con la misma demanda, no para predecir volúmenes.

*Estudio de semillas.* Como el simulador 3D usa una sola semilla, repetimos la comparación sin y con semáforo en 59 cruces con 30 semillas cada uno. Con 20 semillas el veredicto ya era casi igual (12, 8, 38 y 1 frente a 13, 9, 36 y 1 con 30), lo que nos dio confianza en que el resultado no depende del azar de una corrida.

= Defectos encontrados

Durante el proyecto registramos los defectos como issues o directamente en la descripción de los commits que los corregían. La @tabDefectos recoge los que más nos costaron, porque varios no eran errores nuestros sino comportamientos poco documentados de SUMO, y creemos que contarlos le ahorra tiempo a quien siga.

#figure(
  table(
    columns: (auto, 1fr, 1fr, auto),
    table.header([N.º], [Síntoma], [Causa y corrección], [Severidad]),
    [D-01], [De unos 24.600 viajes, SUMO solo simulaba cerca de 1.600.], [SUMO descarta, sin avisar claramente, cualquier viaje cuya salida sea anterior al último ya cargado. Se ordenaron los viajes por hora de salida antes de rutear y se agregó una prueba.], [Bloqueante],
    [D-02], [Al cancelar una corrida, SUMO seguía corriendo y la corrida quedaba en “cancelando” para siempre.], [Los ejecutables de SUMO instalados con pip son lanzadores que abren otro proceso, y matar el lanzador dejaba vivo al hijo. Se cambió por una función que mata el árbol completo de procesos.], [Crítico],
    [D-03], [El simulador 3D se caía después de un rato con un error de almacenamiento interno.], [Suscribirse a actores que ya habían salido de la red acumulaba mensajes de error hasta superar un límite de SUMO 1.27. Ahora se filtran los actores contra la lista de los que siguen en la red.], [Crítico],
    [D-04], [Los dos lados de la comparación 3D divergían por completo aunque tenían la misma demanda.], [Los tipos de vehículo tenían variación aleatoria, y cualquier diferencia de estado consumía números aleatorios distintos. Se copiaron los tipos sin variación en la zona 3D.], [Mayor],
    [D-05], [El contador de colisiones del 3D mostraba cientos.], [SUMO repite una colisión en cada paso que dura. Se cuenta cada pareja una sola vez y se separa el choque del contacto leve.], [Mayor],
    [D-06], [SUMO se cerraba sin mensaje al simular los buses del GTFS.], [El reenrutamiento de un bus con paradas hacía fallar a SUMO 1.27. Se desactivó ese dispositivo para los buses.], [Crítico],
    [D-07], [Error “tipo de vehículo no conocido” al sumar la encuesta completa.], [SUMO carga los archivos de rutas por partes y un tipo definido más adelante todavía no existía. Los vehículos agregados usan tipos propios definidos al inicio de su archivo.], [Mayor],
    [D-08], [La tercera iteración de la asignación iterativa se caía.], [Una opción pasada a duarouter dejaba una ruta alternativa vacía por vehículo. Se pasaron las zonas como archivo adicional.], [Menor],
    [D-09], [El visor no mostraba ningún avance durante minutos.], [SUMO y duarouter guardan su salida en búfer cuando se redirige. El avance se calcula ahora desde el archivo de rutas y desde TraCI.], [Menor],
    [D-10], [El GEH se cumple en 2 de 33 puntos.], [La capacidad de la red construida desde OpenStreetMap no alcanza para la demanda real. Queda abierto como limitación del modelo.], [Abierto],
  ),
  caption: [Defectos más relevantes encontrados durante el proyecto.],
) <tabDefectos>

Al cierre no queda ningún defecto bloqueante ni crítico abierto en el software. El único abierto es el D-10, que es del modelo y depende de datos que el proyecto no tenía (los tiempos reales de los semáforos de la SDM y una red con carriles auditados).

= Trazabilidad con el SRS

La @tabTrazabilidad resume cómo quedaron cubiertos los 64 requerimientos del SRS, contando los casos de su plan de pruebas (sección 5 del SRS). Un requerimiento cuenta como “con prueba” si al menos uno de sus casos se verifica ejecutando el sistema o un componente con un resultado esperado, y como “con demostración o revisión” si solo se verifica mostrándolo, inspeccionando archivos o analizando el código.

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    table.header([Grupo], [Total], [Con prueba], [Con demostración o revisión], [Sin caso en el SRS]),
    [Funcionales (RF)], [48], [35], [8], [5],
    [Desempeño (RD)], [4], [4], [0], [0],
    [No funcionales (RNF)], [12], [5], [6], [1],
  ),
  caption: [Cobertura de los requerimientos según el plan de pruebas del SRS.],
) <tabTrazabilidad>

Seis requerimientos se agregaron al SRS después de escribir su plan de pruebas y quedaron sin un caso propio. Para no dejarlos huérfanos les asignamos los casos de la @tabNuevos, que se ejecutaron igual que los demás.

#figure(
  table(
    columns: (auto, auto, 1fr, auto),
    table.header([Caso], [Req.], [Verificación], [Estado]),
    [CP-050], [RF-023], [Demostración. Se lanzó una corrida con estilo agresivo y otra con estilo cauteloso desde el panel de demanda, y se revisó que la corrida agresiva incluyera el archivo adicional de tipos de vehículo con sus parámetros.], [Pasa],
    [CP-051], [RF-027], [Demostración y prueba. El visor animó los viajes de la precalculada “encuesta” con la línea de tiempo, y `test_kepler.py` verifica el formato de cada trayectoria.], [Pasa],
    [CP-052], [RF-041], [Demostración. Al terminar un viaje en el simulador 3D se descargó el reporte en CSV y en PDF con las métricas de los dos escenarios.], [Pasa],
    [CP-053], [RF-042], [Integración. Se preparó una comparación con el programa de Webster calculado con los volúmenes de la zona y otra con un ciclo fijado a mano, y el lado con semáforo cargó el programa pedido.], [Pasa],
    [CP-054], [RF-043], [Prueba. `test_cierre_pendientes.py` verifica el filtrado del GTFS y que los viajes en transporte público se escriban como viajes con modos públicos, y las precalculadas se generaron con los buses.], [Pasa],
    [CP-055], [RNF-USA-002], [Demostración. Se cambió entre tema claro y oscuro, se recargó la página y el visor recordó la elección.], [Pasa],
  ),
  caption: [Casos agregados para los requerimientos sin caso en el SRS.],
) <tabNuevos>

Que un requerimiento tenga caso no quiere decir que se cumpla. El RF-014 (GEH) tiene sus pruebas y pasan, porque el cálculo es correcto, pero el criterio de aceptación del modelo no se alcanza. Entre los no funcionales, la portabilidad a Windows en la integración continua y el puntaje mínimo de pylint siguen sin cumplirse, y lo decimos tal cual. El estado de cada requerimiento está en su ficha del SRS.

= Estado frente a los criterios de aceptación

#figure(
  table(
    columns: (1fr, auto),
    table.header([Criterio del SRS], [Estado al cierre]),
    [Todas las pruebas automáticas del servicio pasan.], [Cumplido (192 de 192).],
    [Los casos de desempeño pasan en la máquina de referencia.], [Cumplido para RD-001 y RD-003; RD-004 sin medir.],
    [GEH menor que 5 en al menos el 85 % de los puntos de aforo.], [No cumplido (2 de 33).],
    [Integración continua verde en Ubuntu y Windows.], [Parcial. Verde en Ubuntu y sin trabajo en Windows.],
    [Reproducibilidad entre dos ejecuciones con los mismos insumos.], [Cumplido para las precalculadas, verificado por prueba.],
    [Sin defectos bloqueantes ni críticos abiertos.], [Cumplido.],
  ),
  caption: [Criterios de aceptación del sistema.],
) <tabAceptacion>

= Lo que aprendimos

Lo más útil fue tener desde temprano una prueba que fijara el caso base de la demanda. Varias veces refactorizamos la generación de viajes con miedo de romper algo, y esa prueba nos dijo en segundos si la encuesta se seguía reproduciendo. También nos sirvió mucho que los gestores de la API aceptaran un pipeline falso, porque de otra forma probar la cancelación habría significado esperar minutos a que SUMO arrancara.

Lo que haríamos distinto es empezar antes con las pruebas de integración automáticas sobre una red pequeña. Varios de los defectos de la @tabDefectos aparecieron solo con SUMO real y los encontramos tarde, en demostraciones, cuando una prueba de un minuto los habría mostrado el mismo día. Y también habríamos buscado antes la ubicación de los aforos, porque la validación con GEH quedó para el último sprint y eso nos dejó poco margen para trabajar en la calibración de la red.

Para quien continúe el proyecto dejamos tres recomendaciones concretas, en este orden. La primera es agregar un trabajo de Windows a la integración continua, la segunda es crear una red de juguete para probar el orquestador y el simulador 3D con SUMO real y la tercera es hacer una prueba de usabilidad con planificadores de movilidad, que es la validación que más le falta al visor.
