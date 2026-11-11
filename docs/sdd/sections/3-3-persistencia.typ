#import "uml.typ": *

== Persistencia <sec-persistencia>

El sistema *no usa un motor de base de datos*. Los datos se guardan como archivos (TSV, XML de SUMO, JSON y GeoJSON) organizados por escenario y por corrida, y las estructuras en memoria son `dataclass` de Python. Se decidió así porque el volumen es pequeño (un único escenario), los resultados de SUMO ya son archivos y se evita instalar y operar un servicio adicional. Por eso, en lugar de un diagrama entidad--relación sobre tablas, el modelo se describe con un diagrama de clases con estereotipos @ambler-datos en el que cada «directorio» y cada «archivo» juega el papel de una entidad, y su ubicación en disco el de su esquema.

=== Modelo de persistencia

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 0pt,
      spacing: (8mm, 9mm),
      clase((0, 0), "scenarios/<nombre>/", est: "directorio", attrs: ("viajes_usaquen_internos.tsv", "usaquen_3d.net.xml", "usaquen.taz.xml", "usaquen-sim.sumocfg (plantilla)", "nombres_vias.json", "programas de semáforo editados"), name: <esc>),
      clase((1, 0), "runs/<id>/", est: "directorio", attrs: ("estado.json", "usaquen-sim.sumocfg", "*.trips.xml, *.rou.xml", "vtypes_estilo.xml, cierres.xml", "output/"), name: <run>),
      clase((2, 0), "runs/<id>/output/", est: "directorio", attrs: ("usaquen_am.fcd.xml (efímero)", "usaquen_am.vehroute.xml", "usaquen_am.statistics.xml", "usaquen_am.kepler.geojson", "volumenes.json (caché)"), name: <out>),
      clase((3, 0), "cache/", est: "directorio", attrs: ("semaforos.json", "priorizacion.json"), name: <cac>),
      clase((1, 1), "runs/sem-<id>/", est: "directorio", attrs: ("zona.net.xml (lado A)", "zona_tls.net.xml (lado B)", "zona.rou.xml, fondo_*.trips.xml", "vtypes.add.xml", "semaforo_propuesto.nod.xml"), name: <sem>),
      clase((2, 1), "precalculadas/<preset>/", est: "directorio", attrs: ("trips.geojson.gz", "volumenes.json", "meta.json"), name: <pre>),
      clase((3, 1), "data/processed/", est: "directorio", attrs: ("siniestros_usaquen.geojson", "pois_usaquen.geojson", "edificios_osm.geojson", "red y TAZ de origen"), name: <dat>),
      edge(<esc>, <run>, "->", label: [1..\*], label-side: left),
      edge(<run>, <out>, "*->", label: [1], label-side: left),
      edge(<run>, <sem>, "-->", label: [rutas reales (0..1)], label-side: left),
      edge(<out>, <pre>, "-->", label: [`generar`], label-side: left),
      edge(<out>, <cac>, "-->", label: [volúmenes], label-side: left),
      edge(<dat>, <cac>, "-->", label: [evidencia], label-side: left),
    ))
  ],
  caption: [Diagrama de clases con estereotipos del modelo de persistencia.],
) <fig-persistencia>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Elemento], [Descripción]),
    [`scenarios/<nombre>/`], [Insumos de un escenario (hoy solo `default`). El TSV de viajes internos (2.580 filas) es el producto de los cuadernos de exploración, ya filtrado a viajes con origen y destino en Usaquén y con las zonas ZAT mapeadas a TAZ. La red 3D y las zonas también se generan fuera del servicio y se copian aquí.],
    [`runs/<id>/`], [Una corrida lanzada desde la API: sus archivos intermedios (viajes, rutas, `.sumocfg`) y su `estado.json` (@sec-persistencia-corrida). Cada corrida tiene sus propias salidas en `output/` y se crea a partir de la plantilla del escenario, de modo que varias corridas no se pisan.],
    [`runs/<id>/output/`], [Salidas de SUMO (FCD, `vehroute`, estadísticas) y la exportación para kepler. El FCD se borra tras exportar. `volumenes.json` es la caché de volúmenes por _edge_ de esa corrida.],
    [`precalculadas/<preset>/`], [Un preset ya simulado y versionado: lo único que necesita el visor (@sec-persistencia-meta).],
    [`runs/sem-<id>/`], [Una comparación 3D: la red recortada sin y con el semáforo propuesto, la demanda compartida y el parche de nodos. Se borra al cerrar la comparación.],
    [`cache/`], [Caché del análisis de red independiente de la corrida: catálogo de semáforos y análisis de priorización.],
    [`data/processed/`], [Evidencia descargada una sola vez (siniestros SDM, POI y edificios OSM/Microsoft) y artefactos de red de los cuadernos.],
  ),
  caption: [Elementos del modelo de persistencia.],
)

*Asociaciones.* Un escenario da origen a muchas corridas (1..\*); cada corrida contiene exactamente un directorio de salidas (composición). Una comparación 3D puede tomar rutas reales de una corrida (0..1). Una precalculada se genera a partir de las salidas de una corrida del escenario. Las cachés se derivan de la red del escenario, de los volúmenes de una corrida y de la evidencia de `data/processed/`.

=== Diccionario de datos

==== Viaje de la encuesta (TSV de entrada)

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Campo], [Tipo], [Descripción y restricciones]),
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

