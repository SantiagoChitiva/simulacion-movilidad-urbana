// @brief: Sección 3 -- Requerimientos Específicos del SRS
// Proyecto: Mobility Pipeline

// Macro auxiliar: tabla de documentación de un requerimiento individual (formato Volere)
#let reqTable(
  id: "",
  tipo: "",
  cu: "",
  descripcion: "",
  razon: "",
  autor: "",
  criterio: "",
  prioridad: "",
  modulo: "",
  version: "1.0",
  fecha: "",
  estado: none,
) = figure(
  table(
    columns: (auto, 1fr),
    [*N.° Requerimiento*],   [#id],
    [*Tipo*],                [#tipo],
    [*Casos de uso*],        [#cu],
    [*Descripción*],         [#descripcion],
    [*Razón*],               [#razon],
    [*Autor*],               [EFSS],
    [*Criterio de medición*],[#criterio],
    [*Prioridad*],           [#prioridad],
    [*Módulo asociado*],     [#modulo],
    ..if estado != none { ([*Estado (v2.0)*], [#estado]) },
    [*Versión*],             [#version],
    [*Fecha*],               [#fecha],
  ),
  caption: [Requerimiento #id.],
  kind: table,
)

#let requerimientosEspecificos() = [

#align(center)[= Requerimientos Específicos]

Esta sección es en cierto sentido la más importante del proyecto en cuanto a diseño e implementación se refiere. La idea principal de todo el documento,
es la de realizar una conexión, un vínculo entre el cliente final y los desarrolladores de la aplicación o el sistema y esta sección es la encargada de
esa comunicación.

La especificación de requerimientos busca trasladar las necesidades reales del usuario a un lenguaje más técnico que facilite su construcción, sin embargo
es importante mantener un cierto nivel de descripción y lenguaje, para que el cliente no se pierda en tecnicismos y de esta forma hacerlo parte activa de
todo el proceso (diseño y construcción).

Para hacer de este documento una parte valiosa en el proceso de construcción del sistema, todos los requerimientos que se ubiquen en esta sección deben
cumplir con las siguientes características:

- *Atómico:* cada requerimiento tiene un único propósito y su funcionalidad no puede dividirse
  en más de una parte.
- *Correcto:* solo se incluyen los requerimientos necesarios según el análisis previo y las
  entrevistas con los stakeholders.
- *No Ambiguo:* cada requerimiento tiene una sola interpretación válida, independientemente de
  quién lo lea.
- *Completo:* incluye toda la información necesaria para su perfecto entendimiento: descripción,
  razón y criterio de medición.
- *Consistente:* ningún requerimiento contradice a otro ni a ninguna sección de los documentos
  del proyecto.
- *Importancia:* clasificados por prioridad (Alta / Media / Baja) para orientar al equipo hacia
  las funcionalidades más críticas.
- *Verificable:* cada requerimiento posee un criterio de medición objetivo que permite comprobar
  su cumplimiento mediante inspección, análisis, demostración o prueba.
- *Trazable:* el origen de cada requerimiento es claro y su relación con otros requerimientos y
  casos de uso es fácilmente mapeable.
- *Asociado a Versión:* cada requerimiento indica la versión del producto a la que pertenece.
- *No Redundante:* ningún requerimiento se repite ni aparece en más de una parte del documento.
- *Preciso:* se incluyen valores numéricos, umbrales y formatos concretos donde aplique.

== Requerimientos de Interfaces Externas

=== Interfaces con el Usuario

En la versión 2.0 el usuario final interactúa con el sistema a través del *visor web* (`kepler/`), una aplicación React servida por Vite que consume la
API de `simulation-service`. La línea de comandos queda para el equipo de desarrollo (pipeline por defecto y precalculadas). La interfaz está en
español y se organiza así:

- *Mapa principal (kepler.gl):* anima los viajes simulados por modo con una capa de trayectorias, una línea de tiempo y una leyenda de modos en la parte
  superior. La leyenda tiene además los interruptores de las capas *Semáforos* (intersecciones semaforizadas) y *Priorización* (cruces sin semáforo
  puntuados).
- *Panel derecho con pestañas:*
  - *Demanda:* preset, conteos por modo, escala, semilla y estilo de conducción. Muestra el historial de corridas y las simulaciones precalculadas.
  - *Intersección:* ficha del semáforo con accesos, volúmenes y fases, edición del programa, cálculo de Webster y comparación de programas.
  - *Cierres:* lista de vías cerradas para la próxima corrida.
  - *Semaforizar:* elige un cruce candidato, ajusta el tráfico de fondo y abre el simulador 3D.
- *Tarjeta de actividad:* barras de progreso de la corrida en curso o de la descarga, con botón de cancelar.
- *Simulador 3D comparativo (pantalla completa):*
  - *Barra superior:* selector del cruce candidato, modo *Auto / Manual*, pestañas *Comparar / Sin semáforo / Con semáforo*, velocidad de la
    simulación y cámara (tercera persona trasera o aérea).
  - *Vistas:* dos vistas 3D lado a lado, "Sin semáforo (actual)" y "Con semáforo propuesto", o una sola a pantalla completa.
  - *HUD por lado:* una píldora arriba (espera lateral, choques, conflictos y fase del semáforo) y una tarjeta abajo con la velocidad en km/h, el
    estado del actor, la barra de riesgo y los giros posibles; al hacer clic en la tarjeta se despliega el detalle (TTC, DRAC, PET, decisiones en
    el próximo cruce, métricas e historial de riesgo).
  - *Minimapa:* mapa 2D tipo navegador en la esquina superior derecha, girado según el rumbo del actor.
  - *Panel de actores y vías:* para lanzar o seguir actores; se pliega al empezar a seguir uno.

La interfaz se ajusta al tamaño de la ventana; en pantallas de menos de 900 px de ancho las dos vistas 3D se apilan verticalmente. Se usa con ratón y
teclado; en modo manual el actor seguido se maneja con W/↑ (acelerar), S/↓/Espacio (frenar) y A, X, D (izquierda, recto o derecha en el próximo
cruce).

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Comando (desarrollo)*], [*Uso*]),
    [`python -m etl.etl`], [Pipeline completo del escenario por defecto: TSV → trips → duarouter → SUMO → GeoJSON/trips de kepler.],
    [`python -m etl.precalculadas [preset ...]`], [Simula los presets con sus conteos por defecto y guarda los resultados versionados en `precalculadas/`.],
    [`uvicorn api.api:app`], [Levanta la API en el puerto 8000 (documentación interactiva en `/docs`).],
    [`npm run dev`], [Levanta el visor web en el puerto 5173 con proxy `/api` → `localhost:8000` (HTTP y WebSocket).],
  ),
  caption: [Comandos de línea de comandos del sistema.]
) <tabComandos>

=== Interfaces con el Hardware <secInterfacesHardware>

El pipeline opera en una máquina local o servidor de cómputo con los siguientes requisitos
mínimos de hardware, derivados de los supuestos definidos en el SPMP:

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Componente*], [*Requisito mínimo*]),
    [RAM],         [8 GB],
    [CPU],         [4 núcleos físicos a $>=$ 2.0 GHz],
    [Almacenamiento], [$>=$ 10 GB libres para datasets de entrada, red OSM y archivos de salida],
    [Red],         [Acceso a Internet para la descarga de la red vial desde OpenStreetMap
                    (descarga única; la ejecución posterior es offline)],
  ),
  caption: [Requisitos mínimos de hardware.]
) <tabHardware>

No se requieren dispositivos especiales, aceleradores GPU ni interfaces de red de alta velocidad.

=== Interfaces con el Software

#figure(
  table(
    columns: (auto, auto, auto),
    table.header([*Software*], [*Versión mínima*], [*Rol en el sistema*]),
    [Python], [3.11], [Lenguaje del pipeline ETL, la API y el control de SUMO],
    [SUMO (`eclipse-sumo`)], [1.27], [Motor de simulación; netconvert, duarouter y las herramientas `cutRoutes.py` y `randomTrips.py`],
    [TraCI / sumolib], [1.27.1], [Control de SUMO en vivo (avance de corridas, simulador 3D) y lectura de la red],
    [FastAPI + Uvicorn], [0.110+], [API REST y WebSocket del sistema],
    [pyproj], [3.6+], [Conversión entre coordenadas de la red y lon/lat],
    [pandas / geopandas], [2.0 / 0.14], [Exploración y preparación de datos (notebooks)],
    [Node.js + Vite], [20+ / 6], [Servidor de desarrollo y empaquetado del visor web],
    [React], [18.3], [Interfaz del visor web],
    [kepler.gl], [3.1], [Mapa con la animación de viajes y las capas de semáforos y priorización],
    [three.js], [0.169.0], [Render 3D del simulador comparativo],
    [maplibre-gl], [4.7.1], [Minimapa 2D del simulador (teselas de OpenStreetMap)],
    [Typst], [0.12+], [Compilación de los documentos SRS, SPMP y VFP],
    [Ubuntu / macOS / Windows], [22.04 / 13 / 10], [Sistemas operativos soportados],
    [Git], [2.40], [Control de versiones del código fuente],
    [pytest], [7.0], [Ejecución de pruebas unitarias e integración],
    [GitHub Actions], [--], [Integración continua (CI) en cada commit],
  ),
  caption: [Interfaces de software del sistema.]
) <tabSoftware>

=== Interfaces de Comunicaciones

El sistema usa las siguientes comunicaciones, todas en la máquina local salvo las teselas de mapa:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Canal*], [*Protocolo / puerto*], [*Uso*]),
    [Visor #sym.arrow API], [HTTP REST, JSON (`localhost:8000`, vía proxy `/api` de Vite)], [Demanda, corridas, intersecciones, programas,
    comparaciones, priorización y preparación del simulador 3D. Los trips precalculados se sirven en gzip con `Content-Encoding: gzip`.],
    [Visor #sym.arrow API], [WebSocket (`/comparacion3d/{id}`)], [Frames del simulador 3D (≈5 por segundo) y comandos del usuario (pausa, velocidad,
    período de riesgo, seguir o inyectar actor).],
    [API #sym.arrow SUMO], [TraCI sobre TCP en un puerto libre de `localhost`], [Avance de las corridas y control en vivo de los dos SUMO del simulador 3D.],
    [Visor #sym.arrow mapas base], [HTTPS 443], [Teselas de Mapbox (mapa principal, requiere `VITE_MAPBOX_TOKEN`) y de OpenStreetMap (minimapa).],
  ),
  caption: [Interfaces de comunicaciones.]
) <tabComunicaciones>

El pipeline de datos no usa la red; la red vial de OpenStreetMap se descargó una vez durante la preparación de datos.

== Características del Producto de Software (Requerimientos Funcionales)

Los requerimientos funcionales definen las acciones que el sistema debe ejecutar: qué entradas acepta, qué procesamiento realiza y qué salidas produce. Se
redactan con la forma \"El sistema debe #sym.dots\", y se organizan en cinco funcionalidades que corresponden a las fases del pipeline ETL.

=== F1 -- Ingestión y Validación de Datos de Entrada

#reqTable(
  id: [RF-001],
  tipo: [Funcional],
  cu: [CU-01],
  descripcion: [El sistema debe leer la base de datos de la Encuesta de Movilidad de Bogotá 2023 en formato XLSX y validar que el archivo contiene al
  menos las columnas: ID_hogar, modo, origen_UPZ, destino_UPZ y factor_expansión. Si alguna columna obligatoria está ausente, el sistema debe abortar la
  ejecución y registrar el error en el log indicando el nombre de la columna faltante.],
  razon: [La encuesta es la fuente primaria de datos de demanda. Sin las columnas mínimas no es posible construir una matriz O/D válida.],
  criterio: [Dado un archivo XLSX sin la columna destino_UPZ, el sistema debe terminar con código de error distinto de cero y el log debe contener el
  mensaje 'Columna requerida ausente: destino_UPZ'.],
  prioridad: [Alta],
  modulo: [`notebooks/F2.x` + `simulation-service/src/etl/sumo/trips.py`],
  estado: [Parcial. La limpieza y el cruce de la encuesta se hacen en los notebooks de la Fase 2 (`notebooks/F2.x`); el pipeline lee el TSV resultante (`viajes_usaquen_internos.tsv`) y valida sus columnas.],
  fecha: [],
)

#reqTable(
  id: [RF-002],
  tipo: [Funcional],
  cu: [CU-01],
  descripcion: [El sistema debe descargar la red vial del polígono de Usaquén desde OpenStreetMap usando osmium-tool, aplicando el recorte geográfico
  sobre el dump OSM de Bogotá o mediante la API Overpass, y almacenar el resultado en el directorio de datos configurado. Si el archivo ya existe en
  disco, el sistema debe omitir la descarga y usar la copia local.],
  razon: [La red OSM es la fuente de infraestructura vial. La descarga debe ser automática para garantizar la reproducibilidad del pipeline sin
  intervención manual.],
  criterio: [Ejecutado el pipeline con red local ausente, se debe generar el archivo usaquen.osm.pbf en el directorio de datos. En una segunda ejecución,
  el log debe indicar 'Red OSM encontrada en caché, omitiendo descarga'.],
  prioridad: [Alta],
  modulo: [`notebooks/F2.x`, `data/processed/usaquen.osm.xml`],
  estado: [Parcial. La red se descargó y procesó una vez en los notebooks y se versiona en `data/processed/`; no se descarga en cada ejecución.],
  fecha: [],
)

