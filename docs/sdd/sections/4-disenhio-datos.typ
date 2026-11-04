#import "@preview/fletcher:0.5.8": diagram, node, edge

= Diseño de datos

== Esquema de base de datos

El sistema *no usa un motor de base de datos*. Los datos son archivos (TSV, XML de SUMO, JSON y GeoJSON) organizados por escenario y por corrida, y las estructuras en memoria son `dataclass` de Python. Se decidió así porque el volumen es pequeño (un único escenario), los resultados de SUMO ya son archivos, y se evita instalar y operar un servicio adicional (@sec-adrs, ADR-03). El «esquema» se describe, entonces, como el modelo de entidades y su ubicación en disco.

#figure(
  diagram(
    node-stroke: 0.6pt,
    node-inset: 5pt,
    spacing: (12mm, 13mm),
    node((0, 0), [*Escenario*\ `scenarios/<nombre>/`], name: <esc>),
    node((1, 0), [*Corrida*\ `runs/<id>/`\ `estado.json`], name: <run>),
    node((2, 0), [*Comparación 3D*\ `runs/sem-<id>/`], name: <c3d>),
    node((0, 1), [*Viaje de encuesta*\ (`TripRecord`)], name: <trip>),
    node((1, 1), [*Salida de SUMO*\ FCD, vehroute,\ statistics], name: <sal>),
    node((2, 1), [*Precalculada*\ `precalculadas/<preset>/`], name: <pre>),
    node((0, 2), [*Semáforo / Cruce*\ (`Semaforo`,\ `PuntajeCruce`)], name: <sem>),
    node((1, 2), [*Volúmenes por edge*\ `volumenes.json`], name: <vol>),
    node((2, 2), [*Trips de kepler*\ GeoJSON `LineString`], name: <kep>),
    edge(<esc>, <run>, "->", [plantilla]),
    edge(<run>, <c3d>, "-->", [rutas reales]),
    edge(<esc>, <trip>, "->"),
    edge(<run>, <sal>, "->", [produce]),
    edge(<sal>, <vol>, "->", [cuenta]),
    edge(<vol>, <sem>, "->", [puntúa]),
    edge(<sal>, <kep>, "->"),
    edge(<pre>, <kep>, "->"),
  ),
  caption: [Modelo de entidades de datos y su relación.],
) <fig-entidades>

La entrada de todo el sistema es el *TSV de viajes internos* (`scenarios/default/viajes_usaquen_internos.tsv`, 2.580 filas), producto de los cuadernos de exploración: ya viene filtrado a viajes con origen y destino en Usaquén y con las zonas ZAT mapeadas a TAZ. La *red* (`usaquen_3d.net.xml`, con elevación) y las *zonas* (`usaquen.taz.xml`) también se generan fuera del servicio y se copian al escenario.

== Diccionario de datos

=== Viaje de la encuesta (TSV de entrada)

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Campo], [Tipo], [Descripción y restricciones],
    [`zat_ori`], [entero], [Zona de origen; se mapea a un id de TAZ. Fila inválida si falta.],
    [`zat_des`], [entero], [Zona de destino. Fila inválida si falta.],
    [`hora_ini_seg`], [real], [Hora de salida en segundos desde las 00:00. Solo se aceptan viajes entre `HORA_INI` (25.200) y `HORA_FIN` (36.000).],
    [`hora_ini_hhmmss`], [texto], [Misma hora en formato legible (informativo).],
    [`duracion_min`], [real, opcional], [Duración reportada; define el rango de duración para los presets.],
    [`modo_principal_agrupado`], [texto], [Etiqueta cruda (`SurveyMode`, 11 valores) que se convierte en `TransportMode` (10 modos).],
    [`motivo_viaje`], [texto], [Motivo del viaje (informativo, no usado por el pipeline).],
    [`fexp_vj`], [real], [Factor de expansión. El viaje se replica `round(fexp_vj)` veces, con tope `MAX_COPIAS` = 50.],
  ),
  caption: [Columnas del TSV de viajes y su uso.],
)

