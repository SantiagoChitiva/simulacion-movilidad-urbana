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
import { descargarJson, listarPrecalculadas, obtenerIntersecciones, obtenerModos, obtenerPriorizacion, urlTrips } from './api';
import { useCorridas, useTamanoVentana } from './hooks';
import { COLOR_SEMAFORO, hexARgb, modeColorRange, modosPresentes } from './modos';
import FichaInterseccion from './components/FichaInterseccion';
import LeyendaModos from './components/LeyendaModos';
import LimiteError from './components/LimiteError';
import PanelCierres from './components/PanelCierres';
import PanelDemanda from './components/PanelDemanda';
import TarjetaActividad from './components/TarjetaActividad';
import Vista3D from './components/Vista3D';

const reducers = combineReducers({
  keplerGl: keplerGlReducer,
});

const store = createStore(reducers, {}, applyMiddleware(taskMiddleware));

const MAPA_ID = 'map';
const DATASET_TRIPS = 'usaquen_trips';
const DATASET_SEMAFOROS = 'intersecciones';
const DATASET_PRIORIZACION = 'priorizacion';
const CAPA_TRIPS = 'trips_layer';
const CAPA_SEMAFOROS = 'semaforos_layer';
const CAPA_PRIORIZACION = 'priorizacion_layer';

// Colores por nivel de priorización
const COLORES_NIVEL = {
  prioritario: [244, 67, 54],     // rojo
  recomendado: [255, 152, 0],     // naranja
  observacion: [255, 235, 59],    // amarillo
  sin_accion: [144, 164, 174],    // gris
};

const configPriorizacion = {
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: CAPA_PRIORIZACION,
          type: 'point',
          config: {
            dataId: DATASET_PRIORIZACION,
            label: 'Priorización',
            columns: { lat: 'lat', lng: 'lng', altitude: null },
            isVisible: true,
            visConfig: { radius: 18, opacity: 0.85, filled: true },
          },
          visualChannels: {
            colorField: { name: 'nivel', type: 'string' },
            colorScale: 'ordinal',
          },
        },
      ],
    },
  },
};

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

const fecha = (iso) => new Date(iso).toLocaleString('es-CO');
const numero = (n) => n.toLocaleString('es-CO');

/** Cómo se nombra una corrida en la interfaz (null = la corrida por defecto del pipeline). */
const nombreCorrida = (corrida) => {
  if (!corrida) return 'Corrida por defecto';
  if (corrida.precalculada) return `${corrida.nombre} (precalculada)`;
  return `Corrida ${fecha(corrida.creada)}`;
};

/** Mensaje que confirma qué simulación quedó en el mapa. */
const avisoDeCarga = (corrida, nueva) => {
  const viajes = corrida?.resultado?.viajes_generados;
  const detalle = [];
  if (corrida?.precalculada) detalle.push(corrida.nombre, 'precalculada');
  else if (corrida) detalle.push(fecha(corrida.creada));
  else detalle.push('Corrida por defecto del pipeline');
  if (viajes != null) detalle.push(`${numero(viajes)} viajes`);
  return {
    titulo: nueva ? 'Simulación nueva cargada en el mapa' : 'Simulación cargada en el mapa',
    detalle: detalle.join(' · '),
    clave: Date.now(), // reinicia el temporizador aunque el texto se repita
  };
};

