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
  fecha: ""
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

El proyecto se basa en un sistema de línea de comandos (CLI) sin interfaz gráfica en su versión 1.0. La interacción con el usuario se realiza
exclusivamente a través de:

- *Línea de comandos (CLI):* el usuario invoca el pipeline mediante un comando Python con argumentos que especifican la fuente de datos, el período de
  análisis (AM/PM/nocturno) y los parámetros de escenario. Ejemplo:
  #block(
    fill: luma(235),
    inset: 8pt,
    radius: 4pt,
    width: 100%,
  )[
    `python pipeline.py --encuesta datos/encuesta2023.xlsx --periodo AM --localidad Usaquen`
  ]
- *Archivo de configuración YAML:* los parámetros avanzados de simulación (velocidades por
  tipo de vía, factores de expansión, umbrales de validación GEH) se definen en un archivo
  `config.yaml` que el usuario edita antes de ejecutar el pipeline.
- *Logs de consola y archivo:* el sistema imprime el progreso de cada fase en consola y escribe
  un archivo `pipeline.log` con el detalle de registros procesados, descartados y métricas de
  validación.
- *Archivos de salida:* los artefactos generados (`.net.xml`, `.taz.xml`, `.od`, `.rou.xml`,
  `.vtype.xml`) se depositan en un directorio de salida configurable por el usuario.

No se requiere resolución de pantalla específica ni dispositivos de entrada distintos al teclado.

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
    [Python], [3.11], [Lenguaje de implementación del pipeline ETL],
    [SUMO], [1.19], [Motor de simulación; proveedor de netconvert y duarouter],
    [pandas], [2.0], [Procesamiento de datos tabulares de la encuesta],
    [geopandas], [0.14], [Procesamiento de datos geoespaciales (TAZ, OSM)],
    [osmium-tool], [1.16], [Extracción del polígono de Usaquén desde el dump OSM],
    [Ubuntu / macOS / Windows], [22.04 / 13 / 10], [Sistemas operativos soportados],
    [Git], [2.40], [Control de versiones del código fuente],
    [pytest], [7.0], [Ejecución de pruebas unitarias e integración],
    [GitHub Actions], [--], [Integración continua (CI) en cada commit],
  ),
  caption: [Interfaces de software del sistema.]
) <tabSoftware>

=== Interfaces de Comunicaciones

El pipeline no implementa comunicación en red durante su ejecución principal. La única comunicación de red ocurre en la fase de descarga de datos OSM
(RF-002), que utiliza el protocolo HTTPS sobre el puerto 443 hacia los servidores de OpenStreetMap (`planet.openstreetmap.org` o la API Overpass). Una vez
descargada la red vial, todas las fases restantes del pipeline operan de forma completamente *offline*.

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
  modulo: [Módulo de Ingestión (etl/ingestion.py)],
  fecha: []
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
  modulo: [Módulo de Ingestión (etl/ingestion.py)],
  fecha: []
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
  modulo: [Módulo de Ingestión (etl/ingestion.py)],
  fecha: []
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
  modulo: [Módulo de Ingestión (etl/ingestion.py)],
  fecha: []
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
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  fecha: []
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
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  fecha: []
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
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  fecha: []
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
  modulo: [Módulo de Construcción O/D (etl/od_builder.py)],
  fecha: []
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
  modulo: [Módulo de Red (etl/network.py)],
  fecha: []
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
  modulo: [Módulo de Red (etl/network.py)],
  fecha: []
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
  modulo: [Módulo de Simulación (etl/simulation.py)],
  fecha: []
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
  modulo: [Módulo de Simulación (etl/simulation.py)],
  fecha: []
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
  modulo: [Módulo de Configuración (etl/config.py)],
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
  modulo: [Módulo Web (web/api.py + web/frontend/)],
  fecha: []
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
  modulo: [Backend web (web/api.py)],
  fecha: []
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
  modulo: [Módulo Web (web/frontend/ + web/api.py)],
  fecha: []
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
  modulo: [Frontend web (web/frontend/)],
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
  fecha: []
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
  modulo: [Módulo transversal (etl/logger.py)],
  fecha: []
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
  fecha: []
)

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
  fecha: []
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
- *Arquitectura del módulo web:* el módulo web debe seguir una arquitectura de dos capas: backend REST (Python) y frontend accesible desde navegador. El
  backend debe reutilizar el código del pipeline ETL existente sin duplicar lógica de procesamiento.

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
  modulo: [Módulo de Ingestión (etl/ingestion.py)],
  fecha: []
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
  modulo: [Módulo transversal (etl/checkpoint.py)],
  fecha: []
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
  fecha: []
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
  fecha: []
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
  fecha: []
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
  fecha: []
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
  modulo: [Pipeline completo],
  fecha: []
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
  modulo: [Módulo transversal (etl/logger.py)],
  fecha: [],
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
  ),
  caption: [Tipos de datos almacenados por el pipeline.]
) <tabDatos>

No se requiere indexación, uso de llaves primarias ni manejo de transacciones concurrentes, dado que el pipeline es un proceso secuencial monousuario. Las
consultas sobre los datos intermedios se realizan mediante pandas y geopandas directamente sobre los archivos en disco.

]
