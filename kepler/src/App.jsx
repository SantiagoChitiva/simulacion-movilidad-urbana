import React, { useEffect } from 'react';
import { createStore, combineReducers, applyMiddleware } from 'redux';
import { Provider, useDispatch } from 'react-redux';
import { taskMiddleware } from 'react-palm/tasks';
import keplerGlReducer from '@kepler.gl/reducers';
import { addDataToMap } from '@kepler.gl/actions';
import { processGeojson } from '@kepler.gl/processors';
import KeplerGl from '@kepler.gl/components';

const reducers = combineReducers({
  keplerGl: keplerGlReducer,
});

const store = createStore(reducers, {}, applyMiddleware(taskMiddleware));

const DATASET_ID = 'usaquen_trips';

// Color por modo (TransportMode del ETL: simulation-service/src/etl/sumo/enums/transport_mode.py)
const MODE_COLORS = {
  auto: '#ff5c5c',
  bici: '#2ecc71',
  escolar: '#ff9ecf',
  especial: '#b57bff',
  informal: '#c0793a',
  moto: '#ff8c1a',
  otro: '#8c8c8c',
  peaton: '#e6e6e6',
  taxi: '#ffd21f',
  transporte_publico: '#4da3ff',
};
const UNKNOWN_MODE_COLOR = '#ffffff';

// Kepler asigna los colores de la escala ordinal por orden alfabético de los
// modos presentes en los datos, así que la paleta se arma en ese mismo orden.
const modeColorRange = (geojson) => {
  const modes = [...new Set(geojson.features.map((f) => f.properties.mode))].sort();
  return modes.map((mode) => MODE_COLORS[mode] ?? UNKNOWN_MODE_COLOR);
};

const buildConfig = (colors) => ({
  version: 'v1',
  config: {
    visState: {
      layers: [
        {
          id: 'trips_layer',
          type: 'trip',
          config: {
            dataId: DATASET_ID,
            label: 'Trips SUMO',
            columns: { geojson: '_geojson' },
            isVisible: true,
            visConfig: {
              opacity: 0.9,
              thickness: 3,
              trailLength: 60,
              fadeTrail: true,
              colorRange: {
                name: 'modos',
                type: 'qualitative',
                category: 'Custom',
                colors,
              },
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
    mapState: {
      latitude: 4.7345,
      longitude: -74.0395,
      zoom: 12.4,
      pitch: 45,
      bearing: 0,
    },
  },
});

function Map() {
  const dispatch = useDispatch();

  useEffect(() => {
    // generado por el pipeline (python -m etl.etl) y servido por la API
    fetch('/api/kepler-trips')
      .then((res) => {
        if (!res.ok) throw new Error(`API ${res.status}: ¿corriste el pipeline y la API?`);
        return res.json();
      })
      .then((geojson) => {
        dispatch(
          addDataToMap({
            datasets: {
              info: { label: 'Simulación SUMO – Usaquén', id: DATASET_ID },
              data: processGeojson(geojson),
            },
            options: { centerMap: false, readOnly: false },
            config: buildConfig(modeColorRange(geojson)),
          })
        );
      })
      .catch((err) => console.error('No se pudieron cargar los trips:', err));
  }, [dispatch]);

  return (
    <KeplerGl
      id="map"
      mapboxApiAccessToken={import.meta.env.VITE_MAPBOX_TOKEN}
      width={window.innerWidth}
      height={window.innerHeight}
    />
  );
}

export default function App() {
  return (
    <Provider store={store}>
      <Map />
    </Provider>
  );
}