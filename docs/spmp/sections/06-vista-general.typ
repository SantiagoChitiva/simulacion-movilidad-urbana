= Vista General del Proyecto

== Visión del Producto

Bogotá enfrenta uno de los problemas de congestión vehicular más severos del mundo: según el TomTom Traffic Index 2025, ocupa el séptimo lugar global
con un índice del 69,9% y velocidades promedio en horas pico que apenas superan los 15 km/h. Pese a la existencia de herramientas de simulación de
tráfico de clase mundial como SUMO @sumo, su uso por parte de planificadores y analistas de movilidad está limitado por la alta complejidad técnica que
implica transformar datos reales de movilidad en los formatos de entrada que el simulador requiere.

La visión del producto es reducir esa barrera con un módulo de procesamiento de datos que, a partir de la Encuesta de Movilidad de Bogotá 2023
@encuesta y datos de aforos vehiculares, genere automáticamente los archivos necesarios para ejecutar simulaciones en SUMO. El sistema permite a
investigadores y analistas explorar escenarios hipotéticos de movilidad sin necesidad de intervención manual en la preparación de datos.

El alcance de la versión 1 del proyecto está delimitado a la localidad de Usaquén como caso piloto, con un diseño orientado a escalar a todas las
localidades de Bogotá en versiones futuras. El sistema comprende dos módulos: un módulo de procesamiento de datos (pipeline ETL) y un módulo web para
la visualización interactiva de resultados y la parametrización de nuevas simulaciones, ambos incluidos en el alcance actual por instrucción del
director del proyecto.

*Versión 2.0.* Con el pipeline y el visor operativos, el producto avanza hacia el análisis de *control de tráfico* previsto en el Sprint 4. Se
agregan:
- un módulo de intersecciones con ficha, edición de programas, Webster, recorte de zonas, comparación de programas y priorización de cruces;
- un *simulador 3D comparativo* que muestra en pantalla partida un cruce sin semáforo y el mismo cruce con un semáforo propuesto.

El simulador usa la red 3D real de Usaquén, los edificios y la demanda de la encuesta. Permite seguir en tercera persona a un vehículo o peatón y ver
en pantalla su velocidad, su nivel de riesgo y las decisiones que toma, para hacer tangible el efecto de la intervención antes de implementarla.

== Propósito, Alcance y Objetivos

*Propósito.* El proyecto busca eliminar la brecha entre los datos disponibles de movilidad urbana en Bogotá y las herramientas de simulación de
tráfico. La transformación de datos de la Encuesta de Movilidad en insumos para SUMO requiere actualmente procesos manuales que toman horas de trabajo
especializado. El módulo desarrollado automatiza este proceso de extremo a extremo.

*Alcance -- Incluye*
- Análisis y comparación de fuentes de datos de movilidad disponibles (Encuesta de Movilidad 2023, aforos vehiculares HMD, OpenStreetMap).
- Desarrollo del pipeline ETL que transforma los datos en archivos de entrada de SUMO: red vial (`.net.xml`), zonas TAZ (`.taz.xml`), viajes y
  rutas (`.trips.xml`, `.rou.xml`) y tipos de vehículo.
- Validación del pipeline en la localidad de Usaquén, verificando coherencia con aforos reales mediante el estadístico GEH.
- Análisis de al menos dos escenarios hipotéticos de movilidad (infraestructura vial y control de tráfico).
- Desarrollo de un módulo web que permita visualizar de forma interactiva los resultados producidos por SUMO (métricas de congestión, tiempos de
  viaje) y parametrizar nuevas simulaciones desde una interfaz gráfica, sin necesidad de editar archivos manualmente.
- _(v2.0)_ Demanda parametrizable con presets de transferencia modal, conteos por modo, semilla, estilos de conducción y cierres viales, con
  simulaciones precalculadas de los presets.
- _(v2.0)_ Módulo de intersecciones y semaforización: catálogo de semáforos, programas, Webster, recorte de zonas, comparación de programas y
  priorización de cruces sin semáforo.
