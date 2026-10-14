= Administración del Proyecto

== Métodos y Herramientas de Estimación

*Enfoque general de estimación.* La estimación del proyecto se realizó mediante una combinación de métodos cuantitativos y cualitativos con el
objetivo de obtener una planeación realista tanto del esfuerzo de desarrollo como de las actividades de documentación, validación y gestión. Debido a
que el proyecto involucra componentes de procesamiento de datos, simulación de tráfico y desarrollo de software académico, no resulta suficiente
utilizar un único método de estimación tradicional. Por esta razón se adoptó una estrategia híbrida basada en:
- Estimación por analogía.
- Estimación por descomposición (WBS).
- Estimación basada en experiencia del equipo.
- Estimación incremental por sprint.
- Estimación de carga de documentación y validación.

El proceso de estimación fue realizado colectivamente por el equipo durante la planeación inicial del proyecto y refinado después de reuniones con el
director.

*Estimación por analogía.* La primera aproximación de esfuerzo se realizó mediante comparación con proyectos similares encontrados en artículos
académicos, repositorios públicos y tesis relacionadas con simulación de tráfico usando SUMO. Se analizaron proyectos que incluían:
- Procesamiento ETL de datos de movilidad.
- Construcción de matrices O/D.
- Conversión de redes OpenStreetMap.
- Integración con SUMO.
- Validación mediante métricas de tráfico.

A partir de estas referencias se identificó que un proyecto de complejidad similar normalmente requiere entre 2 y 4 meses de trabajo parcial para
equipos de 3 o 4 personas. La comparación permitió establecer un rango inicial de esfuerzo aproximado y validar que el alcance propuesto era viable
dentro del semestre académico.

*Estimación basada en complejidad técnica.* Posteriormente, el equipo clasificó cada componente del sistema según su complejidad técnica.

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Componente], [Complejidad], [Justificación]),
    [Construcción de matrices O/D], [Alta], [Transformaciones estadísticas y expansión muestral],
    [Procesamiento de red vial], [Alta], [Conversión OSM-SUMO y validación geoespacial],
    [Configuración de SUMO], [Media-alta], [Curva de aprendizaje del simulador],
    [Validación GEH], [Media], [Implementación matemática y comparación estadística],
    [Escenarios hipotéticos], [Alta], [Requiere calibración y análisis comparativo],
    [Documentación IEEE], [Media], [Alto volumen documental y trazabilidad],
    [Módulo de semaforización _(v2.0)_], [Media-alta], [Lectura y escritura de `tlLogic`, Webster, recorte de red y demanda],
    [Simulador 3D comparativo _(v2.0)_], [Alta], [Dos SUMO en lockstep por TraCI, render 3D en el navegador e indicadores de riesgo],
  ),
  caption: [Complejidad técnica por componente.],
) <tabComplejidad>

Esta clasificación permitió priorizar tiempo adicional para las actividades de mayor riesgo técnico.

*Estimación por descomposición (WBS).* Después de la estimación inicial, el proyecto fue descompuesto en actividades específicas utilizando una Work
Breakdown Structure (WBS). Cada actividad fue estimada individualmente considerando: complejidad técnica, dependencias, experiencia previa del equipo,
tiempo de aprendizaje requerido, riesgos asociados y actividades de pruebas y correcciones. La suma de estas estimaciones produjo el total de
horas-persona del proyecto.

*Herramientas utilizadas para la estimación.* GitHub Projects se utilizó para estructurar el backlog inicial y dividir el trabajo en tareas concretas.
Cada actividad fue registrada como issue o tarea independiente, permitiendo estimar el tiempo esperado, las dependencias, la prioridad, los
responsables y el estado de avance. La herramienta también facilita el seguimiento posterior del cumplimiento de las estimaciones.

#figure(image("/figures/fig08-wbs-linea-base.png", width: 100%), caption: [Diagrama WBS (línea base v1.x).]) <figWbs>

