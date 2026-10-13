import React, { useEffect, useState } from 'react';
import { obtenerInterseccion, obtenerProgramas, obtenerPrograma, guardarPrograma, calcularWebster } from '../api';
import TablaComparacion from './TablaComparacion';

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));

const GIROS = { s: 'recto', l: 'izquierda', r: 'derecha', t: 'retorno', L: 'izquierda suave', R: 'derecha suave' };
const TIPOS_PROGRAMA = ['static', 'actuated', 'delay_based'];

function Luz({ luz }) {
  return <span className={`fi-luz ${luz}`} title={luz} aria-label={luz} />;
}

// ─── Pestaña Ficha (original) ─────────────────────────────────────────────────

function TabFicha({ ficha, etiquetaCorrida }) {
  const accesos = [...ficha.accesos].sort((a, b) => (b.volumen ?? -1) - (a.volumen ?? -1));
  const giros = (edge) =>
    [...new Set(ficha.enlaces.filter((e) => e.acceso === edge).map((e) => GIROS[e.giro] ?? e.giro))].join(', ');

  return (
    <>
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
    </>
  );
}

// ─── Pestaña Configurar ───────────────────────────────────────────────────────

function TabConfigurar({ id, ficha, corrida }) {
  const [programas, setProgramas] = useState([]);
  const [progId, setProgId] = useState('0');
  const [tipo, setTipo] = useState('static');
  const [offset, setOffset] = useState(0);
  const [fases, setFases] = useState([]);
  const [guardando, setGuardando] = useState(false);
  const [calculando, setCalculando] = useState(false);
  const [mensaje, setMensaje] = useState(null);
  const [errores, setErrores] = useState([]);

  // Cargar lista de programas al montar
  useEffect(() => {
    if (!id) return;
    obtenerProgramas(id)
      .then(setProgramas)
      .catch(() => setProgramas([]));
  }, [id]);

  // Cargar el programa seleccionado
  useEffect(() => {
    if (!id || !progId) return;
    obtenerPrograma(id, progId)
      .then((p) => {
        setTipo(p.tipo);
        setOffset(p.offset);
        setFases(p.fases.map((f) => ({ duracion_s: f.duracion_s, estado: f.estado })));
        setMensaje(null);
        setErrores([]);
      })
      .catch(() => {});
  }, [id, progId]);

  const cambiarFase = (i, campo, valor) =>
    setFases((prev) => prev.map((f, idx) => (idx === i ? { ...f, [campo]: valor } : f)));

  const agregarFase = () =>
    setFases((prev) => [
      ...prev,
      { duracion_s: 30, estado: prev[0]?.estado?.replace(/./g, 'r') ?? 'r' },
    ]);

  const eliminarFase = (i) => setFases((prev) => prev.filter((_, idx) => idx !== i));

  const guardar = async () => {
    setGuardando(true);
    setMensaje(null);
    setErrores([]);
    try {
      const resultado = await guardarPrograma(id, progId, { tipo, offset, fases });
      setMensaje(`✓ Guardado en ${resultado.guardado_en?.split(/[\\/]/).slice(-1)[0] ?? 'el servidor'}`);
    } catch (e) {
      const detalle = e.errores || [e.message];
      setErrores(Array.isArray(detalle) ? detalle : [detalle]);
    } finally {
      setGuardando(false);
    }
  };

  const aplicarWebster = async () => {
    setCalculando(true);
    setMensaje(null);
    try {
      const w = await calcularWebster(id, {
        run_id: corrida?.id && !corrida?.precalculada ? corrida.id : null,
        num_fases: fases.length || 2,
      });
      setMensaje(
        `Webster: ciclo óptimo ${w.ciclo_optimo_s} s · Y=${w.Y} · ${w.nota}`
      );
      // Ajustar duraciones de las fases con verde según Webster
      const verdes = w.verdes_s;
      setFases((prev) =>
        prev.map((f, i) => {
          const tieneVerde = f.estado.includes('G') || f.estado.includes('g');
          if (tieneVerde && verdes[i] !== undefined) return { ...f, duracion_s: verdes[i] };
          if (!tieneVerde && verdes[i] !== undefined) return { ...f, duracion_s: 3 }; // amarillo fijo
          return f;
        })
      );
    } catch (e) {
      setErrores([e.message]);
    } finally {
      setCalculando(false);
    }
  };

  const restaurar = () => {
    setProgId('0');
  };

  const ciclo = fases.reduce((s, f) => s + Number(f.duracion_s), 0);

  return (
    <section>
      <h3>Configurar programa de semáforo</h3>

      <div className="fi-config-controles">
        <label>
          Programa:
          <select value={progId} onChange={(e) => setProgId(e.target.value)}>
            {programas.map((p) => (
              <option key={p.program_id} value={p.program_id}>
                {p.program_id} ({p.tipo}, {numero(p.ciclo_s)} s)
              </option>
            ))}
          </select>
        </label>
        <label>
          Tipo:
          <select value={tipo} onChange={(e) => setTipo(e.target.value)}>
            {TIPOS_PROGRAMA.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </label>
        <label>
          Offset:
          <input
            type="number"
            min="0"
            max="300"
            value={offset}
            onChange={(e) => setOffset(Number(e.target.value))}
          />
          s
        </label>
      </div>

      <p className="pd-nota">Ciclo actual: <strong>{numero(ciclo)} s</strong></p>

      <table className="fi-tabla fi-fases">
        <thead>
          <tr>
            <th>#</th>
            <th>Duración (s)</th>
            <th>Estado SUMO</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {fases.map((f, i) => (
            <tr key={i}>
              <td>{i + 1}</td>
              <td>
                <input
                  type="number"
                  min="1"
                  max="300"
                  step="1"
                  value={f.duracion_s}
                  onChange={(e) => cambiarFase(i, 'duracion_s', Number(e.target.value))}
                  className="fi-input-duracion"
                />
              </td>
              <td>
                <input
                  type="text"
                  value={f.estado}
                  onChange={(e) => cambiarFase(i, 'estado', e.target.value)}
                  className="fi-input-estado"
                  title="Una letra por movimiento: G=verde, y=amarillo, r=rojo"
                  spellCheck={false}
                />
              </td>
              <td>
                <button type="button" onClick={() => eliminarFase(i)} aria-label="Eliminar fase" title="Eliminar esta fase">
                  ×
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="fi-config-acciones">
        <button type="button" onClick={agregarFase}>+ Fase</button>
        <button type="button" onClick={aplicarWebster} disabled={calculando}>
          {calculando ? 'Calculando…' : 'Webster'}
        </button>
        <button type="button" onClick={restaurar} title="Recargar el programa original 0">
          Restaurar original
        </button>
        <button type="button" className="pd-ejecutar fi-guardar" onClick={guardar} disabled={guardando || fases.length === 0}>
          {guardando ? 'Guardando…' : 'Guardar'}
        </button>
      </div>

      {errores.length > 0 && (
        <ul className="pd-error">
          {errores.map((e, i) => <li key={i}>{e}</li>)}
        </ul>
      )}
      {mensaje && <p className="pd-nota fi-ok">{mensaje}</p>}

      <p className="pd-nota">
        El programa se guarda como archivo additional.xml. Para que afecte una simulación,
        reinicia el servicio o recarga el escenario. Los cruces peatonales requieren regenerar la red
        con <code>--crossings.guess</code>.
      </p>
    </section>
  );
}

// ─── Componente principal ─────────────────────────────────────────────────────

/** Ficha de una intersección semaforizada: accesos con volumen simulado y programa del semáforo. */
export default function FichaInterseccion({ id, corrida, etiquetaCorrida, onAbrir3D }) {
  const [ficha, setFicha] = useState(null);
  const [error, setError] = useState(null);
  const [subpestana, setSubpestana] = useState('ficha');

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

  if (!id) {
    return (
      <div className="pd-contenido fi-vacia">
        <p>Haz clic en un semáforo del mapa para ver su ficha.</p>
        <p className="pd-nota">
          Primero activa los semáforos con el botón <strong>Semáforos</strong> en la leyenda superior.
          Aparecen como puntos cian; al hacer clic en uno se abre aquí.
        </p>
        <p className="pd-nota">
          <strong>Ficha</strong> — accesos y volumen simulado por acceso, programa de fases actual.<br />
          <strong>Configurar</strong> — edita las duraciones de cada fase o calcula tiempos óptimos con Webster.<br />
          <strong>Comparar</strong> — lanza simulaciones con distintos programas y compara métricas (demora, cola, peatones).<br />
          <strong>3D ▶</strong> — simulación en vivo de la intersección en tiempo real (requiere zona recortada).
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
        {onAbrir3D && (
          <button type="button" className="fi-btn-3d" onClick={() => onAbrir3D(id)} title="Ver intersección en 3D en vivo">
            3D ▶
          </button>
        )}
      </div>

      {subpestana === 'ficha' && <TabFicha ficha={ficha} etiquetaCorrida={etiquetaCorrida} />}
      {subpestana === 'configurar' && <TabConfigurar id={id} ficha={ficha} corrida={corrida} />}
      {subpestana === 'comparar' && <TablaComparacion id={id} corrida={corrida} />}
    </div>
  );
}