#reqTable(
  id: [RF-003],
  tipo: [Funcional],
  cu: [CU-01],
  descripcion: [El sistema debe eliminar los registros de la encuesta que presenten dobles conteos, aplicando la lógica definida en el documento 'Base de
  datos con factores de ponderación y sin dobles conteos'. Los registros eliminados deben registrarse en el log con su ID_hogar y el motivo de
  eliminación.],
  razon: [Los dobles conteos distorsionan los volúmenes de la matriz O/D y producen sobreestimación de la demanda simulada.],
  criterio: [Dado un conjunto de prueba con 10 registros que incluyan 2 dobles conteos conocidos, el sistema debe producir una tabla de 8 registros y el
  log debe indicar exactamente 2 registros eliminados por doble conteo.],
  prioridad: [Alta],
  modulo: [`notebooks/F2.x`],
  estado: [Implementado en la preparación de datos (notebooks de la Fase 2).],
  fecha: [],
)

#reqTable(
  id: [RF-004],
  tipo: [Funcional],
  cu: [CU-01],
  descripcion: [El sistema debe validar que cada registro de la encuesta tiene valores no nulos y válidos en las columnas modo, origen_UPZ y destino_UPZ.
  Los registros con al menos uno de esos tres campos vacío o con un valor fuera del dominio definido deben descartarse y registrarse en el log con el
  ID_hogar y el campo inválido.],
  razon: [Registros incompletos generan entradas inválidas en la matriz O/D que SUMO no puede procesar.],
  criterio: [El log debe reportar el porcentaje de registros descartados sobre el total leído. Dado un archivo con 5% de registros con origen_UPZ nulo, el
  log debe indicar exactamente ese 5% como tasa de descarte.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/trips.py`],
  estado: [Implementado. Las filas inválidas se descartan y se cuentan en `TripGenerationStats.filas_invalidas`.],
  fecha: [],
)

#reqTable(
  id: [RF-005],
  tipo: [Funcional],
  cu: [CU-01],
  descripcion: [El sistema debe aplicar los factores de expansión muestral de la encuesta a cada viaje válido, de manera que el total de viajes expandido
  sea representativo del universo de viajes de Bogotá y no únicamente de la muestra encuestada.],
  razon: [Sin expansión, los volúmenes de la matriz O/D reflejan solo la muestra (#{sym.tilde.basic}23,000 hogares) y no el universo de viajes de la
  ciudad.],
  criterio: [La suma de los viajes expandidos debe ser igual a la suma del campo factor_expansión de todos los registros válidos, con una tolerancia de
  #sym.plus.minus 0.01%.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/trips.py`, `configuration.py`],
  estado: [Implementado. Cada viaje se replica `round(fexp_vj)` veces, con tope `MAX_COPIAS`.],
  fecha: [],
)

=== F2 -- Construcción de Matrices Origen-Destino

#reqTable(
  id: [RF-006],
  tipo: [Funcional],
  cu: [CU-02],
  descripcion: [El sistema debe construir matrices O/D diferenciadas por modo de transporte: automóvil particular, transporte público (SITP/TransMilenio),
  motocicleta y bicicleta, usando los viajes filtrados y expandidos de la encuesta. Cada modo debe producir un archivo .od independiente.],
  razon: [SUMO modela cada modo de transporte con parámetros de comportamiento distintos (velocidad, aceleración, tamaño del vehículo). Mezclar modos en
  una sola matriz produce simulaciones incorrectas.],
  criterio: [Para cada modo con al menos un viaje registrado en la encuesta, el sistema debe generar un archivo .od. El número de archivos generados debe
  coincidir con el número de modos con viajes en la encuesta.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/trips.py`, `vtypes.py`],
  estado: [Implementado con un formato distinto: en lugar de un `.od` por modo, cada viaje se emite como `<trip>` TAZ a TAZ con su vType (modo) en un único `.trips.xml`.],
  fecha: [],
)

#reqTable(
  id: [RF-007],
  tipo: [Funcional],
  cu: [CU-02],
  descripcion: [El sistema debe construir matrices O/D diferenciadas por al menos tres períodos horarios: AM (6:00–9:00), PM (16:00–19:00) y nocturno
  (21:00–24:00), usando como criterio de clasificación la hora de inicio del viaje registrada en la encuesta. Cada período debe producir archivos .od
  separados por modo.],
  razon: [Los patrones de movilidad varían significativamente por franja horaria. Las horas de máxima demanda (HMD) AM y PM son los períodos de mayor
  interés.],
  criterio: [El sistema debe generar al menos 3 *#sym.ast* N archivos .od, donde N es el número de modos con viajes. Los archivos de período AM deben
  contener únicamente viajes con hora de inicio entre 6:00 y 8:59.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/configuration.py`],
  estado: [Parcial. La versión actual simula la ventana AM de 7:00 a 10:00 (`HORA_INI`, `HORA_FIN`); PM y nocturno quedan pendientes.],
  fecha: [],
)

#reqTable(
  id: [RF-008],
  tipo: [Funcional],
  cu: [CU-02],
  descripcion: [El sistema debe exportar cada matriz O/D al formato de archivo .od requerido por SUMO (TAZ-based OD matrix), con la estructura de
  encabezado, declaración de zonas TAZ y valores de viajes que especifica la documentación oficial de SUMO (versión 1.19+).],
  razon: [duarouter solo acepta archivos .od con la estructura exacta documentada por SUMO. Un formato incorrecto impide la generación de rutas.],
  criterio: [Cada archivo .od generado debe ser procesado exitosamente por duarouter sin errores de formato. Se verificará ejecutando duarouter con el
  archivo generado sobre la red .net.xml de Usaquén.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/trips.py`],
  estado: [Reemplazado por viajes TAZ (`fromTaz`/`toTaz`) que duarouter rutea directamente.],
  fecha: [],
)

=== F3 -- Generación de Red Vial y Zonas TAZ

#reqTable(
  id: [RF-009],
  tipo: [Funcional],
  cu: [CU-03],
  descripcion: [El sistema debe generar un archivo de red vial .net.xml válido para el polígono de Usaquén invocando netconvert sobre la red OSM
  descargada, incluyendo velocidades por tipo de vía, prioridades de paso y tipos de carretera definidos en el archivo de configuración.],
  razon: [El archivo .net.xml es el insumo de infraestructura obligatorio de SUMO. Sin él no es posible ejecutar ninguna simulación.],
  criterio: [El archivo .net.xml generado debe superar la validación de netconvert (salida sin errores) y SUMO debe poder cargar la red sin advertencias
  críticas (tipo ERROR en el log de SUMO).],
  prioridad: [Alta],
  modulo: [`notebooks/F2.x`, `data/processed/`],
  estado: [Implementado. La red 3D (`usaquen_3d_v2.net.xml`, con elevación) se generó con netconvert en los notebooks.],
  fecha: [],
)

#reqTable(
  id: [RF-010],
  tipo: [Funcional],
  cu: [CU-03],
  descripcion: [El sistema debe generar el archivo de zonas TAZ (.taz.xml) para Usaquén usando los polígonos de las Unidades de Planeamiento Zonal (UPZ)
  de la localidad, asignando a cada TAZ los nodos de la red .net.xml que se encuentren dentro de su polígono.],
  razon: [Las zonas TAZ son la unidad espacial que conecta la matriz O/D con la red vial. Sin ellas duarouter no puede asignar rutas a los viajes.],
  criterio: [Cada UPZ de Usaquén debe aparecer como una zona en el .taz.xml y debe contener al menos un nodo de la red. El archivo debe ser validado por
  SUMO sin errores de zona vacía.],
  prioridad: [Alta],
  modulo: [`data/processed/usaquen.taz.xml`],
  estado: [Implementado (`usaquen.taz.xml`).],
  fecha: [],
)

=== F4 -- Generación de Archivos de Simulación

#reqTable(
  id: [RF-011],
  tipo: [Funcional],
  cu: [CU-04],
  descripcion: [El sistema debe generar el archivo de tipos de vehículo (.vtype.xml) con los parámetros de comportamiento estándar de SUMO para cada modo
  de transporte modelado: automóvil particular, bus SITP, motocicleta y bicicleta. Los valores de velocidad máxima, aceleración, deceleración y longitud
  del vehículo deben tomarse de los valores por defecto documentados en SUMO 1.19.],
  razon: [SUMO requiere que cada vehículo esté asociado a un tipo con parámetros físicos válidos. Sin este archivo la simulación no puede iniciarse.],
  criterio: [El archivo .vtype.xml debe contener al menos cuatro entradas (una por modo). SUMO debe cargar el archivo sin errores ni advertencias de tipo
  desconocido.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/vtypes.py`],
  estado: [Implementado. Diez vTypes (auto, bici, moto, taxi, escolar, especial, informal, otro y bus_pt).],
  fecha: [],
)

