// Elementos reutilizables para los diagramas del SDD (fletcher).
#import "@preview/fletcher:0.5.8": diagram, node, edge, shapes

// ------------------------------------------------------------ clases UML
// Compartimentos: nombre (con estereotipo opcional), atributos y métodos.
#let clase(pos, nombre, attrs: (), metodos: (), est: none, name: none, ancho: auto) = node(
  pos,
  name: name,
  inset: 0pt,
  stroke: none,
  table(
    columns: if ancho == auto { auto } else { ancho },
    stroke: 0.5pt,
    inset: 3.5pt,
    align: left,
    fill: white,
    align(center)[#if est != none [#text(size: 6.5pt)[«#est»]\ ]*#nombre*],
    ..if attrs.len() > 0 { (text(size: 6.8pt, attrs.join(linebreak())),) } else { ([],) },
    ..if metodos.len() > 0 { (text(size: 6.8pt, metodos.join(linebreak())),) },
  ),
)

// ------------------------------------------------------------ actividad
#let inicio(pos, name: none) = node(pos, name: name, shape: circle, fill: black, width: 3.5mm, height: 3.5mm, inset: 0pt)
#let fin(pos, name: none) = node(
  pos, name: name, shape: circle, width: 5mm, height: 5mm, inset: 0pt, stroke: 0.8pt,
  circle(radius: 1.5mm, fill: black),
)
#let accion(pos, txt, name: none) = node(
  pos, txt, name: name, shape: rect, corner-radius: 5pt, inset: 4pt, stroke: 0.6pt, fill: luma(248),
)
#let decision(pos, txt, name: none) = node(
  pos, txt, name: name, shape: shapes.diamond, inset: 2pt, stroke: 0.6pt, fill: white,
)

// ------------------------------------------------------------ despliegue / componentes
#let componente(pos, txt, name: none, fill: white) = node(
  pos, txt, name: name, shape: rect, inset: 5pt, stroke: 0.6pt, fill: fill,
)

// Escala un diagrama para que quepa en el ancho de la página (no lo agranda).
#let ajustar(body) = layout(size => {
  let m = measure(body)
  let f = calc.min(1, size.width / m.width)
  scale(f * 100%, reflow: true, body)
})

// Rótulo de un grupo: va dentro del recuadro de agrupación.
#let rotulo(pos, txt, name: none) = node(pos, text(weight: "bold", size: 7.5pt, txt), stroke: none, name: name, inset: 2pt)