function Visor() {
  const dispatch = useDispatch();
  const { ancho, alto } = useTamanoVentana();
  const [modos, setModos] = useState([]);
  const [corridaMapa, setCorridaMapa] = useState(null); // null = corrida por defecto
  const [precalculadas, setPrecalculadas] = useState([]);
  const [aviso, setAviso] = useState(null);
  const [presentes, setPresentes] = useState([]);
  const [carga, setCarga] = useState(null);
  const [errorCarga, setErrorCarga] = useState(null);
  const [plegado, setPlegado] = useState(false);
  const [pestana, setPestana] = useState('demanda');
  const [semaforosVisibles, setSemaforosVisibles] = useState(false);
  const [priorizacionVisible, setPriorizacionVisible] = useState(false);
  const [interseccion, setInterseccion] = useState(null);
  const [versionMapa, setVersionMapa] = useState(0);
  const [sesion3d, setSesion3d] = useState(null);   // { id: tl_id, corrida }
  const [cierres, setCierres] = useState([]);
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
    async (corrida, { nueva = false } = {}) => {
      abortar.current?.abort();
      const controlador = new AbortController();
      abortar.current = controlador;
      const etiqueta = nombreCorrida(corrida);
      setErrorCarga(null);
      setAviso(null);
      setCarga({ etapa: 'descargando', avance: 0, mb: 0, etiqueta });
      try {
        const geojson = await descargarJson(urlTrips(corrida), {
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
              info: { label: corrida ? `Simulación – ${corrida.nombre ?? corrida.preset}` : 'Simulación SUMO – Usaquén', id: DATASET_TRIPS },
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
        setAviso(avisoDeCarga(corrida, nueva));
      } catch (e) {
        setCarga(null);
        if (e.name !== 'AbortError') setErrorCarga(e.message); // cancelar deja la corrida anterior
      }
    },
    [dispatch, limpiarInteraccion]
  );

  const cancelarCarga = useCallback(() => abortar.current?.abort(), []);
  const descartarAviso = useCallback(() => setAviso(null), []);

  // al terminar una simulación se carga sola
  const corridas = useCorridas((corrida) => cargarCorrida(corrida, { nueva: true }));

  useEffect(() => {
    // kepler abre "Add Data To Map" mientras no hay datos y taparía la tarjeta de carga
    dispatch(toggleModal(null));
    obtenerModos().then(setModos).catch(() => {});
    // al abrir se muestra la Encuesta precalculada; sin ella, la corrida por defecto del pipeline
    listarPrecalculadas()
      .catch(() => [])
      .then((lista) => {
        setPrecalculadas(lista);
        cargarCorrida(lista.find((p) => p.preset === 'encuesta') ?? null);
      });
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
    obtenerIntersecciones(corridaMapa)
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
  }, [semaforosVisibles, corridaMapa, dispatch, limpiarInteraccion]);

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

  // ─── priorización ───────────────────────────────────────────────────────────

  useEffect(() => {
    if (!priorizacionVisible) {
      dispatch(removeDataset(DATASET_PRIORIZACION));
      return undefined;
    }
    let cancelado = false;
    obtenerPriorizacion(corridaMapa)
      .then((fc) => {
        if (cancelado) return;
        const filas = fc.features.map((f) => ({
          id: f.properties.id,
          nivel: f.properties.nivel,
          puntaje_total: f.properties.puntaje_total,
          distancia_semaforo_m: f.properties.distancia_semaforo_m,
          lng: f.geometry.coordinates[0],
          lat: f.geometry.coordinates[1],
        }));
        dispatch(removeDataset(DATASET_PRIORIZACION));
        dispatch(
          addDataToMap({
            datasets: {
              info: { label: 'Priorización de cruces', id: DATASET_PRIORIZACION },
              data: processRowObject(filas),
            },
            options: { centerMap: false, keepExistingConfig: true },
            config: configPriorizacion,
          })
        );
      })
      .catch((e) => !cancelado && setErrorCarga(`Priorización: ${e.message}`));
    return () => {
      cancelado = true;
    };
  }, [priorizacionVisible, corridaMapa, dispatch]);

  const etiquetas = Object.fromEntries(modos.map((m) => [m.id, m.etiqueta]));
  let etiquetaCorrida = 'la corrida por defecto';
  if (corridaMapa?.precalculada) etiquetaCorrida = `la simulación precalculada "${corridaMapa.nombre}"`;
  else if (corridaMapa) etiquetaCorrida = `la corrida del ${fecha(corridaMapa.creada)}`;

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
        priorizacionVisible={priorizacionVisible}
        onAlternarSemaforos={() => setSemaforosVisibles((v) => !v)}
        onAlternarPriorizacion={() => setPriorizacionVisible((v) => !v)}
      />

      {sesion3d && (
        <Vista3D
          id={sesion3d.id}
          corrida={sesion3d.corrida}
          onCerrar={() => setSesion3d(null)}
        />
      )}

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
                <button type="button" role="tab" aria-selected={pestana === 'cierres'} className={pestana === 'cierres' ? 'activa' : ''} onClick={() => setPestana('cierres')}>
                  Cierres
                </button>
              </div>
              <button type="button" className="pd-cerrar" onClick={() => setPlegado(true)} aria-label="Plegar panel">
                ›
              </button>
            </header>
            {pestana === 'demanda' && (
              <PanelDemanda
                modos={modos}
                historial={corridas.historial}
                precalculadas={precalculadas}
                corridaCargada={corridaMapa?.id}
                cargando={!!carga}
                enCurso={corridas.enCurso}
                error={corridas.error}
                onEjecutar={(params) => corridas.lanzar({ ...params, cierres })}
                onVerCorrida={cargarCorrida}
              />
            )}
            {pestana === 'interseccion' && (
              <FichaInterseccion
                id={interseccion}
                corrida={corridaMapa}
                etiquetaCorrida={etiquetaCorrida}
                onAbrir3D={(tlId) => setSesion3d({ id: tlId, corrida: corridaMapa })}
              />
            )}
            {pestana === 'cierres' && (
              <PanelCierres cierres={cierres} onChange={setCierres} />
            )}
          </aside>
        )}

        <TarjetaActividad
          corrida={corridas.activa}
          carga={carga}
          errorCarga={errorCarga}
          aviso={aviso}
          onDescartarAviso={descartarAviso}
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
