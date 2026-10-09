# Simulation Service

Puente entre SUMO y los datos de entrada y salida: un ETL que genera viajes, calcula rutas y simula con SUMO, y una API que expone el resultado como GeoJSON.

## Requisitos

- Python 3.11
- SUMO se instala automáticamente (`eclipse-sumo`), junto con `traci`/`sumolib` (control de la simulación) y `pyproj` (coordenadas). En Windows, ese paquete trae rutas de más de 260 caracteres: si `pip install` falla, habilita las rutas largas o instala SUMO 1.27 aparte y usa `pip install --no-deps -e .` más `fastapi[standard]==0.136.3 traci==1.27.1 pyproj==3.8.0 pytest`.

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
- `GET /simulaciones` y `GET /simulaciones/{id}`: estado de cada corrida y resumen al terminar (viajes generados, vehículos insertados, teleports).
  - Estados posibles: `en_cola`, `generando_demanda`, `ruteando`, `simulando`, `exportando`, `cancelando`, `terminado`, `error` o `cancelada`.
  - `avance` (0–1) es el avance global; `avance_etapa`, el de la etapa en curso.
- `POST /simulaciones/{id}/cancelar`: cancela una corrida en cola o en curso, termina SUMO/duarouter y borra sus archivos salvo `estado.json`. Responde `409` si ya terminó.
- `GET /simulaciones/{id}/kepler-trips`: trips de una corrida terminada (`409` si aún no termina).

Las corridas se ejecutan **de a una**, en segundo plano, y cada una tarda 10–15 min. Se escriben en `runs/<id>/` (ignorado por git), junto con `estado.json`, así que el historial se conserva si se reinicia la API. Del FCD solo se guarda la conversión para kepler, porque el XML pesa ~1,4 GB.

**Cómo se mide el avance.** Cuando la salida va a un pipe, SUMO y duarouter la acumulan en un buffer, así que su consola no sirve para medir el avance en vivo. En su lugar:
- **duarouter:** el último `depart` escrito en el `.rou.xml` dice hasta qué hora de la ventana va, porque escribe las rutas ordenadas.
- **SUMO:** se controla con **TraCI** en saltos de 60 s simulados. La simulación y sus salidas son las mismas, y cancelar es inmediato.
- **Exportación a kepler:** se mide por los bytes leídos del FCD.

**Simulaciones precalculadas.** Los cuatro presets, con sus conteos por defecto, se simulan una vez en local y sus resultados se versionan en `precalculadas/<preset>/`. Así el visor los carga en segundos, sin correr SUMO.

```bash
python -m etl.precalculadas                 # los cuatro, uno tras otro (~50 min)
python -m etl.precalculadas dia_sin_carro   # solo uno
```

- Cada preset deja tres archivos:
  - `trips.geojson.gz`: el GeoJSON de kepler comprimido, ~17 MB en lugar de ~91 MB.
  - `volumenes.json`: los volúmenes por edge para la ficha de intersecciones.
  - `meta.json`: conteos, semilla, resumen y la huella de los insumos.
- El `.gz` nunca se descomprime en disco: la API lo envía con `Content-Encoding: gzip` y el navegador lo descomprime al recibirlo. Por eso `.gitignore` ignora cualquier `precalculadas/**/*.geojson`.
- La huella es un sha256 de la encuesta, la red, la TAZ y la plantilla `.sumocfg`. Si cambia alguno, `GET /precalculadas` marca el preset como `desactualizada` y hay que regenerarlo.
- `GET /precalculadas`: lista los presets disponibles con su `meta.json`.
- `GET /precalculadas/{preset}/kepler-trips`: los trips comprimidos.
- `GET /intersecciones?precalculada={preset}`: los volúmenes de una precalculada.

Intersecciones semaforizadas (fase A del módulo de semáforos, ver `../docs/propuesta-semaforizacion-3d.md`):

- `GET /intersecciones?run_id=`: los 220 semáforos de la red como GeoJSON de puntos, con su nombre, número de accesos, ciclo y volumen simulado. El volumen sale de la corrida indicada, o de la corrida por defecto.
- `GET /intersecciones/{id}?run_id=`: la ficha. Trae los accesos (calle, clase de vía, carriles, velocidad, giros y vehículos en la ventana y por hora) y el programa del semáforo (fases con la luz de cada acceso).
- El catálogo se arma desde `usaquen_3d.net.xml` y queda en `cache/semaforos.json`, ignorado por git. Los volúmenes salen del `vehroute.xml` de cada corrida.
- La red no trae nombres de calles: se completan con `scenarios/default/nombres_vias.json`, que se genera desde el OSM con `python -m etl.sumo.intersecciones ../../data/processed/usaquen.osm.xml`.

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
    ├── precalculadas.py # simula los presets una vez y guarda lo que usa el visor
    └── sumo/
        ├── scenarios/default/   # insumos: .net.xml, .taz.xml, .tsv, plantilla .sumocfg
        ├── configuration.py     # rutas por escenario/corrida y constantes
        ├── enums/               # TransportMode, SurveyMode, VehicleType
        ├── vtypes.py            # configuración de vehículos
        ├── demanda.py           # presets y conteos por modo
        ├── proceso.py           # correr duarouter/sumo con avance y cancelación
        ├── intersecciones.py    # catálogo de semáforos y volúmenes por acceso
        ├── trips.py             # TSV → trips.xml
        ├── duarouter.py         # trips.xml → rou.xml
        ├── simulation.py        # ejecuta SUMO
        ├── fcd.py               # FCD → GeoJSON de puntos
        └── kepler.py            # FCD → GeoJSON de trips (kepler.gl)
test/                    # tests con pytest
precalculadas/           # resultados versionados de los presets (python -m etl.precalculadas)
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
