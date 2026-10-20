import React, { useEffect, useRef, useState } from 'react';
import { crearComparacion, obtenerComparacion, obtenerProgramas } from '../api';

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));

const METRICAS = [
  { id: 'demora_media_s', etiqueta: 'Tiempo perdido por vehículo', unidad: 's', menosEsMejor: true,
    ayuda: 'Cuánto más tarda cada vehículo frente a ir a la velocidad permitida, en toda la zona.' },
  { id: 'espera_media_s', etiqueta: 'Tiempo detenido por vehículo', unidad: 's', menosEsMejor: true,
    ayuda: 'Segundos que cada vehículo pasa quieto (en rojo o en cola).' },
  { id: 'cola_max_veh', etiqueta: 'Cola más larga en un acceso', unidad: 'veh', menosEsMejor: true,
    ayuda: 'La fila de vehículos detenidos más larga que se formó en alguno de los accesos del semáforo.' },
  { id: 'detenciones', etiqueta: 'Frenadas hasta quedar quietos', unidad: '', menosEsMejor: true,
    ayuda: 'Veces que un vehículo se detuvo en los accesos del semáforo durante la hora.' },
  { id: 'demora_peaton_s', etiqueta: 'Tiempo perdido por peatón', unidad: 's', menosEsMejor: true,
    ayuda: 'Cuánto más tarda cada peatón frente a caminar sin esperar.' },
  { id: 'vehiculos', etiqueta: 'Vehículos en la hora', unidad: '', menosEsMejor: false,
    ayuda: 'Vehículos que circularon por la zona; si un programa atasca el cruce, pasan menos.' },
];

const ETAPAS = {
  preparando: 'Preparando…',
  recortando_red: 'Recortando la red alrededor del semáforo',
  recortando_demanda: 'Tomando los viajes que pasan por la zona',
  generando_fondo: 'Armando la demanda de la zona',
};

/** La frase que resume la comparación: cuánto cambia el tiempo perdido frente al programa actual. */
function veredicto(programas) {
  const listos = programas.filter((p) => p.metricas?.demora_media_s != null);
  const actual = listos.find((p) => p.nombre === 'actual');
  const otros = listos.filter((p) => p.nombre !== 'actual');
  if (!actual || !otros.length) return null;
  const mejor = otros.reduce((a, b) => (b.metricas.demora_media_s < a.metricas.demora_media_s ? b : a));
  const base = actual.metricas.demora_media_s;
  const diferencia = base - mejor.metricas.demora_media_s;
  const pct = base > 0 ? Math.round((Math.abs(diferencia) / base) * 100) : 0;
  if (pct < 3) {
    return `Los programas dan resultados parecidos: la diferencia en el tiempo perdido por vehículo es menor al 3 %.`;
  }
  return diferencia > 0
    ? `Con "${mejor.etiqueta}" cada vehículo pierde en promedio ${numero(mejor.metricas.demora_media_s)} s, ${numero(diferencia)} s menos (${pct} %) que con el programa actual.`
    : `Ningún programa mejora al actual: con "${mejor.etiqueta}", el mejor de los otros, cada vehículo pierde ${numero(-diferencia)} s más (${pct} %).`;
}

