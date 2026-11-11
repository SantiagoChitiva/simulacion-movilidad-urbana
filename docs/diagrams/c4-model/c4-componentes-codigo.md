# Modelo C4: niveles 3 (Componentes) y 4 (Código)

Complementa `tesis.drawio`, `tesis-c4-context.svg` y `tesis-c4-container.svg`. Los diagramas están en Mermaid, que GitHub, GitLab, VS Code y Obsidian renderizan. Los nombres de módulos, clases y funciones salen del código en `simulation-service/src/` y `kepler/src/`.

Contenedores de partida (nivel 2):

| Contenedor | Tecnología | Carpeta |
|---|---|---|
| Visor web | React, Vite, kepler.gl, three.js | `kepler/` |
| API de simulación | FastAPI | `simulation-service/src/api/` |
| Pipeline ETL | Python | `simulation-service/src/etl/` |
| SUMO | `sumo`, `duarouter`, TraCI | pip `eclipse-sumo` |
| Almacén de archivos | TSV, XML, GeoJSON | `data/`, `scenarios/`, `runs/`, `precalculadas/`, `cache/` |

> Nota: el C4 estricto no tiene "nivel de capas". Aquí el nivel 3 muestra los componentes de cada contenedor y el nivel 4 muestra las clases, que es el nivel de código.

---

## Nivel 3 — Componentes

### 3.1 Backend: API de simulación y Pipeline ETL

```mermaid
C4Component
    title Diagrama de componentes: simulation-service (API + ETL)

    Container(visor, "Visor web", "React, kepler.gl", "Consume la API REST y el WebSocket")
    ContainerDb(archivos, "Almacén de archivos", "TSV, XML, GeoJSON", "Encuesta, red, corridas, precalculadas y caches")
    Container(sumo, "SUMO", "sumo, duarouter, TraCI", "Motor de simulación microscópica")

    Container_Boundary(api, "API de simulación (FastAPI)") {
        Component(rutas, "Rutas HTTP y WS", "api.py", "Endpoints de demanda, simulaciones, intersecciones y comparación 3D")
        Component(jobs, "GestorCorridas", "jobs.py", "Una corrida a la vez, estado.json, avance y cancelación")
        Component(comp3d, "GestorComparaciones", "comparacion3d.py", "Prepara la zona y corre dos SUMO en paralelo por WebSocket")
    }

    Container_Boundary(etl, "Pipeline ETL") {
        Component(orq, "Orquestador", "etl.py", "run_pipeline, run_recorte y run_escenario_semaforo")
        Component(demanda, "Demanda", "demanda.py, trips.py, vtypes.py, enums", "Presets, reglas de transferencia modal y generación de viajes")
        Component(ruteo, "Ruteo y simulación", "duarouter.py, simulation.py, proceso.py", "Envoltorios de subprocesos, TraCI y progreso")
        Component(export, "Exportadores", "fcd.py, kepler.py", "FCD a GeoJSON y a viajes para kepler.gl")
        Component(inter, "Intersecciones", "intersecciones.py, programas_tls.py", "Catálogo de semáforos, volúmenes, programas y Webster")
        Component(prio, "Priorización", "priorizacion.py, evidencia.py", "Cruces sin semáforo: reglas duras, evidencia y puntaje")
        Component(zona, "Escenario de semaforización", "subred.py, semaforo_nuevo.py, demanda_zona.py", "Recorte de zona, red con semáforo propuesto y demanda de la zona")
        Component(escena, "Escena 3D y telemetría", "escena3d.py, telemetria.py, estilos.py", "Geometría de la escena, TTC, DRAC, PET y acciones")
        Component(precalc, "Precalculadas", "precalculadas.py", "Simula cada preset una vez y lo versiona")
        Component(conf, "Configuración", "configuration.py", "ScenarioPaths, constantes y sumocfg por corrida")
    }

    Rel(visor, rutas, "Consulta y lanza corridas", "JSON/HTTP")
    Rel(visor, comp3d, "Simulación 3D en vivo", "WebSocket")
    Rel(rutas, jobs, "Encola corridas")
    Rel(rutas, comp3d, "Crea y cierra comparaciones")
    Rel(rutas, inter, "Lee semáforos y programas")

    Rel(jobs, orq, "Llama run_pipeline")
    Rel(comp3d, orq, "Llama run_escenario_semaforo")
    Rel(comp3d, escena, "Geometría y riesgo")
    Rel(comp3d, sumo, "Dos instancias en lockstep", "TraCI")

    Rel(orq, demanda, "Genera viajes")
    Rel(orq, ruteo, "Ruta y simula")
    Rel(orq, export, "Exporta resultados")
    Rel(orq, zona, "Arma zona A y B")
    Rel(orq, conf, "Resuelve rutas")
    Rel(precalc, orq, "Corre cada preset")

    Rel(ruteo, sumo, "Ejecuta", "CLI y TraCI")
    Rel(export, archivos, "Lee FCD, escribe GeoJSON", "XML y GeoJSON")
    Rel(inter, archivos, "Lee net.xml y vehroute", "XML")
    Rel(prio, inter, "Usa volúmenes")
```

