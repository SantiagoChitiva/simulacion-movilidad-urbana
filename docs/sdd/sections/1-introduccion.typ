= Introducción

== Propósito del documento

Este Documento de Diseño de Software (SDD) describe cómo está construido el sistema _Generación de Escenarios de Movilidad Urbana -- Usaquén_: la arquitectura, los datos que maneja, el diseño detallado de cada componente y las interfaces que expone. Sigue la estructura de la norma IEEE Std 1016 @ieee1016 y complementa a la Especificación de Requisitos (SRS, @ieee830), que dice _qué_ debe hacer el sistema, y al Plan de Gestión (SPMP, @ieee1058), que dice _cómo_ se gestiona el proyecto. Aquí se documenta cómo está resuelto técnicamente.

El documento describe el sistema tal como está implementado en la rama de desarrollo (SRS versión 2.1). Donde algo está diseñado pero no construido, o construido con una limitación conocida, se indica de forma explícita (por ejemplo, el transporte público, @sec-limitaciones).

Está dirigido a:

- *El equipo de desarrollo*, como referencia para mantener y extender el código.
- *El director del proyecto* y *los jurados evaluadores*, como evidencia de las decisiones de diseño y de la justificación de cada una.
- *Futuros mantenedores o investigadores* que quieran reutilizar el pipeline de simulación con otra localidad de Bogotá.

El sistema se compone de dos módulos que se documentan en conjunto:

#figure(
  table(
    columns: (auto, 1fr, auto),
    [Módulo], [Descripción], [Directorio],
    [`simulation-service`], [Paquete Python instalable (≥ 3.11). Contiene el pipeline ETL que convierte la Encuesta de Movilidad en entradas de SUMO, ejecuta la simulación y exporta los resultados, y una API REST/WebSocket (FastAPI) que lo expone.], [`simulation-service/`],
    [`kepler`], [Aplicación web de una sola página (Vite + React) que embebe kepler.gl para animar los viajes simulados y ofrece paneles de demanda, intersecciones, semaforización y el simulador 3D comparativo.], [`kepler/`],
  ),
  caption: [Módulos del sistema cubiertos por este documento.],
)

El resto del repositorio (`notebooks/`, `data/`) es un espacio de exploración de datos (CRISP-DM, fases 1 y 2) cuyos productos entran al sistema como insumos versionados; no forma parte del diseño de software y solo se menciona como fuente de datos.

== Alcance del sistema

*Dentro del alcance.* El sistema:

- Transforma los viajes de la Encuesta de Movilidad de Bogotá 2023 (filtrados a los internos de Usaquén, ventana 07:00--10:00) en demanda multimodal para SUMO, replicando cada viaje según su factor de expansión.
- Permite parametrizar la demanda (presets de cambio modal, conteos por modo, semilla, estilo de conducción y cierres viales) y ejecutar la simulación como trabajos en segundo plano con avance y cancelación.
- Sirve resultados precalculados de los presets para consulta inmediata.
- Visualiza los viajes animados sobre un mapa y los resume por modo.
- Cataloga las intersecciones semaforizadas de la red, muestra sus accesos, volúmenes simulados y programas, y calcula un programa de Webster.
- Prioriza los cruces sin semáforo que justificarían uno nuevo (reglas viales más evidencia de siniestralidad, volumen y entorno).
- Compara en 3D, y en tiempo real, un cruce tal como está contra el mismo cruce con un semáforo propuesto, con telemetría de riesgo del actor seguido y un modo de conducción manual.

*Fuera del alcance.*

- *Transporte público real*: no hay buses, paradas ni GTFS. Los viajes en transporte público se simulan como caminata (`<person><walk>`).
- *Calibración y validación estadística del modelo* frente a aforos reales (HMD). El sistema produce las simulaciones, no certifica la exactitud del modelo.
- *Programas semafóricos reales*: los programas son los generados por `netconvert` desde OpenStreetMap, no los de la Secretaría Distrital de Movilidad.
- *Autenticación, multiusuario y despliegue en la nube*: es una herramienta local de investigación (@sec-seguridad).
- Otras localidades distintas de Usaquén (el diseño es parametrizable por escenario, pero solo existe el escenario `default`).

== Glosario y acrónimos <sec-glosario>

#figure(
  table(
    columns: (auto, 1fr),
    [Término], [Significado],
    [SUMO], [_Simulation of Urban MObility_: simulador microscópico de tráfico de código abierto @sumo. Se usa a través de `sumo`, `duarouter`, `netconvert`, `cutRoutes.py` y `randomTrips.py`.],
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
    [Webster], [Método de F. V. Webster para el ciclo óptimo de un semáforo @webster.],
    [SSM], [_Surrogate Safety Measures_: indicadores de riesgo que no esperan a un choque (TTC, DRAC, PET) @ssm.],
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
