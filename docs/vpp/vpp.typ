#set document(title: "VPP (Versión Parcial de la Propuesta)", author: ("Erick Salazar Suarez", "Felipe Garrido Flores", "Santiago Chitiva Contreras", "Samuel Campos Cañas"))
#set page(paper: "a4", margin: 2.5cm)
#set par(justify: true, spacing: 5pt)
#set heading(numbering: "1.1")

#v(25%)
#align(center)[
  #text(size: 20pt, weight: "bold")[VPP (Versión Parcial de la Propuesta)]

  #v(1cm)
  Erick Salazar Suarez \\
  Felipe Garrido Flores \\
  Santiago Chitiva Contreras \\
  Samuel Campos Cañas

  #v(1fr)
  Pontificia Universidad Javeriana \\
  2026
]
#pagebreak()
#outline(title: "Contenido", depth: 3)
#pagebreak()

= Simulation of Urban MObility \(SUMO)
<simulation-of-urban-mobility-sumo>
== ¿Qué es?
<qué-es>
Simulation of Urban MObility \(SUMO) es un simulador de tráfico, de
código abierto, diseñado para modelar y analizar sistemas de transporte
urbanos.

SUMO permite simular el movimiento individual de vehículos, peatones y
otros actores del sistema de transporte dentro de una red vial
determinada. SUMO modela el comportamiento de cada vehículo de manera
individual, teniendo en cuenta variables como velocidad, aceleración,
interacción con otros vehículos, comportamiento en intersecciones y
respuesta a semáforos o señales de tráfico.

== Funcionalidades
<funcionalidades>
SUMO ofrece un conjunto amplio de funcionalidades orientadas al
análisis, modelado y evaluación de sistemas de transporte urbano.
Tenemos:

- #strong[Simulación detallada de tráfico];: permite modelar el
  comportamiento individual de cada vehículo dentro de la red vial,
  considerando factores como cambios de carril, aceleración, frenado e
  interacción con otros vehículos.

- #strong[Modelado de múltiples actores del sistema de movilidad];:
  además de vehículos particulares, SUMO permite simular transporte
  público, peatones, bicicletas y otros tipos de vehículos.

- #strong[Representación detallada de redes viales];: el simulador
  permite importar o construir redes viales completas que incluyen
  calles, intersecciones, carriles, semáforos y otras infraestructuras
  relevantes del sistema de transporte.

- #strong[Control y modificación de sistemas de tráfico];: SUMO permite
  definir y modificar el comportamiento de semáforos, restricciones de
  circulación, cierres de vías y otras políticas.

- #strong[Integración con datos reales];: la plataforma permite utilizar
  datos provenientes de diferentes fuentes, como redes viales basadas en
  OpenStreetMap o matrices origen–destino generadas a partir de
  encuestas de movilidad.

- #strong[Generación de métricas e indicadores];: durante la ejecución
  de una simulación, SUMO produce datos detallados sobre el
  comportamiento del sistema, incluyendo tiempos de viaje, niveles de
  congestión, velocidades promedio y otros indicadores relevantes para
  el análisis del tráfico.

- #strong[Herramientas de visualización];: el simulador cuenta con una
  interfaz gráfica que permite observar en tiempo real la evolución de
  la simulación, facilitando la comprensión del comportamiento del
  sistema de movilidad bajo diferentes condiciones.

== Importancia dentro del proyecto
<importancia-dentro-del-proyecto>
Dentro del sistema propuesto en este proyecto, SUMO cumple como
simulador encargado de modelar el comportamiento del tráfico urbano a
partir de los datos procesados por el sistema.

SUMO es la herramienta responsable de ejecutar las simulaciones que
permiten evaluar el impacto de diferentes políticas de movilidad sobre
el sistema de transporte. Acá el simulador, recibe como entrada los
archivos generados por el módulo de procesamiento de datos del sistema,
que incluyen la red vial, las matrices origen–destino y los archivos de
rutas necesarios para la simulación.

Una vez ejecutada la simulación, SUMO genera distintos archivos de
salida que contienen información sobre el comportamiento del sistema de
movilidad simulado. Estos resultados incluyen indicadores relevantes
como tiempos de viaje promedio, niveles de congestión en diferentes
segmentos de la red vial y variaciones en el flujo vehicular.

La importancia de SUMO dentro del proyecto radica en que permite
analizar de manera controlada el impacto potencial de diferentes
intervenciones en el sistema de movilidad antes de implementarlas en el
mundo real.

