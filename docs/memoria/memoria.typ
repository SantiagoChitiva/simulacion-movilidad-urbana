// Memoria final del trabajo de grado, con el formato "Formato TG ISIST" de la carrera.
// Compilar desde docs/: python -c "import typst; typst.compile('memoria/memoria.typ', output='memoria/memoria.pdf', root='memoria')"

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#let info = (
  titulo: "Generación de escenarios de movilidad urbana para la toma de decisiones en localidades de Bogotá: caso Usaquén",
  autores: ("Samuel Esteban Campos", "Erick Salazar Suárez", "Santiago Chitiva Contreras", "Felipe Andrés Garrido Flores"),
  director: "Andrés Oswaldo Calderón Romero",
  anio: "2026",
  mes: "Noviembre",
)

#set document(title: info.titulo, author: info.autores)
#set page(paper: "us-letter", margin: (top: 3.17cm, right: 3.17cm, bottom: 3.81cm, left: 3.81cm))
#set text(lang: "es", font: ("Calibri", "Carlito", "Liberation Sans"), size: 11pt)
#show raw: set text(font: ("Calibri", "Carlito", "Liberation Sans"), size: 1.25em)
#set par(justify: true, leading: 0.72em, spacing: 1.1em)
#show heading: set text(font: ("Times New Roman", "Liberation Serif"))
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  set align(center)
  set text(size: 16pt, weight: "bold")
  v(0.6cm)
  if it.numbering != none { counter(heading).display(it.numbering) + h(0.4em) }
  upper(it.body)
  v(0.5cm)
}
#show heading.where(level: 2): set text(size: 13pt)
#show heading.where(level: 3): set text(size: 12pt)
#show figure.where(kind: table): set figure(supplement: [Tabla])
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: image): set figure(supplement: [Figura])
#set table(align: left, inset: 5pt)
#show table: set text(size: 9.5pt)
#set list(indent: 0.4cm)
#set enum(indent: 0.4cm)

// Capítulos en números romanos ("I-"), secciones con números arábigos que reinician en cada capítulo ("1.", "1.1.")
#let numeracion(..n) = {
  let nums = n.pos()
  if nums.len() == 1 { numbering("I-", nums.at(0)) } else { numbering("1.1.", ..nums.slice(1)) }
}

#let captura(archivo, leyenda, ancho: 100%) = figure(image("figures/" + archivo, width: ancho), caption: leyenda)

// ───────────────────────────────────────────── portada

#page(margin: (top: 2.5cm, bottom: 2.5cm, left: 3cm, right: 3cm), numbering: none)[
  #set align(center)
  #set par(justify: false)
  // falta poner el código del trabajo de grado
  #v(1.5cm)
  #text(size: 16pt, weight: "bold", font: ("Times New Roman", "Liberation Serif"))[#upper(info.titulo)]
  #v(2cm)
  #info.autores.join("\n")
  #v(2cm)
  Director \ Ing. #info.director
  #v(1fr)
  #image("figures/logo_javeriana.png", width: 12%)
  #v(0.6cm)
  PONTIFICIA UNIVERSIDAD JAVERIANA \
  FACULTAD DE INGENIERÍA \
  PROGRAMA DE INGENIERÍA DE SISTEMAS \
  BOGOTÁ, D.C. \
  #info.anio
]

// ───────────────────────────────────────────── contraportada

#page(numbering: none)[
  #set align(center)
  #set par(justify: false)
  // falta poner el código del trabajo de grado
  #v(0.8cm)
  #text(weight: "bold")[#upper(info.titulo)]
  #v(1cm)
  Autor(es): \
  #info.autores.join("\n")
  #v(1cm)
  MEMORIA FINAL DEL PROYECTO DE GRADO REALIZADO PARA CUMPLIR UNO DE LOS REQUISITOS DEL GRADO EN INGENIERÍA DE SISTEMAS
  #v(1cm)
  Director \ Ing. #info.director
  #v(0.8cm)
  Jurados del Proyecto Final de Grado \
  // falta poner los nombres de los dos jurados
  #v(1fr)
  PONTIFICIA UNIVERSIDAD JAVERIANA \
  FACULTAD DE INGENIERÍA \
  PROGRAMA DE INGENIERÍA DE SISTEMAS \
  BOGOTÁ, D.C. \
  #info.mes.#info.anio
]

// ───────────────────────────────────────────── autoridades

