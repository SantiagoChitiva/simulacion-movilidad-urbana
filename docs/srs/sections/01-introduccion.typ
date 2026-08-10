// @brief: especificacion de la seccion introduccion y sus subsecciones correspondientes

#let introduccion(info) = [

#align(center)[= Introduccion]

== Propósito

El presente documento constituye la Especificación de Requisitos de Software (SRS) del proyecto *#info.nombreProyecto*, desarrollado para la materia
proyecto de grado.

El propósito de este SRS es definir de manera precisa y verificable los requerimientos funcionales y no funcionales del sistema, de forma que sirva como
contrato técnico entre el equipo de desarrollo y el director del proyecto. El documento describe qué debe hacer el sistema, bajo qué restricciones debe
operar y cómo se verificará su correcto funcionamiento.

La audiencia de este documento incluye:

- *Equipo de desarrollo:* como referencia central para la implementación, las pruebas
  y la toma de decisiones técnicas a lo largo del ciclo de vida del proyecto.
- *Director del proyecto (Ing. Andrés Calderón Romero):* como revisor y aprobador de los
  requerimientos antes de la fase de construcción.
- *Jurados evaluadores:* como insumo para la evaluación académica del proyecto de grado.
- *Investigadores y analistas de movilidad:* potenciales usuarios del sistema en futuras
  iteraciones del producto.

El alcance del documento cubre la versión 1.0 del módulo, cuyo caso de validación está delimitado
a la localidad de Usaquén en Bogotá, Colombia.

== Alcance

El producto de software especificado en este documento es un módulo de procesamiento de datos que automatiza la transformación de fuentes de datos de
movilidad urbana disponibles para Bogotá en archivos de entrada válidos para el simulador de tráfico SUMO (Simulation of Urban MObility).

*Nombre del producto:* \<nombre del producto\>

*Funcionalidades principales que incluirá el sistema:*

- Ingesta y limpieza de la Encuesta de Movilidad de Bogotá 2023 y de los aforos vehiculares en Hora de Máxima Demanda (HMD).
- Descarga y procesamiento de la red vial de Usaquén desde OpenStreetMap mediante osmium y netconvert, generando el archivo `.net.xml` requerido por SUMO.
- Construcción de zonas de análisis de tráfico (TAZ) a partir de las Unidades de Planeamiento Zonal (UPZ) de Usaquén, generando el archivo `.taz.xml`.
- Producción de archivos de rutas (`.rou.xml`) y tipos de vehículo (`.vtype.xml`) compatibles con duarouter y SUMO.
- Variación paramétrica de las configuraciones de entrada para la generación de escenarios hipotéticos de movilidad.
- Validación estadística de los resultados mediante el estadístico GEH y RMSE, contrastando los volúmenes simulados con los aforos reales.
- Módulo web que permite visualizar de forma interactiva los resultados producidos por SUMO (métricas de congestión, tiempos de viaje, flujos vehiculares
  por segmento) y parametrizar nuevas simulaciones desde una interfaz gráfica, sin necesidad de editar archivos XML ni interactuar con la línea de
  comandos.

*Utilidad y objetivos del producto:*

El módulo busca eliminar la barrera técnica que impide a planificadores y analistas de movilidad urbana utilizar SUMO con datos reales de Bogotá. Al
automatizar el pipeline de extremo a extremo, se reduce de horas a minutos el tiempo necesario para preparar una simulación, permitiendo explorar
escenarios hipotéticos como cambios en infraestructura vial o en estrategias de control de tráfico sin intervención manual en la preparación de datos.

*Relación con la estrategia organizacional:*

El producto está alineado con las necesidades de organizaciones como la Secretaría Distrital de Movilidad de Bogotá, o usuarios como ingenieros de
movilidad e infraestructura, los cuales requieren de herramientas sencillas y fiables en cuanto a toma de decisiones frente a implementación de
estrategias o políticas de movilidad en Bogotá. Según el TomTom Traffic Index 2025, Bogotá ocupa el séptimo lugar global en congestión vehicular, con
velocidades promedio en horas pico que apenas superan los 15 km/h, lo que evidencia la urgencia de contar con herramientas de análisis y simulación
accesibles.