SUMO se integrará dentro de la arquitectura del sistema como una
herramienta especializada de simulación, mientras que los demás
componentes del sistema se encargan de simplificar su utilización,
automatizar la preparación de datos y presentar los resultados de forma
comprensible para los usuarios finales.

= Antecedentes, problema y solución propuesta
<antecedentes-problema-y-solución-propuesta>
== Descripción de la problemática y oportunidad
<descripción-de-la-problemática-y-oportunidad>
La movilidad urbana representa uno de los principales retos para las
grandes ciudades contemporáneas, debido al crecimiento poblacional, el
aumento del parque automotor y la complejidad de los sistemas de
transporte. En el caso de Bogotá, este desafío es particularmente
evidente, ya que la ciudad enfrenta altos niveles de congestión
vehicular y una creciente demanda de desplazamientos diarios por parte
de millones de ciudadanos.

Diversos indicadores evidencian la magnitud del problema. De acuerdo con
el TomTom Traffic Index, Bogotá se ubicó en 2025 como la séptima ciudad
con mayor congestión vehicular a nivel mundial, registrando un nivel de
congestión del 69,9% y un incremento de 7,7 puntos porcentuales respecto
al año anterior. Este fenómeno implica que los ciudadanos pueden perder
en promedio hasta 153 horas al año en tráfico durante horas pico, lo que
equivale a más de seis días completos atrapados en congestiones
vehiculares \[1\]. Asimismo, la velocidad promedio de circulación
durante los periodos de mayor demanda apenas supera los 15 km/h, lo que
refleja las dificultades estructurales del sistema vial para absorber el
volumen de vehículos en circulación \[2\].

El impacto de esta situación trasciende el ámbito del transporte y
afecta directamente la calidad de vida de los habitantes, la
productividad económica y la eficiencia del funcionamiento urbano. En
algunos casos, recorrer distancias relativamente cortas dentro de la
ciudad puede tomar tiempos considerablemente altos; por ejemplo,
trayectos de apenas cinco kilómetros pueden tardar hasta 40 minutos en
horas pico, mientras que recorridos de diez kilómetros superan los 30
minutos en promedio\[3\]. A esto se suma el hecho de que cerca del 70%
de la red vial de la ciudad presenta niveles de congestión diaria, lo
que evidencia la dimensión estructural del problema de movilidad en la
capital colombiana.

Paralelamente, Bogotá cuenta con sistemas de transporte de gran escala y
con una alta participación ciudadana en los desplazamientos diarios. Por
ejemplo, el sistema de transporte masivo TransMilenio registra más de
cuatro millones de viajes diarios, consolidándose como uno de los
componentes fundamentales del sistema de movilidad urbana de la
ciudad\[4\]. En este contexto, las encuestas de movilidad realizadas por
la Secretaría Distrital de Movilidad representan una fuente de
información fundamental para comprender cómo se desplazan los ciudadanos
dentro de la ciudad.

Estas encuestas permiten caracterizar los patrones de movilidad de la
población en un momento determinado, identificando aspectos como los
orígenes y destinos de los viajes, los modos de transporte utilizados,
los horarios de desplazamiento y diversas variables socioeconómicas
asociadas a los usuarios del sistema de transporte\[5\]. Gracias a esta
información es posible describir y analizar el comportamiento de la
movilidad urbana, así como identificar tendencias y dinámicas relevantes
para la planificación del sistema de transporte.

En este sentido, la planificación, el diseño y la evaluación de
infraestructura y políticas de movilidad requieren herramientas que
permitan analizar de manera rigurosa el comportamiento del tráfico y los
patrones de desplazamiento de la población. Las entidades responsables
de la planificación del transporte, como la Secretaría Distrital de
Movilidad, así como ingenieros y analistas del sector, necesitan
herramientas que les permitan evaluar diferentes escenarios de movilidad
antes de implementar cambios en la infraestructura o en las políticas de
transporte.

Dentro de este contexto, los sistemas de simulación de tráfico urbano se
han consolidado como herramientas relevantes para analizar el impacto de
diferentes decisiones de planificación. Entre estas herramientas destaca
SUMO \(Simulation of Urban MObility), un simulador de tráfico de código
abierto ampliamente utilizado en investigación y desarrollo para modelar
el comportamiento de vehículos, peatones, infraestructura vial y
sistemas de control del tráfico en entornos urbanos complejos.

