# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Undergraduate thesis (Pontificia Universidad Javeriana): microscopic urban-mobility simulation of the Usaquén locality (Bogotá) in **SUMO**. Real data (Encuesta de Movilidad 2023, HMD vehicle counts) goes through an ETL that produces SUMO inputs, runs the simulation and exposes the results to a web module. Code, comments, identifiers and docs are in **Spanish**. Keep that convention (e.g. `filas_invalidas`, `viajes_generados`).

## Repository layout (two independent Python environments)

- **Repo root**: data-exploration workspace. `requirements.txt` (pandas, geopandas, osmnx, folium, jupyter, pytest-cov, pylint). `notebooks/` holds CRISP-DM phase notebooks named by phase (`F1.x`, `F2.x`). `data/processed/` holds SUMO/OSM artifacts produced by those notebooks (netconvert plain files, `usaquen.net.xml`, TAZ, OD, routes). `data/raw/` is not versioned (it lives on Google Drive). `docs/` holds SPMP/SRS written in **Typst** (`*.typ` → `*.pdf`).
- **`simulation-service/`**: the actual application, an installable package (`pyproject.toml`, Python ≥3.11, `src/` layout). SUMO comes from the `eclipse-sumo` pip package, so `sumo`/`duarouter` end up on PATH inside the venv.
- **`kepler/`**: Vite + React + kepler.gl viewer that animates the simulation trips. `/api/*` is proxied to the API at `localhost:8000` (`vite.config.js`). It needs `VITE_MAPBOX_TOKEN` in `kepler/.env` (template: `.env.example`).
  - `App.jsx` (`Visor`) owns the map: it downloads trips with progress and an `AbortController` (`api.descargarJson`), replaces the kepler dataset, and toggles the traffic-light point layer. It opens the intersection card by reading `visState.clicked` (`clicked.object?.index ?? clicked.index` → row in `filasSemaforos`).
  - `hooks.js`: `useCorridas` handles the history, the running job, 2 s polling, and cancel. `useTamanoVentana` keeps kepler's width/height in sync with the window; the body has `overflow: hidden`.
  - Components:
    - `PanelDemanda`: presets, per-mode counts, scale, and seed.
    - `TarjetaActividad`: bottom-right card with progress bars and cancel.
    - `LeyendaModos`: top-center legend plus the "Semáforos" toggle.
    - `FichaInterseccion`: accesses, volumes, and phases.
  - `modos.js` holds the mode colors.
  - The right column (`.columna-derecha`) leaves room for kepler's map controls (right) and timeline (bottom).
- `docs/propuesta-semaforizacion-3d.md`: analysis of the Barranquilla traffic-signal project and the proposed architecture for the intersection/traffic-light module and 3D view (deck.gl + TraCI over WebSocket). Not implemented yet.

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
- **Parametrized demand** (`demanda.py`): a `DemandaConfig(preset, conteos)` goes into `TripGenerationConfig.demanda`. Presets (`encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`) are modal-shift rules (`ReglaTransferencia`) that redistribute trips using P(mode | trip-duration bin), computed from the full-day survey weighted by `fexp`.
  - Presets preserve the total, and a shifted trip keeps its OD and departure time.
  - User counts are allocated across the survey trips of that mode with largest remainder, so allocation is deterministic. If the preset has no trips for a mode, it falls back to the base survey pool.
  - With `encuesta` + its default counts, the output reproduces the plain survey expansion exactly. Tests assert this.
