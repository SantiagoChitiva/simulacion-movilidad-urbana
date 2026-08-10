
#let listaContenidos() = [

#align(center)[#heading(numbering: none)[Contenido]]

#[
  #show outline.entry.where(level: 1): it => {
    let numSec = if it.element.numbering != none {
      context [#counter(heading).at(it.element.location()).first()\. ]
    }

    link(it.element.location())[
      *#numSec#upper(it.element.body)*
    ]
    box(width: 1fr, repeat[*.*])
    strong(it.page())
    linebreak()
  }
  #outline(title: [])
]

]
