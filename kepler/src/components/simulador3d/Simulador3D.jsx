import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ETAPA_COMPARACION, cerrarComparacion3D, crearComparacion3D, obtenerComparacion3D,
  obtenerGeometriaComparacion3D, urlWsComparacion3D,
} from '../../api';
import Escena3D from './escena';
import HUD from './HUD';
import Minimapa from './Minimapa';

const TIPOS = [
  ['auto', 'Carro'], ['moto', 'Moto'], ['taxi', 'Taxi'], ['bici', 'Bicicleta'], ['bus_pt', 'Bus'], ['peaton', 'Peatón'],
];
const ESTILOS = [['normal', 'Normal'], ['agresivo', 'Agresivo'], ['cauteloso', 'Cauteloso']];
const GIRO = { s: 'Recto', l: 'Izquierda', r: 'Derecha', L: 'Izquierda leve', R: 'Derecha leve' };
const VELOCIDADES = [0.5, 1, 2, 5, 10];
const PERIODOS = [1, 2, 5, 10];
const CAMARAS = [['persecucion', '3ª persona'], ['aerea', 'Aérea']];
const VISTAS = [['comparar', 'Comparar'], ['a', 'Sin semáforo'], ['b', 'Con semáforo']];
const NIVEL = { prioritario: 'CRUCE PRIORITARIO', recomendado: 'CRUCE RECOMENDADO', observacion: 'EN OBSERVACIÓN' };

// teclas del modo manual
const TECLAS_ACELERAR = { KeyW: 1, ArrowUp: 1, KeyS: -1, ArrowDown: -1, Space: -1 };
const TECLAS_GIRO = { KeyA: 'l', ArrowLeft: 'l', KeyD: 'r', ArrowRight: 'r', KeyX: 's' };

const hora = (t) => {
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = Math.floor(t % 60);
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
};

const distancia2 = (a, x, y) => (a[2] - x) ** 2 + (a[3] - y) ** 2;
const nombreCruce = (c) => (c.calles?.length ? c.calles.join(' × ') : `Cruce ${c.id}`);

/**
 * Simulador 3D comparativo de un cruce sin semáforo.
 * Izquierda: el cruce como está hoy. Derecha: el mismo cruce con el semáforo propuesto.
 * Ambos lados corren la misma demanda en lockstep y siguen al mismo actor.
 */