#reqTable(
  id: [RF-012],
  tipo: [Funcional],
  cu: [CU-04],
  descripcion: [El sistema debe invocar duarouter con la matriz O/D, la red .net.xml y las zonas .taz.xml para generar el archivo de rutas (.rou.xml),
  configurando el número máximo de iteraciones de asignación dinámica de rutas (DUE) según el parámetro definido en el archivo de configuración.],
  razon: [El .rou.xml especifica los viajes y sus rutas dentro de la red vial. Es el insumo de demanda que SUMO requiere para ejecutar la simulación.],
  criterio: [duarouter debe completar la ejecución sin errores y producir un .rou.xml con al menos un viaje por cada par O/D con valor mayor a cero en la
  matriz .od.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/duarouter.py`],
  estado: [Parcial: una sola pasada de duarouter (`--ignore-errors --repair`, viajes ordenados por `depart`); las iteraciones de asignación dinámica (duaIterate) no se implementaron.],
  fecha: [],
)

=== F5 -- Variación Paramétrica y Escenarios Hipotéticos

#reqTable(
  id: [RF-013],
  tipo: [Funcional],
  cu: [CU-05],
  descripcion: [El sistema debe permitir la ejecución del pipeline con distintos valores de los parámetros de entrada (período horario, modo de
  transporte, localidad, factor de escala de demanda) especificados en el archivo de configuración YAML, generando conjuntos de artefactos SUMO
  independientes por cada combinación de parámetros sin necesidad de modificar el código fuente.],
  razon: [La capacidad de generar escenarios hipotéticos (ej. aumento del 20% en demanda vehicular, cierre de vías) es el objetivo diferenciador del
  sistema respecto a un pipeline ETL convencional.],
  criterio: [Dados dos archivos de configuración con factores de escala 1.0 y 1.2 respectivamente, el sistema debe generar dos conjuntos de artefactos
  cuyo total de viajes expandidos difiera exactamente en un 20%.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/demanda.py`, `api/api.py`],
  estado: [Implementado y ampliado: la variación paramétrica se hace desde la API/visor con presets de demanda, conteos por modo, semilla, estilo de conducción y cierres viales (ver RF-021 a RF-025).],
  fecha: [],
)

#reqTable(
  id: [RF-021],
  tipo: [Funcional],
  cu: [CU-05],
  descripcion: [El sistema debe ofrecer presets de demanda que redistribuyan los viajes entre modos sin cambiar el total. Los presets son
  `encuesta`, `mas_vehiculos`, `mas_peatones` y `dia_sin_carro`. La redistribución se hace con reglas de transferencia modal basadas en
  P(modo | duración del viaje), calculada sobre la encuesta del día completo ponderada por `fexp`. Un viaje transferido conserva su origen, su
  destino y su hora de salida.],
  razon: [Permite evaluar políticas de movilidad (p. ej. día sin carro) con una demanda coherente con los patrones de la encuesta.],
  criterio: [Con `encuesta` y sus conteos por defecto, los viajes generados son idénticos a la expansión simple de la encuesta (prueba
  `test_demanda.py`). Con cualquier preset, el total de viajes es igual al de la encuesta.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/demanda.py`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-022],
  tipo: [Funcional],
  cu: [CU-05],
  descripcion: [El sistema debe permitir fijar el número de viajes por modo y la semilla aleatoria de una corrida. Los conteos se asignan entre los
  viajes de la encuesta de ese modo por el método de mayor residuo. Si el preset no tiene viajes de un modo, la asignación usa el conjunto base de la
  encuesta.],
  razon: [El analista necesita escenarios con cantidades exactas por modo y resultados repetibles.],
  criterio: [Dos corridas con los mismos conteos y semilla generan el mismo `.trips.xml`; el total por modo coincide con el pedido. La API rechaza
  totales mayores a `MAX_VIAJES` (100 000).],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/demanda.py`, `api/api.py`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-023],
  tipo: [Funcional],
  cu: [CU-05],
  descripcion: [El sistema debe permitir elegir un estilo de conducción (agresivo, normal o cauteloso) que ajuste `sigma`, `speedFactor`, `tau` y
  `lcSpeedGain` de los vTypes motorizados. Peatones y bicicletas no se modifican.],
  razon: [El comportamiento de los conductores bogotanos es heterogéneo; el estilo permite analizar la sensibilidad de los resultados.],
  criterio: [Con estilo distinto de `normal`, la corrida incluye un `vtypes_estilo.xml` cuyos vTypes motorizados tienen los parámetros del estilo.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/estilos.py`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-024],
  tipo: [Funcional],
  cu: [CU-05],
  descripcion: [El sistema debe permitir cerrar vías durante una corrida. El usuario elige la vía con un clic en el mapa (capa de vías visible
  en la pestaña Cierres, con nombre, clase y carriles), decide si cierra los dos sentidos y fija la franja horaria. Cada cierre genera un
  `<rerouter>` con `<closingReroute>` sobre el edge correspondiente, para que los vehículos recalculen su ruta. El id del edge solo se pide en
  opciones avanzadas.],
  razon: [Los cierres por obras o eventos son uno de los escenarios hipotéticos centrales de la propuesta.],
  criterio: [Una corrida con un cierre incluye `cierres.xml` en sus *additional files* y ningún vehículo atraviesa el edge cerrado en la ventana del
  cierre. `GET /red/vias` devuelve un LineString por edge vehicular con el edge del sentido contrario cuando existe.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/cierres.py`, `vias.py`, `kepler/src/components/PanelCierres.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-025],
  tipo: [Funcional],
  cu: [CU-07],
  descripcion: [El sistema debe incluir una simulación precalculada y versionada de cada preset con sus conteos por defecto. Cada una se guarda como
  `trips.geojson.gz`, `volumenes.json` y `meta.json`, con el hash de los insumos. La API debe servirlas comprimidas. El visor debe cargarlas como
  corridas terminadas y abrir la del preset `encuesta` al iniciar.],
  razon: [Una corrida completa tarda varios minutos; las precalculadas permiten explorar los presets de inmediato.],
  criterio: [Al abrir el visor sin corridas propias se muestra la simulación `encuesta`. Si el panel coincide con un preset, sin cierres viales y
  con el estilo de conducción normal, el botón ofrece "Cargar simulación" en lugar de ejecutar.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/precalculadas.py`, `kepler/src/App.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

=== F6 -- Módulo Web: Visualización y Parametrización

#reqTable(
  id: [RF-017],
  tipo: [Funcional],
  cu: [CU-07],
  descripcion: [El módulo web debe permitir visualizar los resultados producidos por SUMO en una interfaz gráfica accesible desde el navegador, mostrando
  al menos las siguientes métricas por simulación: volumen vehicular por segmento de vía, tiempo promedio de viaje, índice de congestión por zona TAZ y
  estadístico GEH por punto de aforo. La visualización debe actualizarse al seleccionar una simulación diferente sin recargar la página.],
  razon: [Los resultados de SUMO se entregan como archivos XML y CSV de difícil interpretación para usuarios no técnicos. La interfaz web elimina esa
  barrera y hace el sistema accesible a planificadores de movilidad sin conocimiento de SUMO.],
  criterio: [Dado un conjunto de resultados de simulación válidos, el módulo web debe renderizar las métricas listadas en menos de 3 segundos desde que el
  usuario selecciona la simulación. Verificable con prueba manual ante el director.],
  prioridad: [Alta],
  modulo: [`kepler/src/App.jsx`],
  estado: [Parcial. El visor anima los viajes por modo y muestra volúmenes por acceso de cada intersección; tiempos de viaje y GEH por punto de aforo quedan pendientes.],
  fecha: [],
)

#reqTable(
  id: [RF-018],
  tipo: [Funcional],
  cu: [CU-07],
  descripcion: [El módulo web debe exponer los resultados de SUMO a través de una API REST que devuelva los datos en formato JSON. La API debe soportar al
  menos los endpoints: GET /simulaciones (lista de simulaciones disponibles), GET /simulaciones/{id}/metricas (métricas de una simulación específica) y
  GET /simulaciones/{id}/geh (resultados de validación GEH).],
  razon: [La separación entre backend (API REST) y frontend (interfaz gráfica) garantiza que los resultados sean consumibles por otras herramientas en el
  futuro, además de por el frontend actual.],
  criterio: [Los tres endpoints deben responder con código HTTP 200 y contenido JSON válido ante peticiones con IDs de simulación existentes, y con código
  404 ante IDs inexistentes.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/api.py`],
  estado: [Implementado con los endpoints actuales: `GET /simulaciones`, `GET /simulaciones/{id}`, `GET /simulaciones/{id}/kepler-trips`, `GET /intersecciones[/{id}]`; 404 si no existe.],
  fecha: [],
)

