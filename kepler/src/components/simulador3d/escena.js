// Escena three.js de un lado de la comparación (sin semáforo / con semáforo propuesto).
//
// Coordenadas: la API manda todo en coordenadas de la red de SUMO (x este, y norte,
// z altura en metros). En three.js el eje vertical es Y, así que
//   three.x = x - origen.x,  three.y = z - origen.z,  three.z = -(y - origen.y)
// con el cruce como origen. Los vehículos de SUMO se ubican por el parachoques
// delantero y su ángulo es en grados desde el norte, en sentido horario.
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

const COLOR_CIELO = 0xbfd6ea;
const COLOR_SUELO = 0x7d8f69;
const COLOR_ASFALTO = 0x3b3e44;
const COLOR_CRUCE = 0x34373c;
const COLOR_ANDEN = 0xa7a39a;
const COLOR_CICLO = 0x8e3b3b;
const COLOR_EGO = 0x00e5ff;

const COLORES_AUTO = [0xd9d9d9, 0x2b2b2b, 0x8a1c1c, 0x1f3f7a, 0x6b6b6b, 0xf2f2f2, 0x274d2b, 0x5a4632];
const COLORES_EDIFICIO = [0xd8d2c4, 0xc9b8a0, 0xb6b0a8, 0xe3ddd3, 0xa89a8a];
const COLORES_ROPA = [0x2f4f7f, 0x8b2f2f, 0x3d6b3d, 0x222222, 0x7a5c2e, 0x5c3d7a, 0xc77d1a];

// Dimensiones (largo, ancho, alto) por vType de SUMO
const DIMENSIONES = {
  auto: [4.5, 1.8, 1.45], taxi: [4.4, 1.75, 1.5], especial: [4.8, 1.9, 1.7], informal: [4.5, 1.8, 1.5],
  otro: [4.5, 1.8, 1.5], moto: [2.1, 0.8, 1.2], bici: [1.8, 0.6, 1.1], bus_pt: [12, 2.55, 3.1],
  escolar: [9, 2.4, 2.9], peaton: [0.5, 0.5, 1.72],
};

const LUZ = {
  verde: new THREE.Color(0x19e05c), amarillo: new THREE.Color(0xffc400), rojo: new THREE.Color(0xff2a1a),
  apagada: new THREE.Color(0x202020),
};

const hash = (texto) => {
  let h = 0;
  for (let i = 0; i < texto.length; i += 1) h = (h * 31 + texto.charCodeAt(i)) | 0;
  return Math.abs(h);
};

const colorLuz = (letra) => {
  if (letra === 'G' || letra === 'g') return 'verde';
  if (letra === 'y' || letra === 'Y' || letra === 'u') return 'amarillo';
  if (letra === 'r' || letra === 'R') return 'rojo';
  return 'apagada';
};

// ───────────────────────────────────────────────────────────── modelos low-poly

const caja = (l, a, h, color, y = 0, z = 0) => {
  const malla = new THREE.Mesh(new THREE.BoxGeometry(a, h, l), new THREE.MeshLambertMaterial({ color }));
  malla.position.set(0, y + h / 2, z);
  return malla;
};

