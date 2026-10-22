import React, { useState } from 'react';

const COLOR_RIESGO = { bajo: '#2ecc71', medio: '#ffb300', alto: '#ff3b30' };
const NIVEL_RIESGO = { bajo: 'riesgo bajo', medio: 'riesgo moderado', alto: 'riesgo alto' };
const FLECHA = { s: '↑', l: '←', r: '→', t: '↶', L: '↖', R: '↗', invalid: '×' };
const COLOR_ESTADO = (e) => {
  if (e === 'G' || e === 'O' || e === 'M') return '#2ecc71';
  if (e === 'g' || e === 'm' || e === '=' || e === 'o') return '#c6e377';
  if (e === 'y' || e === 'Y' || e === 'u') return '#ffb300';
  if (e === 'r' || e === 'R' || e === 's') return '#ff3b30';
  return '#9aa4ad';
};
const ETIQUETA_TIPO = {
  auto: 'Carro', taxi: 'Taxi', moto: 'Moto', bici: 'Bicicleta', bus_pt: 'Bus', escolar: 'Bus escolar',
  especial: 'Vehículo especial', informal: 'Transporte informal', otro: 'Otro vehículo', peaton: 'Peatón',
};

// texto corto del estado del actor, como en la referencia ("En camino", "Espera el verde"…)
const ESTADO = {
  acelera: 'En camino', crucero: 'En camino', camina: 'Caminando', frena: 'Frenando', frena_cruce: 'Frena antes del cruce',
  cede_paso: 'Cede el paso', en_cola: 'En la fila', espera_cruzar: 'Espera para cruzar', frenada_fuerte: '¡Frenada fuerte!',
  frena_semaforo: 'Frena: semáforo', espera_semaforo: 'Espera el verde', cambia_carril: 'Cambia de carril',
  detenido: 'Detenido', esperando_entrar: 'Esperando entrar',
};

const n = (v, d = 0) => (v == null ? '—' : Number(v).toFixed(d));
const mmss = (s) => `${Math.floor((s ?? 0) / 60)}:${String(Math.floor((s ?? 0) % 60)).padStart(2, '0')}`;

function Sparkline({ historial }) {
  if (!historial?.length) return null;
  const w = 160;
  const h = 28;
  const pts = historial.map((p, i) => `${(i / Math.max(historial.length - 1, 1)) * w},${h - (p.indice / 100) * h}`).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="hud-spark" preserveAspectRatio="none" aria-hidden="true">
      <line x1="0" x2={w} y1={h * 0.4} y2={h * 0.4} className="hud-spark-umbral" />
      <polyline points={pts} />
    </svg>
  );
}

function causaRiesgo(r) {
  if (!r) return 'midiendo…';
  if (r.ttc != null && r.ttc < 4) return `TTC ${n(r.ttc, 1)} s`;
  if (r.pet != null && r.pet < 4) return `PET ${n(r.pet, 1)} s`;
  if (r.drac != null && r.drac > 0.5) return `DRAC ${n(r.drac, 1)} m/s²`;
  return r.causa ?? 'sin conflictos';
}

