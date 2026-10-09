import React, { useEffect, useState } from 'react';
import { obtenerInterseccion } from '../api';

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));

const GIROS = { s: 'recto', l: 'izquierda', r: 'derecha', t: 'retorno', L: 'izquierda suave', R: 'derecha suave' };

function Luz({ luz }) {
  return <span className={`fi-luz ${luz}`} title={luz} aria-label={luz} />;
}

/** Ficha de una intersección semaforizada: accesos con volumen simulado y programa del semáforo. */
export default function FichaInterseccion({ id, corrida, etiquetaCorrida }) {
  const [ficha, setFicha] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!id) return undefined;
    let cancelado = false;
    setFicha(null);
    setError(null);
    obtenerInterseccion(id, corrida)
      .then((f) => !cancelado && setFicha(f))
      .catch((e) => !cancelado && setError(e.message));
    return () => {
      cancelado = true;
    };
  }, [id, corrida]);

  if (!id) {
    return (
      <div className="pd-contenido fi-vacia">
        <p>Haz clic en un semáforo del mapa (puntos cian) para ver su ficha.</p>
        <p className="pd-nota">Si no los ves, actívalos con "Semáforos" en la leyenda de arriba.</p>
      </div>
    );
  }
  if (error) return <p className="pd-error">{error}</p>;
  if (!ficha) return <p className="pd-nota">Cargando intersección…</p>;

  const accesos = [...ficha.accesos].sort((a, b) => (b.volumen ?? -1) - (a.volumen ?? -1));
  const giros = (edge) =>
    [...new Set(ficha.enlaces.filter((e) => e.acceso === edge).map((e) => GIROS[e.giro] ?? e.giro))].join(', ');

  return (
    <div className="pd-contenido ficha">
      <h3 className="fi-nombre">{ficha.nombre}</h3>
      <p className="pd-descripcion">
        {ficha.accesos.length} accesos · {ficha.movimientos} movimientos · semáforo {ficha.tipo === 'static' ? 'de tiempo fijo' : ficha.tipo}
        {ficha.cruces.length > 1 && ` · controla ${ficha.cruces.length} nodos`}
      </p>

      <section>
        <h3>Accesos y volumen simulado</h3>
        <p className="pd-nota">Vehículos que pasaron por cada acceso en {etiquetaCorrida} (07:00–10:00).</p>
        <table className="fi-tabla">
          <thead>
            <tr>
              <th>Acceso</th>
              <th title="Vehículos en la ventana de 3 h">Veh.</th>
              <th title="Vehículos por hora">Veh/h</th>
            </tr>
          </thead>
          <tbody>
            {accesos.map((a, i) => (
              <tr key={a.edge}>
                <td>
                  <strong>{String.fromCharCode(65 + i)}.</strong> {a.calle ?? 'Sin nombre'}
                  <span className="fi-sub">
                    {a.clase} · {a.carriles} carril{a.carriles === 1 ? '' : 'es'} · {a.velocidad_kmh} km/h · {giros(a.edge)}
                  </span>
                </td>
                <td>{numero(a.volumen)}</td>
                <td>{numero(a.volumen_hora)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {ficha.nota_volumenes && <p className="pd-nota">{ficha.nota_volumenes}</p>}
      </section>

      <section>
        <h3>Programa del semáforo · ciclo {numero(ficha.ciclo)} s</h3>
        <table className="fi-tabla fi-fases">
          <thead>
            <tr>
              <th>Fase</th>
              <th>s</th>
              {accesos.map((a, i) => (
                <th key={a.edge} title={a.calle ?? a.edge}>
                  {String.fromCharCode(65 + i)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {ficha.fases.map((f, n) => (
              <tr key={n} title={`Estado SUMO: ${f.estado}`}>
                <td>{n + 1}</td>
                <td>{numero(f.duracion)}</td>
                {accesos.map((a) => (
                  <td key={a.edge}>
                    <Luz luz={f.luces[a.edge] ?? 'apagado'} />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
        <p className="pd-nota">
          Cada columna es un acceso de la tabla de arriba; la luz es la de su movimiento más permisivo en esa fase.{' '}
          {ficha.nota_programa}
        </p>
      </section>
    </div>
  );
}
