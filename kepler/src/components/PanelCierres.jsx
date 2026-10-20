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

const nombreVia = (v) => v?.nombre ?? 'Vía sin nombre';

/**
 * Cierres viales para la próxima simulación: se elige la vía con un clic en el mapa
 * (capa "Vías", visible mientras esta pestaña está abierta) y la franja horaria.
 */
export default function PanelCierres({ cierres, onChange, via, cargandoVias, errorVias, onDescartarVia, onIrADemanda }) {
  const [ambos, setAmbos] = useState(true);
  const [inicio, setInicio] = useState('07:00');
  const [fin, setFin] = useState('10:00');
  const [manual, setManual] = useState('');
  const [error, setError] = useState(null);

  const franja = () => {
    const ini = horaASegundos(inicio);
    const fn = horaASegundos(fin);
    let problema = null;
    if (fn <= ini) problema = 'La hora de fin debe ser posterior a la de inicio.';
    else if (ini < HORA_INI || fn > HORA_FIN) problema = 'La simulación va de 07:00 a 10:00: usa horas dentro de ese rango.';
    setError(problema);
    return problema ? null : [ini, fn];
  };

  const agregar = (edges, nombre) => {
    const horas = franja();
    if (!horas) return;
    const nuevos = edges
      .filter((e) => !cierres.some((c) => c.edge_id === e))
      .map((e) => ({ edge_id: e, nombre, hora_inicio: horas[0], hora_fin: horas[1] }));
    onChange([...cierres, ...nuevos]);
  };

  const cerrarVia = () => {
    agregar(ambos && via.contrario ? [via.id, via.contrario] : [via.id], nombreVia(via));
    onDescartarVia();
  };

  return (
    <div className="pd-contenido ci">
      <p className="pd-nota">
        Haz clic en una calle del mapa para cerrarla (las vías se ven en gris mientras esta pestaña está abierta). Los
        vehículos que pasaban por ahí buscan otra ruta. Los cierres se aplican al <strong>ejecutar una simulación nueva</strong>{' '}
        desde la pestaña Demanda.
      </p>
      {cargandoVias && <p className="pd-nota">Cargando las vías de la red…</p>}
      {errorVias && <p className="pd-error">{errorVias}</p>}

      {via ? (
        <div className="ci-via">
          <b>{nombreVia(via)}</b>
          <span className="pd-nota">Vía {via.clase} · {via.carriles} carril{via.carriles === 1 ? '' : 'es'} por sentido</span>
          {via.contrario && (
            <label className="ci-check">
              <input type="checkbox" checked={ambos} onChange={(e) => setAmbos(e.target.checked)} />
              Cerrar los dos sentidos
            </label>
          )}
          <div className="ci-horas">
            <label>
              Desde
              <input type="time" min="07:00" max="10:00" value={inicio} onChange={(e) => setInicio(e.target.value)} />
            </label>
            <label>
              Hasta
              <input type="time" min="07:00" max="10:00" value={fin} onChange={(e) => setFin(e.target.value)} />
            </label>
          </div>
          <div className="ci-acciones">
            <button type="button" className="ps-primario" onClick={cerrarVia}>Cerrar esta vía</button>
            <button type="button" onClick={onDescartarVia}>Cancelar</button>
          </div>
        </div>
      ) : (
        <p className="ci-vacio">Ninguna vía elegida todavía.</p>
      )}
      {error && <p className="pd-error">{error}</p>}

      <section>
        <h3>Cierres para la próxima simulación ({cierres.length})</h3>
        {cierres.length === 0 ? (
          <p className="pd-nota">Sin cierres: se simula la red completa.</p>
        ) : (
          <>
            <ul className="ci-lista">
              {cierres.map((c) => (
                <li key={c.edge_id}>
                  <span>
                    <b>{c.nombre ?? 'Vía sin nombre'}</b>
                    <small>{segundosAHora(c.hora_inicio)}–{segundosAHora(c.hora_fin)} · tramo {c.edge_id}</small>
                  </span>
                  <button type="button" onClick={() => onChange(cierres.filter((x) => x.edge_id !== c.edge_id))} aria-label="Quitar cierre">×</button>
                </li>
              ))}
            </ul>
            <div className="ci-acciones">
              <button type="button" onClick={onIrADemanda}>Ir a simular</button>
              <button type="button" onClick={() => onChange([])}>Quitar todos</button>
            </div>
          </>
        )}
      </section>

      <details className="fi-detalles">
        <summary>Opciones avanzadas</summary>
        <p className="pd-nota">Cerrar un tramo por su id de SUMO (edge), por ejemplo <code>-123456789#0</code>.</p>
        <div className="ci-acciones">
          <input type="text" value={manual} onChange={(e) => setManual(e.target.value)} placeholder="id del edge" className="fi-input-estado" aria-label="Id del edge" />
          <button
            type="button"
            onClick={() => {
              if (manual.trim()) agregar([manual.trim()], null);
              setManual('');
            }}
          >
            Agregar
          </button>
        </div>
      </details>
    </div>
  );
}
