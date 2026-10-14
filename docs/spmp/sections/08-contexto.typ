= Contexto del Proyecto

== Modelo de Ciclo de Vida

#figure(image("/figures/fig01-ciclo-vida-alto-nivel.png", width: 100%), caption: [Diagrama alto nivel del modelo de ciclo de vida.]) <figCicloAlto>

*Descripción del Modelo.* El proyecto adopta un modelo de ciclo de vida híbrido que combina CRISP-DM @crispdm para las fases intensivas en datos
(Fases 1 y 2) con Scrum @scrum para la construcción iterativa del escenario de simulación (Fase 3). La Fase 4 de evaluación retoma la estructura de
CRISP-DM (véase la @figCicloAlto).

Las Fases 1 y 2 siguen CRISP-DM porque el trabajo en esa etapa es de naturaleza exploratoria y analítica: comprender las fuentes de datos, evaluar su
calidad, identificar brechas y construir el pipeline ETL. A partir de la Fase 3, el proyecto migra a Scrum con sprints semanales, dado que el trabajo
pasa a ser incremental y orientado a componentes verificables de software. Además, se aplicará el tablero visual de la metodología Kanban para
gestionar las tareas.

#figure(image("/figures/fig02-bpmn-ciclo-vida.png", width: 100%), caption: [Diagrama BPMN – Modelo de ciclo de vida híbrido CRISP-DM / Scrum.]) <figCicloBpmn>

La @figCicloBpmn muestra las 4 fases del proyecto, la transición entre metodologías, los roles involucrados en cada fase y los artefactos que produce
cada una (matrices O/D, red `.net.xml`, código Python, reportes GEH). En la versión 2.0 la Fase 3 se extiende con los Sprints 5 a 8 (ver 9.3.1); la
estructura de fases no cambia.

*Análisis de Alternativas.* Se evaluaron los siguientes modelos de ciclo de vida antes de seleccionar el híbrido:
- *Cascada:* descartado por su rigidez ante cambios en la calidad de los datos de entrada, que no se conoce hasta la exploración.
- *CRISP-DM puro:* insuficiente para la Fase 3, que requiere gestión de sprints y entregas incrementales de software.
- *RUP:* se descartó por su excesiva burocracia que podría frenar la agilidad del análisis.
- *Híbrido CRISP-DM + Scrum + Kanban:* modelo que combina exploración de datos iterativa con entregas incrementales de software.

*Prácticas Específicas*
- Control de versiones: Git + GitHub con ramas por sprint (`main`, `develop`, `feat/*`).
- Revisiones de código: revisión obligatoria de al menos un compañero antes de hacer merge a cada cambio.
- Integración continua: GitHub Actions para ejecutar pruebas unitarias automáticamente en cada commit.
- Reuniones de equipo: dos reuniones semanales (lunes: planeación/seguimiento; viernes: revisión).
- Reunión con director: una vez a la semana, al cierre de cada sprint.
- Definición de "done" para simulación: componente validado con GEH < 5 en al menos el 85% de los puntos de aforo.
- Definición de "done" para software (v2.0): pruebas automatizadas del módulo en `simulation-service/test/` en verde, `npm run build` del visor sin
  errores y demostración del flujo en el visor.

