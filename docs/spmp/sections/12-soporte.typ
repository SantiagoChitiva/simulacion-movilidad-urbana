= Procesos de Soporte

== Ambiente de Trabajo

El equipo opera bajo las siguientes reglas de trabajo:
- Dos reuniones semanales fijas: lunes (planeación y seguimiento, 1 hora) y viernes (revisión y retrospectiva, 30 minutos).
- Toda comunicación técnica y de decisiones relevantes debe quedar documentada en GitHub (Issues, Pull Requests, comentarios).
- El código se escribe en ramas `feat/*` y solo se integra a `develop` cuando es aprobado por al menos un compañero.
- Los documentos formales se redactan colaborativamente en Typst dentro del repositorio y se compilan a PDF para cada entrega.
- Los integrantes deben avisar con 48 horas de anticipación si no pueden asistir a una reunión o cumplir un compromiso.
- Las decisiones técnicas que afecten el diseño global se documentan como Architecture Decision Records (ADR) en el repositorio (p. ej.
  `docs/propuesta-semaforizacion-3d.md`).
- Siempre se priorizarán soluciones bien fundamentadas sobre soluciones rápidas.
- Siempre se priorizará la colaboración sobre el trabajo individual.
- Siempre se priorizará el impacto a largo plazo sobre los resultados a corto plazo.
- Cada integrante es responsable de sus tareas, pero puede pedir ayuda cuando lo necesite.
- Los compromisos adquiridos en reuniones deben cumplirse en los tiempos acordados.
- Se documentarán los acuerdos y decisiones importantes al finalizar cada reunión por escrito.
- Las decisiones se tomarán entre todos buscando consenso. Si no se llega a consenso, se decidirá por votación.
- Quien tenga mayor conocimiento técnico sobre un tema liderará las decisiones de esa área.
- Si una decisión resulta incorrecta, el equipo buscará una solución sin señalar ni culpar a ningún integrante.
- El feedback entre integrantes del grupo debe ser claro, respetuoso y basado en hechos concretos, nunca en ataques personales.
- Si algo incomoda o genera conflicto, debe comunicarse pronto, antes de que escale.
- Ninguna idea será descartada sin análisis previo.
- En las reuniones, todos deben tener espacio para hablar. Si alguien no participa, se le invitará respetuosamente a opinar.
- Las reuniones deben terminar con acciones concretas y un responsable asignado para cada una.
- Los errores se usan para mejorar, no para señalar a un compañero.
- Se respetarán los tiempos y espacios personales de cada integrante sin descuidar el compromiso grupal.
- Trabajar de forma aislada sin compartir avances con el equipo no está permitido.

== Análisis y Administración de Riesgos

#figure(image("/figures/fig04-bpmn-riesgos.png", width: 100%), caption: [Diagrama BPMN – Proceso de identificación y seguimiento de riesgos.]) <figBpmnRiesgos>

El flujo de la @figBpmnRiesgos muestra el ciclo por sprint: identificar riesgo #sym.arrow evaluar probabilidad e impacto #sym.arrow clasificar
prioridad #sym.arrow asignar plan de mitigación #sym.arrow monitorear en el siguiente sprint #sym.arrow actualizar el registro. Roles: Scrum Master
(responsable del registro), equipo de desarrollo.

*Registro de Riesgos*

#figure(
  table(
    columns: (auto, 1fr, auto, auto, auto),
    table.header([ID], [Descripción del riesgo], [Prob.], [Impacto], [Prioridad]),
    [R1], [Calidad insuficiente de los datos de la Encuesta de Movilidad para construir matrices O/D representativas.], [Alta], [Alto], [Crítica],
    [R2], [Red vial de OSM incompleta o con errores geométricos en Usaquén.], [Media], [Alto], [Alta],
    [R3], [SUMO no puede simular el escenario generado por el pipeline (archivos inválidos o incompatibles).], [Media], [Alto], [Alta],
    [R4], [Estimación de tiempo insuficiente para la calibración del modelo (GEH no alcanzable en 10 semanas).], [Media], [Medio], [Media],
    [R5], [Baja disponibilidad de un integrante del equipo por compromisos académicos o personales.], [Baja], [Alto], [Media],
    [R6], [Datos de aforos HMD insuficientes para cubrir todos los puntos de validación de Usaquén.], [Media], [Medio], [Media],
    [R7], [Conflictos de integración en el repositorio por trabajo simultáneo en ramas.], [Alta], [Bajo], [Media],
    [R8 _(v2.0)_], [El simulador 3D no alcanza una animación fluida en equipos sin GPU dedicada (dos escenas 3D más dos SUMO en vivo).], [Media],
    [Medio], [Media],
    [R9 _(v2.0)_], [Las conclusiones sobre semáforos se basan en programas generados por netconvert y en tráfico de fondo sintético, no en programas
    ni aforos reales del cruce.], [Alta], [Alto], [Alta],
    [R10 _(v2.0)_], [Las pruebas de `simulation-service` no corren en el CI (solo las de la raíz), por lo que una regresión puede llegar a `main`.],
    [Media], [Medio], [Media],
    [R11 _(v2.0)_], [Dependencia de servicios externos para los mapas base (token de Mapbox y teselas de OpenStreetMap).], [Baja], [Bajo], [Baja],
  ),
  caption: [Registro de riesgos identificados.],
) <tabRiesgos>

