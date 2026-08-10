// @brief: especificacion de la seccion descripcion global y sus subsecciones correspondientes

#let descripcionGlobal() = [

#align(center)[= Descripción Global]

En esta sección se describe el contexto general del producto de software, los factores que lo rodean y las características de los usuarios que lo
utilizarán. Esta descripción no constituye una especificación formal de requerimientos, sino el marco de referencia sobre el cual se construyen los
requerimientos específicos de la Seccion 3.

== Perspectiva del Producto

El *Pipeline* es un producto de software nuevo, sin precedente directo en el contexto de Bogotá. Si bien existen herramientas internacionales para la
conversión de datos de movilidad a formatos de simulación (como el convertidor VISUM-SUMO del propio DLR), ninguna de ellas está adaptada para las fuentes
de datos locales: la Encuesta de Movilidad de Bogotá, los aforos vehiculares HMD de la Secretaría Distrital de Movilidad y la red vial de OpenStreetMap
para la ciudad.

El sistema se justifica por la brecha existente entre la disponibilidad de datos y la capacidad de usarlos. Bogotá ocupa el séptimo lugar mundial en
congestión vehicular según el TomTom Traffic Index 2025, con velocidades promedio en horas pico que apenas superan los 15 km/h. Pese a ello, herramientas
de simulación de clase mundial como SUMO no son usadas sistemáticamente por los analistas de movilidad de la ciudad, precisamente porque la transformación
de los datos reales al formato que SUMO requiere es un proceso manual, técnicamente complejo y que puede tomar horas de trabajo especializado.

El sistema desarrollado está compuesto por dos módulos complementarios. El primero es un pipeline de procesamiento de datos que automatiza la
transformación de extremo a extremo: recibe como insumos la encuesta de movilidad y los datos de infraestructura vial, y produce los archivos listos para
ejecutar una simulación en SUMO. El segundo es un módulo web que permite visualizar los resultados producidos por SUMO de forma interactiva y configurar
nuevos escenarios de simulación desde una interfaz gráfica, eliminando la necesidad de editar archivos de configuración XML manualmente. El beneficio
principal para la Secretaría Distrital de Movilidad y para investigadores es poder explorar escenarios hipotéticos de movilidad sin intervención manual en
la preparación de datos ni en la interpretación de resultados.

=== Interfaces con el Sistema

El pipeline interactúa con los siguientes sistemas externos. Ninguno de ellos forma parte del sistema a desarrollar; todos son proveedores de datos o
herramientas que el pipeline invoca como procesos externos.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Sistema externo*], [*Tipo de interfaz*], [*Descripción de la interacción*]),
    [OpenStreetMap],
    [Descarga de datos (HTTPS)],
    [El pipeline descarga el dump OSM de Bogotá o consulta la API Overpass para extraer la red vial del polígono de Usaquén. Esta es la única comunicación
    de red del sistema; ocurre una única vez durante la fase de ingestión (F1).],

    [osmium-tool],
    [Proceso externo (CLI)],
    [Invocado por el pipeline para recortar el dump OSM al polígono de Usaquén y exportar el resultado en formato `.osm.pbf`. Se llama mediante subproceso
    de Python.],

    [netconvert (SUMO)],
    [Proceso externo (CLI)],
    [Herramienta oficial de SUMO invocada para convertir la red OSM al formato `.net.xml`. El pipeline construye el comando con los parámetros definidos
    en el archivo de configuración y captura su salida estándar para el log.],

    [duarouter (SUMO)],
    [Proceso externo (CLI)],
    [Herramienta oficial de SUMO invocada para asignar rutas a los viajes definidos en la matriz O/D, produciendo el archivo `.rou.xml`. Su ejecución es
    iniciada y monitoreada por el pipeline.],

    [SUMO],
    [Proceso externo (CLI)],
    [Motor de simulación que consume los artefactos producidos por el pipeline (`.net.xml`, `.taz.xml`, `.rou.xml`, `.vtype.xml`) para ejecutar la
    simulación. El pipeline no controla SUMO en tiempo real; la ejecución de SUMO y la recolección de resultados de aforo es un paso posterior al
    pipeline.],

    [Encuesta de Movilidad \ de Bogotá 2023],
    [Archivo XLSX (lectura)],
    [Fuente primaria de datos de demanda. El pipeline lee el archivo XLSX directamente desde disco. No hay comunicación en red con la Secretaría Distrital
    de Movilidad; el archivo se obtiene previamente del portal de datos abiertos de Bogotá.],

    [Base de datos de aforos HMD],
    [Archivo tabular (lectura)],
    [Fuente de datos de volúmenes vehiculares reales en Hora de Máxima Demanda para los
     puntos de aforo de Usaquén. Usada exclusivamente en la fase de validación (F5) para
     calcular el estadístico GEH.],
  ),
  caption: [Interfaces del IronWorks Mobility Pipeline con sistemas externos.]
) <tabInterfacesSistema>