== Lenguajes y Herramientas

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    table.header([Herramienta], [Propósito], [Justificación]),
    [Python 3.11+], [Lenguaje principal del pipeline ETL, la API y el control de SUMO], [Ecosistema estándar para análisis de datos. Requerido por la
    API TraCI de SUMO.],
    [FastAPI + Uvicorn], [Backend REST y WebSocket del módulo web], [Herramienta flexible y fácil de configurar; soporta WebSocket para el simulador
    en vivo.],
    [SUMO 1.27 (`eclipse-sumo`)], [Motor de simulación microscópica de tráfico], [Herramienta de código abierto estándar. Única alternativa open
    source con soporte multimodal completo. Instalada con pip, deja `sumo`, `netconvert` y `duarouter` en el entorno virtual.],
    [TraCI / sumolib 1.27.1], [Control en vivo de SUMO y lectura de la red], [Permite medir el avance real de las corridas y correr las dos
    simulaciones del simulador 3D en lockstep.],
    [pandas / geopandas], [Procesamiento de datos tabulares y geoespaciales], [Estándar de Python para ETL de datos estructurados y geoespaciales.],
    [OpenStreetMap + osmium], [Fuente y procesamiento de la red vial], [Única fuente gratuita con cobertura global y nivel de detalle suficiente.],
    [netconvert / duarouter / cutRoutes / randomTrips], [Conversión OSM a `.net.xml`, rutas, recorte de demanda y tráfico de fondo], [Herramientas
    oficiales del ecosistema SUMO; garantizan compatibilidad.],
    [React 18 + Vite], [Visor web (`kepler/`)], [Componentes reutilizables y servidor de desarrollo con proxy HTTP/WebSocket a la API.],
    [kepler.gl 3.1], [Mapa animado de viajes y capas de semáforos y priorización], [Capa de trayectorias nativa para miles de viajes.],
    [three.js 0.169 + maplibre-gl 4.7], [Render 3D del simulador y minimapa 2D], [three.js da control total de la cámara en tercera persona;
    maplibre no requiere token para teselas OSM.],
    [Git + GitHub], [Control de versiones y repositorio del proyecto], [Estándar de la industria. Permite colaboración distribuida y control de
    cambios.],
    [GitHub Actions], [Integración continua (CI)], [Gratuito. Automatiza la ejecución de pruebas en cada commit.],
    [pytest], [Pruebas unitarias e integración], [Estándar de facto para pruebas en Python. Integración nativa con GitHub Actions.],
    [Jupyter Notebooks], [Exploración y caracterización de datos (Fases 1 y 2)], [Permite análisis exploratorio iterativo con visualización
    integrada.],
    [QGIS], [Validación geoespacial de la red vial y TAZ], [Herramienta GIS de código abierto; integración con OSM y geopandas.],
    [Typst], [Documentos formales (SPMP, SRS, VFP)], [Fuente de texto versionable en Git; compila a PDF en segundos.],
  ),
  caption: [Herramientas y lenguajes del proyecto.],
) <tabHerramientas>

=== Análisis de Alternativas y Justificación

- *Backend:* FastAPI frente a Flask o Django. FastAPI valida las solicitudes con Pydantic, genera la documentación en `/docs` y soporta WebSocket de
  forma nativa, lo que el simulador 3D necesita.
- *Visor de resultados:* kepler.gl frente a Leaflet o deck.gl directo. kepler.gl ya trae la capa de trayectorias animadas, la línea de tiempo y
  filtros, lo que evita reimplementarlos.
- *Render 3D:* three.js frente a deck.gl o la interfaz gráfica de SUMO (sumo-gui). deck.gl está pensado para vistas cartográficas y no ofrece una
  cámara de persecución; sumo-gui no se integra al navegador. three.js permite construir la escena desde la geometría de la red y controlar la cámara
  libremente.
- *Documentos:* Typst frente a Word o LaTeX. Es texto plano, por lo que se versiona y revisa en GitHub como el código, y es más sencillo que LaTeX.