/** Pestaña Comparar: el mismo cruce y el mismo tráfico con varios programas de semáforo. */
export default function TablaComparacion({ id, corrida }) {
  const [guardados, setGuardados] = useState([]);
  const [elegidos, setElegidos] = useState({ webster: true });
  const [semilla, setSemilla] = useState(42);
  const [comparacion, setComparacion] = useState(null);
  const [error, setError] = useState(null);
  const sondeo = useRef(null);

  useEffect(() => () => clearInterval(sondeo.current), []);
  useEffect(() => {
    obtenerProgramas(id)
      .then((ps) => {
        const propios = ps.filter((p) => p.guardado);
        setGuardados(propios);
        setElegidos((e) => ({ ...e, ...Object.fromEntries(propios.map((p) => [p.program_id, true])) }));
      })
      .catch(() => setGuardados([]));
  }, [id]);

  const enCurso = comparacion?.estado === 'en_curso';
  const lanzar = async () => {
    clearInterval(sondeo.current);
    setError(null);
    setComparacion(null);
    const programas = ['actual', ...Object.keys(elegidos).filter((k) => elegidos[k])];
    try {
      const { comparacion_id: cid } = await crearComparacion(id, { corrida, programas, semilla });
      const consultar = async () => {
        try {
          const c = await obtenerComparacion(cid);
          setComparacion(c);
          if (c.estado !== 'en_curso') clearInterval(sondeo.current);
        } catch (e) {
          setError(e.message);
          clearInterval(sondeo.current);
        }
      };
      await consultar();
      sondeo.current = setInterval(consultar, 2000);
    } catch (e) {
      setError(e.message);
    }
  };

  const programas = comparacion?.programas ?? [];
  const terminados = programas.filter((p) => p.metricas);
  const mejorDe = (m) => {
    const valores = terminados.map((p) => p.metricas[m.id]).filter((v) => v != null);
    if (valores.length < 2) return null;
    return m.menosEsMejor ? Math.min(...valores) : Math.max(...valores);
  };
  const frase = veredicto(programas);
  const simulando = programas.find((p) => p.estado === 'simulando');
  const teleports = terminados.reduce((s, p) => s + (p.metricas.teleports ?? 0), 0);

  return (
    <section className="tc">
      <p className="pd-nota">
        Simula una hora punta (7:00–8:00) alrededor del semáforo, con los mismos viajes, una vez por programa. Así se
        ve cuál deja pasar mejor a vehículos y peatones. Tarda uno o dos minutos por programa.
      </p>

      <fieldset className="tc-programas">
        <legend>Programas a comparar</legend>
        <label><input type="checkbox" checked disabled /> Programa actual</label>
        <label>
          <input type="checkbox" checked={!!elegidos.webster} onChange={(e) => setElegidos({ ...elegidos, webster: e.target.checked })} />
          Tiempos óptimos (Webster)
        </label>
        {guardados.map((p) => (
          <label key={p.program_id}>
            <input type="checkbox" checked={!!elegidos[p.program_id]} onChange={(e) => setElegidos({ ...elegidos, [p.program_id]: e.target.checked })} />
            Tu programa ({p.program_id}, ciclo {numero(p.ciclo_s)} s)
          </label>
        ))}
        {!guardados.length && <small>Para comparar uno tuyo, créalo y guárdalo en la pestaña Configurar.</small>}
      </fieldset>

      <button type="button" className="pd-ejecutar" onClick={lanzar} disabled={enCurso || !Object.values(elegidos).some(Boolean)}>
        {enCurso ? 'Simulando…' : 'Comparar'}
      </button>
      {error && <p className="pd-error">{error}</p>}

      {enCurso && (
        <p className="pd-nota">{simulando ? `Simulando: ${simulando.etiqueta}…` : ETAPAS[comparacion.etapa] ?? 'Preparando…'}</p>
      )}
      {comparacion?.estado === 'error' && <p className="pd-error">{comparacion.error}</p>}

      {frase && <p className="tc-veredicto">{frase}</p>}

      {terminados.length > 0 && (
        <table className="fi-tabla tc-tabla">
          <thead>
            <tr>
              <th />
              {programas.map((p) => <th key={p.nombre}>{p.etiqueta}</th>)}
            </tr>
          </thead>
          <tbody>
            {METRICAS.map((m) => {
              const mejor = mejorDe(m);
              return (
                <tr key={m.id}>
                  <td title={m.ayuda}>{m.etiqueta} <span className="tc-ayuda" aria-hidden="true">ⓘ</span></td>
                  {programas.map((p) => {
                    const v = p.metricas?.[m.id];
                    return (
                      <td key={p.nombre} className={v != null && v === mejor ? 'tc-mejor' : ''}>
                        {p.metricas ? `${numero(v)}${v != null && m.unidad ? ` ${m.unidad}` : ''}` : '…'}
                      </td>
                    );
                  })}
                </tr>
              );
            })}
            <tr>
              <td>Ciclo</td>
              {programas.map((p) => <td key={p.nombre}>{numero(p.ciclo_s)} s</td>)}
            </tr>
          </tbody>
        </table>
      )}

      {comparacion?.estado === 'terminado' && (
        <p className="pd-nota">
          En verde, el mejor valor de cada fila. Zona de 300 m alrededor del semáforo con los viajes de la encuesta que
          pasan por ella (o tráfico de fondo si la corrida no tiene rutas) y semilla {semilla}.
          {teleports > 0 && ` SUMO retiró ${teleports} vehículos atascados en total.`}
        </p>
      )}

      <details className="fi-detalles">
        <summary>Opciones avanzadas</summary>
        <label className="tc-semilla">
          Semilla aleatoria
          <input type="number" value={semilla} onChange={(e) => setSemilla(Number(e.target.value) || 0)} />
        </label>
        <p className="pd-nota">Con la misma semilla, la misma comparación da exactamente los mismos números.</p>
      </details>
    </section>
  );
}