=== Interfaces con el Usuario

El sistema ofrece dos formas de interacción:

*Línea de comandos (CLI):* el usuario lanza el pipeline desde una terminal con un comando Python al que puede pasar argumentos para seleccionar el período
horario, el modo de transporte y la localidad. El sistema imprime el progreso de cada fase en consola con mensajes de estado y marcas de tiempo.

*Archivo de configuración YAML:* los parámetros avanzados del pipeline (rutas de archivos de entrada, umbrales de validación, parámetros de netconvert,
factor de escala de demanda) se definen en un archivo `config.yaml` que el usuario edita con cualquier editor de texto antes de ejecutar el pipeline.

*Módulo web (interfaz gráfica):* el sistema dispone de una interfaz web accesible desde el navegador que permite: (1) visualizar de forma interactiva los
resultados producidos por SUMO, incluyendo métricas de congestión, tiempos de viaje y flujos vehiculares por segmento; y (2) parametrizar y lanzar nuevas
simulaciones definiendo variables como el escenario geográfico, el período horario y los modos de transporte activos, sin necesidad de editar archivos XML
ni usar la línea de comandos.

=== Interfaces con el Hardware

El pipeline opera sobre una máquina de escritorio o servidor de cómputo convencional. Los requisitos mínimos de hardware están determinados por las fases
más intensivas en memoria y cómputo: la construcción de la matriz O/D sobre #{sym.tilde.basic}500 000 registros (F2) y la ejecución de netconvert sobre la
red vial de Usaquén (F3).

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Componente*], [*Especificación mínima*]),
    [Memoria RAM], [8 GB. Requeridos para la carga en memoria del dataset de la encuesta, los polígonos geoespaciales y la red vial OSM simultáneamente
    durante la fase F2.],

    [Procesador], [4 núcleos físicos a $>=$ 2.0 GHz. netconvert y duarouter utilizan procesamiento paralelo internamente.],

    [Almacenamiento], [$>=$ 10 GB libres. El dump OSM de Bogotá ocupa aproximadamente 2 GB; los artefactos de salida y datos intermedios en requieren
    hasta 5 GB adicionales.],

    [Red], [Acceso a Internet (HTTPS, puerto 443) requerido únicamente durante la descarga inicial de la red OSM. Las fases F2–F5 operan completamente
    offline.],

    [Sistema Operativo], [Ubuntu 22.04, macOS 13+ o Windows 10+. No se requieren controladores especiales ni hardware propietario.],
  ),
  caption: [Requisitos mínimos de hardware.]
) <tabHardwareDesc>

No se requieren tarjetas gráficas dedicadas, aceleradores GPU, dispositivos de red especiales ni hardware de tiempo real.

