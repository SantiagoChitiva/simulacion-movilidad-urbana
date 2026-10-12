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

export const crearSimulacion = ({ preset, conteos, semilla, estilo, cierres }) =>
  pedir('/simulaciones', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ preset, conteos, semilla, estilo, cierres }),
  });

export const obtenerIntersecciones = (corrida) => pedir(conCorrida('/intersecciones', corrida));
export const obtenerInterseccion = (id, corrida) =>
  pedir(conCorrida(`/intersecciones/${encodeURIComponent(id)}`, corrida));

// Fase B: escenarios de zona
export const crearEscenarioZona = (tlId, { run_id, radio_m = 300 }) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/escenarios`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ run_id, radio_m }),
  });
export const obtenerEscenario = (runId) => pedir(`/escenarios/${encodeURIComponent(runId)}`);

// Fase C: programas de semáforo
export const obtenerProgramas = (tlId) => pedir(`/intersecciones/${encodeURIComponent(tlId)}/programas`);
export const obtenerPrograma = (tlId, progId) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/programas/${encodeURIComponent(progId)}`);
export const guardarPrograma = (tlId, progId, datos) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/programas/${encodeURIComponent(progId)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  });
export const calcularWebster = (tlId, datos) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/programas/webster`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  });

// Fase D: comparaciones
export const crearComparacion = (tlId, datos) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/comparaciones`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  });
export const obtenerComparacion = (compId) => pedir(`/comparaciones/${encodeURIComponent(compId)}`);

// Fase E: sesiones 3D
export const crearSesion3D = (tlId, datos) =>
  pedir(`/intersecciones/${encodeURIComponent(tlId)}/sesiones`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(datos),
  });
export const obtenerGeometria3D = (sid) => pedir(`/sesiones/${encodeURIComponent(sid)}/geometria`);
export const cerrarSesion3D = (sid) =>
  fetch(`${BASE}/sesiones/${encodeURIComponent(sid)}`, { method: 'DELETE' });

// Fase F: priorización
export const obtenerPriorizacion = (corrida) => pedir(conCorrida('/intersecciones/priorizacion', corrida));

// Estilos de conducción
export const obtenerEstilos = () => pedir('/demanda/estilos');

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
