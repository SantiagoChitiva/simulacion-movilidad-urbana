// @brief: Propuesta para Proyecto de Grado (VFP) -- formato del Departamento de Ingeniería de Sistemas, PUJ
// Compilar: typst compile vfp.typ  (o desde Python: typst.compile("vfp.typ", root="."))

#let titulo = [Generación de Escenarios de Movilidad Urbana para la Toma de Decisiones en Localidades de Bogotá]
#let version = "2.0"
#let fecha = "13/10/2026"

#set document(title: "Propuesta para Proyecto de Grado -- Generación de Escenarios de Movilidad Urbana")
#set text(lang: "es", size: 11pt)
#set par(justify: true, leading: 0.75em)
#set page(
  paper: "us-letter",
  margin: (x: 2.5cm, top: 2.8cm, bottom: 2.5cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 9pt, style: "italic")
      Pontificia Universidad Javeriana #h(1fr) Propuesta para Trabajo de Grado
      #line(length: 100%, stroke: 0.4pt)
    ]
  },
  footer: context {
    if counter(page).get().first() > 1 [
      #set text(size: 9pt)
      #h(1fr) Página #(counter(page).get().first() - 1)
    ]
  },
)
#set heading(numbering: "1.1.1")
#show heading.where(level: 1): it => { pagebreak(weak: true); it }
#show figure.where(kind: table): set figure(supplement: [Tabla])
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: table): set block(breakable: true)
#set table(stroke: 0.5pt + luma(140), inset: 5pt, align: left)
#show table: set par(justify: false)
#show table.cell.where(y: 0): set text(weight: "bold")

// ───────────────────────────────────────────── portada (formato de la propuesta)

#let campo(t) = text(weight: "bold", size: 10pt)[#t]
#let estudiante(nombre, doc, cel, correo) = [
  #text(weight: "bold")[#nombre] \
  #table(
    columns: (auto, auto, auto, 1fr), stroke: none, inset: 2pt,
    [#campo[Documento]], [#campo[Celular]], [#campo[Teléfono fijo]], [#campo[Correo Javeriano]],
    [#doc], [#cel], [N/A], [#correo],
  )
]

#grid(columns: (1fr, auto), align: (left + horizon, right + horizon),
  image("figures/logo_javeriana.png", height: 1.6cm), text(size: 13pt)[Ingeniería de Sistemas])
