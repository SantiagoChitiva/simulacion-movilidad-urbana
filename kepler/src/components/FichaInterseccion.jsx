import React, { useEffect, useMemo, useState } from 'react';
import { obtenerInterseccion, obtenerProgramas, obtenerPrograma, guardarPrograma, calcularWebster } from '../api';
import TablaComparacion from './TablaComparacion';

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));

const GIROS = { s: 'de frente', l: 'a la izquierda', r: 'a la derecha', t: 'en U', L: 'a la izquierda', R: 'a la derecha' };
const TIPOS_PROGRAMA = ['static', 'actuated', 'delay_based'];
const TIPO_LEGIBLE = { static: 'de tiempo fijo', actuated: 'que se adapta al tráfico (actuado)', delay_based: 'que se adapta a la demora' };
export const PROGRAMA_USUARIO = 'usuario';

// letra del estado de SUMO → luz, y la luz que sigue al hacer clic en el editor
const LUZ = { G: 'verde', g: 'verde', y: 'amarillo', Y: 'amarillo', u: 'amarillo', r: 'rojo', R: 'rojo', s: 'rojo', o: 'apagado', O: 'apagado' };
const SIGUIENTE = { verde: 'amarillo', amarillo: 'rojo', rojo: 'verde', apagado: 'verde' };
const LETRA = { verde: 'G', amarillo: 'y', rojo: 'r' };
const ORDEN_LUZ = ['verde', 'amarillo', 'rojo', 'apagado'];

const letraAcceso = (i) => String.fromCharCode(65 + i);
const lista = (xs) => (xs.length < 2 ? xs.join('') : `${xs.slice(0, -1).join(', ')} y ${xs[xs.length - 1]}`);
const esCambio = (estado) => /[yYu]/.test(estado);

/** Luz de un acceso en una fase: la de su movimiento más permisivo (como en el backend). */
function luzDeAcceso(estado, enlaces, edge) {
  const luces = new Set(enlaces.filter((e) => e.acceso === edge && e.indice < estado.length).map((e) => LUZ[estado[e.indice]] ?? 'rojo'));
  return ORDEN_LUZ.find((l) => luces.has(l)) ?? 'apagado';
}

/** "Pasan los de Calle 127 de frente y a la derecha…" para una fase. */
function describirFase(estado, accesos, enlaces) {
  if (esCambio(estado)) return { tipo: 'cambio', titulo: 'Cambio de luces (amarillo)', detalle: [] };
  if (!/[Gg]/.test(estado)) return { tipo: 'rojo', titulo: 'Todo en rojo (despeje del cruce)', detalle: [] };
  const detalle = accesos.flatMap((a, i) => {
    const propios = enlaces.filter((e) => e.acceso === a.edge && e.indice < estado.length);
    const preferentes = [...new Set(propios.filter((e) => estado[e.indice] === 'G').map((e) => GIROS[e.giro] ?? e.giro))];
    // un mismo giro puede tener un carril con prioridad y otro que cede: se nombra una vez
    const cediendo = [...new Set(propios.filter((e) => estado[e.indice] === 'g').map((e) => GIROS[e.giro] ?? e.giro))]
      .filter((g) => !preferentes.includes(g));
    if (!preferentes.length && !cediendo.length) return [];
    const partes = [];
    if (preferentes.length) partes.push(lista(preferentes));
    if (cediendo.length) partes.push(`${lista(cediendo)} cediendo el paso`);
    return [`${letraAcceso(i)}. ${a.calle ?? 'Sin nombre'}: ${partes.join('; ')}`];
  });
  return { tipo: 'verde', titulo: 'Pasan', detalle };
}

function Luz({ luz, onClick, titulo }) {
  if (onClick) {
    return <button type="button" className={`fi-luz fi-luz-boton ${luz}`} title={titulo} aria-label={titulo} onClick={onClick} />;
  }
  return <span className={`fi-luz ${luz}`} title={titulo ?? luz} aria-label={titulo ?? luz} />;
}

