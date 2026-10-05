// Cliente de la API de simulation-service. Vite hace proxy de /api a localhost:8000.
const BASE = '/api';

const mensajeDeError = async (res) => {
  try {
    const { detail } = await res.json();
    if (Array.isArray(detail)) return detail.map((d) => d.msg).join('; ');
    if (detail) return String(detail);
  } catch {
    // la respuesta no era JSON
  }
  return `La API respondió ${res.status}`;
};

async function pedir(path, opciones) {
  const res = await fetch(`${BASE}${path}`, opciones);
  if (!res.ok) throw new Error(await mensajeDeError(res));
  return res.json();
}

export const obtenerModos = () => pedir('/demanda/modos');
export const obtenerPresets = () => pedir('/demanda/presets');
export const listarSimulaciones = () => pedir('/simulaciones');
export const obtenerSimulacion = (id) => pedir(`/simulaciones/${encodeURIComponent(id)}`);

export const crearSimulacion = ({ preset, conteos, semilla }) =>
  pedir('/simulaciones', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ preset, conteos, semilla }),
  });

// Trips para kepler: de una corrida de la API, o de la corrida por defecto (python -m etl.etl)
export const urlTrips = (id) =>
  id ? `${BASE}/simulaciones/${encodeURIComponent(id)}/kepler-trips` : `${BASE}/kepler-trips`;

export const ESTADOS_FINALES = new Set(['terminado', 'error']);

export const ETIQUETA_ESTADO = {
  en_cola: 'En cola',
  generando_demanda: 'Generando demanda',
  ruteando: 'Calculando rutas (duarouter)',
  simulando: 'Simulando en SUMO',
  exportando: 'Exportando trips',
  terminado: 'Terminada',
  error: 'Error',
};
