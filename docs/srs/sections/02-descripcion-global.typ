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
    columns: (1fr, 1fr, 3fr),
    table.header([*Sistema externo*], [*Tipo de interfaz*], [*Descripción de la interacción*]),
    [OpenStreetMap],
    [Descarga de datos (HTTPS)],
    [La red vial del polígono de Usaquén se descargó una vez en los notebooks de la Fase 2 y se versiona en `data/processed/`. El pipeline no se
    conecta a OpenStreetMap al correr. `python -m etl.sumo.evidencia` consulta Overpass (con un espejo) para los colegios, centros de salud y huellas de
    edificios, y los guarda también en `data/processed/`.],

    [osmium-tool],
    [Proceso externo (CLI)],
    [Previsto para recortar el dump OSM de Bogotá al polígono de Usaquén. El código actual no lo invoca: el recorte se hizo en los notebooks.],

    [netconvert (SUMO)],
    [Proceso externo (CLI)],
    [Herramienta oficial de SUMO. La red de Usaquén se generó con ella en los notebooks. La API la invoca además para recortar zonas alrededor de un
    cruce (`subred.py`) y para instalar el semáforo propuesto (`semaforo_nuevo.py`).],

    [duarouter (SUMO)],
    [Proceso externo (CLI)],
    [Herramienta oficial de SUMO invocada para asignar rutas a los viajes TAZ a TAZ (`.trips.xml`), produciendo el archivo `.rou.xml`. El pipeline
    la inicia y mide su avance por el último `depart` escrito.],

    [SUMO],
    [Proceso externo (CLI)],
    [Motor de simulación que consume los artefactos del pipeline (`.net.xml`, `.taz.xml` y un `.rou.xml` que ya incluye los vTypes). El pipeline lo
    ejecuta y lo controla por TraCI (ver más abajo). La recolección de resultados de aforo para el GEH está pendiente (RF-014).],

    [Encuesta de Movilidad \ de Bogotá 2023],
    [Archivo XLSX (lectura en notebooks) y TSV (lectura en el pipeline)],
    [Fuente primaria de datos de demanda. Los notebooks de la Fase 2 limpian el XLSX y producen `viajes_usaquen_internos.tsv`, que es lo que lee el
    pipeline. No hay comunicación en red con la Secretaría Distrital de Movilidad; el archivo se obtiene previamente del portal de datos abiertos de
    Bogotá.],

    [Base de datos de aforos HMD],
    [Archivo tabular (lectura)],
    [Fuente de datos de volúmenes vehiculares reales en Hora de Máxima Demanda para los
     puntos de aforo de Usaquén. Usada exclusivamente en la fase de validación (F5) para
     calcular el estadístico GEH.],

    [TraCI (SUMO)],
    [Socket TCP local],
    [La API controla SUMO paso a paso para medir el avance de las corridas y, en el simulador 3D, para correr dos simulaciones en lockstep, leer el
    estado de cada actor e inyectar el actor seguido.],

    [`cutRoutes.py` / `randomTrips.py`],
    [Proceso externo (Python)],
    [Herramientas de SUMO para recortar la demanda real a una zona y generar el tráfico de fondo por modo de las comparaciones 3D.],

    [Microsoft Building Footprints],
    [Archivo GeoJSON (lectura)],
    [Huellas de edificios de Usaquén (`data/processed/edificios_ms.geojson`) que se extruyen en la escena 3D, junto con las de OpenStreetMap
    (`edificios_osm.geojson`).],

    [Secretaría Distrital de Movilidad (ArcGIS FeatureServer)],
    [Descarga de datos (HTTPS)],
    [Histórico de siniestros georreferenciados, filtrado a Usaquén y versionado en `data/processed/siniestros_usaquen.geojson`. Es evidencia de la
    priorización de cruces (RF-032, RF-045).],

    [Mapbox / OpenStreetMap tiles],
    [HTTPS (navegador)],
    [Mapas base del visor: Mapbox para el mapa principal de kepler.gl y teselas de OpenStreetMap para el minimapa del simulador 3D.],
  ),
  caption: [Interfaces del sistema con sistemas externos.]
) <tabInterfacesSistema>

