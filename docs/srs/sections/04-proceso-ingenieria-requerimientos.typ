// @brief: especificacion de la seccion proceso ingenieria de requerimientos y sus subsecciones correspondientes

#let procesoIngenieriaRequerimientos() = [

#align(center)[= Proceso de Ingeniería de Requerimientos]

Esta sección describe el proceso que el equipo siguió para construir la especificación de requerimientos contenida en este documento. Se
presentan las técnicas de elicitación utilizadas, la forma en que los requerimientos fueron analizados y priorizados, el esquema de trazabilidad adoptado
y el proceso de control de cambios, el cual es complementario a lo definido en la sección de Control de Requerimientos del SPMP del proyecto.

== Elicitación de Requerimientos

La elicitación es el proceso de descubrir, extraer y comprender las necesidades de los stakeholders del sistema. Para el proyecto, se emplearon
tres técnicas complementarias, seleccionadas en función de la naturaleza técnica del dominio y de la disponibilidad de los actores involucrados.

=== Entrevistas con el Director del Proyecto

Se realizaron sesiones de trabajo estructuradas con el Ing. Andrés Calderón Romero, director del proyecto, quien cumple el rol de cliente técnico del
sistema. Estas sesiones se llevaron a cabo al inicio del proyecto (Semana 1) y al cierre de la Fase 1 de CRISP-DM (Semana 3), con el objetivo de:

- Identificar las fuentes de datos disponibles (Encuesta de Movilidad 2023, aforos HMD, red OSM) y sus restricciones de acceso y calidad.
- Delimitar el alcance geográfico del caso de validación (localidad de Usaquén).
- Validar los modos de transporte prioritarios a modelar: automóvil particular, bus SITP/TransMilenio, motocicleta y bicicleta.
- Acordar los criterios de aceptación del modelo de simulación basados en el estadístico GEH (umbral GEH < 5 en al menos el 85% de los puntos de aforo).

=== Análisis de Documentación

Dado que el dominio del problema combina ciencia de datos, simulación de tráfico y política pública de movilidad, una parte significativa de los
requerimientos se derivó del análisis directo de fuentes documentales:

- *Encuesta de Movilidad de Bogotá 2023:* el análisis de la estructura del dataset (columnas, tipos de dato, dominio de valores, proporción de registros
  incompletos) fue determinante para definir los requerimientos de validación y limpieza de datos (RF-001 a RF-005).
- *Documentación oficial de SUMO 1.19:* la especificación de los formatos de archivo `.net.xml`, `.taz.xml`, `.od`, `.rou.xml` y `.vtype.xml` fue la
  fuente directa para los requerimientos de generación de artefactos (RF-008 a RF-012).
- *Base de datos de aforos HMD:* el análisis de los puntos de aforo disponibles en Usaquén definió la granularidad y el período de las matrices O/D
  requeridas (RF-006, RF-007).
- *TomTom Traffic Index 2025 e informes de la Secretaría Distrital de Movilidad:* usados para contextualizar la importancia del sistema y validar los
  períodos horarios AM/PM como los más relevantes para el análisis.

=== Exploración de Datos (CRISP-DM -- Fase 1)

Las Fases 1 y 2 del modelo de ciclo de vida del proyecto (comprensión del dominio y preparación de datos, bajo CRISP-DM) generaron hallazgos concretos que
se tradujeron directamente en requerimientos.

- La presencia de dobles conteos en la encuesta, que motivó el requerimiento RF-003.
- La variabilidad en la cobertura de UPZ entre los registros de la encuesta y los polígonos oficiales, que motivó el requerimiento RF-010.
- La duración estimada del procesamiento de #{sym.tilde.basic}500,000 registros, que fundamentó el requerimiento de desempeño RD-002.
- La necesidad de diferenciar al menos tres períodos horarios (RF-007), dado que la distribución de viajes en la encuesta mostró patrones claramente
  distintos en AM, PM y nocturno.

== Análisis y Priorización de Requerimientos

Una vez elicitados los requerimientos candidatos, el equipo realizó una sesión de análisis conjunto para depurarlos, verificar su consistencia y
asignarles prioridad. Se aplicaron los siguientes criterios:

=== Resolución de Conflictos

Durante el análisis se identificaron dos conflictos entre requerimientos candidatos:

