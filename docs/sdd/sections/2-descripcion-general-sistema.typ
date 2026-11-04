= Descripción general del sistema

== Contexto del proyecto

Los estudios de movilidad urbana en Bogotá parten de la Encuesta de Movilidad @encuesta, un conjunto tabular de viajes. Convertir esa tabla en una simulación microscópica de tráfico exige muchos pasos manuales y frágiles (zonificar, ponderar, rutear, simular, exportar) y deja a quien toma decisiones sin una forma sencilla de preguntar «¿qué pasaría si...?».

El sistema resuelve tres necesidades del proyecto de grado:

+ *Automatizar* la cadena de datos que va de la encuesta a una simulación SUMO reproducible de Usaquén.
+ *Explorar escenarios hipotéticos* (más vehículos, más peatones, día sin carro, cierres viales, otro estilo de conducción) sin tocar archivos XML, y verlos animados en un mapa.
+ *Apoyar decisiones de semaforización*: identificar qué cruces sin semáforo serían candidatos y mostrar, en una vista 3D comparativa, cómo se comportaría el tráfico con y sin un semáforo propuesto. Esta idea se inspira en el proyecto _Semáforos de Barranquilla_ (análisis en `docs/propuesta-semaforizacion-3d.md`).

Los requisitos correspondientes están en el SRS agrupados así: F1 ingestión de datos, F2 matrices OD, F3 red y TAZ, F4 archivos de simulación, F5 variación paramétrica, F6 módulo web, F7 validación y reportes, F8 intersecciones y semaforización, F9 simulador 3D comparativo.

== Objetivos del diseño

Las prioridades que guían las decisiones, en orden, son:

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    [Prioridad], [Objetivo], [Cómo se refleja en el diseño],
    [1], [*Reproducibilidad científica*: la misma entrada debe producir la misma salida.], [Semilla explícita, ordenamiento determinista de viajes, reparto por mayor resto (sin azar), `gzip` con `mtime=0`, huella SHA-256 de los insumos en cada precalculada, versiones de dependencias fijadas.],
    [2], [*Mantenibilidad y trazabilidad*: un estudiante nuevo debe poder entender y extender cada etapa.], [Un módulo por etapa con el mismo patrón `*Config` / `*Result` / `*Stats`; `configuration.py` como única fuente de rutas; nombres en español; 103 pruebas automáticas.],
    [3], [*Respuesta fluida con un simulador lento*: una corrida completa tarda 10--15 min.], [Trabajos asíncronos con avance y cancelación, presets precalculados servidos comprimidos, cachés de análisis de red, FCD reducido, descarga con barra de progreso.],
    [4], [*Verosimilitud sin sobreprometer*: mostrar resultados creíbles y declarar lo que no se modela.], [Notas explícitas en la API (programas de OSM, volumen sin `vehroute`), escena 3D con relleno marcado como ilustrativo (`relleno: true`).],
    [5], [*Operación local y simple*: sin infraestructura de base de datos ni nube.], [Estado en el sistema de archivos, un solo proceso de API, proxy de Vite para el visor.],
  ),
  caption: [Objetivos de diseño priorizados.],
)

*Restricciones que condicionan el diseño:*

- SUMO es un ejecutable externo (paquete `eclipse-sumo`), de modo que el servicio solo orquesta procesos y archivos; no integra SUMO como biblioteca.
- La API aplica un límite de una corrida pesada a la vez (CPU y memoria de SUMO) y de dos comparaciones 3D simultáneas.
- Los datos crudos de la encuesta no están versionados (viven en Google Drive); lo que entra al repositorio es el TSV de viajes internos ya filtrado.
- El navegador debe poder manejar el volumen de la encuesta completa (~24.600 viajes, ~64 MB de GeoJSON sin comprimir).