En este contexto, surge una oportunidad para desarrollar herramientas
que permitan aprovechar de manera más efectiva la información
proveniente de fuentes de datos como las encuestas de movilidad,
integrándolas con sistemas de simulación que faciliten el análisis de
diferentes escenarios de movilidad. De esta manera, sería posible apoyar
los procesos de planificación y toma de decisiones mediante herramientas
tecnológicas que permitan explorar y evaluar alternativas antes de su
implementación en el entorno urbano real.

== Formulación del problema
<formulación-del-problema>
A pesar de la disponibilidad de herramientas de simulación de movilidad
urbana como SUMO, su utilización en procesos de análisis y planificación
presenta diversas limitaciones prácticas para los usuarios del área de
movilidad.

Por una parte, la configuración y ejecución de simulaciones en SUMO
requiere la preparación manual de diferentes archivos de configuración,
generalmente en formato XML, así como el uso de múltiples utilidades que
forman parte del ecosistema del simulador. Muchas de estas herramientas
se ejecutan mediante interfaces de línea de comandos, lo que puede
resultar poco intuitivo para usuarios que no poseen experiencia previa
en este tipo de entornos. Asimismo, la interfaz gráfica del simulador no
siempre cumple con criterios de usabilidad comunes en el diseño de
software moderno, lo que puede dificultar la configuración de escenarios
y la exploración de diferentes parámetros de simulación.

Por otra parte, aunque las encuestas de movilidad constituyen una fuente
de información valiosa para describir y analizar los patrones de
desplazamiento de la población, actualmente no existe una herramienta
que permita transformar de manera directa estos datos en insumos
compatibles con SUMO para la generación de escenarios de simulación.
Como consecuencia, los analistas deben realizar procesos manuales de
limpieza, transformación y estructuración de la información antes de
poder utilizarla en simulaciones, lo que incrementa el tiempo, la
complejidad técnica y las posibilidades de error en el proceso.

La pregunta que surge de este conjunto de problemas es: #emph[¿Cómo
utilizar datos que describen el comportamiento de la movilidad urbana en
Bogotá, apoyándose en herramientas de simulación como SUMO, para generar
de manera automatizada escenarios de simulación y reportes comprensibles
que faciliten el análisis y la toma de decisiones por parte de entidades
encargadas de la planificación y gestión de la movilidad?]

== Propuesta de la solución
<propuesta-de-la-solución>
Debido a las limitaciones identificadas, los profesionales responsables
del análisis y la planificación de la movilidad urbana no disponen
actualmente de herramientas que permitan integrar de manera sencilla
datos reales de movilidad con plataformas de simulación que faciliten el
análisis de diferentes escenarios antes de su implementación en la
infraestructura urbana.

Con el fin de abordar esta problemática, se propone el desarrollo de un
sistema de software que permita automatizar el proceso de generación de
escenarios de simulación de movilidad urbana a partir de datos reales,
así como facilitar la configuración de simulaciones y la interpretación
de sus resultados mediante una interfaz accesible para los usuarios.

La solución propuesta contempla dos componentes principales que
interactúan entre sí para permitir el procesamiento, simulación y
análisis de escenarios de movilidad urbana.

=== Módulo de procesamiento y transformacion de datos
<módulo-de-procesamiento-y-transformacion-de-datos>
En primer lugar, se plantea el desarrollo de un módulo de procesamiento
de datos encargado de transformar la información proveniente de
encuestas de movilidad en estructuras de datos compatibles con los
formatos requeridos por el simulador SUMO. Este módulo realizará tareas
de limpieza, organización y transformación de los datos, generando
insumos como matrices origen–destino \(estructura de datos que
representa la cantidad de viajes entre distintas zonas de una ciudad,
indicando desde qué zona se origina cada desplazamiento y hacia cuál se
dirige), definiciones de rutas y archivos de configuración en formato
XML necesarios para ejecutar las simulaciones dentro del entorno del
simulador.

Una vez generados estos insumos, el sistema permitirá ejecutar
simulaciones utilizando SUMO como motor de simulación de tráfico.
Durante este proceso, el simulador generará distintos archivos de salida
que contienen información sobre el comportamiento del sistema de
movilidad simulado, incluyendo métricas relacionadas con tiempos de
viaje, flujos vehiculares, densidad de tráfico y otros indicadores
relevantes para el análisis.