### 3.2 Visor web (`kepler/`)

```mermaid
C4Component
    title Diagrama de componentes: Visor web (React + kepler.gl)

    Container(apiC, "API de simulación", "FastAPI", "REST y WebSocket")

    Container_Boundary(spa, "Visor web") {
        Component(app, "Visor", "App.jsx", "Dueño del mapa kepler: carga viajes, capa de semáforos y selección")
        Component(hooks, "Hooks", "hooks.js", "useCorridas, polling cada 2 s, cancelación y useTamanoVentana")
        Component(cliente, "Cliente HTTP", "api.js", "fetch y descargarJson con progreso y AbortController")
        Component(paneles, "Paneles de control", "PanelDemanda, PanelSemaforizacion, PanelCierres, TarjetaActividad, LeyendaModos", "Parametrizan, lanzan y muestran el avance")
        Component(ficha, "Ficha de intersección", "FichaInterseccion, TablaComparacion", "Accesos, volúmenes, fases, programas y Webster")
        Component(sim3d, "Simulador 3D", "Simulador3D, escena.js, HUD, Minimapa", "Lazy: pantalla dividida sin y con semáforo")
        Component(modos, "Colores de modos", "modos.js", "Color por modo de transporte")
    }

    Rel(app, hooks, "Usa")
    Rel(app, paneles, "Renderiza")
    Rel(app, ficha, "Abre al hacer clic en un semáforo")
    Rel(app, sim3d, "Abre desde Semaforizar")
    Rel(hooks, cliente, "Llama")
    Rel(ficha, cliente, "Llama")
    Rel(paneles, modos, "Usa")
    Rel(cliente, apiC, "Peticiones", "JSON/HTTP")
    Rel(sim3d, apiC, "Frames de actores", "WebSocket")
```

---

## Nivel 4 — Código

Diagramas de clases de los componentes con más lógica. Las funciones de módulo se dibujan como clases `<<module>>`.

### 4.1 Patrón común de los pasos del pipeline

Cada paso de `etl/sumo/` usa `*Config` (inmutable), `*Stats` (mutable) y `*Result`, como indica el CLAUDE.md.

```mermaid
classDiagram
    direction LR

    class TripGenerationConfig {
        <<frozen dataclass>>
        +demanda: DemandaConfig
    }
    class TripGenerationStats {
        <<dataclass>>
        +filas_invalidas
        +viajes_generados
    }
    class TripRecord {
        <<frozen dataclass>>
    }
    class TripGenerationResult {
        <<frozen dataclass>>
    }
    class trips {
        <<module>>
        +read_trips(config, stats) Iterator~TripRecord~
        +generate_trips(config) TripGenerationResult
    }

    class DuarouterConfig {
        <<frozen dataclass>>
        +to_args() list
    }
    class DuarouterResult {
        <<frozen dataclass>>
    }
    class DuarouterError
    class duarouter {
        <<module>>
        +run_duarouter(config, on_progreso, cancelar) DuarouterResult
    }

    class SimulationConfig {
        <<frozen dataclass>>
    }
    class SimulationResult {
        <<frozen dataclass>>
    }
    class SimulationError
    class simulation {
        <<module>>
        +run_simulation(config, ...) SimulationResult
        -_run_traci(...)
        +leer_estadisticas(path) dict
    }

    class proceso {
        <<module>>
        +ejecutar(...) SalidaProceso
        +ultimo_depart(path) float
        +revisar_cancelacion(cancelar)
        +avance_ventana(t) float
    }
    class Cancelado

    trips ..> TripGenerationConfig
    trips ..> TripGenerationStats
    trips ..> TripRecord
    trips ..> TripGenerationResult
    duarouter ..> DuarouterConfig
    duarouter ..> DuarouterResult
    duarouter ..> proceso : ejecutar
    simulation ..> SimulationConfig
    simulation ..> SimulationResult
    simulation ..> proceso : ejecutar
    DuarouterError --|> RuntimeError
    SimulationError --|> RuntimeError
    Cancelado --|> Exception
    proceso ..> Cancelado : lanza
```

