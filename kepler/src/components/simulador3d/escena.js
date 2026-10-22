// Escena three.js de un lado de la comparación (sin semáforo / con semáforo propuesto).
//
// Coordenadas: la API manda todo en coordenadas de la red de SUMO (x este, y norte,
// z altura en metros). En three.js el eje vertical es Y, así que
//   three.x = x - origen.x,  three.y = z - origen.z,  three.z = -(y - origen.y)
// con el cruce como origen. Los vehículos de SUMO se ubican por el parachoques
// delantero y su ángulo es en grados desde el norte, en sentido horario.
//
// Rumbos (grados desde el norte, horario) → vectores en el plano de SUMO:
//   adelante d = (sin r, cos r), derecha n = (cos r, -sin r).
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

// ───────────────────────────────────────────────────────────── paleta (atardecer)

const CIELO_ARRIBA = '#5d7fae';
const CIELO_HORIZONTE = '#f3c9a1';
const NIEBLA = 0xe9c9a8;
const COLOR_EGO = 0x00e5ff;
const BLANCO_VIA = 0xeeeee6;
const AMARILLO_VIA = 0xe7b416;

const COLORES_AUTO = [0xd9dadc, 0x23262b, 0x8f1d1d, 0x23407a, 0x7b7f86, 0xf4f4f2, 0x2f5236, 0x6b5640, 0xb7b9bd, 0x3b6ea8];
const COLORES_EDIFICIO = [0xe6dccb, 0xd3bfa3, 0xc8c2b8, 0xefe7da, 0xb9a48e, 0xd9c9b6, 0xa9aeb4, 0xc9b49a];
const COLORES_ROPA = [0x2f4f7f, 0x8b2f2f, 0x3d6b3d, 0x222222, 0x7a5c2e, 0x5c3d7a, 0xc77d1a, 0xdddddd];

// Dimensiones (largo, ancho, alto) por vType de SUMO
const DIMENSIONES = {
  auto: [4.5, 1.8, 1.45], taxi: [4.3, 1.72, 1.5], especial: [4.9, 1.95, 1.8], informal: [4.6, 1.8, 1.55],
  otro: [4.5, 1.8, 1.5], moto: [2.1, 0.8, 1.2], bici: [1.8, 0.6, 1.1], bus_pt: [12, 2.55, 3.1],
  escolar: [9, 2.4, 2.9], peaton: [0.5, 0.5, 1.72],
};

const LUZ = {
  verde: new THREE.Color(0x29ff6a), amarillo: new THREE.Color(0xffc400), rojo: new THREE.Color(0xff2a1a),
  apagada: new THREE.Color(0x1a1a1a),
};

const hash = (texto) => {
  let h = 0;
  for (let i = 0; i < texto.length; i += 1) h = (h * 31 + texto.charCodeAt(i)) | 0;
  return Math.abs(h);
};

const colorLuz = (letra) => {
  if (letra === 'G' || letra === 'g') return 'verde';
  if (letra === 'y' || letra === 'Y' || letra === 'u') return 'amarillo';
  if (letra === 'r' || letra === 'R' || letra === 's') return 'rojo';
  return 'apagada';
};

const masPermisivo = (colores) => {
  if (colores.includes('verde')) return 'verde';
  if (colores.includes('amarillo')) return 'amarillo';
  if (colores.includes('rojo')) return 'rojo';
  return 'apagada';
};

const rad = THREE.MathUtils.degToRad;
const adelante = (r) => [Math.sin(rad(r)), Math.cos(rad(r))];
const derecha = (r) => [Math.cos(rad(r)), -Math.sin(rad(r))];

// ───────────────────────────────────────────────────────────── texturas procedurales