== Plan de Aceptación del Producto

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([Entregable], [Criterio de aceptación], [Herramienta de verificación]),
    [SPMP], [Cubre todas las secciones del estándar IEEE 1058. Consistencia interna entre secciones. Aprobado por el director.], [Revisión documental del
    director],
    [SRS], [Requerimientos trazables, no ambiguos y verificables. Matriz de trazabilidad incluida.], [Revisión formal + checklist IEEE 830],
    [SDD], [Arquitectura documentada. Decisiones de diseño justificadas. Trazabilidad con SRS.], [Revisión formal del director],
    [Plan de Pruebas], [Cobertura del 100% de los requerimientos funcionales del SRS.], [Matriz de trazabilidad SRS-pruebas],
    [Código fuente], [Pasa el 90% de las pruebas unitarias. Cumple PEP 8. Documentado con docstrings.], [pytest + GitHub Actions + pylint],
    [Pipeline validado], [GEH < 5 en al menos el 85% de los puntos de aforo. Ejecutable en SUMO sin errores.], [Métricas GEH y RMSE vs. aforos
    reales],
    [Informe final], [Incluye todos los elementos del IEEE 1063-2001. Aprobado por jurados.], [Revisión de jurados en la exposición],
    [Módulo web], [Permite visualizar métricas de SUMO. Permite lanzar una simulación parametrizada exitosamente desde la interfaz.], [Prueba funcional
    manual + revisión del director],
    [Módulo de semaforización _(v2.0)_], [Muestra la ficha de cualquier semáforo con volúmenes por acceso, guarda un programa válido, calcula Webster y
    lista los cruces prioritarios sin semáforo.], [Pruebas automatizadas + demostración],
    [Simulador 3D comparativo _(v2.0)_], [Para un cruce prioritario prepara la comparación en menos de 60 s y muestra los dos lados a 4 frames/s o
    más. Permite seguir un vehículo y un peatón con HUD de velocidad, riesgo y decisiones, y el minimapa los ubica.], [Prueba de integración +
    demostración ante el director],
  ),
  caption: [Criterios de aceptación de entregables.],
) <tabAceptacion>

== Organización del Proyecto y Comunicación

=== Interfaces Externas

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([Entidad], [Rol en el proyecto], [Medio de contacto]),
    [Ing. Andrés Calderón Romero (Director)], [Revisor, aprobador de entregables y asesor técnico], [andrescalderonr\@javeriana.edu.co / Teams],
    [Secretaría Distrital de Movilidad], [Propietaria de los datos de entrada (encuesta y aforos)], [Portal de datos abiertos de Bogotá],
    [Jurados evaluadores], [Evaluación final del proyecto de grado], [Coordinación académica],
    [OpenStreetMap Community], [Fuente de la red vial base del modelo y de las teselas del minimapa], [openstreetmap.org],
  ),
  caption: [Entidades externas e interfaces.],
) <tabInterfaces>

=== Roles del Equipo

La estructura organizacional del equipo se presenta en la @figOrganigrama.

#figure(image("/figures/fig07-organigrama.png", width: 85%), caption: [Organigrama del equipo de desarrollo.]) <figOrganigrama>

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Rol], [Integrante(s)], [Responsabilidades principales]),
    [Scrum Master (rotativo por sprint)], [Rotación entre integrantes], [Facilitar ceremonias Scrum y actualizar burndown chart.],
    [Responsable de datos], [], [Liderar Fases 1 y 2 (CRISP-DM): exploración, limpieza, matrices O/D.],
    [Responsable de simulación], [], [Liderar Fase 3 (Scrum): construcción y calibración del escenario en SUMO.],
    [Responsable de documentación], [Rotación por entregable], [Coordinar redacción y revisión de cada entregable formal.],
    [Responsable de pruebas], [], [Definir y ejecutar pruebas unitarias del pipeline y validación del modelo.],
    [Responsable de infraestructura], [], [Configurar y mantener GitHub, Actions, entornos Python y SUMO.],
  ),
  caption: [Roles del equipo y responsabilidades.],
) <tabRoles>

*Scrum Master.* Integrantes responsables: rotativo por sprint entre todos los integrantes. El rol de Scrum Master se implementa de manera rotativa
para garantizar que todos los integrantes participen activamente en la gestión del proyecto y comprendan el estado global del desarrollo. Cada sprint
tiene un Scrum Master diferente, responsable de coordinar las actividades del equipo durante ese período.

Responsabilidades principales:
- Planificar y moderar las reuniones semanales de seguimiento.
- Coordinar la reunión de planeación al inicio de cada sprint.
- Actualizar el backlog del proyecto en GitHub Projects.
- Mantener actualizado el burndown chart y las métricas de avance.
- Verificar que las tareas asignadas tengan responsables y fechas definidas.
- Identificar bloqueos técnicos u organizacionales.
- Escalar problemas críticos al director cuando sea necesario.
- Facilitar la comunicación entre los integrantes.
- Coordinar retrospectivas al cierre de cada sprint.
- Garantizar que las actividades priorizadas estén alineadas con los objetivos del sprint.

