= Anexos

== Anexo A – Estructura del Repositorio

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Carpeta / Archivo], [Contenido]),
    [`simulation-service/src/etl/`], [Pipeline ETL: orquestador `etl.py`, simulaciones precalculadas y módulos de cada paso en `sumo/` (viajes, demanda,
    duarouter, simulación, exportación, intersecciones, programas, recorte, priorización, semáforo propuesto, escena 3D, telemetría)],
    [`simulation-service/src/api/`], [API FastAPI (`api.py`), gestor de corridas (`jobs.py`) y simulador 3D comparativo (`comparacion3d.py`)],
    [`simulation-service/test/`], [Pruebas pytest del servicio (99 en v2.0)],
    [`simulation-service/precalculadas/`], [Simulaciones precalculadas de los presets (versionadas)],
    [`simulation-service/runs/`], [Corridas, zonas y comparaciones generadas desde la API (no versionadas)],
    [`kepler/`], [Visor web React + kepler.gl + three.js (`src/components/simulador3d/`)],
    [`tests/`], [Pruebas de la raíz (las que corre el CI)],
    [`data/raw/`], [Datos de entrada originales (enlace a Google Drive; no versionados en Git)],
    [`data/processed/`], [Red OSM y 3D, TAZ, edificios y demás artefactos de los notebooks],
    [`docs/`], [Documentos formales en Typst y PDF (`spmp/`, `srs/`, `vfp/`) y notas de diseño],
    [`notebooks/`], [Jupyter Notebooks de exploración y preparación de datos (Fases 1 y 2)],
    [`requirements.txt`], [Dependencias Python del espacio de exploración],
    [`.github/workflows/`], [Configuración de GitHub Actions (CI/CD)],
    [`README.md`], [Guía de instalación y uso del sistema],
  ),
  caption: [Estructura del repositorio.],
) <tabRepositorio>

== Anexo B – Registro de Riesgos Actualizable

El registro de riesgos se mantiene actualizado en la sección 12.2 de este documento y como archivo en `docs/riesgos/` del repositorio. Se revisa al
inicio de cada sprint.

== Anexo C – Compilación de los documentos

Los documentos formales se compilan con Typst desde la carpeta de cada uno:

#block(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
  `typst compile docs/spmp/spmp.typ` #h(1fr) (o `python -c "import typst; typst.compile('spmp.typ')"` con `pip install typst`)
]