/** Capa de datos sobre la vista 3D de un lado. */
export default function HUD({ conSemaforo, lado, egoId, manual, subtitulo }) {
  const [detalle, setDetalle] = useState(false);
  const ego = lado?.ego;
  const m = lado?.metricas;
  const luces = lado?.luces;
  const riesgo = ego?.riesgo;
  const estado = ego ? ESTADO[ego.accion.codigo] ?? ego.accion.texto : null;

  return (
    <div className="hud">
      <div className="hud-pildora" title={subtitulo}>
        <i className={`hud-punto-estado ${conSemaforo ? 'con' : 'sin'}`} />
        <b>{conSemaforo ? 'CON SEMÁFORO' : 'SIN SEMÁFORO'}</b>
        {m && (
          <>
            <span title="Espera más larga de un vehículo en la vía que cede (la secundaria)">espera lateral {mmss(m.espera_lateral_s)}</span>
            <span title="Colisiones detectadas por SUMO">{m.colisiones} choque{m.colisiones === 1 ? '' : 's'}</span>
            <span title="Pares de vehículos que llegan al punto de cruce con menos de 1,5 s de diferencia (PET)">{m.conflictos} conflicto{m.conflictos === 1 ? '' : 's'}</span>
          </>
        )}
        {luces && <span className="hud-fase" title="Fase del semáforo propuesto y segundos para el cambio">fase {luces.fase + 1} · {n(luces.restante)} s</span>}
      </div>

      {!egoId && <div className="hud-vacio">Lanza un actor o sigue uno que ya circula (panel de la izquierda).</div>}
      {egoId && !ego && <div className="hud-vacio">El actor seguido no está en este escenario ahora (ya salió o aún no entra).</div>}

      {ego && detalle && (
        <div className="hud-detalle">
          <div className="hud-detalle-cab">
            <b>{ETIQUETA_TIPO[ego.tipo] ?? ego.tipo}</b> <span className="hud-id">{ego.id}</span>
            <span className="hud-texto-accion">{ego.accion.texto}</span>
          </div>
          {riesgo && (
            <>
              <div className="hud-causa">{riesgo.causa}</div>
              <Sparkline historial={ego.historial_riesgo} />
            </>
          )}
          <dl className="hud-tabla">
            {ego.limite_kmh != null && (<><dt>Velocidad máxima</dt><dd>{n(ego.limite_kmh)} km/h</dd></>)}
            {ego.aceleracion != null && (<><dt>Aceleración</dt><dd>{n(ego.aceleracion, 2)} m/s²</dd></>)}
            {ego.gap_m != null && (<><dt>Distancia al de adelante</dt><dd>{n(ego.gap_m, 1)} m</dd></>)}
            {riesgo?.ttc != null && (<><dt>TTC</dt><dd>{n(riesgo.ttc, 1)} s</dd></>)}
            {riesgo?.drac != null && (<><dt>DRAC</dt><dd>{n(riesgo.drac, 2)} m/s²</dd></>)}
            {riesgo?.pet != null && (<><dt>PET en el cruce</dt><dd>{n(riesgo.pet, 1)} s</dd></>)}
            {ego.dist_vehiculo_m != null && (<><dt>Vehículo más cercano</dt><dd>{n(ego.dist_vehiculo_m, 1)} m</dd></>)}
            {ego.espera_s != null && (<><dt>Espera</dt><dd>{n(ego.espera_s)} s{ego.espera_acum_s != null ? ` (total ${n(ego.espera_acum_s)} s)` : ''}</dd></>)}
            {ego.perdida_s != null && (<><dt>Tiempo perdido</dt><dd>{n(ego.perdida_s, 1)} s</dd></>)}
            {ego.semaforo && (
              <><dt>Próximo semáforo</dt><dd><i className="hud-punto" style={{ background: COLOR_ESTADO(ego.semaforo.estado) }} /> a {n(ego.semaforo.distancia_m)} m</dd></>
            )}
            {m && (<><dt>En el cruce / detenidos</dt><dd>{m.en_cruce} / {m.detenidos_cruce}</dd></>)}
            {m && (<><dt>Espera media en el cruce</dt><dd>{n(m.espera_media_cruce_s, 1)} s</dd></>)}
          </dl>
          {ego.opciones?.length > 0 && (
            <div className="hud-decisiones">
              <div className="hud-subcab">Decisiones en el próximo cruce</div>
              <ul>
                {ego.opciones.map((o, i) => (
                  <li key={`${o.direccion}-${i}`} className={o.direccion === ego.giro_elegido ? 'elegida' : ''}>
                    <span className="hud-flecha" style={{ color: COLOR_ESTADO(o.estado) }}>{FLECHA[o.direccion] ?? '·'}</span>
                    <span>
                      {o.etiqueta}
                      <small>
                        {o.estado_etiqueta}
                        {o.conflicto ? ' · tráfico en conflicto' : ''}
                        {!o.puede_pasar ? ' · debe esperar' : ''}
                      </small>
                    </span>
                    {o.direccion === ego.giro_elegido && <em>su ruta</em>}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {ego.intenciones_cambio?.map((c) => (
            <div key={c.hacia} className="hud-intencion">
              Quiere pasarse a la {c.hacia} para {c.motivo}{c.bloqueado ? ' (bloqueado)' : ''}
            </div>
          ))}
        </div>
      )}

      {ego && (
        <button type="button" className="hud-tarjeta" onClick={() => setDetalle(!detalle)} aria-expanded={detalle} title="Ver detalle">
          <span className="hud-kmh">
            <b>{n(ego.velocidad_kmh)}</b>
            <small>km/h</small>
          </span>
          <span className={`hud-modo ${manual ? 'manual' : ''}`}>{manual ? '✋ Manual' : '✦ Auto'}</span>
          <span className="hud-estado">
            <b>{estado}</b>
            <span className="hud-barra-riesgo"><span style={{ left: `${Math.min(riesgo?.indice ?? 0, 100)}%` }} /></span>
            <small style={{ color: riesgo ? COLOR_RIESGO[riesgo.nivel] : undefined }}>
              {riesgo ? NIVEL_RIESGO[riesgo.nivel] : 'riesgo —'} · {causaRiesgo(riesgo)}
            </small>
          </span>
          {ego.opciones?.length > 0 && (
            <span className="hud-giros" aria-label="Giros posibles en el próximo cruce">
              {ego.opciones.map((o, i) => (
                <i key={`${o.direccion}-${i}`} className={o.direccion === ego.giro_elegido ? 'elegido' : ''} style={{ color: COLOR_ESTADO(o.estado) }}>
                  {FLECHA[o.direccion] ?? '·'}
                </i>
              ))}
            </span>
          )}
        </button>
      )}
    </div>
  );
}
