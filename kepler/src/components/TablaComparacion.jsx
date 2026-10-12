import React, { useEffect, useRef, useState } from 'react';
import { crearComparacion, obtenerComparacion } from '../api';

const numero = (n, decimales = 0) =>
  n == null ? '—' : n.toLocaleString('es-CO', { minimumFractionDigits: decimales, maximumFractionDigits: decimales });

const METRICAS = [
  { id: 'demora_media_s',     label: 'Demora media', unidad: 's',   menos_es_mejor: true },
  { id: 'tiempo_perdido_s',   label: 'T. perdido',   unidad: 's',   menos_es_mejor: true },
  { id: 'cola_max_veh',       label: 'Cola máx.',    unidad: 'veh', menos_es_mejor: true },
  { id: 'peatones_atendidos', label: 'Peatones',     unidad: '',    menos_es_mejor: false },
  { id: 'teleports',          label: 'Teleports',    unidad: '',    menos_es_mejor: true },
];

function Barra({ valor, max, bueno }) {
  if (valor == null || max === 0) return null;
  const pct = Math.min(100, (valor / max) * 100);
  return (
    <div className="tc-barra-contenedor" title={`${valor}`}>
      <div
        className="tc-barra"
        style={{ width: `${pct}%`, background: bueno ? '#4caf50' : '#e53935' }}
      />
    </div>
  );
}

function BadgeCondicion({ nombre, ok }) {
  if (ok == null) return null;
  return (
    <span className={`tc-badge ${ok ? 'ok' : 'nok'}`} title={`Condición ${nombre}`}>
      {nombre} {ok ? '✓' : '✗'}
    </span>
  );
}

/** Pestaña de comparación de programas de semáforo para una intersección. */
export default function TablaComparacion({ id, corrida }) {
  const [programaIds, setProgramaIds] = useState(['0']);
  const [semilla, setSemilla] = useState('');
  const [compId, setCompId] = useState(null);
  const [comparacion, setComparacion] = useState(null);
  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState(null);
  const pollingRef = useRef(null);

  // Detener polling al desmontar
  useEffect(() => () => clearInterval(pollingRef.current), []);

  const lanzar = async () => {
    setCargando(true);
    setError(null);
    setComparacion(null);
    setCompId(null);
    try {
      const { comparacion_id } = await crearComparacion(id, {
        escenario_run_id: corrida?.id ?? null,
        programas: programaIds,
        semilla: semilla ? Number(semilla) : null,
      });
      setCompId(comparacion_id);
      pollingRef.current = setInterval(async () => {
        try {
          const c = await obtenerComparacion(comparacion_id);
          setComparacion(c);
          if (c.estado === 'terminado' || c.estado === 'error') {
            clearInterval(pollingRef.current);
            setCargando(false);
          }
        } catch {
          clearInterval(pollingRef.current);
          setCargando(false);
        }
      }, 2000);
    } catch (e) {
      setError(e.message);
      setCargando(false);
    }
  };

  const corridas = comparacion?.corridas ?? [];
  const terminadas = corridas.filter((c) => c.estado === 'terminado');

  // Máximos por métrica para las barras
  const maximos = {};
  for (const m of METRICAS) {
    maximos[m.id] = Math.max(1, ...terminadas.map((c) => c.metricas?.[m.id] ?? 0));
  }

  return (
    <section>
      <h3>Comparar programas</h3>
      <p className="pd-nota">
        Elige los programas a comparar y lanza una simulación de zona por cada uno. La corrida base
        de demanda es la que está cargada en el mapa.
      </p>

      <div className="fi-config-controles">
        <label>
          Programas (IDs separados por coma):
          <input
            type="text"
            value={programaIds.join(',')}
            onChange={(e) => setProgramaIds(e.target.value.split(',').map((s) => s.trim()).filter(Boolean))}
            placeholder="0,usuario"
          />
        </label>
        <label>
          Semilla:
          <input
            type="number"
            value={semilla}
            onChange={(e) => setSemilla(e.target.value)}
            placeholder="aleatoria"
            style={{ width: '6rem' }}
          />
        </label>
        <button
          type="button"
          className="pd-ejecutar"
          onClick={lanzar}
          disabled={cargando || programaIds.length < 1}
        >
          {cargando ? 'Simulando…' : 'Comparar'}
        </button>
      </div>

      {error && <p className="pd-error">{error}</p>}

      {comparacion && (
        <>
          <p className="pd-nota">
            Estado: <strong>{comparacion.estado}</strong>
            {comparacion.estado === 'en_curso' && ` · ${corridas.filter((c) => c.estado === 'terminado').length}/${corridas.length} listas`}
          </p>

          {terminadas.length > 0 && (
            <table className="fi-tabla tc-tabla">
              <thead>
                <tr>
                  <th>Programa</th>
                  {METRICAS.map((m) => (
                    <th key={m.id} title={m.unidad ? `en ${m.unidad}` : ''}>
                      {m.label}
                    </th>
                  ))}
                  <th>Condiciones</th>
                </tr>
              </thead>
              <tbody>
                {corridas.map((c) => (
                  <tr key={c.prog_id} className={c.prog_id === '0' ? 'tc-ref' : ''}>
                    <td>
                      <strong>{c.prog_id}</strong>
                      {c.prog_id === '0' && <span className="tc-badge ok">ref</span>}
                      {c.estado !== 'terminado' && <span className="pd-nota"> ({c.estado})</span>}
                    </td>
                    {METRICAS.map((m) => {
                      const val = c.metricas?.[m.id] ?? null;
                      const bueno = m.menos_es_mejor
                        ? val != null && val === Math.min(...terminadas.map((x) => x.metricas?.[m.id] ?? Infinity))
                        : val != null && val === Math.max(...terminadas.map((x) => x.metricas?.[m.id] ?? -Infinity));
                      return (
                        <td key={m.id} className={bueno ? 'tc-mejor' : ''}>
                          <span>{numero(val, m.id.endsWith('_s') ? 1 : 0)}{val != null && m.unidad ? ` ${m.unidad}` : ''}</span>
                          <Barra valor={val} max={maximos[m.id]} bueno={bueno} />
                        </td>
                      );
                    })}
                    <td>
                      <BadgeCondicion nombre="A" ok={c.metricas?.condicion_A} />
                      <BadgeCondicion nombre="C" ok={c.metricas?.condicion_C} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {comparacion.estado === 'terminado' && terminadas.length > 0 && (
            <p className="pd-nota">
              Condiciones A y C según el Manual de Semáforos 2024 (indicativo, ventana 3 h).
              El programa resaltado en cada columna obtiene el mejor valor.
            </p>
          )}
        </>
      )}
    </section>
  );
}