Responsabilidades de comunicación: el Scrum Master es responsable de consolidar el estado semanal del proyecto y comunicarlo durante las reuniones
con el director. También debe asegurar que todas las decisiones importantes queden registradas en GitHub Issues o en la documentación formal
correspondiente.

Entregables asociados: backlog actualizado, burndown charts, registro de reuniones, registro de retrospectivas y seguimiento de issues y tareas.

*Responsable de Datos.* Lidera las actividades relacionadas con adquisición, limpieza, análisis, transformación y validación de los datos de entrada
utilizados por el sistema. Este rol tiene especial relevancia durante las Fases 1 y 2 del proyecto, correspondientes a comprensión del dominio y
preparación de datos bajo CRISP-DM.

Responsabilidades principales:
- Analizar la estructura de la Encuesta de Movilidad 2023.
- Comprender y documentar la estructura de los aforos vehiculares HMD.
- Validar calidad, consistencia y cobertura de los datos.
- Diseñar el pipeline ETL de procesamiento.
- Implementar scripts de limpieza y transformación.
- Aplicar factores de expansión muestral.
- Construir matrices origen-destino.
- Verificar consistencia estadística de los resultados.
- Gestionar los datasets del proyecto.
- Documentar supuestos y limitaciones de los datos.
- Coordinar validaciones cruzadas entre aforos y matrices O/D.

Responsabilidades técnicas: el Responsable de Datos también debe garantizar que los formatos generados sean compatibles con las herramientas del
ecosistema SUMO, particularmente con duarouter y netconvert. Asimismo, debe asegurar que los scripts sean reproducibles y correctamente documentados,
permitiendo que cualquier integrante pueda ejecutar nuevamente el pipeline con los mismos resultados.

- Herramientas asociadas: Python, pandas, geopandas, Jupyter Notebooks, OpenStreetMap y GitHub.
- Entregables asociados: scripts ETL, matrices O/D, reportes de calidad de datos, archivos procesados de entrada y validaciones estadísticas.

*Responsable de Simulación.* Lidera todas las actividades relacionadas con la construcción, calibración y ejecución de escenarios dentro del
simulador SUMO. Este rol tiene especial relevancia durante la Fase 3 del proyecto, correspondiente a la construcción iterativa del escenario de
simulación. En la versión 2.0 incluye la definición de las zonas, del semáforo propuesto y de los indicadores de riesgo del simulador 3D.

Responsabilidades principales:
- Configurar SUMO y las herramientas complementarias.
- Procesar la red vial mediante netconvert.
- Configurar escenarios de simulación.
- Generar archivos `.rou.xml` y de tipos de vehículo.
- Integrar modos de transporte dentro del simulador.
- Ajustar parámetros de comportamiento vehicular.
- Ejecutar simulaciones de validación.
- Analizar resultados de congestión y movilidad.
- Implementar escenarios hipotéticos.
- Verificar que las simulaciones sean reproducibles.
- Documentar parámetros de calibración utilizados.

Responsabilidades de validación: el Responsable de Simulación debe verificar que las simulaciones ejecuten correctamente y que los resultados
producidos mantengan coherencia con los patrones observados en los datos reales. Además, debe coordinar la validación mediante métricas GEH y RMSE
junto con el Responsable de Pruebas.

- Herramientas asociadas: SUMO, netconvert, duarouter, TraCI, Python y QGIS.
- Entregables asociados: escenarios SUMO, archivos de rutas, archivos de tipos de vehículo, resultados de simulaciones, reportes de calibración y
  escenarios hipotéticos.

*Responsable de Pruebas y Validación.* Tiene como propósito garantizar la calidad técnica del sistema y verificar que los resultados producidos por
el pipeline sean consistentes y correctos.