=== Interfaces con el Software

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    table.header([*Producto de Software*], [*Versión*], [*Fuente*], [*Propósito en el sistema*]),
    [Python],
    [3.11],
    [python.org],
    [Lenguaje de implementación del pipeline ETL completo. Requerido por la API TraCI de SUMO para el control de simulaciones.],

    [SUMO],
    [1.19+],
    [sumo.dlr.de],
    [Provee las herramientas netconvert, duarouter y el motor de simulación. Licencia EPL 2.0 (código abierto).],

    [pandas],
    [2.0+],
    [pypi.org],
    [Procesamiento de los datos tabulares de la encuesta de movilidad: lectura XLSX, limpieza, filtrado y construcción de matrices O/D.],

    [geopandas],
    [0.14+],
    [pypi.org],
    [Procesamiento de datos geoespaciales: manejo de polígonos UPZ, asignación de nodos de red a zonas TAZ, validación de cobertura geográfica.],

    [osmium-tool],
    [1.16+],
    [osmcode.org],
    [Extracción del polígono de Usaquén desde el dump OSM de Bogotá mediante recorte geográfico. Invocado como proceso externo desde Python.],

    [pytest],
    [7.0+],
    [pypi.org],
    [Ejecución de pruebas unitarias y de integración del pipeline. Integrado con GitHub Actions para CI automático en cada commit.],

    [GitHub Actions],
    [--],
    [github.com],
    [Integración continua: ejecuta pylint, pytest y verifica portabilidad en Ubuntu y Windows en cada commit a la rama principal.],

    [Git],
    [2.40+],
    [git-scm.com],
    [Control de versiones del código fuente y los documentos del proyecto.],

    [QGIS],
    [3.34+],
    [qgis.org],
    [Validación visual de la red vial generada y de los polígonos TAZ. Usado en la fase de verificación, no en el pipeline automatizado.],

    [Ubuntu 22.04 / \ macOS 13+ / \ Windows 10+],
    [--],
    [--],
    [Sistemas operativos soportados. El pipeline debe ejecutarse sin modificaciones en los tres entornos (ver RNF-PORT-001).],

    [FastAPI], [0.100+], [pypi.org], [Backend del módulo web. Expone los resultados de SUMO mediante una API REST consumida por el frontend. Integrado con
    el pipeline ETL existente.],

    [Jinja2 / HTML+JS], [--], [--], [Frontend del módulo web. Interfaz gráfica accesible desde el navegador para visualización de resultados y
    parametrización de simulaciones.]
  ),
  caption: [Interfaces con el software.]
) <tabInterfacesSoftware>

Todas las herramientas y bibliotecas listadas son de código abierto o de uso académico gratuito, en cumplimiento de la restricción de licencias del SPMP.

=== Interfaces de Comunicación

El pipeline no implementa comunicación en red durante su operación principal. El único protocolo de red utilizado es *HTTPS sobre el puerto 443*,
exclusivamente durante la descarga inicial de la red vial desde OpenStreetMap (API Overpass o descarga directa del dump OSM). Una vez que los datos de
entrada están disponibles en disco, todas las fases del pipeline (F2 a F5) operan completamente offline. No se utilizan sockets, APIs REST, bases de datos
remotas ni ningún otro protocolo de comunicación.

=== Restricciones de Memoria

Los requerimientos de memoria del sistema se derivan de la suma de las necesidades de las bibliotecas y procesos que el pipeline invoca simultáneamente:

