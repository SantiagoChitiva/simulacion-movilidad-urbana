# API de `simulation-service`: diagramas de clases

La documentación OpenAPI completa de la API (26 rutas, FastAPI 0.136.3) está en [`openapi.json`](openapi.json). Se generó con `app.openapi()` desde `simulation-service/src` (`from api.api import app`). La API viva la publica en `/docs` y `/openapi.json`.

Para regenerarla, desde `simulation-service/` con el venv activo:

```bash
python -c "import json; from api.api import app; json.dump(app.openapi(), open('../docs/api/openapi.json', 'w'), indent=2, ensure_ascii=False)"
```

El OpenAPI solo describe los cuerpos de **entrada** (modelos Pydantic). Los endpoints devuelven `dict`, así que sus respuestas no tienen esquema en el JSON. Por eso el diagrama 2 se armó leyendo el código.

## 1. Esquemas de la API (OpenAPI)

Modelos Pydantic de `api/api.py` y los enumerados que usan. Las flechas son referencias entre esquemas.

```mermaid
classDiagram
    direction LR

    class SolicitudSimulacion {
        +Preset preset = encuesta
        +dict~TransportMode,int~ conteos
        +int? semilla  (>= 0)
        +EstiloConductor estilo = normal
        +SolicitudCierre[] cierres
    }
    note for SolicitudSimulacion "Cada conteo: 0..MAX_VIAJES.\nTotal de viajes: 1..100 000 (si no, 422)."

    class SolicitudCierre {
        +string edge_id
        +float hora_inicio  (>= 0)
        +float hora_fin  (>= 0)
        +string? modos_afectados
    }

    class SolicitudEscenario {
        +string run_id
        +int radio_m = 300  (50..2000)
    }

    class SolicitudProgramaTLS {
        +string tipo = static
        +float offset = 0.0
        +dict[] fases
    }

    class SolicitudWebster {
        +string? run_id
        +int num_fases = 2  (1..8)
    }

    class SolicitudComparacion {
        +string escenario_run_id
        +string[] programas
        +int? semilla
    }

    class SolicitudComparacion3D {
        +float lon
        +float lat
        +string? run_id
        +dict~string,float~? intensidades  (0..3000 por modo)
        +string[]? nodos
    }

    class Preset {
        <<enumeration>>
        encuesta
        mas_vehiculos
        mas_peatones
        dia_sin_carro
    }

    class EstiloConductor {
        <<enumeration>>
        agresivo
        normal
        cauteloso
    }

    class TransportMode {
        <<enumeration>>
        auto
        bici
        peaton
        transporte_publico
        moto
        taxi
        escolar
        especial
        informal
        otro
    }

    class HTTPValidationError {
        +ValidationError[] detail
    }

    class ValidationError {
        +any[] loc
        +string msg
        +string type
    }

    SolicitudSimulacion --> Preset
    SolicitudSimulacion --> EstiloConductor
    SolicitudSimulacion --> TransportMode : claves de conteos
    SolicitudSimulacion "1" *-- "0..*" SolicitudCierre
    HTTPValidationError "1" *-- "0..*" ValidationError
```

### Rutas por grupo

| Grupo | Rutas | Cuerpo de entrada |
|---|---|---|
| Corrida por defecto | `GET /health`, `GET /simulation-output`, `GET /kepler-trips` | — |
| Demanda | `GET /demanda/modos`, `/demanda/presets`, `/demanda/estilos` | — |
| Corridas | `POST /simulaciones` (202), `GET /simulaciones`, `GET /simulaciones/{run_id}`, `POST /simulaciones/{run_id}/cancelar` (202), `GET /simulaciones/{run_id}/kepler-trips` | `SolicitudSimulacion` en el POST |
| Precalculadas | `GET /precalculadas`, `GET /precalculadas/{preset}/kepler-trips` | — |
| Intersecciones | `GET /intersecciones`, `/intersecciones/priorizacion`, `/intersecciones/{tl_id}` | — |
| Zonas y programas | `POST /intersecciones/{tl_id}/escenarios` (202), `GET /escenarios/{run_id}`, `GET /intersecciones/{tl_id}/programas[/{program_id}]`, `PUT .../programas/{program_id}`, `POST .../programas/webster` | `SolicitudEscenario`, `SolicitudProgramaTLS`, `SolicitudWebster` |
| Comparación de programas | `POST /intersecciones/{tl_id}/comparaciones` (202), `GET /comparaciones/{id}` | `SolicitudComparacion` |
| Simulador 3D | `POST /cruces/{nodo_id}/comparacion3d` (202), `GET /comparacion3d`, `GET /comparacion3d/{cid}`, `GET .../geometria`, `DELETE /comparacion3d/{cid}` (204), `WS /comparacion3d/{cid}` | `SolicitudComparacion3D` |

El WebSocket no aparece en el OpenAPI (OpenAPI no describe WebSocket). Sus comandos de entrada son `pausa`, `velocidad`, `periodo_riesgo`, `control`, `seguir`, `inyectar`, `manual` y `giro`.

## 2. Clases del servidor

