import React, { useEffect, useMemo, useState } from 'react';
import { obtenerPresets } from '../api';

const PASO = 50;
const MAX_VIAJES = 100000; // mismo tope que configuration.MAX_VIAJES en la API
const SEMILLA_SUMOCFG = 42; // <seed> de usaquen-sim.sumocfg: la que se usa si no se pide otra

const GRUPOS = [
  ['particulares', 'Vehículos particulares'],
  ['servicio', 'Vehículos de servicio'],
  ['otros', 'Otros vehículos'],
  ['activos', 'Peatones y bicicletas'],
  ['publico', 'Transporte público'],
];

const numero = (n) => n.toLocaleString('es-CO');
const suma = (obj) => Object.values(obj).reduce((a, b) => a + b, 0);
const mismosConteos = (a, b) => Object.keys({ ...a, ...b }).every((k) => (a[k] ?? 0) === (b[k] ?? 0));

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

/**
 * Parámetros de demanda: preset, viajes por actor vial, escala y semilla; historial de corridas.
 * Si lo pedido coincide con una simulación precalculada, se carga en vez de simular.
 */
export default function PanelDemanda({
  modos,
  historial,
  precalculadas,
  corridaCargada,
  cargando,
  enCurso,
  error,
  onEjecutar,
  onVerCorrida,
}) {
  const [presets, setPresets] = useState([]);
  const [errorPresets, setErrorPresets] = useState(null);
  const [presetId, setPresetId] = useState('encuesta');
  const [conteos, setConteos] = useState({});
  const [escala, setEscala] = useState(100);
  const [semilla, setSemilla] = useState('');

  useEffect(() => {
    obtenerPresets()
      .then((p) => {
        setPresets(p);
        setConteos({ ...p.find((x) => x.id === 'encuesta').conteos });
      })
      .catch((e) => setErrorPresets(`No se pudo conectar con la API: ${e.message}`));
  }, []);

  const preset = presets.find((p) => p.id === presetId);
  const total = suma(conteos);
  const modificado = preset && modos.some((m) => (conteos[m.id] ?? 0) !== (preset.conteos[m.id] ?? 0));

  // precalculada que corresponde exactamente a lo que está en el panel
  const precalculada = precalculadas.find((p) => p.preset === presetId);
  const semillaPedida = semilla === '' ? SEMILLA_SUMOCFG : Number(semilla);
  const lista =
    !!precalculada &&
    mismosConteos(conteos, precalculada.conteos) &&
    semillaPedida === (precalculada.semilla ?? SEMILLA_SUMOCFG);
  const enMapa = lista && corridaCargada === precalculada.id;

  const subtotales = useMemo(() => {
    const s = {};
    for (const m of modos) s[m.grupo] = (s[m.grupo] ?? 0) + (conteos[m.id] ?? 0);
    return s;
  }, [modos, conteos]);

  const elegirPreset = (id) => {
    setPresetId(id);
    setConteos({ ...presets.find((p) => p.id === id).conteos });
  };

  // al ver una corrida anterior, el panel muestra los parámetros con que se lanzó
  const verCorrida = (id) => {
    const c = [...precalculadas, ...historial].find((x) => x.id === id) ?? null;
    if (c) {
      setPresetId(c.preset);
      setConteos({ ...Object.fromEntries(modos.map((m) => [m.id, 0])), ...c.conteos });
      setSemilla(c.semilla ?? '');
    }
    onVerCorrida(c);
  };

  const aplicarEscala = () => {
    const f = escala / 100;
    setConteos((c) => Object.fromEntries(Object.entries(c).map(([k, v]) => [k, Math.round(v * f)])));
    setEscala(100);
  };

  const ejecutar = () =>
    onEjecutar({
      preset: presetId,
      conteos: Object.fromEntries(Object.entries(conteos).filter(([, v]) => v > 0)),
      semilla: semilla === '' ? null : Number(semilla),
    });

  const nota = modos.find((m) => m.nota)?.nota;

  return (
    <div className="pd-contenido">
      {(errorPresets || error) && <p className="pd-error">{errorPresets || error}</p>}

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
              {precalculadas.some((x) => x.preset === p.id) && (
                <span className="pd-lista" title="Precalculada: se carga sin correr SUMO">
                  {' '}
                  · lista
                </span>
              )}
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
        {nota && <p className="pd-nota">* {nota}</p>}
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

      {lista ? (
        <>
          <button type="button" className="pd-ejecutar" onClick={() => onVerCorrida(precalculada)} disabled={cargando || enMapa}>
            {enMapa ? 'Cargada en el mapa' : 'Cargar simulación'}
          </button>
          <p className="pd-nota">
            Este escenario ya está simulado: se carga en segundos, sin correr SUMO. Cambia algún valor para simular uno
            nuevo.
          </p>
          {precalculada.desactualizada && (
            <p className="pd-advertencia">
              Se generó con otra versión de la red o de la encuesta. Regenérala con <code>python -m etl.precalculadas</code>.
            </p>
          )}
        </>
      ) : (
        <button
          type="button"
          className="pd-ejecutar"
          onClick={ejecutar}
          disabled={enCurso || total < 1 || total > MAX_VIAJES || !modos.length}
          title={enCurso ? 'Espera a que termine o cancela la simulación en curso' : undefined}
        >
          {enCurso ? 'Simulación en curso…' : 'Ejecutar simulación'}
        </button>
      )}

      <section>
        <h3>Corridas</h3>
        <select value={corridaCargada ?? ''} onChange={(e) => verCorrida(e.target.value)} aria-label="Corrida en el mapa">
          <option value="">Corrida por defecto (pipeline)</option>
          {precalculadas.length > 0 && (
            <optgroup label="Precalculadas">
              {precalculadas.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre} · {numero(suma(c.conteos))} viajes
                </option>
              ))}
            </optgroup>
          )}
          <optgroup label="Ejecutadas">
            {historial
              .filter((c) => c.estado === 'terminado')
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {new Date(c.creada).toLocaleString('es-CO')} · {presets.find((p) => p.id === c.preset)?.nombre ?? c.preset} ·{' '}
                  {numero(suma(c.conteos))} viajes
                </option>
              ))}
          </optgroup>
        </select>
      </section>
    </div>
  );
}
