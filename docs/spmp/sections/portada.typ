#let portada(info) = [

#align(center)[

  #v(3em)

  #image("/figures/logo_javeriana.png", height: 4.5cm)

  #v(3em)

  #text(size: 16pt)[
    *PONTIFICIA UNIVERSIDAD JAVERIANA* \
    Facultad de Ingeniería -- Departamento de Ingeniería de Sistemas
  ]

  #v(5em)

  #text(size: 14pt, weight: "bold")[
    PLAN DE ADMINISTRACIÓN DEL PROYECTO DE SOFTWARE \
    (SPMP)
  ]

  #v(1em)

  #text(size: 12pt, weight: "bold")[Generación de Escenarios de Movilidad Urbana para la Toma de Decisiones en Localidades de Bogotá]

  #v(3em)

  #text(size:14pt)[*Estándar base:* IEEE Std 1058--1998 / ISO / IEC 12207:2008]

  #v(7em)

  #text(size: 12pt)[#info.autores.join("\n")]

  #v(1em)

  #text(size: 12pt)[*Director:* Ing. #info.director, PhD.]

  #v(3em)

  #text(size: 12pt)[Bogotá D.C., #datetime.today().display() ]

]
]
