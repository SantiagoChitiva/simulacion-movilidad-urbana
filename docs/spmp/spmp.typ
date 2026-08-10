// @brief: template para el documento SPMP (Software Project Management Planning)
// NOTA: ver documentacion para utilizar typst como lenguaje de marcado (es parecido a LaTeX) pero mas sencillo y mejor documentado

// ==============================
// BEGIN - import
// ==============================

#import "metadata.typ": info

#import "sections/portada.typ": portada


// ==============================
// END - import
// ==============================

#portada(info)

#counter(page).update(0) // reiniciar el contador de pagina despues de la portada

// ==============================
// BEGIN - set
// ==============================

#set text(lang: "es")

#set heading(
  numbering: "1.",
  supplement: [Sección]
)

#set page(margin: 2.5cm)

// ==============================
// END - set
// ==============================


// ==============================
// BEGIN - show
// ==============================

#show figure.where(kind: table): set block(
  breakable: true
)

#show figure.where(kind: table): set figure(
  supplement: [Tabla]
)

#show figure.where(kind: image): set figure(
  supplement: [Figura]
)

// ==============================
// END - show
// ==============================


#pagebreak()


#align(center)[#heading(numbering: none)[Historial de cambios]]

#figure(
  table(
    columns: 5,
    table.header([*Versión*],[*Fecha*],[*Sección modificada*],[*Descripción de cambios*],[*Responsables*]),

    [Indica la versión del documento, que depende según la forma de administración de configuraciones seleccionada.],[Se incluye la fecha en la que fue realizado el cambio del documento.],[Permite especificar las secciones del documento que fueron modificadas.],[Es un pequeño resumen de los cambios más relevantes que fueron realizados en la versión],[Indica las personas del grupo de trabajo que son responsables del o los cambios realizados en el documento.]
  ),
  caption: [Historial de cambios.]
)

#pagebreak()

// ==============================
// BEGIN - contenido
// ==============================

// #introduccion(info) // seccion 01

// ==============================
// END - contenido
// ==============================