#reqTable(
  id: [RF-019],
  tipo: [Funcional],
  cu: [CU-08],
  descripcion: [El módulo web debe permitir al usuario configurar y lanzar una nueva simulación desde la interfaz gráfica, especificando al menos los
  siguientes parámetros: período horario (AM / PM / nocturno), modos de transporte activos (selección múltiple) y factor de escala de demanda (valor
  numérico). Al confirmar, el sistema debe invocar el pipeline ETL con los parámetros seleccionados y notificar al usuario cuando la simulación haya
  finalizado.],
  razon: [La parametrización desde la web elimina la necesidad de editar el archivo config.yaml manualmente, haciendo el sistema accesible a usuarios sin
  conocimiento de Python ni de la estructura de archivos del proyecto.],
  criterio: [El usuario debe poder lanzar una simulación con parámetros distintos a los de la última ejecución sin editar ningún archivo en disco. El
  sistema debe mostrar un indicador de progreso durante la ejecución y un mensaje de éxito o error al finalizar.],
  prioridad: [Alta],
  modulo: [`kepler/src/components/PanelDemanda.jsx`, `api/jobs.py`],
  estado: [Implementado (pestaña Demanda: preset, conteos por modo, escala, semilla, estilo y cierres).],
  fecha: [],
)

#reqTable(
  id: [RF-020],
  tipo: [Funcional],
  cu: [CU-08],
  descripcion: [El módulo web debe validar en el frontend los parámetros ingresados por el usuario antes de enviarlos al backend, verificando que: el
  factor de escala de demanda sea un número positivo mayor a cero, al menos un modo de transporte esté seleccionado y el período horario tenga un valor
  válido. Los errores de validación deben mostrarse al usuario de forma clara antes de permitir el envío del formulario.],
  razon: [La validación en el frontend previene llamadas innecesarias al backend y el lanzamiento de simulaciones con parámetros inválidos que consumirían
  recursos de cómputo sin producir resultados útiles.],
  criterio: [Dado un formulario con factor de escala igual a cero, el sistema debe mostrar un mensaje de error visible y no enviar la petición al backend.
  Verificable mediante prueba manual.],
  prioridad: [Media],
  modulo: [`kepler/src/components/PanelDemanda.jsx`, `api/api.py`],
  estado: [Implementado (validación en el panel y en el modelo Pydantic de la API).],
  fecha: [],
)