Las filas inválidas, fuera de ventana o con modo desconocido no se descartan en silencio: se cuentan en `TripGenerationStats` (`filas_invalidas`, `fuera_de_ventana`, `modos_desconocidos`) y se reportan en el resumen de la corrida.

=== Estado de una corrida (`runs/<id>/estado.json`)

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Campo], [Tipo], [Descripción],
    [`id`], [texto], [`AAAAMMDD-HHMMSS-<6 hex>`; clave primaria de la corrida y nombre del directorio.],
    [`preset`], [texto], [Uno de `encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`.],
    [`conteos`], [mapa modo → entero], [Viajes pedidos por modo; la suma debe estar entre 1 y 100.000.],
    [`semilla`], [entero o nulo], [Semilla de SUMO; nulo = la del `.sumocfg`.],
    [`estilo`], [texto], [`agresivo`, `normal` o `cauteloso`.],
    [`cierres`], [lista], [Cierres viales: `edge_id`, `hora_inicio_s`, `hora_fin_s`.],
    [`estado`], [texto], [`en_cola` → `generando_demanda` → `ruteando` → `simulando` → `exportando` → `terminado`; o `cancelando`, `cancelada`, `error`.],
    [`avance`], [real 0--1], [Avance global (según `FRANJAS_ETAPA`).],
    [`avance_etapa`], [real o nulo], [Avance dentro de la etapa; nulo si no se puede medir.],
    [`creada`, `iniciada`, `actualizada`], [ISO 8601], [Marcas de tiempo.],
    [`error`], [texto o nulo], [Mensaje si falló.],
    [`resultado`], [objeto o nulo], [`viajes_generados`, `viajes_por_modo`, `trips_kepler` y las estadísticas de SUMO (`vehiculos_insertados`, `teleports`, `colisiones`, ...).],
  ),
  caption: [Campos de `estado.json` (dataclass `Corrida`).],
)

=== Trips para kepler (GeoJSON de `LineString`)

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Campo], [Tipo], [Descripción],
    [`properties.id`], [texto], [Id del vehículo o persona. Para personas, el prefijo (`peaton_N`, `transporte_publico_N`) determina el modo.],
    [`properties.mode`], [texto], [`TransportMode`; el visor le asigna color.],
    [`properties.category`], [texto], [`vehiculo` o `persona`.],
    [`properties.inicio_s`, `fin_s`], [entero], [Segundos de simulación al aparecer y al salir.],
    [`properties.dist_m`, `avg_kmh`], [numérico], [Distancia recorrida y velocidad media.],
    [`geometry.coordinates[i]`], [`[lon, lat, z, t]`], [`z` relativa al mínimo del FCD; `t` = _unix time_ = 2000-01-01 UTC + segundos de simulación (07:00 en pantalla = 25.200 s en SUMO).],
  ),
  caption: [Esquema de cada _feature_ de `kepler.geojson`.],
)

=== Metadatos de una precalculada (`meta.json`) y volúmenes

`meta.json` contiene `preset`, `conteos`, `semilla`, `generada`, `tamano_original`, `tamano_gz`, `resultado` (el mismo resumen de una corrida) e `insumos`: una huella SHA-256 (16 primeros hex) de TSV, red, TAZ y `.sumocfg`, con los saltos de línea normalizados. Sirve para detectar que una precalculada quedó desactualizada respecto a sus insumos.

`volumenes.json` mapea cada `edge` a un contador por modo (por ejemplo `{"-1012541443#0": {"bici": 12}}`). Se obtiene recorriendo `vehroute.xml` y contando la última ruta de cada `routeDistribution`; reemplaza al `vehroute` (~22 MB) en las precalculadas.

