# Generación de escenarios de movilidad urbana para la toma de decisiones en localidades de Bogotá

Simulación microscópica de movilidad urbana para las localidades de Bogotá, desarrollada como proyecto de grado en Ingeniería de Sistemas de la Pontificia Universidad Javeriana.

El proyecto toma los viajes de la **Encuesta de Movilidad de Bogotá 2023** dentro de Usaquén y los convierte, con un pipeline ETL, en la demanda de una simulación en **SUMO (Simulation of Urban MObility)**. Un visor web (kepler.gl) anima el resultado y deja parametrizar nuevas simulaciones: cuántos actores viales de cada tipo y qué escenario. Los aforos vehiculares HMD de la EODI sirven para validar los volúmenes simulados con el GEH (ver "Validación con aforos").

## Equipo

| Integrantes |
|---|
| Samuel Esteban Campos |
| Erick Salazar Suárez |
| Santiago Chitiva Contreras |
| Felipe Andrés Garrido Flores |

**Director:** Ing. Andrés Oswaldo Calderón Romero

## Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| `simulation-service/` | El ETL (encuesta → viajes → rutas → SUMO → GeoJSON) y la API (FastAPI). Ver su [README](simulation-service/README.md). |
| `kepler/` | Visor web (Vite + React + kepler.gl) con el panel para parametrizar la demanda. |
| `notebooks/` | Exploración y limpieza de datos (encuesta, aforos HMD, red OSM, netconvert, altura). |
| `data/processed/` | Artefactos que producen los notebooks: red SUMO 2D y 3D, OSM, TAZ, archivos de netconvert. |
| `data/raw/` | Datos originales (Google Drive, no versionados). |
| `docs/` | SPMP, SRS, informes y la [propuesta de semaforización y vista 3D](docs/propuesta-semaforizacion-3d.md). |
| `tests/` | Prueba de humo del entorno que corre en CI. |

## Actores viales simulados

La simulación cubre la ventana **07:00–10:00** sobre la red de Usaquén **con elevación** (`usaquen_3d.net.xml`). Cada viaje de la encuesta conserva su zona de origen, su zona de destino (ZAT) y su hora de salida. Se replica según su factor de expansión (`fexp_vj`), con un tope de 50 copias por viaje.

| Modo (encuesta) | En SUMO | Cómo se modela |
|---|---|---|
| Auto | vehículo `auto` | vClass `passenger`, ruta calculada por duarouter entre TAZ |
| Moto | vehículo `moto` | vClass `motorcycle` |
| Taxi ocupado | vehículo `taxi` | vClass `taxi` |
| Especial ocupado | vehículo `especial` | vClass `passenger` |
| Transporte escolar | vehículo `escolar` | vClass `bus` (sin paradas) |
| Informal / Otro | vehículo `informal` / `otro` | vClass `passenger` |
| Bicicleta | vehículo `bici` | vClass `bicycle`, usa los carriles que la red permite a bicicletas |
| A pie (< 15 min y > 15 min) | persona `peaton` | `<person><walk>` con el modelo peatonal *striping* |
| Transporte público | persona `transporte_publico` | `<personTrip modes="public">`: camina a una parada, toma un bus del SITP (GTFS) y camina a su destino (ver abajo) |

Con la demanda de la encuesta, SUMO carga 10.324 vehículos (bicis incluidas) e inserta 9.557. Las 14.123 personas se insertan todas.

### Transporte público: buses del SITP desde el GTFS

Los buses salen del GTFS de SIMUR (`GTFS-2026-04-29.zip`, catálogo de Mobility Database), que se descarga a `data/raw/gtfs/` y se convierte una vez con `python -m etl.sumo.transporte_publico data/raw/gtfs/GTFS-2026-04-29.zip`:

1. Se reduce a los viajes de un día hábil con al menos dos paradas en Usaquén, sin TransMilenio troncal ni TransMiCable (van por carriles exclusivos y los aforos de transporte público tampoco los cuentan).
2. Cada parada se ubica en el carril con buses más cercano, y duarouter rutea cada viaje pasando por sus paradas. `gtfs2pt.py` de SUMO hace lo mismo con map matching, pero con esta red tardó más de tres horas sin terminar (queda como opción, `--gtfs2pt`).
3. Quedan versionados `pt_paradas.add.xml` (696 paradas) y `pt_vehiculos.rou.xml.gz` (7.382 buses de 9.234 viajes del día; los demás cruzan tramos sin conexión para buses en la red).

