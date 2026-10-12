import React, { useState } from 'react';

const HORA_INI = 7 * 3600;
const HORA_FIN = 10 * 3600;

function segundosAHora(s) {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${h}:${String(m).padStart(2, '0')}`;
}

function horaASegundos(str) {
  const [h, m = '0'] = str.split(':');
  return parseInt(h, 10) * 3600 + parseInt(m, 10) * 60;
}

/**
 * Panel para gestionar cierres viales antes de ejecutar una simulación.
 * Los cierres se pasan al crear la simulación.
 */
export default function PanelCierres({ cierres, onChange }) {
  const [nuevoEdge, setNuevoEdge] = useState('');
  const [nuevoInicio, setNuevoInicio] = useState('07:00');
  const [nuevoFin, setNuevoFin] = useState('10:00');
  const [error, setError] = useState(null);

  const agregar = () => {
    const edgeId = nuevoEdge.trim();
    if (!edgeId) {
      setError('Introduce el id del edge a cerrar.');
      return;
    }
    const inicio = horaASegundos(nuevoInicio);
    const fin = horaASegundos(nuevoFin);
    if (fin <= inicio) {
      setError('La hora de fin debe ser posterior al inicio.');
      return;
    }
    if (inicio < HORA_INI || fin > HORA_FIN) {
      setError(`La ventana simulada es 07:00–10:00. Usa horas dentro de ese rango.`);
      return;
    }
    setError(null);
    onChange([...cierres, { edge_id: edgeId, hora_inicio: inicio, hora_fin: fin }]);
    setNuevoEdge('');
  };

  const eliminar = (i) => onChange(cierres.filter((_, idx) => idx !== i));

  return (
    <div className="pd-contenido">
      <section>
        <h3>Cierres viales activos</h3>
        {cierres.length === 0 ? (
          <p className="pd-nota">Sin cierres. La simulación usará la red completa.</p>
        ) : (
          <table className="fi-tabla">
            <thead>
              <tr>
                <th>Edge</th>
                <th>Inicio</th>
                <th>Fin</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {cierres.map((c, i) => (
                <tr key={i}>
                  <td>
                    <code>{c.edge_id}</code>
                  </td>
                  <td>{segundosAHora(c.hora_inicio)}</td>
                  <td>{segundosAHora(c.hora_fin)}</td>
                  <td>
                    <button type="button" onClick={() => eliminar(i)} aria-label="Eliminar cierre">
                      ×
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section>
        <h3>Agregar cierre</h3>
        <div className="pd-grupo">
          <label>
            Edge ID
            <input
              type="text"
              value={nuevoEdge}
              onChange={(e) => setNuevoEdge(e.target.value)}
              placeholder="-123456789#0"
              className="fi-input-estado"
            />
          </label>
          <label>
            Inicio
            <input
              type="time"
              min="07:00"
              max="10:00"
              value={nuevoInicio}
              onChange={(e) => setNuevoInicio(e.target.value)}
            />
          </label>
          <label>
            Fin
            <input
              type="time"
              min="07:00"
              max="10:00"
              value={nuevoFin}
              onChange={(e) => setNuevoFin(e.target.value)}
            />
          </label>
          <button type="button" onClick={agregar}>
            + Agregar cierre
          </button>
        </div>
        {error && <p className="pd-error">{error}</p>}
        <p className="pd-nota">
          El Edge ID es el identificador interno de SUMO del segmento de vía. Puedes encontrarlo
          en el panel de kepler al seleccionar una arista, o en el archivo .net.xml.
          Los vehículos afectados buscarán rutas alternativas (rerouter SUMO).
        </p>
      </section>
    </div>
  );
}
