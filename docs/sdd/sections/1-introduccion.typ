= Introducción

== Propósito y contenido del documento

Este Documento de Descripción del Diseño del Software (SDD) describe cómo está construido el sistema _Generación de Escenarios de Movilidad Urbana -- Usaquén_. Sigue la estructura de la norma IEEE Std 1016-2009 @ieee1016 y presenta la arquitectura según la norma ISO/IEC/IEEE 42010 @iso42010 y el modelo de vistas «4+1» de Kruchten @kruchten. Complementa a la Especificación de Requisitos (SRS, @ieee830), que dice _qué_ debe hacer el sistema, y al Plan de Gestión (SPMP, @ieee1058), que dice _cómo_ se gestiona el proyecto.

El documento se organiza en dos partes:

- *Arquitectura* (@sec-arquitectura): la estructura y el comportamiento del sistema con un alto nivel de abstracción, en tres vistas: lógica (componentes, librerías e interfaces), física (hardware y dónde se instala cada componente) y de procesos (lo que hace el usuario con el sistema).
- *Diseño detallado* (@sec-diseno-detallado): el diseño de bajo nivel, es decir, las clases de cada componente, la secuencia de las acciones complejas, la forma en que se guardan los datos y las pantallas de la interfaz gráfica.

El documento describe el sistema tal como está implementado en la rama de desarrollo (SRS versión 2.1). Donde algo está diseñado pero no construido, o construido con una limitación conocida (por ejemplo, el transporte público), se indica de forma explícita.

== Audiencia

Este documento está dirigido a:

- *El equipo de desarrollo*, como referencia para mantener y extender el código.
- *El director del proyecto* y *los jurados evaluadores*, como evidencia de las decisiones de diseño y de su justificación.
- *Futuros mantenedores o investigadores* que quieran reutilizar el pipeline de simulación con otra localidad de Bogotá.

== Alcance del sistema

El sistema se compone de dos módulos que se documentan en conjunto:

#figure(
  table(
    columns: (auto, 1fr, auto),
    table.header([Módulo], [Descripción], [Directorio]),
    [`simulation-service`], [Paquete Python instalable (≥ 3.11). Contiene el pipeline ETL que convierte la Encuesta de Movilidad en entradas de SUMO, ejecuta la simulación y exporta los resultados, y una API REST/WebSocket (FastAPI) que lo expone.], [`simulation-service/`],
    [`kepler`], [Aplicación web de una sola página (Vite + React) que embebe kepler.gl para animar los viajes simulados y ofrece paneles de demanda, intersecciones, semaforización y el simulador 3D comparativo.], [`kepler/`],
  ),
  caption: [Módulos del sistema cubiertos por este documento.],
)

El resto del repositorio (`notebooks/`, `data/`) es un espacio de exploración de datos (CRISP-DM, fases 1 y 2) cuyos productos entran al sistema como insumos versionados; no forma parte del diseño de software y solo se menciona como fuente de datos.

*Dentro del alcance.* El sistema:

- Transforma los viajes de la Encuesta de Movilidad de Bogotá 2023 @encuesta (filtrados a los internos de Usaquén, ventana 07:00--10:00) en demanda multimodal para SUMO @sumo, replicando cada viaje según su factor de expansión.
- Permite parametrizar la demanda (presets de cambio modal, conteos por modo, semilla, estilo de conducción y cierres viales) y ejecutar la simulación como trabajos en segundo plano con avance y cancelación.
- Sirve resultados precalculados de los presets para consulta inmediata y visualiza los viajes animados sobre un mapa.
- Cataloga las intersecciones semaforizadas de la red, muestra sus accesos, volúmenes y programas, y calcula un programa de Webster @webster.
- Prioriza los cruces sin semáforo que justificarían uno nuevo y los compara en 3D, en tiempo real, con y sin un semáforo propuesto, con telemetría de riesgo @ssm.

*Fuera del alcance.*

- *Transporte público real*: no hay buses, paradas ni GTFS; esos viajes se simulan como caminata (`<person><walk>`).
- *Calibración y validación estadística* del modelo frente a aforos reales.
- *Programas semafóricos reales*: los programas son los que genera `netconvert` desde OpenStreetMap, no los de la Secretaría Distrital de Movilidad.
- *Autenticación, multiusuario y despliegue en la nube*: es una herramienta local de investigación.
- Otras localidades distintas de Usaquén (el diseño es parametrizable por escenario, pero solo existe el escenario `default`).

== Glosario y acrónimos <sec-glosario>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Término], [Significado]),
    [SUMO], [_Simulation of Urban MObility_: simulador microscópico de tráfico de código abierto. Se usa a través de `sumo`, `duarouter`, `netconvert`, `cutRoutes.py` y `randomTrips.py`.],
    [TraCI], [_Traffic Control Interface_: protocolo para controlar una instancia de SUMO en ejecución (avanzar pasos, consultar y modificar actores).],
    [FCD], [_Floating Car Data_: salida de SUMO con la posición de cada actor en cada periodo. Es la fuente de las exportaciones.],
    [TAZ], [_Traffic Analysis Zone_: zona de análisis de tráfico; origen y destino de los viajes (derivadas de las UPZ de Usaquén).],
    [UPZ / ZAT], [Unidad de Planeamiento Zonal / Zona de Análisis de Transporte de Bogotá.],
    [OD], [Matriz origen--destino.],
    [`fexp`], [Factor de expansión de la encuesta: cuántas personas representa un viaje observado.],
    [Preset], [Regla de cambio modal predefinida (`encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`) que redistribuye los viajes entre modos.],
    [Corrida (_run_)], [Ejecución del pipeline con una demanda concreta; sus archivos viven en `runs/<id>/`.],
    [Precalculada], [Corrida de un preset con conteos por defecto, guardada en el repositorio para servirla sin simular.],
    [`vType`], [Tipo de vehículo de SUMO; aquí hay uno por modo de viaje (`TransportMode`).],
    [`tlLogic`], [Programa de un semáforo en SUMO (fases, duraciones, estados por movimiento).],
    [Cruce], [Agrupación de nodos de SUMO próximos que forman una intersección real (p. ej. las dos calzadas de una avenida).],
    [Webster], [Método de F. V. Webster para el ciclo óptimo de un semáforo.],
    [SSM], [_Surrogate Safety Measures_: indicadores de riesgo que no esperan a un choque (TTC, DRAC, PET).],
    [TTC / DRAC / PET], [Tiempo a la colisión / tasa de desaceleración para evitarla / tiempo posterior a la invasión del cruce.],
    [Ego], [Actor (vehículo o peatón) seguido por la cámara en el simulador 3D; se inyecta con el mismo id y ruta en los dos lados.],
    [Lado], [Una de las dos instancias de SUMO del simulador 3D: A = sin semáforo, B = con semáforo propuesto.],
    [Kepler / kepler.gl], [Biblioteca de visualización geoespacial; su capa _Trip_ anima rutas con marca de tiempo.],
    [ETL], [_Extract, Transform, Load_: aquí, encuesta → trips → rutas → simulación → GeoJSON.],
    [SDM], [Secretaría Distrital de Movilidad de Bogotá (fuente de la encuesta y de los siniestros).],
    [OSM], [OpenStreetMap: fuente de la red vial, nombres de calles, POI y huellas de edificios.],
  ),
  caption: [Glosario de términos y acrónimos.],
)
