import React from 'react';
import { COLOR_SEMAFORO } from '../modos';

const numero = (n) => n.toLocaleString('es-CO');

/** Franja arriba al centro: color de cada actor vial de la corrida cargada y la capa de semáforos. */
export default function LeyendaModos({ presentes, etiquetas, semaforosVisibles, onAlternarSemaforos }) {
  if (!presentes.length) return null;
  const porTrips = [...presentes].sort((a, b) => b.trips - a.trips);
  return (
    <div className="leyenda-contenedor">
    <nav className="leyenda" aria-label="Leyenda de colores">
      {porTrips.map((m) => (
        <span key={m.id} className="leyenda-item" title={`${numero(m.trips)} trips en el mapa`}>
          <span className="leyenda-punto" style={{ background: m.color }} />
          {etiquetas[m.id] ?? m.id}
        </span>
      ))}
      <span className="leyenda-separador" />
      <button
        type="button"
        className={`leyenda-item leyenda-boton ${semaforosVisibles ? 'activo' : ''}`}
        onClick={onAlternarSemaforos}
        aria-pressed={semaforosVisibles}
        title="Mostrar u ocultar las intersecciones semaforizadas"
      >
        <span className="leyenda-punto semaforo" style={{ background: COLOR_SEMAFORO }} />
        Semáforos
      </button>
    </nav>
    </div>
  );
}
