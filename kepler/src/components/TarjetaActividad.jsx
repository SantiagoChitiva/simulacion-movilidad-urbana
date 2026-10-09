import React, { useEffect, useState } from 'react';
import { ESTADOS_FINALES, ETIQUETA_ESTADO } from '../api';

const numero = (n) => (n ?? 0).toLocaleString('es-CO');
const pct = (a) => `${Math.floor(a * 100)} %`;

const mmss = (segundos) => {
  const s = Math.max(0, Math.round(segundos));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

const segundosDesde = (iso) => (Date.now() - new Date(iso).getTime()) / 1000;

const SEGUNDOS_AVISO = 6;

function Barra({ avance }) {
  // avance null = no se sabe cuánto falta: barra animada
  return (
    <div
      className={`ta-barra ${avance == null ? 'indeterminada' : ''}`}
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={avance == null ? undefined : Math.round(avance * 100)}
    >
      <div style={{ width: avance == null ? undefined : `${avance * 100}%` }} />
    </div>
  );
}

function BotonCancelar({ onConfirmar, etiqueta = 'Cancelar' }) {
  const [confirmando, setConfirmando] = useState(false);
  if (!confirmando) {
    return (
      <button type="button" className="ta-cancelar" onClick={() => setConfirmando(true)}>
        {etiqueta}
      </button>
    );
  }
  return (
    <span className="ta-confirmar">
      ¿Seguro?
      <button type="button" className="ta-si" onClick={onConfirmar}>
        Sí, cancelar
      </button>
      <button type="button" onClick={() => setConfirmando(false)}>
        No
      </button>
    </span>
  );
}

function Simulacion({ corrida, onCancelar, onDescartar }) {
  const final = ESTADOS_FINALES.has(corrida.estado);
  const desde = corrida.iniciada ?? corrida.creada;
  const transcurrido = segundosDesde(desde);
  const a = corrida.avance ?? 0;
  // estimación simple: el ritmo hasta ahora se mantiene (solo cuando ya hay base)
  const restante = !final && corrida.iniciada && a >= 0.15 ? (transcurrido * (1 - a)) / a : null;
  const indeterminada = corrida.estado === 'en_cola' || (corrida.estado === 'generando_demanda' && !a);

  return (
    <div className={`ta-item ${corrida.estado}`}>
      <div className="ta-titulo">
        <strong>Simulación · {ETIQUETA_ESTADO[corrida.estado] ?? corrida.estado}</strong>
        {final && (
          <button type="button" className="ta-cerrar" onClick={onDescartar} aria-label="Cerrar aviso">
            ×
          </button>
        )}
      </div>
      {!final && (
        <>
          <Barra avance={indeterminada ? null : a} />
          <div className="ta-detalle">
            <span>{indeterminada ? 'Esperando…' : pct(a)}</span>
            <span>
              {mmss(transcurrido)}
              {restante != null &&
                (restante < 60 ? ' · menos de 1 min' : ` · ~${Math.ceil(restante / 60)} min restantes`)}
            </span>
          </div>
          {corrida.estado !== 'cancelando' && <BotonCancelar onConfirmar={onCancelar} etiqueta="Cancelar simulación" />}
        </>
      )}
      {corrida.estado === 'terminado' && corrida.resultado && (
        <p>
          {numero(corrida.resultado.viajes_generados)} viajes · {numero(corrida.resultado.vehiculos_insertados)} vehículos
          insertados · {numero(corrida.resultado.trips_kepler)} trips. Se carga sola en el mapa.
        </p>
      )}
      {corrida.estado === 'error' && <p className="ta-error">{corrida.error}</p>}
      {corrida.estado === 'cancelada' && <p>La simulación se canceló y sus archivos se borraron.</p>}
    </div>
  );
}

function CargaMapa({ carga, onCancelar }) {
  const descargando = carga.etapa === 'descargando';
  return (
    <div className="ta-item cargando">
      <div className="ta-titulo">
        <strong>{descargando ? 'Descargando trips' : 'Dibujando en el mapa…'}</strong>
      </div>
      <Barra avance={descargando ? carga.avance : null} />
      <div className="ta-detalle">
        <span>
          {descargando && carga.avance != null ? pct(carga.avance) : ''}
          {descargando && carga.mb != null && ` · ${carga.mb.toFixed(0)} MB`}
        </span>
        <span>{carga.etiqueta}</span>
      </div>
      {descargando && <BotonCancelar onConfirmar={onCancelar} etiqueta="Cancelar carga" />}
    </div>
  );
}

function AvisoCarga({ aviso, onDescartar }) {
  // se cierra solo; `clave` reinicia la cuenta si llega otro aviso igual
  useEffect(() => {
    const id = setTimeout(onDescartar, SEGUNDOS_AVISO * 1000);
    return () => clearTimeout(id);
  }, [aviso.clave, onDescartar]);

  return (
    <div className="ta-item terminado ta-aviso" role="status">
      <div className="ta-titulo">
        <strong>✓ {aviso.titulo}</strong>
        <button type="button" className="ta-cerrar" onClick={onDescartar} aria-label="Cerrar aviso">
          ×
        </button>
      </div>
      <p>{aviso.detalle}</p>
    </div>
  );
}

/** Tarjeta en la esquina inferior derecha: simulación en curso, carga de trips en el mapa y aviso al terminar. */
export default function TarjetaActividad({
  corrida,
  carga,
  errorCarga,
  aviso,
  onCancelarCorrida,
  onDescartarCorrida,
  onCancelarCarga,
  onDescartarError,
  onDescartarAviso,
}) {
  const [, setTic] = useState(0);
  const activa = !!carga || (corrida && !ESTADOS_FINALES.has(corrida.estado));
  useEffect(() => {
    if (!activa) return undefined;
    const id = setInterval(() => setTic((t) => t + 1), 1000); // reloj de "transcurrido"
    return () => clearInterval(id);
  }, [activa]);

  if (!corrida && !carga && !errorCarga && !aviso) return null;
  return (
    <section className="tarjeta-actividad" aria-live="polite" aria-label="Actividad">
      {corrida && <Simulacion corrida={corrida} onCancelar={onCancelarCorrida} onDescartar={onDescartarCorrida} />}
      {carga && <CargaMapa carga={carga} onCancelar={onCancelarCarga} />}
      {aviso && <AvisoCarga aviso={aviso} onDescartar={onDescartarAviso} />}
      {errorCarga && (
        <div className="ta-item error">
          <div className="ta-titulo">
            <strong>No se pudieron cargar los trips</strong>
            <button type="button" className="ta-cerrar" onClick={onDescartarError} aria-label="Cerrar aviso">
              ×
            </button>
          </div>
          <p className="ta-error">{errorCarga}</p>
        </div>
      )}
    </section>
  );
}