function texturaAsfalto() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#45484d';
  g.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 9000; i += 1) {
    const v = 55 + Math.random() * 40;
    g.fillStyle = `rgba(${v},${v},${v + 3},${0.25 + Math.random() * 0.35})`;
    g.fillRect(Math.random() * 256, Math.random() * 256, 1.5, 1.5);
  }
  for (let i = 0; i < 14; i += 1) {   // parches y manchas
    g.fillStyle = `rgba(30,32,36,${0.08 + Math.random() * 0.1})`;
    g.beginPath();
    g.ellipse(Math.random() * 256, Math.random() * 256, 10 + Math.random() * 30, 6 + Math.random() * 18, Math.random() * 3, 0, Math.PI * 2);
    g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function texturaVentanas() {
  // una celda = un piso (3 m) x un vano (3,5 m); el color del muro lo pone el material
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#ffffff';
  g.fillRect(0, 0, 64, 64);
  g.fillStyle = 'rgba(0,0,0,0.08)';
  g.fillRect(0, 58, 64, 6);           // losa
  g.fillStyle = '#5b6878';
  g.fillRect(12, 14, 40, 32);
  g.fillStyle = '#8fa3b8';
  g.fillRect(14, 16, 17, 28);
  g.fillStyle = '#7d91a6';
  g.fillRect(33, 16, 17, 28);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.repeat.set(1 / 3.5, 1 / 3);
  return t;
}

function texturaCielo() {
  const c = document.createElement('canvas');
  c.width = 4;
  c.height = 256;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0, CIELO_ARRIBA);
  grad.addColorStop(0.38, '#9db3cf');
  grad.addColorStop(0.5, CIELO_HORIZONTE);
  grad.addColorStop(0.56, '#d9b08c');
  grad.addColorStop(1, '#8b7a66');
  g.fillStyle = grad;
  g.fillRect(0, 0, 4, 256);
  const t = new THREE.CanvasTexture(c);
  t.mapping = THREE.EquirectangularReflectionMapping;
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texturaTexto(lineas, { ancho = 512, alto = 256, fondo = '#16263f', color = '#ffffff', acento = '#ffb300' } = {}) {
  const c = document.createElement('canvas');
  c.width = ancho;
  c.height = alto;
  const g = c.getContext('2d');
  g.fillStyle = fondo;
  g.fillRect(0, 0, ancho, alto);
  g.fillStyle = acento;
  g.fillRect(0, 0, ancho, 10);
  let y = 50;
  lineas.forEach(([texto, tam, peso, col]) => {
    g.fillStyle = col ?? color;
    g.font = `${peso ?? 600} ${tam}px system-ui, sans-serif`;
    g.fillText(texto, 24, y);
    y += tam * 1.35;
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function texturaPare() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  g.translate(64, 64);
  g.fillStyle = '#ffffff';
  g.beginPath();
  for (let i = 0; i < 8; i += 1) {
    const a = (Math.PI / 8) * (2 * i + 1);
    g.lineTo(Math.cos(a) * 62, Math.sin(a) * 62);
  }
  g.fill();
  g.fillStyle = '#c8102e';
  g.beginPath();
  for (let i = 0; i < 8; i += 1) {
    const a = (Math.PI / 8) * (2 * i + 1);
    g.lineTo(Math.cos(a) * 56, Math.sin(a) * 56);
  }
  g.fill();
  g.fillStyle = '#ffffff';
  g.font = 'bold 38px system-ui, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText('PARE', 0, 2);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// ───────────────────────────────────────────────────────────── geometría auxiliar

/** Normal izquierda (en el plano xz de three) de cada punto de una polilínea. */
function normales(puntos) {
  return puntos.map((p, i) => {
    const prev = puntos[Math.max(i - 1, 0)];
    const next = puntos[Math.min(i + 1, puntos.length - 1)];
    const dx = next.x - prev.x;
    const dz = next.z - prev.z;
    const largo = Math.hypot(dx, dz) || 1;
    return [dz / largo, -dx / largo];   // izquierda del sentido, mirando desde arriba
  });
}

/** Cinta de ancho `ancho` a lo largo de `puntos`, desplazada `d` a la izquierda, con UV en metros. */
function cinta(puntos, ancho, alzado, d = 0) {
  if (puntos.length < 2) return null;
  const ns = normales(puntos);
  const pos = [];
  const uv = [];
  const idx = [];
  let s = 0;
  for (let i = 0; i < puntos.length; i += 1) {
    const p = puntos[i];
    if (i > 0) s += Math.hypot(p.x - puntos[i - 1].x, p.z - puntos[i - 1].z);
    const [nx, nz] = ns[i];
    const izq = d + ancho / 2;
    const der = d - ancho / 2;
    pos.push(p.x + nx * izq, p.y + alzado, p.z + nz * izq, p.x + nx * der, p.y + alzado, p.z + nz * der);
    uv.push(0, s, ancho, s);
    if (i > 0) {
      const b = (i - 1) * 2;
      idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/** Cinta elevada con faldones a los lados (andenes y bordillos). */
function cintaElevada(puntos, ancho, alto, d = 0, faldon = 0.6) {
  const tapa = cinta(puntos, ancho, alto, d);
  if (!tapa) return null;
  const lados = [];
  for (const borde of [d + ancho / 2, d - ancho / 2]) {
    const ns = normales(puntos);
    const pos = [];
    const idx = [];
    puntos.forEach((p, i) => {
      const [nx, nz] = ns[i];
      pos.push(p.x + nx * borde, p.y + alto, p.z + nz * borde, p.x + nx * borde, p.y - faldon, p.z + nz * borde);
      if (i > 0) {
        const b = (i - 1) * 2;
        idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
      }
    });
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(new Array((pos.length / 3) * 2).fill(0), 2));
    g.setIndex(idx);
    g.computeVertexNormals();
    lados.push(g);
  }
  return mergeGeometries([tapa, ...lados]);
}

/** Tramos de una polilínea: [desde, hasta] en metros a lo largo (para las líneas discontinuas). */
function recortar(puntos, desde, hasta) {
  const salida = [];
  let s = 0;
  for (let i = 1; i < puntos.length; i += 1) {
    const a = puntos[i - 1];
    const b = puntos[i];
    const l = Math.hypot(b.x - a.x, b.z - a.z);
    const s0 = s;
    const s1 = s + l;
    if (s1 >= desde && s0 <= hasta) {
      const t0 = Math.max(0, (desde - s0) / (l || 1));
      const t1 = Math.min(1, (hasta - s0) / (l || 1));
      if (!salida.length) salida.push(new THREE.Vector3().lerpVectors(a, b, t0));
      salida.push(new THREE.Vector3().lerpVectors(a, b, t1));
    }
    s = s1;
  }
  return salida;
}

function largo(puntos) {
  let s = 0;
  for (let i = 1; i < puntos.length; i += 1) s += Math.hypot(puntos[i].x - puntos[i - 1].x, puntos[i].z - puntos[i - 1].z);
  return s;
}

/** Separa una geometría con grupos (ExtrudeGeometry: 0 = tapas, 1 = muros) en dos. */
function separarGrupos(geo) {
  const partes = [[], []];
  const pos = geo.getAttribute('position');
  const uv = geo.getAttribute('uv');
  const nor = geo.getAttribute('normal');
  for (const grupo of geo.groups) {
    partes[grupo.materialIndex].push([grupo.start, grupo.count]);
  }
  return partes.map((rangos) => {
    const p = [];
    const u = [];
    const n = [];
    for (const [ini, cant] of rangos) {
      for (let i = ini; i < ini + cant; i += 1) {
        p.push(pos.getX(i), pos.getY(i), pos.getZ(i));
        u.push(uv.getX(i), uv.getY(i));
        n.push(nor.getX(i), nor.getY(i), nor.getZ(i));
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(u, 2));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(n, 3));
    return g;
  });
}

/** Pinta una geometría con un color por vértice (para fusionar piezas de un modelo). */
function pintar(geo, color) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  const c = new THREE.Color(color);
  const n = g.getAttribute('position').count;
  const col = new Float32Array(n * 3);
  for (let i = 0; i < n; i += 1) {
    col[i * 3] = c.r;
    col[i * 3 + 1] = c.g;
    col[i * 3 + 2] = c.b;
  }
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  if (g.getAttribute('uv')) g.deleteAttribute('uv');
  return g;
}

const caja = (a, h, l, x, y, z) => new THREE.BoxGeometry(a, h, l).translate(x, y, z);

// ───────────────────────────────────────────────────────────── modelos (caché por tipo)

const MATERIALES = {};
const material = (clave, crear) => {
  if (!MATERIALES[clave]) MATERIALES[clave] = crear();
  return MATERIALES[clave];
};
const matPintura = (color) => material(`pintura-${color}`, () => new THREE.MeshStandardMaterial({ color, metalness: 0.35, roughness: 0.38 }));
const matDetalles = () => material('detalles', () => new THREE.MeshStandardMaterial({ vertexColors: true, metalness: 0.2, roughness: 0.55 }));
const matStop = (encendido) => material(`stop-${encendido}`, () => new THREE.MeshStandardMaterial({
  color: encendido ? 0xff2020 : 0x8a1414, emissive: encendido ? 0xff1010 : 0x5a0000, emissiveIntensity: encendido ? 2.6 : 0.9,
}));
const matFaros = () => material('faros', () => new THREE.MeshStandardMaterial({ color: 0xfff6d8, emissive: 0xfff1c0, emissiveIntensity: 1.6 }));

const GEOMETRIAS = {};

/** Perfil lateral de un carro (z = largo desde el frente, y = alto), extruido a lo ancho. */
function carroceria(l, a, h) {
  const s = new THREE.Shape();
  const base = 0.3;
  s.moveTo(0, base + 0.15);
  s.lineTo(0.05, base + 0.55);                 // parachoques delantero
  s.lineTo(l * 0.24, base + 0.72);             // capó
  s.lineTo(l * 0.38, h);                       // parabrisas
  s.lineTo(l * 0.76, h);                       // techo
  s.lineTo(l * 0.92, base + 0.78);             // luneta
  s.lineTo(l, base + 0.68);                    // baúl
  s.lineTo(l, base + 0.1);
  s.lineTo(0, base + 0.1);
  const g = new THREE.ExtrudeGeometry(s, { depth: a, bevelEnabled: true, bevelThickness: 0.04, bevelSize: 0.04, bevelSegments: 1 });
  // el perfil está en (x = largo, y = alto); se rota para que el largo vaya en +z
  g.rotateY(-Math.PI / 2);
  g.translate(a / 2, 0, 0);
  return g;
}

function vidrios(l, a, h) {
  const base = 0.3;
  const s = new THREE.Shape();
  s.moveTo(l * 0.255, base + 0.76);
  s.lineTo(l * 0.385, h - 0.05);
  s.lineTo(l * 0.755, h - 0.05);
  s.lineTo(l * 0.9, base + 0.8);
  const g = new THREE.ExtrudeGeometry(s, { depth: a + 0.04, bevelEnabled: false });
  g.rotateY(-Math.PI / 2);
  g.translate(a / 2 + 0.02, 0, 0);
  return g;
}

function ruedas(a, posiciones, r = 0.33, ancho = 0.24) {
  const piezas = [];
  for (const z of posiciones) {
    for (const lado of [-1, 1]) {
      const rueda = new THREE.CylinderGeometry(r, r, ancho, 14).rotateZ(Math.PI / 2).translate(lado * (a / 2 - ancho / 2 + 0.04), r, z);
      piezas.push(pintar(rueda, 0x151515));
      const rin = new THREE.CylinderGeometry(r * 0.55, r * 0.55, ancho + 0.02, 10).rotateZ(Math.PI / 2).translate(lado * (a / 2 - ancho / 2 + 0.05), r, z);
      piezas.push(pintar(rin, 0x9a9da2));
    }
  }
  return piezas;
}

/** {cuerpo, detalles, stop, faros} de un tipo de vehículo; el modelo mira a -z con el frente en z = 0. */
function geometriasVehiculo(tipo) {
  if (GEOMETRIAS[tipo]) return GEOMETRIAS[tipo];
  const [l, a, h] = DIMENSIONES[tipo] ?? DIMENSIONES.auto;
  let cuerpo;
  let detalles;
  let stop;
  let faros;
  if (tipo === 'bus_pt' || tipo === 'escolar') {
    cuerpo = mergeGeometries([caja(a, h - 0.45, l, 0, 0.45 + (h - 0.45) / 2, l / 2)]);
    detalles = mergeGeometries([
      pintar(caja(a + 0.02, 1.0, l - 1.6, 0, 1.95, l / 2 + 0.4), 0x1c2733),      // ventanas laterales
      pintar(caja(a - 0.3, 1.3, 0.06, 0, 1.85, 0.0), 0x1c2733),                  // parabrisas
      pintar(caja(a + 0.03, 0.12, l, 0, 0.5, l / 2), 0x333333),                  // franja
      ...ruedas(a, [1.6, l - 2.4], 0.5, 0.3),
    ]);
    stop = mergeGeometries([caja(0.3, 0.25, 0.05, -a / 2 + 0.3, 0.9, l), caja(0.3, 0.25, 0.05, a / 2 - 0.3, 0.9, l)]);
    faros = mergeGeometries([caja(0.3, 0.2, 0.05, -a / 2 + 0.35, 0.8, -0.01), caja(0.3, 0.2, 0.05, a / 2 - 0.35, 0.8, -0.01)]);
  } else if (tipo === 'moto' || tipo === 'bici') {
    const moto = tipo === 'moto';
    cuerpo = mergeGeometries([caja(0.3, moto ? 0.45 : 0.08, l * 0.7, 0, moto ? 0.65 : 0.6, l / 2)]);
    detalles = mergeGeometries([
      ...[0.35, l - 0.35].map((z) => pintar(new THREE.TorusGeometry(0.3, moto ? 0.08 : 0.03, 6, 16).rotateY(Math.PI / 2).translate(0, 0.33, z), 0x151515)),
      pintar(caja(0.36, 0.6, 0.3, 0, 1.12, l / 2 + 0.15), 0x2f3d55),             // torso
      pintar(new THREE.SphereGeometry(0.16, 10, 8).translate(0, 1.6, l / 2 + 0.05), moto ? 0xeeeeee : 0xffb300),
      pintar(caja(0.12, 0.5, 0.12, -0.12, 0.65, l / 2 + 0.25), 0x22252b),          // piernas
      pintar(caja(0.12, 0.5, 0.12, 0.12, 0.65, l / 2 + 0.25), 0x22252b),
    ]);
    stop = caja(0.15, 0.08, 0.04, 0, 0.8, l);
    faros = caja(0.14, 0.12, 0.04, 0, 0.9, -0.01);
  } else {
    cuerpo = carroceria(l, a, h);
    detalles = mergeGeometries([
      pintar(vidrios(l, a, h), 0x1a222c),
      ...ruedas(a, [0.85, l - 0.85]),
      pintar(caja(a * 0.92, 0.08, 0.06, 0, 0.42, -0.02), 0x202020),             // parachoques
      pintar(caja(a * 0.92, 0.08, 0.06, 0, 0.42, l + 0.02), 0x202020),
      pintar(caja(0.1, 0.12, 0.22, -a / 2 - 0.05, 1.0, l * 0.36), 0x202020),     // espejos
      pintar(caja(0.1, 0.12, 0.22, a / 2 + 0.05, 1.0, l * 0.36), 0x202020),
    ]);
    stop = mergeGeometries([caja(0.42, 0.12, 0.05, -a / 2 + 0.3, 0.88, l + 0.01), caja(0.42, 0.12, 0.05, a / 2 - 0.3, 0.88, l + 0.01)]);
    faros = mergeGeometries([caja(0.36, 0.12, 0.05, -a / 2 + 0.3, 0.75, -0.01), caja(0.36, 0.12, 0.05, a / 2 - 0.3, 0.75, -0.01)]);
  }
  GEOMETRIAS[tipo] = { cuerpo, detalles, stop, faros };
  return GEOMETRIAS[tipo];
}

function geometriaPeaton(color) {
  const clave = `peaton-${color}`;
  if (GEOMETRIAS[clave]) return GEOMETRIAS[clave];
  GEOMETRIAS[clave] = mergeGeometries([
    pintar(caja(0.14, 0.82, 0.16, -0.1, 0.41, 0), 0x2a2a35),
    pintar(caja(0.14, 0.82, 0.16, 0.1, 0.41, 0), 0x2a2a35),
    pintar(caja(0.44, 0.62, 0.26, 0, 1.13, 0), color),
    pintar(caja(0.1, 0.55, 0.12, -0.28, 1.12, 0), color),
    pintar(caja(0.1, 0.55, 0.12, 0.28, 1.12, 0), color),
    pintar(new THREE.SphereGeometry(0.13, 10, 8).translate(0, 1.6, 0), 0xc69c74),
  ]);
  return GEOMETRIAS[clave];
}

function modeloVehiculo(tipo, id) {
  const g = geometriasVehiculo(tipo);
  const grupo = new THREE.Group();
  let color = COLORES_AUTO[hash(id) % COLORES_AUTO.length];
  if (tipo === 'taxi') color = 0xffcc00;
  if (tipo === 'bus_pt') color = hash(id) % 3 === 0 ? 0x2f8f3a : 0xc0262d;   // SITP verde / TransMilenio rojo
  if (tipo === 'escolar') color = 0xf5c400;
  if (tipo === 'bici') color = 0x2e7d32;
  if (tipo === 'moto') color = 0x1d1f24;
  const cuerpo = new THREE.Mesh(g.cuerpo, matPintura(color));
  const detalles = new THREE.Mesh(g.detalles, matDetalles());
  const stop = new THREE.Mesh(g.stop, matStop(false));
  stop.name = 'stop';
  const faros = new THREE.Mesh(g.faros, matFaros());
  for (const m of [cuerpo, detalles]) {
    m.castShadow = true;
  }
  grupo.add(cuerpo, detalles, stop, faros);
  return grupo;
}

function modeloPeaton(id) {
  const grupo = new THREE.Group();
  const cuerpo = new THREE.Mesh(geometriaPeaton(COLORES_ROPA[hash(id) % COLORES_ROPA.length]), matDetalles());
  cuerpo.castShadow = true;
  cuerpo.name = 'cuerpo';
  grupo.add(cuerpo);
  return grupo;
}

function marcadorEgo() {
  const g = new THREE.Group();
  const anillo = new THREE.Mesh(
    new THREE.RingGeometry(1.6, 1.9, 40),
    new THREE.MeshBasicMaterial({ color: COLOR_EGO, side: THREE.DoubleSide, transparent: true, opacity: 0.7, depthWrite: false })
  );
  anillo.rotation.x = -Math.PI / 2;
  anillo.position.y = 0.12;
  g.add(anillo);
  return g;
}

/** Haz de luz aditivo frente al vehículo seguido (los faros encendidos al atardecer). */
function hazFaros() {
  const geo = new THREE.ConeGeometry(4.5, 16, 24, 1, true).rotateX(Math.PI / 2).translate(0, 0, -8);
  const mat = new THREE.MeshBasicMaterial({
    color: 0xfff2cc, transparent: true, opacity: 0.09, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  });
  const cono = new THREE.Mesh(geo, mat);
  cono.position.set(0, 0.8, 0);
  cono.scale.set(1, 0.18, 1);
  return cono;
}

// ───────────────────────────────────────────────────────────── escena

export default class Escena3D {
  constructor(contenedor, geometria, { conSemaforo, cartel = null }) {
    this.contenedor = contenedor;
    this.geometria = geometria;
    this.conSemaforo = conSemaforo;
    this.cartel = cartel;
    const nodo = geometria.nodo;
    this.origen = { x: nodo.x, y: nodo.y, z: nodo.z };

    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    contenedor.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.scene.background = texturaCielo();
    this.scene.fog = new THREE.Fog(NIEBLA, 140, 620);
    this.camera = new THREE.PerspectiveCamera(65, 1, 0.2, 2500);
    this.camera.position.set(-45, 40, 45);
    this.camera.lookAt(0, 0, 0);

    this.scene.add(new THREE.HemisphereLight(0xffe3c4, 0x4a4436, 1.25));
    // sol bajo del occidente (atardecer en los cerros): sombras largas
    this.sol = new THREE.DirectionalLight(0xffcf9a, 2.4);
    this.sol.position.set(-90, 60, 35);
    this.sol.castShadow = true;
    this.sol.shadow.mapSize.set(2048, 2048);
    const sc = this.sol.shadow.camera;
    sc.left = -75;
    sc.right = 75;
    sc.top = 75;
    sc.bottom = -75;
    sc.near = 10;
    sc.far = 400;
    this.sol.shadow.bias = -0.0005;
    this.scene.add(this.sol, this.sol.target);

    this.actores = new Map();       // id -> { obj, tipo, desde, hasta, angDesde, angHasta, v }
    this.ego = null;
    this.marcador = marcadorEgo();
    this.marcador.visible = false;
    this.scene.add(this.marcador);
    this.haz = hazFaros();
    this.luzEgo = new THREE.SpotLight(0xfff0d0, 30, 45, Math.PI / 7, 0.5, 1.4);
    this.luzEgo.visible = false;
    this.scene.add(this.luzEgo, this.luzEgo.target);
    this.modoCamara = 'persecucion';
    this.objetivoAereo = new THREE.Vector3(0, 0, 0);
    this.anguloAereo = Math.PI * 0.75;
    this.ultimoFrame = performance.now();
    this.intervalo = 200;
    this.cabezas = [];
    this.obstaculos = [];           // mallas de edificios: la cámara no las atraviesa
    this.rayo = new THREE.Raycaster();

    this._construirMundo();
    this.redimensionar();
  }

  a3(x, y, z) {
    return new THREE.Vector3(x - this.origen.x, (z ?? this.origen.z) - this.origen.z, -(y - this.origen.y));
  }

  _forma(forma) {
    return forma.map(([x, y, z]) => this.a3(x, y, z));
  }

  _construirMundo() {
    const g = this.geometria;
    const asfalto = texturaAsfalto();
    const matAsfalto = new THREE.MeshStandardMaterial({ map: asfalto, roughness: 0.95, metalness: 0, side: THREE.DoubleSide });
    asfalto.repeat.set(1 / 7, 1 / 7);
    const matCruce = new THREE.MeshStandardMaterial({ map: asfalto, roughness: 0.95, color: 0xf0f0f0, side: THREE.DoubleSide });
    const marca = (color) => new THREE.MeshStandardMaterial({
      color, roughness: 0.7, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, side: THREE.DoubleSide,
    });
    const matBlanco = marca(BLANCO_VIA);
    const matAmarillo = marca(AMARILLO_VIA);
    const matAnden = new THREE.MeshStandardMaterial({ color: 0xb9b3a6, roughness: 0.9, side: THREE.DoubleSide });
    const matSendero = new THREE.MeshStandardMaterial({ color: 0xa9a294, roughness: 0.95, side: THREE.DoubleSide });
    const matCiclo = new THREE.MeshStandardMaterial({ color: 0x9a3a32, roughness: 0.9, side: THREE.DoubleSide });

    this._terreno();

    const vias = [];
    const blancas = [];
    const amarillas = [];
    const andenes = [];
    const senderos = [];
    const ciclo = [];
    const porEdge = new Map();
    for (const c of g.calzadas) {
      const puntos = this._forma(c.forma);
      const geo = cinta(puntos, c.ancho, 0.02);
      if (geo) vias.push(geo);
      if (!porEdge.has(c.edge)) porEdge.set(c.edge, []);
      porEdge.get(c.edge).push({ ...c, puntos });
    }
    for (const carriles of porEdge.values()) {
      carriles.sort((p, q) => p.indice - q.indice);
      const total = largo(carriles[0].puntos);
      for (const c of carriles) {
        const n = c.n_carriles;
        // borde derecho (carril 0): continua blanca y andén
        if (c.indice === 0) {
          const borde = cinta(c.puntos, 0.13, 0.03, -c.ancho / 2 + 0.22);
          if (borde) blancas.push(borde);
          const anden = cintaElevada(c.puntos, 2.6, 0.16, -c.ancho / 2 - 1.3);
          if (anden) andenes.push(anden);
        }
        if (c.indice === n - 1 || c.indice === carriles[carriles.length - 1].indice) {
          if (c.opuesto) {
            // cada sentido pinta su línea: juntas quedan como doble amarilla continua
            const am = cinta(c.puntos, 0.12, 0.03, c.ancho / 2 - 0.1);
            if (am) amarillas.push(am);
          } else {
            const borde = cinta(c.puntos, 0.13, 0.03, c.ancho / 2 - 0.22);
            if (borde) blancas.push(borde);
            const anden = cintaElevada(c.puntos, 2.6, 0.16, c.ancho / 2 + 1.3);
            if (anden) andenes.push(anden);
          }
        } else {
          // divisoria entre carriles del mismo sentido: discontinua 3 m / 6 m
          for (let s = 2; s < total - 2; s += 9) {
            const tramo = recortar(c.puntos, s, Math.min(s + 3, total - 2));
            const geo = tramo.length > 1 ? cinta(tramo, 0.12, 0.03, c.ancho / 2) : null;
            if (geo) blancas.push(geo);
          }
        }
      }
    }
    for (const c of g.senderos) {
      const geo = cintaElevada(this._forma(c.forma), Math.max(c.ancho, 1.8), 0.08, 0, 0.4);
      if (geo) senderos.push(geo);
    }
    for (const c of g.ciclorrutas) {
      const geo = cinta(this._forma(c.forma), Math.max(c.ancho, 1.6), 0.04);
      if (geo) ciclo.push(geo);
    }

    // polígonos de los cruces, con la z de cada vértice
    const cruces = [];
    for (const cruce of g.cruces) {
      if (cruce.forma.length < 3) continue;
      const pts = cruce.forma.map(([x, y, z]) => this.a3(x, y, z));
      const contorno = pts.map((p) => new THREE.Vector2(p.x, p.z));
      const tris = THREE.ShapeUtils.triangulateShape(contorno, []);
      if (!tris.length) continue;
      const pos = [];
      const uv = [];
      for (const tri of tris) {
        for (const k of tri) {
          pos.push(pts[k].x, pts[k].y + 0.025, pts[k].z);
          uv.push(pts[k].x, pts[k].z);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
      geo.computeVertexNormals();
      // la triangulación puede quedar al revés según el sentido del contorno
      if (geo.getAttribute('normal').getY(0) < 0) {
        for (let i = 0; i < pos.length; i += 9) {
          for (let k = 0; k < 3; k += 1) [pos[i + 3 + k], pos[i + 6 + k]] = [pos[i + 6 + k], pos[i + 3 + k]];
        }
        geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        geo.computeVertexNormals();
      }
      cruces.push(geo);
    }

    this._bocas(blancas);

    const agregar = (geos, mat, recibe = true) => {
      if (!geos.length) return null;
      const malla = new THREE.Mesh(mergeGeometries(geos), mat);
      malla.receiveShadow = recibe;
      this.scene.add(malla);
      return malla;
    };
    agregar(vias, matAsfalto);
    agregar(cruces, matCruce);
    agregar(andenes, matAnden);
    agregar(senderos, matSendero);
    agregar(ciclo, matCiclo);
    agregar(blancas, matBlanco);
    agregar(amarillas, matAmarillo);

    this._edificios();
    this._mobiliario(porEdge);
    if (this.conSemaforo) this._semaforos();
    else this._senalesPare();
    if (this.cartel) this._valla();
  }

  _terreno() {
    const t = this.geometria.terreno;
    if (!t) return;
    const pos = [];
    const col = [];
    const base = new THREE.Color(0x6f7f4a);
    const tierra = new THREE.Color(0x8b7d5c);
    for (let j = 0; j < t.ny; j += 1) {
      for (let i = 0; i < t.nx; i += 1) {
        const x = t.x0 + i * t.paso;
        const y = t.y0 + j * t.paso;
        const p = this.a3(x, y, t.z[j * t.nx + i] - 0.4);
        pos.push(p.x, p.y, p.z);
        const c = base.clone().lerp(tierra, (hash(`${i},${j}`) % 100) / 260);
        col.push(c.r, c.g, c.b);
      }
    }
    const idx = [];
    for (let j = 0; j < t.ny - 1; j += 1) {
      for (let i = 0; i < t.nx - 1; i += 1) {
        const a = j * t.nx + i;
        const b = a + 1;
        const c = a + t.nx;
        const d = c + 1;
        idx.push(a, b, c, b, d, c);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
    geo.setIndex(idx);
    geo.computeVertexNormals();
    const malla = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, side: THREE.DoubleSide }));
    malla.receiveShadow = true;
    this.scene.add(malla);
    // horizonte: un plano grande bajo todo para que no se vea el vacío
    const lejos = new THREE.Mesh(new THREE.PlaneGeometry(6000, 6000), new THREE.MeshBasicMaterial({ color: 0x6d7a4c }));
    lejos.rotation.x = -Math.PI / 2;
    lejos.position.y = Math.min(...t.z) - this.origen.z - 3;
    this.scene.add(lejos);
  }

  /** Líneas de pare y cebras en las bocas del cruce estudiado. */
  _bocas(blancas) {
    const laterales = new Set(this.geometria.accesos.filter((a) => a.lateral).map((a) => a.edge));
    const franja = (x, y, z, rumbo, ancho, largoF, alto = 0.04) => {
      // rectángulo en el plano: `ancho` a lo largo del rumbo, `largoF` perpendicular
      const geo = new THREE.PlaneGeometry(largoF, ancho).rotateX(-Math.PI / 2);
      geo.rotateY(-rad(rumbo));
      const p = this.a3(x, y, z);
      geo.translate(p.x, p.y + alto, p.z);
      return geo;
    };
    for (const b of this.geometria.bocas) {
      const [dx, dy] = adelante(b.rumbo);
      const [nx, ny] = derecha(b.rumbo);
      const afuera = b.entra ? -1 : 1;   // hacia fuera del cruce, a lo largo del carril
      const [px, py, pz] = b.punto;
      // cebra: franjas de 0,5 m cada 1 m, a lo ancho del carril, entre 0,6 y 3,6 m de la boca
      const centro = 2.1;
      for (let o = -b.ancho / 2 + 0.45; o <= b.ancho / 2 - 0.3; o += 1.0) {
        blancas.push(franja(px + afuera * dx * centro + nx * o, py + afuera * dy * centro + ny * o, pz, b.rumbo, 3.0, 0.5));
      }
      // línea de pare: en el lado con semáforo en todos los accesos; sin él, en la vía que cede
      if (b.entra && (this.conSemaforo || laterales.has(b.edge))) {
        const d = 4.6;
        blancas.push(franja(px - dx * d, py - dy * d, pz, b.rumbo, 0.45, b.ancho - 0.2));
      }
    }
  }

  _edificios() {
    const ventanas = texturaVentanas();
    const muros = COLORES_EDIFICIO.map(() => []);
    const techos = [];
    for (const ed of this.geometria.edificios) {
      const contorno = ed.contorno.map(([x, y]) => new THREE.Vector2(x - this.origen.x, y - this.origen.y));
      if (contorno.length < 3) continue;
      let geo;
      try {
        geo = new THREE.ExtrudeGeometry(new THREE.Shape(contorno), { depth: ed.altura, bevelEnabled: false });
      } catch {
        continue;
      }
      geo.rotateX(-Math.PI / 2);
      geo.translate(0, ed.z - this.origen.z - 0.3, 0);
      const [tapa, muro] = separarGrupos(geo);
      techos.push(tapa);
      muros[hash(`${ed.contorno[0]}`) % muros.length].push(muro);
    }
    muros.forEach((geos, i) => {
      if (!geos.length) return;
      const malla = new THREE.Mesh(
        mergeGeometries(geos),
        new THREE.MeshStandardMaterial({ color: COLORES_EDIFICIO[i], map: ventanas, roughness: 0.85 })
      );
      malla.castShadow = true;
      malla.receiveShadow = true;
      this.scene.add(malla);
      this.obstaculos.push(malla);
    });
    if (techos.length) {
      const malla = new THREE.Mesh(mergeGeometries(techos), new THREE.MeshStandardMaterial({ color: 0x7c746a, roughness: 0.95 }));
      malla.receiveShadow = true;
      this.scene.add(malla);
    }
  }

  /** Postes de alumbrado y árboles en los andenes (instanciados). */
  _mobiliario(porEdge) {
    const postes = [];
    const arboles = [];
    for (const carriles of porEdge.values()) {
      const c = carriles[0];
      const puntos = c.puntos;
      const total = largo(puntos);
      if (total < 25) continue;
      const ancha = carriles.length >= 2;
      const paso = ancha ? 32 : 22;
      for (let s = 8 + (hash(c.edge) % 10); s < total - 6; s += paso) {
        const tramo = recortar(puntos, s, s + 0.5);
        if (tramo.length < 2) continue;
        const [a, b] = tramo;
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const l = Math.hypot(dx, dz) || 1;
        const izq = [dz / l, -dx / l];
        const d = -c.ancho / 2 - 2.2;
        const pos = new THREE.Vector3(a.x + izq[0] * d, a.y + 0.16, a.z + izq[1] * d);
        const rumbo = Math.atan2(izq[0], izq[1]);
        if (ancha) postes.push({ pos, rumbo });
        else if (hash(`${c.edge}${s}`) % 3) arboles.push({ pos, escala: 0.8 + (hash(`${s}${c.edge}`) % 50) / 100 });
      }
    }
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    if (postes.length) {
      const geo = mergeGeometries([
        pintar(new THREE.CylinderGeometry(0.08, 0.12, 8, 8).translate(0, 4, 0), 0x3a3d42),
        pintar(caja(0.08, 0.08, 2.2, 0, 7.9, 1.0), 0x3a3d42),
        pintar(caja(0.35, 0.12, 0.6, 0, 7.82, 2.0), 0xfff1cf),
      ]);
      const inst = new THREE.InstancedMesh(geo, matDetalles(), postes.length);
      postes.forEach(({ pos, rumbo }, i) => {
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rumbo + Math.PI);
        inst.setMatrixAt(i, m.compose(pos, q, new THREE.Vector3(1, 1, 1)));
      });
      inst.castShadow = true;
      this.scene.add(inst);
    }
    if (arboles.length) {
      const geo = mergeGeometries([
        pintar(new THREE.CylinderGeometry(0.12, 0.18, 2.4, 6).translate(0, 1.2, 0), 0x5a4330),
        pintar(new THREE.IcosahedronGeometry(1.7, 0).translate(0, 3.4, 0), 0x4f6e33),
        pintar(new THREE.IcosahedronGeometry(1.2, 0).translate(0.5, 4.3, 0.3), 0x5c7d3b),
      ]);
      const inst = new THREE.InstancedMesh(geo, matDetalles(), arboles.length);
      arboles.forEach(({ pos, escala }, i) => {
        q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), escala * 7);
        inst.setMatrixAt(i, m.compose(pos, q, new THREE.Vector3(escala, escala, escala)));
      });
      inst.castShadow = true;
      this.scene.add(inst);
    }
  }

  /** Semáforo propuesto: un poste con brazo por acceso; una cabeza por giro sobre los carriles. */
  _semaforos() {
    const matPoste = new THREE.MeshStandardMaterial({ color: 0x2d3034, roughness: 0.6, metalness: 0.4 });
    const matCaja = new THREE.MeshStandardMaterial({ color: 0x111214, roughness: 0.5 });
    // cabeza de tres luces mirando a +z local (hacia quien llega)
    const cabeza = (x, y, z, grupo) => {
      const c = new THREE.Mesh(new THREE.BoxGeometry(0.42, 1.25, 0.32), matCaja);
      c.position.set(x, y, z);
      c.castShadow = true;
      grupo.add(c);
      const focos = {};
      [['rojo', 0.4], ['amarillo', 0], ['verde', -0.4]].forEach(([nombre, dy]) => {
        const foco = new THREE.Mesh(new THREE.CircleGeometry(0.14, 16), new THREE.MeshBasicMaterial({ color: LUZ.apagada }));
        foco.position.set(x, y + dy, z + 0.17);
        grupo.add(foco);
        const visera = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.04, 0.22), matCaja);
        visera.position.set(x, y + dy + 0.16, z + 0.27);
        grupo.add(visera);
        focos[nombre] = foco;
      });
      return focos;
    };
    for (const p of this.geometria.postes_semaforo) {
      const [nx, ny] = derecha(p.rumbo);
      const [dx, dy] = adelante(p.rumbo);
      const [px, py, pz] = p.punto;
      // poste en el andén derecho, un poco antes de la línea de pare
      const base = this.a3(px + nx * (p.ancho_carril0 / 2 + 1.0) - dx * 3.5, py + ny * (p.ancho_carril0 / 2 + 1.0) - dy * 3.5, pz);
      const grupo = new THREE.Group();
      grupo.position.copy(base);
      grupo.rotation.y = -rad(p.rumbo);
      const alto = 6.2;
      const brazo = Math.max(p.ancho_calzada + 0.6, 3);
      const poste = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.17, alto, 10), matPoste);
      poste.position.y = alto / 2;
      poste.castShadow = true;
      grupo.add(poste);
      // en el grupo: -z = adelante (sentido de marcha), -x = izquierda del conductor
      const viga = new THREE.Mesh(new THREE.BoxGeometry(brazo, 0.14, 0.14), matPoste);
      viga.position.set(-brazo / 2, alto - 0.3, 0);
      viga.castShadow = true;
      grupo.add(viga);
      const giros = Object.entries(p.enlaces);
      const enlaces = [];
      giros.forEach(([dir, ids], i) => {
        const x = -(p.ancho_carril0 / 2 + 1.0) - (i + 0.5) * Math.min(brazo / giros.length, 2.6);
        // mira a quien llega: los focos en +z local (hacia atrás del sentido de marcha)
        enlaces.push({ dir, ids, focos: cabeza(x, alto - 1.05, 0.2, grupo) });
      });
      // repetidor bajo en el poste
      const repetidor = cabeza(0, 3.0, 0.2, grupo);
      enlaces.push({ dir: 'poste', ids: Object.values(p.enlaces).flat(), focos: repetidor });
      this.scene.add(grupo);
      this.cabezas.push(...enlaces);
    }
  }

  /** Lado sin semáforo: señal de PARE en cada acceso de la vía que cede. */
  _senalesPare() {
    const textura = texturaPare();
    const matSenal = new THREE.MeshStandardMaterial({ map: textura, transparent: true, side: THREE.FrontSide });
    const matPoste = new THREE.MeshStandardMaterial({ color: 0x8a8f96, metalness: 0.5, roughness: 0.4 });
    const laterales = new Set(this.geometria.accesos.filter((a) => a.lateral).map((a) => a.edge));
    for (const b of this.geometria.bocas) {
      if (!b.entra || b.indice !== 0 || !laterales.has(b.edge)) continue;
      const [nx, ny] = derecha(b.rumbo);
      const [dx, dy] = adelante(b.rumbo);
      const [px, py, pz] = b.punto;
      const base = this.a3(px + nx * (b.ancho / 2 + 0.9) - dx * 4.5, py + ny * (b.ancho / 2 + 0.9) - dy * 4.5, pz);
      const grupo = new THREE.Group();
      grupo.position.copy(base);
      grupo.rotation.y = -rad(b.rumbo);
      const poste = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 2.4, 6), matPoste);
      poste.position.y = 1.2;
      grupo.add(poste);
      const senal = new THREE.Mesh(new THREE.PlaneGeometry(0.85, 0.85), matSenal);
      senal.position.set(0, 2.45, 0.05);
      grupo.add(senal);
      this.scene.add(grupo);
    }
  }

  /** Valla "CRUCE PRIORITARIO" junto al primer acceso, como en la referencia. */
  _valla() {
    const acceso = this.geometria.bocas.find((b) => b.entra && b.indice === 0);
    if (!acceso) return;
    const { titulo, subtitulo, detalle } = this.cartel;
    const textura = texturaTexto([
      [titulo, 44, 800, '#ffb300'],
      [subtitulo, 34, 700],
      [detalle, 26, 500, '#cfd8e3'],
    ]);
    const [nx, ny] = derecha(acceso.rumbo);
    const [dx, dy] = adelante(acceso.rumbo);
    const [px, py, pz] = acceso.punto;
    const base = this.a3(px + nx * (acceso.ancho / 2 + 5) - dx * 22, py + ny * (acceso.ancho / 2 + 5) - dy * 22, pz);
    const grupo = new THREE.Group();
    grupo.position.copy(base);
    grupo.rotation.y = -rad(acceso.rumbo) + 0.35;
    const matPoste = new THREE.MeshStandardMaterial({ color: 0x404448 });
    for (const x of [-2.4, 2.4]) {
      const poste = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 4.6, 8), matPoste);
      poste.position.set(x, 2.3, 0);
      poste.castShadow = true;
      grupo.add(poste);
    }
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 3.2), new THREE.MeshStandardMaterial({ map: textura, emissive: 0xffffff, emissiveMap: textura, emissiveIntensity: 0.35 }));
    panel.position.set(0, 5.2, 0.15);
    grupo.add(panel);
    const dorso = new THREE.Mesh(new THREE.BoxGeometry(6.6, 3.4, 0.2), matPoste);
    dorso.position.set(0, 5.2, 0);
    dorso.castShadow = true;
    grupo.add(dorso);
    this.scene.add(grupo);
  }

  actualizarLuces(luces) {
    if (!luces?.estado) return;
    for (const { ids, focos } of this.cabezas) {
      const color = masPermisivo(ids.map((i) => colorLuz(luces.estado[i])));
      for (const [nombre, foco] of Object.entries(focos)) {
        foco.material.color.copy(nombre === color ? LUZ[nombre] : LUZ.apagada);
      }
    }
  }

  // ─────────────────────────────────────────────────────────── actores

  /** Recibe un frame de un lado: [id, tipo, x, y, z, ángulo, velocidad, edge]. */
  actualizarActores(vehiculos, personas, ego) {
    const ahora = performance.now();
    const dt = ahora - this.ultimoFrame;
    if (dt > 20 && dt < 3000) this.intervalo = this.intervalo * 0.7 + dt * 0.3;
    this.ultimoFrame = ahora;
    this.ego = ego;

    const vivos = new Set();
    for (const lista of [vehiculos, personas]) {
      for (const [id, tipo, x, y, z, ang, v] of lista) {
        vivos.add(id);
        const destino = this.a3(x, y, z);
        let actor = this.actores.get(id);
        if (!actor) {
          const obj = tipo === 'peaton' ? modeloPeaton(id) : modeloVehiculo(tipo, id);
          obj.position.copy(destino);
          obj.rotation.y = -rad(ang);
          this.scene.add(obj);
          actor = { obj, tipo, desde: destino.clone(), hasta: destino, angDesde: ang, angHasta: ang, v, vPrev: v, fase: Math.random() * 6 };
          this.actores.set(id, actor);
        } else {
          actor.desde.copy(actor.obj.position);
          actor.hasta = destino;
          actor.angDesde = -THREE.MathUtils.radToDeg(actor.obj.rotation.y);
          actor.angHasta = ang;
          actor.vPrev = actor.v;
          actor.v = v;
        }
      }
    }
    for (const [id, actor] of this.actores) {
      if (!vivos.has(id)) {
        this.scene.remove(actor.obj);   // las geometrías y materiales son compartidos: no se liberan
        this.actores.delete(id);
      }
    }
  }

  posicionActor(id) {
    return this.actores.get(id)?.obj.position ?? null;
  }

  // ─────────────────────────────────────────────────────────── cámara y render

  setModoCamara(modo) {
    this.modoCamara = modo;
  }

  mirarA(x, y, z) {
    this.objetivoAereo.copy(this.a3(x, y, z));
  }

  _interpolar() {
    const ahora = performance.now();
    const alfa = Math.min((ahora - this.ultimoFrame) / this.intervalo, 1);
    for (const actor of this.actores.values()) {
      actor.obj.position.lerpVectors(actor.desde, actor.hasta, alfa);
      let d = actor.angHasta - actor.angDesde;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      actor.obj.rotation.y = -rad(actor.angDesde + d * alfa);
      if (actor.tipo === 'peaton') {
        const cuerpo = actor.obj.children[0];
        cuerpo.position.y = Math.abs(Math.sin(ahora / 160 + actor.fase)) * 0.05 * Math.min(actor.v, 1.5);
      } else {
        const stop = actor.obj.children[2];
        const frena = actor.v < actor.vPrev - 0.15 || actor.v < 0.2;
        stop.material = matStop(frena);
      }
    }
  }

  _actualizarCamara(dt) {
    const actor = this.ego ? this.actores.get(this.ego) : null;
    this.marcador.visible = !!actor;
    const conHaz = actor && actor.tipo !== 'peaton';
    if (conHaz && this.haz.parent !== actor.obj) actor.obj.add(this.haz);
    if (!conHaz && this.haz.parent) this.haz.parent.remove(this.haz);
    this.luzEgo.visible = !!conHaz;
    if (actor) {
      this.marcador.position.copy(actor.obj.position);
      if (conHaz) {
        const rot = actor.obj.rotation.y;
        this.luzEgo.position.copy(actor.obj.position).add(new THREE.Vector3(0, 1.0, 0));
        this.luzEgo.target.position.copy(actor.obj.position).add(new THREE.Vector3(-Math.sin(rot) * 20, 0, -Math.cos(rot) * 20));
      }
    }
    // las sombras siguen a la cámara
    const foco = actor ? actor.obj.position : this.objetivoAereo;
    this.sol.position.set(foco.x - 90, foco.y + 60, foco.z + 35);
    this.sol.target.position.copy(foco);

    const suave = 1 - Math.exp(-dt * 4);
    if (this.modoCamara === 'persecucion' && actor) {
      const [l, , h] = DIMENSIONES[actor.tipo] ?? DIMENSIONES.auto;
      const peaton = actor.tipo === 'peaton';
      const atras = peaton ? 3.4 : l + (l > 8 ? 9 : 5.2);
      const alto = peaton ? 2.1 : h + (l > 8 ? 2.6 : 1.4);
      const rot = actor.obj.rotation.y;
      // detrás del actor: su "atrás" es +Z local (el modelo mira a -Z)
      const objetivo = actor.obj.position.clone().add(new THREE.Vector3(Math.sin(rot) * atras, alto, Math.cos(rot) * atras));
      // si un edificio queda entre el actor y la cámara (al girar en una esquina), se acerca
      const desde = actor.obj.position.clone().add(new THREE.Vector3(0, h * 0.8, 0));
      const hacia = objetivo.clone().sub(desde);
      const distancia = hacia.length();
      this.rayo.set(desde, hacia.normalize());
      this.rayo.far = distancia;
      const choque = this.rayo.intersectObjects(this.obstaculos, false)[0];
      if (choque) objetivo.copy(desde).addScaledVector(hacia, Math.max(choque.distance - 0.6, 1.2)).add(new THREE.Vector3(0, 0.8, 0));
      this.camera.position.lerp(objetivo, 1 - Math.exp(-dt * 6));
      const mira = actor.obj.position.clone().add(new THREE.Vector3(-Math.sin(rot) * 14, peaton ? 1.2 : h * 0.55, -Math.cos(rot) * 14));
      this.camera.lookAt(mira);
      return;
    }
    // aérea: sobre el actor seguido o sobre el punto elegido (cruce o vía), girando despacio
    this.anguloAereo += dt * 0.05;
    const objetivo = foco.clone().add(new THREE.Vector3(Math.cos(this.anguloAereo) * 62, 52, Math.sin(this.anguloAereo) * 62));
    this.camera.position.lerp(objetivo, suave);
    this.camera.lookAt(foco);
  }

  render(dt) {
    this._interpolar();
    this._actualizarCamara(dt);
    this.renderer.render(this.scene, this.camera);
  }

  redimensionar() {
    const { clientWidth: w, clientHeight: h } = this.contenedor;
    if (!w || !h) return;
    this.renderer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  destruir() {
    const compartidas = new Set(Object.values(GEOMETRIAS).flatMap((g) => (g.isBufferGeometry ? [g] : Object.values(g))));
    const materiales = new Set(Object.values(MATERIALES));
    this.scene.traverse((o) => {
      if (o.geometry && !compartidas.has(o.geometry)) o.geometry.dispose();
      if (o.material) {
        (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => {
          if (!materiales.has(m)) {
            m.map?.dispose();
            m.dispose();
          }
        });
      }
    });
    this.scene.background?.dispose?.();
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}