#reqTable(
  id: [RF-026],
  tipo: [Funcional],
  cu: [CU-08],
  descripcion: [El sistema debe ejecutar una corrida a la vez en segundo plano. Debe informar su avance global y por etapa (generando demanda,
  ruteando, simulando, exportando) y permitir cancelarla. Al cancelar se detienen los subprocesos y se borran los archivos de la corrida, salvo su
  estado.],
  razon: [Las corridas tardan minutos; el usuario necesita saber cuánto falta y poder detener una corrida equivocada.],
  criterio: [El avance mostrado crece de forma monótona hasta 100%. Tras cancelar, `runs/<id>/` contiene solo `estado.json` con estado `cancelada`.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/jobs.py`, `etl/sumo/proceso.py`, `kepler/src/hooks.js`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-027],
  tipo: [Funcional],
  cu: [CU-07],
  descripcion: [El visor debe animar en el mapa los viajes simulados con una capa de trayectorias de kepler.gl: una línea por vehículo o persona con
  coordenadas `[lon, lat, z, t]` y un color por modo. Al reemplazar una corrida no debe recargar la página.],
  razon: [Ver los viajes moverse en el tiempo es la forma más directa de entender los resultados de SUMO.],
  criterio: [Al cargar una corrida, la leyenda muestra los modos presentes con su número de viajes y la línea de tiempo reproduce la ventana
  7:00–10:00.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/kepler.py`, `kepler/src/App.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

=== F7 -- Validación y Reportes

#reqTable(
  id: [RF-014],
  tipo: [Funcional],
  cu: [CU-06],
  descripcion: [El sistema debe comparar los volúmenes vehiculares simulados por SUMO en los puntos de aforo de Usaquén contra los volúmenes reales de la
  base de datos HMD, calculando el estadístico GEH para cada punto de aforo. El resultado debe exportarse en un archivo CSV con columnas: punto_aforo,
  volumen_simulado, volumen_real, GEH.],
  razon: [El GEH es la métrica estándar de calibración de modelos de tráfico. Un GEH $<$ 5 en al menos el 85% de los puntos indica que el modelo es
  válido.],
  criterio: [El archivo de validación CSV debe generarse con una fila por punto de aforo HMD disponible en Usaquén. El sistema debe imprimir en el log el
  porcentaje de puntos con GEH $<$ 5.],
  prioridad: [Alta],
  modulo: [Módulo de Validación (etl/validation.py)],
  estado: [Pendiente (planeado para la Fase 4).],
  fecha: [],
)

#reqTable(
  id: [RF-015],
  tipo: [Funcional],
  cu: [CU-06],
  descripcion: [El sistema debe generar un log de ejecución estructurado en formato texto plano (pipeline.log) que registre: inicio y fin de cada fase,
  número de registros procesados y descartados por fase, porcentaje de descarte acumulado, métricas GEH obtenidas y cualquier advertencia o error ocurrido
  durante la ejecución.],
  razon: [El log es el principal mecanismo de observabilidad del pipeline. Permite al usuario detectar problemas de calidad de datos y reproducir la
  ejecución con los mismos parámetros.],
  criterio: [Al finalizar una ejecución exitosa, el archivo pipeline.log debe existir y contener al menos una entrada de inicio y una de fin para cada una
  de las fases F1 a F5, con marca de tiempo.],
  prioridad: [Media],
  modulo: [`simulation-service/src/api/jobs.py`],
  estado: [Parcial. Cada corrida registra su estado y avance en `runs/<id>/estado.json` y el log de SUMO en `output/`.],
  fecha: [],
)

#reqTable(
  id: [RF-016],
  tipo: [Funcional],
  cu: [CU-06],
  descripcion: [El sistema debe guardar un archivo de checkpoint al finalizar cada fase del pipeline (F1 a F5), de forma que ante un fallo en una fase
  posterior sea posible reanudar la ejecución desde la última fase completada sin reprocesar las anteriores. El usuario debe poder activar o desactivar
  esta función mediante el archivo de configuración.],
  razon: [El pipeline completo puede tardar hasta 4 horas. Un fallo en la fase de validación no debe obligar a repetir la ingestión ni la construcción de
  matrices.],
  criterio: [Simulado un fallo al inicio de la fase F4, al relanzar el pipeline con el flag y opcion #{sym.hyph}#{sym.hyph}#text(fill:olive)[resume], el
  sistema debe saltar las fases F1-F3 y comenzar desde F4, produciendo artefactos idénticos a una ejecución completa.],
  prioridad: [Media],
  modulo: [Módulo transversal (etl/checkpoint.py)],
  estado: [Pendiente. Las simulaciones precalculadas (RF-025) evitan recalcular los presets, pero no hay reanudación por fase.],
  fecha: [],
)

=== F8 -- Intersecciones y Semaforización

#reqTable(
  id: [RF-028],
  tipo: [Funcional],
  cu: [CU-09],
  descripcion: [El sistema debe mostrar en el mapa las intersecciones semaforizadas de la red (una por `tlLogic`). Al seleccionar una, debe abrir su
  ficha con:
  - nombre de las vías que se cruzan (tomado de OpenStreetMap),
  - accesos y su volumen por tipo de vehículo en la corrida cargada,
  - fases del programa con su duración y estado.],
  razon: [La intersección es la unidad de análisis de las decisiones de semaforización.],
  criterio: [`GET /intersecciones` devuelve un punto por `tlLogic` y `GET /intersecciones/{id}` devuelve la ficha (404 si no existe). Los volúmenes
  cambian al cambiar la corrida cargada.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/intersecciones.py`, `kepler/src/components/FichaInterseccion.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-029],
  tipo: [Funcional],
  cu: [CU-09],
  descripcion: [El sistema debe recortar la red y la demanda a un radio configurable (50 a 2000 m) alrededor de un cruce. La red se recorta con
  netconvert (`--keep-edges.in-geo-boundary`) y la demanda con `cutRoutes.py`, tomando como entrada el vehroute de la corrida cuando exista. Así los
  escenarios locales se simulan en segundos.],
  razon: [Simular toda Usaquén para evaluar un solo cruce es lento; el recorte permite iterar rápido sobre programas y escenarios.],
  criterio: [La zona resultante (`zona.net.xml`) conserva los ids de edges y nodos de la red original, y SUMO la carga sin errores.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/subred.py`, `etl/etl.py` (`run_recorte`)],
  estado: [Implementado. En v2.0 se corrigió el uso de `cutRoutes.py` (`--disconnected-action`), que antes dejaba las zonas sin demanda.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-030],
  tipo: [Funcional],
  cu: [CU-10],
  descripcion: [El sistema debe permitir editar las duraciones y estados de las fases de un semáforo y calcular un programa con el método de Webster
  @webster a partir de los volúmenes por acceso. La ficha describe cada fase en palabras ("pasan los de la Calle 134 de frente y a la derecha") y el
  editor cambia la luz de un acceso con un clic; las cadenas de estado de SUMO quedan en opciones avanzadas. En Webster cada acceso cuenta en las
  fases en las que tiene verde, con un flujo de saturación de 1800 veh/h por carril, y las fases de amarillo conservan su duración. Antes de
  guardarlo debe validar que el estado de cada fase tenga un carácter por movimiento, que haya al menos
  una fase amarilla de 3 s o más si hay verdes, y que el ciclo sea de al menos 15 s.],
  razon: [Ajustar tiempos es la intervención más común y barata sobre una intersección.],
  criterio: [Un programa inválido se rechaza con un mensaje que indica la regla incumplida (y la fase, cuando aplica). El ciclo de Webster
  $C = (1,5 L + 5)/(1 - Y)$ queda entre 30 y 150 s (150 s cuando $Y >= 0,9$).],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/programas_tls.py`, `FichaInterseccion.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-031],
  tipo: [Funcional],
  cu: [CU-10],
  descripcion: [El sistema debe comparar el programa actual con el de Webster y con los que guarde el usuario sobre la misma zona (300 m) y la
  misma demanda, con una hora punta de SUMO por programa. Por programa reporta el tiempo perdido y detenido por vehículo, la cola más larga y las
  detenciones en los accesos (detectores E2 por carril), el tiempo perdido por peatón y los vehículos atendidos; resalta el mejor valor de cada
  fila y resume el resultado en una frase.],
  razon: [La decisión entre programas debe sustentarse con métricas cuantitativas comparables.],
  criterio: [`POST /intersecciones/{id}/comparaciones` devuelve un id; al terminar, `GET /comparaciones/{id}` trae una fila por programa con las
  métricas.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/comparacion_programas.py`, `etl/etl.py` (`run_comparacion_programas`), `api/api.py`,
  `kepler/src/components/TablaComparacion.jsx`],
  estado: [Implementado en v2.2. Antes la comparación no aplicaba el programa a la simulación y solo leía teleports.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-032],
  tipo: [Funcional],
  cu: [CU-11],
  descripcion: [El sistema debe priorizar los cruces sin semáforo con la lógica del proyecto Semáforos de Barranquilla (`github.com/Victorpay1/semaforos-barranquilla`), adaptada a la
  red de SUMO:
  - *cruces, no nodos:* los nodos a menos de 20 m se agrupan (span máximo 45 m) y los del mismo par de calles a menos de 150 m (doble calzada) se
    fusionan; un cruce necesita dos calles distintas que se corten a más de 35°;
  - *reglas duras:* vía colectora o de mayor jerarquía sin autopistas ni troncales (la Autopista Norte con TransMilenio es de acceso controlado);
    vía secundaria al menos local residencial; a nivel (sin rampas ni glorietas a menos de 40 m); conflicto real (desde la secundaria se cruza de
    frente o se gira a la izquierda); sin semáforo a menos de 80 m;
  - *evidencia calibrada con los cruces que ya tienen semáforo:* siniestros a menos de 30 m ≥ p75 de los semaforizados (mínimo 3), o ≥ mediana con
    un colegio o centro de salud a menos de 200 m; tramo de la vía principal sin semáforo ≥ 600 m; volumen simulado que entra al cruce ≥ p75 de
    los semaforizados;
  - *niveles:* prioritario (reglas y dos o más evidencias), recomendado (una), en observación (siniestros ≥ mediana o un generador cerca); dos
    cruces del mismo nivel a menos de 120 m se estudian juntos y el peor baja un nivel;
  - *puntaje:* piso del nivel (75, 50 o 25) más hasta 25 puntos por siniestros, volumen, generadores, tramo y jerarquía.
  Cada candidato lleva los nodos del cruce, las calles y la evidencia en texto. El mapa muestra los prioritarios y recomendados.],
  razon: [Ayuda a decidir dónde vale la pena estudiar un semáforo nuevo antes de simularlo (ver F9). La versión anterior puntuaba cada nodo de SUMO
  por separado (unos 700 candidatos, incluidos nodos a mitad de cuadra y cruces de la Autopista Norte).],
  criterio: [`test_priorizacion.py`: una doble calzada es un solo cruce; un nodo a mitad de cuadra, una troncal, un cruce con solo giro a la derecha o
  con semáforo a 70 m quedan fuera; los niveles responden a la evidencia y al NMS. Con la red de Usaquén y la corrida `encuesta` resultan 5
  prioritarios, 56 recomendados y 146 en observación.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/priorizacion.py`, `evidencia.py`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

=== F9 -- Simulador 3D Comparativo de Semáforo Propuesto

Esta funcionalidad permite ver de forma tangible, como en un videojuego pero con los datos reales de Usaquén, qué pasaría al poner un semáforo en
un cruce que hoy no lo tiene. La pantalla se parte en dos:
- a la izquierda, el cruce como está hoy, sin semáforo;
- a la derecha, el mismo cruce con el semáforo propuesto.

Los dos lados corren la misma demanda, con la misma semilla y a la par (lockstep). Se puede seguir a cualquier actor en tercera persona y ver sus
datos, su riesgo y sus decisiones.

#reqTable(
  id: [RF-033],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Dado un cruce sin semáforo, el sistema debe preparar en segundo plano un escenario comparativo con:
  - el recorte de la zona (350 m) como escenario actual (`zona.net.xml`);
  - una variante idéntica con un semáforo de tiempos fijos instalado por netconvert (`--tls.set`) en ese nodo (`zona_tls.net.xml`);
  - una demanda común a ambos lados: los viajes reales de una corrida que pasan por la zona más un tráfico de fondo por modo generado con
    `randomTrips.py`, con intensidades (veh/h y peatones/h) ajustables por el usuario.],
  razon: [Recortada a unos cientos de metros, la demanda real de la encuesta es muy escasa para mostrar el efecto de un semáforo. El tráfico de fondo la
  completa sin perder los viajes reales.],
  criterio: [`POST /cruces/{nodo}/comparacion3d` responde 202. En menos de 60 s, `GET /comparacion3d/{id}` pasa a estado `lista`, con
  `fuente_demanda` (`real`, `sintetica` o `real+sintetica`) y el número de fases y el ciclo del semáforo propuesto. Si el nodo ya tiene semáforo, el
  estado es `error` con un mensaje que lo indica.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/semaforo_nuevo.py`, `demanda_zona.py`, `etl/etl.py` (`run_escenario_semaforo`)],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-034],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El visor debe mostrar los dos escenarios en una vista 3D partida. Cada lado debe incluir:
  - la red 3D real de la zona: calzadas con divisorias, doble línea amarilla y bordes, polígonos de cruce con su elevación, andenes, ciclorrutas,
    cebras y líneas de pare en el cruce estudiado, y un terreno que sigue la pendiente;
  - los edificios de OpenStreetMap y Microsoft Building Footprints extruidos, con ventanas; donde ninguna fuente tiene huellas, edificios de
    relleno ilustrativo en los frentes de manzana (se indica en la interfaz);
  - en el lado con semáforo, un poste con brazo por acceso cuyas luces cambian según el estado de cada paso; en el lado sin semáforo, señales de
    PARE en la vía que cede;
  - un modelo por actor según su tipo (carro, taxi, moto, bicicleta, bus o peatón), con el movimiento interpolado entre frames.],
  razon: [Ver el escenario en 3D hace tangible el resultado de la simulación para usuarios no técnicos.],
  criterio: [Con la comparación abierta, ambos lados muestran los mismos actores en las mismas posiciones mientras sus trayectorias no diverjan, y el
  lado derecho muestra las luces del semáforo con la fase reportada por TraCI.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/comparacion3d.py`, `etl/sumo/escena3d.py`, `kepler/src/components/simulador3d/escena.js`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-035],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El usuario debe poder seguir con cámara en tercera persona trasera a cualquier vehículo o peatón presente en ambos escenarios, o
  lanzar uno nuevo. Para lanzarlo elige el tipo, la vía de llegada, el giro (recto, izquierda, derecha) y el estilo de conducción; el sistema lo
  inyecta en los dos lados a la vez con la misma ruta. También debe ofrecer una cámara aérea sobre el cruce o la vía elegida. La cámara en tercera
  persona no debe atravesar los edificios al girar en una esquina.],
  razon: [Seguir un mismo actor en los dos escenarios muestra cómo cambia su comportamiento según haya o no semáforo.],
  criterio: [Tras lanzar un actor, en menos de 2 s aparece en ambos lados con el mismo id y la cámara lo sigue. Si no hay ruta peatonal por el
  acceso elegido, el visor muestra un aviso sin interrumpir la simulación.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/comparacion3d.py` (`Lado.inyectar`), `kepler/src/components/simulador3d/Simulador3D.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-036],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Para el actor seguido, cada lado debe mostrar en pantalla (HUD):
  - velocidad y límite del carril, aceleración, distancia al vehículo de adelante;
  - tiempo de espera, tiempo perdido y estado y distancia del próximo semáforo;
  - la acción que está tomando (acelera, frena, frena por el semáforo, cede el paso, en cola, cambia de carril, camina, espera para cruzar);
  - las decisiones posibles en el próximo cruce: cada giro con su estado (verde, rojo, vía principal, cede), si hay tráfico en conflicto y cuál
    tomará según su ruta;
  - su intención de cambio de carril y el motivo.],
  razon: [Explica por qué el actor se comporta como lo hace en cada escenario.],
  criterio: [Los valores del HUD coinciden con los que reporta TraCI en el mismo paso. Un vehículo detenido frente a un rojo muestra "Detenido en el
  semáforo".],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/telemetria.py`, `kepler/src/components/simulador3d/HUD.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-037],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El sistema debe calcular cada cierto tiempo, configurable entre 1 y 10 s simulados, un índice de riesgo de 0 a 100 para el actor
  seguido, con nivel bajo, medio o alto y la causa dominante. El índice toma el peor de tres indicadores sustitutos de seguridad:
  - TTC con el vehículo de adelante (crítico < 1,5 s);
  - DRAC (crítico > 3,35 m/s²);
  - PET aproximado con el tráfico transversal en el cruce (crítico < 1,5 s).
  Para peatones se usa el tiempo hasta que lo alcance el vehículo más cercano. El HUD debe mostrar el historial reciente del índice.],
  razon: [El riesgo es el argumento principal para instalar un semáforo; medirlo en el tiempo permite comparar ambos escenarios.],
  criterio: [Con TTC = 1 s el índice es 100 (alto); sin conflictos es 0 (bajo); el período elegido cambia la frecuencia de las muestras del historial
  (prueba `test_telemetria.py`).],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/telemetria.py`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-038],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Cada escenario debe tener en su esquina superior derecha un minimapa 2D tipo Maps con el cruce estudiado, el límite de la zona
  simulada, la posición del actor seguido en ese escenario, el rastro de su recorrido y, en gris, dónde va el mismo actor en el otro escenario.],
  razon: [Ubica al usuario en la ciudad mientras ve la escena en 3D.],
  criterio: [El punto del actor en cada minimapa sigue las coordenadas lon/lat que TraCI reporta en ese escenario; el rastro se borra al cambiar de
  actor y un actor que aún no entra a la vía no se dibuja.],
  prioridad: [Media],
  modulo: [`kepler/src/components/simulador3d/Minimapa.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-039],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El usuario debe poder elegir cualquiera de las vías con nombre de la zona para llevar la cámara a ella y ver la lista de actores que
  circulan por esa vía en ese momento, con su tipo y velocidad, para seguir a uno.],
  razon: [Permite mirar las distintas vías del cruce y elegir qué actor observar.],
  criterio: [La lista de una vía solo contiene actores cuyo edge actual pertenece a esa vía.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/escena3d.py` (vías), `Simulador3D.jsx`],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-040],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Cada lado debe mostrar métricas del cruce actualizadas en cada frame:
  - vehículos a menos de 60 m del cruce y cuántos están detenidos;
  - espera media;
  - conflictos (pares de vehículos con PET < 1,5 s);
  - colisiones detectadas por SUMO;
  - vehículos y peatones en la zona.],
  razon: [Resume, lado a lado, el efecto del semáforo propuesto sobre la fluidez y la seguridad.],
  criterio: [Las métricas de ambos lados se calculan con la misma definición y radio; sin actores en el cruce, los contadores instantáneos son 0.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/comparacion3d.py` (`Lado.actores`, `Lado.contar_conflictos`)],
  estado: [Implementado.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-041],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El sistema debe exportar un reporte de la comparación 3D (PDF o CSV) con:
  - las métricas acumuladas de cada lado;
  - la distribución del índice de riesgo;
  - los datos del semáforo propuesto (fases y ciclo);
  - un resumen de recomendación.],
  razon: [El análisis debe poder entregarse a la entidad que toma la decisión.],
  criterio: [Al cerrar una comparación, el usuario puede descargar el reporte con los valores de ambos lados.],
  prioridad: [Media],
  modulo: [Por definir],
  estado: [Parcial: el resumen de la comparación se muestra en pantalla (RF-048); falta exportarlo a PDF o CSV.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-042],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El simulador debe permitir editar el programa del semáforo propuesto (ciclo y repartos, o Webster con los volúmenes de la zona) y
  reiniciar la comparación con el nuevo programa.],
  razon: [El programa por defecto de netconvert no es óptimo; la comparación es más justa con un programa ajustado a la demanda.],
  criterio: [El ciclo elegido se refleja en `GET /comparacion3d/{id}` y en la fase mostrada en el HUD del lado con semáforo.],
  prioridad: [Media],
  modulo: [`semaforo_nuevo.py` (`ciclo_s` ya soportado por la API interna), `programas_tls.py`],
  estado: [Parcial: el backend acepta `ciclo_s`; falta exponerlo en el visor.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-043],
  tipo: [Funcional],
  cu: [CU-05, CU-12],
  descripcion: [El sistema debe modelar el transporte público con buses, paradas y rutas reales (GTFS de TransMilenio/SITP mediante `gtfs2pt`) y
  viajes de personas con `personTrip modes="public"`, en lugar de representarlo como caminata.],
  razon: [Hoy los viajes de transporte público se emiten como `<person><walk>`, lo que subestima los buses en las vías y en los cruces.],
  criterio: [Una corrida con transporte público muestra buses deteniéndose en paradas y personas que los abordan.],
  prioridad: [Media],
  modulo: [Por definir],
  estado: [Pendiente (por desarrollar).],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RF-044],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [El simulador debe ofrecer un modo *Manual* en el que el usuario maneja el actor seguido con el teclado: acelerar, frenar y elegir el
  giro en el próximo cruce. Los comandos se aplican igual en los dos escenarios y SUMO conserva sus chequeos de seguridad (no atraviesa un rojo ni
  choca), de modo que se ve la decisión del usuario frente a las reglas del cruce. El modo *Auto* devuelve el control a SUMO.],
  razon: [Permite explorar "qué pasa si" el conductor toma otra decisión, como en un videojuego, sin romper la comparación.],
  criterio: [Con el modo manual activo, mantener W durante 3 s acelera el actor en ambos lados (verificado: 30 km/h en A y B), soltar y frenar lo
  detiene, y elegir un giro distinto cambia su destino en los dos lados (mensaje `giro`).],
  prioridad: [Media],
  modulo: [`simulation-service/src/api/comparacion3d.py` (`Lado.tomar_control`, `controlar`, `girar`), `Simulador3D.jsx`],
  estado: [Implementado.],
  version: "2.1",
  fecha: []
)

