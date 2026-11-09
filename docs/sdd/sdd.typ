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

#heading(outlined: false)[Historial de cambios]

#figure(
  table(
    columns: (auto, auto, 1fr, 18%),
    table.header([Versión], [Fecha], [Descripción del cambio], [Autor(es)]),

    [0.1], [20/02/2026], [Creación inicial del documento de diseño de software. Definición de su estructura y organización de las secciones principales.], [Samuel Campos],

    [0.2], [27/02/2026], [Desarrollo de la introducción, incluyendo el propósito del documento, alcance y convenciones utilizadas para describir el diseño del sistema.], [Erick Salazar],

    [0.3], [06/03/2026], [Descripción general del sistema, identificación de sus principales funcionalidades y definición de las características que debe cumplir.], [Santiago Chitiva],

    [0.4], [13/03/2026], [Primera definición de la arquitectura del sistema y distribución de responsabilidades entre los módulos principales.], [Felipe Garrido],

    [0.5], [20/03/2026], [Ampliación de la descripción arquitectónica mediante la identificación de componentes y sus relaciones dentro de la solución.], [Samuel Campos, Erick Salazar],

    [0.6], [10/04/2026], [Incorporación del diseño de datos, identificación de las entidades principales y definición de las relaciones necesarias para representar la información del sistema.], [Santiago Chitiva],

    [0.7], [24/04/2026], [Desarrollo del diseño de componentes, especificando las responsabilidades y operaciones principales de cada elemento del sistema.], [Felipe Garrido, Samuel Campos],

    [0.8], [08/05/2026], [Incorporación del diseño de interfaces y descripción de la comunicación entre los componentes de la solución.], [Erick Salazar],

    [0.9], [22/05/2026], [Definición inicial de los atributos de calidad del sistema, considerando aspectos como rendimiento, mantenibilidad, disponibilidad y escalabilidad.], [Santiago Chitiva, Felipe Garrido],

    [1.0], [12/06/2026], [Consolidación de la primera versión del diseño de software. Revisión de la arquitectura, estructura de datos, componentes e interfaces.], [Samuel Campos, Erick Salazar],

    [1.1], [17/07/2026], [Actualización de la arquitectura para reflejar los ajustes realizados en el procesamiento de datos y la integración con el simulador SUMO.], [Felipe Garrido],

    [1.2], [14/08/2026], [Actualización del diseño de componentes e interfaces para incorporar las funcionalidades de parametrización y visualización de escenarios desde el módulo web.], [Santiago Chitiva, Samuel Campos],

    [1.3], [11/09/2026], [Ampliación del diseño de datos y componentes relacionados con el análisis de intersecciones y la configuración de programas semafóricos.], [Erick Salazar, Felipe Garrido],

    [1.4], [25/09/2026], [Incorporación de los elementos arquitectónicos del simulador 3D comparativo y de los componentes asociados a la evaluación de seguridad vial.], [Santiago Chitiva],

    [1.5], [24/10/2026], [Actualización general del documento para reflejar el alcance ampliado del proyecto, incluyendo ajustes en arquitectura, datos, componentes, interfaces y atributos de calidad.], [Samuel Campos, Felipe Garrido],
  ),
  caption: [Historial de cambios del documento.],
)


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