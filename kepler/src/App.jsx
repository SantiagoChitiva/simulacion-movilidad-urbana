import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createStore, combineReducers, applyMiddleware } from 'redux';
import { Provider, useDispatch, useSelector } from 'react-redux';
import { taskMiddleware } from 'react-palm/tasks';
import keplerGlReducer from '@kepler.gl/reducers';
import {
  addDataToMap,
  onLayerHover,
  onMapClick,
  removeDataset,
  reorderLayer,
  toggleModal,
} from '@kepler.gl/actions';
import { processGeojson, processRowObject } from '@kepler.gl/processors';
import KeplerGl from '@kepler.gl/components';
import { descargarJson, obtenerIntersecciones, obtenerModos, urlTrips } from './api';
import { useCorridas, useTamanoVentana } from './hooks';
import { COLOR_SEMAFORO, hexARgb, modeColorRange, modosPresentes } from './modos';
import FichaInterseccion from './components/FichaInterseccion';
import LeyendaModos from './components/LeyendaModos';
import LimiteError from './components/LimiteError';
import PanelDemanda from './components/PanelDemanda';
import TarjetaActividad from './components/TarjetaActividad';

const reducers = combineReducers({
  keplerGl: keplerGlReducer,
});

const store = createStore(reducers, {}, applyMiddleware(taskMiddleware));

const MAPA_ID = 'map';
const DATASET_TRIPS = 'usaquen_trips';
const DATASET_SEMAFOROS = 'intersecciones';
const CAPA_TRIPS = 'trips_layer';
const CAPA_SEMAFOROS = 'semaforos_layer';

const VISTA_INICIAL = { latitude: 4.7345, longitude: -74.0395, zoom: 12.4, pitch: 45, bearing: 0 };

const configTrips = (colors, conVista) => ({
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: CAPA_TRIPS,
          type: 'trip',
          config: {
            dataId: DATASET_TRIPS,
            label: 'Trips SUMO',
            columns: { geojson: '_geojson' },
            isVisible: true,
            visConfig: {
              opacity: 0.9,
              thickness: 3,
              trailLength: 60,
              fadeTrail: true,
              colorRange: { name: 'modos', type: 'qualitative', category: 'Custom', colors },
            },
          },
          visualChannels: {
            colorField: { name: 'mode', type: 'string' },
            colorScale: 'ordinal',
            sizeField: null,
            sizeScale: 'linear',
          },
        },
      ],
      animationConfig: { currentTime: null, speed: 1 },
    },
    ...(conVista ? { mapState: VISTA_INICIAL } : {}),
  },
});

const configSemaforos = {
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: CAPA_SEMAFOROS,
          type: 'point',
          config: {
            dataId: DATASET_SEMAFOROS,
            label: 'Semáforos',
            columns: { lat: 'lat', lng: 'lng', altitude: null },
            isVisible: true,
            color: hexARgb(COLOR_SEMAFORO),
            visConfig: { radius: 22, opacity: 0.95, filled: true, outline: true, thickness: 2, strokeColor: [16, 24, 32] },
          },
          visualChannels: { colorField: null, sizeField: null },
        },
      ],
      interactionConfig: {
        tooltip: {
          enabled: true,
          fieldsToShow: {
            [DATASET_SEMAFOROS]: [
              { name: 'nombre', format: null },
              { name: 'volumen', format: null },
              { name: 'ciclo_s', format: null },
            ],
          },
        },
      },
    },
  },
};

const tickDePintado = () => new Promise((r) => setTimeout(r, 30)); // deja que React pinte antes de bloquear

