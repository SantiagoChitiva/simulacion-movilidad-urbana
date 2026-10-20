import React, { Suspense, lazy, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createStore, combineReducers, applyMiddleware } from 'redux';
import { Provider, useDispatch, useSelector } from 'react-redux';
import { taskMiddleware } from 'react-palm/tasks';
import keplerGlReducer from '@kepler.gl/reducers';
import {
  addDataToMap,
  mapStyleChange,
  onLayerHover,
  onMapClick,
  removeDataset,
  reorderLayer,
  toggleModal,
  updateMap,
} from '@kepler.gl/actions';
import { processGeojson, processRowObject } from '@kepler.gl/processors';
import KeplerGl from '@kepler.gl/components';
import { descargarJson, listarPrecalculadas, obtenerIntersecciones, obtenerModos, obtenerPriorizacion, obtenerVias, urlTrips } from './api';
import { useCorridas, useTamanoVentana } from './hooks';
import { COLOR_SEMAFORO, hexARgb, modeColorRange, modosPresentes } from './modos';
import FichaInterseccion from './components/FichaInterseccion';
import LeyendaModos from './components/LeyendaModos';
import LimiteError from './components/LimiteError';
import PanelCierres from './components/PanelCierres';
import PanelDemanda from './components/PanelDemanda';
import TarjetaActividad from './components/TarjetaActividad';
import PanelSemaforizacion, { NIVELES } from './components/PanelSemaforizacion';
import LimiteErrores from './components/simulador3d/LimiteErrores';

// three.js y maplibre solo se descargan al abrir el simulador
const Simulador3D = lazy(() => import('./components/simulador3d/Simulador3D'));

const reducers = combineReducers({
  keplerGl: keplerGlReducer,
});

const store = createStore(reducers, {}, applyMiddleware(taskMiddleware));

const MAPA_ID = 'map';
const DATASET_TRIPS = 'usaquen_trips';
const DATASET_SEMAFOROS = 'intersecciones';
const DATASET_PRIORIZACION = 'priorizacion';
const DATASET_SELECCION = 'seleccion';
const DATASET_VIAS = 'vias';
const DATASET_CIERRES = 'cierres';
const CAPA_TRIPS = 'trips_layer';
const CAPA_SEMAFOROS = 'semaforos_layer';
const CAPA_PRIORIZACION = 'priorizacion_layer';
const CAPA_SELECCION = 'seleccion_layer';
const CAPA_VIAS = 'vias_layer';
const CAPA_CIERRES = 'cierres_layer';

// Tema de la interfaz (claro u oscuro) y estilo de mapa base que le corresponde
const CLAVE_TEMA = 'visor.tema';
const MAPA_BASE = { claro: 'positron', oscuro: 'dark-matter' };
const temaGuardado = () => {
  try {
    return localStorage.getItem(CLAVE_TEMA) === 'oscuro' ? 'oscuro' : 'claro';
  } catch {
    return 'claro';
  }
};

// Como los modos, kepler asigna los colores ordinales en orden alfabético de los niveles presentes
const configPriorizacion = (niveles) => ({
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: CAPA_PRIORIZACION,
          type: 'point',
          config: {
            dataId: DATASET_PRIORIZACION,
            label: 'Priorización de cruces',
            columns: { lat: 'lat', lng: 'lng', altitude: null },
            isVisible: true,
            visConfig: {
              radius: 14, opacity: 0.95, filled: true, outline: true, thickness: 1.5, strokeColor: [255, 255, 255],
              colorRange: { name: 'niveles', type: 'qualitative', category: 'Custom', colors: niveles.map((n) => NIVELES[n].color) },
            },
          },
          visualChannels: {
            colorField: { name: 'nivel', type: 'string' },
            colorScale: 'ordinal',
          },
        },
      ],
      interactionConfig: {
        tooltip: {
          enabled: true,
          fieldsToShow: {
            [DATASET_PRIORIZACION]: [
              { name: 'cruce', format: null },
              { name: 'prioridad', format: null },
            ],
          },
        },
      },
    },
  },
});

// Anillo alrededor del cruce elegido (en el mapa o en la lista del panel): oscuro sobre el
// mapa claro, blanco sobre el oscuro
const configSeleccion = (color) => ({
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: CAPA_SELECCION,
          type: 'point',
          config: {
            dataId: DATASET_SELECCION,
            label: 'Cruce elegido',
            columns: { lat: 'lat', lng: 'lng', altitude: null },
            isVisible: true,
            color,
            visConfig: { radius: 30, opacity: 1, filled: false, outline: true, thickness: 3, strokeColor: color },
          },
          visualChannels: { colorField: null, sizeField: null },
        },
      ],
    },
  },
});

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