- *RF-006 vs. RF-007 (versión preliminar):* inicialmente se habían redactado como dos requerimientos separados que definían períodos horarios para
  automóviles y para los demás modos respectivamente, con definiciones de períodos inconsistentes. Se resolvió unificando la definición de períodos en
  RF-007 (AM: 6–9h, PM: 16–19h, nocturno: 21–24h) y haciendo que RF-006 referencie esa definición.
- *Checkpoint vs. Logging:* se separó la funcionalidad de persistencia de estado (RF-016) de la de registro de ejecución (RF-015), dado que son
  responsabilidades de módulos distintos (`etl/checkpoint.py` y `etl/logger.py`) y tienen criterios de medición independientes.

=== Esquema de Priorización

Los requerimientos fueron clasificados en tres niveles de prioridad usando el método MoSCoW, consensuado con el director del proyecto:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Prioridad*], [*Etiqueta MoSCoW*], [*Criterio de clasificación*]),

    [Alta], [Must Have], [El sistema no puede entregarse sin este requerimiento. Su ausencia impide la ejecución del pipeline o invalida los resultados de
    la simulación.],
    [Media], [Should Have], [Requerimiento importante que mejora la usabilidad, mantenibilidad o confiabilidad del sistema, pero cuya ausencia no impide
    la ejecución básica del pipeline.],
    [Baja], [Could Have], [Requerimiento deseable que puede diferirse a una versión futura si el tiempo de desarrollo no lo permite.],
  ),
  caption: [Esquema de priorización MoSCoW.]
) <tabMoscow>

En la versión 1.0 del sistema todos los requerimientos documentados tienen prioridad Alta o Media. No se identificaron requerimientos de prioridad Baja
que justificaran su inclusión en el SRS; los candidatos de baja prioridad fueron documentados como requerimientos diferidos en el SPMP.

== Especificación y Documentación

Cada requerimiento fue documentado siguiendo el formato Volere adaptado que se describe en la Sección 3 de este documento (ver Tabla 7: Documentación de
Requerimientos). Este formato garantiza que cada requerimiento sea atómico, no ambiguo, completo y verificable, cumpliendo con las características
definidas en IEEE 830-1998.

La convención de identificadores adoptada es la siguiente:

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([*Prefijo*], [*Tipo*], [*Ejemplo*]),
    [`RF-NNN`],      [Requerimiento Funcional],         [`RF-001`, `RF-016`],
    [`RD-NNN`],      [Requerimiento de Desempeño],      [`RD-001`, `RD-002`],
    [`RNF-CON-NNN`], [No Funcional -- Confiabilidad],    [`RNF-CON-001`],
    [`RNF-DISP-NNN`],[No Funcional -- Disponibilidad],   [`RNF-DISP-001`],
    [`RNF-SEG-NNN`], [No Funcional -- Seguridad],        [`RNF-SEG-001`],
    [`RNF-MAN-NNN`], [No Funcional -- Mantenibilidad],   [`RNF-MAN-001`],
    [`RNF-PORT-NNN`],[No Funcional -- Portabilidad],     [`RNF-PORT-001`],
    [`RNF-REP-NNN`], [No Funcional -- Reproducibilidad], [`RNF-REP-001`],
    [`RNF-OBS-NNN`], [No Funcional -- Observabilidad],   [`RNF-OBS-001`],
  ),
  caption: [Convención de identificadores de requerimientos.]
) <tabIds>

Los identificadores son únicos, permanentes y no se reasignan cuando un requerimiento es eliminado, para preservar la trazabilidad histórica.

== Trazabilidad de Requerimientos

La trazabilidad permite rastrear cada requerimiento hacia adelante (hacia los casos de prueba y el código) y hacia atrás (hacia su fuente de origen). El
equipo implementa dos niveles de trazabilidad:

=== Trazabilidad hacia el origen

Cada requerimiento está asociado a la fuente que lo originó:

