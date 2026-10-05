import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ESTADOS_FINALES,
  ETIQUETA_ESTADO,
  crearSimulacion,
  listarSimulaciones,
  obtenerModos,
  obtenerPresets,
  obtenerSimulacion,
} from '../api';

const PASO = 50;
const MAX_VIAJES = 100000; // mismo tope que configuration.MAX_VIAJES en la API
const INTERVALO_CONSULTA_MS = 5000;

const GRUPOS = [
  ['particulares', 'Vehículos particulares'],
  ['servicio', 'Vehículos de servicio'],
  ['otros', 'Otros vehículos'],
  ['activos', 'Peatones y bicicletas'],
  ['publico', 'Transporte público'],
];

const numero = (n) => n.toLocaleString('es-CO');
const suma = (obj) => Object.values(obj).reduce((a, b) => a + b, 0);

const duracion = (desde) => {
  const s = Math.max(0, Math.round((Date.now() - new Date(desde).getTime()) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

function FilaModo({ modo, valor, onCambio }) {
  const fijar = (v) => onCambio(Math.max(0, Math.round(Number.isFinite(v) ? v : 0)));
  return (
    <div className="pd-fila">
      <span className="pd-etiqueta" title={modo.nota ?? ''}>
        {modo.etiqueta}
        {modo.nota && <span className="pd-aviso"> *</span>}
      </span>
      <button type="button" onClick={() => fijar(valor - PASO)} aria-label={`Restar ${PASO} a ${modo.etiqueta}`}>
        −
      </button>
      <input
        type="number"
        min="0"
        step={PASO}
        value={valor}
        onChange={(e) => fijar(e.target.value === '' ? 0 : Number(e.target.value))}
        aria-label={`Viajes en ${modo.etiqueta}`}
      />
      <button type="button" onClick={() => fijar(valor + PASO)} aria-label={`Sumar ${PASO} a ${modo.etiqueta}`}>
        +
      </button>
    </div>
  );
}

export default function PanelDemanda({ corridaCargada, onCargarCorrida }) {
  const [abierto, setAbierto] = useState(true);
  const [modos, setModos] = useState([]);
  const [presets, setPresets] = useState([]);
  const [presetId, setPresetId] = useState('encuesta');
  const [conteos, setConteos] = useState({});
  const [escala, setEscala] = useState(100);
  const [semilla, setSemilla] = useState('');
  const [activa, setActiva] = useState(null); // corrida en curso (o la última lanzada)
  const [historial, setHistorial] = useState([]);
  const [error, setError] = useState(null);
  const [, setTic] = useState(0); // refresca el tiempo transcurrido

  const preset = presets.find((p) => p.id === presetId);
  const total = suma(conteos);
  const modificado = preset && modos.some((m) => (conteos[m.id] ?? 0) !== (preset.conteos[m.id] ?? 0));
  const enCurso = activa && !ESTADOS_FINALES.has(activa.estado);

  const refrescarHistorial = useCallback(
    () => listarSimulaciones().then(setHistorial).catch((e) => setError(e.message)),
    []
  );

  // carga inicial: modos, presets e historial (retoma una corrida que siga en curso)
  useEffect(() => {
    Promise.all([obtenerModos(), obtenerPresets(), listarSimulaciones()])
      .then(([m, p, h]) => {
        setModos(m);
        setPresets(p);
        setConteos({ ...p.find((x) => x.id === 'encuesta').conteos });
        setHistorial(h);
        const pendiente = h.find((c) => !ESTADOS_FINALES.has(c.estado));
        if (pendiente) setActiva(pendiente);
      })
      .catch((e) => setError(`No se pudo conectar con la API: ${e.message}`));
  }, []);

  // consulta el estado de la corrida en curso
  useEffect(() => {
    if (!enCurso) return undefined;
    const id = setInterval(() => {
      setTic((t) => t + 1);
      obtenerSimulacion(activa.id)
        .then((c) => {
          setActiva(c);
          if (ESTADOS_FINALES.has(c.estado)) {
            refrescarHistorial();
            if (c.estado === 'terminado') onCargarCorrida(c);
          }
        })
        .catch((e) => setError(e.message));
    }, INTERVALO_CONSULTA_MS);
    return () => clearInterval(id);
  }, [enCurso, activa?.id, onCargarCorrida, refrescarHistorial]);

  const elegirPreset = (id) => {
    setPresetId(id);
    setConteos({ ...presets.find((p) => p.id === id).conteos });
  };

  // al ver una corrida anterior, el panel muestra los parámetros con que se lanzó
  const verCorrida = (id) => {
    const c = historial.find((x) => x.id === id) ?? null;
    if (c) {
      setPresetId(c.preset);
      setConteos({ ...Object.fromEntries(modos.map((m) => [m.id, 0])), ...c.conteos });
      setSemilla(c.semilla ?? '');
    }
    onCargarCorrida(c);
  };

  const aplicarEscala = () => {
    const f = escala / 100;
    setConteos((c) => Object.fromEntries(Object.entries(c).map(([k, v]) => [k, Math.round(v * f)])));
    setEscala(100);
  };

  const ejecutar = () => {
    setError(null);
    crearSimulacion({
      preset: presetId,
      conteos: Object.fromEntries(Object.entries(conteos).filter(([, v]) => v > 0)),
      semilla: semilla === '' ? null : Number(semilla),
    })
      .then((c) => {
        setActiva(c);
        refrescarHistorial();
      })
      .catch((e) => setError(e.message));
  };

  const subtotales = useMemo(() => {
    const s = {};
    for (const m of modos) s[m.grupo] = (s[m.grupo] ?? 0) + (conteos[m.id] ?? 0);
    return s;
  }, [modos, conteos]);

  if (!abierto) {
    return (
      <button type="button" className="pd-abrir" onClick={() => setAbierto(true)}>
        Demanda
      </button>
    );
  }

  return (
    <aside className="pd-panel" aria-label="Parámetros de demanda">
      <header className="pd-encabezado">
        <h2>Demanda de la simulación</h2>
        <button type="button" className="pd-cerrar" onClick={() => setAbierto(false)} aria-label="Plegar panel">
          ›
        </button>
      </header>

      {error && <p className="pd-error">{error}</p>}

      <section>
        <h3>Escenario</h3>
        <div className="pd-presets">
          {presets.map((p) => (
            <button
              type="button"
              key={p.id}
              className={p.id === presetId ? 'activo' : ''}
              onClick={() => elegirPreset(p.id)}
              title={p.descripcion}
            >
              {p.nombre}
            </button>
          ))}
        </div>
        {preset && (
          <p className="pd-descripcion">
            {preset.descripcion}
            {modificado && <strong> Valores modificados.</strong>}
          </p>
        )}
      </section>

      <section>
        <h3>Viajes por actor vial (07:00–10:00)</h3>
        {GRUPOS.map(([grupo, titulo]) => {
          const delGrupo = modos.filter((m) => m.grupo === grupo);
          if (!delGrupo.length) return null;
          return (
            <div key={grupo} className="pd-grupo">
              <div className="pd-grupo-titulo">
                <span>{titulo}</span>
                <span>{numero(subtotales[grupo] ?? 0)}</span>
              </div>
              {delGrupo.map((m) => (
                <FilaModo
                  key={m.id}
                  modo={m}
                  valor={conteos[m.id] ?? 0}
                  onCambio={(v) => setConteos((c) => ({ ...c, [m.id]: v }))}
                />
              ))}
            </div>
          );
        })}
        {modos.some((m) => m.nota) && <p className="pd-nota">* {modos.find((m) => m.nota).nota}</p>}
        <div className={`pd-total ${total > MAX_VIAJES ? 'excedido' : ''}`}>
          <span>Total</span>
          <span>{numero(total)}</span>
        </div>
      </section>

      <section className="pd-ajustes">
        <label>
          Escala
          <input type="number" min="1" max="1000" value={escala} onChange={(e) => setEscala(Number(e.target.value) || 0)} />
          %
        </label>
        <button type="button" onClick={aplicarEscala} disabled={escala === 100 || escala <= 0}>
          Aplicar
        </button>
        <label>
          Semilla
          <input type="number" min="0" placeholder="42" value={semilla} onChange={(e) => setSemilla(e.target.value)} />
        </label>
      </section>

      <button
        type="button"
        className="pd-ejecutar"
        onClick={ejecutar}
        disabled={enCurso || total < 1 || total > MAX_VIAJES || !modos.length}
      >
        {enCurso ? 'Simulación en curso…' : 'Ejecutar simulación'}
      </button>

      {activa && (
        <div className={`pd-estado ${activa.estado}`}>
          <strong>{ETIQUETA_ESTADO[activa.estado] ?? activa.estado}</strong>
          {enCurso && <span> · {duracion(activa.creada)} (una corrida completa tarda 10–15 min)</span>}
          {activa.estado === 'error' && <p>{activa.error}</p>}
          {activa.estado === 'terminado' && activa.resultado && (
            <p>
              {numero(activa.resultado.viajes_generados)} viajes generados ·{' '}
              {numero(activa.resultado.vehiculos_insertados ?? 0)} vehículos insertados ·{' '}
              {numero(activa.resultado.trips_kepler)} trips en el mapa
            </p>
          )}
        </div>
      )}

      <section>
        <h3>Corridas</h3>
        <select
          value={corridaCargada ?? ''}
          onChange={(e) => verCorrida(e.target.value)}
        >
          <option value="">Corrida por defecto (pipeline)</option>
          {historial
            .filter((c) => c.estado === 'terminado')
            .map((c) => (
              <option key={c.id} value={c.id}>
                {new Date(c.creada).toLocaleString('es-CO')} · {presets.find((p) => p.id === c.preset)?.nombre ?? c.preset} ·{' '}
                {numero(suma(c.conteos))} viajes
              </option>
            ))}
        </select>
      </section>
    </aside>
  );
}