La estructura WBS (@figWbs) fue utilizada para organizar el proyecto jerárquicamente y visualizar las fases principales, las subtareas, las
dependencias críticas y la relación entre entregables. Gracias a esta estructura fue posible estimar el esfuerzo de manera más precisa y detectar
actividades críticas. La figura corresponde a la línea base; los paquetes de trabajo F3.5 a F3.8 de la versión 2.0 se agregan en la @tabCalendario.

#figure(image("/figures/fig09-gantt-linea-base.png", width: 100%), caption: [Diagrama Gantt (línea base v1.x).]) <figGantt>

El cronograma general se representó con un diagrama Gantt (@figGantt) para visualizar:
- la distribución temporal de actividades;
- las dependencias y la ruta crítica;
- las semanas de contingencia y las actividades paralelas.

El Gantt permitió validar que las actividades más complejas terminarían antes del cierre formal del semestre.

*Estimación de horas-persona.* El esfuerzo total del proyecto fue estimado utilizando horas-persona como unidad principal, considerando 4 integrantes,
10 semanas efectivas de trabajo y aproximadamente 14 horas semanales por integrante: 560 horas-persona = 4 integrantes × 10 semanas × 14
horas/semana. Esta estimación contempla tanto actividades técnicas como documentación, reuniones, pruebas y correcciones.

#figure(
  table(
    columns: (1fr, auto, 2fr),
    table.header([Fase / Componente], [H-P estimadas], [Justificación]),
    [Fase 1 – Comprensión del dominio y datos], [80 h-p], [Exploración de fuentes de datos heterogéneas con análisis de calidad y brechas.],
    [Fase 2 – Preparación de datos (ETL)], [160 h-p], [Componente más complejo: limpieza, matrices O/D, red vial, validación cruzada.],
    [Fase 3 – Construcción del escenario (Sprints 1 a 5)], [240 h-p], [5 sprints × \~40 h/sprint; incluye calibración, escenarios hipotéticos y
    desarrollo del módulo web (backend FastAPI + frontend de visualización).],
    [Fase 3 – Extensión v2.0 (Sprints 6 a 8)], [120 h-p], [Semaforización, simulador 3D comparativo y pendientes (reporte de la comparación,
    programa editable, transporte público con GTFS).],
    [Fase 4 – Evaluación y análisis], [80 h-p], [Validación formal, análisis de resultados, documentación de conclusiones.],
    [Documentación y gestión (transversal)], [80 h-p], [SPMP, SRS, SDD, Plan de pruebas, Informe final, reuniones.],
    [Total], [720 h-p], [Línea base de 600 h-p (560 h-p + 40 h del Sprint 5) más 120 h-p de la extensión v2.0.],
  ),
  caption: [Asignación de recursos por fase.],
) <tabRecursos>

*Estimación de riesgo y contingencia.* El equipo decidió planificar únicamente 10 semanas efectivas de trabajo dentro de un semestre de 16 semanas.
Esta decisión se tomó deliberadamente para disponer de tiempo adicional destinado a:
- corrección de errores y retrasos técnicos;
- ajustes de calibración y revisión documental;
- cambios solicitados por el director;
- problemas de integración y riesgos académicos.

La estrategia busca evitar que el proyecto llegue al cierre del semestre sin margen de maniobra. La extensión v2.0 se planea dentro de ese margen
(semanas 11 a 14), dejando las semanas 15 y 16 para el informe final y la sustentación.

*Validación de las estimaciones.* Las estimaciones fueron revisadas colectivamente y ajustadas durante reuniones con el director del proyecto. Los
principales criterios utilizados para validarlas fueron:
- viabilidad dentro del tiempo disponible;
- consistencia entre alcance y recursos;
- balance de carga entre integrantes;
- riesgo técnico aceptable;
- compatibilidad con otros compromisos académicos.

Las estimaciones podrán ajustarse durante el desarrollo si aparecen riesgos o cambios importantes en el alcance.

== Inicio del Proyecto