- _(v2.0)_ Simulador 3D comparativo de semáforo propuesto, con seguimiento en tercera persona de cualquier actor, HUD de velocidad, riesgo (TTC,
  DRAC, PET) y decisiones, minimapa 2D y selección de vías.

*Alcance -- Excluye*
- Integración en tiempo real con APIs de tráfico comerciales.
- Despliegue en sistemas de producción institucionales.
- Calibración del modelo para localidades distintas a Usaquén en esta versión.
- Programas semafóricos reales de la Secretaría Distrital de Movilidad (se usan los generados por netconvert a partir de OpenStreetMap).

*Objetivo General.* Diseñar e implementar un módulo de procesamiento de datos que automatice la transformación de fuentes de datos de movilidad
disponibles para Bogotá en archivos de entrada válidos para el simulador SUMO, eliminando la intervención manual en la generación de redes viales,
matrices origen-destino y archivos de rutas.

*Objetivos Específicos*
- Analizar y comparar las fuentes de datos de movilidad disponibles para Bogotá para determinar cuáles permiten construir matrices O/D
  suficientemente representativas @ortuzar.
- Desarrollar el módulo de procesamiento que automatice la transformación en archivos válidos para SUMO, con manejo de datos faltantes y resultados
  reproducibles.
- Validar el módulo generando insumos de simulación para la localidad de Usaquén, verificando coherencia con aforos reales y ejecutando el escenario
  en SUMO.
- Desarrollar un módulo web que permita visualizar de forma interactiva los resultados generados por SUMO y parametrizar nuevas simulaciones desde
  una interfaz gráfica, reduciendo la barrera técnica de acceso al sistema para usuarios del área de movilidad. En la versión 2.0 este objetivo
  incluye el análisis de intersecciones y el simulador 3D comparativo.

== Supuestos y Restricciones

*Supuestos*
- La Encuesta de Movilidad de Bogotá 2023 y la base de datos de aforos vehiculares HMD son accesibles y de calidad suficiente para construir matrices
  O/D representativas.
- La red vial de Bogotá en OpenStreetMap tiene suficiente cobertura y atributos para generar una red simulable en SUMO para la localidad de Usaquén.
- Los cuatro integrantes del equipo están disponibles durante las 16 semanas del proyecto con una dedicación aproximada de 10 horas semanales por
  persona.
- El equipo de cómputo disponible tiene al menos 8 GB de RAM y un procesador de 4 núcleos para ejecutar SUMO a escala de localidad.
- SUMO en su versión estable (1.27, instalada con el paquete `eclipse-sumo`) soporta todos los modos de transporte a modelar.
- _(v2.0)_ El navegador del usuario soporta WebGL 2 para el render 3D del simulador.

*Restricciones*
- El proyecto está planeado para completarse en 10 semanas de trabajo efectivo. Aunque el semestre cuenta con 16 semanas para la entrega final, la
  calendarización se diseñó dejando semanas adicionales de contingencia y ajuste, con el fin de disponer de tiempo suficiente para corregir errores,
  realizar pruebas, atender imprevistos y efectuar mejoras antes de la entrega final. La extensión v2.0 (Sprints 6 a 8) usa ese margen (ver 9.3).
- Todas las herramientas deben ser de código abierto o de uso académico gratuito (sin licencias comerciales).
- El alcance geográfico está limitado a la localidad de Usaquén para la validación.
- El código fuente debe seguir la guía de estilo PEP 8 y estar versionado en GitHub.
- El módulo web debe ser accesible desde navegadores modernos sin instalación adicional; no se contempla despliegue en producción institucional en
  esta versión.

== Entregables

