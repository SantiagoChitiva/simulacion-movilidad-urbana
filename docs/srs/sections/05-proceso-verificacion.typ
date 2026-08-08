// @brief: especificacion de la seccion proceso de verificacion y sus subsecciones correspondientes

#let procesoVerificacion() = [

#align(center)[= Proceso de Verificación]

Esta sección presenta el plan de verificación y validación que se aplicará tanto a este documento SRS como a los requerimientos individuales especificados
en la Sección 3. El objetivo es garantizar que el sistema construido cumpla con lo especificado y que la especificación misma sea correcta, completa y
consistente antes de iniciar la implementación.

Se distinguen dos actividades complementarias:

- *Verificación:* determinar si el sistema se está construyendo correctamente, es decir, si los artefactos producidos (código, archivos de simulación,
  datos intermedios) se corresponden con lo especificado en el SRS.
- *Validación:* determinar si se está construyendo el sistema correcto, es decir, si el sistema producido satisface las necesidades reales de los posibles
  usuarios identificados (p. ej., analisistas de movilidad, ingenieros de infraestructura, Secretaría Distrital de Movilidad Bogotá)


== Verificación del Documento SRS

Antes de iniciar la fase de implementación, el documento SRS en su conjunto será sometido a un proceso de revisión estructurada para verificar que la
especificación cumple con las características definidas en la Sección 3 (atomicidad, completitud, consistencia, verificabilidad, trazabilidad, entre
otras).

=== Técnica de Revisión por Pares

Se realizará una sesión de revisión por pares (peer review) en la que cada integrante del equipo revisará las secciones redactadas por otro, verificando
los siguientes criterios:

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([*Criterio*], [*Pregunta de verificación*], [*Método*]),

    [Completitud], [¿Cada requerimiento tiene descripción, razón, criterio de medición, prioridad, módulo y versión?], [Inspección],

    [No ambigüedad], [¿Cada requerimiento admite una única interpretación? ¿Se usan términos del glosario de la Sección 1?], [Inspección],

    [Verificabilidad], [¿El criterio de medición permite comprobar el requerimiento mediante prueba, demostración, análisis o inspección?], [Análisis],

    [Consistencia], [¿Algún requerimiento contradice a otro o a las restricciones de diseño definidas?], [Inspección],

    [Trazabilidad], [¿Cada requerimiento tiene un identificador único y puede rastrearse hacia su fuente de origen y hacia al menos un caso de prueba?],
    [Inspección],

    [No redundancia], [¿Existe algún requerimiento que sea duplicado o subconjunto de otro?], [Inspección],

    [Atomicidad], [¿Cada requerimiento expresa una única capacidad del sistema?], [Inspección],
  ),
  caption: [Criterios de verificación del documento SRS.]
) <tabCriteriosVerificacion>

Los hallazgos de la revisión se registrarán en un issue de GitHub con la etiqueta `srs-review`, indicando el identificador del requerimiento afectado, el
criterio incumplido y la corrección propuesta. El documento no se considerará aprobado hasta que todos los issues de revisión estén cerrados.

=== Revisión con el Director del Proyecto

Se realizará una sesión de validación del SRS con el Ing. Andrés Calderón Romero al finalizar la revisión por pares. En esta sesión se verificará que:

- Los requerimientos de la Sección 3 reflejan correctamente las necesidades discutidas en las entrevistas de elicitación.
- Los criterios de aceptación (especialmente el umbral GEH $<$ 5 en $>=$ 85% de los puntos de aforo) son correctos y consensuados.
- Las exclusiones de alcance documentadas (interfaz web, otras localidades) son aceptadas.
- La distribución de requerimientos por módulo es coherente con la arquitectura esperada del sistema.

== Verificación de Requerimientos Individuales

Cada requerimiento de la Sección 3 será verificado mediante uno o más métodos formales, seleccionados según la naturaleza del requerimiento. Se utilizarán
cuatro métodos:

