= Apéndices y referencias

== Pila tecnológica (Tech Stack)

#figure(
  table(
    columns: (1fr, 2fr, 3fr),
    [Capa], [Tecnología], [Uso],
    [Simulación], [SUMO 1.27.1 (`eclipse-sumo`), `traci` 1.27.1, `sumolib`], [Simulación microscópica, ruteo (`duarouter`), construcción de red (`netconvert`), control en vivo (TraCI).],
    [Servicio], [Python ≥ 3.11, FastAPI 0.136.3 (`fastapi[standard]`), Pydantic, `uvicorn`], [API REST/WebSocket, validación.],
    [Geodesia], [`pyproj` 3.8.0], [Coordenadas UTM de la red a lon/lat.],
    [Pruebas], [`pytest` 9.1.1; `matplotlib` (validación)], [Pruebas y gráficos de validación (`validation/`).],
    [Visor], [React 18.3, Vite 6, `vite-plugin-node-polyfills`], [Aplicación de una página con proxy `/api`.],
    [Mapa], [kepler.gl 3.1 (`@kepler.gl/*`), Redux 4, `react-palm`, `styled-components` 6.1.8, `react-intl`], [Mapa y capa Trip.],
    [3D], [three.js 0.169, maplibre-gl 4.7.1], [Escena comparativa y minimapa OSM.],
    [Calidad], [ESLint 10 (visor), pylint (CI, sin bloqueo)], [Análisis estático.],
    [Documentación], [Typst (`.typ` → PDF), IEEE 1016, 830, 1058], [SRS, SPMP, SDD, VFP.],
    [Datos], [Encuesta de Movilidad 2023 (TSV), OSM, siniestros SDM, edificios OSM y Microsoft], [Insumos versionados en `data/processed/` y `scenarios/`.],
    [Control de versiones y CI], [Git, GitHub Actions], [Flujo `tests.yml` (ver @sec-limitaciones).],
  ),
  caption: [Pila tecnológica.],
)

*Puesta en marcha.*

```bash
# Servicio (desde simulation-service/)
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
python -m etl.etl                 # pipeline completo (varios minutos)
python -m etl.precalculadas       # regenerar presets precalculados
uvicorn api.api:app --reload      # API en :8000, documentación en /docs
pytest -v

# Visor (desde kepler/)
npm install && npm run dev        # requiere la API en :8000 y VITE_MAPBOX_TOKEN en .env
```

El SDD se compila con `typst compile docs/sdd/sdd.typ` (desde la raíz del repositorio puede usarse `--root docs/sdd`). Los diagramas usan el paquete `fletcher` de Typst, que se descarga en la primera compilación.

== Registros de decisiones (ADRs) <sec-adrs>