- *Python 3.11 + pandas + geopandas:* carga del dataset completo de la encuesta
  (#{sym.tilde.basic}500,000 registros #sym.ast.basic 30 columnas) en memoria: aproximadamente 2-3 GB de RAM en el
  peor caso.
- *osmium-tool / netconvert:* procesamiento de la red vial de Bogotá en formato OSM:
  aproximadamente 1-2 GB adicionales durante la fase F3.
- *Sistema operativo y procesos base:* reserva de 1-2 GB.
- *Total estimado:* 6-7 GB de RAM en uso simultáneo en el pico de la fase F2/F3,
  dentro del límite mínimo establecido de 8 GB (ver @tabHardwareDesc).

El almacenamiento secundario requerido se detalla en la @tabHardwareDesc. No hay requerimientos especiales de memoria de video ni caché de red.

=== Operaciones

El pipeline opera en un único modo, sin distinción de roles de administrador y usuario final:

*Ejecución completa:* el usuario lanza el pipeline con los parámetros de configuración deseados y el sistema ejecuta las fases F1 a F5 en secuencia,
produciendo todos los artefactos de salida. El tiempo estimado de ejecución completa es de hasta 4 horas en la máquina de referencia (ver RD-001).

*Ejecución parcial (reanudación):* si una ejecución previa fue interrumpida, el usuario puede reanudar desde la última fase completada usando el flag
#sym.hyph#sym.hyph#text(fill:olive)[resume]. El sistema carga el checkpoint guardado y continúa sin reprocesar las fases anteriores (ver RF-016).

*Ejecución de escenario hipotético:* el usuario modifica el archivo `config.yaml` (por ejemplo, ajustando el factor de escala de demanda o el período
horario) y relanza el pipeline para generar un conjunto de artefactos distinto sin modificar el código fuente (ver RF-013).

No se definen períodos de mantenimiento ni ventanas de inactividad programadas, dado que el sistema es una herramienta de escritorio de uso bajo demanda.
El respaldo de datos está delegado al sistema de control de versiones Git y a las copias locales de los datasets de entrada.

=== Requerimientos de Adaptación del Sitio

El pipeline no requiere adaptaciones de infraestructura de red ni de hardware en el sitio de uso. Para adaptar el sistema a una localidad distinta de
Usaquén (uso futuro), el usuario debe:

- Actualizar el polígono geográfico de recorte en el archivo `config.yaml`.
- Proveer los archivos de aforos HMD para la nueva localidad.
- Verificar que las UPZ de la nueva localidad estén disponibles en la fuente de datos geoespaciales oficial.

No se requieren cambios en el código fuente para la adaptación geográfica, lo cual es un objetivo de diseño explícito del sistema.

== Funciones del Producto

El pipeline está organizado en cinco funcionalidades principales (F1–F5) que corresponden a las fases del proceso ETL. A continuación se describe cada una
en lenguaje de usuario. Los casos de uso asociados se documentan en detalle en el documento SDD.

*F1 -- Ingestión y Validación de Datos:* el sistema recibe la Encuesta de Movilidad 2023 en formato XLSX/CSV y los archivos de aforos HMD, valida que
contienen las columnas mínimas requeridas, elimina registros duplicados por doble conteo y descarta registros con campos obligatorios vacíos, registrando
en un log el porcentaje de datos descartados. También descarga la red vial de Usaquén desde OpenStreetMap si no está disponible localmente.

*F2 -- Construcción de Matrices Origen-Destino:* con los datos limpios y expandidos por los factores muestrales de la encuesta, el sistema construye
matrices O/D separadas por modo de transporte (automóvil, bus SITP, motocicleta, bicicleta) y por período horario (AM: 6-9h, PM: 16-19h, nocturno:
21-24h), exportando cada combinación en el formato `.od` que SUMO requiere.

*F3 -- Generación de Red Vial y Zonas TAZ:* el sistema convierte la red OSM de Usaquén al formato `.net.xml` de SUMO usando netconvert, y construye el
archivo de zonas de análisis de tráfico (`.taz.xml`) asociando cada UPZ de la localidad con los nodos de la red vial que le corresponden.

*F4 -- Generación de Archivos de Simulación:* el sistema produce el archivo de tipos de vehículo (`.vtype.xml`) con los parámetros físicos estándar de
SUMO para cada modo, e invoca duarouter para asignar rutas a los viajes de la matriz O/D, generando el archivo de rutas (`.rou.xml`).

*F5 -- Variación Paramétrica y Validación:* el sistema permite generar múltiples conjuntos de artefactos variando los parámetros del archivo de
configuración sin modificar el código, habilitando la exploración de escenarios hipotéticos. Una vez ejecutada la simulación en SUMO, el sistema compara
los volúmenes simulados con los aforos reales HMD calculando el estadístico GEH para cada punto de aforo y exportando el resultado en un archivo CSV.

*F6 -- Módulo Web:* el sistema dispone de una interfaz web que permite a los usuarios visualizar de forma interactiva los resultados producidos por SUMO
(métricas de congestión, tiempos de viaje, flujos por segmento y niveles de servicio) y configurar nuevos escenarios de simulación desde el navegador,
especificando parámetros como el período horario, los modos de transporte activos y el factor de escala de demanda.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Funcionalidad*], [*Casos de uso*], [*Artefactos producidos*]),

    [F1 -- Ingestión], [CU-01], [`encuesta_limpia.parquet`, `pipeline.log`],
    [F2 -- Matrices O/D], [CU-02], [`od_auto_AM.od`, `od_bus_PM.od`, #sym.dots (N modos *#sym.ast* 3 períodos)],
    [F3 -- Red y TAZ], [CU-03], [`usaquen.net.xml`, `usaquen.taz.xml`],
    [F4 -- Simulación], [CU-04], [`vehiculos.vtype.xml`, `rutas.rou.xml`],
    [F5 -- Escenarios/Val.], [CU-05, CU-06], [`validacion_geh.csv`, conjuntos de artefactos por escenario],
    [F6 -- Módulo Web], [CU-07, CU-08], [Interfaz web de visualización de resultados SUMO y formulario de parametrización de nuevas simulaciones]
  ),
  caption: [Funciones del producto y artefactos generados.]
) <tabFunciones>