// Todos los modelos miran hacia -Z y tienen el origen en el frente (como SUMO)
function modeloVehiculo(tipo, id) {
  const [l, a, h] = DIMENSIONES[tipo] ?? DIMENSIONES.auto;
  const g = new THREE.Group();
  if (tipo === 'bus_pt' || tipo === 'escolar') {
    const color = tipo === 'escolar' ? 0xf5c400 : 0x1f6fbf;
    g.add(caja(l, a, h - 0.35, color, 0.35, l / 2));
    const ventanas = caja(l - 1.2, a + 0.02, 0.9, 0x1b2a38, 1.5, l / 2 + 0.3);
    g.add(ventanas);
    g.add(caja(0.1, a - 0.2, 1.1, 0x1b2a38, 1.3, 0.05));
  } else if (tipo === 'moto' || tipo === 'bici') {
    const color = tipo === 'moto' ? 0x202020 : 0x2e7d32;
    g.add(caja(l, 0.25, tipo === 'moto' ? 0.55 : 0.12, color, 0.35, l / 2));
    const rueda = new THREE.CylinderGeometry(0.33, 0.33, 0.12, 12);
    rueda.rotateZ(Math.PI / 2);
    for (const z of [0.3, l - 0.3]) {
      const r = new THREE.Mesh(rueda, new THREE.MeshLambertMaterial({ color: 0x111111 }));
      r.position.set(0, 0.33, z);
      g.add(r);
    }
    const ropa = COLORES_ROPA[hash(id) % COLORES_ROPA.length];
    g.add(caja(0.35, 0.42, 0.62, ropa, 0.85, l / 2 + 0.1));
    const casco = new THREE.Mesh(new THREE.SphereGeometry(0.16, 10, 8), new THREE.MeshLambertMaterial({ color: tipo === 'moto' ? 0xeeeeee : 0xffb300 }));
    casco.position.set(0, 1.62, l / 2 + 0.05);
    g.add(casco);
  } else {
    const color = tipo === 'taxi' ? 0xffd21f : COLORES_AUTO[hash(id) % COLORES_AUTO.length];
    g.add(caja(l, a, h * 0.55, color, 0.25, l / 2));
    g.add(caja(l * 0.52, a * 0.9, h * 0.42, 0x1d2733, 0.25 + h * 0.55, l / 2 + l * 0.05));
    const rueda = new THREE.CylinderGeometry(0.32, 0.32, 0.22, 12);
    rueda.rotateZ(Math.PI / 2);
    const material = new THREE.MeshLambertMaterial({ color: 0x111111 });
    for (const [x, z] of [[a / 2, 0.8], [-a / 2, 0.8], [a / 2, l - 0.8], [-a / 2, l - 0.8]]) {
      const r = new THREE.Mesh(rueda, material);
      r.position.set(x, 0.32, z);
      g.add(r);
    }
    // luces: delanteras blancas, traseras rojas (se encienden al frenar)
    const traseras = caja(0.05, a * 0.8, 0.12, 0x550000, 0.75, l);
    traseras.name = 'stop';
    g.add(traseras);
    g.add(caja(0.05, a * 0.8, 0.1, 0xfff6d0, 0.7, 0));
  }
  return g;
}

function modeloPeaton(id) {
  const g = new THREE.Group();
  const ropa = COLORES_ROPA[hash(id) % COLORES_ROPA.length];
  const piernas = caja(0.25, 0.32, 0.85, 0x2a2a35, 0, 0.12);
  piernas.name = 'piernas';
  g.add(piernas);
  g.add(caja(0.28, 0.44, 0.62, ropa, 0.85, 0.12));
  const cabeza = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 8), new THREE.MeshLambertMaterial({ color: 0xc69c74 }));
  cabeza.position.set(0, 1.6, 0.12);
  g.add(cabeza);
  return g;
}

function marcadorEgo() {
  const g = new THREE.Group();
  const anillo = new THREE.Mesh(
    new THREE.RingGeometry(1.4, 1.8, 32),
    new THREE.MeshBasicMaterial({ color: COLOR_EGO, side: THREE.DoubleSide, transparent: true, opacity: 0.85 })
  );
  anillo.rotation.x = -Math.PI / 2;
  anillo.position.y = 0.08;
  g.add(anillo);
  const flecha = new THREE.Mesh(new THREE.ConeGeometry(0.45, 0.9, 4), new THREE.MeshBasicMaterial({ color: COLOR_EGO }));
  flecha.rotation.x = Math.PI;
  flecha.name = 'flecha';
  g.add(flecha);
  return g;
}

// ───────────────────────────────────────────────────────────── geometría estática

