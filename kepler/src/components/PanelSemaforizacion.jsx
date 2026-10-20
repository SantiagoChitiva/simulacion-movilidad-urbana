import React, { useMemo, useState } from 'react';
import VistaCruce from './VistaCruce';

export const NIVELES = {
  prioritario: { etiqueta: 'Prioritario', ayuda: 'Estudiar primero', color: '#e5383b' },
  recomendado: { etiqueta: 'Recomendado', ayuda: 'Estudiar después', color: '#f77f00' },
  observacion: { etiqueta: 'En observación', ayuda: 'Hacer seguimiento', color: '#f6d581' },
};

// Tráfico de fondo por defecto de la zona (veh/h; peatones en personas/h)
export const INTENSIDADES_DEFECTO = { auto: 700, moto: 250, taxi: 120, bici: 60, bus: 30, peaton: 400 };
const ETIQUETAS = { auto: 'Carros', moto: 'Motos', taxi: 'Taxis', bici: 'Bicicletas', bus: 'Buses', peaton: 'Peatones' };

const nombre = (c) => (c.calles?.length ? c.calles.join(' × ') : `Cruce ${c.id}`);
const sinTildes = (t) => t.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

function Cifra({ titulo, valor }) {
  return (
    <div className="ps-cifra">
      <span>{titulo}</span>
      <b>{valor}</b>
    </div>
  );
}

/** Lo que se ve al elegir un cruce: por qué es candidato, cifras, el cruce en fotos y el botón al 3D. */
function TarjetaCruce({ cruce, periodoSiniestros, onVolver, onAbrir }) {
  const [intensidades, setIntensidades] = useState(INTENSIDADES_DEFECTO);
  const nivel = NIVELES[cruce.nivel] ?? { etiqueta: cruce.nivel, color: '#999' };
  const porque = [...(cruce.evidencias ?? []), ...(cruce.contexto ?? [])];
  const accesos = cruce.brazos || '—';
  const periodo = periodoSiniestros ? `${periodoSiniestros[0]}–${periodoSiniestros[1]}` : '';

  return (
    <article className="ps-tarjeta">
      <div className="ps-tarjeta-cab">
        <button type="button" className="ps-enlace" onClick={onVolver}>← Todos los cruces</button>
        <button type="button" className="ps-x" onClick={onVolver} aria-label="Cerrar">×</button>
      </div>
      <span className="ps-insignia" style={{ background: nivel.color }}>{nivel.etiqueta}</span>
      <h2 className="ps-titulo">{nombre(cruce)}</h2>
      {cruce.tipo_vias && <p className="ps-sub">{cruce.tipo_vias}</p>}

      <div className="ps-medida">
        <small>Medida sugerida para estudio</small>
        <b>{cruce.nivel === 'observacion' ? 'Seguimiento' : 'Semáforo vehicular'}</b>
        <span>{cruce.medida}</span>
        <button type="button" className="ps-primario" onClick={() => onAbrir(cruce, intensidades)}>
          ▶ Ver simulación: hoy y con semáforo
        </button>
        <details className="ps-intensidades">
          <summary>Ajustar el tráfico de fondo</summary>
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
            Vehículos (o peatones) por hora que se suman a los viajes de la encuesta que pasan por el cruce. Son un
            supuesto, no un aforo: la encuesta sola deja muy poco tráfico en una zona tan pequeña.
          </small>
        </details>
      </div>

      {porque.length > 0 && (
        <section>
          <h3>Por qué</h3>
          <ul className="ps-porque">
            {porque.map((e) => <li key={e}>{e}</li>)}
          </ul>
        </section>
      )}

      <div className="ps-cifras">
        <Cifra titulo="Siniestros" valor={cruce.siniestros ?? 0} />
        <Cifra titulo="Semáforo más cercano" valor={cruce.distancia_semaforo_m != null ? `${Math.round(cruce.distancia_semaforo_m)} m` : '—'} />
        <Cifra titulo="Accesos" valor={accesos} />
      </div>
      {cruce.siniestros > 0 && (
        <p className="pd-nota">
          Siniestros {periodo}: {cruce.siniestros_heridos ?? 0} con heridos, {cruce.siniestros_muertos ?? 0} con muertos
          (Secretaría Distrital de Movilidad).
        </p>
      )}
      {cruce.generadores_nombres?.length > 0 && (
        <p className="pd-nota">Cerca: {cruce.generadores_nombres.join(', ')}.</p>
      )}

      <VistaCruce lon={cruce.lon} lat={cruce.lat} />
    </article>
  );
}

/**
 * Pestaña Semaforizar, al estilo de Semáforos de Barranquilla: la lista de cruces sin
 * semáforo por prioridad y, al elegir uno, su tarjeta con el botón al simulador 3D.
 */
