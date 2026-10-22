= Monitoreo y Control del Proyecto

== Administración de Requerimientos

Los requerimientos del sistema se gestionan a través del SRS (entregable de la semana 4; versión 2.0 en la semana 11). El proceso de administración de
requerimientos incluye: identificación inicial, revisión con el director, aprobación, y control de cambios durante el desarrollo.

#figure(image("/figures/fig03-bpmn-requerimientos.png", width: 100%), caption: [Diagrama BPMN – Proceso de administración de requerimientos.]) <figBpmnReq>

El flujo de la @figBpmnReq muestra: detección del cambio #sym.arrow creación de GitHub Issue #sym.arrow análisis de impacto (alcance + diseño +
pruebas) #sym.arrow aprobación (director si afecta alcance; equipo si es menor) #sym.arrow actualización del SRS con nueva versión #sym.arrow
actualización de la matriz de trazabilidad. Roles: equipo de desarrollo, director.

*Artefactos generados:* SRS (requerimientos funcionales y no funcionales), matriz de trazabilidad (SRS #sym.arrow.l.r diseño #sym.arrow.l.r
pruebas), registro de cambios de requerimientos en GitHub Issues.

*Proceso de control de cambios:* toda solicitud de cambio a un requerimiento aprobado debe documentarse como un GitHub Issue, ser analizada por el
equipo (impacto en alcance, calendario y diseño), aprobada por el director si afecta el alcance, e incorporada al SRS con actualización de la versión.
Los cambios se discuten al inicio de cada sprint. Desde la versión 2.0 cada requerimiento del SRS indica su estado (Implementado, Parcial o
Pendiente), lo que facilita la métrica de requerimientos completados.

== Monitoreo y Control de Progreso

El monitoreo y control del proyecto tiene como propósito verificar continuamente que el desarrollo avance de acuerdo con el alcance, cronograma y
objetivos definidos en el SPMP. El proceso de seguimiento busca identificar tempranamente desviaciones, retrasos o problemas técnicos que puedan afectar
la entrega del proyecto, permitiendo aplicar acciones correctivas oportunamente. El modelo de seguimiento combina prácticas de Scrum, métricas
cuantitativas y validaciones técnicas específicas para proyectos de simulación de tráfico.

*Métricas de Progreso.* Las métricas seleccionadas permiten medir tanto el avance del software como la calidad de los resultados producidos.

#figure(
  table(
    columns: (2fr, 2fr, 1fr, 1fr),
    table.header([Métrica], [Unidad], [Frecuencia], [Responsable]),
    [Tareas completadas vs. planificadas], [Issues cerrados / total sprint], [Fin de cada sprint], [Scrum Master],
    [Burndown del sprint], [Horas restantes], [Diario], [Scrum Master],
    [Cobertura de pruebas unitarias], [% de líneas cubiertas], [Por commit (CI automático)], [Responsable de pruebas],
    [Pruebas automatizadas _(v2.0)_], [Pruebas que pasan / total (`simulation-service/test/`)], [Por commit], [Responsable de pruebas],
    [Porcentaje de validación GEH], [% de puntos con GEH < 5], [Fin de cada sprint de simulación], [Responsable de simulación y pruebas],
    [Velocidad del equipo], [Puntos de historia por sprint], [Fin de cada sprint], [Scrum Master],
    [Número de requerimientos completados], [Requerimientos completados / requerimientos totales], [Semanal], [Responsable de documentación y Scrum
    Master],
    [Errores detectados y corregidos], [Número de issues de error cerrados], [Semanal], [Responsable de pruebas],
  ),
  caption: [Métricas del proyecto.],
) <tabMetricas>

- *Tareas completadas vs. tareas planificadas.* Mide la cantidad de tareas finalizadas respecto a las comprometidas para un sprint o fase. Unidad:
  número de issues cerrados / total de issues planificados. Objetivo: verificar el cumplimiento del backlog comprometido. Frecuencia: al cierre de cada
  sprint. Responsable: Scrum Master.
- *Horas restantes del sprint (burndown).* Mide el trabajo pendiente dentro de cada sprint. Unidad: horas restantes estimadas. Objetivo: detectar
  retrasos tempranos y sobrecarga de trabajo. Frecuencia: seguimiento diario. Responsable: Scrum Master.
- *Cobertura de pruebas unitarias.* Mide el porcentaje de código cubierto por pruebas automatizadas. Unidad: porcentaje de líneas cubiertas. Objetivo:
  garantizar calidad y estabilidad del pipeline. Frecuencia: automática por commit mediante CI. Responsable: Responsable de pruebas.
- *Pruebas automatizadas (v2.0).* Número de pruebas de `simulation-service/test/` y cuántas pasan; en la versión 2.0 son 99 y pasan todas. Objetivo:
  detectar regresiones en el pipeline, la API y el simulador. Frecuencia: por commit. Responsable: Responsable de pruebas. Estas pruebas aún no corren
  en el CI (ver R10).