=== Interfaces con el Usuario

El sistema ofrece dos formas de interacción:

*Visor web (interfaz principal):* aplicación en el navegador que permite:
+ ver los viajes simulados animados sobre el mapa de Usaquén;
+ parametrizar y lanzar corridas (preset, conteos por modo, semilla, estilo de conducción, cierres viales) y seguir su avance;
+ consultar y configurar intersecciones semaforizadas (ficha, programa, Webster, comparación);
+ ver la priorización de cruces sin semáforo;
+ abrir el simulador 3D comparativo de un semáforo propuesto, con pantalla partida, cámara en tercera persona, HUD de datos y minimapa 2D.

*Línea de comandos (CLI):* reservada al equipo de desarrollo para ejecutar el pipeline por defecto (`python -m etl.etl`), regenerar las simulaciones
precalculadas (`python -m etl.precalculadas`) y levantar la API y el visor.

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
    columns: (2fr, 1fr, 1fr, 4fr),
    table.header([*Producto de Software*], [*Versión*], [*Fuente*], [*Propósito en el sistema*]),
    [Python],
    [3.11],
    [python.org],
    [Lenguaje de implementación del pipeline ETL completo. Requerido por la API TraCI de SUMO para el control de simulaciones.],

    [SUMO (`eclipse-sumo`)],
    [1.27.1],
    [pypi.org],
    [Provee las herramientas netconvert, duarouter, `cutRoutes.py`, `randomTrips.py` y el motor de simulación. Licencia EPL 2.0 (código abierto).],

    [pandas],
    [2.2.3+],
    [pypi.org],
    [Procesamiento de los datos tabulares de la encuesta de movilidad en los notebooks: lectura XLSX, limpieza y filtrado. No lo usa `simulation-service`.],

    [geopandas],
    [0.14.4+],
    [pypi.org],
    [Procesamiento de datos geoespaciales: manejo de polígonos UPZ, asignación de nodos de red a zonas TAZ, validación de cobertura geográfica.],

    [osmium-tool],
    [1.16+],
    [osmcode.org],
    [Opcional, previsto para recortar el dump OSM de Bogotá. El código actual no lo invoca.],

    [pytest],
    [9.1.1],
    [pypi.org],
    [Ejecución de las pruebas de `simulation-service/test/` (121 pruebas). El CI solo ejecuta las pruebas de la raíz, que son un marcador de posición.],

    [GitHub Actions],
    [--],
    [github.com],
    [Integración continua: en cada push o pull request a `main` o `develop` ejecuta pytest sobre `tests/` y `pylint src/ --exit-zero` en Ubuntu. No
    corre en Windows ni ejecuta las pruebas de `simulation-service/`.],

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

    [FastAPI], [0.136.3], [pypi.org], [Backend del módulo web. Expone los resultados de SUMO mediante una API REST consumida por el frontend. Integrado con
    el pipeline ETL existente.],

    [TraCI / sumolib], [1.27.1], [pypi.org], [Control en vivo de SUMO y lectura de la red desde Python.],

    [pyproj], [3.8.0], [pypi.org], [Conversión entre las coordenadas de la red de SUMO (UTM) y lon/lat.],

    [React + Vite], [18.3 / 6], [npmjs.com], [Frontend del módulo web (visor `kepler/`).],

    [kepler.gl], [3.1], [npmjs.com], [Mapa animado de viajes y capas de semáforos y priorización.],

    [three.js], [0.169.0], [npmjs.com], [Render 3D del simulador comparativo.],

    [maplibre-gl], [4.7.1], [npmjs.com], [Minimapa 2D del simulador con teselas de OpenStreetMap.]
  ),
  caption: [Interfaces con el software.]
) <tabInterfacesSoftware>

Todas las herramientas y bibliotecas listadas son de código abierto o de uso académico gratuito, en cumplimiento de la restricción de licencias del SPMP.

=== Interfaces de Comunicación

El pipeline de datos opera offline. El sistema completo usa:
- HTTP REST con JSON entre el visor y la API (`localhost:8000`, a través del proxy `/api` de Vite);
- un WebSocket para el simulador 3D;
- TraCI sobre TCP local entre la API y SUMO;
- HTTPS hacia los proveedores de mapas base.