=== Entrenamiento del Personal

#figure(
  table(
    columns: (auto, auto, 1fr, auto),
    table.header([Conocimiento / Habilidad], [Estado actual], [Plan de entrenamiento], [Semana]),
    [SUMO (configuración y uso básico)], [Nivel básico], [Tutoriales oficiales SUMO + documentación TraCI + práctica con dataset de ejemplo.], [1–2],
    [netconvert y duarouter], [Sin experiencia], [Práctica guiada con la red OSM de Usaquén descargada.], [2],
    [geopandas y análisis geoespacial], [Nivel básico-intermedio], [Tutoriales de DataCamp + práctica con los datos de aforos y UPZ.], [1–3],
    [pytest y GitHub Actions], [Nivel básico], [Configuración del repositorio con el primer pipeline de CI en la semana 1.], [1],
    [TraCI en vivo y three.js _(v2.0)_], [Nivel básico], [Documentación de TraCI (suscripciones, `getJunctionFoes`) y ejemplos oficiales de
    three.js; prototipo de la escena con una zona recortada.], [11],
  ),
  caption: [Entrenamiento del personal.],
) <tabEntrenamiento>

=== Infraestructura

*Objetivo de la infraestructura del proyecto.* La infraestructura del proyecto tiene como propósito proporcionar un entorno de desarrollo
reproducible, colaborativo y estable que permita ejecutar correctamente el pipeline ETL, las simulaciones SUMO y las actividades de documentación y
validación. Debido a que el proyecto involucra procesamiento de datos, simulación microscópica de tráfico y trabajo colaborativo entre varios
integrantes, la infraestructura debe garantizar:
- compatibilidad entre herramientas y versionamiento adecuado;
- reproducibilidad de resultados e integración continua;
- disponibilidad de datos y colaboración eficiente.

Todas las herramientas seleccionadas son de código abierto o gratuitas para uso académico.

#figure(
  table(
    columns: (1fr, auto, auto),
    table.header([Tarea], [Responsable], [Semana]),
    [Crear repositorio GitHub con estructura base (`src/`, `tests/`, `docs/`, `data/`)], [Erick Salazar], [1],
    [Configurar GitHub Actions con pytest + pylint], [Erick Salazar], [1],
    [Instalar SUMO en los equipos del equipo], [Todos], [1],
    [Configurar entorno virtual Python con `requirements.txt`], [Erick Salazar], [1],
    [Descargar y versionar datasets base (aforos HMD, encuesta, OSM Usaquén)], [Felipe Garrido], [1–2],
    [Configurar GitHub Projects para backlog y burndown chart], [Scrum Master semana 1], [1],
    [_(v2.0)_ Instalar `simulation-service` (`pip install -e ".[dev]"`, SUMO por `eclipse-sumo`) y el visor (`npm install`, `VITE_MAPBOX_TOKEN`)],
    [Todos], [6],
    [_(v2.0)_ Instalar el compilador de documentos Typst (`pip install typst`)], [Responsable de documentación], [11],
  ),
  caption: [Infraestructura y configuración.],
) <tabInfraestructura>

*Configuración inicial del repositorio GitHub.* La primera actividad de infraestructura consiste en la creación del repositorio principal del
proyecto en GitHub. Tareas asociadas:
- crear el repositorio privado inicial;
- definir la estructura de carpetas y configurar las ramas principales;
- definir reglas de merge y convenciones de commits;
- crear el README inicial y configurar permisos de colaboradores.

Responsables: Responsable de infraestructura y Scrum Master del Sprint 1. Momento de ejecución: semana 1. Frecuencia: actividad inicial con
mantenimiento continuo durante todo el proyecto.

*Configuración del entorno Python.* El proyecto utiliza Python como lenguaje principal del pipeline ETL y de integración con SUMO. Tareas asociadas:
- instalar Python 3.11+ y crear el entorno virtual;
- configurar `requirements.txt` (raíz) y `pyproject.toml` (`simulation-service`) e instalar las librerías necesarias;
- verificar compatibilidad entre dependencias y actualizarlas cuando sea necesario.