Responsabilidades principales:
- Diseñar casos de prueba del pipeline ETL.
- Diseñar pruebas unitarias para scripts críticos.
- Configurar pytest y GitHub Actions.
- Ejecutar pruebas automáticas.
- Analizar resultados de cobertura.
- Validar consistencia de archivos generados.
- Verificar métricas GEH y RMSE.
- Coordinar validación funcional del pipeline.
- Registrar defectos encontrados.
- Realizar seguimiento de errores reportados.
- Verificar corrección de errores.

Responsabilidades de calidad: este rol debe asegurar que cada incremento del proyecto cumpla con la definición de "done" establecida por el equipo.
También es responsable de garantizar que los cambios realizados no introduzcan regresiones en funcionalidades previamente validadas.

- Herramientas asociadas: pytest, GitHub Actions, pylint, Python y GitHub Issues.
- Entregables asociados: casos de prueba, reportes de cobertura, registro de defectos, validaciones GEH y resultados de pruebas.

*Responsable de Infraestructura.* Administra los entornos de desarrollo y garantiza que el equipo disponga de las herramientas necesarias para
ejecutar el proyecto de manera estable y reproducible.

Responsabilidades principales:
- Configurar el repositorio principal en GitHub.
- Definir la estructura de carpetas del proyecto.
- Configurar GitHub Actions.
- Mantener actualizados `requirements.txt` y `pyproject.toml`.
- Configurar entornos virtuales Python.
- Gestionar versiones de SUMO.
- Verificar compatibilidad entre herramientas.
- Gestionar el almacenamiento de datasets.
- Administrar permisos y ramas del repositorio.
- Verificar respaldos y versionamiento.

Responsabilidades operativas: el Responsable de Infraestructura debe apoyar a los demás integrantes cuando existan problemas de instalación,
dependencias o conflictos de configuración. También debe garantizar que la infraestructura utilizada permita la ejecución reproducible del pipeline en
diferentes equipos.

- Herramientas asociadas: GitHub, Git, GitHub Actions, Python, SUMO, Node.js y Google Colab.
- Entregables asociados: repositorio configurado, integración continua funcional, entornos reproducibles y configuración de herramientas.

*Responsable de Documentación.* Integrantes responsables: rotativo por entregable. Coordina la elaboración, revisión y consolidación de todos los
documentos formales del proyecto.

Responsabilidades principales:
- Coordinar la redacción de entregables.
- Verificar consistencia entre documentos.
- Mantener formato y estructura de estándares IEEE.
- Consolidar diagramas y tablas.
- Actualizar el historial de cambios.
- Gestionar referencias bibliográficas.
- Revisar ortografía y redacción.
- Verificar trazabilidad entre documentos.
- Coordinar revisiones internas.
- Incorporar observaciones del director.

Responsabilidades de calidad documental: el Responsable de Documentación debe garantizar que todos los documentos mantengan coherencia con el estado
actual del proyecto y con las decisiones tomadas durante el desarrollo. Asimismo, debe asegurar que las versiones entregadas cumplan con los
lineamientos establecidos por la Pontificia Universidad Javeriana y los estándares IEEE seleccionados.

Entregables asociados: SPMP, SRS, SDD, plan de pruebas, informe final, diagramas BPMN, tablas y anexos.

*Responsabilidad compartida del equipo.* Aunque existen roles especializados, el proyecto adopta un enfoque colaborativo donde todos los integrantes
participan activamente en decisiones críticas relacionadas con arquitectura, calidad, alcance y validación. Las siguientes actividades son
responsabilidad compartida del equipo:
- Participación en reuniones semanales.
- Revisión de código.
- Revisión de documentación.
- Discusión de decisiones técnicas.
- Identificación de riesgos.
- Resolución de problemas críticos.
- Planeación de sprints.
- Presentaciones y sustentaciones.

El equipo considera que esta distribución balanceada de responsabilidades permite reducir dependencias críticas entre integrantes y aumentar la
resiliencia del proyecto frente a retrasos o dificultades técnicas.
