# Simulation Service

Puente entre SUMO y los datos de entrada y salida: un ETL que genera viajes, calcula rutas y simula con SUMO, y una API que expone el resultado como GeoJSON.

## Requisitos

- Python 3.11
- SUMO se instala automáticamente (`eclipse-sumo`). En Windows, ese paquete trae rutas de más de 260 caracteres: si `pip install` falla, habilita las rutas largas o instala SUMO 1.27 aparte y usa `pip install --no-deps -e .` más `fastapi[standard]` y `pytest`.

## Instalación

```bash
python3.11 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Ejecutar

**ETL** (TSV → trips → duarouter → SUMO → GeoJSON). La simulación tarda varios minutos. Corre sobre la red 3D (`usaquen_3d.net.xml`), así que el FCD trae la altura `z`. Genera dos GeoJSON en `scenarios/default/output/`:

- `usaquen_am.fcd.geojson`: un punto por entidad y timestep.
- `usaquen_am.kepler.geojson`: un `LineString` `[lon, lat, z, unix_t]` por vehículo o persona, para la capa Trip de kepler.gl (`../kepler`).

```bash
python -m etl.etl
```

**API**

```bash
uvicorn api.api:app --reload
```

Corrida por defecto (la de `python -m etl.etl`):

- `GET /simulation-output` devuelve los primeros 3 registros del GeoJSON (`?limit=10` para más).
- `GET /kepler-trips` devuelve el GeoJSON de trips completo; lo consume el visor de `../kepler`.

Demanda parametrizable (la usa el panel del visor):

- `GET /demanda/modos`: actores viales que se pueden parametrizar, con etiqueta, grupo y notas.
- `GET /demanda/presets`: los presets `encuesta`, `mas_vehiculos`, `mas_peatones` y `dia_sin_carro`, con sus conteos por modo.
- `POST /simulaciones` con cuerpo `{"preset": "dia_sin_carro", "conteos": {"bici": 2400, "peaton": 14500}, "semilla": 42}`: encola una corrida y responde `202` con su `id`. Los conteos son enteros ≥ 0 y el total va de 1 a 100.000.
- `GET /simulaciones` y `GET /simulaciones/{id}`: estado de cada corrida (`en_cola`, `generando_demanda`, `ruteando`, `simulando`, `exportando`, `terminado` o `error`) y resumen al terminar (viajes generados, vehículos insertados, teleports).
- `GET /simulaciones/{id}/kepler-trips`: trips de una corrida terminada (`409` si aún no termina).

Las corridas se ejecutan **de a una**, en segundo plano, y cada una tarda 10–15 min. Se escriben en `runs/<id>/` (ignorado por git), junto con `estado.json`, así que el historial se conserva si se reinicia la API. Del FCD solo se guarda la conversión para kepler, porque el XML pesa ~1,4 GB.

Documentación interactiva en `http://localhost:8000/docs`.

**Tests**

```bash
pytest -v
```

## Estructura

```
src/
├── api/
│   ├── api.py           # API FastAPI
│   └── jobs.py          # cola de corridas (una a la vez) y su estado en runs/
└── etl/
    ├── etl.py           # orquestador del pipeline
    └── sumo/
        ├── scenarios/default/   # insumos: .net.xml, .taz.xml, .tsv, plantilla .sumocfg
        ├── configuration.py     # rutas por escenario/corrida y constantes
        ├── enums/               # TransportMode, SurveyMode, VehicleType
        ├── vtypes.py            # configuración de vehículos
        ├── demanda.py           # presets y conteos por modo
        ├── trips.py             # TSV → trips.xml
        ├── duarouter.py         # trips.xml → rou.xml
        ├── simulation.py        # ejecuta SUMO
        ├── fcd.py               # FCD → GeoJSON de puntos
        └── kepler.py            # FCD → GeoJSON de trips (kepler.gl)
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