### 4.2 Demanda parametrizada y mapeo de modos

```mermaid
classDiagram
    direction TB

    class SurveyMode {
        <<enum, str>>
        etiquetas crudas de la encuesta
    }
    class TransportMode {
        <<enum, str>>
        id del vType en SUMO
    }
    class VehicleType {
        <<enum, str>>
        vClass de SUMO
    }
    class VTypeConfig {
        <<frozen dataclass>>
    }
    class Preset {
        <<enum, str>>
        encuesta
        mas_vehiculos
        mas_peatones
        dia_sin_carro
    }
    class InfoModo {
        <<frozen dataclass>>
    }
    class InfoPreset {
        <<frozen dataclass>>
        +reglas: ReglaTransferencia[]
    }
    class ReglaTransferencia {
        <<frozen dataclass>>
    }
    class DemandaConfig {
        <<frozen dataclass>>
        +preset: Preset
        +conteos: dict
    }
    class demanda {
        <<module>>
        +rango_duracion(min) int
        +mayor_resto(pesos, total) int[]
        +probabilidades_por_duracion(registros)
        +construir_pools(...)
        +cargar_dia(tsv) TripRecord[]
        +cargar_ventana(tsv) TripRecord[]
        +conteos_preset(...)
        +asignar(...)
    }
    class TripRecord {
        <<frozen dataclass>>
    }

    SurveyMode --> TransportMode : se mapea a
    TransportMode --> VehicleType : vtypes.VTYPES
    VTypeConfig --> VehicleType
    InfoPreset "1" *-- "*" ReglaTransferencia
    DemandaConfig --> Preset
    demanda ..> DemandaConfig
    demanda ..> InfoPreset
    demanda ..> InfoModo
    demanda ..> TripRecord
    TripRecord --> TransportMode
```

### 4.3 Orquestación, corridas y progreso

```mermaid
classDiagram
    direction LR

    class etl {
        <<module>>
        +run_etl(...) EtlResult
        +simulate(...)
        +export_geojson(...)
        +export_kepler_trips(...)
        +run_pipeline(..., on_progreso, cancelar) PipelineResult
        +resumen_corrida(resultado, paths) dict
        +run_recorte(...)
        +run_escenario_semaforo(...)
    }
    class EtlResult {
        <<frozen dataclass>>
    }
    class PipelineResult {
        <<frozen dataclass>>
    }
    class ScenarioPaths {
        <<frozen dataclass>>
        +from_name(name, run_id) ScenarioPaths
    }
    class ArchivosPrecalculada {
        <<frozen dataclass>>
    }

    class Corrida {
        <<dataclass>>
        +estado
        +avance
        +etapa
    }
    class GestorCorridas {
        -ThreadPoolExecutor(1) ejecutor
        -Event cancelar
        +crear(...) Corrida
        +obtener(id) Corrida
        +cancelar(id)
        -_ejecutar(...)
    }
    class jobs {
        <<module>>
        +FRANJAS_ETAPA
        +avance_global(etapa, avance) float
    }
    class api {
        <<FastAPI app>>
        +obtener_gestor()
        +obtener_gestor_comparaciones()
    }

    api ..> GestorCorridas : Depends
    GestorCorridas "1" o-- "*" Corrida
    GestorCorridas ..> etl : run_pipeline
    GestorCorridas ..> jobs : avance_global
    etl ..> EtlResult
    etl ..> PipelineResult
    etl ..> ScenarioPaths
    ScenarioPaths ..> ArchivosPrecalculada
```

> Los métodos de `GestorCorridas` en este diagrama (`crear`, `obtener`, `cancelar`, `_ejecutar`) están inferidos de su responsabilidad. Verifica los nombres reales en `api/jobs.py`, porque no leí esa clase completa.

### 4.4 Intersecciones y priorización