*Funcionalidades excluidas de esta versión:*

- Integración en tiempo real con APIs de tráfico comerciales.
- Despliegue en sistemas de producción institucionales.
- Calibración del modelo para localidades distintas a Usaquén.

== Definiciones, Acrónimos y Abreviaciones

A continuación se presentan los términos clave utilizados a lo largo del documento. Este glosario complementa y extiende el definido en el documento SPMP
del proyecto.

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Término / Acrónimo*], [*Definición*]),

    [*SUMO*], [Simulation of Urban MObility. Simulador de tráfico microscópico de código abierto desarrollado por el DLR (German Aerospace Center).
    Permite modelar sistemas de tráfico intermodal incluyendo vehículos, transporte público y peatones.],

    [*SRS*],  [Software Requirements Specification. Especificación de Requisitos del Software. Documento que describe de forma completa el comportamiento
    del sistema a desarrollar.],

    [*SPMP*], [Software Project Management Plan. Plan de Administración del Proyecto de Software. Documento que define la planificación, organización y
    control del proyecto.],

    [*ETL*], [Extract, Transform, Load. Pipeline de procesamiento de datos estructurado en tres etapas: extracción desde fuentes originales,
    transformación al formato requerido y carga en el sistema destino.],

    [*O/D*], [Matriz Origen-Destino. Estructura de datos que cuantifica el número de viajes realizados entre pares de zonas geográficas en un período de
    tiempo definido.],

    [*TAZ*], [Traffic Analysis Zone. Unidad espacial básica del modelo de demanda de transporte. En este proyecto corresponde a las UPZ de la localidad de
    Usaquén.],

    [*UPZ*], [Unidad de Planeamiento Zonal. División administrativa de Bogotá utilizada como unidad de análisis geográfico (TAZ) en este proyecto.],

    [*HMD*], [Hora de Máxima Demanda. Período del día con mayor volumen vehicular, típicamente en jornada AM (mañana) o PM (tarde).],

    [*GEH*], [Geoffrey E. Havers. Estadístico de validación de modelos de tráfico. Un valor GEH $<$ 5 indica una buena calibración del modelo.],

    [*RMSE*], [Root Mean Square Error. Raíz del Error Cuadrático Medio. Métrica de precisión numérica utilizada para cuantificar la diferencia entre
    valores simulados y observados.],

    [*OSM*], [OpenStreetMap. Proyecto colaborativo de cartografía en línea que provee datos geoespaciales de código abierto. Fuente de la red vial
    base del modelo.],

    [*TraCI*], [Traffic Control Interface. API oficial de SUMO para controlar y consultar el estado de una simulación en tiempo real mediante Python u
    otros lenguajes.],

    [*netconvert*], [Herramienta del ecosistema SUMO que convierte redes viales desde formatos externos (OSM, VISUM, etc.) al formato nativo `.net.xml` de
    SUMO.],

    [*duarouter*], [Herramienta del ecosistema SUMO que asigna rutas óptimas a los viajes definidos en una matriz O/D, generando el archivo `.rou.xml`.],

    [*CRISP-DM*], [Cross-Industry Standard Process for Data Mining. Metodología iterativa de ciencia de datos adoptada para las fases 1 y 2 del
    proyecto.],

    [*Scrum*], [Marco ágil de desarrollo de software basado en sprints iterativos cortos. Adoptado a partir de la Fase 3 del proyecto.],

    [*PEP 8*], [Guía de estilo para código Python de la Python Software Foundation. Estándar de codificación obligatorio en el proyecto.],

    [*API*], [Application Programming Interface. Interfaz de programación que permite la comunicación entre componentes de software.],

    [*DLR*], [German Aerospace Center (Deutsches Zentrum für Luft- und Raumfahrt). Organización responsable del desarrollo principal de SUMO.],

    [*WBS*], [Work Breakdown Structure. Estructura jerárquica de descomposición de las tareas del proyecto.],

    [*CI*], [Continuous Integration. Integración Continua. Práctica de automatizar la ejecución de pruebas en cada commit al repositorio, implementada
    mediante GitHub Actions.],

    [*REST API*], [Representational State Transfer Application Programming Interface. Estilo de arquitectura para servicios web utilizado por el módulo
    web para exponer los resultados de SUMO al frontend.],

    [*Frontend*], [Capa de presentación del módulo web. Interfaz gráfica accesible desde el navegador que permite visualizar resultados de simulación y
    configurar nuevos escenarios sin interacción directa con la línea de comandos.]
  ),
  caption: [Definiciones, acrónimos y abreviaciones del proyecto.]
) <tabAcronimos>