*Plan de Mitigación*

#figure(
  table(
    columns: (auto, 1fr, 1fr, auto),
    table.header([ID], [Prevención], [Mitigación (si ocurre)], [Responsable]),
    [R1], [Exploración temprana de la encuesta en Fase 1 con análisis de calidad y cobertura.], [Reducir el alcance a las UPZ con mayor cobertura
    muestral.], [Samuel / Erick],
    [R2], [Inspección manual de la red OSM en QGIS antes de iniciar Fase 2.], [Corrección de geometrías con JOSM o parámetros de netconvert.],
    [Santiago],
    [R3], [Pruebas de integración del pipeline contra SUMO desde el Sprint 1.], [Depuración de archivos XML con herramientas de validación de SUMO.],
    [Felipe / Santiago],
    [R4], [Definir GEH como criterio aspiracional (no bloqueante) en sprints intermedios.], [Ajustar el criterio de "done" o reducir modos integrados
    en acuerdo con el director.], [Director + equipo],
    [R5], [Documentación continua del conocimiento en el repositorio (README, docstrings).], [Redistribuir tareas entre los tres integrantes
    restantes.], [Scrum Master],
    [R8], [Fusionar las geometrías estáticas por material, limitar la resolución del render y recortar la zona a 350 m.], [Cámara aérea con menos
    detalle o una sola vista a la vez.], [Responsable de simulación],
    [R9], [Mostrar en el visor la fuente de la demanda (real / sintética) y el origen del programa; usar viajes reales recortados cuando existan.],
    [Calibrar el tráfico de fondo con aforos del cruce y ajustar el programa con Webster (RF-042).], [Responsable de simulación + datos],
    [R10], [Ejecutar `pytest` de `simulation-service` antes de cada pull request.], [Agregar el job de `simulation-service` al workflow de GitHub
    Actions.], [Responsable de pruebas],
    [R11], [Documentar el token en `kepler/.env.example`.], [Cambiar a otro proveedor de teselas en `Minimapa.jsx` / kepler.gl.], [Responsable de
    infraestructura],
  ),
  caption: [Plan de mitigación de riesgos prioritarios.],
) <tabMitigacion>

== Administración de Configuración y Documentación

#figure(image("/figures/fig05-bpmn-configuracion.png", width: 70%), caption: [Diagrama BPMN – Proceso de control de configuración.]) <figBpmnConf>

El flujo de la @figBpmnConf muestra:
+ cambio en código o documento;
+ creación de una rama `feat/*` y desarrollo;
+ pull request y revisión por pares (al menos un aprobador);
+ ejecución automática del CI (GitHub Actions);
+ merge a `develop`, validación final y release a `main`.

Roles: desarrollador, revisor y CI automático.

*Ítems de Configuración*

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([Ítem de configuración], [Tipo], [Ubicación en el repositorio]),
    [Pipeline ETL y pasos de SUMO], [Software], [`simulation-service/src/etl/` (`etl.py`, `sumo/*.py`)],
    [API (REST + WebSocket) y gestor de corridas], [Software], [`simulation-service/src/api/`],
    [Visor web y simulador 3D], [Software], [`kepler/src/` (`components/simulador3d/`)],
    [Pruebas unitarias e integración (pytest)], [Software], [`simulation-service/test/` y `tests/` (raíz)],
    [Escenario por defecto (red 3D, TAZ, TSV, plantilla `.sumocfg`)], [Datos / configuración], [`simulation-service/src/etl/sumo/scenarios/default/`],
    [Simulaciones precalculadas], [Artefacto versionado], [`simulation-service/precalculadas/<preset>/`],
    [Corridas, zonas y comparaciones 3D], [Artefacto generado (no versionado)], [`simulation-service/runs/`],
    [SPMP], [Documento (Typst + PDF)], [`docs/spmp/`],
    [SRS], [Documento (Typst + PDF)], [`docs/srs/`],
    [VFP (propuesta)], [Documento (Typst + PDF)], [`docs/vfp/`],
    [SDD], [Documento], [`docs/sdd/`],
    [Plan de Pruebas], [Documento], [`docs/testing/`],
    [Informe Final], [Documento], [`docs/informe-final/`],
    [Datos de entrada (aforos, encuesta, OSM)], [Datos], [`data/raw/` (Google Drive; no versionados en Git)],
    [Red, TAZ, edificios y artefactos de los notebooks], [Artefacto generado], [`data/processed/`],
    [Notebooks CRISP-DM], [Software], [`notebooks/` (`F1.x`, `F2.x`)],
    [Dependencias], [Configuración], [`requirements.txt` (raíz), `simulation-service/pyproject.toml`, `kepler/package.json`],
    [Configuración de GitHub Actions (`.yml`)], [Configuración CI], [`.github/workflows/`],
  ),
  caption: [Ítems de configuración.],
) <tabItems>

