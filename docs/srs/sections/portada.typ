#let portada(info) = [

#align(center)[

  #v(2cm)

  #text(size: 18pt, weight: "bold")[ #info.nombreProyecto ] // comentario 1: es la forma de identificar el proyecto en el que se esta trabajando, este deberia ser creativo

  #text(size: 12pt)[ #info.nombreEmpresa ] // comentario 2: es la forma de indentificar el grupo de trabajo

  #v(4cm)

  #text(size: 12pt, weight: "bold")[ ESPECIFICACIÓN DE REQUERIMIENTOS DE SOFTWARE ]

  #text(size: 12pt)[ #datetime.today().display() ] // comentario 3: indica la fecha de entrega del documento al cliente

  #v(.75cm)

  #text(size: 12pt)[ versión #info.version ] // comentario 4: version del documento que se establece segun la forma escogida de administracion de configuracion

  #v(4cm)

  #image(info.logoEmpresaUri, width: 7.5%) // comentario 5: imagenes que indentifican el proyecto y la empresa

  #v(4cm)

  #text(size: 12pt)[ #info.autores.join("\n") ] // comentario 6: personas que realizaron el documento

]
]
