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
const CAMARAS = [['persecucion', '3ª persona'], ['aerea', 'Aérea'], ['libre', 'Libre']];

const hora = (t) => {
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = Math.floor(t % 60);
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
};

const distancia2 = (a, x, y) => (a[2] - x) ** 2 + (a[3] - y) ** 2;

/**
 * Simulador 3D comparativo de un cruce sin semáforo.
 * Izquierda: el cruce como está hoy. Derecha: el mismo cruce con el semáforo propuesto.
 * Ambos lados corren la misma demanda en lockstep y siguen al mismo actor.
 */
export default function Simulador3D({ cruce, corrida, intensidades, onCerrar }) {
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
  const [tipo, setTipo] = useState('auto');
  const [estilo, setEstilo] = useState('normal');
  const [acceso, setAcceso] = useState('');
  const [giro, setGiro] = useState('s');
  const [via, setVia] = useState('');
  const [panelAbierto, setPanelAbierto] = useState(true);
  const [conectar, setConectar] = useState(false);

  const egoRef = useRef(null);
  egoRef.current = ego;

  // 1. preparar la zona (recorte + demanda + semáforo propuesto) y esperar
  useEffect(() => {
    let vivo = true;
    (async () => {
      try {
        const comp = await crearComparacion3D(cruce.id, { lon: cruce.lon, lat: cruce.lat, corrida, intensidades });
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
    };
  }, [cruce, corrida, intensidades]);

  // 2. armar las dos escenas y el bucle de render
  useEffect(() => {
    if (!geometria || !refA.current || !refB.current) return undefined;
    const a = new Escena3D(refA.current, geometria, { conSemaforo: false });
    const b = new Escena3D(refB.current, geometria, { conSemaforo: true });
    escenas.current = { a, b };
    a.mirarA(geometria.nodo.x, geometria.nodo.y, geometria.nodo.z);
    b.mirarA(geometria.nodo.x, geometria.nodo.y, geometria.nodo.z);

    // en cámara libre, mover un lado mueve el otro
    let sincronizando = false;
    const sincronizar = (origen, destino) => () => {
      if (sincronizando) return;
      sincronizando = true;
      destino.camera.position.copy(origen.camera.position);
      destino.controles.target.copy(origen.controles.target);
      destino.controles.update();
      sincronizando = false;
    };
    a.controles.addEventListener('change', sincronizar(a, b));
    b.controles.addEventListener('change', sincronizar(b, a));

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
      a.render(dt);
      b.render(dt);
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
  }, [geometria]);

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

  const accesoSel = geometria?.accesos.find((x) => x.edge === acceso);
  const viaSel = geometria?.vias.find((v) => v.nombre === via);

  const lanzarActor = () => {
    enviar({ inyectar: { tipo, acceso, giro, estilo } });
    setCamara('persecucion');
  };

  const seguir = (id) => {
    setEgo(id);
    enviar({ seguir: id });
    setCamara('persecucion');
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
    const candidatos = [...lado.vehiculos, ...lado.personas].filter((act) => frame.lados.b.vehiculos.some((v) => v[0] === act[0]) || frame.lados.b.personas.some((p) => p[0] === act[0]));
    if (!candidatos.length) return;
    candidatos.sort((p, q) => distancia2(p, x, y) - distancia2(q, x, y));
    seguir(candidatos[0][0]);
  };

  const irAVia = (nombre) => {
    setVia(nombre);
    const v = geometria?.vias.find((x) => x.nombre === nombre);
    if (!v?.centro) return;
    for (const esc of Object.values(escenas.current)) esc?.mirarA(...v.centro);
    if (!ego) setCamara('aerea');
  };

  const egoMapa = frame?.lados.a.ego ?? frame?.lados.b.ego ?? null;
  const calles = cruce.calles?.length ? cruce.calles.join(' × ') : `Cruce ${cruce.id}`;

  return (
    <div className="sim3d" role="dialog" aria-label="Simulador 3D: con y sin semáforo">
      <header className="sim3d-barra">
        <div className="sim3d-titulo">
          <strong>Simulador 3D · {calles}</strong>
          <span>
            {info ? `Demanda ${info.fuente_demanda === 'sintetica' ? 'sintética' : info.fuente_demanda === 'real' ? 'real' : 'real + fondo sintético'}` : ''}
            {info?.ciclo_s ? ` · semáforo propuesto: ${info.fases} fases, ciclo ${Math.round(info.ciclo_s)} s` : ''}
            {frame ? ` · ${hora(frame.t)}` : ''}
          </span>
        </div>
        <div className="sim3d-controles-top">
          <button type="button" onClick={() => { setPausada(!pausada); enviar({ pausa: !pausada }); }} disabled={fase !== 'en_vivo'}>
            {pausada ? '▶ Continuar' : '⏸ Pausar'}
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

      <div className="sim3d-vistas">
        <section className="sim3d-vista">
          <div ref={refA} className="sim3d-lienzo" />
          {geometria && (
            <HUD titulo="Sin semáforo (actual)" subtitulo={`Cruce ${geometria.nodo.tipo_actual === 'priority' ? 'con prioridad' : geometria.nodo.tipo_actual === 'right_before_left' ? 'de prioridad a la derecha' : geometria.nodo.tipo_actual ?? ''}`} conSemaforo={false} lado={frame?.lados.a} egoId={ego} />
          )}
        </section>
        <section className="sim3d-vista">
          <div ref={refB} className="sim3d-lienzo" />
          {geometria && <HUD titulo="Con semáforo propuesto" subtitulo="Programa de tiempos fijos generado por netconvert" conSemaforo lado={frame?.lados.b} egoId={ego} />}
        </section>

        {geometria && <Minimapa nodo={geometria.nodo} bbox={geometria.bbox_lonlat} ego={egoMapa} egoId={ego} />}

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
      </div>

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
                  {geometria.accesos.map((a) => <option key={a.edge} value={a.edge}>{a.nombre ?? a.edge} ({a.carriles} carril{a.carriles > 1 ? 'es' : ''})</option>)}
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
              {aviso && <p className="pd-error">{aviso}</p>}

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
                punto de cruce con tráfico transversal). Alto ≥ 60.
              </p>
              {ego && <button type="button" onClick={() => seguir(null)}>Dejar de seguir</button>}
            </>
          )}
        </aside>
      )}
    </div>
  );
}