== Características del Usuario

Se identifican dos clases de usuarios que interactuarán con el pipeline en la versión 1.0:

#figure(
  table(
    columns: (15%, 15%, 30%, 20%, 30%),
    table.header(
      [*Clase de usuario*],
      [*Nivel de privilegios*],
      [*Rol*],
      [*Frecuencia de uso*],
      [*Perfil técnico*],
    ),

    [Investigador/Analista de datos],
    [Usuario estándar],
    [Ejecuta el pipeline con distintas configuraciones para generar escenarios de movilidad y analizar los resultados de simulación.],
    [Ocasional (por campaña de análisis, no diaria)],
    [Conocimiento de Python a nivel de usuario (puede editar `config.yaml` y ejecutar comandos en terminal). No requiere conocimiento profundo del código
    fuente. Familiaridad con conceptos de movilidad urbana y matrices O/D.],

    [Desarrollador del equipo],
    [Desarrollador],
    [Implementa, prueba y mantiene el pipeline. Ejecuta el sistema durante el desarrollo para verificar la correcta generación de artefactos.],
    [Frecuente (diaria durante el desarrollo; semanal durante mantenimiento)],
    [Dominio de Python 3.11, pandas, geopandas, SUMO y Git. Capacidad de modificar el código fuente, escribir pruebas unitarias con pytest y depurar
    errores del pipeline.],

    [Planificador / Analista de movilidad (no técnico)],
    [Usuario estándar],
    [Consume los resultados de simulación a través del módulo web y configura nuevos escenarios sin necesidad de usar la línea de comandos.],
    [Ocasional (por campaña de análisis)],
    [Sin conocimiento de Python ni de SUMO. Familiaridad con conceptos de movilidad urbana. Accede al sistema únicamente a través de la interfaz web.]
  ),
  caption: [Características de las clases de usuario.]
) <tabUsuarios>

== Restricciones

=== Restricciones Generales

- El alcance geográfico del sistema está limitado a la localidad de Usaquén de Bogotá para la versión 1.0. El diseño debe facilitar la extensión a otras
  localidades sin modificar el código fuente (solo `config.yaml`).
- El pipeline es un proceso monousuario, secuencial y de línea de comandos. No soporta ejecuciones concurrentes sobre los mismos datos de entrada.
- El idioma de los mensajes de log, comentarios del código y documentación es el español. Las variables y funciones del código siguen nomenclatura en
  inglés (PEP 8).
