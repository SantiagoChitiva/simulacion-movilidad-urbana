import { useCallback, useEffect, useRef, useState } from 'react';
import {
  ESTADOS_FINALES,
  cancelarSimulacion,
  crearSimulacion,
  listarSimulaciones,
  obtenerSimulacion,
} from './api';

const INTERVALO_CONSULTA_MS = 2000;

/** Tamaño actual de la ventana: kepler necesita ancho y alto explícitos. */
export function useTamanoVentana() {
  const [tamano, setTamano] = useState({ ancho: window.innerWidth, alto: window.innerHeight });
  useEffect(() => {
    const alCambiar = () => setTamano({ ancho: window.innerWidth, alto: window.innerHeight });
    window.addEventListener('resize', alCambiar);
    return () => window.removeEventListener('resize', alCambiar);
  }, []);
  return tamano;
}

/**
 * Corridas de simulación: historial, la corrida en curso (con su avance) y cancelación.
 * `onTerminada(corrida)` se llama cuando la corrida en curso termina bien.
 */
export function useCorridas(onTerminada) {
  const [historial, setHistorial] = useState([]);
  const [activa, setActiva] = useState(null);   // en curso, o la última que terminó (hasta descartarla)
  const [error, setError] = useState(null);
  const alTerminar = useRef(onTerminada);
  alTerminar.current = onTerminada;

  const refrescar = useCallback(
    () =>
      listarSimulaciones()
        .then((h) => {
          setHistorial(h);
          return h;
        })
        .catch((e) => setError(e.message)),
    []
  );

  // al abrir: historial, y retomar una corrida que siga en curso
  useEffect(() => {
    refrescar().then((h) => {
      const pendiente = h?.find((c) => !ESTADOS_FINALES.has(c.estado));
      if (pendiente) setActiva(pendiente);
    });
  }, [refrescar]);

  const enCurso = !!activa && !ESTADOS_FINALES.has(activa.estado);

  useEffect(() => {
    if (!enCurso) return undefined;
    const id = setInterval(() => {
      obtenerSimulacion(activa.id)
        .then((c) => {
          setActiva(c);
          if (ESTADOS_FINALES.has(c.estado)) {
            refrescar();
            if (c.estado === 'terminado') alTerminar.current?.(c);
          }
        })
        .catch((e) => setError(e.message));
    }, INTERVALO_CONSULTA_MS);
    return () => clearInterval(id);
  }, [enCurso, activa?.id, refrescar]);

  const lanzar = useCallback(
    (solicitud) => {
      setError(null);
      return crearSimulacion(solicitud)
        .then((c) => {
          setActiva(c);
          refrescar();
        })
        .catch((e) => setError(e.message));
    },
    [refrescar]
  );

  const cancelar = useCallback(() => {
    if (!activa) return;
    cancelarSimulacion(activa.id)
      .then(setActiva)
      .catch((e) => setError(e.message));
  }, [activa]);

  const descartar = useCallback(() => {
    setActiva(null);
    setError(null);
  }, []);

  return { historial, activa, enCurso, error, lanzar, cancelar, descartar };
}