Las filas inválidas, fuera de ventana o con modo desconocido no se descartan en silencio: se cuentan en `TripGenerationStats` y se reportan en el resumen de la corrida.

==== Estado de una corrida (`runs/<id>/estado.json`) <sec-persistencia-corrida>

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Campo], [Tipo], [Descripción]),
    [`id`], [texto], [`AAAAMMDD-HHMMSS-<6 hex>`; clave primaria de la corrida y nombre del directorio.],
    [`preset`], [texto], [Uno de `encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`.],
    [`conteos`], [mapa modo → entero], [Viajes pedidos por modo; la suma debe estar entre 1 y 100.000.],
    [`semilla`], [entero o nulo], [Semilla de SUMO; nulo = la del `.sumocfg`.],
    [`estilo`], [texto], [`agresivo`, `normal` o `cauteloso`.],
    [`cierres`], [lista], [Cierres viales: `edge_id`, `hora_inicio_s`, `hora_fin_s`.],
    [`estado`], [texto], [Ver @fig-estados-corrida.],
    [`avance`], [real 0--1], [Avance global (según `FRANJAS_ETAPA`).],
    [`avance_etapa`], [real o nulo], [Avance dentro de la etapa; nulo si no se puede medir.],
    [`creada`, `iniciada`, `actualizada`], [ISO 8601], [Marcas de tiempo.],
    [`error`], [texto o nulo], [Mensaje si falló.],
    [`resultado`], [objeto o nulo], [`viajes_generados`, `viajes_por_modo`, `trips_kepler` y las estadísticas de SUMO (`vehiculos_insertados`, `teleports`, `colisiones`, ...).],
  ),
  caption: [Campos de `estado.json` (dataclass `Corrida`).],
)

==== Trips para kepler (GeoJSON de `LineString`)

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Campo], [Tipo], [Descripción]),
    [`properties.id`], [texto], [Id del vehículo o persona. Para personas, el prefijo (`peaton_N`, `transporte_publico_N`) determina el modo.],
    [`properties.mode`], [texto], [`TransportMode`; el visor le asigna color.],
    [`properties.category`], [texto], [`vehiculo` o `persona`.],
    [`properties.inicio_s`, `fin_s`], [entero], [Segundos de simulación al aparecer y al salir.],
    [`properties.dist_m`, `avg_kmh`], [numérico], [Distancia recorrida y velocidad media.],
    [`geometry.coordinates[i]`], [`[lon, lat, z, t]`], [`z` relativa al mínimo del FCD; `t` = _unix time_ = 2000-01-01 UTC + segundos de simulación (07:00 en pantalla = 25.200 s en SUMO).],
  ),
  caption: [Esquema de cada _feature_ de `kepler.geojson`.],
)

==== Metadatos de una precalculada (`meta.json`) y volúmenes <sec-persistencia-meta>

`meta.json` contiene `preset`, `conteos`, `semilla`, `generada`, `tamano_original`, `tamano_gz`, `resultado` (el mismo resumen de una corrida) e `insumos`: una huella SHA-256 (16 primeros hex) de TSV, red, TAZ y `.sumocfg`, con los saltos de línea normalizados. Sirve para detectar que una precalculada quedó desactualizada respecto a sus insumos.

`volumenes.json` mapea cada `edge` a un contador por modo (por ejemplo `{"-1012541443#0": {"bici": 12}}`). Se obtiene recorriendo `vehroute.xml` y contando la última ruta de cada `routeDistribution`; reemplaza al `vehroute` (~22 MB) en las precalculadas.

==== Cachés de intersecciones

`cache/semaforos.json` guarda el catálogo de `Semaforo` (@sec-clases-analisis) y `cache/priorizacion.json` el análisis de cruces sin semáforo con sus puntajes base. Ambos guardan la firma (mtime y tamaño) de sus insumos (la red y, en `priorizacion.json`, también la evidencia y los nombres de vías) y se descartan si cambia; `priorizacion.json` también si cambia `VERSION_ANALISIS`. El puntaje que depende de los volúmenes de una corrida no se guarda: se recalcula en cada consulta porque es barato.

==== Mensaje de _frame_ del simulador 3D <sec-datos-frame>

Aunque no se persiste, es la estructura de datos más grande que circula en tiempo real. Cada frame del WebSocket es un objeto JSON `{tipo: "frame", t, dt, ego, manual, lados: {a: L, b: L}}`, donde cada lado `L` contiene:

- `vehiculos` y `personas`: listas de actores `[id, tipo, x, y, z, ángulo, velocidad, edge]` en coordenadas de la red.
- `luces`: `{estado, fase, restante}` del semáforo (nulo en el lado A, que no tiene).
- `metricas`: `vehiculos`, `peatones`, `en_cruce`, `detenidos_cruce`, `velocidad_media_cruce_kmh`, `espera_media_cruce_s`, `espera_lateral_s`, `colisiones`, `conflictos`, `riesgo_max`.
- `ego`: telemetría del actor seguido (velocidad, aceleración, líder, riesgo `TTC/DRAC/PET`, acción, decisiones posibles en el próximo cruce).

=== Estrategia de almacenamiento <sec-almacenamiento-ref>

#figure(
  table(
    columns: (auto, auto, 1fr),
    table.header([Ubicación], [Versionada], [Contenido y política]),
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