El detalle está en la tabla de interfaces de comunicaciones de la Sección 3.

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

*Ejecución completa:* el desarrollador lanza `python -m etl.etl`, o el usuario una corrida desde el visor, y el sistema genera los viajes, calcula las rutas,
simula y exporta los resultados. Las fases de preparación de datos (F1 y parte de F2 y F3) se ejecutan antes en los notebooks. El tiempo estimado de ejecución completa es de hasta 4 horas en la máquina de referencia (ver RD-001).

*Ejecución parcial (reanudación):* prevista, aún no implementada. Se planeó reanudar desde la última fase completada con un flag
#sym.hyph#sym.hyph#text(fill:olive)[resume] y un checkpoint por fase (ver RF-016, pendiente).

*Ejecución de escenario hipotético:* el usuario cambia en el panel Demanda el preset, los conteos por modo, la semilla, el estilo de conducción o los
cierres viales, y lanza una corrida nueva sin tocar el código (ver RF-013 y RF-021 a RF-024). No existe un `config.yaml`.

*Uso interactivo (v2.0):* el usuario abre el visor, carga una simulación (precalculada o propia), lanza nuevas corridas desde el panel, explora
intersecciones y abre comparaciones 3D. La API ejecuta una corrida a la vez y como máximo dos comparaciones 3D simultáneas.

No se definen períodos de mantenimiento ni ventanas de inactividad programadas, dado que el sistema es una herramienta de escritorio de uso bajo demanda.
El respaldo de datos está delegado al sistema de control de versiones Git y a las copias locales de los datasets de entrada.

=== Requerimientos de Adaptación del Sitio

El pipeline no requiere adaptaciones de infraestructura de red ni de hardware en el sitio de uso. Para adaptar el sistema a una localidad distinta de
Usaquén (uso futuro), el usuario debe:

- Repetir la preparación de datos de los notebooks (encuesta, red, TAZ) para la nueva localidad y dejar los resultados en `scenarios/<nombre>/`.
- Proveer los archivos de aforos HMD para la nueva localidad.
- Verificar que las UPZ de la nueva localidad estén disponibles en la fuente de datos geoespaciales oficial.

La adaptación geográfica es un objetivo de diseño. Hoy la ventana horaria (`HORA_INI`, `HORA_FIN`) y los nombres de los archivos del escenario están
en `configuration.py`, y la API solo expone el escenario `default`.

== Funciones del Producto

El pipeline está organizado en cinco funcionalidades principales (F1–F5) que corresponden a las fases del proceso ETL, más cuatro del módulo web (F6–F9).
A continuación se describe cada una en lenguaje de usuario. Los casos de uso asociados se documentan en detalle en el documento SDD.

*Nota de implementación (v2.2):* F1, la matriz O/D de F2 y la construcción de la red y las TAZ de F3 se resolvieron en los notebooks de la Fase 2, y sus
resultados se versionan en `data/processed/`. El código de `simulation-service` empieza en el TSV de viajes: genera viajes TAZ a TAZ (no archivos `.od`),
los rutea con duarouter y simula. Por eso los artefactos `.parquet`, `.od`, `.vtype.xml` y `validacion_geh.csv` de la @tabFunciones son los previstos
originalmente; los reales son `.trips.xml`, `.rou.xml` (con los vTypes dentro) y los GeoJSON de salida.

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

*F7 -- Validación y Reportes:* comparación de los volúmenes simulados contra los aforos reales (GEH) y registro de la ejecución.

*F8 -- Intersecciones y Semaforización:*
- consultar cada intersección semaforizada (accesos, volúmenes y fases);
- recortar la red a una zona alrededor de un cruce;
- editar el programa del semáforo o calcularlo con Webster, y comparar programas;
- ver una priorización de los cruces sin semáforo donde podría valer la pena instalar uno.