/** Cinta (BufferGeometry) de ancho `ancho` a lo largo de `puntos` (ya en coordenadas three). */
function cinta(puntos, ancho, alzado) {
  if (puntos.length < 2) return null;
  const pos = [];
  const idx = [];
  for (let i = 0; i < puntos.length; i += 1) {
    const prev = puntos[Math.max(i - 1, 0)];
    const next = puntos[Math.min(i + 1, puntos.length - 1)];
    const dx = next.x - prev.x;
    const dz = next.z - prev.z;
    const largo = Math.hypot(dx, dz) || 1;
    const nx = -dz / largo;
    const nz = dx / largo;
    const p = puntos[i];
    pos.push(p.x + (nx * ancho) / 2, p.y + alzado, p.z + (nz * ancho) / 2);
    pos.push(p.x - (nx * ancho) / 2, p.y + alzado, p.z - (nz * ancho) / 2);
    if (i > 0) {
      const b = (i - 1) * 2;
      idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/** Puntos desplazados lateralmente `d` metros (positivo = a la izquierda del sentido). */
function desplazar(puntos, d) {
  return puntos.map((p, i) => {
    const prev = puntos[Math.max(i - 1, 0)];
    const next = puntos[Math.min(i + 1, puntos.length - 1)];
    const dx = next.x - prev.x;
    const dz = next.z - prev.z;
    const largo = Math.hypot(dx, dz) || 1;
    return new THREE.Vector3(p.x + (-dz / largo) * d, p.y, p.z + (dx / largo) * d);
  });
}

export default class Escena3D {
  constructor(contenedor, geometria, { conSemaforo }) {
    this.contenedor = contenedor;
    this.geometria = geometria;
    this.conSemaforo = conSemaforo;
    const nodo = geometria.nodo;
    this.origen = { x: nodo.x, y: nodo.y, z: nodo.z };

    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    contenedor.appendChild(this.renderer.domElement);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(COLOR_CIELO);
    this.scene.fog = new THREE.Fog(COLOR_CIELO, 180, 650);
    this.camera = new THREE.PerspectiveCamera(60, 1, 0.3, 2000);
    this.camera.position.set(-60, 70, 60);
    this.controles = new OrbitControls(this.camera, this.renderer.domElement);
    this.controles.enableDamping = true;
    this.controles.maxPolarAngle = Math.PI * 0.48;
    this.controles.enabled = false;

    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x556b2f, 1.6));
    const sol = new THREE.DirectionalLight(0xffffff, 1.4);
    sol.position.set(120, 200, 60);
    this.scene.add(sol);

    this.actores = new Map();       // id -> { obj, tipo, desde, hasta, angDesde, angHasta, v }
    this.ego = null;
    this.marcador = marcadorEgo();
    this.marcador.visible = false;
    this.scene.add(this.marcador);
    this.modoCamara = 'persecucion';
    this.objetivoAereo = new THREE.Vector3(0, 0, 0);
    this.ultimoFrame = performance.now();
    this.intervalo = 200;
    this.cabezasSemaforo = [];

    this._construirMundo();
    this.redimensionar();
  }

  a3(x, y, z) {
    return new THREE.Vector3(x - this.origen.x, (z ?? this.origen.z) - this.origen.z, -(y - this.origen.y));
  }

  _construirMundo() {
    const g = this.geometria;
    const [x0, y0, x1, y1] = g.limites;
    const centro = this.a3((x0 + x1) / 2, (y0 + y1) / 2, this.origen.z);
    const suelo = new THREE.Mesh(
      new THREE.PlaneGeometry(x1 - x0 + 600, y1 - y0 + 600),
      new THREE.MeshLambertMaterial({ color: COLOR_SUELO })
    );
    suelo.rotation.x = -Math.PI / 2;
    // el suelo va bajo el punto más bajo de la red para que no tape vías en pendiente
    const zMin = Math.min(...g.cruces.map((c) => c.z), this.origen.z);
    suelo.position.set(centro.x, zMin - this.origen.z - 0.4, centro.z);
    this.scene.add(suelo);

    // carriles: se agrupan por material y se fusionan (miles de cintas → pocas mallas)
    const grupos = { asfalto: [], anden: [], ciclo: [], marcas: [], bordes: [] };
    for (const carril of g.carriles) {
      if (carril.forma.length < 2) continue;
      const puntos = carril.forma.map(([x, y, z]) => this.a3(x, y, z));
      const tipo = carril.peatonal ? 'anden' : carril.ciclorruta ? 'ciclo' : 'asfalto';
      const geo = cinta(puntos, carril.ancho, carril.interno ? 0.03 : 0.05);
      if (geo) grupos[tipo].push(geo);
      if (!carril.interno && tipo === 'asfalto') {
        const indice = Number(carril.id.split('_').pop());
        const borde = desplazar(puntos, -carril.ancho / 2 + 0.12);
        const marca = cinta(borde, 0.14, 0.07);
        if (marca) (indice === 0 ? grupos.bordes : grupos.marcas).push(marca);
      }
    }
    const materiales = {
      asfalto: new THREE.MeshLambertMaterial({ color: COLOR_ASFALTO }),
      anden: new THREE.MeshLambertMaterial({ color: COLOR_ANDEN }),
      ciclo: new THREE.MeshLambertMaterial({ color: COLOR_CICLO }),
      marcas: new THREE.MeshBasicMaterial({ color: 0xe8e8e8 }),
      bordes: new THREE.MeshBasicMaterial({ color: 0xf2f2f2 }),
    };
    for (const [tipo, geos] of Object.entries(grupos)) {
      if (!geos.length) continue;
      const malla = new THREE.Mesh(mergeGeometries(geos), materiales[tipo]);
      this.scene.add(malla);
    }

    // cruces (polígonos)
    const geosCruce = [];
    for (const cruce of g.cruces) {
      if (cruce.forma.length < 3) continue;
      const forma = new THREE.Shape(cruce.forma.map(([x, y]) => new THREE.Vector2(x - this.origen.x, y - this.origen.y)));
      const geo = new THREE.ShapeGeometry(forma);
      geo.rotateX(-Math.PI / 2);
      geo.translate(0, cruce.z - this.origen.z + 0.04, 0);
      geosCruce.push(geo);
    }
    if (geosCruce.length) {
      this.scene.add(new THREE.Mesh(mergeGeometries(geosCruce), new THREE.MeshLambertMaterial({ color: COLOR_CRUCE, side: THREE.DoubleSide })));
    }

    // cruce estudiado: un halo en el piso para ubicarlo desde lejos
    const halo = new THREE.Mesh(
      new THREE.RingGeometry(9, 10.5, 48),
      new THREE.MeshBasicMaterial({ color: this.conSemaforo ? 0x00e676 : 0xffb300, transparent: true, opacity: 0.55, side: THREE.DoubleSide })
    );
    halo.rotation.x = -Math.PI / 2;
    halo.position.y = 0.09;
    this.scene.add(halo);

    // edificios extruidos, fusionados por color
    const porColor = COLORES_EDIFICIO.map(() => []);
    for (const ed of g.edificios) {
      const contorno = ed.contorno.map(([x, y]) => new THREE.Vector2(x - this.origen.x, y - this.origen.y));
      if (contorno.length < 4) continue;
      const geo = new THREE.ExtrudeGeometry(new THREE.Shape(contorno), { depth: ed.altura, bevelEnabled: false });
      geo.rotateX(-Math.PI / 2);
      geo.translate(0, ed.z - this.origen.z - 0.3, 0);
      porColor[hash(`${ed.contorno[0]}`) % porColor.length].push(geo);
    }
    porColor.forEach((geos, i) => {
      if (geos.length) {
        this.scene.add(new THREE.Mesh(mergeGeometries(geos), new THREE.MeshLambertMaterial({ color: COLORES_EDIFICIO[i] })));
      }
    });

    if (this.conSemaforo) this._construirSemaforos();
  }

  _construirSemaforos() {
    // una cabeza por posición (las conexiones de un mismo carril comparten poste)
    const porPosicion = new Map();
    for (const luz of this.geometria.luces) {
      const clave = luz.posicion.map((v) => v.toFixed(1)).join(',');
      if (!porPosicion.has(clave)) porPosicion.set(clave, { posicion: luz.posicion, enlaces: [] });
      porPosicion.get(clave).enlaces.push(luz.enlace);
    }
    const poste = new THREE.CylinderGeometry(0.09, 0.11, 4.2, 8);
    const matPoste = new THREE.MeshLambertMaterial({ color: 0x2b2b2b });
    for (const { posicion, enlaces } of porPosicion.values()) {
      const [x, y, z] = posicion;
      const base = this.a3(x, y, z);
      const g = new THREE.Group();
      const p = new THREE.Mesh(poste, matPoste);
      p.position.y = 2.1;
      g.add(p);
      const cuerpo = caja(0.35, 0.42, 1.25, 0x111111, 3.6, 0);
      g.add(cuerpo);
      const focos = {};
      [['rojo', 4.5], ['amarillo', 4.2], ['verde', 3.9]].forEach(([nombre, alto]) => {
        const foco = new THREE.Mesh(new THREE.SphereGeometry(0.13, 12, 8), new THREE.MeshBasicMaterial({ color: LUZ.apagada }));
        foco.position.set(0, alto, -0.2);
        g.add(foco);
        focos[nombre] = foco;
      });
      // la línea de pare queda en el centro del carril: el poste va a la derecha del
      // sentido de llegada (que apunta, más o menos, hacia el centro del cruce)
      const llegada = new THREE.Vector3(-base.x, 0, -base.z).normalize();
      const derecha = new THREE.Vector3(-llegada.z, 0, llegada.x);
      g.position.copy(base).addScaledVector(derecha, 2.6).addScaledVector(llegada, -0.8);
      // lookAt orienta +Z hacia el cruce: los focos (en -Z) quedan de cara a quien llega
      g.lookAt(new THREE.Vector3(0, g.position.y, 0));
      this.scene.add(g);
      this.cabezasSemaforo.push({ enlaces, focos });
    }
  }

  actualizarLuces(luces) {
    if (!luces?.estado) return;
    for (const { enlaces, focos } of this.cabezasSemaforo) {
      // la cabeza muestra el estado más permisivo de sus conexiones
      const colores = enlaces.map((i) => colorLuz(luces.estado[i]));
      const color = colores.includes('verde') ? 'verde' : colores.includes('amarillo') ? 'amarillo' : 'rojo';
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
          obj.rotation.y = -THREE.MathUtils.degToRad(ang);
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
        this.scene.remove(actor.obj);
        actor.obj.traverse((o) => o.geometry?.dispose());
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
    this.controles.enabled = modo === 'libre';
    if (modo === 'libre') this.controles.target.copy(this.posicionActor(this.ego) ?? new THREE.Vector3());
  }

  mirarA(x, y, z) {
    this.objetivoAereo.copy(this.a3(x, y, z));
  }

  _interpolar() {
    const alfa = Math.min((performance.now() - this.ultimoFrame) / this.intervalo, 1);
    for (const actor of this.actores.values()) {
      actor.obj.position.lerpVectors(actor.desde, actor.hasta, alfa);
      let d = actor.angHasta - actor.angDesde;
      if (d > 180) d -= 360;
      if (d < -180) d += 360;
      actor.obj.rotation.y = -THREE.MathUtils.degToRad(actor.angDesde + d * alfa);
      if (actor.tipo === 'peaton') {
        const piernas = actor.obj.getObjectByName('piernas');
        if (piernas) piernas.scale.y = 1 + Math.sin(performance.now() / 120 + actor.fase) * 0.06 * Math.min(actor.v, 1.5);
      } else {
        const stop = actor.obj.getObjectByName('stop');
        if (stop) stop.material.color.setHex(actor.v < actor.vPrev - 0.15 || actor.v < 0.2 ? 0xff1a1a : 0x550000);
      }
    }
  }

  _actualizarCamara(dt) {
    const actor = this.ego ? this.actores.get(this.ego) : null;
    this.marcador.visible = !!actor;
    if (actor) {
      this.marcador.position.copy(actor.obj.position);
      const flecha = this.marcador.getObjectByName('flecha');
      const [, , h] = DIMENSIONES[actor.tipo] ?? DIMENSIONES.auto;
      flecha.position.y = h + 1.2 + Math.sin(performance.now() / 300) * 0.2;
    }
    if (this.modoCamara === 'libre') {
      this.controles.update();
      return;
    }
    const suave = 1 - Math.exp(-dt * 3.5);
    if (this.modoCamara === 'persecucion' && actor) {
      const [l, , h] = DIMENSIONES[actor.tipo] ?? DIMENSIONES.auto;
      const atras = actor.tipo === 'peaton' ? 3.2 : l + 6;
      const alto = actor.tipo === 'peaton' ? 1.9 : h + 2.4;
      const rot = actor.obj.rotation.y;
      // detrás del vehículo: su "atrás" es +Z local (el modelo mira a -Z)
      const objetivo = actor.obj.position.clone().add(new THREE.Vector3(Math.sin(rot) * atras, alto, Math.cos(rot) * atras));
      this.camera.position.lerp(objetivo, suave);
      const adelante = actor.obj.position.clone().add(new THREE.Vector3(-Math.sin(rot) * 12, h * 0.6, -Math.cos(rot) * 12));
      this.camera.lookAt(adelante);
      return;
    }
    // aérea: sobre el actor seguido o sobre el punto elegido (cruce o vía)
    const foco = actor ? actor.obj.position : this.objetivoAereo;
    const objetivo = foco.clone().add(new THREE.Vector3(-35, 60, 45));
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
    this.controles.dispose();
    this.scene.traverse((o) => {
      o.geometry?.dispose();
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => m.dispose());
    });
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}
