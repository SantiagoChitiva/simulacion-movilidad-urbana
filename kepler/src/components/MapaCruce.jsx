import React, { useEffect, useRef } from 'react';
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';

// Teselas raster sin token: imágenes satelitales de Esri y el mapa de OpenStreetMap
const FUENTES = {
  satelite: {
    tiles: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
    attribution: 'Imágenes © Esri, Maxar, Earthstar Geographics',
    maxzoom: 19,
  },
  mapa: {
    tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
    attribution: '© OpenStreetMap',
    maxzoom: 19,
  },
};

const estilo = (modo) => ({
  version: 8,
  sources: { base: { type: 'raster', tileSize: 256, ...FUENTES[modo] } },
  layers: [{ id: 'base', type: 'raster', source: 'base' }],
});

/** Mapa pequeño centrado en el cruce, en vista satelital o de calles, con un anillo en el punto. */
export default function MapaCruce({ lon, lat, modo }) {
  const contenedor = useRef(null);
  const mapa = useRef(null);
  const marcador = useRef(null);

  useEffect(() => {
    const m = new maplibregl.Map({
      container: contenedor.current,
      style: estilo(modo),
      center: [lon, lat],
      zoom: 18,
      attributionControl: { compact: true },
    });
    m.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    const anillo = document.createElement('div');
    anillo.className = 'mc-anillo';
    marcador.current = new maplibregl.Marker({ element: anillo }).setLngLat([lon, lat]).addTo(m);
    mapa.current = m;
    return () => m.remove();
    // el mapa se crea una vez; los cambios de cruce y de modo se aplican abajo
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    mapa.current?.setStyle(estilo(modo));
  }, [modo]);

  useEffect(() => {
    mapa.current?.jumpTo({ center: [lon, lat], zoom: 18 });
    marcador.current?.setLngLat([lon, lat]);
  }, [lon, lat]);

  // maplibre le pone position: relative al contenedor: el tamaño va en un envoltorio
  return (
    <div className="vc-marco">
      <div ref={contenedor} className="vc-mapa" />
    </div>
  );
}