Los viajes `transporte_publico` de la encuesta pasan a `<personTrip modes="public">`. En la corrida de la mañana, 3.967 de 4.556 se hacen en bus, con unos 10 minutos de espera media en la parada. Sigue siendo una aproximación: los buses arrancan en el borde de Usaquén y no hay TransMilenio troncal.

### Validación con aforos (GEH)

Cada corrida cuenta los vehículos por modo en los 33 puntos de aforo HMD que caen en la red (`data/processed/aforos_usaquen.json`, de `python -m etl.sumo.aforos`) y escribe `output/validacion.csv` y `validacion.json`. Ahí se compara la hora pico simulada con la aforada; el criterio es GEH < 5 en el 85 % de los puntos. Las estaciones se dividen en dos grupos fijos, calibración y control, para que el tráfico de paso (que se ajusta a las primeras) no se valide contra sí mismo.

Resultados medidos en la mañana:

| Demanda | Vehículos que entran a la red | Volumen simulado / aforado | Puntos con GEH < 5 |
| --- | --- | --- | --- |
| Solo viajes internos de la encuesta (tope de 50 copias) | 9.592 | 6 % | 0 de 33 |
| + tráfico de paso calibrado (`trafico_paso.py`) | — | 27 % | 2 de 33 |
| Encuesta completa (`encuesta_completa.py`), mesoscópico | 54.984 de 145.014 | 22 % | 2 de 33 |
| Encuesta completa con rutas de duaIterate (2 iteraciones) | 54.944 de 145.014 | 22 % | 2 de 33 |
| Encuesta completa sin control de cruces (diagnóstico) | 66.678 de 145.014 | 33 % | 2 de 33 |

La **encuesta completa** (`python -m etl.sumo.encuesta_completa "<carpeta 2.PublicacionSIMUR>"`) agrega lo que la demanda interna deja por fuera: los vehículos que entran o salen de Usaquén (unos 61.500 autos en la mañana frente a 21.800 internos) y las copias que quita el tope (la mediana del factor de expansión es 123). Con eso la demanda ya alcanza el orden de magnitud de los aforos, pero la red no la mueve. La mayoría de los vehículos no alcanza a entrar en 15 minutos, y a las 10:00 quedan más de 20.000 atrapados adentro. Repartir las rutas con duaIterate no cambia el resultado y quitar el control de los cruces solo sube el volumen al 33 %. El cuello de botella es la capacidad de la red en su conjunto, no la demanda ni la elección de rutas. A eso se suma que algunos aforos, como el de la Autopista Norte con Calle 116, cubren la calzada principal y las laterales, mientras que en la red quedan en edges separados.

Lo que falta para cumplir el criterio es calibrar la red, no generar más demanda: revisar carriles y conexiones de las avenidas, cargar los planes reales de los semáforos (la SDM publica dónde están y cuántas fases tienen, no sus tiempos) y sumar los aforos de calzadas paralelas.

### Otros límites conocidos

- Las TAZ `19` y `1012` aparecen en la encuesta pero no en `usaquen.taz.xml`. duarouter descarta esos ~200 viajes.
- El `.sumocfg` limita a 5.000 vehículos circulando a la vez (`max-num-vehicles`). Si se pide mucha demanda, el resto espera para entrar.
- El FCD se escribe cada 2 s y los trips para kepler se reducen a un punto cada 8 s, para que el visor cargue la demanda completa.

## Escenarios de demanda

El visor ofrece cuatro presets. Al elegir uno se cargan sus conteos por modo y después se pueden editar a mano antes de ejecutar.