- El sistema no implementa tolerancia a fallos de hardware (corte de energía, fallo de disco). La recuperación ante estos eventos se limita al mecanismo
  de checkpoint (RF-016).

=== Restricciones de Software

- *Lenguaje de programación:* Python 3.11 exclusivamente en el pipeline principal.
- *Licencias:* todas las bibliotecas deben ser de código abierto o uso académico gratuito. No se permiten licencias comerciales (restricción del SPMP).
- *Herramientas SUMO:* la generación de la red y las rutas debe realizarse con netconvert y duarouter. No se reimplementan estas funcionalidades en
  Python.
- *Sin base de datos relacional:* el almacenamiento intermedio es por archivos en disco (Parquet, CSV, XML). No se usa PostgreSQL, SQLite ni ningún motor
  de BD.
- *Sin interfaz web:* no se implementa frontend en esta versión (requerimiento diferido).

=== Restricciones de Hardware

- La máquina de ejecución debe cumplir los requisitos mínimos definidos en la @tabHardwareDesc (8 GB RAM, 4 núcleos, $>=$ 10 GB libres).
- El pipeline no requiere GPU ni hardware especializado.
- El tiempo máximo de ejecución completa es de 4 horas en la máquina de referencia (RD-001). En máquinas que no cumplan los mínimos, el tiempo puede ser
  mayor y el sistema no garantiza el requerimiento de desempeño.

== Modelo del Dominio

El modelo del dominio del *IronWorks Mobility Pipeline* representa las entidades del mundo real que el sistema maneja, transforma y produce. No es un
modelo de clases de software sino una representación conceptual del dominio de movilidad urbana y simulación de tráfico.

#figure(
  image("/figures/grafico-modelo-dominio.png"),
  caption: [Gráfico modelo de dominio. ]
)<figModeloDominio>

Las entidades centrales del dominio y sus relaciones son:

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([*Entidad*], [*Descripción*], [*Fuente / Artefacto*]),

    [Viaje], [Desplazamiento de un hogar entre una zona de origen y una de destino, registrado en la encuesta con su modo de transporte, hora de inicio y
    factor de expansión muestral.], [Encuesta 2023 (XLSX)],

    [Zona TAZ / UPZ], [Unidad geográfica de análisis de tráfico. En este proyecto corresponde a las UPZ de Usaquén. Conecta los viajes de la encuesta con
    los nodos de la red vial.], [Shapefile oficial de UPZ],

    [Matriz O/D], [Estructura que agrega los viajes expandidos entre pares de zonas TAZ, diferenciada por modo y período horario. Es el principal insumo
    de demanda para SUMO.], [`.od` (generado)],

    [Red Vial], [Conjunto de nodos (intersecciones) y aristas (segmentos de vía) de Usaquén, con atributos de velocidad, prioridad y tipo de carretera.],
    [OSM #sym.arrow `.net.xml`],

    [Tipo de Vehículo], [Modelo paramétrico que describe el comportamiento físico de un modo de transporte en la simulación: velocidad máxima,
    aceleración, deceleración y longitud.], [`.vtype.xml` (generado)],

    [Ruta], [Secuencia de aristas de la red vial asignada por duarouter a un viaje de la matriz O/D para representar el trayecto dentro de la
    simulación.], [`.rou.xml` (generado)],

    [Punto de Aforo], [Ubicación física en Usaquén donde la Secretaría de Movilidad registra conteos vehiculares reales en Hora de Máxima Demanda. Usado
    para validar la simulación.], [Base HMD],

    [Escenario de Simulación], [Conjunto completo de artefactos SUMO (red, TAZ, rutas, tipos de vehículo) que define una configuración específica de la
    simulación. Distintos escenarios se generan variando los parámetros del pipeline.], [Conjunto de archivos generados],
  ),
  caption: [Entidades del modelo del dominio.]
) <tabModeloDominio>

