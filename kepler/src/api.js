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

const conRun = (path, runId) => (runId ? `${path}?run_id=${encodeURIComponent(runId)}` : path);

export const obtenerModos = () => pedir('/demanda/modos');
export const obtenerPresets = () => pedir('/demanda/presets');
export const listarSimulaciones = () => pedir('/simulaciones');
export const obtenerSimulacion = (id) => pedir(`/simulaciones/${encodeURIComponent(id)}`);
export const cancelarSimulacion = (id) =>
  pedir(`/simulaciones/${encodeURIComponent(id)}/cancelar`, { method: 'POST' });

export const crearSimulacion = ({ preset, conteos, semilla }) =>
  pedir('/simulaciones', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ preset, conteos, semilla }),
  });

export const obtenerIntersecciones = (runId) => pedir(conRun('/intersecciones', runId));
export const obtenerInterseccion = (id, runId) =>
  pedir(conRun(`/intersecciones/${encodeURIComponent(id)}`, runId));

// Trips para kepler: de una corrida de la API, o de la corrida por defecto (python -m etl.etl)
export const urlTrips = (id) =>
  id ? `${BASE}/simulaciones/${encodeURIComponent(id)}/kepler-trips` : `${BASE}/kepler-trips`;

/**
 * Descarga un JSON grande informando el avance (0-1, o null si el servidor no manda
 * Content-Length). Se cancela con `signal` (AbortController).
 */
export async function descargarJson(url, { onProgreso, signal } = {}) {
  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error(await mensajeDeError(res));
  const total = Number(res.headers.get('Content-Length')) || null;
  const lector = res.body.getReader();
  const partes = [];
  let recibidos = 0;
  for (;;) {
    const { done, value } = await lector.read();
    if (done) break;
    partes.push(value);
    recibidos += value.length;
    onProgreso?.(total ? recibidos / total : null, recibidos);
  }
  const bytes = new Uint8Array(recibidos);
  let pos = 0;
  for (const p of partes) {
    bytes.set(p, pos);
    pos += p.length;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export const ESTADOS_FINALES = new Set(['terminado', 'error', 'cancelada']);

export const ETIQUETA_ESTADO = {
  en_cola: 'En cola',
  generando_demanda: 'Generando demanda',
  ruteando: 'Calculando rutas (duarouter)',
  simulando: 'Simulando en SUMO',
  exportando: 'Preparando trips para el mapa',
  cancelando: 'Cancelando…',
  terminado: 'Terminada',
  error: 'Error',
  cancelada: 'Cancelada',
};