#figure(
  table(
    columns: (1fr, 2fr, 2fr),
    table.header([*Requerimiento*], [*Fuente de origen*], [*Artefacto de evidencia*]),

    [`RF-001`], [Estructura de columnas de la Encuesta de Movilidad 2023], [Notebook `01_exploracion_encuesta.ipynb`],
    [`RF-003`], [Documento "Base de datos con factores de ponderación y sin dobles conteos"], [Acta de reunión Semana 1],
    [`RF-007`], [Análisis de distribución horaria de viajes (exploración Fase 1)], [Notebook `02_distribucion_horaria.ipynb`],
    [`RF-008`], [Documentación oficial SUMO 1.19 -- TAZ-based OD matrix format], [docs.sumo.dlr.de/docs/Demand/Importing_O/D_Matrices],
    [`RF-014`], [Criterio de validación acordado con el director (GEH < 5 en ≥ 85%)], [Acta de reunión Semana 3],
    [`RD-001`], [Supuesto de hardware del SPMP (8 GB RAM, 4 núcleos)], [SPMP Sección 6.3 -- Supuestos y Restricciones],
    [`RNF-REP-001`], [Requisito científico del proyecto de grado (resultados verificables)], [Acta de reunión Semana 1 -- objetivo de reproducibilidad],
  ),
  caption: [Trazabilidad de requerimientos seleccionados hacia su origen.]
) <tabTrazabilidadOrigen>

=== Trazabilidad hacia casos de prueba

La matriz de trazabilidad completa entre requerimientos y casos de prueba se documenta en la Sección 5 (Proceso de Verificación) de este documento y se
mantiene actualizada en la hoja `traceability_matrix.xlsx` del repositorio del proyecto.

La gestión de la trazabilidad se apoya en GitHub Issues: cada requerimiento tiene un issue asociado con su identificador como etiqueta, permitiendo
rastrear los commits, pull requests y casos de prueba que lo implementan y verifican.

== Control de Cambios a los Requerimientos

Este proceso es complementario a la sección de Control de Requerimientos del SPMP y describe el flujo operativo que el equipo sigue cuando un
requerimiento necesita ser creado, modificado o eliminado.

=== Flujo de Control de Cambios

#figure(
  table(
    columns: (20%, 20%, auto),
    table.header([*Paso*], [*Responsable*], [*Acción*]),

    [1. Solicitud], [Cualquier integrante], [Se abre un GitHub Issue con la etiqueta `change-request`, describiendo el requerimiento afectado, la razón
    del cambio y el impacto estimado en otros requerimientos.],

    [2. Análisis], [Responsable de Documentación + equipo], [El equipo analiza el impacto del cambio sobre los requerimientos existentes, los casos de
    prueba y el código. El resultado se documenta en el mismo issue.],

    [3. Aprobación], [Director del proyecto], [Cambios que afecten el alcance, los criterios de aceptación o los requerimientos de prioridad Alta
    requieren aprobación explícita del director (comentario en el issue o correo electrónico adjunto). Cambios menores (corrección de redacción, ajuste de
    criterios de medición) pueden ser aprobados por el equipo.],

    [4. Implementación],[Responsable de Documentación], [Se actualiza la tabla del requerimiento en el SRS, se incrementa el número de versión del
    requerimiento y se actualiza la fecha. El historial de cambios del documento se registra en la tabla de la página inicial del SRS.],

    [5. Cierre], [Responsable de Documentación], [Se cierra el issue con referencia al commit que incorpora el cambio en el SRS. Se actualiza la matriz de
    trazabilidad si el cambio afecta casos de prueba.],
  ),
  caption: [Flujo de control de cambios a los requerimientos.]
) <tabControlCambios>

=== Versionamiento de Requerimientos

Cada requerimiento lleva un número de versión independiente (campo *Versión* del formato Volere). La versión inicial de todos los requerimientos de este
documento es 1.0. Un cambio en la descripción o criterio de medición incrementa el número menor (1.0 #sym.arrow 1.1). Un cambio en el alcance o la
prioridad del requerimiento incrementa el número mayor (1.0 #sym.arrow 2.0). Los requerimientos eliminados no se borran del documento; se marcan como
*[Eliminado v X.Y]* y se conservan para preservar la trazabilidad histórica.

=== Restricciones al Control de Cambios

De acuerdo con el SPMP, se establecen las siguientes restricciones para evitar la expansión descontrolada del alcance (*scope creep*):

- No se aceptarán nuevos requerimientos funcionales de prioridad Alta después de la Semana 5 del proyecto (inicio de la Fase 3 -- construcción).
- Cambios en los criterios de aceptación de requerimientos de validación (RF-014, RNF-REP-001) requieren aprobación del director en todos los casos.
- Cualquier cambio que implique modificar los formatos de salida del pipeline (extensiones de archivo, estructura XML) debe ser evaluado contra la
  compatibilidad con SUMO 1.19 antes de ser aprobado.

]