#v(0.6cm)
#align(center, text(size: 15pt, weight: "bold")[PROPUESTA PARA PROYECTO DE GRADO])
#v(0.2cm)
#set text(size: 10pt)
#table(
  columns: (1fr), stroke: 0.8pt, inset: 7pt,
  [#campo[TÍTULO] \ #align(center)[#titulo]],
  [#campo[OBJETIVO GENERAL] \ Diseñar un sistema para la automatización de escenarios de simulación de movilidad urbana en Bogotá, que facilite el
  análisis y la evaluación de políticas de movilidad a partir de datos de transporte.],
  [#campo[ESTUDIANTE(S)] \
    #estudiante("Samuel Esteban Campos", "cc. 1145924065", "315-773-7425", "samuelcampos@javeriana.edu.co")
    #estudiante("Erick Salazar Suarez", "cc. 1032677069", "319-782-7251", "ericksalazar@javeriana.edu.co")
    #estudiante("Santiago Chitiva Contreras", "cc. 1093592516", "322-937-8026", "schitiva@javeriana.edu.co")
    #estudiante("Felipe Andrés Garrido Flores", "cc. 1000461910", "305-310-4606", "f-garrido@javeriana.edu.co")],
  [#campo[DIRECTOR] \
    #text(weight: "bold")[Ing. Andrés Oswaldo Calderon Romero] \
    #table(
      columns: (auto, auto, auto, auto, 1fr), stroke: none, inset: 2pt,
      [#campo[Documento]], [#campo[Celular]], [#campo[Teléfono fijo]], [#campo[Correo Javeriano]], [#campo[Empresa donde trabaja y cargo]],
      [C.C. 75.088.955], [323-338-5956], [320 8320 Ext. 5275 - 5276], [andrescalderonr\@javeriana.edu.co],
      [Pontificia Universidad Javeriana; Profesor Departamento de Sistemas],
    )],
)
#align(right)[Versión original: 6/2/2026 · Versión #version (actualización de alcance): #fecha]
#set text(size: 11pt)

#pagebreak()
#outline(title: [Contenido], depth: 3)
#pagebreak()

// ───────────────────────────────────────────── 1. Visión global

= Visión global

== Antecedentes, problema y solución propuesta

=== Descripción de la problemática u oportunidad

La movilidad urbana representa uno de los principales retos para las grandes ciudades contemporáneas, debido al crecimiento poblacional, el aumento
del parque automotor y la complejidad de los sistemas de transporte. En el caso de Bogotá, este desafío es particularmente evidente, ya que la ciudad
enfrenta altos niveles de congestión vehicular y una creciente demanda de desplazamientos diarios por parte de millones de ciudadanos.

Diversos indicadores evidencian la magnitud del problema. De acuerdo con el TomTom Traffic Index, Bogotá se ubicó en 2025 como la séptima ciudad con
mayor congestión vehicular a nivel mundial, registrando un nivel de congestión del 69,9 % y un incremento de 7,7 puntos porcentuales respecto al año
anterior. Este fenómeno implica que los ciudadanos pueden perder en promedio hasta 153 horas al año en tráfico durante horas pico, lo que equivale a
más de seis días completos atrapados en congestiones vehiculares @eltiempo. Asimismo, la velocidad promedio de circulación durante los periodos de
mayor demanda apenas supera los 15 km/h, lo que refleja las dificultades estructurales del sistema vial para absorber el volumen de vehículos en
circulación @portafolio2025.

El impacto de esta situación trasciende el ámbito del transporte y afecta directamente la calidad de vida de los habitantes, la productividad
económica y la eficiencia del funcionamiento urbano. En algunos casos, recorrer distancias relativamente cortas dentro de la ciudad puede tomar tiempos
considerablemente altos; por ejemplo, trayectos de apenas cinco kilómetros pueden tardar hasta 40 minutos en horas pico, mientras que recorridos de diez
kilómetros superan los 30 minutos en promedio @infobae. A esto se suma el hecho de que cerca del 70 % de la red vial de la ciudad presenta niveles de
congestión diaria, lo que evidencia la dimensión estructural del problema de movilidad en la capital colombiana.

Paralelamente, Bogotá cuenta con sistemas de transporte de gran escala y con una alta participación ciudadana en los desplazamientos diarios. Por
ejemplo, el sistema de transporte masivo TransMilenio registra más de cuatro millones de viajes diarios, consolidándose como uno de los componentes
fundamentales del sistema de movilidad urbana de la ciudad @alcaldia. En este contexto, las encuestas de movilidad realizadas por la Secretaría
Distrital de Movilidad representan una fuente de información fundamental para comprender cómo se desplazan los ciudadanos dentro de la ciudad.

Estas encuestas permiten caracterizar los patrones de movilidad de la población en un momento determinado, identificando aspectos como los orígenes y
destinos de los viajes, los modos de transporte utilizados, los horarios de desplazamiento y diversas variables socioeconómicas asociadas a los usuarios
del sistema de transporte @portafolio2023. Gracias a esta información es posible describir y analizar el comportamiento de la movilidad urbana, así como
identificar tendencias y dinámicas relevantes para la planificación del sistema de transporte.

En este sentido, la planificación, el diseño y la evaluación de infraestructura y políticas de movilidad requieren herramientas que permitan analizar
de manera rigurosa el comportamiento del tráfico y los patrones de desplazamiento de la población. Las entidades responsables de la planificación del
transporte, como la Secretaría Distrital de Movilidad, así como ingenieros y analistas del sector, necesitan herramientas que les permitan evaluar
diferentes escenarios de movilidad antes de implementar cambios en la infraestructura o en las políticas de transporte.

Dentro de este contexto, los sistemas de simulación de tráfico urbano se han consolidado como herramientas relevantes para analizar el impacto de
diferentes decisiones de planificación. Entre estas herramientas destaca SUMO (Simulation of Urban MObility), un simulador de tráfico de código abierto
ampliamente utilizado en investigación y desarrollo para modelar el comportamiento de vehículos, peatones, infraestructura vial y sistemas de control
del tráfico en entornos urbanos complejos.

En este contexto, surge una oportunidad para desarrollar herramientas que permitan aprovechar de manera más efectiva la información proveniente de
fuentes de datos como las encuestas de movilidad, integrándolas con sistemas de simulación que faciliten el análisis de diferentes escenarios de
movilidad. De esta manera, sería posible apoyar los procesos de planificación y toma de decisiones mediante herramientas tecnológicas que permitan
explorar y evaluar alternativas antes de su implementación en el entorno urbano real.

=== Formulación del problema

A pesar de la disponibilidad de herramientas de simulación de movilidad urbana como SUMO, su utilización en procesos de análisis y planificación
presenta diversas limitaciones prácticas para los usuarios del área de movilidad.

Por una parte, la configuración y ejecución de simulaciones en SUMO requiere la preparación manual de diferentes archivos de configuración,
generalmente en formato XML, así como el uso de múltiples utilidades que forman parte del ecosistema del simulador. Muchas de estas herramientas se
ejecutan mediante interfaces de línea de comandos, lo que puede resultar poco intuitivo para usuarios que no poseen experiencia previa en este tipo de
entornos. Asimismo, la interfaz gráfica del simulador no siempre cumple con criterios de usabilidad comunes en el diseño de software moderno, lo que
puede dificultar la configuración de escenarios y la exploración de diferentes parámetros de simulación.

Por otra parte, aunque las encuestas de movilidad constituyen una fuente de información valiosa para describir y analizar los patrones de
desplazamiento de la población, actualmente no existe una herramienta que permita transformar de manera directa estos datos en insumos compatibles con
SUMO para la generación de escenarios de simulación. Como consecuencia, los analistas deben realizar procesos manuales de limpieza, transformación y
estructuración de la información antes de poder utilizarla en simulaciones, lo que incrementa el tiempo, la complejidad técnica y las posibilidades de
error en el proceso.

La pregunta que surge de este conjunto de problemas es: _¿Cómo utilizar datos que describen el comportamiento de la movilidad urbana en Bogotá,
apoyándose en herramientas de simulación como SUMO, para generar de manera automatizada escenarios de simulación y reportes comprensibles que faciliten
el análisis y la toma de decisiones por parte de entidades encargadas de la planificación y gestión de la movilidad?_

=== Propuesta de solución

Debido a las limitaciones identificadas, los profesionales responsables del análisis y la planificación de la movilidad urbana no disponen actualmente
de herramientas que permitan integrar de manera sencilla datos reales de movilidad con plataformas de simulación que faciliten el análisis de
diferentes escenarios antes de su implementación en la infraestructura urbana.

Con el fin de abordar esta problemática, se propone el desarrollo de un módulo de procesamiento de datos que permita automatizar la transformación de
información proveniente de encuestas de movilidad en insumos compatibles con el simulador SUMO, eliminando la necesidad de intervención manual en cada
etapa del proceso.

El módulo de procesamiento de datos es el componente central de la solución. Se encargará de transformar la información proveniente de encuestas de
movilidad en estructuras de datos compatibles con los formatos requeridos por SUMO. Para esto, realizará tareas de limpieza, organización y
transformación de los datos, generando insumos como matrices origen–destino (O/D), definiciones de rutas y archivos de configuración en formato XML
necesarios para ejecutar las simulaciones dentro del entorno del simulador.

Complementando el módulo de procesamiento, se propone el desarrollo de un módulo web que actúa como interfaz de usuario del sistema. Este módulo
cumple dos funciones principales:
- permite visualizar de forma interactiva los resultados producidos por SUMO (incluyendo métricas de congestión, tiempos de viaje, flujos
  vehiculares y niveles de servicio por segmento de vía), de manera que los resultados sean comprensibles sin necesidad de interpretar directamente
  los archivos de salida del simulador;
- permite al usuario parametrizar y lanzar nuevas simulaciones desde la misma interfaz, definiendo variables como el período horario, los modos de
  transporte activos y las estrategias o políticas de movilidad a simular, sin necesidad de editar archivos XML manualmente.

*Ampliación (versión #version).* Para que el sistema apoye decisiones de control de tráfico, el módulo web incorpora dos herramientas:
- *Análisis de intersecciones:*
  - consulta de cada semáforo con sus volúmenes simulados por acceso;
  - edición de su programa o cálculo con el método de Webster, y comparación de programas;
  - priorización de los cruces sin semáforo donde podría justificarse instalar uno.
- *Simulador 3D comparativo:* para un cruce sin semáforo, el sistema prepara dos escenarios con la misma demanda (el cruce como está hoy y el mismo
  cruce con un semáforo propuesto), los simula a la par y los muestra lado a lado en 3D, con la red vial real y los edificios de la zona.
  - El usuario sigue en tercera persona a un vehículo o a un peatón y ve en pantalla su velocidad, la acción que toma, las decisiones posibles en el
    próximo cruce y un índice de riesgo calculado periódicamente.
  - Un minimapa 2D lo ubica en la ciudad.
  - El objetivo es hacer tangible el efecto de la intervención para quien toma la decisión.

Es importante precisar el rol que cumple SUMO dentro de la arquitectura del sistema propuesto. SUMO actúa como una caja negra al final del pipeline:
recibe como entrada los archivos de configuración generados por el módulo de procesamiento (redes viales, matrices O/D y archivos de rutas en formato
XML) y ejecuta la simulación internamente, produciendo archivos de salida con métricas del comportamiento del sistema simulado. El aporte de este
proyecto radica en automatizar y estructurar todo el proceso previo que hoy se realiza manualmente, dejando a SUMO como la herramienta de ejecución que
opera sobre insumos ya listos y validados. En el simulador 3D, SUMO se controla además en vivo mediante su API TraCI.

El alcance geográfico inicial del proyecto comprende la localidad de Usaquén como caso de estudio principal para el desarrollo y validación del sistema,
con el diseño orientado a soportar todas las localidades presentes en la encuesta de movilidad de Bogotá.

=== Justificación de la solución

Como se ha descrito en las secciones anteriores, el análisis de la movilidad urbana enfrenta diversas limitaciones relacionadas con la dificultad de
transformar datos reales de movilidad en escenarios de simulación, así como con la complejidad técnica asociada al uso de herramientas como SUMO. Estas
problemáticas evidencian la necesidad de contar con herramientas que permitan aprovechar de manera más efectiva la información disponible y facilitar su
utilización en procesos de análisis y planificación del transporte.

La justificación de la solución propuesta se apoya en el análisis comparativo de alternativas presentado en la sección 5.2 de este documento
(@tabAlternativas). Dicho análisis evalúa cuatro enfoques alternativos para el mismo problema (modelos analíticos y teoría de colas, machine learning
predictivo, APIs de datos en tiempo real, y el modelo clásico de cuatro pasos) frente a la propuesta de simulación con SUMO. El análisis demuestra que
ninguna de las alternativas satisface de forma simultánea los requerimientos centrales del proyecto: resolución microscópica del comportamiento
vehicular, capacidad de analizar escenarios hipotéticos, independencia de datos privados, multimodalidad integrada y costo accesible para investigación
académica.

En particular, la propuesta del proyecto (un pipeline de procesamiento de datos reales que genera insumos listos para simulación microscópica de
tráfico) es la única alternativa que combina datos propios y reproducibles, análisis a nivel de vehículo individual, evaluación de escenarios
hipotéticos, soporte multimodal completo y costo cero de herramientas. El desarrollo del módulo propuesto adquiere relevancia al abordar directamente
estas limitaciones mediante la automatización del proceso de generación de insumos para simulación, reduciendo la cantidad de tareas manuales y
simplificando el flujo de trabajo requerido para utilizar SUMO en contextos de planificación urbana.

== Descripción general del proyecto

=== Objetivo general

Diseñar e implementar un módulo de procesamiento de datos que automatice la transformación de fuentes de datos de movilidad disponibles para Bogotá en
archivos de entrada válidos para el simulador SUMO, con el fin de eliminar la intervención manual en la generación de redes viales, matrices
origen–destino y archivos de rutas, y facilitar así el análisis de movilidad urbana a entidades públicas, investigadores y consultores del sector
mediante una interfaz web que permita visualizar los resultados de las simulaciones y configurar nuevos escenarios de forma accesible.

=== Objetivos Específicos

- Analizar y comparar las fuentes de datos de movilidad disponibles para Bogotá (incluyendo los datos de la Encuesta de Movilidad 2023 y datasets
  complementarios como los mapas de densidad poblacional y movilidad del programa Data for Good de Meta) con el fin de determinar cuáles fuentes, o
  combinación de ellas, permiten construir matrices origen–destino suficientemente representativas para alimentar los escenarios de simulación,
  reconociendo las limitaciones de periodicidad y cobertura de cada fuente como parte del alcance del sistema.
- Desarrollar un módulo de procesamiento de datos que automatice la transformación de los registros de la encuesta en archivos de entrada válidos para
  SUMO, eliminando la necesidad de intervención manual en las etapas de generación de redes viales, matrices O/D y archivos de rutas.
- Validar el módulo generando los insumos de simulación para al menos una localidad representativa de Bogotá, verificando la coherencia de los
  archivos producidos frente a los patrones de movilidad reportados en la encuesta y ejecutando el escenario resultante en SUMO.
- Desarrollar un módulo web que permita visualizar de forma interactiva los resultados generados por SUMO y parametrizar nuevas simulaciones desde una
  interfaz gráfica, eliminando la necesidad de interacción directa con la línea de comandos o con archivos de configuración en formato XML.
- _(Versión #version)_ Incorporar al módulo web el análisis de intersecciones y un simulador 3D comparativo que permita evaluar la instalación de un
  semáforo en un cruce sin señalizar. El simulador muestra lado a lado el escenario actual y el escenario con el semáforo propuesto, con indicadores de
  fluidez y de seguridad (TTC, DRAC, PET) para los actores observados.

== Entregables, estándares utilizados y justificación

Los entregables formales del proyecto de grado están basados en estándares de ingeniería de software reconocidos internacionalmente. La selección y
combinación de estándares siguió el principio de completitud y consistencia, adaptando sus componentes a la naturaleza del proyecto: un pipeline de
procesamiento de datos orientado a la generación de insumos para simulación de tráfico (véase la @tabEntregables).

#figure(
  table(
    columns: (15%, 25%, 1fr),
    table.header([Entregable], [Estándares asociados], [Justificación]),
    [SPMP], [IEEE Std 1058-1998 (SPMP) \ ISO/IEC 12207:2008 \ BPMN 2.0], [El IEEE 1058 define la estructura estándar para planes de gestión de
    proyectos de software, cubriendo alcance, cronograma, recursos y riesgos. ISO/IEC 12207 complementa definiendo los procesos del ciclo de vida
    aplicables. BPMN 2.0 se usa para modelar los procesos internos del proyecto.],
    [SRS], [IEEE 830-1998 (SRS) \ ISO 29148:2011 \ UML v2.5.1], [Se utilizarán los estándares IEEE 830 y ISO/IEC/IEEE 29148 para el SRS, ya que el
    primero define una estructura clara para documentar requisitos, mientras el segundo asegura su calidad, consistencia y correcta gestión. Su uso
    conjunto permite contar con requisitos bien definidos y alineados con el desarrollo y las pruebas del sistema.],
    [SDD], [IEEE 1016-2009 (SDD) \ ISO/IEC/IEEE 42010 \ UML v2.5.1 \ C4 model], [IEEE 1016 establece el contenido mínimo para documentar
    decisiones de diseño arquitectónico. ISO/IEC/IEEE 42010 provee el marco conceptual para describir arquitecturas mediante vistas. C4 y UML para
    diagramar la arquitectura y UML para el diseño detallado, p. ej., Estructura (diagramas de clases), Comportamiento (diagramas de secuencia),
    Persistencia (diagramas Entidad-Relación).],
    [Plan de pruebas], [ISO/IEC/IEEE 29119-1:2022], [El plan de pruebas se basará en el estándar ISO/IEC/IEEE 29119, ya que define apartados clave
    como la planificación de pruebas, el diseño de casos, la ejecución, la gestión de defectos y la trazabilidad. Esto permite estructurar el proceso de
    pruebas, asegurar la cobertura de los requisitos y garantizar la calidad del sistema.],
    [Código fuente], [PEP 8 (código en Python) \ API TraCI (API de SUMO)], [El código fuente se desarrollará siguiendo la guía de estilo PEP 8 para
    Python, con el fin de asegurar legibilidad, consistencia y buenas prácticas en la escritura del código, facilitando su mantenimiento y
    colaboración. Asimismo, se utilizará la API TraCI de SUMO, la cual permite la interacción y control de simulaciones de tráfico en tiempo real,
    integrando la lógica del sistema con el entorno de simulación; en la versión #version es la base del simulador 3D comparativo.],
    [Informe final], [IEEE 1063-2001 \ ISO/IEC/IEEE 26512:2018], [El informe final se elaborará considerando el estándar IEEE 1063-2001, el cual
    define la estructura y contenido de la documentación orientada al usuario, incluyendo apartados como descripción del sistema, instrucciones de uso
    y guías operativas, asegurando que el producto sea comprensible y fácil de utilizar. Por su parte, el estándar ISO/IEC/IEEE 26512:2018 establece
    lineamientos para la creación y organización de documentación técnica más completa, abarcando aspectos como instalación, mantenimiento y soporte,
    garantizando consistencia, calidad y utilidad a lo largo del ciclo de vida del sistema.],
  ),
  caption: [Entregables, estándares asociados y justificación.],
) <tabEntregables>

== Cambios de alcance (versión #version)

Esta versión de la propuesta conserva el problema, la justificación, el objetivo general y el marco metodológico aprobados. Se actualizan el alcance y
las fases con lo construido hasta la fecha y lo que se planea desarrollar:

#figure(
  table(
    columns: (26%, 1fr, 17%),
    table.header([Cambio], [Descripción], [Estado]),
    [Demanda parametrizable], [Presets de transferencia modal (encuesta, más vehículos, más peatones, día sin carro), conteos por modo, semilla,
    estilos de conducción y cierres viales; simulaciones precalculadas de los presets.], [Implementado],
    [Visor web], [Mapa animado de los viajes por modo (kepler.gl), panel de parametrización, avance real y cancelación de corridas.], [Implementado],
    [Análisis de intersecciones], [Ficha de semáforos con volúmenes por acceso, edición de programas, Webster, recorte de zonas, comparación de
    programas y priorización de cruces sin semáforo.], [Implementado],
    [Simulador 3D comparativo], [Pantalla partida sin / con semáforo propuesto, red 3D y edificios reales, actor en tercera persona, HUD de velocidad,
    acción, decisiones y riesgo (TTC, DRAC, PET), minimapa 2D y selección de vías.], [Implementado],
    [Reporte de la comparación 3D y programa editable del semáforo propuesto], [Exportar las métricas de ambos escenarios y ajustar el ciclo del
    semáforo propuesto desde el visor.], [Por desarrollar],
    [Transporte público real], [Buses, paradas y rutas desde GTFS (`gtfs2pt`); hoy los viajes en transporte público se representan como caminata.],
    [Por desarrollar],
    [Validación GEH / RMSE], [Comparación de los volúmenes simulados con los aforos HMD (Fase 4).], [Por desarrollar],
  ),
  caption: [Cambios de alcance de la versión #version.],
) <tabCambios>

Fuera del alcance siguen la integración con APIs comerciales de tráfico, el despliegue institucional, la calibración para otras localidades y el uso de
los programas semafóricos reales de la Secretaría Distrital de Movilidad: los programas se generan con netconvert a partir de OpenStreetMap.

// ───────────────────────────────────────────── 2. Análisis de impacto

= Análisis de impacto

La implementación exitosa del sistema propuesto tendrá impactos significativos a corto, mediano y largo plazo sobre la planificación de la movilidad
urbana en Bogotá y, potencialmente, en otras ciudades con contextos similares.

A corto plazo, el impacto más inmediato se concentra en los usuarios directos del sistema: planificadores y analistas de la Secretaría Distrital de
Movilidad, investigadores académicos y consultores del sector transporte. Para estos usuarios, el sistema reduce significativamente el tiempo y la
complejidad técnica requeridos para generar y analizar escenarios de simulación. Tareas que hoy requieren horas o días de trabajo manual (limpieza de
datos, transformación de formatos, configuración de archivos XML de SUMO) quedarían automatizadas, permitiendo dedicar más tiempo al análisis y la
interpretación de resultados, esto mediante la interacción y uso del módulo web orientado a solucionar dichas problemáticas relacionadas con la
facilidad de uso a la hora de lanzar y configurar simulaciones.

A mediano plazo, el sistema puede convertirse en una herramienta de apoyo para la evaluación de políticas de movilidad antes de su implementación
real. Intervenciones como el día sin carro, restricciones vehiculares por pico y placa, cierres temporales de vías por obras o eventos, o
modificaciones en la sincronización de semáforos, podrían evaluarse de manera controlada y cuantitativa antes de aplicarse en la ciudad. Esto
reduciría la incertidumbre en la toma de decisiones y podría contribuir a intervenciones más efectivas y mejor fundamentadas. El simulador 3D
comparativo de la versión #version permite además comunicar el efecto de una intervención (por ejemplo, un semáforo nuevo) a públicos no técnicos de
forma visual y concreta.

A largo plazo, el proyecto tiene el potencial de fortalecer la capacidad institucional y académica de Bogotá en el uso de simulación de tráfico como
herramienta de planificación. Al ser desarrollado con tecnología de código abierto y datos disponibles públicamente, el sistema es reproducible,
extensible y adaptable a otras localidades de la ciudad o a otras ciudades colombianas con contextos de movilidad similares. La modularidad del diseño
permite incorporar nuevas fuentes de datos, nuevas políticas de movilidad y nuevas funcionalidades de análisis en versiones futuras, lo que garantiza
la sostenibilidad del proyecto más allá de su entrega inicial.

El impacto social del proyecto se relaciona directamente con la calidad de vida de los ciudadanos bogotanos. La congestión vehicular tiene costos
tangibles, como la pérdida de tiempo productivo. Al apoyar la evaluación rigurosa de medidas de gestión del tráfico, el sistema contribuye
indirectamente a la posibilidad de reducir estos efectos negativos mediante decisiones de política mejor informadas.

// ───────────────────────────────────────────── 3. Proceso

= Proceso

== Fase 1: Comprensión del Dominio y de los Datos

Esta fase corresponde a las primeras dos etapas de CRISP-DM: comprensión del negocio (_business understanding_) y comprensión de los datos (_data
understanding_). Su propósito es establecer con precisión el problema a resolver, identificar las fuentes de datos disponibles, y evaluar su calidad y
pertinencia antes de iniciar cualquier transformación.

=== Método

Se adaptan las dos primeras fases de CRISP-DM al contexto de un proyecto académico de simulación de tráfico. La fase de comprensión del negocio se
ejecuta mediante revisión bibliográfica del sistema de movilidad bogotano y el análisis de documentación oficial de la Encuesta de Movilidad de Bogotá.
La fase de comprensión de datos se ejecuta mediante exploración estadística descriptiva de las bases de datos de aforos y de la encuesta, identificando
valores faltantes, inconsistencias, distribuciones de variables clave y cobertura geográfica. La adaptación principal respecto al proceso estándar de
CRISP-DM consiste en incorporar explícitamente el análisis de la red vial digital (OpenStreetMap) como una tercera fuente de datos que debe comprenderse
en paralelo con los datos de demanda.

=== Actividades

- Exploración y caracterización estadística de la base de datos de aforos vehiculares en hora de máxima demanda.
- Exploración y caracterización de la base de datos de la Encuesta de Movilidad, incluyendo análisis de la cobertura muestral y los factores de
  ponderación.
- Evaluación de la red vial de Bogotá en OpenStreetMap: cobertura, tipos de vía, atributos disponibles y calidad geométrica.
- Identificación de brechas de datos: zonas sin cobertura de aforo, modos de transporte sin representación suficiente, períodos horarios sin datos.
- Definición formal del alcance geográfico y temporal de la simulación.

=== Resultados esperados

- Informe de caracterización de datos: descripción estadística de las fuentes de entrada, calidad de los datos y brechas identificadas.
- Alcance geográfico y temporal del modelo de simulación formalmente definido y documentado.
- Inventario de fuentes de datos con su estado de disponibilidad, formato y nivel de procesamiento requerido.

== Fase 2: Preparación de datos

Esta fase corresponde a la etapa de preparación de datos (_data preparation_) de CRISP-DM. Su objetivo es transformar los datos brutos identificados en
la fase anterior en insumos estructurados, limpios y en el formato requerido por el simulador. El resultado de esta fase es el pipeline de datos que
constituye uno de los aportes técnicos centrales del proyecto.

=== Método

Se implementa un pipeline ETL (Extract, Transform, Load) adaptado a los requerimientos de entrada de SUMO:
- la *extracción* obtiene los datos desde sus fuentes originales (archivos Excel de aforos, base de datos de la encuesta de movilidad, archivos
  XML/OSM de la red vial);
- la *transformación* aplica limpieza, validación, expansión muestral mediante factores de ponderación, construcción de matrices origen-destino por
  período horario y geocodificación de zonas de análisis de tráfico (TAZ);
- la *carga* genera los archivos de entrada de SUMO: red vial procesada con netconvert, matrices O/D en formato TAZ, archivos de demanda y archivos de
  tipos de vehículos.

=== Actividades

- Limpieza y validación de la base de datos de aforos: eliminación de registros duplicados, imputación de valores faltantes y verificación de
  consistencia temporal.
- Aplicación de factores de ponderación para expansión muestral de la encuesta de movilidad.
- Construcción de matrices origen-destino desagregadas por modo de transporte y período horario (mañana, mediodía, tarde).
- Definición y delimitación de zonas de análisis de tráfico (TAZ) sobre la red vial de Bogotá.
- Procesamiento de la red vial desde OpenStreetMap mediante netconvert: limpieza de geometría, asignación de tipos de vía, velocidades y capacidades.
- Generación de archivos de tipos de vehículos (vType) para cada modo del sistema de movilidad bogotano.
- Validación cruzada entre aforos, matrices O/D y red vial para verificar consistencia global del modelo de demanda.

=== Resultados esperados

- Pipeline ETL documentado y reproducible, con scripts versionados en el repositorio del proyecto.
- Matrices origen-destino por modo y período horario, en formato compatible con SUMO (OD2Trips).
- Red vial de Bogotá procesada y lista para simulación, en formato `.net.xml` de SUMO (en la versión #version, red 3D de Usaquén con elevación).
- Archivos de tipos de vehículos (passenger, bus, motorcycle, bicycle) calibrados con parámetros representativos del contexto bogotano.
- Reporte de calidad del dato: métricas de completitud, consistencia y cobertura geográfica del modelo de demanda resultante.

== Fase 3: Construcción del escenario de simulación

Esta fase marca la transición de CRISP-DM a Scrum como metodología principal. Una vez que los datos están preparados y los archivos de entrada de SUMO
están disponibles, el trabajo pasa a ser iterativo: se construye el escenario de simulación en incrementos sucesivos, cada uno verificado contra los
datos de aforo reales antes de avanzar al siguiente. Cada sprint de Scrum tiene una duración de dos semanas y produce un incremento funcional del
escenario de simulación.

=== Método

Se adopta Scrum con adaptaciones para un equipo académico de cuatro personas sin roles de Product Owner externo. El Product Backlog contiene los
componentes del escenario de simulación ordenados por prioridad:
- red vial base y demanda monomodal (solo automóviles);
- integración de modos adicionales (buses, motos, bicicletas);
- calibración de parámetros de comportamiento vehicular;
- modelado de semáforos y control de tráfico;
- análisis de escenarios hipotéticos.

Cada sprint inicia con una reunión de planeación donde el equipo selecciona los ítems del backlog a desarrollar, y cierra con una revisión del
incremento y una retrospectiva.

La adaptación principal de Scrum consiste en reemplazar la definición de "done" convencional (software funcional) por una definición específica para
modelos de simulación: un incremento se considera terminado cuando el componente simulado reproduce los aforos observados con un error GEH menor a 5 en
al menos el 85% de los puntos de conteo, criterio estándar en la validación de modelos de tráfico. Para los incrementos de software del módulo web
(Sprints 5 a 8), un incremento se considera terminado cuando sus pruebas automatizadas pasan y su flujo se demuestra en el visor.

=== Actividades

- *Sprint 1:* construcción del escenario base con red vial y demanda de automóviles particulares. Verificación inicial contra aforos de vehículos
  livianos.
- *Sprint 2:* integración del transporte público (SITP y TransMilenio) con carriles exclusivos y paradas. Calibración de parámetros de buses.
- *Sprint 3:* integración de motocicletas con el modelo de sublane. Calibración de parámetros de comportamiento lateral y calibración global del
  modelo: ajuste de parámetros de car-following y lane-changing para reproducir los patrones de congestión observados en todos los modos integrados.
- *Sprint 4:* escenarios hipotéticos de infraestructura vial (cierre de vías, adición de carriles, variación de demanda) y de control de tráfico
  (instalación de semáforos en zonas sin señalización actual, modificación de fases semafóricas en intersecciones existentes). Evaluación del impacto
  en tiempos de viaje y niveles de servicio.
- *Sprint 5:* desarrollo del módulo web: implementación del backend con FastAPI para exponer los resultados de SUMO, desarrollo del frontend de
  visualización interactiva (métricas de congestión, tiempos de viaje, flujos por segmento de vía) e implementación del formulario de parametrización
  de nuevas simulaciones desde la interfaz gráfica.
- *Sprint 6 _(v#version)_:* análisis de intersecciones y semaforización en el módulo web:
  - ficha de cada semáforo con volúmenes por acceso;
  - edición de programas y método de Webster;
  - recorte de zonas y comparación de programas;
  - priorización de cruces sin semáforo.
- *Sprint 7 _(v#version)_:* simulador 3D comparativo del semáforo propuesto:
  - dos simulaciones en lockstep controladas por TraCI;
  - escena 3D con la red y los edificios reales;
  - seguimiento en tercera persona de vehículos y peatones;
  - HUD de velocidad, acción, decisiones y riesgo (TTC, DRAC, PET);
  - minimapa 2D y selección de vías.
- *Sprint 8 _(v#version, por desarrollar)_:* reporte exportable de la comparación 3D, programa editable del semáforo propuesto y transporte público con
  buses y paradas reales desde GTFS.

=== Resultados esperados

- Escenario de simulación calibrado y validado para el área de estudio de Bogotá, reproducible desde el repositorio del proyecto.
- Reporte de calibración: comparación entre flujos simulados y aforos reales, con métricas GEH y RMSE por punto de conteo.
- Resultados de escenarios hipotéticos de infraestructura vial: análisis cuantitativo del impacto de cierres, nuevos carriles y variaciones de demanda.
- Resultados de escenarios hipotéticos de control de tráfico: análisis del impacto de semáforos nuevos y ajuste de fases en tiempos de viaje y niveles
  de servicio.
- Código fuente del pipeline de simulación versionado y documentado.
- Módulo web funcional: interfaz de visualización interactiva de métricas de SUMO y formulario de parametrización de simulaciones operativo, con prueba
  funcional aprobada por el director.
- _(v#version)_ Simulador 3D comparativo operativo sobre los cruces prioritarios de Usaquén, con comparaciones documentadas (métricas de fluidez,
  conflictos y riesgo en ambos escenarios) que alimentan los resultados de control de tráfico.

== Fase 4: Evaluación y análisis de resultados

Esta fase retoma el proceso de CRISP-DM en su etapa de evaluación, en la que se valora si el modelo construido responde efectivamente a los objetivos
planteados al inicio del proyecto. A diferencia de la calibración técnica realizada en la fase anterior, esta fase tiene un carácter analítico e
interpretativo.

=== Método

Se adopta la etapa de evaluación de CRISP-DM, adaptada para modelos de simulación de tráfico. La evaluación se realiza en dos niveles:
- *técnico:* ¿el pipeline produce archivos que SUMO puede ejecutar correctamente y que reproducen con suficiente fidelidad el comportamiento observado?
  Para este nivel se usan métricas estándar de validación de modelos de tráfico (GEH, RMSE);
- *analítico:* ¿los insumos generados son coherentes con los patrones de movilidad reportados en la encuesta?

=== Actividades

- Validación formal del pipeline contra un conjunto de datos de aforo reservado para validación (no usado en calibración).
- Verificación de coherencia de los archivos generados: matrices O/D, red vial y archivos de rutas frente a los patrones de movilidad de la encuesta.
- Ejecución del escenario resultante en SUMO para confirmar que los insumos producidos por el pipeline son válidos y ejecutables.
- Identificación de limitaciones del modelo: zonas con menor fidelidad, modos con menor cobertura de datos, supuestos simplificadores (en la versión
  #version, entre ellos el tráfico de fondo sintético y los programas semafóricos generados por netconvert).
- Documentación de conclusiones y recomendaciones para trabajo futuro.

=== Resultados esperados

- Reporte de validación del pipeline con métricas de error (GEH, RMSE) y análisis de sensibilidad.
- Documentación del alcance y las limitaciones del módulo: zonas cubiertas, modos soportados y supuestos adoptados en el procesamiento.
- Conclusiones del proyecto documentadas en el informe final, incluyendo alcance, limitaciones y líneas de trabajo futuro.

// ───────────────────────────────────────────── 4. Aspectos generales

= Aspectos generales del proyecto

== Compromiso de apoyo de la Institución

El presente proyecto de grado se desarrolla en el marco académico de la Pontificia Universidad Javeriana, sin vinculación directa con una organización
externa. Los datos de entrada del sistema (Encuesta de Movilidad de Bogotá y red vial OpenStreetMap) son de carácter público y de libre acceso, por lo
que no se requiere carta de compromiso institucional de una entidad externa. El proyecto cuenta con el apoyo del Departamento de Sistemas de la Facultad
de Ingeniería, que provee el acompañamiento académico necesario a través del director del proyecto de grado.

== Derechos patrimoniales

Los derechos morales de la producción intelectual derivada de este proyecto de grado corresponden a los estudiantes autores, de acuerdo con la
legislación colombiana sobre propiedad intelectual. Dado que el proyecto se desarrolla en el marco de la Pontificia Universidad Javeriana sin
financiación de una entidad externa, los derechos patrimoniales sobre los resultados del proyecto --incluyendo el código fuente del sistema de software
desarrollado-- se rigen por el Reglamento de Propiedad Intelectual de la Universidad.

El software desarrollado en el marco de este proyecto se entregará a la Universidad bajo una licencia de código abierto (MIT License o Apache 2.0, por
definir), lo que permite su uso, modificación y distribución libre bajo las condiciones de dicha licencia, garantizando la transparencia y
reproducibilidad del trabajo académico.

// ───────────────────────────────────────────── 5. Marco teórico

= Marco teórico

== Fundamentos y conceptos relevantes para el proyecto

Esta sección introduce los conceptos necesarios para comprender el problema abordado por el proyecto: el análisis y modelado del flujo de tráfico
urbano en Bogotá mediante simulación basada en datos. Se presenta el problema desde la perspectiva de la ingeniería de sistemas, destacando los retos
de procesamiento de datos, modelado de sistemas complejos y representación computacional del comportamiento colectivo.

=== El problema del flujo en sistemas complejos

El concepto de flujo es transversal a múltiples disciplinas de la ingeniería y las ciencias aplicadas. En términos generales, un flujo describe el
movimiento de entidades (vehículos, paquetes de datos, personas, fluidos) a través de una red estructurada, sujeto a restricciones de capacidad, reglas
de enrutamiento y comportamiento de los agentes involucrados.

En ingeniería de sistemas, el análisis de flujos en redes es un problema central que aparece en contextos tan diversos como las redes de computadores
(flujo de paquetes TCP/IP), los sistemas de manufactura (flujo de materiales en líneas de producción), las redes de distribución eléctrica y, por
supuesto, el tráfico vehicular urbano. El tráfico vehicular urbano es uno de los sistemas de flujo más complejos de modelar, porque combina
infraestructura física (vías, intersecciones, semáforos), comportamiento humano heterogéneo, múltiples tipos de agentes y una demanda variable en el
tiempo y el espacio.

=== Modelado y simulación de sistemas

El modelado es el proceso de construir una representación abstracta de un sistema real con el fin de estudiar su comportamiento, hacer predicciones o
evaluar alternativas de intervención. La simulación, en particular, permite representar el comportamiento dinámico de un sistema a lo largo del tiempo,
reproduciendo la interacción entre sus componentes de forma controlada. Existen tres niveles de abstracción en la simulación de tráfico:
- *Simulación microscópica:* modela cada vehículo de forma individual, con posición, velocidad y comportamiento propios. Permite analizar fenómenos
  locales como la formación de colas, el cambio de carril y la respuesta a semáforos. Requiere datos detallados, pero ofrece la mayor fidelidad.
- *Simulación mesoscópica:* agrupa vehículos en paquetes o los mueve por colas sin posición continua exacta. Es un compromiso entre detalle y
  eficiencia computacional.
- *Simulación macroscópica:* trata el tráfico como un fluido, describiendo densidad, velocidad promedio y flujo por segmento de vía mediante
  ecuaciones diferenciales. Es eficiente para redes grandes, pero pierde el comportamiento individual.

=== Datos de movilidad urbana y su procesamiento

Un proyecto de análisis de movilidad urbana es esencialmente un proyecto de datos. La calidad, cobertura y consistencia de los datos de entrada
determinan directamente la validez de los resultados. En el contexto de este proyecto, los datos de entrada provienen de dos fuentes principales: aforos
vehiculares en hora de máxima demanda, y la Encuesta de Movilidad de Bogotá, a partir de la cual se construyen las matrices origen-destino (O/D) que
cuantifican el número de viajes entre pares de zonas geográficas.

El procesamiento de estos datos para alimentar un modelo de simulación implica un pipeline con varias etapas:
- limpieza y validación de registros;
- expansión muestral mediante factores de ponderación;
- construcción de matrices O/D por período horario;
- geocodificación de zonas de análisis (TAZ);
- integración con la red vial digital.

Este pipeline es en sí mismo una contribución técnica del proyecto.

=== Matrices Origen-Destino y Zonas de Análisis de tráfico

Una matriz origen-destino (O/D) es una estructura de datos fundamental en la modelación del transporte. Cada celda $O_(i j)$ de la matriz representa
el número de viajes que se realizan desde la zona $i$ hasta la zona $j$ durante un período de tiempo determinado. Las zonas de análisis de tráfico
(TAZ, _Traffic Analysis Zones_) son las unidades espaciales básicas que agrupan áreas con comportamiento de movilidad homogéneo y sirven como nodos en
el modelo de demanda.

La construcción de una matriz O/D a partir de una encuesta de movilidad requiere aplicar factores de expansión muestral @ortuzar que permitan inferir el
comportamiento de la población total a partir de la muestra encuestada. En el contexto del sistema de transporte de Bogotá, las TAZ suelen
corresponder a unidades de planeamiento zonal (UPZ) o sectores definidos en la Encuesta de Movilidad de Bogotá.

=== Simulation of Urban MObility (SUMO)

SUMO es un simulador de tráfico de código abierto diseñado para modelar y analizar sistemas de transporte urbanos @lopez2018 @krajzewicz2012. SUMO
permite simular el movimiento individual de vehículos, peatones y otros actores del sistema de transporte dentro de una red vial determinada,
modelando el comportamiento de cada vehículo de manera individual, teniendo en cuenta variables como velocidad, aceleración, interacción con otros
vehículos, comportamiento en intersecciones y respuesta a semáforos.

SUMO ofrece un conjunto amplio de funcionalidades:
- simulación detallada de tráfico;
- modelado de múltiples actores del sistema de movilidad (transporte público, peatones, bicicletas);
- representación detallada de redes viales;
- control y modificación de sistemas de tráfico;
- integración con datos reales (OpenStreetMap, matrices O/D);
- generación de métricas e indicadores como tiempos de viaje, niveles de congestión y velocidades promedio.

Dentro del sistema propuesto, SUMO actúa como motor de simulación especializado. Recibe como entrada los archivos generados por el módulo de
procesamiento de datos (red vial, matrices O/D y archivos de rutas), ejecuta las simulaciones que permiten evaluar el impacto de diferentes políticas de
movilidad, y genera archivos de salida con indicadores relevantes del comportamiento del sistema simulado.

=== Modelos de comportamiento vehicular

En la simulación microscópica de tráfico, el comportamiento de cada vehículo se rige por dos modelos fundamentales: el modelo de seguimiento vehicular
(_car-following_) y el modelo de cambio de carril (_lane-changing_). El modelo de seguimiento vehicular determina cómo un conductor ajusta su velocidad
en función de la distancia y velocidad relativa respecto al vehículo que le precede. Los modelos más utilizados son el modelo de Krauss (base de SUMO),
el Intelligent Driver Model (IDM) y el modelo de Wiedemann.

El comportamiento heterogéneo de los conductores bogotanos --incluyendo irrespeto a señales, conducción agresiva e invasión de carriles exclusivos--
puede representarse mediante la distribución estadística de los parámetros de estos modelos entre la población vehicular simulada, en lugar de asignar
valores únicos a todos los vehículos.

=== El sistema de movilidad de Bogotá

Bogotá cuenta con un sistema de movilidad multimodal que incluye TransMilenio (sistema BRT de alta capacidad con carriles exclusivos), el SITP (Sistema
Integrado de Transporte Público), transporte privado (automóviles y motocicletas), bicicletas y taxis y plataformas digitales. La congestión en Bogotá
tiene causas estructurales: alta motorización, oferta vial limitada por la topografía y la urbanización histórica, concentración de empleos en pocas
zonas, y alta dependencia del vehículo particular.

=== Control semafórico y medidas sustitutas de seguridad _(v#version)_

Un semáforo asigna el derecho de paso entre los movimientos de una intersección mediante un programa de fases, cada una con su duración y el estado
(verde, amarillo o rojo) de cada movimiento. El método de Webster @webster estima el ciclo que minimiza la demora media:
$ C_0 = (1.5 L + 5) / (1 - Y) $
donde $L$ es el tiempo perdido por ciclo y $Y$ la suma de las razones flujo/flujo de saturación de los movimientos críticos. Los verdes se reparten en
proporción a esas razones.

Instalar un semáforo no siempre mejora un cruce: reduce los conflictos entre movimientos transversales, pero puede aumentar la demora y las colas. Para
evaluar la seguridad sin esperar a que ocurran choques se usan medidas sustitutas de seguridad (SSM) @gettman, calculadas sobre las trayectorias
simuladas:
- *TTC* (tiempo a la colisión): segundos hasta alcanzar al vehículo de adelante si ambos mantienen su velocidad. Valores menores a 1,5 s indican un
  conflicto serio.
- *DRAC* (desaceleración requerida para evitar la colisión): frenado necesario para no alcanzarlo. Por encima de 3,35 m/s² exige un frenado fuerte.
- *PET* (tiempo posterior a la invasión): diferencia de tiempo entre el paso de dos actores por el mismo punto de conflicto. Menos de 1,5 s es un
  cruce peligroso.

El simulador 3D del proyecto calcula estos indicadores para el actor observado en ambos escenarios (sin y con semáforo propuesto), junto con métricas
de fluidez (detenidos, espera media) y de conflictos en el cruce.

== Análisis de alternativas de solución

=== Alternativas de solución e impacto

El problema central del proyecto admite múltiples enfoques de solución. Las alternativas que se presentan a continuación no son variantes de la
herramienta elegida, sino enfoques metodológicos diferentes para resolver el mismo problema, cada uno con supuestos, requerimientos de datos e impactos
distintos (véase la @tabAlternativas).

*Alternativa 1 -- Modelos Analíticos y Teoría de Colas:* los modelos analíticos de tráfico abordan el problema del flujo vehicular mediante
formulaciones matemáticas cerradas. El enfoque más consolidado es la teoría de flujo de tráfico macroscópico (modelo LWR), complementada por la teoría
de colas (M/M/1, M/D/1, redes de Jackson) para modelar intersecciones y cuellos de botella. Son computacionalmente eficientes y transparentes, pero su
principal limitación es la necesidad de simplificaciones fuertes que reducen significativamente la validez de los resultados en un contexto heterogéneo
como el de Bogotá. Además, no permiten evaluar escenarios hipotéticos que involucren cambios estructurales en la red sin reformular completamente las
ecuaciones.

*Alternativa 2 -- Machine Learning Predictivo:* el enfoque de aprendizaje automático consiste en entrenar modelos estadísticos (LSTM, Random Forest,
Graph Neural Networks) que aprendan patrones de congestión a partir de datos históricos @vlahogianni. Su limitación crítica para este proyecto es que
los modelos predictivos no permiten explorar escenarios que no hayan ocurrido históricamente, lo que limita su valor para el análisis de políticas de
transporte. Además, la escasez de datos históricos estructurados en Bogotá representa una barrera de entrada significativa.

*Alternativa 3 -- APIs de Datos en Tiempo Real (Waze / Google Maps):* plataformas como Waze for Cities y la API de Google Maps ofrecen datos de
velocidad y congestión en tiempo real. Sin embargo, sus limitaciones son determinantes: los datos son privados y su acceso está sujeto a contratos
comerciales, la cobertura depende de la densidad de usuarios, y de manera crítica, este enfoque no permite evaluar escenarios hipotéticos, solo puede
describir lo que ya ocurrió.

*Alternativa 4 -- Modelo de Cuatro Pasos Clásico:* el modelo de cuatro pasos (generación, distribución, elección modal y asignación de tráfico) es el
estándar de la planificación del transporte @mcnally. Hace uso directo de las encuestas de movilidad como insumo principal y ha sido validado en
múltiples ciudades. Su principal limitación es que opera a nivel zonal y produce resultados estáticos, sin capturar la dinámica temporal del tráfico ni
el comportamiento individual de los vehículos.

=== Comparación de alternativas

#figure(
  table(
    columns: (20%, 1fr, 1fr, 1fr, 1fr),
    table.header([Criterio], [Propuesta: SUMO], [Modelos Analíticos], [ML Predictivo], [Modelo 4 Pasos]),
    [Resolución del análisis], [Microscópica (vehículo a vehículo)], [Macroscópica / agregada], [Depende del modelo], [Zonal / macroscópica],
    [Escenarios hipotéticos], [Alta], [Media (reformular modelo)], [Baja (reentrenamiento)], [Media (iteración manual)],
    [Reproducibilidad], [Alta (código abierto)], [Alta (fórmulas)], [Media (cajas negras)], [Alta (metodología estándar)],
    [Dependencia de datos privados], [No (OSM + datos propios)], [No], [Parcial], [No],
    [Costo de implementación], [Bajo (open source)], [Bajo], [Medio-alto], [Alto (encuestas)],
    [Multimodalidad], [Sí, integrada], [Limitada], [Sí, si datos lo incluyen], [Sí, por etapas],
    [Comportamiento individual], [Sí (car-following)], [No], [No (estadístico)], [No],
    [Transparencia], [Alta], [Muy alta], [Baja-media], [Alta],
    [Aplicabilidad a Bogotá], [Alta], [Media], [Media (datos escasos)], [Alta],
  ),
  caption: [Comparación de alternativas de solución.],
) <tabAlternativas>

El análisis comparativo muestra que ninguna de las alternativas satisface de forma simultánea los requerimientos centrales del proyecto: resolución
microscópica del comportamiento vehicular, capacidad de analizar escenarios hipotéticos, independencia de datos privados, multimodalidad integrada y
costo accesible para investigación académica. La propuesta del proyecto --un pipeline de procesamiento de datos reales integrado con simulación
microscópica de tráfico mediante SUMO-- es la única alternativa que combina todos estos criterios simultáneamente, posicionándola como la solución
metodológicamente más robusta y pertinente para el problema planteado en el contexto de Bogotá.

// ───────────────────────────────────────────── 6. Referencias

= Referencias

#bibliography("referencias.yml", title: none, style: "ieee", full: true)
