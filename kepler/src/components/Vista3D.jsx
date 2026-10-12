import React, { useEffect, useRef, useState, useCallback } from 'react';
import { crearSesion3D, obtenerGeometria3D, cerrarSesion3D } from '../api';

const WS_BASE = window.location.origin.replace(/^http/, 'ws').replace(':5173', ':8000');
const WS_API = `${WS_BASE}/api`;

// Colores por estado de semáforo (letra SUMO → CSS)
const COLOR_LUZ = { G: '#00e676', g: '#00c853', y: '#ffd600', Y: '#ff6f00', r: '#f44336', R: '#b71c1c' };

const numero = (n) => (n == null ? '—' : Math.round(n).toLocaleString('es-CO'));

function indicadorLuz(estado = '') {
  const luces = [...new Set([...estado])].map((c) => COLOR_LUZ[c]).filter(Boolean);
  return luces[0] ?? '#888';
}

/**
 * Vista 3D en vivo de una intersección usando un Canvas 2D simple.
 * Muestra vehículos como puntos de colores y el estado del semáforo como cuadros.
 * (Reemplazable por DeckGL cuando se instale la dependencia.)
 */
export default function Vista3D({ id, corrida, onCerrar }) {
  const canvasRef = useRef(null);
  const wsRef = useRef(null);
  const frameRef = useRef(null);
  const [sid, setSid] = useState(null);
  const [geometria, setGeometria] = useState(null);
  const [estado, setEstado] = useState({ pausada: false, velocidad: 1, tiempo: 0 });
  const [errorMsg, setErrorMsg] = useState(null);
  const [conectado, setConectado] = useState(false);

  // Abrir sesión al montar
  useEffect(() => {
    let cancelado = false;
    crearSesion3D(id, { escenario_run_id: corrida?.id ?? null, programa_id: '0' })
      .then(async ({ sid: nuevoSid }) => {
        if (cancelado) return;
        setSid(nuevoSid);
        const geo = await obtenerGeometria3D(nuevoSid).catch(() => null);
        if (!cancelado) setGeometria(geo);
      })
      .catch((e) => !cancelado && setErrorMsg(e.message));
    return () => {
      cancelado = true;
    };
  }, [id, corrida]);

  // Conectar WebSocket al obtener el sid
  useEffect(() => {
    if (!sid) return undefined;
    const ws = new WebSocket(`${WS_API}/sesiones/${sid}`);
    wsRef.current = ws;
    ws.onopen = () => setConectado(true);
    ws.onclose = () => setConectado(false);
    ws.onerror = () => setErrorMsg('Error de conexión WebSocket');
    ws.onmessage = (ev) => {
      try {
        const frame = JSON.parse(ev.data);
        if (frame.tipo === 'frame') {
          frameRef.current = frame;
          setEstado((prev) => ({ ...prev, tiempo: frame.tiempo }));
        } else if (frame.tipo === 'error') {
          setErrorMsg(frame.mensaje);
        }
      } catch {
        // ignorar mensajes malformados
      }
    };
    return () => {
      ws.close();
      wsRef.current = null;
    };
  }, [sid]);

  // Cerrar sesión al desmontar
  useEffect(() => {
    return () => {
      if (sid) cerrarSesion3D(sid).catch(() => {});
    };
  }, [sid]);

  // Bucle de dibujado
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const ctx = canvas.getContext('2d');
    let animId;
    let bbox = null;

    // Calcular bounding box de la geometría
    if (geometria?.carriles?.length) {
      let minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
      for (const carril of geometria.carriles) {
        for (const [lon, lat] of carril.coords) {
          if (lon < minLon) minLon = lon;
          if (lon > maxLon) maxLon = lon;
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
        }
      }
      bbox = { minLon, maxLon, minLat, maxLat };
    }

    const toCanvas = (lon, lat) => {
      if (!bbox) return [canvas.width / 2, canvas.height / 2];
      const padding = 30;
      const w = canvas.width - 2 * padding;
      const h = canvas.height - 2 * padding;
      const x = padding + ((lon - bbox.minLon) / (bbox.maxLon - bbox.minLon || 1)) * w;
      const y = padding + (1 - (lat - bbox.minLat) / (bbox.maxLat - bbox.minLat || 1)) * h;
      return [x, y];
    };

    const dibujar = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = '#111';
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      // Carriles
      if (geometria?.carriles) {
        ctx.strokeStyle = '#334';
        ctx.lineWidth = 3;
        for (const carril of geometria.carriles) {
          if (!carril.coords.length) continue;
          ctx.beginPath();
          const [x0, y0] = toCanvas(carril.coords[0][0], carril.coords[0][1]);
          ctx.moveTo(x0, y0);
          for (let i = 1; i < carril.coords.length; i++) {
            const [x, y] = toCanvas(carril.coords[i][0], carril.coords[i][1]);
            ctx.lineTo(x, y);
          }
          ctx.stroke();
        }
      }

      const frame = frameRef.current;
      if (!frame) {
        animId = requestAnimationFrame(dibujar);
        return;
      }

      // Vehículos
      for (const v of frame.vehiculos ?? []) {
        const [x, y] = toCanvas(v.lon, v.lat);
        ctx.beginPath();
        ctx.arc(x, y, 5, 0, Math.PI * 2);
        ctx.fillStyle = v.tipo?.startsWith('auto') ? '#2196f3'
          : v.tipo?.startsWith('moto') ? '#ff9800'
          : v.tipo?.startsWith('bici') ? '#4caf50'
          : v.tipo?.startsWith('taxi') ? '#ffeb3b'
          : '#90a4ae';
        ctx.fill();
      }

      // Personas
      for (const p of frame.personas ?? []) {
        const [x, y] = toCanvas(p.lon, p.lat);
        ctx.beginPath();
        ctx.arc(x, y, 3, 0, Math.PI * 2);
        ctx.fillStyle = '#e91e63';
        ctx.fill();
      }

      // Semáforos
      for (const s of frame.semaforos ?? []) {
        const color = indicadorLuz(s.estado);
        ctx.fillStyle = color;
        ctx.fillRect(10, 10, 24, 24);
        ctx.fillStyle = '#fff';
        ctx.font = '10px monospace';
        ctx.fillText(`F${s.fase + 1} ${s.tiempo_restante?.toFixed(0) ?? ''}s`, 38, 26);
      }

      animId = requestAnimationFrame(dibujar);
    };

    animId = requestAnimationFrame(dibujar);
    return () => cancelAnimationFrame(animId);
  }, [geometria]);

  const enviarCmd = useCallback((cmd) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(cmd));
    }
  }, []);

  const alternarPausa = () => {
    const nuevaPausa = !estado.pausada;
    setEstado((prev) => ({ ...prev, pausada: nuevaPausa }));
    enviarCmd({ pausa: nuevaPausa });
  };

  const cambiarVelocidad = (v) => {
    setEstado((prev) => ({ ...prev, velocidad: v }));
    enviarCmd({ velocidad: v });
  };

  const formatTiempo = (s) => {
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return `${h}:${String(m).padStart(2, '0')}`;
  };

  return (
    <div className="vista3d-overlay">
      <div className="vista3d-panel">
        <header className="vista3d-encabezado">
          <h3>Vista 3D · {id}</h3>
          <span className={`vista3d-estado ${conectado ? 'conectado' : 'desconectado'}`}>
            {conectado ? 'En vivo' : sid ? 'Conectando…' : 'Iniciando…'}
          </span>
          <button type="button" className="pd-cerrar" onClick={onCerrar} aria-label="Cerrar vista 3D">×</button>
        </header>

        {errorMsg && <p className="pd-error">{errorMsg}</p>}

        <canvas
          ref={canvasRef}
          width={560}
          height={400}
          className="vista3d-canvas"
          aria-label="Simulación 3D en vivo"
        />

        <div className="vista3d-controles">
          <button type="button" onClick={alternarPausa} disabled={!conectado}>
            {estado.pausada ? '▶ Continuar' : '⏸ Pausar'}
          </button>
          <span>Velocidad:</span>
          {[0.5, 1, 2, 5].map((v) => (
            <button
              key={v}
              type="button"
              className={estado.velocidad === v ? 'activo' : ''}
              onClick={() => cambiarVelocidad(v)}
              disabled={!conectado}
            >
              {v}×
            </button>
          ))}
          <span className="vista3d-tiempo">⏱ {formatTiempo(estado.tiempo)}</span>
        </div>

        <p className="pd-nota">
          Vista simplificada: carriles en azul oscuro, vehículos en puntos de colores, peatones en rosa.
          El cuadro superior izquierdo muestra el estado del semáforo y el tiempo restante de la fase.
        </p>
      </div>
    </div>
  );
}
