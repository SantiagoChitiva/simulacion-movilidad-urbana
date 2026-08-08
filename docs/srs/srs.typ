// @brief: template para el documento SRS (Software Requeriments Specifications)
// NOTA: ver documentacion para utilizar typst como lenguaje de marcado (es parecido a LaTeX) pero mas sencillo y mejor documentado

// ==============================
// BEGIN - import
// ==============================

#import "metadata.typ": info

#import "sections/portada.typ": portada
#import "sections/lista-contenidos.typ": listaContenidos
#import "sections/lista-tablas.typ": listaTablas
#import "sections/lista-ilustraciones.typ": listaIlustraciones
#import "sections/01-introduccion.typ": introduccion
#import "sections/02-descripcion-global.typ": descripcionGlobal
#import "sections/03-requerimientos-especificos.typ": requerimientosEspecificos
#import "sections/04-proceso-ingenieria-requerimientos.typ": procesoIngenieriaRequerimientos
#import "sections/05-proceso-verificacion.typ": procesoVerificacion
#import "sections/06-anexos.typ": anexos

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

#set page(
  margin: 2.5cm,

  header: context {
    grid(
      columns: (auto, 1fr, auto),
      [#image("figures/logo_javeriana.png", height: 50%)],
      [#h(.5cm) SRS: #info.nombreProyecto],
      [#info.logoEmpresaUri]
    )
    line(length: 100%)
  },

  footer: context {
    line(length: 100%)
    grid(
      columns: (1fr, auto),
      [*EFSS* #h(.4cm) Creado por EFSS -- Ingeniería de Sistemas PUJ],
      [#counter(page).display()]
    )
  }
)

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
// filas (contenido o registro de la tabla)
    [Indica la versión del documento, que depende según la forma de administración de configuraciones seleccionada.],[Se incluye la fecha en la que fue realizado el cambio del documento.],[Permite especificar las secciones del documento que fueron modificadas.],[Es un pequeño resumen de los cambios más relevantes que fueron realizados en la versión],[Indica las personas del grupo de trabajo que son responsables del o los cambios realizados en el documento.]
  ),
  caption: [Historial de cambios.]
)

#pagebreak()

#listaContenidos() // lista de contenidos de todas las secciones dentro del documento

#pagebreak()

#listaTablas() // lista de tablas utilizadas dentro del documento, una tabla debe estar dentro de un entorno #figure()

#pagebreak()

#listaIlustraciones() // lista de ilustraciones o imagenes dentro del documento, una ilustracion/imagen debe estar dentro de un entorno #figure()

#pagebreak()

// ==============================
// BEGIN - contenido
// ==============================

#introduccion(info) // seccion 01
#descripcionGlobal() // seccion 02
#requerimientosEspecificos() // seccion 03
#procesoIngenieriaRequerimientos() // seccion 04
#procesoVerificacion() // seccion 05
#anexos() // seccion 06

// ==============================
// END - contenido
// ==============================

