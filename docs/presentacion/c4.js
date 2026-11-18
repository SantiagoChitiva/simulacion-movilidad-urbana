/* Visor C4 con "zoom" entre niveles.
 *
 * Cada nivel es un SVG exportado de draw.io (copiado en assets/c4/). Las zonas clicables y las regiones
 * de destino están en coordenadas del viewBox de cada SVG. Si se edita el
 * .drawio, hay que reexportar el SVG y ajustar los rectángulos de abajo.
 *
 * Los rectángulos se derivaron de las posiciones de tesis.drawio:
 *   contexto:     coordenadas medidas sobre el render (px / 1,5)
 *   contenedores: x_svg = x_drawio - 38,   y_svg = y_drawio - 140
 *   componentes:  x_svg = x_drawio - 1239, y_svg = y_drawio + 421
 */
const C4 = (() => {
  const BASE = 'assets/c4/';
  const AREA = { x: 0, y: 84, w: 1920, h: 940 };   // zona bajo la barra superior
  const ZOOM_EXTRA = 1.5;                          // cuánto se aleja el nivel entrante al empezar

  const NIVELES = {
    contexto: {
      titulo: 'Nivel 1 · Contexto', archivo: 'tesis-c4-context.svg', raster: 'tesis-c4-context.webp', vw: 1404, vh: 1044,
      zonas: [
        { etiqueta: 'Sitio web', rect: [582, 322, 241, 120], destino: ['contenedores', [842, 382, 400, 320]] },
        { etiqueta: 'Servicio de simulación', rect: [582, 641, 241, 121], destino: ['contenedores', [642, 940, 800, 760]] },
      ],
    },
    contenedores: {
      titulo: 'Nivel 2 · Contenedores', archivo: 'tesis-c4-container.svg', raster: 'tesis-c4-container.webp', vw: 2046, vh: 1704,
      zonas: [
        { etiqueta: 'UI (React)', rect: [922, 457, 240, 160], destino: ['componentes', [1039, 259, 1120, 760]] },
        { etiqueta: 'API (FastAPI)', rect: [910, 1020, 252, 120], destino: ['componentes', [1081, 1221, 1040, 320]] },
        { etiqueta: 'ETL', rect: [908, 1220, 252, 120], destino: ['componentes', [761, 1581, 1680, 560]] },
        { etiqueta: 'Almacén de archivos', rect: [922, 1460, 240, 140], destino: ['componentes', [1159, 2138, 640, 340]] },
      ],
    },
    componentes: {
      titulo: 'Nivel 3 · Componentes', archivo: 'tesis-c4-component.svg', raster: 'tesis-c4-component.webp', vw: 3023, vh: 2465,
      zonas: [],
    },
  };
  const ORDEN = ['contexto', 'contenedores', 'componentes'];
  const VISTA_COMPLETA = (n) => [0, 0, NIVELES[n].vw, NIVELES[n].vh];

  // Cámara {k, tx, ty} para que `rect` (en unidades del viewBox) llene el área.
  function camara(rect) {
    const [x, y, w, h] = rect;
    const k = Math.min(AREA.w / w, AREA.h / h) * 0.94;
    return { k, tx: AREA.x + (AREA.w - w * k) / 2 - x * k, ty: AREA.y + (AREA.h - h * k) / 2 - y * k };
  }
  const kAjustado = (nombre) => camara(VISTA_COMPLETA(nombre)).k;
  const K_MIN = 0.85, K_MAX = 12;   // límites de zoom, relativos al zoom que muestra todo el diagrama

  // Mismo centro, rectángulo más grande (cámara más lejos).
  const alejar = (rect, f) => {
    const [x, y, w, h] = rect;
    return [x - (w * (f - 1)) / 2, y - (h * (f - 1)) / 2, w * f, h * f];
  };
  const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
  const siguienteCuadro = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));

  function iniciar(raiz, Reveal) {
    const capas = {};
    const cam = {};
    let actual = 'contexto';
    let ocupado = false;
    // Para volver: región que ocupaba cada nivel al entrar desde el anterior.
    const pila = [];

    raiz.innerHTML = `
      <div class="barra">
        <div class="titulo">Arquitectura · C4</div>
        <div class="migas"></div>
        <div class="zoom">
          <button class="zoom-menos" title="Alejar">−</button>
          <button class="zoom-todo" title="Ver todo el diagrama">Ver todo</button>
          <button class="zoom-mas" title="Acercar">+</button>
        </div>
        <button class="subir">← Subir nivel</button>
      </div>`;
    const migas = raiz.querySelector('.migas');
    const botonSubir = raiz.querySelector('.subir');

    for (const nombre of ORDEN) {
      const n = NIVELES[nombre];
      const capa = document.createElement('div');
      capa.className = 'capa';
      const mundo = document.createElement('div');
      mundo.className = 'mundo sin-trans reposo';
      mundo.style.width = n.vw + 'px';
      mundo.style.height = n.vh + 'px';
      // Mapa de bits (liviano de mover) siempre debajo; el SVG vectorial solo se ve en reposo.
      const raster = document.createElement('img');
      raster.className = 'raster';
      raster.src = BASE + n.raster;
      raster.alt = n.titulo;
      raster.draggable = false;
      raster.decoding = 'sync';
      const vector = document.createElement('img');
      vector.className = 'vec';
      vector.src = BASE + n.archivo;
      vector.alt = '';
      vector.draggable = false;
      mundo.append(raster, vector);
      for (const z of n.zonas) {
        const d = document.createElement('div');
        d.className = 'zona pulso';
        d.dataset.etiqueta = z.etiqueta;
        const [x, y, w, h] = z.rect;
        Object.assign(d.style, { left: x + 'px', top: y + 'px', width: w + 'px', height: h + 'px' });
        // La etiqueta y el borde escalan con el mundo; se compensan para que se vean legibles.
        d.addEventListener('click', (e) => { e.stopPropagation(); entrar(nombre, z); });
        mundo.appendChild(d);
      }
      capa.appendChild(mundo);
      raiz.appendChild(capa);
      capas[nombre] = { capa, mundo };
      cam[nombre] = camara(VISTA_COMPLETA(nombre));
    }

    // Borde y etiqueta de las zonas se compensan con el zoom para verse siempre igual de legibles.
    const estilo = document.createElement('style');
    estilo.textContent = '#c4 .zona::after { font-size: calc(40px * var(--inv, 1)); }';
    document.head.appendChild(estilo);

    // Mientras la cámara se mueve se muestra el mapa de bits (la GPU solo lo traslada y escala);
    // al quedar quieta se muestra el SVG, que se rasteriza una sola vez a la escala final.
    const temporizadores = {};
    function moviendo(nombre, ms) {
      const { mundo } = capas[nombre];
      mundo.classList.remove('reposo');
      clearTimeout(temporizadores[nombre]);
      temporizadores[nombre] = setTimeout(() => mundo.classList.add('reposo'), ms);
    }

    function aplicar(nombre) {
      const { mundo } = capas[nombre];
      const { k, tx, ty } = cam[nombre];
      mundo.style.transform = `translate(${tx}px, ${ty}px) scale(${k})`;
      mundo.style.setProperty('--inv', 1 / k);
      mundo.querySelectorAll('.zona').forEach((d) => {
        d.style.borderWidth = 6 / k + 'px';
        d.style.borderRadius = 24 / k + 'px';
      });
    }
    for (const nombre of ORDEN) aplicar(nombre);

    function pintarMigas() {
      migas.innerHTML = '';
      ORDEN.forEach((nombre, i) => {
        const el = document.createElement('span');
        const profundidad = ORDEN.indexOf(actual);
        el.className = 'miga' + (nombre === actual ? ' activa' : i < profundidad ? ' nav' : '');
        el.textContent = NIVELES[nombre].titulo;
        if (i < profundidad) el.addEventListener('click', () => volverA(nombre));
        migas.appendChild(el);
      });
      botonSubir.classList.toggle('visible', actual !== 'contexto');
    }

    async function fijar(nombre, rect, animar) {
      const { mundo } = capas[nombre];
      mundo.classList.toggle('sin-trans', !animar);
      moviendo(nombre, animar ? 1150 : 200);
      if (!animar) await siguienteCuadro();
      cam[nombre] = camara(rect);
      aplicar(nombre);
    }

    async function entrar(desde, zona) {
      if (ocupado) return;
      ocupado = true;
      const [hasta, regionDestino] = zona.destino;
      pila.push({ nivel: desde, zona });
      const origen = capas[desde], destino = capas[hasta];

      // El destino arranca alejado y encuadrado sobre la región; se acerca mientras el origen se agranda.
      await fijar(hasta, alejar(regionDestino, ZOOM_EXTRA), false);
      fijar(desde, alejar(zona.rect, 1.15), true);
      await pausa(450);
      destino.capa.classList.add('visible');
      origen.capa.classList.remove('visible');
      await fijar(hasta, regionDestino, true);
      actual = hasta;
      pintarMigas();
      await pausa(1000);
      await fijar(desde, VISTA_COMPLETA(desde), false);
      ocupado = false;
    }

    async function subir() {
      if (ocupado || !pila.length) return;
      ocupado = true;
      const { nivel: arriba, zona } = pila.pop();
      const abajo = actual;
      const regionAbajo = zona.destino[1];
      const capaArriba = capas[arriba], capaAbajo = capas[abajo];

      // El nivel superior aparece acercado sobre el elemento y se aleja hasta la vista completa.
      await fijar(arriba, alejar(zona.rect, 1.15), false);
      fijar(abajo, alejar(regionAbajo, ZOOM_EXTRA), true);
      await pausa(350);
      capaArriba.capa.classList.add('visible');
      capaAbajo.capa.classList.remove('visible');
      await fijar(arriba, VISTA_COMPLETA(arriba), true);
      actual = arriba;
      pintarMigas();
      await pausa(1000);
      await fijar(abajo, regionAbajo, false);
      ocupado = false;
    }

    async function volverA(nombre) {
      while (ORDEN.indexOf(actual) > ORDEN.indexOf(nombre) && !ocupado) {
        await subir();
        await pausa(50);
      }
    }

    // ---- Zoom y desplazamiento libres sobre el nivel visible ----
    function moverLibre(nombre) {
      capas[nombre].mundo.classList.add('sin-trans');
      moviendo(nombre, 220);
      aplicar(nombre);
    }
    function zoomEn(px, py, factor) {
      const c = cam[actual], kf = kAjustado(actual);
      const k = Math.min(kf * K_MAX, Math.max(kf * K_MIN, c.k * factor));
      const f = k / c.k;
      // Mantiene fijo el punto del diagrama que está bajo (px, py).
      cam[actual] = { k, tx: px - (px - c.tx) * f, ty: py - (py - c.ty) * f };
      moverLibre(actual);
    }
    const centro = () => [AREA.x + AREA.w / 2, AREA.y + AREA.h / 2];
    const esc = () => { const r = raiz.getBoundingClientRect(); return r.width / 1920; };

    raiz.addEventListener('wheel', (e) => {
      if (ocupado) return;
      e.preventDefault();
      e.stopPropagation();
      const r = raiz.getBoundingClientRect(), s = esc();
      zoomEn((e.clientX - r.left) / s, (e.clientY - r.top) / s, Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0018)));
    }, { passive: false });

    let arrastre = null, huboArrastre = false;
    raiz.addEventListener('pointerdown', (e) => {
      if (ocupado || e.button !== 0 || e.target.closest('.barra')) return;
      arrastre = { x: e.clientX, y: e.clientY, tx: cam[actual].tx, ty: cam[actual].ty };
      huboArrastre = false;
    });
    window.addEventListener('pointermove', (e) => {
      if (!arrastre || ocupado) return;
      const dx = e.clientX - arrastre.x, dy = e.clientY - arrastre.y;
      if (!huboArrastre && Math.hypot(dx, dy) < 6) return;
      huboArrastre = true;
      raiz.classList.add('arrastrando');
      const s = esc();
      cam[actual] = { ...cam[actual], tx: arrastre.tx + dx / s, ty: arrastre.ty + dy / s };
      moverLibre(actual);
    });
    window.addEventListener('pointerup', () => {
      arrastre = null;
      raiz.classList.remove('arrastrando');
      setTimeout(() => { huboArrastre = false; }, 0);
    });
    // Un arrastre no debe contar como clic sobre una zona.
    raiz.addEventListener('click', (e) => { if (huboArrastre) { e.stopPropagation(); e.preventDefault(); } }, true);

    async function ajustar() {
      if (ocupado) return;
      await fijar(actual, VISTA_COMPLETA(actual), true);
    }
    raiz.querySelector('.zoom-mas').addEventListener('click', () => { if (!ocupado) { const [x, y] = centro(); zoomEn(x, y, 1.4); } });
    raiz.querySelector('.zoom-menos').addEventListener('click', () => { if (!ocupado) { const [x, y] = centro(); zoomEn(x, y, 1 / 1.4); } });
    raiz.querySelector('.zoom-todo').addEventListener('click', ajustar);
    raiz.addEventListener('dblclick', (e) => { if (!e.target.closest('.zona, .barra')) ajustar(); });

    // Calentamiento: decodifica los mapas de bits y obliga a pintar los niveles ocultos una vez,
    // para que el primer zoom no tenga el tirón de la primera pintura.
    let calentado = false;
    async function calentar() {
      if (calentado) return;
      calentado = true;
      await Promise.all([...raiz.querySelectorAll('img.raster')].map((i) => i.decode().catch(() => {})));
      for (const nombre of ORDEN) if (nombre !== actual) capas[nombre].capa.classList.add('calentando');
      await siguienteCuadro();
      await siguienteCuadro();
      for (const nombre of ORDEN) capas[nombre].capa.classList.remove('calentando');
    }
    const esC4 = (slide) => slide && slide.contains(raiz);
    Reveal.on('ready', (ev) => { if (esC4(ev.currentSlide)) calentar(); });
    Reveal.on('slidechanged', (ev) => { if (esC4(ev.currentSlide)) calentar(); });

    botonSubir.addEventListener('click', subir);
    capas.contexto.capa.classList.add('visible');
    pintarMigas();

    // Retroceso sube de nivel solo cuando la diapositiva C4 está activa.
    document.addEventListener('keydown', (e) => {
      const activa = Reveal.getCurrentSlide();
      if (!activa || !activa.contains(raiz)) return;
      if (e.key === 'Backspace' || e.key === 'u') { e.preventDefault(); subir(); }
    });
    // Al salir y volver a la diapositiva, reinicia en el contexto.
    Reveal.on('slidechanged', (ev) => {
      if (!ev.previousSlide || !ev.previousSlide.contains(raiz)) return;
      pila.length = 0;
      actual = 'contexto';
      for (const nombre of ORDEN) {
        capas[nombre].capa.classList.toggle('visible', nombre === 'contexto');
        fijar(nombre, VISTA_COMPLETA(nombre), false);
      }
      pintarMigas();
    });
  }

  return { iniciar };
})();