export default function Simulador3D({ cruce, candidatos = [], corrida, intensidades, onCambiarCruce, onCerrar }) {
  const refA = useRef(null);
  const refB = useRef(null);
  const escenas = useRef({ a: null, b: null });
  const ws = useRef(null);
  const cidRef = useRef(null);

  const [fase, setFase] = useState('preparando');
  const [etapa, setEtapa] = useState('preparando');
  const [mensaje, setMensaje] = useState(null);
  const [error, setError] = useState(null);
  const [info, setInfo] = useState(null);
  const [geometria, setGeometria] = useState(null);
  const [frame, setFrame] = useState(null);
  const [ego, setEgo] = useState(null);
  const [aviso, setAviso] = useState(null);

  const [pausada, setPausada] = useState(false);
  const [velocidad, setVelocidad] = useState(1);
  const [periodo, setPeriodo] = useState(2);
  const [camara, setCamara] = useState('persecucion');
  const [vista, setVista] = useState('comparar');
  const [manual, setManual] = useState(false);
  const [tipo, setTipo] = useState('auto');
  const [estilo, setEstilo] = useState('normal');
  const [acceso, setAcceso] = useState('');
  const [giro, setGiro] = useState('s');
  const [via, setVia] = useState('');
  const [panelAbierto, setPanelAbierto] = useState(true);
  const [conectar, setConectar] = useState(false);

  const egoRef = useRef(null);
  egoRef.current = ego;

  const ranking = useMemo(
    () => [...candidatos].sort((p, q) => q.puntaje_total - p.puntaje_total),
    [candidatos]
  );
  const cartel = useMemo(() => {
    const puesto = ranking.findIndex((c) => c.id === cruce.id);
    const nivel = NIVEL[cruce.nivel] ?? 'CRUCE CANDIDATO';
    const detalle = [
      cruce.puntaje_total != null ? `Puntaje ${Math.round(cruce.puntaje_total)}` : null,
      cruce.siniestros ? `${cruce.siniestros} siniestros` : null,
      cruce.generadores ? `${cruce.generadores} colegios/salud` : null,
    ].filter(Boolean).join(' · ');
    return {
      titulo: puesto >= 0 ? `${nivel} #${puesto + 1}` : nivel,
      subtitulo: nombreCruce(cruce),
      detalle: detalle || 'Semáforo propuesto en estudio',
    };
  }, [cruce, ranking]);

  // 1. preparar la zona (recorte + demanda + semáforo propuesto) y esperar
  useEffect(() => {
    let vivo = true;
    setFase('preparando');
    setGeometria(null);
    setFrame(null);
    setEgo(null);
    setConectar(false);
    (async () => {
      try {
        const comp = await crearComparacion3D(cruce.id, { lon: cruce.lon, lat: cruce.lat, corrida, intensidades, nodos: cruce.nodos });
        cidRef.current = comp.id;
        let estado = comp;
        while (vivo && estado.estado === 'preparando') {
          setEtapa(estado.etapa ?? 'preparando');
          await new Promise((r) => setTimeout(r, 1000));
          estado = await obtenerComparacion3D(comp.id);
        }
        if (!vivo) return;
        if (estado.estado === 'error') throw new Error(estado.error ?? 'Error desconocido al preparar la zona');
        setInfo(estado.info);
        const geo = await obtenerGeometriaComparacion3D(comp.id);
        if (!vivo) return;
        setGeometria(geo);
        if (geo.accesos.length) {
          setAcceso(geo.accesos[0].edge);
          setGiro(geo.accesos[0].giros[0]?.direccion ?? 's');
        }
        setFase('conectando');
        setConectar(true);
      } catch (e) {
        if (vivo) {
          setError(e.message);
          setFase('error');
        }
      }
    })();
    return () => {
      vivo = false;
      if (cidRef.current) cerrarComparacion3D(cidRef.current).catch(() => {});
      cidRef.current = null;
    };
  }, [cruce, corrida, intensidades]);

  // 2. armar las dos escenas y el bucle de render
  useEffect(() => {
    if (!geometria || !refA.current || !refB.current) return undefined;
    const a = new Escena3D(refA.current, geometria, { conSemaforo: false, cartel });
    const b = new Escena3D(refB.current, geometria, { conSemaforo: true, cartel });
    escenas.current = { a, b };
    a.mirarA(geometria.nodo.x, geometria.nodo.y, geometria.nodo.z);
    b.mirarA(geometria.nodo.x, geometria.nodo.y, geometria.nodo.z);

    const observador = new ResizeObserver(() => {
      a.redimensionar();
      b.redimensionar();
    });
    observador.observe(refA.current);
    observador.observe(refB.current);

    let anim;
    let previo = performance.now();
    const bucle = (ahora) => {
      const dt = Math.min((ahora - previo) / 1000, 0.1);
      previo = ahora;
      // un lado oculto (vista de un solo escenario) no se dibuja
      if (refA.current?.clientWidth) a.render(dt);
      if (refB.current?.clientWidth) b.render(dt);
      anim = requestAnimationFrame(bucle);
    };
    anim = requestAnimationFrame(bucle);
    return () => {
      cancelAnimationFrame(anim);
      observador.disconnect();
      a.destruir();
      b.destruir();
      escenas.current = { a: null, b: null };
    };
  }, [geometria, cartel]);

  // 3. WebSocket: frames → escenas + HUD
  useEffect(() => {
    if (!conectar || !cidRef.current) return undefined;
    const socket = new WebSocket(urlWsComparacion3D(cidRef.current));
    ws.current = socket;
    socket.onmessage = (ev) => {
      let msg;
      try {
        msg = JSON.parse(ev.data);
      } catch {
        return;
      }
      if (msg.tipo === 'frame') {
        const { a, b } = escenas.current;
        const egoActual = egoRef.current;
        a?.actualizarActores(msg.lados.a.vehiculos, msg.lados.a.personas, egoActual);
        b?.actualizarActores(msg.lados.b.vehiculos, msg.lados.b.personas, egoActual);
        b?.actualizarLuces(msg.lados.b.luces);
        setFrame(msg);
        setFase('en_vivo');
        setMensaje(null);
      } else if (msg.tipo === 'estado') {
        setMensaje(msg.mensaje);
      } else if (msg.tipo === 'ego') {
        setEgo(msg.id);
        setAviso(null);
      } else if (msg.tipo === 'giro') {
        setAviso(`Tomará ${GIRO[msg.direccion]?.toLowerCase() ?? msg.direccion} en el próximo cruce (en los dos escenarios).`);
      } else if (msg.tipo === 'aviso') {
        setAviso(msg.mensaje);
      } else if (msg.tipo === 'error') {
        setError(msg.mensaje);
        setFase('error');
      } else if (msg.tipo === 'fin') {
        setFase('fin');
      }
    };
    socket.onerror = () => setError('Se perdió la conexión con la simulación.');
    return () => {
      socket.close();
      ws.current = null;
    };
  }, [conectar]);

  const enviar = useCallback((cmd) => {
    if (ws.current?.readyState === WebSocket.OPEN) ws.current.send(JSON.stringify(cmd));
  }, []);

  useEffect(() => {
    escenas.current.a?.setModoCamara(camara);
    escenas.current.b?.setModoCamara(camara);
  }, [camara, geometria]);

  // 4. modo manual: teclado → comandos (el backend los aplica igual en los dos lados)
  useEffect(() => {
    if (!manual) return undefined;
    const pulsadas = new Set();
    const acelerar = () => {
      let valor = 0;
      for (const k of pulsadas) valor = TECLAS_ACELERAR[k] < 0 ? -1 : Math.max(valor, TECLAS_ACELERAR[k] ?? 0);
      enviar({ control: { acelerar: valor } });
    };
    const abajo = (e) => {
      if (e.target instanceof HTMLSelectElement || e.target instanceof HTMLInputElement) return;
      if (e.code in TECLAS_ACELERAR) {
        e.preventDefault();
        if (!pulsadas.has(e.code)) {
          pulsadas.add(e.code);
          acelerar();
        }
      } else if (e.code in TECLAS_GIRO && !e.repeat) {
        e.preventDefault();
        enviar({ giro: TECLAS_GIRO[e.code] });
      }
    };
    const arriba = (e) => {
      if (pulsadas.delete(e.code)) acelerar();
    };
    window.addEventListener('keydown', abajo);
    window.addEventListener('keyup', arriba);
    return () => {
      window.removeEventListener('keydown', abajo);
      window.removeEventListener('keyup', arriba);
      enviar({ control: { acelerar: 0 } });
    };
  }, [manual, enviar]);

  const alternarManual = (valor) => {
    setManual(valor);
    enviar({ manual: valor });
    if (valor) setCamara('persecucion');
  };

  const accesoSel = geometria?.accesos.find((x) => x.edge === acceso);
  const viaSel = geometria?.vias.find((v) => v.nombre === via);

  // al seguir a alguien el panel se pliega para dejar ver la escena y el detalle del HUD
  const lanzarActor = () => {
    enviar({ inyectar: { tipo, acceso, giro, estilo } });
    setCamara('persecucion');
    setPanelAbierto(false);
  };

  const seguir = (id) => {
    setEgo(id);
    enviar({ seguir: id });
    if (id) {
      setCamara('persecucion');
      setPanelAbierto(false);
    }
  };

  const enLaVia = useMemo(() => {
    if (!frame || !viaSel) return [];
    const edges = new Set(viaSel.edges);
    const lado = frame.lados.a;
    return [...lado.vehiculos, ...lado.personas].filter((x) => edges.has(x[7])).slice(0, 14);
  }, [frame, viaSel]);

  const masCercano = () => {
    if (!frame || !geometria) return;
    const { x, y } = geometria.nodo;
    const lado = frame.lados.a;
    const enB = new Set([...frame.lados.b.vehiculos, ...frame.lados.b.personas].map((act) => act[0]));
    const candidatosEgo = [...lado.vehiculos, ...lado.personas].filter((act) => enB.has(act[0]));
    if (!candidatosEgo.length) return;
    candidatosEgo.sort((p, q) => distancia2(p, x, y) - distancia2(q, x, y));
    seguir(candidatosEgo[0][0]);
  };

  const irAVia = (nombre) => {
    setVia(nombre);
    const v = geometria?.vias.find((x) => x.nombre === nombre);
    if (!v?.centro) return;
    for (const esc of Object.values(escenas.current)) esc?.mirarA(...v.centro);
    if (!ego) setCamara('aerea');
  };

  const egoMapa = frame?.lados.a.ego ?? frame?.lados.b.ego ?? null;
  const rumboEgo = useMemo(() => {
    if (!frame || !ego) return null;
    for (const lado of [frame.lados.a, frame.lados.b]) {
      const act = [...lado.vehiculos, ...lado.personas].find((x) => x[0] === ego);
      if (act) return act[5];
    }
    return null;
  }, [frame, ego]);
  const tipoActual = geometria?.nodo.tipo_actual === 'priority' ? 'cruce con prioridad (la secundaria cede)'
    : geometria?.nodo.tipo_actual === 'right_before_left' ? 'prioridad a la derecha' : geometria?.nodo.tipo_actual ?? '';

  return (
    <div className="sim3d" role="dialog" aria-label="Simulador 3D: con y sin semáforo">
      <header className="sim3d-barra">
        <div className="sim3d-titulo">
          {ranking.length > 1 && onCambiarCruce ? (
            <select
              className="sim3d-selector-cruce" value={cruce.id} aria-label="Cruce a simular"
              onChange={(e) => onCambiarCruce(ranking.find((c) => c.id === e.target.value))}
            >
              {!ranking.some((c) => c.id === cruce.id) && <option value={cruce.id}>{nombreCruce(cruce)}</option>}
              {ranking.slice(0, 60).map((c, i) => <option key={c.id} value={c.id}>#{i + 1} {nombreCruce(c)}</option>)}
            </select>
          ) : (
            <strong>{nombreCruce(cruce)}</strong>
          )}
          <span>
            {info ? `Demanda ${info.fuente_demanda === 'sintetica' ? 'sintética' : info.fuente_demanda === 'real' ? 'real' : 'real + fondo sintético'}` : 'Preparando…'}
            {info?.ciclo_s ? ` · semáforo propuesto: ${info.fases} fases, ciclo ${Math.round(info.ciclo_s)} s` : ''}
            {frame ? ` · ${hora(frame.t)}` : ''}
          </span>
        </div>

        <div className="sim3d-grupo sim3d-pildoras" role="group" aria-label="Quién maneja">
          <button type="button" className={!manual ? 'activo rojo' : ''} onClick={() => alternarManual(false)} disabled={fase !== 'en_vivo'}>✦ Auto</button>
          <button type="button" className={manual ? 'activo rojo' : ''} onClick={() => alternarManual(true)} disabled={fase !== 'en_vivo'}>✋ Manual</button>
        </div>
        <div className="sim3d-grupo sim3d-pestanas" role="tablist" aria-label="Vista">
          {VISTAS.map(([id, etiqueta]) => (
            <button key={id} type="button" role="tab" aria-selected={vista === id} className={vista === id ? 'activo' : ''} onClick={() => setVista(id)}>
              {etiqueta}
            </button>
          ))}
        </div>

        <div className="sim3d-controles-top">
          <button type="button" onClick={() => { setPausada(!pausada); enviar({ pausa: !pausada }); }} disabled={fase !== 'en_vivo'} aria-label={pausada ? 'Continuar' : 'Pausar'}>
            {pausada ? '▶' : '⏸'}
          </button>
          <div className="sim3d-grupo" role="group" aria-label="Velocidad">
            {VELOCIDADES.map((v) => (
              <button key={v} type="button" className={velocidad === v ? 'activo' : ''} onClick={() => { setVelocidad(v); enviar({ velocidad: v }); }}>
                {v}×
              </button>
            ))}
          </div>
          <div className="sim3d-grupo" role="group" aria-label="Cámara">
            {CAMARAS.map(([id, etiqueta]) => (
              <button key={id} type="button" className={camara === id ? 'activo' : ''} onClick={() => setCamara(id)}>
                {etiqueta}
              </button>
            ))}
          </div>
          <button type="button" className="sim3d-cerrar" onClick={onCerrar} aria-label="Cerrar simulador">×</button>
        </div>
      </header>

      <div className="sim3d-cuerpo">
        <div className={`sim3d-vistas vista-${vista}`}>
          <section className="sim3d-vista" aria-label="Sin semáforo (actual)">
            <div ref={refA} className="sim3d-lienzo" />
            {geometria && <HUD conSemaforo={false} lado={frame?.lados.a} egoId={ego} manual={manual} subtitulo={`Hoy: ${tipoActual}`} />}
          </section>
          <section className="sim3d-vista" aria-label="Con semáforo propuesto">
            <div ref={refB} className="sim3d-lienzo" />
            {geometria && <HUD conSemaforo lado={frame?.lados.b} egoId={ego} manual={manual} subtitulo="Programa de tiempos fijos generado por netconvert" />}
          </section>
        </div>

        {geometria && <Minimapa nodo={geometria.nodo} bbox={geometria.bbox_lonlat} ego={egoMapa} egoId={ego} rumbo={camara === 'persecucion' ? rumboEgo : 0} />}

        {manual && fase === 'en_vivo' && (
          <div className="sim3d-teclas" aria-live="polite">
            {ego ? (
              <><kbd>W</kbd>/<kbd>↑</kbd> acelera · <kbd>S</kbd>/<kbd>↓</kbd>/<kbd>Espacio</kbd> frena · <kbd>A</kbd> izquierda · <kbd>X</kbd> recto · <kbd>D</kbd> derecha en el próximo cruce</>
            ) : (
              <>Modo manual: lanza un actor o sigue uno para manejarlo.</>
            )}
          </div>
        )}
        {aviso && fase === 'en_vivo' && <div className="sim3d-aviso" role="status">{aviso}</div>}

        {fase !== 'en_vivo' && fase !== 'fin' && (
          <div className="sim3d-cortina">
            {fase === 'error' ? (
              <>
                <p className="pd-error">{error}</p>
                <button type="button" onClick={onCerrar}>Cerrar</button>
              </>
            ) : (
              <>
                <div className="sim3d-spinner" aria-hidden="true" />
                <p>{mensaje ?? ETAPA_COMPARACION[etapa] ?? etapa}</p>
                <small>La primera vez tarda entre 15 y 40 s: se recorta la red, se arma la demanda y se instala el semáforo propuesto.</small>
              </>
            )}
          </div>
        )}

        {geometria && (
          <aside className={`sim3d-panel ${panelAbierto ? '' : 'plegado'}`} aria-label="Actores y vías">
            <button type="button" className="sim3d-plegar" onClick={() => setPanelAbierto(!panelAbierto)}>
              {panelAbierto ? '‹ Ocultar' : 'Actores y vías ›'}
            </button>
            {panelAbierto && (
              <>
                <h4>Lanzar un actor</h4>
                <p className="pd-nota">Entra por el mismo acceso, a la misma hora, en los dos escenarios.</p>
                <label>
                  Tipo
                  <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
                    {TIPOS.map(([id, et]) => <option key={id} value={id}>{et}</option>)}
                  </select>
                </label>
                <label>
                  Llega por
                  <select value={acceso} onChange={(e) => { setAcceso(e.target.value); const a = geometria.accesos.find((x) => x.edge === e.target.value); setGiro(a?.giros[0]?.direccion ?? 's'); }}>
                    {geometria.accesos.map((a) => (
                      <option key={a.edge} value={a.edge}>
                        {a.nombre ?? a.edge} ({a.carriles} carril{a.carriles > 1 ? 'es' : ''}{a.lateral ? ', cede el paso' : ''})
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Y sigue
                  <select value={giro} onChange={(e) => setGiro(e.target.value)}>
                    {accesoSel?.giros.map((g) => (
                      <option key={g.direccion} value={g.direccion} disabled={tipo === 'peaton' && !g.peatones}>
                        {GIRO[g.direccion] ?? g.direccion}{g.salida_nombre ? ` → ${g.salida_nombre}` : ''}
                      </option>
                    ))}
                  </select>
                </label>
                {tipo !== 'peaton' && (
                  <label>
                    Conducción
                    <select value={estilo} onChange={(e) => setEstilo(e.target.value)}>
                      {ESTILOS.map(([id, et]) => <option key={id} value={id}>{et}</option>)}
                    </select>
                  </label>
                )}
                <button type="button" className="sim3d-primario" onClick={lanzarActor} disabled={fase !== 'en_vivo'}>Lanzar y seguir</button>

                <h4>Seguir uno que ya circula</h4>
                <button type="button" onClick={masCercano} disabled={fase !== 'en_vivo'}>El más cercano al cruce</button>
                <label>
                  Ver una vía
                  <select value={via} onChange={(e) => irAVia(e.target.value)}>
                    <option value="">— elegir —</option>
                    {geometria.vias.map((v) => <option key={v.nombre} value={v.nombre}>{v.nombre}</option>)}
                  </select>
                </label>
                {viaSel && (
                  <ul className="sim3d-lista">
                    {enLaVia.length === 0 && <li className="pd-nota">Nadie circula por {viaSel.nombre} ahora mismo.</li>}
                    {enLaVia.map((x) => (
                      <li key={x[0]}>
                        <button type="button" className={ego === x[0] ? 'activo' : ''} onClick={() => seguir(x[0])}>
                          {TIPOS.find(([id]) => id === x[1])?.[1] ?? x[1]} · {Math.round(x[6] * 3.6)} km/h
                        </button>
                      </li>
                    ))}
                  </ul>
                )}

                <h4>Riesgo</h4>
                <label>
                  Medir cada
                  <select value={periodo} onChange={(e) => { setPeriodo(Number(e.target.value)); enviar({ periodo_riesgo: Number(e.target.value) }); }}>
                    {PERIODOS.map((p) => <option key={p} value={p}>{p} s simulados</option>)}
                  </select>
                </label>
                <p className="pd-nota">
                  Índice 0–100 que toma el peor de TTC (alcance al de adelante), DRAC (frenado necesario) y PET (llegada al
                  punto de cruce con tráfico transversal). Alto ≥ 60. Haz clic en la tarjeta de abajo para ver el detalle.
                </p>
                {ego && <button type="button" onClick={() => seguir(null)}>Dejar de seguir</button>}
                <p className="pd-nota">
                  Red, demanda y semáforo: SUMO. Edificios: huellas de OpenStreetMap y Microsoft; donde faltan, se
                  rellenan los frentes de manzana con edificios ilustrativos.
                </p>
              </>
            )}
          </aside>
        )}
      </div>
    </div>
  );
}