#reqTable(
  id: [RF-045],
  tipo: [Funcional],
  cu: [CU-11],
  descripcion: [El sistema debe descargar y versionar en `data/processed/` la evidencia externa de la priorización y de la escena 3D: siniestros
  georreferenciados de la Secretaría Distrital de Movilidad (Histórico de siniestros, datos abiertos de Bogotá) filtrados a Usaquén, colegios y
  centros de salud de OpenStreetMap y huellas de edificios de OpenStreetMap (`python -m etl.sumo.evidencia`). Si falta un archivo, la
  priorización no usa esa evidencia y la API lo informa en `notas`.],
  razon: [Barranquilla prioriza con siniestros y generadores de viajes; sin ellos solo quedan reglas geométricas.],
  criterio: [La descarga produjo 20.109 siniestros, 370 colegios y centros de salud y 14.773 edificios. Sin los archivos, `GET
  /intersecciones/priorizacion` responde con una nota y sin error.],
  prioridad: [Media],
  modulo: [`simulation-service/src/etl/sumo/evidencia.py`],
  estado: [Implementado.],
  version: "2.1",
  fecha: []
)


=== F10 -- Usabilidad para la toma de decisiones (v2.2)

Las funciones de semaforización eran correctas pero estaban escritas para quien conoce SUMO. Esta versión las acerca a un directivo de la
Secretaría de Movilidad: frases en vez de códigos, una tarjeta por cruce como la de Semáforos de Barranquilla @barranquilla y un resumen final que
dice si el semáforo ayudó en la simulación.

#reqTable(
  id: [RF-046],
  tipo: [Funcional],
  cu: [CU-11],
  descripcion: [La pestaña Semaforizar debe mostrar:
  - una lista de cruces sin semáforo con el conteo por nivel (prioritario, recomendado, en observación y con semáforo), búsqueda por nombre de
    calle y filtros "cerca de colegio" y "cerca de hospital";
  - al elegir un cruce, en el mapa o en la lista, un anillo sobre él y una tarjeta con el nivel, el tipo de vías ("Primaria × Residencial"), la
    medida sugerida, el porqué en frases simples, las cifras (siniestros con su gravedad, semáforo más cercano, accesos) y la vista del cruce en
    Street View, satélite y mapa;
  - el botón "Ver simulación: hoy y con semáforo", que abre el simulador 3D (F9);
  - el aviso de que la lista sirve para priorizar estudios y no es un dictamen.],
  razon: [Un directivo debe entender en segundos por qué un cruce está en la lista y reconocerlo en la calle.],
  criterio: [Elegir un cruce de la lista centra el mapa y dibuja el anillo; las tres vistas del cruce cargan sin clave de API; la búsqueda ignora tildes.],
  prioridad: [Alta],
  modulo: [`kepler/src/components/PanelSemaforizacion.jsx`, `VistaCruce.jsx`, `MapaCruce.jsx`, `priorizacion.py`],
  estado: [Implementado.],
  version: "2.2",
  fecha: []
)

