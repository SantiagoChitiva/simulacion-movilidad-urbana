import React, { useState } from 'react';

const NIVEL = { prioritario: 'Prioritario', recomendado: 'Recomendado', observacion: 'En observación', sin_accion: 'Sin acción' };

// Tráfico de fondo por defecto de la zona (veh/h; peatones en personas/h)
export const INTENSIDADES_DEFECTO = { auto: 700, moto: 250, taxi: 120, bici: 60, bus: 30, peaton: 400 };
const ETIQUETAS = { auto: 'Carros', moto: 'Motos', taxi: 'Taxis', bici: 'Bicicletas', bus: 'Buses', peaton: 'Peatones' };

const nombre = (c) => (c.calles?.length ? c.calles.join(' × ') : `Cruce ${c.id}`);

/**
 * Elegir un cruce sin semáforo (de la capa de priorización) y abrir el simulador 3D
 * que lo compara tal como está y con un semáforo propuesto.
 */
export default function PanelSemaforizacion({ seleccionado, candidatos, notas = [], priorizacionVisible, onMostrarPriorizacion, onElegir, onAbrir }) {
  const [intensidades, setIntensidades] = useState(INTENSIDADES_DEFECTO);
  const [verMas, setVerMas] = useState(false);
  const [nivel, setNivel] = useState('todos');

  const conteo = candidatos.reduce((acc, c) => ({ ...acc, [c.nivel]: (acc[c.nivel] ?? 0) + 1 }), {});
  const filtrados = candidatos.filter((c) => (nivel === 'todos' ? c.nivel !== 'observacion' : c.nivel === nivel));
  const top = [...filtrados].sort((a, b) => b.puntaje_total - a.puntaje_total).slice(0, verMas ? 40 : 8);

  return (
    <div className="ps-panel">
      <p className="pd-nota">
        Compara en 3D, lado a lado, un cruce <strong>sin semáforo</strong> como está hoy y el mismo cruce con un
        <strong> semáforo propuesto</strong>, con la misma demanda y el mismo actor en tercera persona.
      </p>

      {!priorizacionVisible && (
        <button type="button" className="ps-boton" onClick={onMostrarPriorizacion}>
          Mostrar cruces candidatos en el mapa
        </button>
      )}

      {seleccionado ? (
        <div className="ps-seleccion">
          <div className="ps-nombre">{nombre(seleccionado)}</div>
          <div className="ps-detalle">
            <span className={`ps-nivel nivel-${seleccionado.nivel}`}>{NIVEL[seleccionado.nivel] ?? seleccionado.nivel}</span>
            Puntaje {Math.round(seleccionado.puntaje_total)}
            {seleccionado.distancia_semaforo_m != null && ` · semáforo más cercano a ${Math.round(seleccionado.distancia_semaforo_m)} m`}
          </div>
          {seleccionado.evidencias?.length > 0 && (
            <ul className="ps-evidencias" aria-label="Por qué es candidato">
              {seleccionado.evidencias.map((e) => <li key={e}>{e}</li>)}
            </ul>
          )}

          <fieldset className="ps-intensidades">
            <legend>Tráfico de fondo de la zona (por hora)</legend>
            {Object.entries(intensidades).map(([modo, valor]) => (
              <label key={modo}>
                <span>{ETIQUETAS[modo]}</span>
                <input
                  type="range" min="0" max={modo === 'auto' || modo === 'peaton' ? 1500 : 600} step="10" value={valor}
                  onChange={(e) => setIntensidades({ ...intensidades, [modo]: Number(e.target.value) })}
                />
                <b>{valor}</b>
              </label>
            ))}
            <small>
              Se suma a los viajes reales de la encuesta que pasan por la zona. Recortada a unos cientos de metros, la
              demanda real es poca para ver el efecto del semáforo.
            </small>
          </fieldset>

          <button type="button" className="pd-ejecutar" onClick={() => onAbrir(seleccionado, intensidades)}>
            Simular en 3D: sin vs. con semáforo
          </button>
        </div>
      ) : (
        <p className="pd-nota">Haz clic en un cruce de la capa <strong>Priorización</strong> o elige uno de la lista.</p>
      )}

      {candidatos.length > 0 && (
        <>
          <h4 className="ps-subtitulo">Cruces candidatos</h4>
          <p className="pd-nota">
            Reglas y evidencia como en Semáforos de Barranquilla: vía colectora o mayor, a nivel, con cruces reales y
            sin semáforo a menos de 80 m; evidencia de siniestros (SDM), tramo largo sin semáforo y volumen simulado,
            calibrada con los cruces que ya tienen semáforo. No reemplaza un estudio de tránsito con aforos.
          </p>
          <div className="ps-filtros" role="group" aria-label="Nivel">
            {[['todos', `Mapa (${(conteo.prioritario ?? 0) + (conteo.recomendado ?? 0)})`], ['prioritario', `Prioritarios (${conteo.prioritario ?? 0})`],
              ['recomendado', `Recomendados (${conteo.recomendado ?? 0})`], ['observacion', `En observación (${conteo.observacion ?? 0})`]].map(([id, et]) => (
              <button key={id} type="button" className={`ps-boton ${nivel === id ? 'activo' : ''}`} onClick={() => setNivel(id)}>{et}</button>
            ))}
          </div>
          <ul className="ps-lista">
            {top.map((c) => (
              <li key={c.id}>
                <button type="button" className={seleccionado?.id === c.id ? 'activo' : ''} onClick={() => onElegir(c)}>
                  <span className={`ps-punto nivel-${c.nivel}`} />
                  <span className="ps-lista-nombre">{nombre(c)}</span>
                  <b>{Math.round(c.puntaje_total)}</b>
                </button>
              </li>
            ))}
          </ul>
          {filtrados.length > 8 && (
            <button type="button" className="ps-enlace" onClick={() => setVerMas(!verMas)}>
              {verMas ? 'Ver menos' : 'Ver más'}
            </button>
          )}
        </>
      )}
      {notas.map((n) => <p key={n} className="pd-nota">{n}</p>)}
    </div>
  );
}