/** Barra del ciclo: cada fase con su largo proporcional a la duración. */
function BarraCiclo({ fases }) {
  const total = fases.reduce((s, f) => s + Number(f.duracion), 0) || 1;
  return (
    <div className="fi-ciclo" aria-label="Duración de cada fase en el ciclo">
      {fases.map((f, i) => (
        <span
          key={i}
          className={`fi-ciclo-fase ${esCambio(f.estado) ? 'cambio' : /[Gg]/.test(f.estado) ? 'verde' : 'rojo'}`}
          style={{ flexGrow: Number(f.duracion) / total }}
          title={`Fase ${i + 1}: ${numero(f.duracion)} s`}
        >
          {Number(f.duracion) / total > 0.08 ? i + 1 : ''}
        </span>
      ))}
    </div>
  );
}

/** Lista de fases en palabras, con la duración de cada una. */
function FasesEnPalabras({ fases, accesos, enlaces }) {
  return (
    <ol className="fi-fases-texto">
      {fases.map((f, i) => {
        const d = describirFase(f.estado, accesos, enlaces);
        return (
          <li key={i} className={d.tipo}>
            <b>Fase {i + 1} · {numero(f.duracion)} s</b> — {d.titulo}
            {d.detalle.length > 0 && (
              <ul>{d.detalle.map((t) => <li key={t}>{t}</li>)}</ul>
            )}
          </li>
        );
      })}
    </ol>
  );
}

// ─── Pestaña Ficha ────────────────────────────────────────────────────────────

function TabFicha({ ficha, accesos, etiquetaCorrida }) {
  const giros = (edge) =>
    [...new Set(ficha.enlaces.filter((e) => e.acceso === edge).map((e) => GIROS[e.giro] ?? e.giro))].join(', ');
  const verdes = ficha.fases.filter((f) => /[Gg]/.test(f.estado) && !esCambio(f.estado)).length;

  return (
    <>
      <p className="pd-descripcion">
        Semáforo {TIPO_LEGIBLE[ficha.tipo] ?? ficha.tipo} con {verdes} turnos de paso. Una vuelta completa de luces (el
        ciclo) dura <strong>{numero(ficha.ciclo)} s</strong>.
        {ficha.cruces.length > 1 && ` Controla ${ficha.cruces.length} nodos a la vez.`}
      </p>

      <section>
        <h3>Accesos y tráfico simulado</h3>
        <p className="pd-nota">Vehículos que llegaron por cada acceso en {etiquetaCorrida} (07:00–10:00).</p>
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
                  <strong>{letraAcceso(i)}.</strong> {a.calle ?? 'Sin nombre'}
                  <span className="fi-sub">
                    {a.clase === 'ciclorruta' ? 'Ciclorruta' : `Vía ${a.clase}`} · {a.carriles} carril{a.carriles === 1 ? '' : 'es'} · {a.velocidad_kmh} km/h · puede ir {giros(a.edge)}
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
        <h3>Cómo cambian las luces</h3>
        <BarraCiclo fases={ficha.fases} />
        <FasesEnPalabras fases={ficha.fases} accesos={accesos} enlaces={ficha.enlaces} />
        <details className="fi-detalles">
          <summary>Ver la tabla de luces por acceso</summary>
          <table className="fi-tabla fi-fases">
            <thead>
              <tr>
                <th>Fase</th>
                <th>s</th>
                {accesos.map((a, i) => <th key={a.edge} title={a.calle ?? a.edge}>{letraAcceso(i)}</th>)}
              </tr>
            </thead>
            <tbody>
              {ficha.fases.map((f, n) => (
                <tr key={n}>
                  <td>{n + 1}</td>
                  <td>{numero(f.duracion)}</td>
                  {accesos.map((a) => <td key={a.edge}><Luz luz={f.luces[a.edge] ?? 'apagado'} /></td>)}
                </tr>
              ))}
            </tbody>
          </table>
          <p className="pd-nota">Cada columna es un acceso; la luz es la de su movimiento más permisivo en esa fase.</p>
        </details>
        <p className="pd-nota">{ficha.nota_programa}</p>
      </section>
    </>
  );
}

