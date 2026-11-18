# Presentación de la tesis

Presentación en HTML (reveal.js) basada en `docs/memoria/`: 21 diapositivas, fondo blanco, sin flechas de navegación en pantalla (se avanza con el teclado). La diapositiva 9 (`#/arquitectura`) es el visor C4 con zoom entre niveles. La última diapositiva muestra el enlace al video demo de YouTube: se pega en `index.html` (`id="enlace-video"`, href y texto).

## Guion de la sustentación (30 min: 23 de exposición + 7 de video, 4 personas)

Cada diapositiva lleva en la esquina superior derecha la parte y el criterio de evaluación que cubre.

| Parte | Diapositivas | Criterio (peso) | Tiempo |
|---|---|---|---|
| Apertura | 1–2 | Agenda y criterios | (dentro de la parte 1) |
| 1 | 3–7 | Análisis de entorno y herramientas (5 %) | 5:45 |
| 2 | 8–10 | Diseño (5 %), incluye el C4 interactivo | 5:45 |
| 3 | 11–14 | Solución (8 %), anuncia el video demo | 5:45 |
| 4 | 15–20 | Control de calidad (7 %) y cierre | 5:45 |
| Video | 21 | Enlace al video demo de YouTube | 7:00 |

## Cómo abrirla

```bash
cd docs/presentacion
python -m http.server 8080      # luego abrir http://localhost:8080
```

También funciona abriendo `index.html` directamente con `file://`. Reveal.js está en `vendor/reveal/` (sin dependencias de red).

## Teclas

- Flechas del teclado, espacio o AvPág: cambiar de diapositiva. `F`: pantalla completa. `Esc`: vista general.
- En la diapositiva C4: clic en un elemento resaltado para entrar al siguiente nivel. Rueda del mouse: zoom hacia el cursor; arrastrar: mover; doble clic o «Ver todo»: encuadrar el diagrama completo; botones − y +; `Retroceso` (o `u`) o «Subir nivel» para volver.

## Archivos

- `index.html`: diapositivas.
- `estilos.css`: tema y estilos del visor C4.
- `c4.js`: visor C4.
- `assets/`: copias de los SVG de `docs/diagrams/c4-model/` y de las figuras de `docs/memoria/figures/`. La carpeta es autocontenida (se puede mover o llevar en USB). Si cambian los originales, hay que volver a copiarlos.

## Si cambia el diagrama de draw.io

Cada nivel tiene además un `.webp` en `assets/c4/` (mapa de bits que se usa mientras la cámara se mueve; el SVG se muestra al quedar quieta). Hay que regenerarlo al cambiar el SVG: abrir el SVG en Chromium a 1,5x–2x de su `viewBox` y guardarlo como WebP.

Reexportar los SVG a `docs/diagrams/c4-model/`, copiarlos a `assets/c4/` y ajustar en `c4.js` los rectángulos `zonas` y `destino` (coordenadas del viewBox de cada SVG). La conversión desde `tesis.drawio` está en el comentario al inicio de `c4.js`.