#reqTable(
  id: [RF-047],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Al lanzar un actor, el sistema debe agregarlo con la misma ruta en los dos escenarios o en ninguno: valida la ruta en ambos antes de
  insertar, retira por igual el tráfico de fondo de los primeros 40 m de la vía de entrada y, si después de 1 s simulado el actor sigue esperando
  en algún lado, libera más vía en los dos (hasta 8 intentos). Un peatón usa la misma ruta calculada una sola vez.],
  razon: [La cola del semáforo propuesto podía llegar al borde de la zona y el actor entraba en un escenario y en el otro no, lo que rompía la comparación.],
  criterio: [Prueba por WebSocket con SUMO real: seis actores lanzados por los tres accesos de un cruce prioritario entran en el mismo paso en los dos lados.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/comparacion3d.py` (`inyectar_en_lados`, `Lado.despejar_entrada`, `_ViajeEgo`)],
  estado: [Implementado.],
  version: "2.2",
  fecha: []
)

#reqTable(
  id: [RF-048],
  tipo: [Funcional],
  cu: [CU-12],
  descripcion: [Cuando el actor seguido termina su viaje en los dos escenarios (o en uno y pasan 90 s), el simulador debe mostrar un resumen con la
  duración, el tiempo detenido, las paradas, las frenadas en seco (desaceleración de 4,5 m/s² o más), el riesgo máximo, el CO₂ emitido y la
  velocidad media de cada lado, y una frase de veredicto que no afirme mejoras que no ocurrieron. Debe incluir el balance del cruce durante la
  sesión, por hora: frenadas en seco, casi choques (PET < 1,5 s, cada par una vez cada 10 s), choques sin contar el calentamiento, cola más larga y
  espera media en la vía principal y en la que cede. El resumen también se abre con el botón "Resumen" y recuerda que el tráfico de fondo es un
  supuesto, no un aforo.],
  razon: [La pregunta del usuario es si de verdad sirve poner el semáforo; la vista 3D sola no la responde.],
  criterio: [`test_telemetria.py`: paradas, frenadas, tiempo detenido, veredictos (más seguro, solo más espera, sin cambios) y balance por hora.],
  prioridad: [Alta],
  modulo: [`etl/sumo/telemetria.py`, `api/comparacion3d.py`, `kepler/src/components/simulador3d/ResumenComparacion.jsx`],
  estado: [Implementado.],
  version: "2.2",
  fecha: []
)

=== Cruce de funcionalidades

La tabla relaciona cada funcionalidad con sus requerimientos y con las demás funcionalidades de las que depende.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Funcionalidad*], [*Requerimientos*], [*Depende de*]),
    [F1 -- Ingestión], [RF-001 a RF-003], [--],
    [F2 -- Matrices O/D], [RF-004 a RF-006], [F1],
    [F3 -- Red y TAZ], [RF-007 a RF-010], [F1],
    [F4 -- Archivos de simulación], [RF-011, RF-012], [F2, F3],
    [F5 -- Escenarios], [RF-013, RF-021 a RF-025], [F4],
    [F6 -- Módulo web], [RF-017 a RF-020, RF-026, RF-027], [F4, F5],
    [F7 -- Validación y reportes], [RF-014 a RF-016], [F4, aforos HMD georreferenciados (pendiente)],
    [F8 -- Intersecciones], [RF-028 a RF-032, RF-045], [F3, F4 (volúmenes por acceso), F6],
    [F9 -- Simulador 3D], [RF-033 a RF-044, RF-047, RF-048], [F3, F4, F8 (cruce candidato)],
    [F10 -- Usabilidad], [RF-046, RNF-USA-002], [F6, F8, F9],
  ),
  caption: [Cruce de funcionalidades.]
) <tabCruceFuncionalidades>

== Requerimientos de Desempeño

Los siguientes requerimientos establecen los umbrales cuantitativos de rendimiento del sistema, medibles durante las fases de verificación y validación.

#reqTable(
  id: [RD-001],
  tipo: [Desempeño -- Latencia],
  cu: [CU-01 a CU-06],
  descripcion: [El pipeline completo (fases F1 a F5) debe completarse en un tiempo total menor o igual a 4 horas en una máquina con 8 GB de RAM y CPU de 4
  núcleos físicos, procesando los datos de la localidad de Usaquén.],
  razon: [El equipo de cómputo disponible para el proyecto tiene exactamente esas especificaciones. Un tiempo mayor haría inviable la exploración
  iterativa de escenarios hipotéticos en una jornada de trabajo.],
  criterio: [Ejecutado el pipeline completo en la máquina de referencia con el dataset de Usaquén, el tiempo registrado entre el inicio de F1 y la
  finalización de F5 debe ser $<=$ 14,400 segundos.],
  prioridad: [Alta],
  modulo: [Pipeline completo],
  estado: [Cumplido: la corrida completa con la demanda de la encuesta (~24.600 viajes) toma varios minutos.],
  fecha: [],
)

#reqTable(
  id: [RD-002],
  tipo: [Desempeño -- Tasa de procesamiento],
  cu: [CU-02],
  descripcion: [La construcción de la matriz O/D (fase F2) debe completarse en un tiempo máximo de 30 minutos para un conjunto de datos de entrada de
  aproximadamente 500,000 registros de encuesta.],
  razon: [La encuesta de movilidad 2023 tiene del orden de 500,000 registros de viaje. Un tiempo mayor en esta fase comprometería el tiempo total del
  pipeline (RD-001).],
  criterio: [Ejecutada únicamente la fase F2 sobre el dataset completo de la encuesta en la máquina de referencia, el tiempo de ejecución debe ser $<=$
  1,800 segundos.],
  prioridad: [Media],
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  estado: [No aplica en la versión actual: la matriz se arma en los notebooks.],
  fecha: [],
)

#reqTable(
  id: [RD-003],
  tipo: [Desempeño -- Latencia],
  cu: [CU-12],
  descripcion: [La preparación de una comparación 3D (recorte, demanda y semáforo propuesto) debe tardar como máximo 60 s. Durante la comparación,
  el servidor debe emitir al menos 4 frames por segundo con los dos lados a velocidad 1× para zonas de hasta 200 actores por lado.],
  razon: [Por debajo de ese ritmo la animación pierde continuidad incluso con interpolación.],
  criterio: [Medido en la máquina de referencia, la preparación tardó 14 a 40 s y el bucle mantuvo 5 frames/s con unos 60 vehículos y 95 peatones por
  lado.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/comparacion3d.py`],
  estado: [Cumplido en las pruebas de integración.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RD-004],
  tipo: [Desempeño -- Render],
  cu: [CU-12],
  descripcion: [El visor debe renderizar las dos escenas 3D a 30 cuadros por segundo o más en un equipo con GPU integrada. Para lograrlo, las
  geometrías estáticas (carriles, cruces y edificios) se fusionan en pocas mallas por material.],
  razon: [Una experiencia "tipo videojuego" requiere fluidez visual.],
  criterio: [Medido con las herramientas de rendimiento del navegador durante 60 s de comparación a velocidad 1×.],
  prioridad: [Media],
  modulo: [`kepler/src/components/simulador3d/escena.js`],
  estado: [Por verificar en la prueba de aceptación.],
  version: "2.0",
  fecha: []
)

== Restricciones de Diseño

Las siguientes restricción se identificaron para delimitar el alcance del proyecto y las herramientas tecnológicas a utilizar, sin embargo cabe mencionar
que esto puede cambiar ya que, puede haber una tecnología que disminuya el tiempo de implementación.

- *Lenguaje de programación:* Python 3.11. De momento se tiene pensado utilizar Python como lenguaje de programación principal, no obstante lenguajes como
  C/C++ son utilizados en gran parte para el desarrollo de SUMO, no se descarta el uso de estos dos también para temas de integración o módulos
  adicionales.
- *Estilo de código:* el código fuente debe cumplir con la guía de estilo PEP 8. El cumplimiento se verifica automáticamente mediante pylint en cada
  ejecución de CI.
- *Herramientas del ecosistema SUMO:* la generación de la red (.net.xml) y de las rutas (.rou.xml) debe realizarse con netconvert y duarouter
  respectivamente. No es ideal reimplementar estas funcionalidades.
- *Software de código abierto:* todas las herramientas y bibliotecas usadas deben ser preferiblemente de código abierto o de uso académico gratuito.
- *Arquitectura del pipeline:* el sistema debe seguir una arquitectura de pipeline por fases secuenciales (F1-F5), donde cada fase produce artefactos que
  sirven como entrada de la fase siguiente.
- *Control de versiones:* todo el código fuente debe versionarse en el repositorio GitHub del proyecto con una estructura de carpetas definida en el SPMP.
- *Arquitectura del módulo web:* el módulo web sigue una arquitectura de dos capas: backend REST/WebSocket en Python (FastAPI, `simulation-service/`) y
  frontend React en el navegador (`kepler/`). El backend reutiliza los módulos del pipeline (`etl/sumo/`) sin duplicar lógica de procesamiento.
- *Patrón de los pasos del pipeline:* cada paso de `etl/sumo/` define un `*Config` inmutable, un `*Result` y un `*Stats` mutable, y lanza un
  `*Error(RuntimeError)` propio si falla la herramienta de SUMO que invoca. `configuration.py` es la única fuente de rutas y constantes.
- *Control en vivo:* toda interacción en tiempo real con SUMO (avance de corridas, simulador 3D) se hace por TraCI. No se interpreta la salida de
  consola de SUMO, porque llega en bloque al terminar el proceso.
- *Render 3D en el cliente:* la escena 3D se construye en el navegador con three.js a partir de la geometría de la red en coordenadas de SUMO; el
  servidor solo envía posiciones y estados.

Para las restricciones de diseño de arquitectura interna, modelos de datos y diagramas de componentes, se remite al documento SDD (Software Design
Document).

== Atributos del Sistema de Software (Requerimientos No Funcionales)

=== Confiabilidad

#reqTable(
  id: [RNF-CON-001],
  tipo: [No Funcional -- Confiabilidad],
  cu: [CU-01 a CU-06],
  descripcion: [El sistema debe manejar valores faltantes (NaN) en las columnas modo, origen_UPZ y destino_UPZ de la encuesta sin lanzar excepciones no
  controladas. Los registros afectados deben descartarse silenciosamente y el porcentaje de registros descartados debe registrarse en el log al finalizar
  la fase F1.],
  razon: [Los datasets reales de encuesta contienen inevitablemente registros incompletos. Un fallo por NaN detendría el pipeline completo.],
  criterio: [Dado un archivo de prueba con 10% de registros con NaN en origen_UPZ, el pipeline debe completarse sin excepciones y el log debe reportar
  exactamente 10% de registros descartados en F1.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/sumo/trips.py`],
  estado: [Implementado (filas inválidas descartadas y contadas).],
  fecha: [],
)

#reqTable(
  id: [RNF-CON-002],
  tipo: [No Funcional -- Confiabilidad],
  cu: [CU-01 a CU-06],
  descripcion: [Ante un fallo en cualquier fase del pipeline (excepción no controlada, archivo de entrada no encontrado, timeout de herramienta externa),
  el sistema debe guardar el estado procesado hasta ese punto en un archivo de checkpoint y terminar con un mensaje de error descriptivo en el log,
  indicando la fase fallida y la causa.],
  razon: [El pipeline puede ejecutarse por horas. Perder todo el progreso por un fallo al final de la ejecución es inaceptable para el flujo de trabajo
  del equipo.],
  criterio: [Simulado un fallo forzado al inicio de F4, el directorio de salida debe contener los artefactos de F1-F3 y el log debe indicar 'Fase F4
  fallida: [causa]'.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/api/jobs.py`],
  estado: [Parcial: un fallo deja el error en `estado.json`; cancelar borra la corrida.],
  fecha: [],
)

=== Disponibilidad

#reqTable(
  id: [RNF-DISP-001],
  tipo: [No Funcional -- Disponibilidad],
  cu: [CU-01 a CU-06],
  descripcion: [El pipeline debe poder ejecutarse de forma completamente offline una vez que los datos de entrada (encuesta XLSX, dump OSM, aforos HMD)
  hayan sido descargados. No debe depender de servicios en línea durante las fases F2 a F5.],
  razon: [El entorno de cómputo del equipo puede no tener acceso estable a Internet durante la ejecución de simulaciones. La disponibilidad del pipeline
  no debe depender de servicios externos en las fases críticas.],
  criterio: [Desconectada la red durante las fases F2-F5, el pipeline debe completarse sin errores de conexión.],
  prioridad: [Media],
  modulo: [Pipeline completo],
  estado: [Cumplido para el pipeline; el minimapa del simulador 3D usa teselas de OpenStreetMap en línea.],
  fecha: [],
)

=== Seguridad

