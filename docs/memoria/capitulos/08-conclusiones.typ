= Conclusiones

== Análisis de impacto del proyecto

*A corto plazo*, el impacto recae en quien analiza movilidad. Un escenario que antes exigía días de preparación ahora se lanza desde el navegador y
se ve en unos minutos, o en segundos si es uno de los cuatro presets. La pestaña de priorización reduce la pregunta de dónde estudiar un semáforo de
miles de nodos a una lista de 62 cruces con su porqué. El simulador 3D convierte esa pregunta en algo que un directivo puede ver y discutir.

*A mediano plazo*, el sistema puede servir como banco de pruebas antes de intervenir la calle. Sirve para probar un cierre por obras, un día sin
carro, un cambio de programa en un semáforo o un semáforo nuevo. El aporte no es reemplazar el estudio de tránsito, que sigue necesitando aforos
en sitio. Lo que el sistema hace es decidir mejor qué estudiar y llegar a ese estudio con una hipótesis ya explorada.

*A largo plazo*, el valor está en que todo es abierto y reproducible: el código, la red, la demanda, las semillas y las simulaciones precalculadas
con la huella de sus insumos. Otra localidad de Bogotá, otra ciudad colombiana con una encuesta similar o un grupo de investigación puede partir de
aquí sin licencias.

*En ingeniería de sistemas*, el proyecto mostró que el trabajo difícil de un sistema de simulación está alrededor del simulador. La mayor parte del
esfuerzo se fue en el tratamiento de datos incompletos, en la orquestación de procesos largos con avance y cancelación y en la sincronización de dos
simulaciones en vivo. También se fue en una interfaz que no exija saber lo que el equipo sabe. Varias de las fallas más costosas se encontraron solo
al probar con datos y usuarios reales: el orden de los viajes, la comparación que no aplicaba el programa y el actor que entraba en un solo lado.

*En lo social, económico y ambiental*, la congestión le cuesta a Bogotá tiempo, productividad y aire. Una herramienta que ayude a escoger mejor
dónde invertir en semáforos o cómo manejar un cierre contribuye, aunque sea de forma indirecta, a reducir esos costos. La priorización usa
siniestros con heridos y muertos y la cercanía a colegios y centros de salud, de modo que pone primero los cruces donde una mala decisión cuesta
vidas. El cálculo de CO₂ por viaje en el simulador 3D es un primer paso para que la discusión incluya emisiones.

== Conclusiones y trabajos futuros

=== Cumplimiento de los objetivos

La @tabObjetivos revisa cada objetivo específico.

#figure(
  table(
    columns: (30%, 15%, 1fr),
    table.header([*Objetivo*], [*Estado*], [*Por qué*]),
    [1. Analizar las fuentes de datos], [Cumplido], [Se evaluaron la encuesta, los aforos HMD y OpenStreetMap, con un informe de brechas. La encuesta resultó la única
    fuente utilizable para la demanda; los aforos no tenían coordenadas.],
    [2. Automatizar la transformación a SUMO], [Cumplido], [El pipeline genera viajes, rutas, configuración y trayectorias sin pasos manuales, con 177
    pruebas automatizadas.],
    [3. Validar en una localidad], [Parcial], [Usaquén se simuló completa, los presets reproducen la encuesta y cada corrida se compara con 33
    puntos de aforo (GEH). El criterio (85 % de los puntos con GEH < 5) no se cumple: con la encuesta completa la demanda ya es del orden de los
    aforos, pero la red no alcanza a moverla. Falta calibrar su capacidad.],
    [4. Módulo web de visualización y parametrización], [Cumplido], [El visor anima los viajes, lanza y cancela corridas, carga precalculadas y aplica
    cierres y estilos sin tocar archivos.],
    [5. Intersecciones y simulador 3D], [Cumplido], [Ficha, programas, Webster y comparación con SUMO real; priorización con evidencia; comparación
    3D con entrada simultánea y resumen del viaje.],
  ),
  caption: [Cumplimiento de los objetivos específicos.],
) <tabObjetivos>