export default function PanelSemaforizacion({
  seleccionado, candidatos, notas = [], periodoSiniestros, totalSemaforizados,
  priorizacionVisible, semaforosVisibles, onMostrarPriorizacion, onAlternarSemaforos, onElegir, onAbrir,
}) {
  const [nivel, setNivel] = useState(null);   // null: prioritarios y recomendados (los del mapa)
  const [busqueda, setBusqueda] = useState('');
  const [cerca, setCerca] = useState(null);   // 'colegio' | 'salud' | null
  const [verMas, setVerMas] = useState(false);

  const conteo = useMemo(
    () => candidatos.reduce((acc, c) => ({ ...acc, [c.nivel]: (acc[c.nivel] ?? 0) + 1 }), {}),
    [candidatos]
  );
  const filtrados = useMemo(() => {
    const texto = sinTildes(busqueda.trim());
    return candidatos
      .filter((c) => (nivel ? c.nivel === nivel : c.nivel !== 'observacion'))
      .filter((c) => !texto || sinTildes(nombre(c)).includes(texto))
      .filter((c) => (cerca === 'colegio' ? c.colegios > 0 : cerca === 'salud' ? c.salud > 0 : true))
      .sort((a, b) => b.puntaje_total - a.puntaje_total);
  }, [candidatos, nivel, busqueda, cerca]);

  if (seleccionado) {
    return (
      <TarjetaCruce
        key={seleccionado.id}
        cruce={seleccionado}
        periodoSiniestros={periodoSiniestros}
        onVolver={() => onElegir(null, { centrar: false })}
        onAbrir={onAbrir}
      />
    );
  }

  const visibles = filtrados.slice(0, verMas ? 120 : 25);
  return (
    <div className="ps-panel">
      <h2 className="ps-titulo">Dónde estudiar un semáforo nuevo</h2>
      <p className="ps-sub">
        Cruces de Usaquén sin semáforo, ordenados por siniestros, tramos largos sin semáforo, colegios y centros de
        salud cerca y tráfico simulado.
      </p>
      <p className="ps-aviso">
        <strong>Proyecto académico, no oficial.</strong> Es una lista para priorizar estudios técnicos, no un dictamen:
        la decisión final requiere aforos y un estudio de tránsito.
      </p>

      {!priorizacionVisible && (
        <button type="button" className="ps-primario" onClick={onMostrarPriorizacion}>
          Mostrar los cruces en el mapa
        </button>
      )}

      <ul className="ps-niveles">
        {Object.entries(NIVELES).map(([id, n]) => (
          <li key={id}>
            <button type="button" className={nivel === id ? 'activo' : ''} aria-pressed={nivel === id} onClick={() => setNivel(nivel === id ? null : id)}>
              <span className="ps-punto" style={{ background: n.color }} />
              <span className="ps-nivel-texto">
                <b>{n.etiqueta}</b>
                <small>{n.ayuda}</small>
              </span>
              <span className="ps-conteo">{conteo[id] ?? 0}</span>
            </button>
          </li>
        ))}
        <li>
          <button type="button" className={semaforosVisibles ? 'activo' : ''} aria-pressed={semaforosVisibles} onClick={onAlternarSemaforos}>
            <span className="ps-punto semaforo" />
            <span className="ps-nivel-texto">
              <b>Con semáforo</b>
              <small>{semaforosVisibles ? 'Ocultar del mapa' : 'Ver en el mapa'}</small>
            </span>
            <span className="ps-conteo">{totalSemaforizados ?? ''}</span>
          </button>
        </li>
      </ul>

      <input
        type="search"
        className="ps-buscar"
        placeholder="Buscar calle o carrera…"
        value={busqueda}
        onChange={(e) => setBusqueda(e.target.value)}
        aria-label="Buscar calle o carrera"
      />
      <div className="ps-chips">
        {[['colegio', 'Cerca de colegio'], ['salud', 'Cerca de hospital']].map(([id, et]) => (
          <button key={id} type="button" className={cerca === id ? 'activo' : ''} aria-pressed={cerca === id} onClick={() => setCerca(cerca === id ? null : id)}>
            {et}
          </button>
        ))}
      </div>

      <h3 className="ps-lista-cab">
        <span>{nivel ? NIVELES[nivel].etiqueta : 'Cruces por prioridad'}</span>
        <span>{filtrados.length}</span>
      </h3>
      {candidatos.length === 0 && <p className="pd-nota">Activa la capa para cargar la lista de cruces.</p>}
      <ul className="ps-lista">
        {visibles.map((c) => (
          <li key={c.id}>
            <button type="button" onClick={() => onElegir(c, { centrar: true })}>
              <span className="ps-punto" style={{ background: NIVELES[c.nivel]?.color }} />
              <span className="ps-lista-nombre">
                {nombre(c)}
                <small>{c.evidencias?.[0] ?? c.contexto?.[0]}</small>
              </span>
            </button>
          </li>
        ))}
      </ul>
      {filtrados.length > visibles.length && (
        <button type="button" className="ps-enlace" onClick={() => setVerMas(true)}>Ver más</button>
      )}
      <details className="ps-como">
        <summary>Cómo se hizo</summary>
        <p>
          Se siguen las reglas del proyecto Semáforos de Barranquilla. Un cruce entra a la lista si una vía colectora o
          mayor cruza otra calle a nivel, si desde la calle secundaria se cruza o se gira a la izquierda y si no hay un
          semáforo a menos de 80 m. Luego se miran tres señales, comparadas con los cruces que ya tienen semáforo:
          siniestros registrados por la Secretaría de Movilidad, tramos largos sin semáforo y el tráfico que entra en
          la simulación. Dos señales fuertes lo vuelven prioritario y una, recomendado.
        </p>
      </details>
      {notas.map((n) => <p key={n} className="pd-nota">{n}</p>)}
    </div>
  );
}