=== Módulo web
<módulo-web>
En segundo lugar, se propone el desarrollo de un módulo web orientado a
facilitar la interacción del usuario con el sistema. A través de esta
interfaz, los usuarios podrán configurar y parametrizar diferentes
escenarios de simulación, incluyendo la modificación de variables
asociadas a políticas de movilidad, condiciones del sistema de
transporte o características de la infraestructura vial.

Adicionalmente, este módulo web permitirá gestionar la ejecución de
simulaciones y visualizar los resultados generados por el simulador
mediante herramientas de análisis y visualización de datos. De esta
manera, los usuarios podrán acceder a métricas, gráficos e indicadores
que faciliten la interpretación del comportamiento del sistema de
movilidad bajo diferentes configuraciones de simulación.

Es importante precisar el rol que cumple SUMO dentro de la arquitectura
del sistema propuesto. SUMO actúa como una caja negra en el centro del
proceso: recibe como entrada los archivos de configuración generados por
el módulo de procesamiento de datos \(redes viales, matrices O/D y
archivos de rutas en formato XML), ejecuta la simulación internamente y
devuelve como salida la visualización de la simulación que es
posteriormente consumida por el módulo web para su análisis. El usuario
final nunca interactúa directamente con SUMO ni con sus archivos; toda
la parametrización y la interpretación de resultados ocurren a través de
la interfaz web. Esto es precisamente lo que diferencia esta propuesta
del uso tradicional del simulador, donde el usuario debe conocer y
manipular manualmente cada uno de los formatos de entrada y salida de la
herramienta.

El flujo general del sistema contempla entonces la transformación de
datos de movilidad provenientes de encuestas, la generación automática
de escenarios de simulación en SUMO y el posterior análisis de los
resultados mediante una plataforma web que permita explorar y comparar
diferentes escenarios de movilidad urbana. De esta forma, se busca
proporcionar una herramienta que facilite el uso de simulaciones como
apoyo en los procesos de análisis, planificación y toma de decisiones
relacionadas con la movilidad urbana.

=== Políticas de movilidad soportadas
<políticas-de-movilidad-soportadas>
Las políticas de movilidad que podrán configurarse dentro del sistema
corresponden a un conjunto inicial de intervenciones que pueden
aplicarse sobre la red vial simulada con el objetivo de analizar su
impacto en el comportamiento del tráfico urbano. Estas políticas podrán
ser parametrizadas desde el módulo web y posteriormente traducidas a
configuraciones compatibles con el simulador SUMO para su ejecución
dentro del entorno de simulación.

Entre las políticas que se soportarán inicialmente se encuentran:

- #strong[Restricción o eliminación de vehículos];: permite reducir o
  eliminar determinados tipos de vehículos dentro del escenario de
  simulación, con el fin de representar medidas de restricción
  vehicular.

- #strong[Cierre de vías o segmentos de la red vial];: permite bloquear
  determinadas calles o tramos de la red para analizar el impacto que
  puede generar la interrupción del flujo vehicular en zonas
  específicas.

- #strong[Desactivación o modificación de semáforos];: permite alterar
  el comportamiento de los sistemas de control de tráfico, incluyendo la
  posibilidad de desactivar semáforos o modificar su funcionamiento
  dentro del escenario simulado.

- #strong[Combinación de políticas];: el sistema permitirá aplicar
  múltiples políticas de manera simultánea sobre un mismo escenario, lo
  que facilita la exploración de situaciones más complejas.

Estas configuraciones permiten modelar escenarios de interés para la
planificación urbana, como por ejemplo la implementación de medidas de
restricción vehicular similares al #emph[día sin carro];, cierres
temporales de vías por eventos urbanos o modificaciones en la operación
de intersecciones semaforizadas.

Es importante señalar que el simulador SUMO permite modelar escenarios
mucho más complejos que incluyen una gran variedad de actores dentro del
sistema de movilidad, como peatones, transporte público, bicicletas,
distintos tipos de vehículos y sistemas avanzados de control del
tráfico. No obstante, en esta primera versión del sistema se prioriza la
implementación de un conjunto inicial de políticas que permitan explorar
escenarios relevantes de manera sencilla desde la interfaz web.

Finalmente, el sistema esta pensado para que sea modular, lo que permite
que en futuras versiones se puedan incorporar nuevas políticas de
movilidad y configuraciones adicionales de simulación, ampliando así las
capacidades de análisis del sistema.