*F9 -- Simulador 3D Comparativo:* para un cruce sin semáforo, el sistema prepara el escenario actual y una variante con un semáforo propuesto y los
simula a la par, mostrándolos lado a lado en 3D con la red, los edificios y los actores reales de la zona. El usuario sigue en tercera persona a un
vehículo o peatón y ve su velocidad, su riesgo, la acción que toma y las decisiones posibles en el próximo cruce. Un minimapa 2D lo ubica en la
ciudad.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Funcionalidad*], [*Casos de uso*], [*Artefactos producidos*]),

    [F1 -- Ingestión], [CU-01], [`encuesta_limpia.parquet`, `pipeline.log`],
    [F2 -- Matrices O/D], [CU-02], [`od_auto_AM.od`, `od_bus_PM.od`, #sym.dots (N modos *#sym.ast* 3 períodos)],
    [F3 -- Red y TAZ], [CU-03], [`usaquen.net.xml`, `usaquen.taz.xml`],
    [F4 -- Simulación], [CU-04], [`vehiculos.vtype.xml`, `rutas.rou.xml`],
    [F5 -- Escenarios/Val.], [CU-05, CU-06], [`validacion_geh.csv`, conjuntos de artefactos por escenario],
    [F6 -- Módulo Web], [CU-07, CU-08], [Interfaz web de visualización de resultados SUMO y formulario de parametrización de nuevas simulaciones],
    [F8 -- Intersecciones], [CU-09 a CU-11], [Ficha de intersección, programas `programa_<tl>_<id>.xml`, zonas `runs/zona-*`, tabla de comparación,
    capa de priorización],
    [F9 -- Simulador 3D], [CU-12], [`runs/sem-*` (zona, variante con semáforo, demanda), frames en vivo por WebSocket, vista 3D partida con HUD y
    minimapa]
  ),
  caption: [Funciones del producto y artefactos generados.]
) <tabFunciones>

== Características del Usuario

Se identifican tres clases de usuarios que interactúan con el sistema:

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
    [Conocimiento de Python a nivel de usuario (puede ejecutar comandos en terminal y usar el visor). No requiere conocimiento profundo del código
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

- El alcance geográfico del sistema está limitado a la localidad de Usaquén de Bogotá. El diseño debe facilitar la extensión a otras localidades, que hoy
  exige preparar los insumos del escenario (ver Requerimientos de Adaptación del Sitio).
- El pipeline es un proceso monousuario y secuencial: la API ejecuta una corrida a la vez y como máximo dos comparaciones 3D simultáneas.
- El idioma de los mensajes, los comentarios, los identificadores del código (por ejemplo `filas_invalidas`, `viajes_generados`) y la documentación es el
  español. El estilo del código sigue PEP 8.
- El sistema no implementa tolerancia a fallos de hardware (corte de energía, fallo de disco). Una corrida que falla deja su error en `estado.json`; el
  mecanismo de checkpoint (RF-016) está pendiente.

=== Restricciones de Software

- *Lenguaje de programación:* Python 3.11 o superior en el pipeline y la API; JavaScript (React) en el visor.
- *Licencias:* todas las bibliotecas deben ser de código abierto o uso académico gratuito. No se permiten licencias comerciales (restricción del SPMP).
- *Herramientas SUMO:* la generación de la red y las rutas debe realizarse con netconvert y duarouter. No se reimplementan estas funcionalidades en
  Python.
- *Sin base de datos relacional:* el almacenamiento es por archivos en disco (TSV, XML, JSON, GeoJSON). No se usa PostgreSQL, SQLite ni ningún motor
  de BD.
- *Interfaz web:* el frontend es una aplicación React; requiere un navegador con WebGL 2 para el simulador 3D.

=== Restricciones de Hardware

- La máquina de ejecución debe cumplir los requisitos mínimos definidos en la @tabHardwareDesc (8 GB RAM, 4 núcleos, $>=$ 10 GB libres).
- El pipeline no requiere GPU ni hardware especializado.
- El tiempo máximo de ejecución completa es de 4 horas en la máquina de referencia (RD-001). En máquinas que no cumplan los mínimos, el tiempo puede ser
  mayor y el sistema no garantiza el requerimiento de desempeño.

== Modelo del Dominio

El modelo del dominio del sistema representa las entidades del mundo real que el sistema maneja, transforma y produce. No es un
modelo de clases de software sino una representación conceptual del dominio de movilidad urbana y simulación de tráfico.

#figure(
  image("/figures/grafico-modelo-dominio.png"),
  caption: [Gráfico modelo de dominio. ]
)<figModeloDominio>

