# Propuesta: módulo de intersecciones, semaforización y vista 3D

Estado: análisis y diseño, **sin implementar**. Fecha: 2026-10-05.

Este documento responde a dos preguntas del equipo:

1. Qué funcionalidades del proyecto [Semáforos de Barranquilla](https://github.com/Victorpay1/semaforos-barranquilla) se pueden adaptar a nuestro simulador.
2. Cuál es la mejor arquitectura para una vista 3D que muestre lo que de verdad ocurre en SUMO.

El flujo que buscamos:

> Mapa → seleccionar una intersección → obtener la red y los datos de esa zona → configurar y simular → ver la simulación en 3D y comparar resultados.

---

## 1. Qué hace el proyecto de Barranquilla

Es un monorepo TypeScript con tres paquetes: `pipeline/`, `scorer-jev/` y `web/` (Next.js + MapLibre, sitio estático). Revisamos el README, `docs/architecture.md`, `docs/simulation.md`, `docs/research/criteria.md`, `pipeline/src/priority.ts` y `web/lib/sim.ts`.

| Pieza | Qué hace | Dónde |
|---|---|---|
| Catálogo de cruces | Toma de OpenStreetMap (Overpass) los nodos compartidos por dos o más vías. Las dos calzadas de una avenida cuentan como un solo cruce. Para cada cruce guarda la clase de las vías, carriles, sentidos, ramas (3, 4…) y si es glorieta o desnivel. | `pipeline/src/build.ts` |
| Semáforos existentes | Concilia los nodos `highway=traffic_signals` de OSM con el inventario oficial de la ciudad (339 de 341 coincidían). | `pipeline/src/signals.ts` |
| Siniestros | Geocodifica los siniestros de la policía por dirección ("CL 72 CR 46"): solo cuando la dirección nombra exactamente dos vías y hay un único cruce con esos nombres. Ubicó el 66 % de los registros. | `pipeline/src/crashes.ts`, `streetkeys.ts` |
| Contexto | Colegios, centros de salud, mercados y paraderos a menos de 200 m. Distancia al semáforo más cercano, en línea recta y sobre la misma vía. | `pipeline/src/heuristic.ts` |
| Priorización | Cuatro niveles (prioritario, recomendado, observación, sin acción) que combinan:<br>- **reglas**: vía colectora o mayor, cruce a nivel, sin semáforo en la misma cuadra;<br>- **evidencia**: siniestros sobre el percentil 75 de los cruces ya semaforizados, o colegio u hospital cerca, o más de 600 m sin semáforo;<br>- **un modelo de IA de pago (Jev)**, consultado dos veces: con y sin los siniestros. | `pipeline/src/priority.ts` |
| Validación | Backtest contra los cruces que la ciudad ya semaforizó: de cada 10, la evaluación habría señalado 7; de 100 cruces tranquilos, ninguno. | `docs/validation.md` |
| Simulación del cruce | Microsimulación propia en el navegador (canvas 2D) que compara "hoy con PARE" contra "con semáforo de 2 fases". El reparto de verde es tipo Webster, y el amarillo y el todo rojo dependen de la velocidad y del tamaño del cruce. Los **volúmenes son supuestos** por clase de vía (60–1.800 veh/h), porque no tienen aforos. | `web/lib/sim.ts`, `web/components/JunctionSim.tsx` |
| Marco normativo | Manual de Señalización Vial 2024 (MinTransporte), cap. 4: **Condiciones A–F** para justificar un semáforo, entre ellas:<br>- **A, volumen**: 500–600 veh/h en la vía principal y 150–200 en la secundaria, durante 8 h;<br>- **C, peatones**: ≥ 250 peatones/h;<br>- **D, coordinación**: nunca a menos de 300 m de otro semáforo. | `docs/research/criteria.md` |

Su vista 3D no está en el repositorio. La simulación que publican es 2D e ilustrativa.

## 2. Qué adaptar y qué no

| Idea de Barranquilla | ¿Adaptar? | Cómo, en nuestro proyecto |
|---|---|---|
| Catálogo de cruces desde OSM, fusionando calzadas | **Sí** | Partir de los *junctions* de nuestra red SUMO, que ya vienen de OSM: los ids de los nodos se conservan y netconvert ya agrupa los clústeres. Les agregamos atributos de OSM: nombres, clase, carriles, `traffic_signals`, `crossing`. Una sola fuente de verdad para el mapa y la simulación. |
| Semáforos existentes | **Sí** | La red ya tiene **220 semáforos** (`tlLogic`). Los cruzamos con los **480 nodos `traffic_signals`** del OSM local para detectar los que netconvert no convirtió. El inventario oficial de la Secretaría Distrital de Movilidad (datos abiertos de Bogotá) puede reemplazar al de Barranquilla [por verificar disponibilidad y licencia]. |
| Priorización por reglas y evidencia | **Sí, sin el modelo de pago** | Usamos un puntaje abierto con los pesos que propone su `criteria.md` §3.2: jerarquía del par de vías (40), carriles y geometría (15), hueco en el corredor (15), demanda peatonal (15) y siniestralidad (15). Las mismas reglas duras: menos de 300 m de otro semáforo pone un tope; glorietas y desniveles se excluyen. |
| Volúmenes supuestos por clase de vía | **No: es nuestra ventaja** | Nuestra simulación ya produce **volúmenes modelados por acceso** a partir de la encuesta. Se pueden medir con detectores E1/E2 o `edgeData` en los accesos del cruce. Con eso las **Condiciones A, B y C del Manual 2024** se evalúan con números y no con supuestos. Es indicativo, no un dictamen: nuestra ventana es de 3 h y el Manual pide 8. |
| Siniestros por dirección | **Más adelante** | Bogotá publica siniestros con coordenadas [por verificar], lo que evitaría el geocodificado por dirección. |
| POIs (colegios, salud, paraderos) | **Sí** | Nuestro OSM local (OSMnx) no los trae. Hace falta una consulta Overpass acotada a Usaquén, guardada en `data/raw/`. |
| Microsimulación propia en JS | **No** | Usamos **SUMO**: las comparaciones salen del mismo motor que el resto del proyecto, con la demanda de la encuesta. |
| Comparar "hoy" contra "con semáforo" | **Sí, generalizado** | Comparamos N configuraciones del mismo cruce: programa actual, Webster, actuado, sin semáforo (prioridad) y semáforo nuevo. Todas con la misma demanda y la misma semilla. |

## 3. Datos de Usaquén con los que contamos hoy

| Dato | Estado |
|---|---|
| Red SUMO 3D (`usaquen_3d.net.xml`) | 28.080 edges, 7.338 cruces de prioridad, **220 semáforos estáticos**. Todos tienen el programa por defecto de netconvert (82 s verde, 3 s amarillo, 5 s todo rojo), no tiempos reales. |
| OSM local (`data/processed/usaquen.osm.xml`) | 42.888 nodos, 11.743 vías, 480 `traffic_signals`, 2.093 `crossing`. **Sin relaciones** (rutas de bus) ni POIs. |
| Pasos peatonales en la red SUMO | 0. La red se generó sin `--crossings.guess`: los peatones cruzan sin cebra ni fase peatonal. |
| Demanda | Encuesta 2023, 07:00–10:00, con presets y conteos por modo. Ver el [README](../README.md#escenarios-de-demanda). |
| Rutas por vehículo | El `.sumocfg` ya escribe `vehroute-output` con tiempos de salida de cada edge, que es la entrada de `cutRoutes.py`. |

## 4. Flujo funcional propuesto

```
[1] Mapa de intersecciones ──► [2] Selección ──► [3] Recorte de la zona ──► [4] Demanda de la zona
        (kepler/deck.gl)                           (netconvert)               (cutRoutes.py)
                                                                                      │
[8] Vista 3D en vivo ◄── [7] Métricas y comparación ◄── [6] Corridas headless ◄── [5] Configurar semáforo
   (deck.gl + TraCI)        (tripinfo, queue, E2)        (misma semilla)            (programa, Webster, actuado)
```

1. **Mapa de intersecciones.** Una capa nueva en el visor muestra los cruces: semaforizados, candidatos por puntaje o sin acción. Igual que en Barranquilla, cada uno tiene una ficha de **evidencia verificable**: vías que se cruzan, distancia al semáforo más cercano, volúmenes simulados y POIs cercanos.
2. **Selección.** Clic en un cruce. La API identifica el *junction* SUMO, sus *edges* de entrada y salida, el `tlLogic` si existe y los atributos OSM.
3. **Recorte de la zona.** `netconvert -s usaquen_3d.net.xml --keep-edges.in-geo-boundary <bbox>` con un radio configurable (300 m por defecto). Así sale una subred pequeña que conserva la altura y los semáforos.
4. **Demanda de la zona.** `tools/route/cutRoutes.py` recorta las rutas de una corrida de ciudad (sus `vehroute` con tiempos) a la subred. Así la demanda del cruce es **coherente con la encuesta y con el preset elegido**: Día sin carro, por ejemplo. También recorta personas que caminan (`--pt-input` y `keep.walk`) [por verificar la calidad con nuestra demanda]. Se puede escalar con `--scale` de SUMO.
5. **Configurar el semáforo.**
   - Ver el programa actual: fases, duraciones y qué movimiento controla cada letra del estado.
   - Editar ciclo, verdes por fase y desfase.
   - Calcular tiempos con **Webster** usando los flujos de la zona (`tools/tlsCycleAdaptation.py`).
   - Cambiar a semáforo **actuado** (`type="actuated"`) o *delay_based*.
   - En un cruce sin semáforo, **agregar uno**: `netconvert --tls.set <id>` sobre la subred.
   - Opción "sin semáforo" (prioridad o PARE).
   - Los programas se guardan como archivos adicionales (`<tlLogic programID="…">`), así que la red no cambia.
6. **Corridas comparativas.** Cada configuración se corre *headless* sobre la subred con la misma demanda y la misma semilla. Reutiliza `GestorCorridas` (`src/api/jobs.py`). Son mucho más rápidas que la ciudad completa: segundos o pocos minutos.
7. **Métricas.** Comparación lado a lado:
   - demora y tiempo perdido medio por modo y por acceso (`tripinfo`);
   - cola máxima por carril (`queue-output` o detectores E2);
   - espera peatonal (`personinfo`);
   - vehículos atendidos por hora;
   - teleports y frenadas de emergencia.

   Se agregan las Condiciones A/B/C del Manual 2024 evaluadas con los volúmenes simulados, marcadas como **indicativas**.
8. **Vista 3D en vivo** de la configuración elegida (sección 5).

## 5. Arquitectura de la vista 3D

### 5.1 Requisito clave

La vista 3D **no puede ser una animación inventada en el frontend**: tiene que mostrar el estado de SUMO. Eso significa:
- posiciones, ángulos y velocidades de cada vehículo, bicicleta y peatón;
- el estado de cada semáforo **por movimiento** (la cadena `rrGGyy…` de su `tlLogic`);
- los cambios de luz en el instante en que ocurren.

### 5.2 Nuestro stack

- **Frontend:** Vite + React 18 + kepler.gl 3.2. kepler.gl ya trae **deck.gl 8.9.36** (incluidos `@deck.gl/mesh-layers` y `@deck.gl/geo-layers`), `react-map-gl` 7.1 y **MapLibre 3.6**.
- **Backend:** FastAPI (Python) con SUMO 1.27. El paquete `traci` y `sumolib` están en `SUMO_HOME/tools`, y también en PyPI con la misma versión.

### 5.3 Recomendación: deck.gl + TraCI por WebSocket

```
┌────────────────────────── simulation-service (FastAPI) ──────────────────────────┐
│  POST /intersecciones/{id}/sesion  → arranca SUMO de la subred con TraCI          │
│  WS   /sesiones/{sid}              → bucle: traci.simulationStep()                │
│        cada paso envía  {t, vehiculos[], personas[], semaforos[]}                 │
│        recibe comandos  {pausa, velocidad, fase, programa, duracion_fase}         │
│  GET  /sesiones/{sid}/geometria    → carriles, cruces y semáforos en lon/lat/z    │
└──────────────────────────────────────────────────────────────────────────────────┘
                 │ WebSocket (JSON compacto o binario, 5–10 mensajes/s)
┌──────────────────────────── kepler/ (React) ─────────────────────────────────────┐
│  Vista "Intersección 3D": DeckGL + react-map-gl/maplibre                          │
│   - PolygonLayer/PathLayer  : carriles y área del cruce (desde el .net.xml, con z)│
│   - ScenegraphLayer (glTF)  : autos, motos, buses, bicis y personas por tipo      │
│   - SimpleMeshLayer/Column  : postes de semáforo; color = estado del movimiento   │
│   - TextLayer               : nombres de calles y contadores de cola              │
│   Interpolación entre pasos en el cliente para que el movimiento se vea continuo  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**Por qué deck.gl:**
- **Ya está en el proyecto.** Viene con kepler.gl, en las mismas versiones, así que no se agrega otro motor 3D.
- **Es georreferenciado.** Las coordenadas lon/lat/z de SUMO (`fcd-output.geo`, `sumolib` `convertXY2LonLat`) se usan directamente, con cámara de mapa (pitch, bearing, zoom) y mapa base.
- **Tiene las capas 3D que necesitamos.** `ScenegraphLayer` dibuja un modelo glTF por entidad con orientación (`getOrientation` a partir del ángulo de SUMO) y escala por tipo. Una subred de 300 m tiene cientos de entidades, muy lejos del límite de deck.gl.
- **Permite pasar del mapa general a la vista 3D sin cambiar de librería.** La selección del cruce se hace en la vista kepler, que también es deck.gl, y la vista 3D se abre como otra pantalla de la misma app.
- **Mapa base sin token.** MapLibre funciona con un mapa base abierto, como OpenFreeMap, que también usa Barranquilla.

**Por qué TraCI en vivo y no solo reproducir archivos:**
- El usuario quiere **modificar los semáforos y ver el efecto**. Con TraCI se cambia de programa o de fase en caliente (`trafficlight.setProgram`, `setPhase`, `setPhaseDuration`, `setProgramLogic`) y la simulación reacciona en ese momento.
- Los estados de luz se leen **por movimiento** con `trafficlight.getRedYellowGreenState` + `getControlledLinks`. Así cada carril de entrada recibe su color exacto.
- Las posiciones salen de `vehicle.getPosition3D` / `person.getPosition3D` y `getAngle`, o de *subscriptions* para pedirlo todo en una sola llamada por paso.
- Para la subred del cruce, SUMO va mucho más rápido que el tiempo real: el bucle se puede frenar a 1×, 2× o 5×.

**Modo de respaldo, replay.** Para videos o para equipos sin backend se puede grabar una corrida:
- FCD (`fcd-output.geo`, con z);
- los estados de semáforo, con `<timedEvent type="SaveTLSStates">` en un archivo adicional.

El frontend reproduce esos archivos con el **mismo formato de mensaje** que el WebSocket. El modo en vivo y el replay comparten la vista.

### 5.4 Alternativas consideradas

| Opción | Por qué no como base |
|---|---|
| Three.js / React Three Fiber | Da más control visual (sombras, materiales, edificios detallados), pero hay que construir a mano la georreferenciación, la cámara de mapa, el mapa base y la selección. Puede servir más adelante para una escena "cinemática" del cruce, alimentada por el mismo WebSocket. |
| CesiumJS | Globo 3D con terreno real: atractivo para la altura de Usaquén, pero es pesado, tiene su propio stack y no se integra con kepler.gl. |
| Unity / Unreal (+ conector SUMO) | Fuera del stack web y difícil de desplegar para el equipo y los evaluadores. |
| `sumo-gui` en 3D (OSG) | Solo escritorio; no se integra en la web. |
| Kepler Trip layer (lo que tenemos) | Sirve para la vista de ciudad, pero dibuja trazas, no objetos 3D, y no tiene semáforos ni interacción. |

### 5.5 Formato de mensaje propuesto

```json
{
  "t": 25321.0,
  "vehiculos": [["auto_17", "auto", -74.03211, 4.70122, 2561.4, 87.0, 6.2]],
  "personas":  [["peaton_88", -74.03190, 4.70110, 2560.9, 270.0, 1.1]],
  "semaforos": [{"id": "10564081144", "estado": "GGrrGGrr", "fase": 0, "restante": 23.0}]
}
```

Las filas en arreglo (`id, tipo, lon, lat, z, ángulo, velocidad`) reducen el tamaño frente a objetos. La geometría de carriles y la relación "índice del estado → carril y movimiento" se envían **una sola vez**, en `/geometria`.

## 6. Fases de implementación (siguiente iteración)

| Fase | Entregable | Notas y riesgos |
|---|---|---|
| A. Catálogo | `GET /intersecciones` (GeoJSON) desde la red SUMO + OSM, y una capa en el visor con ficha de evidencia | Los clústeres de netconvert (`cluster_…`) agrupan varios nodos OSM; hay que mapearlos. |
| B. Recorte y demanda | Subred por bbox + `cutRoutes.py` desde la corrida elegida | Verificar `cutRoutes` con personas, y que los bordes del recorte no generen inserciones en cola. |
| C. Semáforos | Leer y editar programas, Webster (`tlsCycleAdaptation.py`), tipo actuado, agregar o quitar semáforo | Los 220 programas actuales son los de netconvert, no los reales: la línea base "hoy" es una aproximación. |
| D. Comparación | Corridas headless en lote, métricas y Condiciones A/B/C indicativas | Reutiliza `GestorCorridas`. Definir el período de calentamiento. |
| E. 3D en vivo | Sesión TraCI + WebSocket + vista deck.gl con modelos glTF y semáforos | Elegir modelos glTF con licencia abierta. Una sesión TraCI por usuario: limitar sesiones simultáneas. |
| F. Priorización | Puntaje abierto + POIs (Overpass) + siniestros de Bogotá | Validar como Barranquilla: contra los cruces ya semaforizados. |
| Previo recomendado | Regenerar la red con `--crossings.guess` (pasos peatonales) | Sin cruces peatonales, la fase peatonal y la espera de peatones en el semáforo no se pueden modelar bien. Hay que volver a correr la ciudad. |

Orden sugerido: A → B → C → E (para tener pronto el flujo completo con 3D) → D → F.