// ─── Pestaña Configurar ───────────────────────────────────────────────────────

function TabConfigurar({ id, ficha, accesos, corrida, onGuardado }) {
  const [programas, setProgramas] = useState([]);
  const [progId, setProgId] = useState(ficha.programa ?? '0');
  const [nombreGuardado, setNombreGuardado] = useState(PROGRAMA_USUARIO);
  const [tipo, setTipo] = useState('static');
  const [offset, setOffset] = useState(0);
  const [fases, setFases] = useState([]);
  const [original, setOriginal] = useState([]);
  const [guardando, setGuardando] = useState(false);
  const [calculando, setCalculando] = useState(false);
  const [mensaje, setMensaje] = useState(null);
  const [errores, setErrores] = useState([]);

  useEffect(() => {
    obtenerProgramas(id).then(setProgramas).catch(() => setProgramas([]));
  }, [id]);

  useEffect(() => {
    obtenerPrograma(id, progId)
      .then((p) => {
        const leidas = p.fases.map((f) => ({ duracion_s: f.duracion_s, estado: f.estado }));
        setTipo(p.tipo);
        setOffset(p.offset);
        setFases(leidas);
        setOriginal(leidas);
        setMensaje(null);
        setErrores([]);
      })
      .catch(() => {});
  }, [id, progId]);

  const cambiarFase = (i, campo, valor) =>
    setFases((prev) => prev.map((f, idx) => (idx === i ? { ...f, [campo]: valor } : f)));

  // clic en la luz de un acceso: cambian todos sus movimientos en esa fase
  const alternarLuz = (i, edge) => {
    const f = fases[i];
    const nueva = SIGUIENTE[luzDeAcceso(f.estado, ficha.enlaces, edge)];
    const indices = new Set(ficha.enlaces.filter((e) => e.acceso === edge).map((e) => e.indice));
    const previo = original[i]?.estado ?? '';
    const estado = [...f.estado]
      .map((c, k) => {
        if (!indices.has(k)) return c;
        // al volver a verde se respeta el "cediendo el paso" (g) que traía el programa
        if (nueva === 'verde' && 'Gg'.includes(previo[k])) return previo[k];
        return LETRA[nueva];
      })
      .join('');
    cambiarFase(i, 'estado', estado);
  };

  const guardar = async () => {
    setGuardando(true);
    setMensaje(null);
    setErrores([]);
    try {
      await guardarPrograma(id, nombreGuardado, { tipo, offset, fases });
      setMensaje('Guardado. Ahora puedes compararlo con el programa actual en la pestaña Comparar.');
      onGuardado?.();
    } catch (e) {
      setErrores([e.message]);
    } finally {
      setGuardando(false);
    }
  };

  const aplicarWebster = async () => {
    setCalculando(true);
    setMensaje(null);
    setErrores([]);
    try {
      const w = await calcularWebster(id, corrida);
      setFases(w.programa.fases.map((f) => ({ duracion_s: f.duracion_s, estado: f.estado })));
      setMensaje(`Tiempos calculados con el tráfico simulado: ciclo de ${numero(w.ciclo_optimo_s)} s. ${w.nota}`);
    } catch (e) {
      setErrores([e.message]);
    } finally {
      setCalculando(false);
    }
  };

  const ciclo = fases.reduce((s, f) => s + Number(f.duracion_s), 0);
  const fasesVista = fases.map((f) => ({ duracion: f.duracion_s, estado: f.estado }));

  return (
    <section>
      <p className="pd-nota">
        Cambia cuánto dura cada fase o qué accesos tienen verde (clic en una luz: verde → amarillo → rojo). Lo que guardes
        queda como <strong>tu programa</strong> y se puede comparar con el actual en la pestaña <strong>Comparar</strong>;
        no cambia la simulación de toda la localidad.
      </p>

      <BarraCiclo fases={fasesVista} />
      <p className="pd-nota">Ciclo: <strong>{numero(ciclo)} s</strong></p>

      <ol className="fi-editor">
        {fases.map((f, i) => {
          const d = describirFase(f.estado, accesos, ficha.enlaces);
          return (
            <li key={i}>
              <div className="fi-editor-cab">
                <b>Fase {i + 1}</b>
                <span className="fi-editor-tipo">{d.tipo === 'verde' ? 'paso' : d.titulo.toLowerCase()}</span>
                <span className="fi-duracion">
                  <button type="button" onClick={() => cambiarFase(i, 'duracion_s', Math.max(1, Number(f.duracion_s) - 1))} aria-label="Un segundo menos">−</button>
                  <input
                    type="number" min="1" max="300" step="1" value={f.duracion_s}
                    onChange={(e) => cambiarFase(i, 'duracion_s', Number(e.target.value))}
                    aria-label={`Duración de la fase ${i + 1} en segundos`}
                  />
                  <button type="button" onClick={() => cambiarFase(i, 'duracion_s', Number(f.duracion_s) + 1)} aria-label="Un segundo más">+</button>
                  s
                </span>
              </div>
              <div className="fi-editor-luces">
                {accesos.map((a, k) => {
                  const luz = luzDeAcceso(f.estado, ficha.enlaces, a.edge);
                  return (
                    <span key={a.edge} className="fi-editor-acceso">
                      <Luz luz={luz} titulo={`${letraAcceso(k)}. ${a.calle ?? 'Sin nombre'}: ${luz}`} onClick={() => alternarLuz(i, a.edge)} />
                      {letraAcceso(k)}
                    </span>
                  );
                })}
              </div>
            </li>
          );
        })}
      </ol>

      <div className="fi-config-acciones">
        <button type="button" onClick={aplicarWebster} disabled={calculando} title="Método de Webster con el tráfico de la simulación cargada">
          {calculando ? 'Calculando…' : 'Calcular tiempos óptimos'}
        </button>
        <button type="button" onClick={() => setFases(original)} title="Vuelve al programa que trae la red">
          Volver al original
        </button>
        <button type="button" className="fi-guardar" onClick={guardar} disabled={guardando || fases.length === 0}>
          {guardando ? 'Guardando…' : 'Guardar como mi programa'}
        </button>
      </div>
      <p className="pd-nota">
        <strong>Tiempos óptimos</strong>: el método de Webster reparte el verde según el tráfico que llega por cada acceso
        en la simulación cargada; con poco tráfico el ciclo se acorta y con mucho se alarga.
      </p>

      {errores.length > 0 && (
        <ul className="pd-error">{errores.map((e) => <li key={e}>{e}</li>)}</ul>
      )}
      {mensaje && <p className="pd-nota fi-ok">{mensaje}</p>}

      <details className="fi-detalles">
        <summary>Opciones avanzadas</summary>
        <div className="fi-config-controles">
          <label>
            Programa base
            <select value={progId} onChange={(e) => setProgId(e.target.value)}>
              {programas.filter((p) => !p.guardado).map((p) => (
                <option key={p.program_id} value={p.program_id}>{p.program_id} ({numero(p.ciclo_s)} s)</option>
              ))}
            </select>
          </label>
          <label>
            Guardar como
            <input type="text" value={nombreGuardado} onChange={(e) => setNombreGuardado(e.target.value.replace(/[^\w-]/g, ''))} />
          </label>
          <label>
            Tipo
            <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
              {TIPOS_PROGRAMA.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </label>
          <label>
            Desfase (offset, s)
            <input type="number" min="0" max="300" value={offset} onChange={(e) => setOffset(Number(e.target.value))} />
          </label>
        </div>
        <p className="pd-nota">Estado SUMO de cada fase: una letra por movimiento (G verde, g verde cediendo el paso, y amarillo, r rojo).</p>
        <table className="fi-tabla">
          <tbody>
            {fases.map((f, i) => (
              <tr key={i}>
                <td>{i + 1}</td>
                <td>
                  <input type="text" value={f.estado} onChange={(e) => cambiarFase(i, 'estado', e.target.value)} className="fi-input-estado" spellCheck={false} aria-label={`Estado SUMO de la fase ${i + 1}`} />
                </td>
                <td>
                  <button type="button" onClick={() => setFases((prev) => prev.filter((_, k) => k !== i))} aria-label="Eliminar fase">×</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <button type="button" onClick={() => setFases((prev) => [...prev, { duracion_s: 30, estado: prev[0]?.estado?.replace(/./g, 'r') ?? 'r' }])}>
          + Fase
        </button>
      </details>
    </section>
  );
}

// ─── Componente principal ─────────────────────────────────────────────────────

/** Ficha de una intersección semaforizada: accesos, cómo cambian sus luces, edición y comparación. */
export default function FichaInterseccion({ id, corrida, etiquetaCorrida }) {
  const [ficha, setFicha] = useState(null);
  const [error, setError] = useState(null);
  const [subpestana, setSubpestana] = useState('ficha');
  const [versionGuardado, setVersionGuardado] = useState(0);

  useEffect(() => {
    if (!id) return undefined;
    let cancelado = false;
    setFicha(null);
    setError(null);
    setSubpestana('ficha');
    obtenerInterseccion(id, corrida)
      .then((f) => !cancelado && setFicha(f))
      .catch((e) => !cancelado && setError(e.message));
    return () => {
      cancelado = true;
    };
  }, [id, corrida]);

  // los accesos llevan la misma letra en todas las pestañas: de más a menos tráfico
  const accesos = useMemo(
    () => (ficha ? [...ficha.accesos].sort((a, b) => (b.volumen ?? -1) - (a.volumen ?? -1)) : []),
    [ficha]
  );

  if (!id) {
    return (
      <div className="pd-contenido fi-vacia">
        <p>Haz clic en un semáforo del mapa para ver su ficha.</p>
        <p className="pd-nota">
          Actívalos con el botón <strong>Semáforos</strong> de la leyenda de arriba: aparecen como puntos cian.
        </p>
        <p className="pd-nota">
          <strong>Ficha</strong>: por dónde llegan los vehículos y cómo cambian las luces.<br />
          <strong>Configurar</strong>: cambia los tiempos de cada fase o calcula unos tiempos óptimos.<br />
          <strong>Comparar</strong>: simula el cruce con el programa actual y con otros, y dice cuál funciona mejor.<br />
          Para un semáforo <strong>nuevo</strong> en un cruce que no lo tiene, usa la pestaña <strong>Semaforizar</strong>.
        </p>
      </div>
    );
  }
  if (error) return <p className="pd-error">{error}</p>;
  if (!ficha) return <p className="pd-nota">Cargando intersección…</p>;

  return (
    <div className="pd-contenido ficha">
      <h3 className="fi-nombre">{ficha.nombre}</h3>

      <div className="fi-subpestanas" role="tablist">
        {[['ficha', 'Ficha'], ['configurar', 'Configurar'], ['comparar', 'Comparar']].map(([key, label]) => (
          <button
            key={key}
            type="button"
            role="tab"
            aria-selected={subpestana === key}
            className={subpestana === key ? 'activa' : ''}
            onClick={() => setSubpestana(key)}
          >
            {label}
          </button>
        ))}
      </div>

      {subpestana === 'ficha' && <TabFicha ficha={ficha} accesos={accesos} etiquetaCorrida={etiquetaCorrida} />}
      {subpestana === 'configurar' && (
        <TabConfigurar id={id} ficha={ficha} accesos={accesos} corrida={corrida} onGuardado={() => setVersionGuardado((v) => v + 1)} />
      )}
      {subpestana === 'comparar' && <TablaComparacion key={versionGuardado} id={id} corrida={corrida} />}
    </div>
  );
}