=== Intersección y cruce candidato

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Entidad / campo], [Tipo], [Descripción],
    [`Semaforo`], [dataclass], [Un `tlLogic`: `id`, `tipo`, `programa`, `offset`, `ciclo`, `fases`, `cruces` (nodos), `lon`, `lat`, `z`, `accesos`, `calles`, `movimientos`, `enlaces`.],
    [`Acceso`], [dataclass], [`edge`, `calle`, `clase`, `carriles`, `velocidad_kmh`, `movimientos` y volúmenes opcionales (`volumen`, `volumen_hora`, `volumen_por_tipo`).],
    [`Fase`], [dataclass], [`duracion`, `estado` (una letra por `linkIndex`), `luces` por acceso (verde, amarillo, rojo, apagado).],
    [`ProgramaTLS`], [dataclass], [`tl_id`, `program_id`, `tipo`, `offset`, lista de `FasePrograma(duracion_s, estado)`; `ciclo_s` es la suma de duraciones.],
    [`PuntajeCruce`], [dataclass], [`nodo_id`, `nodos`, `lon`, `lat`, `puntaje_total` (0--100), `nivel` (`prioritario`, `recomendado`, `observacion`), `detalle` (5 componentes en 0--1), `siniestros`, `generadores`, `tramo_m`, `volumen`, `calles`, `evidencias`, `distancia_semaforo_m`.],
  ),
  caption: [Entidades de análisis de intersecciones.],
)

=== Mensaje de _frame_ del simulador 3D <sec-datos-frame>

Cada frame del WebSocket es un objeto JSON `{tipo: "frame", t, dt, ego, manual, lados: {a: L, b: L}}`, donde cada lado `L` contiene:

- `vehiculos` y `personas`: listas de actores `[id, tipo, x, y, z, ángulo, velocidad, edge]` en coordenadas de la red.
- `luces`: `{estado, fase, restante}` del semáforo (nulo en el lado A, que no tiene).
- `metricas`: `vehiculos`, `peatones`, `en_cruce`, `detenidos_cruce`, `velocidad_media_cruce_kmh`, `espera_media_cruce_s`, `espera_lateral_s`, `colisiones`, `conflictos`, `riesgo_max`.
- `ego`: telemetría del actor seguido (velocidad, aceleración, líder, riesgo `TTC/DRAC/PET`, acción, decisiones posibles en el próximo cruce).

== Estrategia de almacenamiento <sec-almacenamiento-ref>

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Ubicación], [Versionada], [Contenido y política],
    [`scenarios/default/`], [Sí], [Insumos: TSV, red 3D, TAZ, plantilla `.sumocfg`, `nombres_vias.json`, programas de semáforo guardados.],
    [`precalculadas/<preset>/`], [Sí], [`trips.geojson.gz` (11,7 MB comprimido frente a 63,7 MB), `volumenes.json`, `meta.json`. El `*.geojson` sin comprimir se ignora.],
    [`data/processed/`], [Sí], [Evidencia descargada una vez: siniestros SDM, POI y edificios OSM/Microsoft.],
    [`runs/<id>/`], [No], [Archivos generados por corrida y por comparación; se borran al cancelar (menos `estado.json`) o al cerrar la comparación.],
    [`cache/`], [No], [`semaforos.json` y `priorizacion.json`, invalidados por mtime y tamaño de la red (y por `VERSION_ANALISIS`).],
    [`runs/<id>/output/volumenes.json`], [No], [Caché de volúmenes junto a la corrida, invalidada por mtime/tamaño del `vehroute`.],
  ),
  caption: [Ubicaciones de almacenamiento y su política.],
)

*Decisiones de almacenamiento relevantes:*

- *Archivos pesados efímeros.* El FCD de una corrida completa es de gigabytes; se escribe cada 2 s (`device.fcd.period=2`), se convierte en streaming con `iterparse` y se borra tras el export. No se genera `emission-output` (~2 GB sin uso).
- *Reproducibilidad de las precalculadas.* El `.gz` se escribe con `mtime=0`, de modo que regenerar el mismo contenido da el mismo archivo y Git no registra cambios espurios.
- *Servir comprimido.* La API entrega el `.gz` sin descomprimir con `Content-Encoding: gzip` y `X-Tamano-Original`, que el visor usa para dibujar el progreso de descarga.
- *Persistencia del historial.* `estado.json` se escribe como mucho cada 2 s durante una etapa; al reiniciar el servicio, `GestorCorridas` recarga las corridas existentes.
- *Las corridas no se pisan.* Los archivos generados van a `runs/<id>/`; sin `run_id` se escribe en el escenario (comportamiento heredado para ejecutar el pipeline desde la línea de comandos).