#figure(
  table(
    columns: (auto, 1fr),
    table.header([*Método*], [*Descripción y aplicación en el proyecto*]),

    [*Prueba (T)*], [Ejecución del sistema o de un componente con entradas definidas y comparación de la salida con el resultado esperado. Aplicable a
    todos los requerimientos funcionales (RF) y de desempeño (RD). Se implementará mediante pytest con fixtures que preparan los datasets de prueba.],

    [*Demostración (D)*], [Ejecución del sistema completo ante el director del proyecto para mostrar que una funcionalidad opera según lo especificado.
    Aplicable a los requerimientos funcionales de alto nivel (F1–F5) y al requerimiento de variación paramétrica (RF-013).],

    [*Análisis (A)*], [Revisión del código fuente, configuración del CI o métricas generadas para verificar que el requerimiento se cumple sin necesidad
    de ejecutar el sistema. Aplicable a requerimientos de mantenibilidad (RNF-MAN), portabilidad (RNF-PORT) y reproducibilidad (RNF-REP).],

    [*Inspección (I)*], [Revisión manual de artefactos generados (archivos XML, CSV, logs) para verificar que su estructura y contenido cumplen con la
    especificación. Aplicable a los requerimientos de formato de salida (RF-008, RF-009, RF-010, RF-011).],
  ),
  caption: [Métodos de verificación de requerimientos.]
) <tabMetodosVerificacion>

== Plan de Casos de Prueba

A continuación se presenta el plan de casos de prueba que se diseñará e implementará para verificar los requerimientos de la Sección 3. Cada caso de
prueba está asociado a uno o más requerimientos y especifica el método de verificación, las entradas de prueba y el criterio de éxito.

=== Pruebas de Requerimientos Funcionales

#figure(
  table(
    columns: (auto, auto, auto, 1fr, 1fr),
    table.header([*ID Caso*], [*Req.*], [*Método*], [*Entrada de prueba*], [*Criterio de éxito*]),

    [CP-001], [RF-001], [T], [Archivo XLSX con columnas obligatorias completas; segundo archivo XLSX sin la columna `destino_UPZ`.], [Primer caso:
    pipeline continúa sin error. Segundo caso: pipeline termina con código de error ≠ 0 y el log contiene "Columna requerida ausente: destino_UPZ".],

    [CP-002], [RF-002], [T], [Ejecución sin archivo OSM local; segunda ejecución con el archivo ya presente.], [Primera ejecución: archivo
    `usaquen.osm.pbf` generado en el directorio de datos. Segunda ejecución: log indica "Red OSM encontrada en caché, omitiendo descarga".],

    [CP-003], [RF-003], [T], [Dataset de 10 registros con 2 dobles conteos conocidos e identificados previamente.], [Tabla de salida con exactamente 8
    registros; log indica 2 registros eliminados por doble conteo con su ID_hogar.],

    [CP-004], [RF-004], [T], [Archivo con 1 000 registros de los cuales 50 tienen `origen_UPZ` nulo.], [Log reporta 5.0% de tasa de descarte; dataset
    limpio contiene exactamente 950 registros.],

    [CP-005], [RF-005], [T], [Dataset de prueba con factores de expansión conocidos cuya suma es exactamente
    12 500.0.], [Suma de viajes expandidos en el output: entre 12 498.75 y 12 501.25 (±0.01%).],

    [CP-006], [RF-006], [T], [Dataset con viajes de todos los modos (auto, bus, moto, bicicleta).], [Sistema genera un archivo `.od` por cada modo con al
    menos un viaje. Número de archivos `.od` = número de modos con viajes en el dataset.],

    [CP-007], [RF-007], [T, I], [Dataset con viajes distribuidos en los tres períodos horarios (AM, PM, nocturno).], [Sistema genera al menos 3 × N
    archivos `.od` (N = número de modos). Los archivos AM contienen solo viajes con hora de inicio entre 6:00 y 8:59.],

    [CP-008], [RF-008], [T, I], [Archivo `.od` generado por el pipeline para el período AM, modo automóvil.], [duarouter procesa el archivo sin errores de
    formato sobre la red `.net.xml` de Usaquén y genera un `.rou.xml` válido.],

    [CP-009], [RF-009], [T, I], [Red OSM de Usaquén recortada disponible en disco.], [Archivo `.net.xml` generado por netconvert sin errores. SUMO carga
    la red sin mensajes de tipo ERROR en su log.],

    [CP-010], [RF-010], [T, I], [Shapefile de UPZ de Usaquén y red `.net.xml` generada.], [Archivo `.taz.xml` con una entrada por cada UPZ de Usaquén.
    Cada zona contiene al menos un nodo de la red. SUMO valida el archivo sin errores de zona vacía.],

    [CP-011], [RF-011], [T, I], [Ejecución de la fase F4 del pipeline con la red y matrices disponibles.], [Archivo `.vtype.xml` con al menos 4 entradas
    (auto, bus, moto, bicicleta). SUMO carga el archivo sin advertencias de tipo desconocido.],

    [CP-012], [RF-012], [T], [Archivos `.od`, `.net.xml` y `.taz.xml` generados por las fases anteriores.], [duarouter completa sin errores y genera
    `.rou.xml` con al menos un viaje por cada par O/D con valor > 0 en la matriz.],

    [CP-013], [RF-013], [T, D], [Dos archivos `config.yaml` idénticos excepto en el campo `factor_escala_demanda`: 1.0 y 1.2 respectivamente.], [Los dos
    conjuntos de artefactos generados difieren en el total de viajes exactamente en un 20%. Sin modificaciones al código fuente entre ejecuciones.],

    [CP-014], [RF-014], [T, I], [Resultados de simulación SUMO y base de datos de aforos HMD de Usaquén.], [Archivo `validacion_geh.csv` con una fila por
    punto de aforo disponible, columnas `punto_aforo`, `volumen_simulado`, `volumen_real`, `GEH`. Log indica el porcentaje de puntos con GEH < 5.],

    [CP-015], [RF-015], [T, I], [Ejecución completa del pipeline con los datos de Usaquén.], [Archivo `pipeline.log` con al menos una entrada de inicio y
    una de fin para cada fase F1–F5, cada una con marca de tiempo.],

    [CP-016], [RF-016], [T], [Ejecución interrumpida forzosamente al inicio de F4 (kill del proceso); relanzamiento con flag `--resume`.], [Segunda
    ejecución salta F1–F3, inicia desde F4 y produce artefactos idénticos a una ejecución completa (verificado por hash SHA-256 de los archivos de
    salida).],

    [CP-017b], [RF-017], [D], [Simulación con resultados disponibles; abrir el módulo web en el navegador y seleccionar la simulación.], [Las métricas de
    la simulación se renderizan en menos de 3 segundos. Todos los campos (volumen, tiempo, GEH) muestran valores distintos de cero.],

    [CP-018b], [RF-018], [T], [Petición GET a /simulaciones/{id}/metricas con un ID válido y con un ID inexistente.], [ID válido: respuesta HTTP 200 con
    JSON. ID inexistente: respuesta HTTP 404.],

    [CP-019b], [RF-019], [D], [Abrir el formulario de parametrización, seleccionar período PM y factor 1.2, confirmar.], [El pipeline se ejecuta con los
    parámetros seleccionados. El módulo web muestra indicador de progreso y mensaje de éxito al finalizar.],

    [CP-020b], [RF-020], [D], [Ingresar factor de escala igual a 0 en el formulario y pulsar Confirmar.], [El formulario muestra mensaje de error visible.
    No se envía ninguna petición al backend.]
  ),
  caption: [Plan de casos de prueba para requerimientos funcionales.]
) <tabCasosPruebaFuncionales>

