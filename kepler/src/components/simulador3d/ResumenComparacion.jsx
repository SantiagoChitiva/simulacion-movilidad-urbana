import React from 'react';

const num = (n, unidad = '') => (n == null ? '—' : `${Math.round(n).toLocaleString('es-CO')}${unidad}`);
const tiempo = (s) => {
  if (s == null) return '—';
  const m = Math.floor(s / 60);
  return m ? `${m} min ${Math.round(s % 60)} s` : `${Math.round(s)} s`;
};

// filas del viaje: etiqueta, campo, formato y si menos es mejor (para resaltar)
const FILAS_VIAJE = [
  ['Duración del viaje', 'duracion_s', tiempo, true],
  ['Tiempo detenido', 'detenido_s', tiempo, true],
  ['Paradas', 'paradas', (v) => num(v), true],
  ['Frenadas en seco', 'frenadas', (v) => num(v), true],
  ['Riesgo máximo (0–100)', 'riesgo_max', (v) => num(v), true],
  ['CO₂ emitido', 'co2_g', (v) => num(v, ' g'), true],
  ['Velocidad media', 'velocidad_media_kmh', (v) => num(v, ' km/h'), false],
];

const FILAS_BALANCE = [
  ['Frenadas en seco cerca del cruce, por hora', 'frenadas_hora', (v) => num(v), true],
  ['…de ellas en la vía principal', 'frenadas_principal_hora', (v) => num(v), true],
  ['Casi choques por hora (llegan al mismo punto con menos de 1,5 s)', 'conflictos_hora', (v) => num(v), true],
  ['Choques', 'colisiones', (v) => num(v), true],
  ['Cola más larga en la vía que cede', 'cola_max_lateral', (v) => num(v, ' veh'), true],
  ['Cola más larga en la vía principal', 'cola_max_principal', (v) => num(v, ' veh'), true],
  ['Espera media en la vía que cede', 'espera_lateral_s', tiempo, true],
  ['Espera media en la vía principal', 'espera_principal_s', tiempo, true],
];

function Tabla({ filas, a, b }) {
  return (
    <table className="rc-tabla">
      <thead>
        <tr>
          <th />
          <th><span className="hud-punto-estado sin" /> Hoy, sin semáforo</th>
          <th><span className="hud-punto-estado con" /> Con semáforo</th>
        </tr>
      </thead>
      <tbody>
        {filas.map(([etiqueta, campo, formato, menosEsMejor]) => {
          const va = a?.[campo];
          const vb = b?.[campo];
          const mejor = va != null && vb != null && va !== vb ? ((vb < va) === menosEsMejor ? 'b' : 'a') : null;
          return (
            <tr key={campo}>
              <td>{etiqueta}</td>
              <td className={mejor === 'a' ? 'rc-mejor' : ''}>{formato(va)}</td>
              <td className={mejor === 'b' ? 'rc-mejor' : ''}>{formato(vb)}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

/**
 * Resultado de la comparación: el viaje del actor seguido en los dos escenarios (si ya
 * terminó) y el balance del cruce en toda la sesión, con su frase de veredicto.
 */
export default function ResumenComparacion({ resumen, balance, info, nombreCruce, onOtro, onCerrar }) {
  const minutos = balance?.a?.minutos ?? 0;
  const fondo = info?.viajes_sinteticos ? Object.values(info.viajes_sinteticos).reduce((s, n) => s + n, 0) : 0;
  return (
    <div className="rc-fondo" role="dialog" aria-label="Resumen de la comparación">
      <div className="rc">
        <header className="rc-cab">
          <div>
            <small>¿Sirve un semáforo aquí?</small>
            <h3>{nombreCruce}</h3>
          </div>
          <button type="button" className="sim3d-cerrar" onClick={onCerrar} aria-label="Cerrar resumen">×</button>
        </header>

        {resumen ? (
          <section>
            <h4>El viaje que seguiste</h4>
            <p className={`rc-veredicto ${resumen.comparacion.tono}`}>{resumen.comparacion.veredicto}</p>
            <Tabla filas={FILAS_VIAJE} a={resumen.a} b={resumen.b} />
          </section>
        ) : (
          <p className="pd-nota">Lanza un actor y deja que termine su recorrido para comparar su viaje en los dos escenarios.</p>
        )}

        {balance?.a && balance?.b && (
          <section>
            <h4>Lo que pasó en el cruce ({num(minutos)} min simulados)</h4>
            <Tabla filas={FILAS_BALANCE} a={balance.a} b={balance.b} />
          </section>
        )}

        <p className="rc-nota">
          El cruce (carriles, sentidos y giros) es el de la red real. El tráfico mezcla los viajes de la encuesta que pasan por
          aquí{fondo ? ` con ${num(fondo)} viajes de fondo supuestos` : ''}: no es un aforo. Un solo viaje depende mucho del
          momento en que se lanza; lanza varios y mira el balance del cruce. Si de verdad conviene un semáforo lo decide un
          estudio de tránsito con conteos en sitio.
        </p>
        <div className="rc-acciones">
          <button type="button" className="sim3d-primario" onClick={onOtro}>Lanzar otro viaje</button>
          <button type="button" onClick={onCerrar}>Volver a la simulación</button>
        </div>
      </div>
    </div>
  );
}
