= Conclusiones

== Análisis de impacto del proyecto

*A corto plazo*, el impacto recae en quien analiza movilidad. Un escenario que antes exigía días de preparación ahora se lanza desde el navegador y
se ve en unos minutos, o en segundos si es uno de los cuatro presets. La pestaña de priorización reduce la pregunta de dónde estudiar un semáforo de
miles de nodos a una lista de 61 cruces con su porqué. El simulador 3D convierte esa pregunta en algo que un directivo puede ver y discutir.

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
    [2. Automatizar la transformación a SUMO], [Cumplido], [El pipeline genera viajes, rutas, configuración y trayectorias sin pasos manuales, con 139
    pruebas automatizadas.],
    [3. Validar en una localidad], [Parcial], [Usaquén se simuló completa y los presets reproducen la encuesta. Falta la comparación con aforos (GEH)
    que la metodología fijaba como criterio de terminado.],
    [4. Módulo web de visualización y parametrización], [Cumplido], [El visor anima los viajes, lanza y cancela corridas, carga precalculadas y aplica
    cierres y estilos sin tocar archivos.],
    [5. Intersecciones y simulador 3D], [Cumplido], [Ficha, programas, Webster y comparación con SUMO real; priorización con evidencia; comparación
    3D con entrada simultánea y resumen del viaje.],
  ),
  caption: [Cumplimiento de los objetivos específicos.],
) <tabObjetivos>

El objetivo general se cumplió en lo que respecta a la automatización y a la interfaz: el trabajo manual entre la encuesta y SUMO desapareció y un
usuario sin formación técnica puede generar y comparar escenarios. Queda abierta la validación del modelo contra la calle. Hasta que exista, los
resultados sirven para comparar alternativas entre sí, no para afirmar cifras absolutas.

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
    [Calibración y validación], [Demanda desde la encuesta oficial; semilla fija y precalculadas con huella de insumos (reproducibilidad).], [GEH
    contra aforos georreferenciados @dmrb; asignación iterativa de rutas (equilibrio de Wardrop @wardrop); viajes de paso por la localidad.],
    [Indicadores], [Tiempo perdido, colas, detenciones y espera peatonal por programa; TTC, DRAC, PET, frenadas y casi choques en 3D; CO₂ por
    viaje.], [Emisiones y tiempos de viaje agregados para toda la red; varias semillas para reportar rangos en lugar de un solo valor.],
    [Escenarios], [Presets de cambio modal, cierres viales, estilos de conducción, programas de semáforo y semáforo nuevo.], [Infraestructura nueva
    (carriles exclusivos, ciclorrutas), restricciones como pico y placa y ventana de la tarde.],
    [Datos e integración], [OpenStreetMap, GeoJSON, siniestros de la SDM, huellas de edificios.], [GTFS del SITP y TransMilenio para el transporte
    público real; programas reales de los semáforos de la ciudad.],
    [Comunicación], [Visor en español, tema claro, tarjeta de cruce, resumen en palabras y advertencias sobre lo que el modelo no mide.], [Reporte
    exportable (PDF o CSV) de cada comparación; análisis costo-beneficio en horas-hombre y combustible.],
  ),
  caption: [Estado del sistema frente a los requisitos de una herramienta institucional.],
) <tabInstitucional>

=== Trabajo futuro

En orden de prioridad, según lo que más acercaría el sistema a una decisión real:

+ *Validación GEH.* Terminar la geocodificación de los aforos HMD, ubicar los que caen en Usaquén y comparar sus volúmenes con los simulados. Es la
  pieza que convierte el sistema de herramienta de exploración en modelo de apoyo técnico.
+ *Demanda completa.* Agregar los viajes que entran, salen o atraviesan Usaquén, revisar el tope de copias por respuesta y calibrar contra los
  aforos.
+ *Transporte público real.* Importar el GTFS de TransMilenio y el SITP con `gtfs2pt` y convertir los viajes en transporte público en viajes con
  buses, paradas y esperas.
+ *Rangos en lugar de valores únicos.* Repetir cada comparación con varias semillas y reportar el intervalo ("entre 70 y 160 frenadas por hora"),
  como hace Semáforos de Barranquilla.
+ *Reporte exportable.* Descargar en PDF o CSV el resumen de cada comparación, con el programa del semáforo propuesto y sus supuestos.
+ *Programa editable del semáforo propuesto.* Ajustar el ciclo y los repartos del semáforo nuevo desde el visor y reiniciar la comparación.
+ *Prueba con usuarios reales.* Sentar a una persona de la Secretaría de Movilidad frente al visor y medir si encuentra, entiende y usa los
  resultados sin ayuda.