- **Runs:** `ScenarioPaths.from_name(name, run_id)` puts generated files in `simulation-service/runs/<run_id>/` (git-ignored). Inputs stay in the scenario. `simulate()` writes a per-run sumocfg from the template (`escribir_sumocfg_corrida`, absolute net/taz/routes, outputs relative). Without `run_id` everything stays in `scenarios/default/` as before.
- **Precalculated presets** (`src/etl/precalculadas.py`, `python -m etl.precalculadas [preset ...]`): each preset with its default counts is simulated once locally and **committed** to `simulation-service/precalculadas/<preset>/`:
  - `trips.geojson.gz` (gzip `mtime=0`, so it is reproducible), `volumenes.json`, `meta.json` (with a content sha256 `insumos` of TSV/net/TAZ/sumocfg, CRLF-normalized).
  - The API serves the `.gz` as-is with `Content-Encoding: gzip` + `X-Tamano-Original` (the browser decompresses it; the viewer measures progress with that header). Uncompressed `*.geojson` there is git-ignored.
  - The viewer treats them as finished runs (`id: precalculada-<preset>`, `precalculada: true`). When the panel matches one exactly, it shows "Cargar simulación" instead of running. On startup it loads the `encuesta` one if it exists.
- The API (`src/api/api.py`, FastAPI):
  - Default-run files: `/simulation-output?limit=`, `/kepler-trips`, and `/health`. These return 404 if the pipeline hasn't run yet.
  - Parametrized runs: `/demanda/modos`, `/demanda/presets`, `POST/GET /simulaciones`, and `POST /simulaciones/{id}/cancelar`.
  - Intersections: `GET /intersecciones[/{id}]?run_id=`.
  - `api/jobs.py` (`GestorCorridas`) runs one pipeline at a time in a `ThreadPoolExecutor(1)`. It persists `runs/<id>/estado.json`, throttled to one write every 2 s.
    - Progress: `avance` maps each stage to a band of the global progress (`FRANJAS_ETAPA`).
    - Cancel: a `threading.Event` goes down to the subprocesses. `Cancelado` makes the worker delete everything in the run dir except `estado.json`.
    - The FCD is deleted after the kepler export.
    - Tests inject a fake pipeline through `app.dependency_overrides[obtener_gestor]`.
- **Progress/cancel plumbing:** `run_pipeline(..., on_progreso(etapa, avance|None), cancelar=Event)`.
  - SUMO and duarouter block-buffer stdout when it's piped, so their step log arrives only at exit. Don't parse it.
  - duarouter progress comes from polling the last `depart` written to the `.rou.xml` (`proceso.ultimo_depart`).
  - SUMO is driven by **TraCI** (`simulation._run_traci`, 60 s jumps, `traci==1.27.1` from pip); outputs are identical to a plain run.
  - The kepler export reports bytes read.
- **Intersections** (`etl/sumo/intersecciones.py`): one `Semaforo` per `tlLogic`.
  - Accesses come from `<connection tl=… linkIndex=…>`; lon/lat via pyproj from the net's `<location>`.
  - The net has no street names: `scenarios/default/nombres_vias.json` (OSM way id → name, from `python -m etl.sumo.intersecciones <osm>`) fills them by edge id (`-123#4` → way `123`).
  - Volumes per access are counted from a run's `vehroute.xml` (last route of a `routeDistribution`).
  - Caches: `simulation-service/cache/semaforos.json` and `output/volumenes.json`, both invalidated by mtime/size.
- Public transport (`transporte_publico`) is still `<person><walk>`: there are no buses, stops, or GTFS. The README documents the limitation and the fix (gtfs2pt + `personTrip modes="public"`).
- Persons' kepler mode is derived from the id prefix (`peaton_N`, `transporte_publico_N`), so `kepler.mode_of` depends on the id format in `trips.py`. `kepler/src/App.jsx` maps modes to colors (`MODE_COLORS`) and builds the color range in alphabetical order of the modes present, because that's how kepler's ordinal scale assigns them. Add a color there when you add a `TransportMode`.

Generated files are git-ignored in simulation-service (`*rou*.xml`, `*trips.xml`, `output/`). Do not commit them.

## Methodology / docs

Hybrid lifecycle: CRISP-DM for the data phases (1–2), Scrum for the simulation phase (3). Standards: IEEE 1058 (SPMP), IEEE 830 (SRS), ISO/IEC 12207, PEP 8. `cronograma.md` holds the schedule.