=== Pruebas de Requerimientos No Funcionales

#figure(
  table(
    columns: (auto, auto, auto, 1fr, 1fr),
    table.header([*ID Caso*], [*Req.*], [*Método*], [*Procedimiento*], [*Criterio de éxito*]),

    [CP-017], [RD-001], [T], [Ejecutar el pipeline completo (F1–F5) en la máquina de referencia (8 GB RAM,
    4 núcleos) con el dataset completo de Usaquén. Registrar tiempo de inicio y fin.], [Tiempo total de ejecución ≤ 14 400 segundos (4 horas).],

    [CP-018], [RD-002], [T], [Ejecutar únicamente la fase F2 sobre el dataset completo de la encuesta (~500 000 registros) en la máquina de referencia.],
    [Tiempo de ejecución de F2 ≤ 1 800 segundos (30 minutos).],

    [CP-019], [RNF-CON-001], [T], [Archivo de prueba con 10% de registros con NaN en `origen_UPZ`.], [Pipeline completa sin excepciones no controladas.
    Log reporta exactamente 10% de descarte en F1.],

    [CP-020], [RNF-CON-002], [T], [Fallo forzado (excepción lanzada) al inicio de F4.], [Directorio de salida contiene artefactos de F1–F3. Log indica
    "Fase F4 fallida" con la causa del error.],

    [CP-021], [RNF-DISP-001], [T], [Ejecutar fases F2–F5 con la interfaz de red deshabilitada (modo avión o desconexión del adaptador).], [Pipeline
    completa sin errores de conexión en ninguna de las fases F2–F5.],

    [CP-022], [RNF-SEG-001], [I], [Inspeccionar el contenido de los archivos `.od`, `.rou.xml` y `.taz.xml` generados con el dataset de Usaquén.], [Ningún
    archivo de salida contiene el campo `ID_hogar` ni ningún identificador individual de la encuesta.],

    [CP-023], [RNF-MAN-001], [A], [Ejecutar `pydocstyle` sobre el paquete `etl/` al finalizar la implementación.], [Cero funciones públicas sin docstring
    completo (descripción, parámetros, retorno, ejemplo).],

    [CP-024], [RNF-MAN-002], [A], [Verificar los logs del workflow de GitHub Actions en la rama principal tras un commit de código.], [El step de pylint
    reporta score ≥ 8.0/10. El build está marcado como exitoso.],

    [CP-025], [RNF-PORT-001], [A], [Revisar los logs de los jobs de CI en GitHub Actions para Ubuntu 22.04 y Windows 10.], [Ambos jobs completan
    exitosamente. Ningún step falla por incompatibilidad de sistema operativo.],

    [CP-026], [RNF-PORT-002], [I], [Inspeccionar el archivo `requirements.txt` del repositorio.], [Todas las entradas siguen el formato
    `biblioteca==X.Y.Z`. No existen rangos del tipo `>=` ni `~=`.],

    [CP-027], [RNF-REP-001], [T, A], [Ejecutar el pipeline dos veces consecutivas con los mismos archivos de entrada y el mismo `config.yaml`. Calcular el
    hash SHA-256 de cada archivo de salida en ambas ejecuciones.], [El hash SHA-256 de cada archivo de salida es idéntico entre las dos ejecuciones. El
    script `scripts/verify_reproducibility.py` reporta 0 diferencias.],

    [CP-028], [RNF-OBS-001], [T], [Ejecutar la fase F2 con el dataset completo y medir el tiempo entre mensajes de progreso en consola.], [Al menos un
    mensaje de progreso visible en consola por cada minuto de ejecución de F2.],
  ),
  caption: [Plan de casos de prueba para requerimientos no funcionales.]
) <tabCasosPruebaNoFuncionales>