// Líneas de la red (pestaña Cierres): gris para elegir, rojo para lo ya cerrado
const configLineas = (id, dataId, label, color, thickness) => ({
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id,
          type: 'geojson',
          config: {
            dataId,
            label,
            columns: { geojson: '_geojson' },
            isVisible: true,
            color,
            visConfig: { opacity: 0.8, thickness, strokeColor: color, stroked: true, filled: false },
          },
          visualChannels: { colorField: null, sizeField: null, strokeColorField: null },
        },
      ],
      interactionConfig: {
        tooltip: {
          enabled: true,
          fieldsToShow: { [dataId]: [{ name: 'nombre', format: null }, { name: 'clase', format: null }] },
        },
      },
    },
  },
});

// feature de /intersecciones/priorizacion → cruce candidato (panel y simulador 3D)
const aCandidato = (f) => ({
  ...f.properties,
  lon: f.geometry.coordinates[0],
  lat: f.geometry.coordinates[1],
  nodos: f.properties.nodos?.length ? f.properties.nodos : [f.properties.id],
});

// Orden de dibujo, de arriba hacia abajo. reorderLayer reemplaza el orden completo: una
// lista parcial dejaría fuera (ocultas) las capas que no nombra.
const ORDEN_CAPAS = [CAPA_SELECCION, CAPA_PRIORIZACION, CAPA_SEMAFOROS, CAPA_CIERRES, CAPA_VIAS, CAPA_TRIPS];
const ordenCapas = (layerOrder) => [
  ...ORDEN_CAPAS.filter((id) => layerOrder.includes(id)),
  ...layerOrder.filter((id) => !ORDEN_CAPAS.includes(id)),
];

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
  const [cruceCandidato, setCruceCandidato] = useState(null);   // cruce sin semáforo elegido
  const [candidatos, setCandidatos] = useState([]);
  const [simulador, setSimulador] = useState(null);   // { cruce, corrida, intensidades }
  const [notasPriorizacion, setNotasPriorizacion] = useState([]);
  const [umbralesPriorizacion, setUmbralesPriorizacion] = useState({});
  const [tema, setTema] = useState(temaGuardado);
  // estable entre renders: si cambia, el simulador reconstruye sus dos escenas 3D
  const candidatosSimulador = useMemo(() => candidatos.filter((c) => c.nivel !== 'observacion'), [candidatos]);
  const [cierres, setCierres] = useState([]);
  const [viaElegida, setViaElegida] = useState(null);
  const [vias, setVias] = useState(null);   // FeatureCollection de /red/vias (se pide una vez)
  const [estadoVias, setEstadoVias] = useState({ cargando: false, error: null });
  const abortar = useRef(null);
  const primeraCarga = useRef(true);
  const filasSemaforos = useRef([]);
  const filasPriorizacion = useRef([]);
  const filasVias = useRef([]);

  // Kepler conserva el objeto bajo el mouse y el tooltip fijado; si se reemplaza el
  // dataset sin limpiarlos, intenta dibujar un trip que ya no existe y se cae.
  const limpiarInteraccion = useCallback(() => {
    dispatch(onLayerHover(null));
    dispatch(onMapClick());
  }, [dispatch]);

  // las capas nuevas entran arriba: después de cada cambio se reordenan
  const layerOrder = useSelector((s) => s.keplerGl?.[MAPA_ID]?.visState?.layerOrder);
  useEffect(() => {
    if (!layerOrder?.length) return;
    const orden = ordenCapas(layerOrder);
    if (orden.some((id, i) => id !== layerOrder[i])) dispatch(reorderLayer(orden));
  }, [layerOrder, dispatch]);

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

  // clic sobre un semáforo → ficha; sobre un cruce candidato → semaforizar
  // (kepler guarda el objeto clicado en visState.clicked)
  const clicado = useSelector((s) => s.keplerGl?.[MAPA_ID]?.visState?.clicked);
  useEffect(() => {
    const capa = clicado?.layer?.id ?? '';
    const indice = clicado?.object?.index ?? clicado?.index;
    if (capa.startsWith(CAPA_SEMAFOROS)) {
      const fila = filasSemaforos.current[indice];
      if (fila) {
        setInterseccion(fila.id);
        setPestana('interseccion');
        setPlegado(false);
      }
    } else if (capa.startsWith(CAPA_VIAS)) {
      const via = filasVias.current[indice];
      if (via) setViaElegida(via);
    } else if (capa.startsWith(CAPA_PRIORIZACION)) {
      const fila = filasPriorizacion.current[indice];
      if (fila) {
        setCruceCandidato(fila);
        setPestana('semaforizar');
        setPlegado(false);
      }
    }
  }, [clicado]);

  // ─── priorización ───────────────────────────────────────────────────────────

  useEffect(() => {
    if (!priorizacionVisible) {
      filasPriorizacion.current = [];
      limpiarInteraccion();
      dispatch(removeDataset(DATASET_PRIORIZACION));
      return undefined;
    }
    let cancelado = false;
    obtenerPriorizacion(corridaMapa)
      .then((fc) => {
        if (cancelado) return;
        // En el mapa, como en Semáforos de Barranquilla: prioritarios y recomendados
        // (los "en observación" quedan solo en la lista del panel)
        const todos = fc.features.map(aCandidato);
        const enMapa = todos.filter((c) => c.nivel === 'prioritario' || c.nivel === 'recomendado');
        filasPriorizacion.current = enMapa;
        setCandidatos(todos);
        setNotasPriorizacion(fc.notas ?? []);
        setUmbralesPriorizacion(fc.umbrales ?? {});
        // kepler no acepta listas en las columnas: al mapa solo va lo que se dibuja y el tooltip
        const filas = enMapa.map((c) => ({
          id: c.id,
          nivel: c.nivel,
          cruce: c.calles?.length ? c.calles.join(' × ') : `Cruce ${c.id}`,
          prioridad: NIVELES[c.nivel].etiqueta,
          lng: c.lon,
          lat: c.lat,
        }));
        const niveles = [...new Set(filas.map((f) => f.nivel))].sort();
        limpiarInteraccion();
        dispatch(removeDataset(DATASET_PRIORIZACION));
        dispatch(
          addDataToMap({
            datasets: {
              info: { label: 'Priorización de cruces', id: DATASET_PRIORIZACION },
              data: processRowObject(filas),
            },
            options: { centerMap: false, keepExistingConfig: true },
            config: configPriorizacion(niveles),
          })
        );
      })
      .catch((e) => !cancelado && setErrorCarga(`Priorización: ${e.message}`));
    return () => {
      cancelado = true;
    };
  }, [priorizacionVisible, corridaMapa, dispatch, limpiarInteraccion]);

  // ─── cierres viales ─────────────────────────────────────────────────────────

  const enCierres = pestana === 'cierres' && !plegado;
  useEffect(() => {
    if (!enCierres || vias) return;
    setEstadoVias({ cargando: true, error: null });
    obtenerVias()
      .then((fc) => {
        setVias(fc);
        setEstadoVias({ cargando: false, error: null });
      })
      .catch((e) => setEstadoVias({ cargando: false, error: `Vías: ${e.message}` }));
  }, [enCierres, vias]);

  // la capa de vías solo está mientras se eligen cierres: con 15 000 tramos taparía el resto
  useEffect(() => {
    if (!enCierres || !vias) {
      filasVias.current = [];
      dispatch(removeDataset(DATASET_VIAS));
      return;
    }
    filasVias.current = vias.features.map((f) => f.properties);
    limpiarInteraccion();
    dispatch(
      addDataToMap({
        datasets: { info: { label: 'Vías', id: DATASET_VIAS }, data: processGeojson(vias) },
        options: { centerMap: false, keepExistingConfig: true },
        config: configLineas(CAPA_VIAS, DATASET_VIAS, 'Vías', [140, 150, 165], 3),
      })
    );
  }, [enCierres, vias, dispatch, limpiarInteraccion]);

  // los tramos cerrados se ven en rojo mientras haya cierres
  useEffect(() => {
    dispatch(removeDataset(DATASET_CIERRES));
    if (!vias || !cierres.length) return;
    const cerrados = new Set(cierres.map((c) => c.edge_id));
    const features = vias.features.filter((f) => cerrados.has(f.properties.id));
    if (!features.length) return;
    dispatch(
      addDataToMap({
        datasets: { info: { label: 'Cierres viales', id: DATASET_CIERRES }, data: processGeojson({ type: 'FeatureCollection', features }) },
        options: { centerMap: false, keepExistingConfig: true },
        config: configLineas(CAPA_CIERRES, DATASET_CIERRES, 'Cierres viales', [214, 40, 40], 6),
      })
    );
  }, [cierres, vias, dispatch]);

  // anillo sobre el cruce elegido; se dibuja encima de las demás capas
  useEffect(() => {
    dispatch(removeDataset(DATASET_SELECCION));
    if (!cruceCandidato) return;
    dispatch(
      addDataToMap({
        datasets: {
          info: { label: 'Cruce elegido', id: DATASET_SELECCION },
          data: processRowObject([{ lat: cruceCandidato.lat, lng: cruceCandidato.lon }]),
        },
        options: { centerMap: false, keepExistingConfig: true },
        config: configSeleccion(tema === 'claro' ? [17, 24, 39] : [255, 255, 255]),
      })
    );
  }, [cruceCandidato, tema, dispatch]);

  const elegirCruce = useCallback(
    (cruce, { centrar = false } = {}) => {
      setCruceCandidato(cruce);
      if (cruce && centrar) dispatch(updateMap({ latitude: cruce.lat, longitude: cruce.lon, zoom: 16 }));
    },
    [dispatch]
  );

  // ─── tema ───────────────────────────────────────────────────────────────────

  useEffect(() => {
    document.documentElement.dataset.tema = tema;
    dispatch(mapStyleChange(MAPA_BASE[tema]));
    try {
      localStorage.setItem(CLAVE_TEMA, tema);
    } catch {
      // sin almacenamiento (ventana privada): el tema dura lo que dure la pestaña
    }
  }, [tema, dispatch, versionMapa]);

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
          theme={tema === 'claro' ? 'light' : undefined}
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

      {simulador && (
        <LimiteErrores onCerrar={() => setSimulador(null)}>
          <Suspense fallback={<div className="sim3d"><div className="sim3d-cortina"><div className="sim3d-spinner" /><p>Cargando el simulador 3D…</p></div></div>}>
            <Simulador3D
              cruce={simulador.cruce}
              candidatos={candidatosSimulador}
              corrida={simulador.corrida}
              intensidades={simulador.intensidades}
              onCambiarCruce={(c) => c && setSimulador((s) => ({ ...s, cruce: c }))}
              onCerrar={() => setSimulador(null)}
            />
          </Suspense>
        </LimiteErrores>
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
                <button type="button" role="tab" aria-selected={pestana === 'semaforizar'} className={pestana === 'semaforizar' ? 'activa' : ''} onClick={() => setPestana('semaforizar')}>
                  Semaforizar
                </button>
              </div>
              <div className="pd-acciones">
                <button
                  type="button"
                  className="pd-tema"
                  onClick={() => setTema(tema === 'claro' ? 'oscuro' : 'claro')}
                  aria-label={tema === 'claro' ? 'Cambiar a tema oscuro' : 'Cambiar a tema claro'}
                  title={tema === 'claro' ? 'Tema oscuro' : 'Tema claro'}
                >
                  {tema === 'claro' ? '☾' : '☀'}
                </button>
                <button type="button" className="pd-cerrar" onClick={() => setPlegado(true)} aria-label="Plegar panel">
                  ›
                </button>
              </div>
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
                cierres={cierres.length}
                onEjecutar={(params) => corridas.lanzar({ ...params, cierres })}
                onVerCorrida={cargarCorrida}
              />
            )}
            {pestana === 'interseccion' && (
              <FichaInterseccion
                id={interseccion}
                corrida={corridaMapa}
                etiquetaCorrida={etiquetaCorrida}
              />
            )}
            {pestana === 'cierres' && (
              <PanelCierres
                cierres={cierres}
                onChange={setCierres}
                via={viaElegida}
                cargandoVias={estadoVias.cargando}
                errorVias={estadoVias.error}
                onDescartarVia={() => setViaElegida(null)}
                onIrADemanda={() => setPestana('demanda')}
              />
            )}
            {pestana === 'semaforizar' && (
              <PanelSemaforizacion
                seleccionado={cruceCandidato}
                candidatos={candidatos}
                notas={notasPriorizacion}
                periodoSiniestros={umbralesPriorizacion.anios_siniestros}
                totalSemaforizados={umbralesPriorizacion.semaforizados}
                priorizacionVisible={priorizacionVisible}
                semaforosVisibles={semaforosVisibles}
                onMostrarPriorizacion={() => setPriorizacionVisible(true)}
                onAlternarSemaforos={() => setSemaforosVisibles((v) => !v)}
                onElegir={elegirCruce}
                onAbrir={(cruce, intensidades) => setSimulador({ cruce, corrida: corridaMapa, intensidades })}
              />
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
