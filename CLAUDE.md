# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Undergraduate thesis (Pontificia Universidad Javeriana): microscopic urban-mobility simulation of the Usaquén locality (Bogotá) in **SUMO**. Real data (Encuesta de Movilidad 2023, HMD vehicle counts) goes through an ETL that produces SUMO inputs, runs the simulation and exposes the results to a web module. Code, comments, identifiers and docs are in **Spanish**. Keep that convention (e.g. `filas_invalidas`, `viajes_generados`).

## Repository layout (two independent Python environments)

- **Repo root**: data-exploration workspace. `requirements.txt` (pandas, geopandas, osmnx, folium, jupyter, pytest-cov, pylint). `notebooks/` holds CRISP-DM phase notebooks named by phase (`F1.x`, `F2.x`). `data/processed/` holds SUMO/OSM artifacts produced by those notebooks (netconvert plain files, `usaquen.net.xml`, TAZ, OD, routes). `data/raw/` is not versioned (it lives on Google Drive). `docs/` holds SPMP/SRS written in **Typst** (`*.typ` → `*.pdf`).
- **`simulation-service/`**: the actual application, an installable package (`pyproject.toml`, Python ≥3.11, `src/` layout). SUMO comes from the `eclipse-sumo` pip package, so `sumo`/`duarouter` end up on PATH inside the venv.
- **`kepler/`**: Vite + React + kepler.gl viewer that animates the simulation trips. It fetches `/api/kepler-trips`, which Vite proxies to the API at `localhost:8000` (`vite.config.js`). It needs `VITE_MAPBOX_TOKEN` in `kepler/.env` (template: `.env.example`).

The root README mentions `src/pipeline/` and `src/simulation/`. Those directories do not exist. All pipeline code is in `simulation-service/src/`.

## Commands

simulation-service (run from `simulation-service/`):
```bash
python3.11 -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
python -m etl.etl                     # full pipeline: TSV → trips → duarouter → SUMO → GeoJSON (takes several minutes)
uvicorn api.api:app --reload          # API at :8000, docs at /docs
pytest -v                             # tests in test/, src/ already on pythonpath
pytest test/etl/sumo/test_fcd.py::<test_name>   # single test
```

kepler viewer (run from `kepler/`; `.npmrc` sets `legacy-peer-deps`):
```bash
npm install
npm run dev        # needs the API running on :8000
npm run build
```

Repo root:
```bash
pip install -r requirements.txt
pytest tests/ --cov=src --cov-report=term-missing
```

CI (`.github/workflows/tests.yml`, push/PR to `main`/`develop`) installs only the root `requirements.txt` and runs only the root `tests/`, which is a placeholder. It also runs `pylint src/ --exit-zero`. **`simulation-service/test/` does not run in CI.**

## simulation-service architecture

`src/etl/etl.py` orchestrates the pipeline in four steps, all keyed by a scenario name (default `"default"`):
1. `run_etl`: `trips.generate_trips` (survey TSV → `*.trips.xml`), then `duarouter.run_duarouter` (→ `*.rou.xml`, with `--ignore-errors --repair`). **Trips must be written sorted by `depart`.** The TSV isn't sorted, duarouter keeps the input order, and SUMO *drops* (doesn't reorder) any entity whose depart is lower than the max already loaded ("Route file should be sorted by departure time, ignoring ..."). Without the sort, ~23k of ~24.6k trips are lost.
2. `simulate`: `simulation.run_simulation` runs headless `sumo -c <sumocfg>` with `cwd` set to the sumocfg's directory. The scenario uses the **3D network** (`usaquen_3d.net.xml`, a copy of `data/processed/usaquen_3d_v2.net.xml`), so SUMO writes `z` into the FCD. With the full demand, output size matters. That's why the sumocfg sets `device.fcd.period=2` and has no `emission-output` (~2 GB), and `export_kepler_trips` uses `step=8`.
3. `export_geojson`: `fcd.convert_fcd_to_geojson` streams the FCD XML with `iterparse` into a GeoJSON of Point features, downsampled by `sample_every` seconds.
4. `export_kepler_trips`: `kepler.convert_fcd_to_kepler_trips` groups the FCD by entity into one `LineString` per vehicle/person with `[lon, lat, z, unix_t]` coordinates, for kepler.gl's Trip layer. `unix_t` = `base_date` (2000-01-01 UTC) + simulation seconds. `z` is relative to the FCD minimum. Points are reduced by time step/heading change, and entities that barely move are dropped.

Conventions across `etl/sumo/` modules:
- Each step follows the same pattern: a frozen `*Config` dataclass (with `to_args()` for CLI tools), a `*Result` dataclass, and a mutable `*Stats` dataclass passed in and incremented while processing. Subprocess wrappers find the binary with `shutil.which` and raise a module-specific `*Error(RuntimeError)`.
- `configuration.py` is the single source of truth for paths and constants. `ScenarioPaths.from_name()` maps a scenario to `scenarios/<name>/` and its `output/` subfolder. The simulation window (`HORA_INI`=7h, `HORA_FIN`=10h) and `MAX_COPIAS` are defined there too. Output filenames in `ScenarioPaths` must stay in sync with the scenario's `.sumocfg` (`output-prefix="usaquen_am."` + `output/fcd.xml` → `output/usaquen_am.fcd.xml`).
- Mode mapping: `SurveyMode` (raw survey labels such as `"A PIE <15 MIN"`) → `TransportMode` (also the SUMO vType id) → `VTYPES` in `vtypes.py` (`VehicleType` = SUMO vClass). Each survey row is replicated `round(fexp_vj)` times, capped at `MAX_COPIAS`. Pedestrians **and public transport** are emitted as `<person><walk>` because there are no `<ride>`/stops yet. `bus_pt` is a vType for a future PT service, not a travel mode.
- `network.py` is a stub. The network is built in the notebooks/`data/processed/` and copied into `scenarios/default/`.
- The API (`src/api/api.py`, FastAPI) only reads files produced by the pipeline: `/simulation-output?limit=` returns the first N point features, `/kepler-trips` streams the full trips GeoJSON, and there's `/health`. It returns 404 if the pipeline hasn't run yet.
- Persons' kepler mode is derived from the id prefix (`peaton_N`, `transporte_publico_N`), so `kepler.mode_of` depends on the id format in `trips.py`. `kepler/src/App.jsx` maps modes to colors (`MODE_COLORS`) and builds the color range in alphabetical order of the modes present, because that's how kepler's ordinal scale assigns them. Add a color there when you add a `TransportMode`.

Generated files are git-ignored in simulation-service (`*rou*.xml`, `*trips.xml`, `output/`). Do not commit them.

## Methodology / docs

Hybrid lifecycle: CRISP-DM for the data phases (1–2), Scrum for the simulation phase (3). Standards: IEEE 1058 (SPMP), IEEE 830 (SRS), ISO/IEC 12207, PEP 8. `cronograma.md` holds the schedule.