#page(numbering: none)[
  #set align(center)
  #set par(justify: false)
  PONTIFICIA UNIVERSIDAD JAVERIANA \
  FACULTAD DE INGENIERÍA \
  PROGRAMA DE INGENIERÍA DE SISTEMAS
  #v(1.2cm)
  *Rector de la Pontificia Universidad Javeriana* \ // falta poner el nombre del rector
  #v(0.6cm)
  *Decano de la Facultad de Ingeniería* \ // falta poner el nombre del decano
  #v(0.6cm)
  *Jefe del Departamento de Ingeniería de Sistemas* \ // falta poner el nombre del jefe del departamento
  #v(0.6cm)
  *Director de la carrera de Ingeniería de Sistemas* \ // falta poner el nombre del director de carrera
  #v(1fr)
  #set align(left)
  #set par(justify: true)
  *Artículo 23 de la Resolución No. 1 de Junio de 1946*

  _"La Universidad no se hace responsable de los conceptos emitidos por sus alumnos en sus proyectos de grado. Sólo velará porque no se publique
  nada contrario al dogma y la moral católica y porque no contengan ataques o polémicas puramente personales. Antes bien, que se vean en ellos el
  anhelo de buscar la verdad y la Justicia"_
]

// ───────────────────────────────────────────── agradecimientos, contenido, abstract y resumen

#set page(numbering: "i", footer: context align(center, text(size: 9pt, counter(page).display("i"))))
#counter(page).update(1)

#align(center)[#text(size: 14pt, weight: "bold", font: ("Times New Roman", "Liberation Serif"))[AGRADECIMIENTOS]]
#v(0.5cm)

Al ingeniero Andrés Oswaldo Calderón Romero, director de este trabajo, por proponernos la idea que dio origen al proyecto y por guiarnos
en cada etapa con sus observaciones y su acompañamiento constante.

A los profesores de la carrera, por las correcciones al plan, a los requisitos y a los demás documentos, que se notan en cada versión.

A nuestras familias, por su apoyo incondicional durante la carrera y a lo largo de este trabajo.

A Victor Pay, autor de Semáforos de Barranquilla, cuyo trabajo publicado de forma abierta sirvió de base para el módulo de priorización de cruces,
y a las comunidades de SUMO, OpenStreetMap y kepler.gl, por las herramientas libres sobre las que se construyó este proyecto.

#pagebreak()

#align(center)[#text(size: 14pt, weight: "bold", font: ("Times New Roman", "Liberation Serif"))[CONTENIDO]]
#outline(title: none, depth: 3, indent: auto)

#pagebreak()

#align(center)[#text(size: 14pt, weight: "bold", font: ("Times New Roman", "Liberation Serif"))[ABSTRACT]]
#v(0.3cm)

Bogotá is among the most congested cities in the world, yet testing a traffic measure before building it is still slow: the 2023
mobility survey has to be turned by hand into simulator input files. We built an open-source system that converts the survey trips of Usaquén
into a SUMO microscopic simulation, runs demand scenarios and road closures, ranks unsignalized crossings with crash records, and lets
non-technical users compare, side by side in 3D, a crossing with and without a proposed traffic light, closing with a plain-language summary.
Validation against traffic counts remains future work.

#v(0.8cm)
#align(center)[#text(size: 14pt, weight: "bold", font: ("Times New Roman", "Liberation Serif"))[RESUMEN]]
#v(0.3cm)

Bogotá está entre las ciudades más congestionadas del mundo, pero probar una medida de tránsito antes de construirla sigue siendo lento: la
Encuesta de Movilidad 2023 hay que convertirla a mano en archivos para un simulador. Construimos un sistema de código abierto que transforma los
viajes de Usaquén en una simulación microscópica en SUMO, corre escenarios de demanda y cierres viales, prioriza cruces sin semáforo con datos de
siniestros y permite comparar en 3D, lado a lado, un cruce con y sin un semáforo propuesto, con un resumen en lenguaje sencillo. La validación con
aforos queda pendiente.

// ───────────────────────────────────────────── cuerpo

#set heading(numbering: numeracion)
#set page(numbering: "1", footer: context align(center, text(size: 9pt, counter(page).display("1"))))
#counter(page).update(1)

#include "capitulos/01-introduccion.typ"
#include "capitulos/02-descripcion-general.typ"
#include "capitulos/03-contexto.typ"
#include "capitulos/04-analisis.typ"
#include "capitulos/05-diseno.typ"
#include "capitulos/06-desarrollo.typ"
#include "capitulos/07-resultados.typ"
#include "capitulos/08-conclusiones.typ"

= Referencias
#bibliography("referencias.yml", title: none, style: "ieee", full: false)

#include "capitulos/10-anexos.typ"