function Visor() {
  const dispatch = useDispatch();
  const { ancho, alto } = useTamanoVentana();
  const [modos, setModos] = useState([]);
  const [corridaMapa, setCorridaMapa] = useState(null); // null = corrida por defecto
  const [presentes, setPresentes] = useState([]);
  const [carga, setCarga] = useState(null);
  const [errorCarga, setErrorCarga] = useState(null);
  const [plegado, setPlegado] = useState(false);
  const [pestana, setPestana] = useState('demanda');
  const [semaforosVisibles, setSemaforosVisibles] = useState(false);
  const [interseccion, setInterseccion] = useState(null);
  const [versionMapa, setVersionMapa] = useState(0);
  const abortar = useRef(null);
  const primeraCarga = useRef(true);
  const filasSemaforos = useRef([]);

  // Kepler conserva el objeto bajo el mouse y el tooltip fijado; si se reemplaza el
  // dataset sin limpiarlos, intenta dibujar un trip que ya no existe y se cae.
  const limpiarInteraccion = useCallback(() => {
    dispatch(onLayerHover(null));
    dispatch(onMapClick());
  }, [dispatch]);

  // ---------------------------------------------------------------- trips

  const cargarCorrida = useCallback(
    async (corrida) => {
      abortar.current?.abort();
      const controlador = new AbortController();
      abortar.current = controlador;
      const etiqueta = corrida ? `Corrida ${new Date(corrida.creada).toLocaleString('es-CO')}` : 'Corrida por defecto';
      setErrorCarga(null);
      setCarga({ etapa: 'descargando', avance: 0, mb: 0, etiqueta });
      try {
        const geojson = await descargarJson(urlTrips(corrida?.id), {
          signal: controlador.signal,
          onProgreso: (avance, bytes) => setCarga({ etapa: 'descargando', avance, mb: bytes / 1e6, etiqueta }),
        });
        setCarga({ etapa: 'dibujando', avance: null, etiqueta });
        await tickDePintado();
        if (controlador.signal.aborted) return;

        const modosCorrida = modosPresentes(geojson);
        limpiarInteraccion();
        dispatch(removeDataset(DATASET_TRIPS)); // reemplaza la corrida anterior, si había
        dispatch(
          addDataToMap({
            datasets: {
              info: { label: corrida ? `Simulación (${corrida.preset})` : 'Simulación SUMO – Usaquén', id: DATASET_TRIPS },
              data: processGeojson(geojson),
            },
            options: { centerMap: false, readOnly: false, keepExistingConfig: true },
            config: configTrips(modeColorRange(modosCorrida), primeraCarga.current),
          })
        );
        primeraCarga.current = false;
        if (filasSemaforos.current.length) dispatch(reorderLayer([CAPA_SEMAFOROS, CAPA_TRIPS]));
        setPresentes(modosCorrida);
        setCorridaMapa(corrida);
        setCarga(null);
      } catch (e) {
        setCarga(null);
        if (e.name !== 'AbortError') setErrorCarga(e.message); // cancelar deja la corrida anterior
      }
    },
    [dispatch, limpiarInteraccion]
  );

  const cancelarCarga = useCallback(() => abortar.current?.abort(), []);

  const corridas = useCorridas(cargarCorrida); // al terminar una simulación se carga sola

  useEffect(() => {
    // kepler abre "Add Data To Map" mientras no hay datos y taparía la tarjeta de carga
    dispatch(toggleModal(null));
    obtenerModos().then(setModos).catch(() => {});
    cargarCorrida(null);
  }, [cargarCorrida, dispatch]);

  // ----------------------------------------------------------- semáforos

  useEffect(() => {
    if (!semaforosVisibles) {
      filasSemaforos.current = [];
      limpiarInteraccion();
      dispatch(removeDataset(DATASET_SEMAFOROS));
      return undefined;
    }
    let cancelado = false;
    obtenerIntersecciones(corridaMapa?.id)
      .then((fc) => {
        if (cancelado) return;
        const filas = fc.features.map((f) => ({
          id: f.properties.id,
          nombre: f.properties.nombre,
          accesos: f.properties.accesos,
          fases: f.properties.fases,
          ciclo_s: f.properties.ciclo_s,
          volumen: f.properties.volumen,
          lng: f.geometry.coordinates[0],
          lat: f.geometry.coordinates[1],
        }));
        filasSemaforos.current = filas;
        limpiarInteraccion();
        dispatch(removeDataset(DATASET_SEMAFOROS));
        dispatch(
          addDataToMap({
            datasets: { info: { label: 'Semáforos', id: DATASET_SEMAFOROS }, data: processRowObject(filas) },
            options: { centerMap: false, keepExistingConfig: true },
            config: configSemaforos,
          })
        );
      })
      .catch((e) => !cancelado && setErrorCarga(`Semáforos: ${e.message}`));
    return () => {
      cancelado = true;
    };
  }, [semaforosVisibles, corridaMapa?.id, dispatch, limpiarInteraccion]);

  // clic sobre un semáforo → ficha (kepler guarda el objeto clicado en visState.clicked)
  const clicado = useSelector((s) => s.keplerGl?.[MAPA_ID]?.visState?.clicked);
  useEffect(() => {
    if (!clicado?.layer?.id?.startsWith(CAPA_SEMAFOROS)) return;
    const fila = filasSemaforos.current[clicado.object?.index ?? clicado.index];
    if (fila) {
      setInterseccion(fila.id);
      setPestana('interseccion');
      setPlegado(false);
    }
  }, [clicado]);

  const etiquetas = Object.fromEntries(modos.map((m) => [m.id, m.etiqueta]));
  const etiquetaCorrida = corridaMapa
    ? `la corrida del ${new Date(corridaMapa.creada).toLocaleString('es-CO')}`
    : 'la corrida por defecto';

  return (
    <>
      <LimiteError
        onReintentar={() => {
          limpiarInteraccion();
          setVersionMapa((v) => v + 1);
        }}
      >
        <KeplerGl
          key={versionMapa}
          id={MAPA_ID}
          mapboxApiAccessToken={import.meta.env.VITE_MAPBOX_TOKEN}
          width={ancho}
          height={alto}
        />
      </LimiteError>

      <LeyendaModos
        presentes={presentes}
        etiquetas={etiquetas}
        semaforosVisibles={semaforosVisibles}
        onAlternarSemaforos={() => setSemaforosVisibles((v) => !v)}
      />

      <div className="columna-derecha">
        {plegado ? (
          <button type="button" className="cd-abrir" onClick={() => setPlegado(false)}>
            Panel
          </button>
        ) : (
          <aside className="pd-panel" aria-label="Panel de la simulación">
            <header className="pd-encabezado">
              <div className="cd-pestanas" role="tablist">
                <button type="button" role="tab" aria-selected={pestana === 'demanda'} className={pestana === 'demanda' ? 'activa' : ''} onClick={() => setPestana('demanda')}>
                  Demanda
                </button>
                <button type="button" role="tab" aria-selected={pestana === 'interseccion'} className={pestana === 'interseccion' ? 'activa' : ''} onClick={() => setPestana('interseccion')}>
                  Intersección
                </button>
              </div>
              <button type="button" className="pd-cerrar" onClick={() => setPlegado(true)} aria-label="Plegar panel">
                ›
              </button>
            </header>
            {pestana === 'demanda' ? (
              <PanelDemanda
                modos={modos}
                historial={corridas.historial}
                corridaCargada={corridaMapa?.id}
                enCurso={corridas.enCurso}
                error={corridas.error}
                onEjecutar={corridas.lanzar}
                onVerCorrida={cargarCorrida}
              />
            ) : (
              <FichaInterseccion id={interseccion} runId={corridaMapa?.id} etiquetaCorrida={etiquetaCorrida} />
            )}
          </aside>
        )}

        <TarjetaActividad
          corrida={corridas.activa}
          carga={carga}
          errorCarga={errorCarga}
          onCancelarCorrida={corridas.cancelar}
          onDescartarCorrida={corridas.descartar}
          onCancelarCarga={cancelarCarga}
          onDescartarError={() => setErrorCarga(null)}
        />
      </div>
    </>
  );
}

export default function App() {
  return (
    <Provider store={store}>
      <Visor />
    </Provider>
  );
}