=== Especificación de localidades
<especificación-de-localidades>
La Encuesta de Movilidad de Bogotá organiza la información de
desplazamientos de la población a partir de divisiones territoriales
correspondientes a las diferentes localidades de la ciudad. Estas
localidades permiten agrupar los viajes reportados en la encuesta y
constituyen una unidad territorial útil para el análisis de los patrones
de movilidad dentro del sistema urbano.

Entre las localidades más representativas dentro de la ciudad se
encuentran, por ejemplo, Usaquén, Suba, Chapinero, Kennedy, Engativá y
Fontibón, las cuales concentran una parte importante de los flujos de
movilidad debido a su densidad poblacional, actividad económica y
conexión con corredores viales principales.

Dentro del alcance inicial del proyecto se tomará la localidad de
#strong[Usaquén] como caso de estudio principal para el desarrollo y
validación del sistema. Esta decisión se debe a que, de acuerdo con
reportes del Concejo de Bogotá, Usaquén presenta una movilidad mixta, lo
cual implica picos de congestion vehicular lo que la convierte en un
escenario relevante para el análisis de movilidad urbana y la evaluación
de políticas de transporte.

El sistema se diseñará de forma que las herramientas desarrolladas
puedan aplicarse posteriormente a otras localidades de la ciudad. De
esta manera, aunque el proceso de desarrollo y prueba se realizará
inicialmente sobre la localidad de Usaquén, la herramienta debe soportar
a todas las localidades que estan presentes en la encuesta de movilidad
de Bogotá.

=== Datos alternativos
<datos-alternativos>
Si bien la Encuesta de Movilidad constituye una de las principales
fuentes de información para el análisis de los patrones de
desplazamiento en la ciudad, esta no se realiza de manera anual, sino de
forma periódica cada varios años. Debido a esta periodicidad, los datos
obtenidos pueden no reflejar completamente las dinámicas de movilidad
más recientes, especialmente en una ciudad con cambios constantes en
comportamientos de transporte y crecimiento urbano.

Por esta razón, resulta pertinente considerar fuentes de datos
complementarias que permitan actualizar o enriquecer el análisis de
movilidad entre los periodos en los que se realiza la encuesta. Una de
estas fuentes es el #emph[Observatorio de Movilidad de Bogotá];, una
plataforma institucional que recopila y publica información relacionada
con el comportamiento del sistema de transporte en la ciudad. Este
observatorio integra indicadores sobre tráfico, uso del transporte
público, seguridad vial y otros aspectos relevantes del sistema de
movilidad. Los reportes y bases de datos publicadas por el observatorio
suelen actualizarse de manera periódica, generalmente de forma anual, lo
que permite contar con información más reciente sobre la evolución de la
movilidad en la ciudad.

Otra fuente relevante corresponde a los portales de datos abiertos de la
Secretaría Distrital de Movilidad. A través de estos portales se
publican diferentes conjuntos de datos relacionados con el sistema de
transporte urbano, incluyendo información sobre flujos vehiculares,
siniestros viales, aforos de tráfico y otros registros operativos.
Muchos de estos datasets son actualizados de manera periódica, de forma
anual, lo que los convierte en un recurso valioso para complementar la
información obtenida en las encuestas de movilidad.

Adicionalmente, en el ámbito de los estudios de movilidad urbana también
se utilizan conjuntos de datos derivados de dispositivos móviles, los
cuales permiten estimar patrones de desplazamiento a partir de registros
agregados de localización de teléfonos celulares. Este tipo de
información puede proporcionar estimaciones más dinámicas de los flujos
de movilidad entre diferentes zonas de la ciudad. Sin embargo, el acceso
a estos datasets suele estar restringido debido a consideraciones de
privacidad y propiedad de los datos.

== Justificación de la solución
<justificación-de-la-solución>
Como se ha descrito en las secciones anteriores, el análisis de la
movilidad urbana enfrenta diversas limitaciones relacionadas con la
dificultad de transformar datos reales de movilidad en escenarios de
simulación, así como con la complejidad técnica asociada al uso de
herramientas como SUMO. Estas problemáticas evidencian la necesidad de
contar con herramientas que permitan aprovechar de manera más efectiva
la información disponible y facilitar su utilización en procesos de
análisis y planificación del transporte.

En este contexto, el desarrollo del sistema propuesto adquiere
relevancia al abordar directamente estas limitaciones mediante la
automatización del proceso de generación de escenarios de simulación a
partir de datos provenientes de encuestas de movilidad. Al reducir la
cantidad de tareas manuales necesarias para preparar los datos y
configurar las simulaciones, la solución permite simplificar el flujo de
trabajo requerido para utilizar este tipo de herramientas.

