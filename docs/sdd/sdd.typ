// @brief: SPMP (Software Project Management Plan) -- IEEE Std 1058-1998 / ISO/IEC 12207:2008
// Compilar: typst compile spmp.typ  (o desde Python: typst.compile("spmp.typ", root="."))

#import "metadata.typ": info
#import "sections/portada.typ": portada

#set document(title: "SDD -- " + info.nombreProyecto, author: info.autores)
#set text(lang: "es", size: 11pt)
#set par(justify: true)
#set page(
  margin: 2.5cm,
  numbering: "1",
  footer: context [
    #line(length: 100%, stroke: 0.4pt)
    #grid(columns: (1fr, auto), [SDD -- versión #info.version], [#counter(page).display()])
  ],
)

#show figure.where(kind: table): set block(breakable: true)
#show figure.where(kind: table): set figure(supplement: [Tabla])
#show figure.where(kind: table): set figure.caption(position: top)
#show figure.where(kind: image): set figure(supplement: [Figura])
#set table(stroke: 0.5pt + luma(150), inset: 5pt, align: left)
#show table.cell.where(y: 0): set text(weight: "bold")
#show table: set par(justify: false)

#page(numbering: none, footer: none)[#portada(info)]
#counter(page).update(1)

#heading(outlined: false)[Tabla de Contenidos]
#outline(title: none, depth: 2)

#heading(outlined: false)[Lista de Figuras]
#outline(title: none, target: figure.where(kind: image))

#heading(outlined: false)[Lista de Tablas]
#outline(title: none, target: figure.where(kind: table))

#pagebreak()

#set heading(numbering: "1.1")

#include "sections/1-introduccion.typ"
#include "sections/2-descripcion-general-sistema.typ"
#include "sections/3-arquitectura-sistema.typ"
#include "sections/4-disenhio-datos.typ"
#include "sections/5-disenhio-componentes.typ"
#include "sections/6-disenhio-interfaces.typ"
#include "sections/7-atributos-calidad.typ"
#include "sections/8-apendices-referencias.typ"

#heading[Referencias]
#bibliography("referencias.yml", title: none, style: "ieee", full: true)
