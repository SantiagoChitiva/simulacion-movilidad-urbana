import React, { useEffect, useState } from 'react';
import { obtenerValidacion } from '../api';
import { descargarCsv, imprimirReporte } from '../exportar';

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));
const MODOS = { auto: 'auto', moto: 'moto', taxi: 'taxi', especial: 'especial', escolar: 'escolar', bici: 'bici', bus: 'bus' };
const SENTIDO = { 'N-S': 'norte → sur', 'S-N': 'sur → norte', 'W-E': 'oeste → este', 'E-W': 'este → oeste' };

/** La frase que resume la validación para quien no conoce el GEH. */
function resumenEnPalabras(v) {
  if (!v.puntos) return 'No hay puntos de aforo comparables en esta simulación.';
  const base = `${v.cumplen} de ${v.puntos} puntos de aforo (${v.porcentaje} %) tienen un volumen simulado parecido al contado en la calle (GEH < ${v.umbral_geh}).`;
  const criterio = v.cumple_criterio
    ? ` Se cumple el criterio usual de calibración (al menos ${v.criterio_porcentaje} %).`
    : ` El criterio usual de calibración pide al menos ${v.criterio_porcentaje} %: el modelo todavía no reproduce los volúmenes de la calle.`;
  const razon = v.razon_volumen != null
    ? ` En esos puntos la simulación lleva el ${Math.round(v.razon_volumen * 100)} % de los vehículos aforados.`
    : '';
  return base + criterio + razon;
}

const filasCsv = (v) => [
  ['id', 'direccion', 'sentido', 'via', 'modos', 'simulado_veh_h', 'aforo_veh_h', 'geh', 'cumple'],
  ...v.filas.map((f) => [f.id, f.direccion, f.sentido, f.via ?? '', f.modos.join(' '), f.simulado, f.real, f.geh, f.cumple ? 'si' : 'no']),
];

/** Pestaña Validar: volúmenes simulados contra los aforos de la hora de máxima demanda (GEH). */
export default function PanelValidacion({ corrida, etiquetaCorrida, puntosVisibles, onAlternarPuntos, onMostrarPuntos }) {
  const [validacion, setValidacion] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelado = false;
    setValidacion(null);
    setError(null);
    obtenerValidacion(corrida)
      .then((v) => !cancelado && setValidacion(v))
      .catch((e) => !cancelado && setError(e.message));
    return () => {
      cancelado = true;
    };
  }, [corrida]);

  useEffect(() => {
    onMostrarPuntos(puntosVisibles && validacion ? validacion.filas : null);
  }, [validacion, puntosVisibles, onMostrarPuntos]);

  const exportarPdf = () => {
    try {
      imprimirReporte('Validación de la simulación con aforos (GEH)', [
        { parrafos: [`Simulación: ${etiquetaCorrida}. Periodo del aforo: ${validacion.periodo}.`, resumenEnPalabras(validacion)] },
        {
          titulo: 'Puntos de aforo',
          tabla: {
            encabezado: ['Punto', 'Sentido', 'Vía', 'Simulado (veh/h)', 'Aforo (veh/h)', 'GEH'],
            filas: validacion.filas.map((f) => [`${f.id} · ${f.direccion}`, SENTIDO[f.sentido] ?? f.sentido, f.via ?? '—', numero(f.simulado), numero(f.real), f.geh]),
          },
        },
        {
          titulo: 'Cómo se calcula',
          parrafos: [
            'GEH = √(2 (M − C)² / (M + C)), con M el volumen simulado y C el aforado en la hora de máxima demanda. Un GEH menor que 5 indica que los dos volúmenes son parecidos.',
            'Aforos: Encuesta de Movilidad 2023 (EODI), base de aforos de la hora de máxima demanda publicada en SIMUR. Solo se comparan los modos que la simulación tiene (los camiones y TransMilenio troncal no se simulan).',
          ],
        },
      ]);
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <section className="tc">
      <p className="pd-nota">
        Compara los vehículos que pasan por cada punto de aforo de Usaquén en la hora de más tráfico de la simulación con
        los que contó la Encuesta de Movilidad 2023 en la calle ({etiquetaCorrida}).
      </p>
      {error && <p className="pd-error">{error}</p>}
      {!validacion && !error && <p className="pd-nota">Cargando…</p>}
      {validacion && (
        <>
          <p className="tc-veredicto">{resumenEnPalabras(validacion)}</p>
          <div className="pv-acciones">
            <label>
              <input type="checkbox" checked={puntosVisibles} onChange={(e) => onAlternarPuntos(e.target.checked)} />
              Ver los puntos en el mapa
            </label>
            <button type="button" onClick={() => descargarCsv(`validacion-geh-${validacion.periodo}`, filasCsv(validacion))}>CSV</button>
            <button type="button" onClick={exportarPdf}>PDF</button>
          </div>
          <table className="fi-tabla tc-tabla">
            <thead>
              <tr><th>Punto</th><th>Simulado</th><th>Aforo</th><th>GEH</th></tr>
            </thead>
            <tbody>
              {validacion.filas.map((f) => (
                <tr key={`${f.id}-${f.sentido}`}>
                  <td title={`Modos comparados: ${f.modos.map((m) => MODOS[m] ?? m).join(', ')}`}>
                    {f.via ?? f.direccion} <small>({SENTIDO[f.sentido] ?? f.sentido})</small>
                  </td>
                  <td>{numero(f.simulado)}</td>
                  <td>{numero(f.real)}</td>
                  <td className={f.cumple ? 'tc-mejor' : 'pv-falla'}>{f.geh.toLocaleString('es-CO')}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <details className="fi-detalles">
            <summary>Cómo leer esta tabla</summary>
            <p className="pd-nota">
              Simulado y aforo están en vehículos por hora, en la hora de máxima demanda del periodo {validacion.periodo}.
              El GEH mide qué tan distintos son: menos de 5 es un buen ajuste. Los aforos cuentan todo el tráfico de la
              calle; la simulación solo tiene los viajes de la encuesta que empiezan y terminan en Usaquén (más el tráfico
              de paso si la corrida lo incluye), así que en las avenidas suele quedar por debajo.
            </p>
            {validacion.estaciones_no_simuladas?.length > 0 && (
              <p className="pd-nota">
                Estaciones sin comparar porque su modo no se simula: {validacion.estaciones_no_simuladas.join(', ')}.
              </p>
            )}
          </details>
        </>
      )}
    </section>
  );
}