Las entidades centrales del dominio y sus relaciones son:

#figure(
  table(
    columns: (1fr, 4fr, 2fr),
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

    [Intersección semaforizada], [Nodo de la red controlado por un `tlLogic`, con accesos, conexiones y un programa de fases.], [`.net.xml`],

    [Cruce candidato], [Cruce sin semáforo (uno o varios nodos de SUMO) que cumple las reglas de priorización; posible ubicación de un semáforo
    nuevo.], [Priorización (RF-032)],

    [Escenario comparativo], [Par de zonas idénticas (sin y con semáforo propuesto) con la misma demanda, simuladas en lockstep.], [`runs/sem-*`],

    [Actor seguido (ego)], [Vehículo o peatón que el usuario observa en tercera persona; tiene telemetría e índice de riesgo por lado.], [Frames del
    WebSocket],
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
- SUMO 1.27.1 soporta los modos de transporte a modelar con los parámetros por defecto. El transporte público se emite hoy como caminata (RF-043). Cambios
  en la API de TraCI en versiones posteriores podrían requerir ajustes; por eso `eclipse-sumo` y `traci` están fijados en 1.27.1.
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

    [`notebooks/F1.x`, `F2.x`], [RF-001, RF-002, RF-003, RF-009, RF-010], [Exploración, limpieza de la encuesta y los aforos y construcción de
    la red 3D y las TAZ (artefactos en `data/processed/`).],

    [`etl/sumo/trips.py`, `vtypes.py`], [RF-004, RF-005, RF-006, RF-008, RF-011, RNF-CON-001, RNF-SEG-001], [Generación de viajes TAZ ordenados por
    salida y tipos de vehículo.],

    [`etl/sumo/demanda.py`], [RF-013, RF-021, RF-022], [Presets de transferencia modal y conteos por modo.],

    [`etl/sumo/duarouter.py`, `simulation.py`, `proceso.py`], [RF-012, RNF-OBS-001], [Ruteo, simulación por TraCI, avance y cancelación de
    procesos.],

    [`etl/sumo/estilos.py`, `cierres.py`], [RF-023, RF-024], [Estilos de conducción y cierres viales.],

    [`etl/sumo/fcd.py`, `kepler.py`], [RF-027], [Exportación de las trayectorias para el visor.],

    [`etl/precalculadas.py`], [RF-025, RNF-REP-001], [Simulaciones precalculadas reproducibles.],

    [`etl/sumo/intersecciones.py`, `programas_tls.py`, `subred.py`, `priorizacion.py`, `evidencia.py`], [RF-028 a RF-032, RF-045],
    [Intersecciones, programas, Webster, recorte de zonas, priorización y evidencia externa.],

    [`etl/sumo/semaforo_nuevo.py`, `demanda_zona.py`, `escena3d.py`, `telemetria.py`], [RF-033, RF-034, RF-036, RF-037, RF-039], [Semáforo
    propuesto, demanda de la zona, geometría de la escena e indicadores de riesgo.],

    [`api/api.py`, `api/jobs.py`, `api/comparacion3d.py`], [RF-015, RF-018, RF-026, RF-031, RF-035, RF-040, RF-044, RD-003], [API REST/WebSocket, gestor de
    corridas y bucle lockstep de las comparaciones 3D.],

    [`kepler/src/`], [RF-017, RF-019, RF-020, RF-027, RF-034 a RF-039, RF-044, RD-004, RNF-USA-001], [Visor web: mapa, paneles y simulador 3D.],

    [Por definir], [RF-014, RF-016, RF-041, RF-043], [Validación GEH, reanudación por fase, reporte de la comparación 3D y transporte público real.],

    [Pipeline completo], [RD-001, RD-002, RNF-MAN-001, RNF-MAN-002, RNF-PORT-001, RNF-PORT-002], [Requerimientos que aplican al sistema como un todo.],
  ),
  caption: [Distribución de requerimientos por módulo (v2.0).]
) <tabDistribucion>

]