```mermaid
classDiagram
    direction LR

    class Semaforo {
        <<dataclass>>
        +accesos: Acceso[]
        +fases: Fase[]
    }
    class Acceso {
        <<dataclass>>
    }
    class Fase {
        <<dataclass>>
    }
    class intersecciones {
        <<module>>
        +leer_semaforos(net, nombres) Semaforo[]
        +catalogo(net, cache, nombres) Semaforo[]
        +volumenes_por_edge(vehroute) dict
        +volumenes(vehroute, cache) dict
        +con_volumenes(semaforo, vols) Semaforo
        +a_feature(semaforo) dict
    }

    class ProgramaTLS {
        <<dataclass>>
        +fases: FasePrograma[]
    }
    class FasePrograma {
        <<dataclass>>
    }
    class ProgramasTLSError
    class programas_tls {
        <<module>>
        +leer_programas(net, tl_id)
        +leer_programa(net, tl_id, program_id)
        +escribir_programa(prog, destino)
        +validar_programa(prog, movimientos) str[]
        +webster(...)
        +agregar_semaforo(...)
    }

    class PuntajeCruce {
        <<dataclass>>
    }
    class priorizacion {
        <<module>>
        +analizar_red(...) dict
        +analisis_con_cache(net, nombres, cache)
        +puntuar(analisis, volumenes) PuntajeCruce[]
        +a_geojson(cruces, umbrales, notas) dict
        -_agrupar(...)
        -_conflicto_real(...)
        -_tramo_sin_semaforo(...)
        -_suprimir_vecinos(...)
    }
    class evidencia {
        <<module>>
        siniestros, pois, edificios
    }

    Semaforo "1" *-- "*" Acceso
    Semaforo "1" *-- "*" Fase
    intersecciones ..> Semaforo
    ProgramaTLS "1" *-- "*" FasePrograma
    programas_tls ..> ProgramaTLS
    ProgramasTLSError --|> RuntimeError
    priorizacion ..> PuntajeCruce
    priorizacion ..> intersecciones : volumenes
    priorizacion ..> evidencia : datos GeoJSON
```

### 4.5 Comparador 3D (`comparacion3d.py`)

```mermaid
classDiagram
    direction TB

    class Comparacion {
        <<dataclass>>
        +resumen() dict
    }
    class GestorComparaciones {
        +crear(...) Comparacion
        +obtener(cid) Comparacion
        +cerrar(cid)
        +listar() dict[]
        -_limpiar_expiradas()
    }
    class Lado {
        +avanzar(hasta)
        +tiempo() float
        +actores() tuple
        +luces() dict
        +contar_conflictos()
        +ruta(ego) str[]
        +existe(ego) str
        +telemetria(ego, actores_veh, medir_riesgo) dict
        +tomar_control(ego, manual)
        +controlar(ego, acelerar, dt)
        +girar(ego, destino) bool
        +inyectar(ego_id, tipo, edges, estilo)
        +cerrar()
    }
    class EstiloConductor {
        estilos.py
    }
    class comparacion3d {
        <<module>>
        -_preparar_zona(comp, nodo_id, lon, lat, ...)
        +escribir_sumocfg_lado(destino, net, demanda, vtypes)
        +correr_comparacion(comp, cola, bucle)
        -_ruta_inyeccion(accesos, acceso, giro)
        -_destino_giro(accesos, ruta, giro)
        +mensaje_json(texto) dict
    }
    class telemetria {
        <<module>>
        TTC, DRAC, PET
        clasificar_accion
    }
    class escena3d {
        <<module>>
        +geometria_escena(...)
        +rutas_por_acceso(...)
    }

    GestorComparaciones "1" o-- "*" Comparacion
    GestorComparaciones ..> comparacion3d : preparar
    Comparacion "1" *-- "2" Lado : sin y con semáforo
    Lado ..> EstiloConductor
    Lado ..> telemetria
    comparacion3d ..> Lado : crea
    comparacion3d ..> escena3d
```

---

## Cómo mantenerlo

- Si agregas un `TransportMode`, actualiza 4.2 y el color en `kepler/src/modos.js`.
- Si agregas un componente al pipeline, agrégalo en 3.1 y verifica que su archivo exista.
- Mermaid `C4Component` es experimental y su layout es automático. Si necesitas control exacto de posiciones, usa `tesis.drawio` como fuente visual.
