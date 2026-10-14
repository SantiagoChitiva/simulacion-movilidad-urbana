import React from 'react';

const COLOR_RIESGO = { bajo: '#2ecc71', medio: '#ffb300', alto: '#ff3b30' };
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

const n = (v, d = 0) => (v == null ? '—' : Number(v).toFixed(d));

function Velocimetro({ kmh, limite }) {
  const max = 80;
  const frac = Math.min((kmh ?? 0) / max, 1);
  const ang = -120 + 240 * frac;
  const exceso = limite != null && kmh > limite + 2;
  const arco = (a0, a1) => {
    const p = (a) => [50 + 40 * Math.sin((a * Math.PI) / 180), 55 - 40 * Math.cos((a * Math.PI) / 180)];
    const [x0, y0] = p(a0);
    const [x1, y1] = p(a1);
    return `M ${x0} ${y0} A 40 40 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
  };
  return (
    <svg viewBox="0 0 100 80" className="hud-velocimetro" aria-label={`Velocidad ${n(kmh)} km/h`}>
      <path d={arco(-120, 120)} className="hud-vel-fondo" />
      <path d={arco(-120, ang)} className="hud-vel-valor" style={{ stroke: exceso ? '#ff3b30' : '#00e5ff' }} />
      {limite != null && (
        <line
          x1={50 + 34 * Math.sin(((-120 + 240 * Math.min(limite / max, 1)) * Math.PI) / 180)}
          y1={55 - 34 * Math.cos(((-120 + 240 * Math.min(limite / max, 1)) * Math.PI) / 180)}
          x2={50 + 46 * Math.sin(((-120 + 240 * Math.min(limite / max, 1)) * Math.PI) / 180)}
          y2={55 - 46 * Math.cos(((-120 + 240 * Math.min(limite / max, 1)) * Math.PI) / 180)}
          className="hud-vel-limite"
        />
      )}
      <text x="50" y="55" className="hud-vel-numero">{n(kmh)}</text>
      <text x="50" y="68" className="hud-vel-unidad">km/h{limite != null ? ` · máx ${n(limite)}` : ''}</text>
    </svg>
  );
}

function Sparkline({ historial }) {
  if (!historial?.length) return null;
  const w = 120;
  const h = 26;
  const pts = historial.map((p, i) => `${(i / Math.max(historial.length - 1, 1)) * w},${h - (p.indice / 100) * h}`).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="hud-spark" preserveAspectRatio="none" aria-hidden="true">
      <line x1="0" x2={w} y1={h * 0.4} y2={h * 0.4} className="hud-spark-umbral" />
      <polyline points={pts} />
    </svg>
  );
}

/** Capa de datos sobre la vista 3D de un lado. */
export default function HUD({ titulo, subtitulo, conSemaforo, lado, egoId }) {
  const ego = lado?.ego;
  const m = lado?.metricas;
  const luces = lado?.luces;
  const riesgo = ego?.riesgo;
  return (
    <div className="hud">
      <div className="hud-titulo">
        <span className={`hud-chip ${conSemaforo ? 'con' : 'sin'}`}>{titulo}</span>
        <span className="hud-subtitulo">{subtitulo}</span>
        {luces && (
          <span className="hud-fase" title="Fase del semáforo propuesto y segundos para el cambio">
            Fase {luces.fase + 1} · {n(luces.restante)} s
          </span>
        )}
      </div>

      {m && (
        <div className="hud-metricas" aria-label="Métricas del cruce">
          <span title="Vehículos a menos de 60 m del cruce">En el cruce <b>{m.en_cruce}</b></span>
          <span title="Vehículos detenidos a menos de 60 m del cruce">Detenidos <b>{m.detenidos_cruce}</b></span>
          <span title="Espera media de los vehículos que han pasado por el cruce">Espera media <b>{n(m.espera_media_cruce_s, 1)} s</b></span>
          <span title="Pares de vehículos que llegan al punto de cruce con menos de 1,5 s de diferencia (PET)">Conflictos <b>{m.conflictos}</b></span>
          <span title="Colisiones detectadas por SUMO">Choques <b>{m.colisiones}</b></span>
          <span title="Vehículos y peatones en la zona">Zona <b>{m.vehiculos}</b> veh · <b>{m.peatones}</b> peat.</span>
        </div>
      )}

      {!egoId && <div className="hud-vacio">Elige o lanza un actor para seguirlo en tercera persona.</div>}
      {egoId && !ego && <div className="hud-vacio">El actor seguido no está en este escenario ahora (aún no entra o ya salió).</div>}

      {ego && (
        <div className="hud-ego">
          <div className="hud-col">
            <div className="hud-actor">
              <b>{ETIQUETA_TIPO[ego.tipo] ?? ego.tipo}</b> <span className="hud-id">{ego.id}</span>
            </div>
            <Velocimetro kmh={ego.velocidad_kmh} limite={ego.limite_kmh} />
            <div className={`hud-accion accion-${ego.accion.codigo}`}>{ego.accion.texto}</div>
          </div>

          <div className="hud-col hud-col-datos">
            {riesgo && (
              <div className="hud-riesgo">
                <div className="hud-riesgo-cab">
                  <span>Riesgo</span>
                  <b style={{ color: COLOR_RIESGO[riesgo.nivel] }}>{riesgo.indice} · {riesgo.nivel}</b>
                </div>
                <div className="hud-barra"><span style={{ width: `${riesgo.indice}%`, background: COLOR_RIESGO[riesgo.nivel] }} /></div>
                <div className="hud-causa">{riesgo.causa}</div>
                <Sparkline historial={ego.historial_riesgo} />
              </div>
            )}
            <dl className="hud-tabla">
              {ego.aceleracion != null && (<><dt>Aceleración</dt><dd>{n(ego.aceleracion, 2)} m/s²</dd></>)}
              {ego.gap_m != null && (<><dt>Distancia al de adelante</dt><dd>{n(ego.gap_m, 1)} m</dd></>)}
              {riesgo?.ttc != null && (<><dt>TTC</dt><dd>{n(riesgo.ttc, 1)} s</dd></>)}
              {riesgo?.drac != null && (<><dt>DRAC</dt><dd>{n(riesgo.drac, 2)} m/s²</dd></>)}
              {riesgo?.pet != null && (<><dt>PET en el cruce</dt><dd>{n(riesgo.pet, 1)} s</dd></>)}
              {ego.dist_vehiculo_m != null && (<><dt>Vehículo más cercano</dt><dd>{n(ego.dist_vehiculo_m, 1)} m</dd></>)}
              <dt>Espera</dt><dd>{n(ego.espera_s)} s{ego.espera_acum_s != null ? ` (total ${n(ego.espera_acum_s)} s)` : ''}</dd>
              {ego.perdida_s != null && (<><dt>Tiempo perdido</dt><dd>{n(ego.perdida_s, 1)} s</dd></>)}
              {ego.semaforo && (
                <><dt>Próximo semáforo</dt><dd><i className="hud-punto" style={{ background: COLOR_ESTADO(ego.semaforo.estado) }} /> a {n(ego.semaforo.distancia_m)} m</dd></>
              )}
            </dl>
          </div>

          {(ego.opciones?.length > 0 || ego.intenciones_cambio?.length > 0) && (
            <div className="hud-col hud-decisiones">
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
              {ego.intenciones_cambio?.map((c) => (
                <div key={c.hacia} className="hud-intencion">
                  Quiere pasarse a la {c.hacia} para {c.motivo}{c.bloqueado ? ' (bloqueado)' : ''}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