Adicionalmente, la incorporación de un módulo web para la configuración
de escenarios y la visualización de resultados permite que los usuarios
puedan interactuar con el sistema de simulación de una forma más
accesible, facilitando la exploración de diferentes políticas de
movilidad y la interpretación de los resultados obtenidos.

De esta manera, la solución propuesta no solo permite aprovechar de
forma más eficiente los datos de movilidad existentes, sino que también
contribuye a ampliar el uso de herramientas de simulación en procesos de
análisis y planificación urbana. En consecuencia, el desarrollo de este
proyecto resulta relevante al proporcionar una herramienta que puede
apoyar la evaluación de escenarios de movilidad y contribuir a la toma
de decisiones informadas en materia de movilidad.

= Descripción general del proyecto
<descripción-general-del-proyecto>
== Objetivo general
<objetivo-general>
Diseñar e implementar un sistema de software que automatice la
generación de escenarios de simulación de movilidad urbana en SUMO a
partir de fuentes de datos de movilidad disponibles para Bogotá,
integrando un módulo web para la configuración de parámetros,
exploración de escenarios de política de transporte y visualización de
métricas, con el fin de facilitar el análisis de movilidad urbana a
entidades públicas, investigadores y consultores del sector.

== Objetivos específicos
<objetivos-específicos>
- Analizar y comparar las fuentes de datos de movilidad disponibles para
  Bogotá \(incluyendo los datos de la Encuesta de Movilidad 2023 y
  datasets complementarios como los mapas de densidad poblacional y
  movilidad del programa Data for Good de Meta) con el fin de determinar
  cuáles fuentes, o combinación de ellas, permiten construir matrices
  origen–destino suficientemente representativas para alimentar los
  escenarios de simulación, reconociendo las limitaciones de
  periodicidad y cobertura de cada fuente como parte del alcance del
  sistema.

- Desarrollar un módulo de procesamiento de datos que automatice la
  transformación de los registros de la encuesta en archivos de entrada
  válidos para SUMO, eliminando la necesidad de intervención manual en
  las etapas de generación de redes viales, matrices O/D y archivos de
  rutas.

- Implementar un módulo web que permita a usuarios no expertos en SUMO
  configurar y ejecutar simulaciones de movilidad, definir escenarios
  asociados a políticas de transporte \(como restricciones vehiculares o
  cambios en infraestructura) y comparar sus resultados frente a un
  escenario base.

- Desarrollar un componente de análisis que genere métricas e
  indicadores de movilidad a partir de los resultados de la simulación,
  como tiempos de viaje promedio y niveles de congestión por zona,
  presentados mediante visualizaciones accesibles para perfiles técnicos
  y no técnicos.

- Validar el sistema generando escenarios de simulación para al menos
  una localidad representativa de Bogotá, verificando la coherencia de
  los flujos simulados frente a los patrones de movilidad reportados en
  la encuesta.

= Citas
<citas>
+ El Tiempo, "Bogotá está entre las diez ciudades del mundo con más tráfico". Disponible en: #link("https://www.eltiempo.com/bogota/bogota-esta-entre-las-diez-ciudades-del-mundo-con-mas-trafico-la-congestion-subio-7-7-por-ciento-en-3527699")

+ Portafolio, "Bogotá, cada año con un tráfico que sigue empeorando". Disponible en: #link("https://www.portafolio.co/economia/regiones/bogota-cada-ano-con-un-trafico-que-sigue-empeorando-nivel-de-congestion-en-la-ciudad-crecio-7-7-en-487350")

+ Infobae, "Moverse en Bogotá se volvió una odisea: recorrer 5 kilómetros puede tomar hasta 40 minutos". Disponible en: #link("https://www.infobae.com/colombia/2026/03/05/moverse-en-bogota-se-volvio-una-odisea-recorrer-5-kilometros-puede-tomar-hasta-40-minutos/")

+ Alcaldía de Bogotá, "Más de 4 millones de personas se benefician con TransMilenio". Disponible en: #link("https://bogota.gov.co/mi-ciudad/movilidad/transmilenio-en-bogota-personas-beneficiadas-flota-viajes-y-mas")

+ Portafolio, "En transporte público y a pie: preferencias de transporte para los bogotanos en 2023". Disponible en: #link("https://www.portafolio.co/economia/regiones/en-transporte-publico-y-a-pie-asi-se-transportaron-los-bogotanos-en-2023-606118")
