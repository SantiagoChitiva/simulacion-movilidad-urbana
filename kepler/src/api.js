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

// La corrida que se consulta: una precalculada, una de la API o (sin corrida) la por defecto
const conCorrida = (path, corrida) => {
  if (corrida?.precalculada) return `${path}?precalculada=${encodeURIComponent(corrida.preset)}`;
  if (corrida?.id) return `${path}?run_id=${encodeURIComponent(corrida.id)}`;
  return path;
};

export const obtenerModos = () => pedir('/demanda/modos');
export const obtenerPresets = () => pedir('/demanda/presets');
export const listarSimulaciones = () => pedir('/simulaciones');

// Las precalculadas se manejan como corridas terminadas para que el visor las trate igual
export const listarPrecalculadas = () =>
  pedir('/precalculadas').then((lista) =>
    lista.map((p) => ({ ...p, id: `precalculada-${p.preset}`, precalculada: true, estado: 'terminado', creada: p.generada }))
  );
export const obtenerSimulacion = (id) => pedir(`/simulaciones/${encodeURIComponent(id)}`);
export const cancelarSimulacion = (id) =>
  pedir(`/simulaciones/${encodeURIComponent(id)}/cancelar`, { method: 'POST' });

export const crearSimulacion = ({ preset, conteos, semilla }) =>
  pedir('/simulaciones', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ preset, conteos, semilla }),
  });

export const obtenerIntersecciones = (corrida) => pedir(conCorrida('/intersecciones', corrida));
export const obtenerInterseccion = (id, corrida) =>
  pedir(conCorrida(`/intersecciones/${encodeURIComponent(id)}`, corrida));

// Trips para kepler: de una precalculada, de una corrida de la API, o de la corrida por
// defecto (python -m etl.etl)
export const urlTrips = (corrida) => {
  if (corrida?.precalculada) return `${BASE}/precalculadas/${encodeURIComponent(corrida.preset)}/kepler-trips`;
  if (corrida?.id) return `${BASE}/simulaciones/${encodeURIComponent(corrida.id)}/kepler-trips`;
  return `${BASE}/kepler-trips`;
};

/**
 * Descarga un JSON grande informando el avance (0-1, o null si no se conoce el tamaño).
 * Se cancela con `signal` (AbortController).
 */
export async function descargarJson(url, { onProgreso, signal } = {}) {
  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error(await mensajeDeError(res));
  // Con Content-Encoding: gzip el navegador entrega los bytes ya descomprimidos, pero
  // Content-Length es el tamaño comprimido: la API manda el original en X-Tamano-Original
  const comprimido = !!res.headers.get('Content-Encoding');
  const total = Number(res.headers.get('X-Tamano-Original')) || (!comprimido && Number(res.headers.get('Content-Length'))) || null;
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
