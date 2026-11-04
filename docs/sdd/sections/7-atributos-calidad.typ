= Atributos de calidad

== Seguridad <sec-seguridad>

El sistema está pensado como *herramienta local de investigación*, no como servicio expuesto a Internet. Por eso el modelo de seguridad es deliberadamente mínimo, y aquí se declara qué se cubre y qué no.

*Medidas presentes:*

- *Validación de entradas en la frontera.* Pydantic valida tipos y rangos: conteos 0--100.000 y total 1--100.000 viajes, semilla ≥ 0, radio de recorte 50--2.000 m, intensidades de fondo 0--3.000 por hora, factor de velocidad acotado a 0,25--20 y periodo de riesgo a 0,4--30 s. Los valores enumerados (`Preset`, `TransportMode`, `EstiloConductor`) rechazan cualquier otro texto.
- *Sin ejecución de comandos arbitrarios.* Los subprocesos se lanzan con una lista de argumentos (sin _shell_) y los parámetros que llegan del cliente nunca forman parte de la línea de comandos sin pasar por un tipo validado; los ids de nodo que llegan del cliente se escapan antes de escribirse en el XML del parche de semáforo y solo se usan si existen en la red recortada.
- *Recursos acotados.* Un trabajador para las corridas, máximo dos comparaciones 3D, una sola ventana por comparación y expiración por inactividad evitan que un cliente agote la máquina.
- *Secretos fuera del código.* El token de Mapbox se lee de `kepler/.env` (ignorado por Git; la plantilla es `.env.example`).
- *Manejo de errores.* Una corrida fallida no tumba el servicio: se registra el error (últimos 2.000 caracteres) en su `estado.json`.

*Limitaciones aceptadas (fuera de alcance de la versión actual):*

- *No hay autenticación ni autorización*, no hay roles ni cifrado en tránsito (HTTP local) y no se configura CORS: el visor accede por el proxy de Vite del mismo origen. Si el servicio se publicara, habría que añadir autenticación (p. ej. OAuth 2.0/JWT), TLS y limitación de tasa.
- Algunas rutas (`/escenarios/{run_id}`) leen `runs/<run_id>/estado.json` directamente a partir del identificador recibido; conviene validar el formato del id (`[0-9A-Za-z-]+`) antes de exponer el servicio fuera de la máquina local.
- Los datos son abiertos o agregados (encuesta expandida, siniestros públicos): no contienen información personal identificable.

== Rendimiento y escalabilidad

*Tiempos medidos de referencia.* Una corrida completa de la encuesta (~24.600 viajes) tarda unos 12 min: generación de demanda y `duarouter` ≈ 1,5 min, SUMO ≈ 8 min y exportación ≈ 2 min. De ahí salen las franjas de avance (`FRANJAS_ETAPA`). La comparación 3D tarda en preparar la zona decenas de segundos, más 240 s simulados de calentamiento al conectarse.

#figure(
  table(
    columns: (1fr, 2fr),
    [Problema], [Estrategia],
    [SUMO es lento], [Presets precalculados y versionados: abrir el visor muestra una simulación completa sin esperar. Corridas nuevas en segundo plano con cancelación.],
    [Salida enorme (FCD ~1,4 GB)], [`device.fcd.period=2`, sin `emission-output`, lectura en streaming con `iterparse`, borrado del FCD tras exportar.],
    [GeoJSON de ~64 MB en el navegador], [Reducción de puntos por tiempo y rumbo, descarte de entidades casi inmóviles, compresión gzip (11,7 MB) servida sin recomprimir, barra de progreso.],
    [Análisis de red costoso], [Cachés en disco (`semaforos.json`, `priorizacion.json`, `volumenes.json`) invalidadas por mtime y tamaño; las consultas dependientes de la corrida son baratas.],
    [3D en tiempo real], [Paso de 0,2 s, cola de frames de tamaño 8 con descarte del más antiguo, ritmo de tiempo real con factor de velocidad, mallas fusionadas por material, interpolación entre frames y carga diferida de three.js.],
    [Concurrencia], [Un `ThreadPoolExecutor(1)` para corridas; hasta 2 comparaciones 3D (cada una son 2 procesos SUMO).],
  ),
  caption: [Estrategias de rendimiento.],
)

*Escalabilidad.* El diseño escala en *volumen de demanda* (hasta 100.000 viajes por corrida) y en *número de escenarios* (cada uno en `scenarios/<nombre>/`), pero no en *número de usuarios simultáneos*: la cola de un solo trabajador y el estado en memoria y disco local suponen una instancia. Para soportar varios usuarios habría que mover el estado de las corridas a una base de datos o cola externa y ejecutar trabajadores en procesos distintos (@sec-adrs, ADR-02).

*Recuperación (_failover_).* No hay alta disponibilidad. Lo que sí existe es recuperación ante reinicio: el historial se reconstruye desde `runs/*/estado.json` y las corridas que estaban activas se marcan como `error` («Interrumpida: el servicio se reinició»). Las comparaciones 3D, en cambio, son efímeras y se pierden.

== Mantenibilidad y pruebas

- *Pruebas automáticas:* 103 pruebas con `pytest` en `simulation-service/test/` (demanda y presets, viajes, FCD, kepler, intersecciones, priorización, progreso y cancelación, semáforo nuevo, escena 3D, telemetría, precalculadas, API y comparación 3D). Las dependencias externas se aíslan con `dependency_overrides` y datos mínimos, sin ejecutar SUMO completo.
- *Riesgo conocido:* el flujo de CI (`.github/workflows/tests.yml`) instala solo el `requirements.txt` de la raíz y corre `tests/`, que es un marcador. *Las pruebas de `simulation-service/` no se ejecutan en CI*; deben correrse a mano (`pytest -v` dentro de `simulation-service/`). El visor no tiene pruebas automáticas.
- *Convenciones:* PEP 8, nombres y comentarios en español, patrón `Config/Result/Stats` uniforme, y una sola fuente de verdad para rutas (`configuration.py`).
- *Sincronización con el SRS:* cada requisito tiene un estado (Implementado/Parcial/Pendiente) que debe actualizarse al construir la funcionalidad.

== Reproducibilidad y portabilidad

- Versiones fijadas (`eclipse-sumo==1.27.1`, `traci==1.27.1`, `fastapi==0.136.3`, `pyproj==3.8.0`), semilla configurable, ordenamiento determinista de viajes y huella de insumos en las precalculadas.
- El mismo código corre en Linux y Windows. Se contempla el bloqueo de archivos de Windows al borrar el directorio de una comparación (hasta 5 reintentos en un hilo aparte) y se normalizan los saltos de línea al calcular la huella de insumos.

== Observabilidad y usabilidad

- *Observabilidad:* estado y avance de cada corrida consultables por la API; el _stderr_ de SUMO se anexa al error de una corrida o comparación fallida; las estadísticas (`teleports`, colisiones, viajes descartados) se incluyen en el resultado.
- *Honestidad del modelo:* la API acompaña los datos con notas cuando una limitación afecta su lectura (programa de OSM, ausencia de volúmenes, falta de datos de siniestros).
- *Usabilidad:* progreso visible, cancelación, valores por defecto coherentes con la encuesta, mensajes de error en español y un visor en una sola pantalla.