*Ciclo de Vida de Artefactos*

#figure(
  table(
    columns: (1fr, auto, 1fr),
    table.header([Artefacto], [Se crea en], [Se actualiza en]),
    [SPMP], [Semana 1–3], [Cada entrega formal del proyecto (v2.0: semana 11)],
    [SRS], [Semana 3–4], [Si hay cambios de requerimientos aprobados (v2.0: semana 11)],
    [SDD], [Semana 5–6], [Con cambios de diseño durante Fase 3],
    [Plan de Pruebas], [Semana 6–7], [Con cambios de diseño o SRS],
    [Código fuente], [Desde semana 1], [Continuo (por commit)],
    [Simulaciones precalculadas], [Sprint 5], [Cuando cambian la red, la TAZ, la encuesta o la plantilla `.sumocfg` (su `meta.json` lo detecta)],
    [Informe Final], [Semana 9], [Semanas 9–16],
    [Registro de riesgos], [Semana 1], [Inicio de cada sprint],
  ),
  caption: [Ciclo de vida de artefactos.],
) <tabCicloArtefactos>

== Métricas y Proceso de Medición

#figure(
  table(
    columns: (1fr, auto, auto, auto, 1fr),
    table.header([Métrica], [Sección de uso], [Quién recolecta], [Cuándo], [Herramienta]),
    [Tareas completadas / sprint], [10.2], [Scrum Master], [Fin de sprint], [GitHub Projects],
    [Burndown del sprint], [10.2], [Scrum Master], [Diario], [GitHub Projects],
    [Cobertura de pruebas (%)], [10.2], [CI automático], [Por commit], [pytest-cov + GitHub Actions],
    [Pruebas automatizadas que pasan], [10.2], [Responsable de pruebas], [Por commit], [pytest (`simulation-service/test/`)],
    [GEH por punto de aforo], [8.3 / 10.2], [Responsable de simulación], [Fin de sprint de simulación], [Script Python + salida SUMO],
    [RMSE del modelo], [8.3 / 10.2], [Responsable de simulación], [Fin de Fase 3 y Fase 4], [Script Python],
    [Desempeño del simulador 3D (frames/s, tiempo de preparación)], [8.3], [Responsable de simulación], [Fin del Sprint 7 y 8], [Script de integración
    por WebSocket + perfil del navegador],
    [Velocidad del equipo], [10.2], [Scrum Master], [Fin de sprint], [GitHub Projects],
  ),
  caption: [Métricas y proceso de medición.],
) <tabMedicion>

== Control de Calidad

#figure(image("/figures/fig06-bpmn-calidad.png", width: 70%), caption: [Diagrama BPMN – Proceso de control de calidad.]) <figBpmnCalidad>

La @figBpmnCalidad muestra los tres niveles de calidad:
+ *código:* revisión por pares en cada PR y CI automático (pytest + pylint);
+ *modelo de simulación:* validación GEH al cierre de cada sprint de simulación;
+ *documentos formales:* revisión con checklist por estándar antes de cada entrega y auditoría de trazabilidad SRS #sym.arrow.l.r código
  #sym.arrow.l.r pruebas.

Roles: desarrollador, revisor, director y CI automático.

#figure(
  table(
    columns: (1fr, auto, auto, 1fr),
    table.header([Proceso de calidad], [Momento], [Responsable], [Herramienta]),
    [Revisión de cambios (peer review)], [Por cada PR], [Al menos 1 compañero], [GitHub PR reviews],
    [Pruebas unitarias automatizadas (CI)], [Por cada commit], [GitHub Actions], [pytest + pylint],
    [Compilación del visor], [Por cada PR que toque `kepler/`], [Autor del cambio], [`npm run build`],
    [Validación GEH del modelo], [Fin de cada sprint de simulación], [Responsable de simulación], [Script Python + aforos reales],
    [Revisión formal de documentos], [Antes de cada entrega formal], [Equipo + director], [Checklist por estándar IEEE + compilación Typst],
    [Retrospectiva de sprint], [Fin de cada sprint], [Scrum Master], [Registro de lecciones aprendidas],
    [Auditoría de trazabilidad SRS #sym.arrow.l.r código #sym.arrow.l.r pruebas], [Antes de cada entrega formal], [Responsable de documentación],
    [Matriz de trazabilidad (columna Estado del SRS)],
  ),
  caption: [Procesos de control de calidad.],
) <tabCalidad>
