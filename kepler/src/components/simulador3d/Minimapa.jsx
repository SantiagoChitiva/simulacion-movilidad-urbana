import React, { useEffect, useRef } from 'react';
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

// Teselas raster de OpenStreetMap: no requieren token (uso de desarrollo/académico)
const ESTILO = {
  version: 8,
  sources: {
    osm: {
      type: 'raster',
      tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      tileSize: 256,
      attribution: '© OpenStreetMap',
    },
  },
  layers: [{ id: 'osm', type: 'raster', source: 'osm' }],
};

const vacio = { type: 'FeatureCollection', features: [] };

/**
 * Mapa 2D "tipo Maps" en la esquina: el cruce estudiado, la zona simulada, el actor
 * seguido y el rastro que ha dejado.
 */
export default function Minimapa({ nodo, bbox, ego, egoId, rumbo = null, seguir = true }) {
  const contenedor = useRef(null);
  const mapa = useRef(null);
  const listo = useRef(false);
  const rastro = useRef([]);

  useEffect(() => {
    const m = new maplibregl.Map({
      container: contenedor.current,
      style: ESTILO,
      center: [nodo.lon, nodo.lat],
      zoom: 16.3,
      attributionControl: { compact: true },
    });
    mapa.current = m;
    m.on('load', () => {
      const [w, s, e, n] = bbox;
      m.addSource('zona', {
        type: 'geojson',
        data: { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[w, s], [e, s], [e, n], [w, n], [w, s]]] } },
      });
      m.addLayer({ id: 'zona', type: 'line', source: 'zona', paint: { 'line-color': '#1e88e5', 'line-width': 1.5, 'line-dasharray': [2, 2] } });
      m.addSource('cruce', { type: 'geojson', data: { type: 'Feature', geometry: { type: 'Point', coordinates: [nodo.lon, nodo.lat] } } });
      m.addLayer({ id: 'cruce', type: 'circle', source: 'cruce', paint: { 'circle-radius': 7, 'circle-color': '#ffb300', 'circle-stroke-color': '#000', 'circle-stroke-width': 1.5 } });
      m.addSource('rastro', { type: 'geojson', data: vacio });
      m.addLayer({ id: 'rastro', type: 'line', source: 'rastro', paint: { 'line-color': '#00bcd4', 'line-width': 3, 'line-opacity': 0.8 } });
      m.addSource('ego', { type: 'geojson', data: vacio });
      m.addLayer({ id: 'ego', type: 'circle', source: 'ego', paint: { 'circle-radius': 6, 'circle-color': '#00e5ff', 'circle-stroke-color': '#003040', 'circle-stroke-width': 2 } });
      listo.current = true;
    });
    return () => {
      listo.current = false;
      m.remove();
    };
  }, [nodo.lon, nodo.lat, bbox]);

  // otro actor seguido: se borra el rastro del anterior
  useEffect(() => {
    rastro.current = [];
  }, [egoId]);

  useEffect(() => {
    const m = mapa.current;
    if (!m || !listo.current) return;
    if (!ego) {
      rastro.current = [];
      m.getSource('ego')?.setData(vacio);
      m.getSource('rastro')?.setData(vacio);
      return;
    }
    const punto = [ego.lon, ego.lat];
    const ultimo = rastro.current[rastro.current.length - 1];
    if (!ultimo || Math.hypot(ultimo[0] - punto[0], ultimo[1] - punto[1]) > 0.00002) {
      rastro.current = [...rastro.current.slice(-300), punto];
    }
    m.getSource('ego')?.setData({ type: 'Feature', geometry: { type: 'Point', coordinates: punto } });
    m.getSource('rastro')?.setData({ type: 'Feature', geometry: { type: 'LineString', coordinates: rastro.current } });
    // como un navegador: el mapa gira para que el sentido de marcha quede hacia arriba
    if (seguir) m.easeTo({ center: punto, bearing: rumbo ?? m.getBearing(), duration: 300 });
  }, [ego, seguir, rumbo]);

  // maplibre le pone position: relative al contenedor del mapa: el posicionamiento va en un envoltorio
  return (
    <div className="sim3d-minimapa" aria-label="Mapa 2D de la zona">
      <div ref={contenedor} className="sim3d-minimapa-mapa" />
      <span className="sim3d-minimapa-norte" style={{ transform: `rotate(${-(rumbo ?? 0)}deg)` }} title="Norte">N</span>
    </div>
  );
}