- *Validación GEH.* Mide el porcentaje de puntos de aforo cuya simulación alcanza valores GEH menores a 5. Unidad: porcentaje de puntos válidos.
  Objetivo: validar la calibración del modelo de tráfico. Frecuencia: al cierre de cada sprint de simulación. Responsable: Responsable de simulación y
  Responsable de pruebas.
- *Velocidad del equipo.* Mide la cantidad de trabajo completado por sprint. Unidad: puntos de historia completados. Objetivo: estimar la capacidad
  real del equipo. Frecuencia: fin de cada sprint. Responsable: Scrum Master.
- *Número de requerimientos implementados.* Mide la cantidad de requerimientos funcionales implementados y verificados. Unidad: requerimientos
  completados / requerimientos totales. Objetivo: verificar el avance funcional del sistema. Frecuencia: semanal. Responsable: Responsable de
  Documentación y Scrum Master.
- *Errores detectados y corregidos.* Mide la cantidad de defectos identificados y solucionados. Unidad: número de issues de error cerrados. Objetivo:
  monitorear estabilidad y calidad. Frecuencia: semanal. Responsable: Responsable de Pruebas.

*Actividades de reporte de progreso*
- *Reuniones semanales de seguimiento.* El equipo revisa el estado del proyecto:
  - tareas completadas, bloqueos y métricas;
  - actualización del backlog, ajuste de prioridades y definición de compromisos.

  Responsables: todos los integrantes. Frecuencia: dos veces por semana.
- *Reuniones con el director.* Al cierre de cada sprint se presentan avances, se revisan entregables, se discuten riesgos y se recibe
  retroalimentación técnica y validación de decisiones importantes. Responsables: equipo completo y director. Frecuencia: semanal según
  disponibilidad.
- *Actualización de GitHub Projects.* GitHub Projects actúa como mecanismo central de seguimiento: se actualiza el estado de tareas, se registran
  issues, bloqueos y responsables, y se registra el progreso del sprint. Responsables: Scrum Master. Frecuencia: diaria.

*Verificación de implementación exitosa.* Para considerar que un requerimiento fue implementado exitosamente deben cumplirse los siguientes criterios:
- el código compila y ejecuta correctamente;
- las pruebas unitarias asociadas pasan exitosamente;
- el cambio fue revisado mediante pull request;
- el resultado es consistente con el SRS;
- la funcionalidad fue validada por al menos otro integrante;
- la documentación correspondiente fue actualizada.

En el caso de componentes de simulación se requiere además la ejecución correcta en SUMO, la generación válida de archivos XML y métricas GEH dentro
del rango esperado.

*Acciones correctivas.* Cuando las métricas indiquen desviaciones importantes respecto a la planeación inicial, el equipo aplicará acciones
correctivas:
- *Retrasos en el sprint.*
  - Condición: avance inferior al 70% del trabajo comprometido.
  - Acción: reunión extraordinaria, repriorización del backlog, redistribución de tareas y reducción de alcance no crítico.
  - Responsables: Scrum Master y equipo.
- *Problemas técnicos críticos.*
  - Condición: errores que impidan continuar el desarrollo.
  - Acción: investigación colaborativa, escalamiento al director, implementación temporal alternativa y ajuste del cronograma.
  - Responsable: el responsable técnico del área afectada.
- *Baja calidad del modelo.*
  - Condición: GEH > 5 en más del 15% de puntos.
  - Acción: revisión de matrices O/D, ajuste de parámetros de simulación, validación de aforos y recalibración del escenario.
  - Responsables: Responsable de simulación y Responsable de datos.
- *Problemas de calidad del código.*
  - Condición: cobertura insuficiente o errores frecuentes.
  - Acción: incrementar pruebas, revisión obligatoria de código, refactorización y congelamiento temporal de nuevas funcionalidades.
  - Responsable: Responsable de pruebas.
- *Desviaciones documentales.*
  - Condición: inconsistencias entre entregables.
  - Acción: revisión cruzada de documentos, actualización de trazabilidad, corrección de versiones y validación colectiva.
  - Responsable: Responsable de documentación.

*Cierre del monitoreo.* Al finalizar cada sprint se consolidará un resumen de:
- tareas completadas y problemas encontrados;
- riesgos identificados y acciones correctivas aplicadas;
- estado de las métricas y decisiones tomadas.

Estos resultados servirán como insumo para retrospectivas y para ajustar la planeación de los siguientes sprints.

== Cierre del Proyecto

Al finalizar cada entrega formal del proyecto, el equipo realiza:
- una retrospectiva de la fase, con registro de lecciones aprendidas;
- la actualización del SPMP y del registro de riesgos;
- la verificación de que todos los artefactos están versionados en GitHub.

Al cierre final (semanas 14 a 16), el equipo:
- entrega todos los artefactos al director y a la coordinación académica;
- realiza la exposición ante los jurados;
- archiva el repositorio con el código fuente y la documentación.