== Criterios de Aceptación del Sistema

El sistema se considerará verificado y listo para la entrega al director del proyecto cuando se cumplan simultáneamente los siguientes criterios:

+ Todos los casos de prueba de requerimientos funcionales (CP-001 a CP-016) han sido ejecutados y su resultado es *Pasa*.
+ Los casos de prueba de desempeño (CP-017 y CP-018) han sido ejecutados en la máquina de referencia definida en @tabHardwareDesc y su resultado es *Pasa*.
+ Al menos el 85% de los puntos de aforo HMD de Usaquén obtienen un GEH < 5 en la simulación de validación (criterio del requerimiento RF-014).
+ Los jobs de CI en GitHub Actions para Ubuntu y Windows están en estado *verde* (todos los steps exitosos) en el último commit de la rama principal.
+ El script `scripts/verify_reproducibility.py` reporta 0 diferencias entre dos ejecuciones consecutivas del pipeline con los mismos datos de entrada.
+ No existen issues abiertos en GitHub con la etiqueta `blocker` o `bug-critico`.

== Proceso de Registro de Defectos

Durante la fase de verificación, los defectos encontrados se registrarán y gestionarán siguiendo el proceso definido a continuación:

#figure(
  table(
    columns: (auto, 1fr, 2fr),
    table.header([*Paso*], [*Responsable*], [*Acción*]),

    [1. Reporte], [Responsable de Pruebas], [Se abre un GitHub Issue con la etiqueta `bug`, indicando el caso de prueba fallido, el requerimiento
    afectado, los pasos para reproducir el defecto, el resultado obtenido y el resultado esperado.],

    [2. Clasificación], [Responsable de Pruebas], [Se asigna una severidad: `blocker` (impide la entrega), `bug-critico` (afecta un requerimiento de
    prioridad Alta), `bug-menor` (afecta un requerimiento de prioridad Media). Los blockers y críticos deben corregirse antes de la entrega.],

    [3. Asignación], [Responsable de Documentación], [El issue se asigna al integrante del equipo responsable del módulo afectado según la distribución de
    requerimientos de la Sección 2.8.],

    [4. Corrección], [Desarrollador asignado], [Se implementa la corrección en una rama separada y se abre un pull request referenciando el issue. El PR
    debe incluir o actualizar el caso de prueba que detectó el defecto.],

    [5. Verificación], [Responsable de Pruebas], [Se ejecuta nuevamente el caso de prueba fallido y los casos relacionados para confirmar la corrección y
    verificar la ausencia de regresiones.],

    [6. Cierre], [Responsable de Pruebas], [Se cierra el issue con referencia al commit de corrección y se actualiza el estado del caso de prueba en la
    matriz de trazabilidad.],
  ),
  caption: [Proceso de registro y gestión de defectos.]
) <tabDefectos>

]
