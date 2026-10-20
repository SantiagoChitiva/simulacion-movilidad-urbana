import React, { Suspense, lazy, useState } from 'react';

// maplibre solo se descarga cuando alguien abre Satélite o Mapa
const MapaCruce = lazy(() => import('./MapaCruce'));

const MODOS = [['streetview', 'Street View'], ['satelite', 'Satélite'], ['mapa', 'Mapa']];

// Embed público de Google Maps: no pide clave, pero no es una API oficial. Si deja de
// funcionar queda el enlace de abajo, que siempre abre el mismo punto en Google Maps.
const urlStreetView = (lat, lon) => `https://maps.google.com/maps?layer=c&cbll=${lat},${lon}&cbp=11,0,0,0,0&output=svembed`;
const urlGoogleMaps = (lat, lon) => `https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${lat},${lon}`;

/** "Ver el cruce": Street View, imagen satelital o mapa de calles alrededor del punto. */
export default function VistaCruce({ lon, lat }) {
  const [modo, setModo] = useState('streetview');
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
  return (
    <section className="vc">
      <div className="vc-cabecera">
        <h3>Ver el cruce</h3>
        <div className="vc-modos" role="tablist" aria-label="Vista del cruce">
          {MODOS.map(([id, etiqueta]) => (
            <button key={id} type="button" role="tab" aria-selected={modo === id} className={modo === id ? 'activo' : ''} onClick={() => setModo(id)}>
              {etiqueta}
            </button>
          ))}
        </div>
      </div>
      {modo === 'streetview' ? (
        <div className="vc-marco">
          <iframe
            key={`${lat},${lon}`}
            title="Street View del cruce"
            className="vc-mapa"
            src={urlStreetView(lat, lon)}
            loading="lazy"
            referrerPolicy="no-referrer-when-downgrade"
            allowFullScreen
          />
        </div>
      ) : (
        <Suspense fallback={<div className="vc-marco vc-cargando">Cargando mapa…</div>}>
          <MapaCruce lon={lon} lat={lat} modo={modo} />
        </Suspense>
      )}
      <a className="vc-enlace" href={urlGoogleMaps(lat, lon)} target="_blank" rel="noreferrer">
        Abrir en Google Maps ↗
      </a>
    </section>
  );
}