#figure(
  table(
    columns: (2fr, 2fr, 3fr, auto, 2fr),
    table.header([Entregable], [Estándar], [Descripción], [Audiencia], [Semana]),
    [SPMP corregido], [IEEE 1058-1998], [Plan de administración del proyecto (fuente Typst + PDF)], [Equipo / Director / Jurados], [3],
    [SRS corregido], [IEEE 830-1998], [Especificación de requisitos del software @ieee830 (fuente Typst + PDF)], [Equipo / Director / Jurados], [4],
    [SDD], [IEEE 1016-2009], [Documento de diseño del sistema @ieee1016], [Equipo / Director], [6],
    [Plan de Pruebas], [ISO/IEC/IEEE 29119], [Plan detallado de pruebas @iso29119], [Equipo / Director], [7],
    [Código Fuente], [PEP 8 / API TraCI], [`simulation-service` (pipeline ETL, API, simulador 3D) y visor web `kepler`], [Repositorio GitHub], [9],
    [Módulo de semaforización y simulador 3D _(v2.0)_], [PEP 8 / API TraCI], [Intersecciones, priorización y comparación 3D sin / con semáforo
    propuesto], [Director / Jurados], [11–14],
    [Informe Final], [IEEE 1063-2001], [Documento final con resultados], [Jurados / Universidad], [10–16],
  ),
  caption: [Entregables del proyecto.],
) <tabEntregables>

== Resumen de Calendarización y Presupuesto

*Hitos del Proyecto*

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([Hito], [Descripción], [Semana]),
    [H1], [Entrega SPMP y SRS corregidos. Arranque formal del proyecto], [1–2],
    [H2], [Pipeline ETL funcional. Matrices O/D y red vial generadas], [2–6],
    [H3], [Módulo web funcional: visualización de resultados y parametrización de simulaciones], [6–8],
    [H4], [Entrega SDD y Plan de Pruebas], [8–10],
    [H5], [Escenario base validado en SUMO (Sprint 1)], [10–12],
    [H6], [Escenarios hipotéticos analizados (Sprint 3–4)], [12–14],
    [H7], [Entrega informe final], [14–16],
    [H8 _(v2.0)_], [Módulo de intersecciones y simulador 3D comparativo operativos (Sprints 6 y 7)], [11–14],
  ),
  caption: [Hitos del proyecto.],
) <tabHitos>

*Resumen de Presupuesto*

#figure(
  table(
    columns: (auto, 1fr, auto, auto),
    table.header([Ítem], [Descripción], [Cantidad], [Costo equivalente]),
    [Horas-persona totales], [Línea base: 4 personas × 10 semanas × 14 h/semana + 40 h del Sprint 5. Extensión v2.0: Sprints 6 a 8 (120 h)],
    [720 h], [—],
    [Herramientas de software], [SUMO, Python, FastAPI, React, kepler.gl, three.js, GitHub, GitHub Actions, Typst (todos gratuitos)], [—], [\$0 COP],
    [Datos de entrada], [Encuesta Movilidad 2023, aforos, OSM, Microsoft Building Footprints (todos públicos)], [—], [\$0 COP],
    [Infraestructura de cómputo], [Equipos personales del equipo + Google Colab], [—], [\$0 COP],
    [Total monetario del proyecto], [], [], [\$0 COP],
  ),
  caption: [Resumen de presupuesto (horas-persona).],
) <tabPresupuesto>

El proyecto no maneja presupuesto monetario. Todas las herramientas son de código abierto y los datos de entrada son de acceso público. El costo total
equivalente se expresa en horas-persona: la línea base es de 600 h-p (560 h-p de 4 integrantes × 10 semanas × 14 h/semana, más 40 h del módulo web).
La extensión v2.0 suma 120 h-p estimadas para los Sprints 6 a 8, para un total de 720 h-p.

== Evolución del Plan

El presente documento es un artefacto vivo que se actualizará en cada entrega formal del proyecto. Los cambios al plan se gestionan a través del
proceso de control de configuración descrito en la sección 12.3. Cualquier modificación sustancial al alcance, calendario o recursos debe ser aprobada
por el director y registrada en el historial de cambios (sección 1). La versión 2.0 (ampliación del alcance con semaforización y simulador 3D) se
somete a esa aprobación.