== Referencias

#set enum(numbering: "[1]")

+ IEEE Std 830-1998, _IEEE Recommended Practice for Software Requirements Specifications_, IEEE, 1998.
+ IEEE Std 1058-1998, _IEEE Standard for Software Project Management Plans_, IEEE, 1998.
+ P. A. Lopez et al., "Microscopic Traffic Simulation using SUMO," in _Proc. 21st IEEE International Conference on Intelligent Transportation Systems
  (ITSC)_, Maui, HI, USA, 2018, pp. 2575–2582. DOI: 10.1109/ITSC.2018.8569938.
+ Secretaría Distrital de Movilidad de Bogotá, _Encuesta de Movilidad de Bogotá 2023_, Alcaldía Mayor de Bogotá, 2023. [En línea]. Disponible en:
  https://www.movilidadbogota.gov.co
+ TomTom International BV, _TomTom Traffic Index 2025_, 2025. [En línea]. Disponible en: https://www.tomtom.com/traffic-index/
+ OpenStreetMap contributors, _OpenStreetMap_, 2024. [En línea]. Disponible en: https://www.openstreetmap.org
+ Eclipse Foundation, _Eclipse SUMO — Simulation of Urban MObility: User Documentation_, versión 1.19, 2023. [En línea]. Disponible en:
  https://sumo.dlr.de/docs/
+ G. Van Rossum y el equipo de Python, _PEP 8 — Style Guide for Python Code_, Python Software Foundation, 2001. [En línea]. Disponible en:
  https://peps.python.org/pep-0008/

== Apreciación Global

El presente documento está organizado en seis secciones principales que cubren de forma progresiva todos los aspectos del sistema especificado:

La *Sección 1 -- Introducción* (actual) presenta el propósito, el alcance y los términos fundamentales del documento, proporcionando al lector el marco
conceptual necesario para interpretar correctamente el resto del contenido.

La *Sección 2 -- Descripción Global* describe el sistema desde una perspectiva de alto nivel: su contexto de operación, las interfaces con sistemas
externos (SUMO, OSM, encuestas de movilidad), los tipos de usuarios que interactuarán con él y las restricciones generales de diseño e implementación.

La *Sección 3 -- Requerimientos Específicos* constituye el núcleo técnico del SRS. En ella se detallan los requerimientos funcionales organizados por
capacidades del pipeline ETL, los requerimientos no funcionales (rendimiento, confiabilidad, mantenibilidad, portabilidad) y las interfaces del sistema.

La *Sección 4 -- Proceso de Ingeniería de Requerimientos* documenta la metodología utilizada para elicitar, analizar, especificar y validar los
requerimientos, describiendo las técnicas empleadas y los artefactos producidos durante este proceso.

La *Sección 5 -- Proceso de Verificación* describe el plan de validación del sistema, especificando los criterios de aceptación, las métricas de calidad
(GEH, RMSE) y los casos de prueba asociados a los requerimientos.

La *Sección 6 -- Anexos* incluye material complementario como diagramas de flujo del pipeline, ejemplos de los formatos de entrada y salida, y trazabilidad
entre requerimientos y casos de prueba.

]

