// Exportar resultados del visor sin librerías: CSV con un Blob y PDF con el diálogo de
// impresión del navegador (que permite "Guardar como PDF").

const escaparCsv = (v) => {
  const s = v == null ? '' : String(v);
  return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** Descarga `filas` (lista de listas; la primera es el encabezado) como CSV. */
export function descargarCsv(nombre, filas) {
  // BOM: Excel abre el CSV en UTF-8 y respeta las tildes
  const texto = `﻿${filas.map((f) => f.map(escaparCsv).join(',')).join('\r\n')}`;
  const url = URL.createObjectURL(new Blob([texto], { type: 'text/csv;charset=utf-8' }));
  const enlace = document.createElement('a');
  enlace.href = url;
  enlace.download = nombre.endsWith('.csv') ? nombre : `${nombre}.csv`;
  document.body.appendChild(enlace);
  enlace.click();
  enlace.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const escaparHtml = (s) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/**
 * Abre el reporte en una ventana nueva y lanza la impresión (Guardar como PDF).
 * `secciones`: [{ titulo, parrafos?: [texto], tabla?: { encabezado: [...], filas: [[...]] } }]
 */
export function imprimirReporte(titulo, secciones) {
  const cuerpo = secciones
    .map((s) => {
      const parrafos = (s.parrafos ?? []).map((p) => `<p>${escaparHtml(p)}</p>`).join('');
      const tabla = s.tabla
        ? `<table><thead><tr>${s.tabla.encabezado.map((c) => `<th>${escaparHtml(c)}</th>`).join('')}</tr></thead>`
          + `<tbody>${s.tabla.filas.map((f) => `<tr>${f.map((c) => `<td>${escaparHtml(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`
        : '';
      return `<section>${s.titulo ? `<h2>${escaparHtml(s.titulo)}</h2>` : ''}${parrafos}${tabla}</section>`;
    })
    .join('');
  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${escaparHtml(titulo)}</title>
<style>
  body { font: 12px/1.45 system-ui, sans-serif; color: #111; margin: 24px; }
  h1 { font-size: 18px; margin: 0 0 4px; } h2 { font-size: 14px; margin: 18px 0 6px; }
  .fecha { color: #555; margin-bottom: 12px; }
  table { border-collapse: collapse; width: 100%; margin-top: 6px; }
  th, td { border: 1px solid #bbb; padding: 4px 6px; text-align: left; vertical-align: top; }
  th { background: #eee; }
  @page { margin: 14mm; }
</style></head><body>
<h1>${escaparHtml(titulo)}</h1>
<div class="fecha">Generado el ${escaparHtml(new Date().toLocaleString('es-CO'))} · Simulación de movilidad de Usaquén (SUMO)</div>
${cuerpo}
</body></html>`;
  const ventana = window.open('', '_blank');
  if (!ventana) throw new Error('El navegador bloqueó la ventana del reporte; permite las ventanas emergentes.');
  ventana.document.open();
  ventana.document.write(html);
  ventana.document.close();
  ventana.focus();
  setTimeout(() => ventana.print(), 300);
}
