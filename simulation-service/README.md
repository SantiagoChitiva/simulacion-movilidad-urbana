# Simulation Service

Puente entre SUMO y los datos de entrada y salida: un ETL que genera viajes, calcula rutas y simula con SUMO, y una API que expone el resultado como GeoJSON.

## Requisitos

- Python 3.11
- SUMO se instala automáticamente (`eclipse-sumo`)

## Instalación

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Ejecutar

**ETL** (TSV → trips → duarouter → SUMO → GeoJSON). La simulación tarda varios minutos.

```bash
python -m etl.etl
```

**API**

```bash
uvicorn api.api:app --reload
```

- `GET http://localhost:8000/simulation-output` devuelve los primeros 3 registros del GeoJSON (`?limit=10` para más).
- Documentación interactiva en `http://localhost:8000/docs`.

**Tests**

```bash
pytest -v
```

## Estructura

```
src/
├── api/                 # API FastAPI
└── etl/
    ├── etl.py           # orquestador del pipeline
    └── sumo/
        ├── scenarios/default/   # insumos: .net.xml, .taz.xml, .tsv, .sumocfg
        ├── enums/               # TransportMode, SurveyMode, VehicleType
        ├── vtypes.py            # configuración de vehículos
        ├── trips.py             # TSV → trips.xml
        ├── duarouter.py         # trips.xml → rou.xml
        ├── simulation.py        # ejecuta SUMO
        └── fcd.py               # FCD → GeoJSON
test/                    # tests con pytest
```

## `pyproject.toml`

| Sección | Para qué sirve |
|---|---|
| `[build-system]` | Herramienta que construye el paquete (setuptools) |
| `[project]` | Nombre, versión y versión de Python requerida |
| `dependencies` | Librerías necesarias siempre, con versión fija (`==`) |
| `[project.optional-dependencies]` | Grupos opcionales: `test` (pytest) y `dev` (incluye `test`) |
| `[tool.setuptools.packages.find]` | Indica que el código está en `src/` |
| `[tool.pytest.ini_options]` | Config de pytest: busca tests en `test/` y agrega `src/` al path |

Instalación según el entorno:

| Entorno | Comando |
|---|---|
| Producción | `pip install .` |
| Testing | `pip install -e ".[test]"` |
| Desarrollo | `pip install -e ".[dev]"` |