La encuesta **nunca** muestra más vehículos que peatones en ninguna hora con muestra suficiente: el máximo es 36 % de vehículos a las 17 h. Por eso los tres escenarios nuevos son contrafactuales. Se construyen con una **transferencia modal** que reparte los viajes según P(modo | duración del viaje), calculada con la misma encuesta (todo el día, ponderada por `fexp_vj`). El único supuesto de cada preset es qué viajes pueden cambiar de modo. Cada viaje transferido conserva su origen, destino y hora, y el total de viajes no cambia.

| Preset | Qué viajes cambian de modo | Vehículos motorizados | Peatones + TP | Bicis |
|---|---|---:|---:|---:|
| Encuesta | ninguno | 8.562 | 14.273 | 1.812 |
| Más vehículos | a pie de más de 15 min → modos motorizados | 13.451 | 9.384 | 1.812 |
| Más peatones | auto, moto, informal u otro de hasta 30 min → a pie o bici | 4.260 | 18.135 | 2.252 |
| Día sin carro | todos los de auto, moto, informal y otro → a pie, bici, TP, taxi, especial o escolar | 2.902 | 19.407 | 2.338 |

En Día sin carro siguen circulando taxis, servicio especial y transporte escolar, como en el "día sin carro y sin moto" de Bogotá.

Cuando el usuario cambia un conteo, ese número de viajes se reparte entre los viajes de la encuesta de ese modo, en proporción a su peso, con el método del mayor resto. Es determinista. Si el preset no tiene viajes de un modo (por ejemplo, autos en Día sin carro), se usan los de la encuesta. La lógica está en `simulation-service/src/etl/sumo/demanda.py`.

## Instalación y uso

**Simulación y API** (Python ≥ 3.11 y SUMO 1.27; detalles en el [README del servicio](simulation-service/README.md)):

```bash
cd simulation-service
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
cd src
python -m etl.etl               # corrida por defecto (encuesta), 10–15 min
uvicorn api.api:app             # API en http://localhost:8000
```

En Windows, `eclipse-sumo` trae rutas de más de 260 caracteres. Si `pip install` falla, habilita las rutas largas de Windows o instala SUMO aparte y usa `pip install --no-deps -e .` más `fastapi[standard]==0.136.3 traci==1.27.1 pyproj==3.8.0 pytest`.

**Visor** (Node 20+):

```bash
cd kepler
cp .env.example .env            # poner VITE_MAPBOX_TOKEN
npm install
npm run dev                     # http://localhost:5173
```

En el visor:

- **Pestaña "Demanda"** (panel derecho): se elige el escenario, se ajustan los viajes por actor vial (con los botones −/+ o escribiendo el número), se aplica una escala global y se ejecuta la simulación. Las corridas anteriores quedan en el selector "Corridas".
- **Tarjeta de actividad** (esquina inferior derecha): muestra la simulación en curso con una barra de progreso real por etapa, el tiempo transcurrido y una estimación del restante. Desde ahí se puede **cancelar**. Al terminar, la corrida se carga sola en el mapa, con su propia barra de descarga, que también se puede cancelar.
- **Leyenda** (arriba al centro): el color de cada actor vial de la corrida cargada y el botón **Semáforos**, que muestra las 220 intersecciones semaforizadas.
- **Pestaña "Intersección":** al hacer clic en un semáforo del mapa se abre su ficha. Muestra sus calles, sus accesos con el volumen simulado en la corrida cargada y su programa (fases con la luz de cada acceso). Es la fase A del [módulo de semáforos y vista 3D](docs/propuesta-semaforizacion-3d.md).

## Ejecutar pruebas

```bash
cd simulation-service && pytest -v    # pruebas del ETL, la demanda y la API
pytest tests/                          # prueba de humo de la raíz (la que corre en CI)
```

GitHub Actions (`.github/workflows/tests.yml`) corre solo las pruebas de la raíz en cada `push` o `pull request` a `main` y `develop`.

## Metodología

El proyecto sigue un modelo de ciclo de vida híbrido: **CRISP-DM** para las fases de datos (Fase 1-2) y **Scrum** para la construcción del escenario de simulación (Fase 3), documentado en el SPMP (`docs/spmp/`).

## Estándares

IEEE 1058-1998 (SPMP) · IEEE 830-1998 (SRS) · ISO/IEC 12207:2008 · PEP 8