El objetivo general se cumplió en lo que respecta a la automatización y a la interfaz: el trabajo manual entre la encuesta y SUMO desapareció y un
usuario sin formación técnica puede generar y comparar escenarios. La validación contra la calle ya existe como medición: cada corrida reporta su GEH frente a los
aforos, con un grupo de estaciones de control que no se usa para calibrar. Lo que todavía no existe es un modelo que la pase. Hasta que la red esté
calibrada, los resultados sirven para comparar alternativas entre sí, no para afirmar cifras absolutas.

=== Qué le falta para un uso institucional

Para que una secretaría de movilidad adopte una herramienta como insumo técnico de sus decisiones, se le suelen exigir cinco cosas:
- un modelo calibrado;
- indicadores de gobierno (demora, colas, emisiones, seguridad);
- escenarios comparables;
- integración con sus fuentes de datos;
- reportes para públicos técnicos y directivos.

La @tabInstitucional contrasta esos pilares con el estado del sistema.

#figure(
  table(
    columns: (24%, 1fr, 1fr),
    table.header([*Pilar*], [*Qué tiene el sistema*], [*Qué falta*]),
    [Calibración y validación], [Demanda desde la encuesta oficial, completa con los viajes que entran y salen; GEH contra 33 puntos de aforo con
    estaciones de control @dmrb; tráfico de paso calibrado; asignación iterativa opcional (equilibrio de Wardrop @wardrop); semilla fija y
    precalculadas con huella de insumos.], [Una red calibrada que pase el criterio GEH: capacidad de avenidas y cruces, planes reales de los
    semáforos.],
    [Indicadores], [Tiempo perdido, colas, detenciones y espera peatonal por programa; TTC, DRAC, PET, frenadas y casi choques en 3D; CO₂ por
    viaje; rangos con varias semillas en la comparación de programas.], [Emisiones y tiempos de viaje agregados para toda la red.],
    [Escenarios], [Presets de cambio modal, cierres viales, estilos de conducción, programas de semáforo y semáforo nuevo.], [Infraestructura nueva
    (carriles exclusivos, ciclorrutas) y restricciones como pico y placa.],
    [Datos e integración], [OpenStreetMap, GeoJSON, siniestros y semáforos reales de la SDM (ubicación y fases), aforos HMD, GTFS del SITP,
    huellas de edificios.], [Tiempos de los planes semafóricos (la SDM no los publica); TransMilenio troncal.],
    [Comunicación], [Visor en español, tema claro, tarjeta de cruce, resumen en palabras, reporte CSV/PDF y advertencias sobre lo que el modelo no mide.], [Análisis
    costo-beneficio en horas-hombre y combustible.],
  ),
  caption: [Estado del sistema frente a los requisitos de una herramienta institucional.],
) <tabInstitucional>

=== Trabajo futuro

En orden de prioridad, según lo que más acercaría el sistema a una decisión real:

En el sprint 10 se construyeron la validación GEH, la encuesta completa, los buses del SITP, los rangos con varias semillas, el reporte CSV/PDF y el
programa editable del semáforo propuesto, que esta lista tenía como pendientes. Lo que queda:

+ *Calibrar la capacidad de la red.* Es lo que separa al sistema de pasar el GEH. Con la demanda completa, la mayoría de los vehículos no alcanza a
  entrar y la red se llena. Hay que revisar carriles y conexiones en las avenidas, cargar los planes reales de los semáforos y sumar los aforos de
  calzadas paralelas (la Autopista Norte con sus laterales es un solo punto de aforo y varios edges en la red).
+ *Planes reales de los semáforos.* La Secretaría de Movilidad publica dónde están sus 1.643 intersecciones semaforizadas y cuántas fases tiene cada
  una, pero no los tiempos (los enlaces a los planes están vacíos). Hay que pedirlos con un derecho de petición; el sistema ya puede cargarlos como
  programa propio de cada semáforo.
+ *TransMilenio troncal.* Los buses del SITP ya circulan; faltan las troncales, que van por carriles exclusivos.
+ *Prueba con usuarios reales.* Sentar a una persona de la Secretaría de Movilidad frente al visor y medir si encuentra, entiende y usa los
  resultados sin ayuda.