Responsables: Responsable de infraestructura y todos los integrantes. Momento de ejecución: semana 1. Frecuencia: revisión y mantenimiento semanal.

*Instalación y configuración de SUMO.* SUMO constituye la herramienta central de simulación del proyecto. Tareas asociadas:
- descargar la versión estable de SUMO y configurar las variables de entorno (`SUMO_HOME`);
- verificar el funcionamiento de netconvert y duarouter;
- configurar TraCI, ejecutar simulaciones de prueba y verificar la compatibilidad con Python.

Responsables: Responsable de simulación y Responsable de infraestructura. Momento de ejecución: semana 1. Frecuencia: validación continua al inicio de
cada sprint.

*Configuración de GitHub Actions.* La integración continua permite ejecutar pruebas automáticas y mantener calidad constante del código. Tareas
asociadas:
- configurar los workflows de CI e integrar pytest y pylint;
- verificar la ejecución automática y la validación por pull requests;
- corregir los errores del pipeline de CI.

Responsables: Responsable de infraestructura y Responsable de pruebas. Momento de ejecución: semana 1. Frecuencia: monitoreo continuo por commit.

*Descarga y gestión de datasets.* Los datasets constituyen uno de los activos más importantes del proyecto. Tareas asociadas:
- descargar la Encuesta de Movilidad, los aforos HMD y la red OpenStreetMap;
- verificar la integridad de los archivos y versionar los datasets procesados;
- mantener una estructura organizada de datos y generar respaldos locales.

Responsables: Responsable de datos y Responsable de infraestructura. Momento de ejecución: semanas 1 y 2. Frecuencia: actualización cuando existan
nuevas versiones o correcciones.

*Configuración del sistema de gestión de proyecto.* El seguimiento de tareas se realizará mediante GitHub Projects. Tareas asociadas:
- crear el tablero Kanban y definir las columnas del flujo;
- registrar el backlog inicial y los issues por sprint;
- configurar etiquetas y milestones.

Responsables: Scrum Master y Responsable de infraestructura. Momento de ejecución: semana 1. Frecuencia: actualización diaria.

*Mantenimiento de la infraestructura.* La infraestructura requiere mantenimiento continuo para garantizar estabilidad y reproducibilidad. Actividades
de mantenimiento:
- actualización de dependencias y verificación de compatibilidad;
- respaldo de información crítica;
- monitoreo de los pipelines de CI;
- limpieza de ramas obsoletas;
- corrección de conflictos de versiones y validación periódica de entornos.

Responsables: Responsable de Infraestructura y todos los integrantes para la validación local. Frecuencia: semanal o cuando se detecten problemas.

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([Riesgo], [Impacto], [Mitigación]),
    [Incompatibilidad de versiones], [Alto], [Uso de `requirements.txt` / `pyproject.toml` y documentación detallada],
    [Fallos en GitHub Actions], [Medio], [Validación manual temporal],
    [Pérdida de datos], [Alto], [Backups periódicos y versionamiento],
    [Problemas de instalación de SUMO], [Alto], [Guías compartidas, soporte interno y paquete pip `eclipse-sumo`],
    [Dependencias rotas], [Medio], [Congelamiento de versiones estables (p. ej. `traci==1.27.1`, `three@0.169.0`)],
  ),
  caption: [Riesgos de infraestructura.],
) <tabRiesgosInfra>

== Planes de Trabajo del Proyecto

=== Calendarización con ruta crítica

La siguiente tabla presenta la descomposición completa de actividades (WBS) con la duración estimada, las semanas de ejecución, los prerrequisitos
(actividades que deben estar completas antes de iniciar) y los co-requisitos (actividades que deben ejecutarse en paralelo). Las actividades resaltadas
corresponden a fases de nivel superior; las marcadas _(v2.0)_ son la extensión del alcance, cuyo estado al 13/10/2026 se indica en la última
columna.

