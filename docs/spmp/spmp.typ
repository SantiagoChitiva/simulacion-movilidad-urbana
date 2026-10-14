// @brief: SPMP (Software Project Management Plan) -- IEEE Std 1058-1998 / ISO/IEC 12207:2008
// Compilar: typst compile spmp.typ  (o desde Python: typst.compile("spmp.typ", root="."))

#import "metadata.typ": info
#import "sections/portada.typ": portada

#set document(title: "SPMP -- " + info.nombreProyecto, author: info.autores)
#set text(lang: "es", size: 11pt)
#set par(justify: true)
#set page(
  margin: 2.5cm,
  numbering: "1",
  footer: context [
    #line(length: 100%, stroke: 0.4pt)
    #grid(columns: (1fr, auto), [SPMP -- versión #info.version], [#counter(page).display()])
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

// ───────────────────────────────────────────── preliminares (sin numerar)

#heading(numbering: none)[1. Historial de Cambios]

#figure(
  table(
    columns: (auto, auto, 1fr, 18%),
    table.header([Versión], [Fecha], [Descripción del cambio], [Autor(es)]),
    [0.1], [30/04/2026], [Creación inicial del documento. Definición de estructura y alcance preliminar del proyecto.], [Santiago Chitiva, Samuel Campos],
    [0.2], [01/05/2026], [Actualización del propósito del proyecto tras reunión con el director.], [Felipe Garrido, Erick Salazar],
    [0.3], [04/05/2026], [Incorporación del modelo de ciclo de vida híbrido (CRISP-DM + Scrum). Justificación de alternativas descartadas.], [Samuel Campos, Santiago Chitiva],
    [0.4], [05/05/2026], [Incorporación de comentarios de la Feria de Pósters. Ajuste de estimaciones Fase 3. Confirmación del alcance con director.], [Felipe Garrido, Erick Salazar],
    [0.5], [06/05/2026], [Revisión y aprobación por el director. Ajustes al plan de riesgos (R1 y R3 reclasificados como críticos).], [Santiago Chitiva, Samuel Campos],
    [0.6], [09/05/2026], [Actualización de la calendarización a 10 semanas con incorporación de ruta crítica y prerrequisitos.], [Todos],
    [1.0], [10/05/2026], [Versión final para entrega formal. Revisión de consistencia interna entre secciones.], [Erick Salazar, Felipe Garrido],
    [1.1], [31/05/2026], [Reincorporación formal del módulo web al alcance del proyecto por indicación del director y la profesora. Actualización de
    secciones 6.1, 6.2, 6.3, 6.5, WBS (F3.5), presupuesto y criterios de aceptación. Eliminación de restricción que excluyó la interfaz web en la
    versión anterior.], [Todos],
    [1.2], [02/06/2026], [Correcciones derivadas de las sugerencias del Profesor: adición de paginación, renumeración de figuras, ajuste de figuras a
    márgenes, inclusión de captions en figuras y tablas, y verificación de referencias citadas en el texto.], [Todos],
    [2.0], [13/10/2026], [Migración del documento a Typst (fuente versionada en `docs/spmp/`). Actualización al estado del proyecto (rama
    `feat/fases-b-f-estilos-cierres`):
    - alcance ampliado con la demanda parametrizable, el módulo de intersecciones y semaforización y el simulador 3D comparativo (6.1, 6.2, 6.4,
      6.5, 11);
    - herramientas reales del sistema (8.2), criterios de aceptación (8.3), WBS y calendarización con los Sprints 6 a 8 (9.3);
    - riesgos R8 a R11 (12.2), ítems de configuración y estructura del repositorio (12.3, Anexo A) y nueva métrica de pruebas automatizadas (12.4).],
    [Equipo EFSS],
    [2.1], [14/10/2026], [Alcance del Sprint 7 (9.3): escena 3D tipo videojuego, modo manual del actor seguido y priorización de cruces con reglas y
    evidencia (siniestros de la SDM, colegios y centros de salud de OSM), siguiendo el proyecto Semáforos de Barranquilla.], [Equipo EFSS],
  ),
  caption: [Historial de cambios del documento.],
) <tabHistorial>

#heading(numbering: none)[2. Prefacio]

El presente documento constituye el Plan de Administración del Proyecto de Software (SPMP) para el proyecto de grado "#info.nombreProyecto",
desarrollado por cuatro estudiantes de Ingeniería de Sistemas de la Pontificia Universidad Javeriana.

El proyecto tiene como propósito diseñar e implementar dos módulos:
- un módulo de procesamiento de datos que automatiza la transformación de la información de la Encuesta de Movilidad de Bogotá (2023) y de los aforos
  vehiculares en hora de máxima demanda en archivos de entrada válidos para el simulador de tráfico SUMO (Simulation of Urban MObility) @sumo;
- un módulo web que permite visualizar los resultados producidos por SUMO y parametrizar nuevas simulaciones desde una interfaz gráfica accesible, sin
  interactuar con archivos de configuración técnicos.

En la versión 2.0, el módulo web incorpora además el análisis de intersecciones y un simulador 3D que compara, lado a lado, un cruce sin semáforo y
el mismo cruce con un semáforo propuesto.

Este documento está dirigido principalmente al equipo de desarrollo, al director del proyecto y a los jurados evaluadores del trabajo de grado. El
SPMP se basa en el estándar IEEE Std 1058-1998 @ieee1058, complementado con ISO/IEC 12207:2008 @iso12207. Los procesos de soporte se describen con
diagramas BPMN 2.0 @bpmn, cuya ubicación se señala en cada sección correspondiente.

#heading(numbering: none, outlined: false)[3. Tabla de Contenidos]
#outline(title: none, depth: 2)

#heading(numbering: none, outlined: false)[4. Lista de Figuras]
#outline(title: none, target: figure.where(kind: image))

#heading(numbering: none, outlined: false)[5. Lista de Tablas]
#outline(title: none, target: figure.where(kind: table))

#pagebreak()

// ───────────────────────────────────────────── cuerpo (numeración desde la sección 6, como en la versión 1)

#set heading(numbering: "1.1")
#counter(heading).update(5)

#include "sections/06-vista-general.typ"
#include "sections/07-glosario.typ"
#include "sections/08-contexto.typ"
#include "sections/09-administracion.typ"
#include "sections/10-monitoreo.typ"
#include "sections/11-entrega.typ"
#include "sections/12-soporte.typ"
#include "sections/13-anexos.typ"

#heading(numbering: none)[14. Referencias]
#bibliography("referencias.yml", title: none, style: "ieee", full: true)