#reqTable(
  id: [RNF-SEG-001],
  tipo: [No Funcional -- Seguridad],
  cu: [CU-01 a CU-06],
  descripcion: [El sistema no debe exponer los microdatos de la Encuesta de Movilidad 2023 en los artefactos de salida. Los archivos .od, .rou.xml y
  .taz.xml deben contener únicamente datos agregados por zona TAZ, sin identificadores de hogar ni de persona.],
  razon: [La Encuesta de Movilidad contiene datos de movilidad de hogares que pueden ser sensibles. Los artefactos de salida son compartidos con el
  director y los jurados del proyecto.],
  criterio: [Inspeccionados los archivos de salida, ninguno debe contener el campo ID_hogar ni ningún identificador individual de la encuesta.],
  prioridad: [Media],
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  estado: [Cumplido: los archivos de SUMO solo contienen viajes por TAZ con ids sintéticos (`auto_N`, `peaton_N`).],
  fecha: [],
)

=== Mantenibilidad

#reqTable(
  id: [RNF-MAN-001],
  tipo: [No Funcional -- Mantenibilidad],
  cu: [--],
  descripcion: [Toda función pública del pipeline debe tener un docstring con al menos los siguientes campos: descripción de la función, parámetros de
  entrada con su tipo, valor de retorno con su tipo y un ejemplo de uso.],
  razon: [El sistema será mantenido por cuatro integrantes del equipo con roles distintos. Sin documentación interna, la curva de aprendizaje para
  modificar una fase es demasiado alta.],
  criterio: [Ejecutado pydocstyle sobre el paquete etl/, el número de funciones públicas sin docstring completo debe ser cero.],
  prioridad: [Media],
  modulo: [Pipeline completo],
  estado: [Parcial: los módulos tienen docstring de módulo y de las funciones públicas principales.],
  fecha: [],
)

=== Portabilidad

#reqTable(
  id: [RNF-PORT-001],
  tipo: [No Funcional -- Portabilidad],
  cu: [--],
  descripcion: [El pipeline debe ejecutarse sin modificaciones en los sistemas operativos Ubuntu 22.04, macOS 13+ y Windows 10+, usando Python 3.11 y SUMO
  1.19 instalados en el sistema. La instalación de dependencias debe realizarse únicamente con #text(fill: olive)[pip install -r] #text(fill:
  gray)[requirements.txt].],
  razon: [Los cuatro integrantes del equipo trabajan en sistemas operativos distintos. El pipeline debe funcionar en todos ellos sin configuraciones
  especiales.],
  criterio: [El pipeline de CI de GitHub Actions debe incluir jobs para Ubuntu y Windows. Ambos jobs deben completarse exitosamente en cada commit a la
  rama principal.],
  prioridad: [Alta],
  modulo: [Pipeline completo],
  estado: [Parcial: probado en Windows 11; el CI solo corre las pruebas de la raíz.],
  fecha: [],
)

#reqTable(
  id: [RNF-PORT-002],
  tipo: [No Funcional -- Portabilidad],
  cu: [--],
  descripcion: [Todas las dependencias de Python del pipeline deben estar especificadas en el archivo requirements.txt con versiones exactas (pinned), de
  forma que #text(fill: olive)[pip install -r] #text(fill: gray)[requirements.txt] produzca un entorno idéntico en cualquier máquina.],
  razon: [Sin versiones exactas, actualizaciones de bibliotecas como pandas o geopandas pueden romper el pipeline silenciosamente entre ejecuciones de
  distintos integrantes.],
  criterio: [Todas las entradas de requirements.txt deben seguir el formato biblioteca==X.Y.Z. La presencia de rangos ($>=$, #sym.tilde.basic$=$) debe ser detectada y
  reportada por el CI como advertencia.],
  prioridad: [Media],
  modulo: [Configuración del entorno],
  estado: [Parcial: `simulation-service/pyproject.toml` fija `traci==1.27.1`; el resto usa rangos.],
  fecha: [],
)

=== Reproducibilidad

#reqTable(
  id: [RNF-REP-001],
  tipo: [No Funcional -- Reproducibilidad],
  cu: [CU-01 a CU-06],
  descripcion: [Dado el mismo conjunto de archivos de entrada (encuesta XLSX, dump OSM, aforos HMD) y el mismo archivo de configuración YAML, dos
  ejecuciones consecutivas del pipeline deben producir artefactos de salida bit-a-bit idénticos, sin importar en qué máquina o en qué momento se
  ejecuten.],
  razon: [La reproducibilidad es un requisito fundamental del proyecto. Los resultados publicados en el informe final deben poder ser verificados.],
  criterio: [Ejecutado el pipeline dos veces con los mismos inputs, el hash SHA-256 de cada archivo de salida debe ser idéntico entre ambas ejecuciones.
  Verificable con el script scripts/verify_reproducibility.py incluido en el repositorio.],
  prioridad: [Alta],
  modulo: [`simulation-service/src/etl/precalculadas.py`],
  estado: [Implementado para las precalculadas: gzip con `mtime=0` y hash SHA-256 de los insumos en `meta.json`.],
  fecha: [],
)

=== Observabilidad

#reqTable(
  id: [RNF-OBS-001],
  tipo: [No Funcional -- Observabilidad],
  cu: [CU-01 a CU-06],
  descripcion: [El pipeline debe reportar el progreso de cada fase en la consola con una barra de progreso o mensajes de estado al menos cada 30 segundos
  durante operaciones que tomen más de un minuto, indicando la fase actual, el número de registros procesados y el tiempo transcurrido.],
  razon: [Una ejecución de hasta 4 horas sin retroalimentación visual hace imposible distinguir si el pipeline está procesando lentamente o si se ha
  colgado.],
  criterio: [Durante la ejecución de F2 con el dataset completo, el usuario debe ver al menos un mensaje de progreso en consola por cada minuto de
  ejecución.],
  prioridad: [Media],
  modulo: [`simulation-service/src/api/jobs.py`, `etl/sumo/proceso.py`],
  estado: [Implementado: avance real por etapa (duarouter por último `depart`, SUMO por TraCI) visible en el visor.],
  fecha: [],
)

=== Usabilidad

#reqTable(
  id: [RNF-USA-001],
  tipo: [No Funcional -- Usabilidad],
  cu: [CU-07 a CU-12],
  descripcion: [Toda la interacción del usuario final debe hacerse desde el visor web en español, sin editar archivos XML ni usar la línea de comandos.
  Cada operación de más de 2 s (corrida, descarga, preparación de la comparación 3D) debe mostrar su avance o la etapa en curso, y los errores deben
  explicarse con un mensaje legible.],
  razon: [El usuario objetivo (planificador de movilidad) no conoce SUMO ni Python.],
  criterio: [Prueba de usuario con el director: lanzar una corrida, abrir una intersección y una comparación 3D sin asistencia del equipo.],
  prioridad: [Alta],
  modulo: [`kepler/src/`],
  estado: [Implementado; pendiente la prueba de usuario.],
  version: "2.0",
  fecha: []
)

#reqTable(
  id: [RNF-USA-002],
  tipo: [No Funcional -- Usabilidad],
  cu: [CU-07 a CU-12],
  descripcion: [El visor debe ofrecer un tema claro (por defecto) y uno oscuro con un botón, recordado entre visitas. Los textos para el usuario final deben
  evitar la jerga de SUMO: las cadenas de estado, ids de edges, semillas y tipos de programa solo aparecen en "Opciones avanzadas", y cada métrica
  lleva una explicación corta.],
  razon: [Un perfil directivo abandona una herramienta que le habla en códigos.],
  criterio: [Recorrido con Chrome sin interfaz: el tema cambia mapa base, paneles y capas; ninguna pantalla principal muestra ids de SUMO.],
  prioridad: [Media],
  modulo: [`kepler/src/App.jsx`, `index.css`, `FichaInterseccion.jsx`, `TablaComparacion.jsx`, `PanelCierres.jsx`],
  estado: [Implementado.],
  version: "2.2",
  fecha: []
)

== Requerimientos de la Base de Datos

El almacenamiento de los datos a manejar tiene el siguiente formatos:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Fase*], [*Formato*], [*Descripción*]),
    [F1 -- Ingestión], [Parquet], [Datos limpios de la encuesta con factor de expansión aplicado. Permite lectura parcial y compresión eficiente para
    #{sym.tilde.basic}500K registros.],
    [F2 -- Matrices O/D], [.od], [Formato nativo de SUMO para matrices TAZ. Texto plano estructurado según documentación oficial de SUMO 1.19.],
    [F3 -- Red vial], [.net.xml], [Formato XML nativo de SUMO generado por netconvert. Contiene nodos, aristas, velocidades y prioridades.],
    [F3 -- Zonas TAZ], [.taz.xml], [Formato XML nativo de SUMO. Lista de zonas con sus nodos de red asociados.],
    [F4 -- Tipos vehículo], [.vtype.xml],[Formato XML nativo de SUMO. Parámetros físicos y de comportamiento por modo de transporte.],
    [F4 -- Rutas], [.rou.xml], [Formato XML nativo de SUMO generado por duarouter. Contiene viajes y rutas asignadas.],
    [F5 -- Validación], [CSV], [Tabla de resultados GEH por punto de aforo. Columnas: punto_aforo, volumen_simulado, volumen_real, GEH.],
    [Transversal], [JSON], [Archivos de checkpoint por fase. Contienen el estado de ejecución para permitir reanudación parcial.],
    [Corridas (v2.0)], [`runs/<id>/`], [Trips, rutas, salidas de SUMO, `estado.json` y trips de kepler de cada corrida lanzada desde la API. No se
    versiona.],
    [Precalculadas (v2.0)], [`.geojson.gz` + JSON], [`precalculadas/<preset>/`: trips comprimidos, volúmenes por edge y metadatos con el hash de los
    insumos. Se versiona.],
    [Zonas y comparaciones 3D (v2.0)], [`.net.xml`, `.rou.xml`, `.trips.xml`], [`runs/zona-*` y `runs/sem-*`: red recortada, variante con el semáforo
    propuesto, demanda real recortada y tráfico de fondo. Se borran al cerrar la comparación.],
    [Cachés (v2.0)], [JSON], [`cache/semaforos.json` (catálogo de intersecciones) y `volumenes.json` por corrida; se invalidan por fecha y tamaño del
    archivo de origen.],
  ),
  caption: [Tipos de datos almacenados por el pipeline.]
) <tabDatos>

No se requiere indexación, uso de llaves primarias ni manejo de transacciones concurrentes, dado que el pipeline es un proceso secuencial monousuario. Las
consultas sobre los datos intermedios se realizan mediante pandas y geopandas directamente sobre los archivos en disco.

]