El camino crítico del proyecto es: F1.1 #sym.arrow F1.2 #sym.arrow F1.3 #sym.arrow F1.5 #sym.arrow F2.5 #sym.arrow F2.7 #sym.arrow F3.1
#sym.arrow F3.2 #sym.arrow F3.3 #sym.arrow F3.4 #sym.arrow F4.1 #sym.arrow F4.3. Cualquier retraso en estas actividades impacta directamente la
fecha de finalización del proyecto. La extensión v2.0 (F3.6 #sym.arrow F3.7 #sym.arrow F3.8) corre en paralelo a la Fase 4 y no está en el camino
crítico.

#let fase(..c) = c.pos().map(x => table.cell(fill: luma(225))[*#x*])

#figure(
  text(size: 8.5pt, table(
    columns: (7%, 1fr, 7%, 9%, 12%, 8%, 15%),
    table.header([ID], [Actividad], [H-P], [Semana(s)], [Prerreq.], [Co-req.], [Estado]),
    ..fase([F1], [FASE 1 – Comprensión del dominio y los datos], [80 h], [1–3], [—], [—], [Terminada]),
    [F1.1], [Exploración y caracterización de aforos vehiculares HMD], [20 h], [1], [—], [F1.2], [Terminada],
    [F1.2], [Exploración de la Encuesta de Movilidad 2023], [20 h], [1], [—], [F1.1], [Terminada],
    [F1.3], [Evaluación de la red OSM de Bogotá para Usaquén], [16 h], [2], [F1.1, F1.2], [—], [Terminada],
    [F1.4], [Identificación de brechas de datos y calidad], [12 h], [2], [F1.1, F1.2], [F1.3], [Terminada],
    [F1.5], [Definición formal del alcance geográfico y temporal], [12 h], [3], [F1.3, F1.4], [—], [Terminada],
    ..fase([F2], [FASE 2 – Preparación de datos (Pipeline ETL)], [160 h], [3–6], [F1], [—], [Terminada]),
    [F2.1], [Limpieza y validación de registros de aforos], [20 h], [3], [F1.1], [F2.2], [Terminada],
    [F2.2], [Aplicación de factores de ponderación y eliminación de dobles conteos], [24 h], [3–4], [F1.2], [F2.1], [Terminada],
    [F2.3], [Construcción de la demanda O/D por modo y período], [36 h], [4–5], [F2.1, F2.2], [F2.4], [Terminada (ventana AM)],
    [F2.4], [Definición y delimitación de TAZ (UPZ de Usaquén)], [16 h], [4], [F1.5], [F2.3], [Terminada],
    [F2.5], [Procesamiento de red vial con netconvert (`.net.xml`, red 3D con elevación)], [28 h], [5], [F1.3], [—], [Terminada],
    [F2.6], [Generación de archivos vType por modo de transporte], [16 h], [5–6], [F2.3], [F2.5], [Terminada],
    [F2.7], [Validación cruzada O/D + red + aforos (GEH preliminar)], [20 h], [6], [F2.3, F2.5, F2.6], [—], [Pendiente (GEH)],
    ..fase([F3], [FASE 3 – Construcción del escenario (Scrum, Sprints 1 a 8)], [320 h], [6–14], [F2], [—], [En curso]),
    [F3.1], [Sprint 1: Escenario base (`.rou.xml` + ejecución SUMO)], [40 h], [6–7], [F2.7], [—], [Terminada],
    [F3.2], [Sprint 2: Integración transporte público (SITP / TransMilenio)], [40 h], [7–8], [F3.1], [—], [Parcial (como caminata; GTFS en F3.8)],
    [F3.3], [Sprint 3: Integración motocicletas y calibración global del modelo], [40 h], [8–9], [F3.2], [—], [Parcial (calibración pendiente)],
    [F3.4], [Sprint 4: Escenarios hipotéticos (presets de demanda, estilos de conducción, cierres viales, control de tráfico)], [40 h], [9], [F3.3],
    [—], [Terminada],
    [F3.5], [Sprint 5: Módulo web (API, visor kepler.gl, parametrización, precalculadas, progreso y cancelación)], [40 h], [9–10], [F3.4], [—],
    [Terminada],
    [F3.6], [_(v2.0)_ Sprint 6: Intersecciones y semaforización (ficha, programas, Webster, zonas, comparación, priorización)], [40 h], [11–12],
    [F3.5], [—], [Terminada],
    [F3.7], [_(v2.0)_ Sprint 7: Simulador 3D comparativo (semáforo propuesto, lockstep, 3ª persona, HUD, riesgo, minimapa)], [40 h], [12–13],
    [F3.6], [—], [Terminada],
    [F3.8], [_(v2.0)_ Sprint 8: Reporte de la comparación 3D, programa editable del semáforo propuesto, transporte público con GTFS], [40 h],
    [13–14], [F3.7], [F4.1], [Pendiente],
    ..fase([F4], [FASE 4 – Evaluación y análisis], [80 h], [9–14], [F3.5], [—], [Pendiente]),
    [F4.1], [Validación formal del pipeline (GEH < 5 en ≥ 85% de puntos)], [24 h], [9–10], [F3.4], [F4.2], [Pendiente],
    [F4.2], [Verificación de coherencia global del modelo simulado], [20 h], [9–10], [F3.4], [F4.1], [Pendiente],
    [F4.3], [Documentación de conclusiones, limitaciones y trabajo futuro], [36 h], [10–14], [F4.1, F4.2], [—], [Pendiente],
    ..fase([F5], [DOCUMENTACIÓN Y GESTIÓN (transversal)], [80 h], [1–16], [—], [—], [En curso]),
    [F5.1], [Elaboración y actualización del SPMP], [12 h], [1–3, 11], [—], [F5.2], [v2.0],
    [F5.2], [Elaboración del SRS], [16 h], [3–4, 11], [F5.1], [—], [v2.0],
    [F5.3], [Elaboración del SDD], [16 h], [5–6], [F5.2], [—], [Pendiente],
    [F5.4], [Elaboración del Plan de Pruebas], [10 h], [6–7], [F5.2], [—], [Pendiente],
    [F5.5], [Elaboración del Informe Final], [18 h], [14–16], [F4.3], [—], [Pendiente],
    [F5.6], [Reuniones de equipo (lunes) y con director (quincenal)], [8 h], [1–16], [—], [Todos], [En curso],
  )),
  caption: [Calendarización con camino crítico (WBS + prerrequisitos).],
) <tabCalendario>