#figure(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    [ID], [Decisión], [Motivo], [Alternativas y consecuencias],
    [ADR-01], [Servicio único FastAPI con módulos internos (monolito modular).], [Una sola máquina; SUMO domina el costo; simplifica cancelación, rutas de archivos y pruebas.], [Microservicios: más infraestructura sin beneficio. Costo: no escala en usuarios.],
    [ADR-02], [Un trabajador (`ThreadPoolExecutor(1)`) y cola en memoria para las corridas.], [SUMO consume CPU y memoria; dos corridas a la vez se estorban y no terminan antes.], [Celery/Redis: sobredimensionado. Costo: una sola instancia; las corridas activas se pierden si el servicio se reinicia (se marcan `error`).],
    [ADR-03], [Archivos en lugar de base de datos.], [Los resultados de SUMO ya son archivos; un escenario; cero operación.], [PostgreSQL/PostGIS: útil con muchos escenarios y usuarios. Costo: consultas ad hoc, sin transacciones.],
    [ADR-04], [Orquestar SUMO como subprocesos y TraCI.], [Binarios probados; TraCI permite medir avance, cancelar y controlar actores.], [Bindings C++/libsumo: más rápido, más acoplado. Costo: latencia de socket en el 3D.],
    [ADR-05], [Ordenar los viajes por salida antes de rutear.], [SUMO descarta lo que llegue desordenado (~23.000 de ~24.600 viajes se perdían).], [Ordenar en `duarouter`: no lo hace. Costo: pasar todos los viajes por memoria (aceptable).],
    [ADR-06], [Presets como reglas de transferencia modal con P(modo | duración) y mayor resto.], [Conservan el total y los orígenes/destinos y son deterministas; con `encuesta` reproducen la encuesta.], [Reponderar al azar: menos reproducible. Costo: el reparto depende de la duración reportada.],
    [ADR-07], [Precalcular y versionar los cuatro presets.], [Una corrida tarda ~12 min; el visor debe mostrar algo útil al abrir.], [Generar al arrancar: lento. Costo: ~12 MB por preset en Git y la huella de insumos para detectarlos obsoletos.],
    [ADR-08], [Usar kepler.gl (capa Trip) para la visualización principal.], [Animación de trayectorias lista, filtros y línea de tiempo.], [deck.gl a mano: más control, más trabajo. Costo: dependencia pesada, Redux y orden alfabético de colores.],
    [ADR-09], [Simulador 3D comparativo con dos SUMO en lockstep, en lugar de una vista en vivo de un semáforo existente.], [La decisión de interés es «¿qué cambia si pongo un semáforo aquí?», que exige misma demanda y semilla en ambos lados.], [Comparar métricas finales de dos corridas: menos intuitivo. Costo: 2 procesos SUMO por comparación y un límite de 2 comparaciones.],
    [ADR-10], [Priorización con reglas y evidencia calibrada contra los semáforos existentes, sin modelo de lenguaje.], [Explicable, reproducible y sin dependencia externa; se adapta el enfoque de Barranquilla.], [Puntaje opaco con LLM. Costo: umbrales fijados a mano y a la red de Usaquén.],
    [ADR-11], [Transporte público como `<person><walk>`.], [No hay GTFS ni paradas; evita inventar un servicio.], [Buses con `gtfs2pt` y `personTrip modes="public"`: pendiente. Costo: subestima la carga sobre las vías.],
    [ADR-12], [Escena 3D con relleno ilustrativo marcado (`relleno: true`).], [OSM y Microsoft no cubren todas las manzanas; una escena vacía no se entiende.], [Solo edificios reales: escena vacía. Costo: parte de la escena no es real.],
    [ADR-13], [Documentación en Typst y código en español.], [Uniformidad con el SRS/SPMP y con el equipo y jurado.], [LaTeX/Word: menos mantenible. Costo: ecosistema más pequeño.],
  ),
  caption: [Registro de decisiones de arquitectura.],
)

== Trazabilidad con el SRS

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    [Grupo del SRS], [Cubre], [Componentes del diseño],
    [F1, F2, F3], [Ingestión de datos, matrices OD, red y TAZ.], [`trips.py`, `enums/`; notebooks `F1.x`/`F2.x` (fuera del servicio); red y TAZ copiadas a `scenarios/`.],
    [F4], [Archivos de simulación.], [`etl.py`, `duarouter.py`, `simulation.py`, `configuration.py`.],
    [F5], [Variación paramétrica.], [`demanda.py`, `estilos.py`, `cierres.py`, `jobs.py`, `precalculadas.py`.],
    [F6], [Módulo web.], [`kepler/` completo; `GET/POST /simulaciones`, `/precalculadas`.],
    [F7], [Validación y reportes.], [`fcd.py`, `kepler.py`, estadísticas en `resumen_corrida`; `validation/` (histograma de salidas).],
    [F8], [Intersecciones y semaforización.], [`intersecciones.py`, `priorizacion.py`, `evidencia.py`, `programas_tls.py`, `subred.py`, `FichaInterseccion`, `PanelSemaforizacion`.],
    [F9], [Simulador 3D comparativo.], [`comparacion3d.py`, `semaforo_nuevo.py`, `demanda_zona.py`, `escena3d.py`, `telemetria.py`, `simulador3d/`.],
  ),
  caption: [Trazabilidad entre grupos de requisitos y componentes de diseño.],
)

== Limitaciones conocidas del diseño <sec-limitaciones>

- *Transporte público* simulado como caminata; sin buses, paradas ni GTFS.
- *Programas de semáforo* generados por `netconvert` desde OSM; no son los reales de la Secretaría de Movilidad.
- *Webster simplificado:* reparto circular de accesos a fases y valor de demostración cuando no hay volumen.
- *Demanda sintética en la comparación 3D:* los viajes de la encuesta son escasos en una zona de 350 m, así que se completan con tráfico de fondo por modo; los resultados comparan escenarios entre sí, no predicen un volumen real.
- *Una instancia:* estado local, cola de un trabajador, sin autenticación.
- *CI incompleto:* las pruebas de `simulation-service` y el visor no se ejecutan en CI.
- *Sin reanudación por fase:* una corrida interrumpida debe repetirse completa.
- *Rutas heredadas:* el README raíz menciona `src/pipeline/` y `src/simulation/`, que no existen; todo el código del pipeline está en `simulation-service/src/`.