Las relaciones clave entre entidades son: un *Viaje* pertenece a una *Zona TAZ* de origen y una de destino; múltiples *Viajes* agregados forman una
*Matriz O/D*; una *Matriz O/D* es asignada sobre una *Red Vial* para producir *Rutas*; las *Rutas* junto con los *Tipos de Vehículo* conforman un
*Escenario de Simulación*; los resultados del escenario se contrastan con los *Puntos de Aforo* reales para producir la métrica GEH de validación.

== Suposiciones y Dependencias

Las siguientes suposiciones pueden afectar los requerimientos si resultan ser incorrectas:

- La Encuesta de Movilidad de Bogotá 2023 y la base de datos de aforos HMD son accesibles y tienen calidad suficiente para construir matrices O/D
  representativas de Usaquén. Si la cobertura de UPZ en la encuesta fuera muy baja para Usaquén, los volúmenes de la matriz O/D no serían estadísticamente
  confiables.
- La red vial de OpenStreetMap para Usaquén tiene atributos suficientes (tipo de vía, velocidades, conectividad) para generar una red simulable en SUMO.
  Si la cobertura fuera deficiente, sería necesario enriquecerla manualmente con QGIS.
- SUMO 1.19 soporta todos los modos de transporte a modelar (automóvil, bus SITP, motocicleta, bicicleta) con los parámetros por defecto. Cambios en la
  API de SUMO en versiones posteriores podrían requerir ajustes en el pipeline.
- Los cuatro integrantes del equipo están disponibles durante las 16 semanas del proyecto con una dedicación aproximada de 10 horas semanales por persona.
- La máquina de cómputo disponible cumple los requisitos mínimos definidos en la @tabHardwareDesc. Si no los cumple, el requerimiento RD-001 (pipeline en
  $<=$ 4 horas) no puede garantizarse.

== Distribución de Requerimientos

Los requerimientos de la Sección 3 se distribuyen entre los módulos del pipeline de la siguiente manera, lo que facilita su localización para verificación
y mantenimiento:

#figure(
  table(
    columns: (2fr,3fr,4fr),
    table.header([*Módulo*], [*Requerimientos asociados*], [*Descripción del módulo*]),

    [`etl/ingestion.py`], [RF-001, RF-002, RF-003, RF-004, RF-005, \ RNF-CON-001], [Lectura, validación y limpieza del dataset de la encuesta y descarga
    de la red OSM.],

    [`etl/od_builder.py`], [RF-006, RF-007, RF-008, RNF-SEG-001], [Construcción y exportación de matrices O/D por modo y período horario.],

    [`etl/network.py`], [RF-009, RF-010], [Invocación de netconvert y construcción del archivo de zonas TAZ.],

    [`etl/simulation.py`], [RF-011, RF-012], [Generación del archivo `.vtype.xml` e invocación de duarouter.],

    [`etl/config.py`], [RF-013], [Lectura y validación del archivo `config.yaml`; soporte a variación paramétrica.],

    [`etl/validation.py`], [RF-014], [Comparación de volúmenes simulados vs. aforos HMD y cálculo del estadístico GEH.],

    [`etl/logger.py`], [RF-015, RNF-OBS-001], [Registro estructurado de eventos del pipeline en consola y archivo.],

    [`etl/checkpoint.py`], [RF-016, RNF-CON-002], [Persistencia del estado por fase y reanudación de ejecuciones interrumpidas.],

    [Pipeline completo], [RD-001, RD-002, RNF-PORT-001, RNF-PORT-002, RNF-REP-001], [Requerimientos que aplican al sistema como un todo, verificados en
    CI o en prueba de integración completa.],

    [`web/api.py`], [RF-017, RF-018], [Backend REST del módulo web. Expone los resultados de SUMO y recibe parámetros de configuración para nuevas
    simulaciones.],

    [`web/frontend/`], [RF-019, RF-020], [Frontend del módulo web. Visualización de resultados y formulario de parametrización de simulaciones.]
  ),
  caption: [Distribución de requerimientos por módulo del pipeline.]
) <tabDistribucion>

]