=== Asignación de responsabilidades por fase

#figure(
  table(
    columns: (1fr, auto, auto, auto, auto),
    table.header([Fase / Actividad], [Samuel Campos], [Erick Salazar], [Santiago Chitiva], [Felipe Garrido]),
    [Fase 1 – Dominio y datos], [Líder], [Co-líder], [Apoyo], [Apoyo],
    [Fase 2 – Pipeline ETL], [Co-líder (O/D)], [Co-líder (limpieza)], [Líder (red OSM)], [Apoyo (validación)],
    [Fase 3 – Escenarios (Scrum)], [Apoyo], [Apoyo (pruebas)], [Co-líder (simulación)], [Líder (calibración)],
    [Fase 3 – Módulo Web], [Apoyo], [Líder], [Apoyo], [Apoyo],
    [Fase 3 – Semaforización y simulador 3D _(v2.0)_], table.cell(colspan: 4, align: center)[Por definir en la planeación de los Sprints 6 a 8],
    [Fase 4 – Evaluación], [Apoyo], [Líder (métricas)], [Apoyo], [Co-líder (análisis)],
    [Documentación], [SRS], [Plan de pruebas], [SDD / Informe], [SPMP / Informe],
  ),
  caption: [Asignación de responsabilidades por fase e integrante.],
) <tabAsignacion>
