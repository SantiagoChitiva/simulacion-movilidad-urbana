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
    [1.0], [2026-05-31], [Todas], [Versión inicial del SRS: pipeline ETL (F1–F5) y módulo web (F6–F7).], [Equipo EFSS],
    [2.0], [2026-10-13], [1.2, 1.3, 2.1, 2.2, 2.5, 2.8, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 4.1, 4.4, 5.3, 5.4],
    [Se actualiza el documento al estado de la rama `feat/fases-b-f-estilos-cierres`. Cada requerimiento indica su estado (Implementado, Parcial,
    Pendiente) y su módulo real. Se agregan:
    - demanda parametrizable (RF-021 a RF-025) y progreso, cancelación y animación de viajes (RF-026, RF-027);
    - intersecciones y semaforización (F8, RF-028 a RF-032);
    - simulador 3D comparativo de semáforo propuesto (F9, RF-033 a RF-042) y transporte público con GTFS (RF-043, pendiente);
    - RD-003, RD-004 y RNF-USA-001, con sus casos de prueba CP-029 a CP-042.
    Se reescriben las interfaces de usuario, software y comunicaciones (visor web, WebSocket, TraCI).],
    [Equipo EFSS],
    [2.1], [2026-10-14], [2.8, 3.1, 3.3, 4.4, 5.3],
    [Priorización con la lógica de Semáforos de Barranquilla y evidencia externa (RF-032 reescrito, RF-045). Simulador 3D: escena y HUD como la
    referencia, edificios OSM + Microsoft, un poste por acceso, sin cámara libre (RF-034, RF-035) y modo manual (RF-044). Casos CP-043 y CP-044.],
    [Equipo EFSS],
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

