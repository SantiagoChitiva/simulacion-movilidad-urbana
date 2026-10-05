// Color por modo (TransportMode del ETL: simulation-service/src/etl/sumo/enums/transport_mode.py)
export const MODE_COLORS = {
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
export const UNKNOWN_MODE_COLOR = '#ffffff';

// Intersecciones semaforizadas: un color que no usa ningún modo
export const COLOR_SEMAFORO = '#00e0ff';

// Modos presentes en un GeoJSON de trips, en orden alfabético, con cuántos trips tiene cada uno
export const modosPresentes = (geojson) => {
  const conteo = {};
  for (const f of geojson.features) conteo[f.properties.mode] = (conteo[f.properties.mode] ?? 0) + 1;
  return Object.keys(conteo)
    .sort()
    .map((id) => ({ id, trips: conteo[id], color: MODE_COLORS[id] ?? UNKNOWN_MODE_COLOR }));
};

// Kepler asigna los colores de la escala ordinal por orden alfabético de los
// modos presentes en los datos, así que la paleta se arma en ese mismo orden.
export const modeColorRange = (presentes) => presentes.map((m) => m.color);

export const hexARgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