Clases que implementan la API: los gestores de `api/jobs.py` y `api/comparacion3d.py`, y las estructuras de `etl/sumo/` que se devuelven como JSON. Solo se muestran los atributos y métodos principales.

```mermaid
classDiagram
    direction TB

    class FastAPIApp {
        <<api/api.py>>
        +dependency obtener_gestor()
        +dependency obtener_gestor_comparaciones()
    }

    class GestorCorridas {
        <<api/jobs.py>>
        -ThreadPoolExecutor(1) pool
        +crear(demanda, semilla, estilo, cierres) Corrida
        +cancelar(run_id) Corrida
        +obtener(run_id) Corrida?
        +listar() Corrida[]
        +paths(run_id) ScenarioPaths
        +esperar(run_id, timeout)
    }

    class Corrida {
        <<dataclass>>
        +string id
        +string preset
        +dict~string,int~ conteos
        +int? semilla
        +string estado
        +float avance
        +float? avance_etapa
        +string? error
        +dict? resultado
        +string estilo
        +dict[] cierres
        +string creada
        +string actualizada
    }

    class GestorComparaciones {
        <<api/comparacion3d.py>>
        MAX_COMPARACIONES = 2
        -dict~string,Comparacion~ comparaciones
        +crear(nodo, lon, lat, run_id, intensidades, nodos) Comparacion
        +obtener(cid) Comparacion?
        +cerrar(cid)
        +listar() dict[]
    }

    class Comparacion {
        <<dataclass>>
        +string cid
        +string nodo_id
        +string[] nodos
        +string estado
        +string? etapa
        +dict info
        +dict? geometria
        +string? error
        +bool conectada
        +bool pausada
        +float velocidad
        +float periodo_riesgo
        +bool manual
        +int acelerar
        +resumen() dict
    }

    class Lado {
        <<TraCI + SUMO>>
        +string nombre
        +string? tl_id
        +int colisiones
        +int conflictos
        +float max_riesgo
        +avanzar(hasta)
        +actores() tuple
        +luces() dict?
        +contar_conflictos()
        +telemetria(ego, actores, medir_riesgo) dict?
        +inyectar(ego_id, tipo, edges, estilo)
        +tomar_control(ego, manual)
        +controlar(ego, acelerar, dt)
        +girar(ego, destino) bool
        +cerrar()
    }

    class Riesgo {
        <<dataclass, frozen>>
        +float indice
        +string nivel
        +string causa
        +float? ttc
        +float? drac
        +float? pet
        +to_dict() dict
    }

    class Semaforo {
        <<dataclass>>
        +string id
        +string tipo
        +string programa
        +float ciclo
        +float lon
        +float lat
        +float z
        +string nombre
        +string[] calles
        +int movimientos
    }

    class Acceso {
        <<dataclass>>
        +string edge
        +string? calle
        +string clase
        +int carriles
        +float velocidad_kmh
        +int movimientos
        +int? volumen
        +float? volumen_hora
        +dict? volumen_por_tipo
    }

    class Fase {
        <<dataclass>>
        +float duracion
        +string estado
        +dict~string,string~ luces
    }

    class ProgramaTLS {
        <<dataclass>>
        +string tl_id
        +string program_id
        +string tipo
        +float offset
        +ciclo_s() float
    }

    class FasePrograma {
        <<dataclass>>
        +float duracion_s
        +string estado
    }

    class CierreVial {
        <<dataclass>>
        +string edge_id
        +float hora_inicio_s
        +float hora_fin_s
        +string modos_afectados
    }

    class ScenarioPaths {
        <<dataclass, frozen>>
        +from_name(name, run_id) ScenarioPaths
    }

    FastAPIApp ..> GestorCorridas : inyecta
    FastAPIApp ..> GestorComparaciones : inyecta
    GestorCorridas "1" o-- "0..*" Corrida
    GestorCorridas ..> ScenarioPaths
    Corrida "1" o-- "0..*" CierreVial : cierres
    GestorComparaciones "1" o-- "0..2" Comparacion
    Comparacion "1" --> "2" Lado : A sin semáforo, B con semáforo
    Lado ..> Riesgo : produce
    Semaforo "1" *-- "1..*" Acceso
    Semaforo "1" *-- "1..*" Fase
    ProgramaTLS "1" *-- "1..*" FasePrograma
    FastAPIApp ..> Semaforo : GET /intersecciones
    FastAPIApp ..> ProgramaTLS : programas y Webster
```

### Notas

- `GestorCorridas` ejecuta una corrida a la vez (`ThreadPoolExecutor(1)`) y guarda cada `Corrida` en `runs/<id>/estado.json`. Los estados son `en_cola`, `generando_demanda`, `ruteando`, `simulando`, `exportando`, `cancelando`, `terminado`, `error` y `cancelada`.
- `GestorComparaciones` rechaza con 429 la tercera comparación simultánea. Cada `Comparacion` abre dos `Lado` (dos procesos SUMO en lockstep) solo cuando se conecta el WebSocket.
- `Lado` está en la clase `Comparacion` solo de forma conceptual: se crea en el hilo que ejecuta `correr_comparacion`, no es un campo del dataclass.
- Los gestores se inyectan con `Depends`, y las pruebas los reemplazan con `app.dependency_overrides`.
