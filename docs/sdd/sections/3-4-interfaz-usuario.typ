#import "uml.typ": *

== Interfaz de usuario <sec-interfaz-usuario>

La interfaz es una aplicación web de una sola página a pantalla completa (`overflow: hidden`): el mapa de kepler.gl ocupa toda la ventana y los paneles flotan encima. Esta sección describe las pantallas de la interfaz gráfica y la navegación entre ellas; es consistente con los procesos de la @sec-vista-procesos. Los colores por modo se definen en `modos.js` y se usan en el mapa, la leyenda y el panel.

=== Diagrama de navegación

El panel lateral tiene cuatro pestañas (el usuario puede pasar de cualquiera a cualquiera). Dos capas del mapa llevan a pestañas concretas, y el simulador 3D se abre desde «Semaforizar» y vuelve a ella al cerrarse @ambler-ui.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (9mm, 11mm),
      inicio((0, 1), name: <i>),
      accion((1, 1), [*Demanda*\ presets, conteos,\ semilla, estilo], name: <dem>),
      accion((2, 1), [*Intersección*\ subpestañas: Ficha,\ Configurar, Comparar], name: <int>),
      accion((3, 1), [*Cierres*\ cierres viales], name: <cie>),
      accion((4, 1), [*Semaforizar*\ cruces candidatos,\ tráfico de fondo], name: <sem>),
      accion((2.5, 0), [*Mapa kepler.gl*\ capas «Semáforos» y\ «Priorización»], name: <map>),
      accion((4, 2.3), [*Simulador 3D*\ Comparar · Sin ·\ Con semáforo], name: <s3d>),
      edge(<i>, <dem>, "->", label: [al abrir], label-side: left),
      edge(<dem>, <dem>, "->", bend: 130deg, label: [Simular /\ Cargar simulación], label-side: left, loop-angle: 90deg),
      edge(<dem>, <int>, "<->", label: [pestaña]),
      edge(<int>, <cie>, "<->", label: [pestaña]),
      edge(<cie>, <sem>, "<->", label: [pestaña]),
      edge(<map>, <int>, "->", label: [clic en un\ semáforo], label-side: right),
      edge(<map>, <sem>, "->", label: [clic en un cruce\ candidato], label-side: left),
      edge(<sem>, <s3d>, "->", label: [Abrir simulador 3D], label-side: left),
      edge(<s3d>, <sem>, "->", label: [Cerrar], label-side: left, bend: 25deg),
    ))
  ],
  caption: [Diagrama de navegación de la interfaz gráfica.],
) <fig-navegacion>

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    table.header([Transición], [Disparador], [Proceso (@sec-vista-procesos)]),
    [Al abrir → Demanda], [Se carga la aplicación; si existe la precalculada `encuesta`, se muestra automáticamente.], [P1 (pasos 1--3, 8).],
    [Demanda → Demanda], [Botón «Simular» o «Cargar simulación» según coincida o no con una precalculada.], [P1 (pasos 2--8).],
    [Mapa → Intersección], [Clic en un punto de la capa «Semáforos».], [P2 (pasos 1--3).],
    [Mapa → Semaforizar], [Clic en un cruce de la capa «Priorización» o en la lista ordenada por puntaje.], [P3 (pasos 1--2).],
    [Semaforizar ↔ Simulador 3D], [«Abrir simulador 3D» y «Cerrar».], [P3 (pasos 3--12).],
    [Entre pestañas], [Clic en la pestaña.], [---],
  ),
  caption: [Transiciones del diagrama de navegación.],
)

=== Pantalla principal

#figure(
  block(width: 100%, height: 8.2cm, stroke: 0.6pt + luma(120), radius: 3pt, inset: 0pt)[
    #set par(justify: false)
    #set text(size: 8.5pt)
    #place(top + left, dx: 6pt, dy: 6pt, rect(width: 4.6cm, height: 7.6cm, stroke: 0.5pt, radius: 2pt, inset: 5pt, fill: luma(245))[
      *Panel lateral*\
      pestañas: Demanda · Intersección · Cierres · Semaforizar\
      #v(2pt)
      presets, conteos por modo, escala y semilla, estilo de conducción\
      #v(2pt)
      #box(stroke: 0.5pt, inset: 3pt)[Simular / Cargar simulación]
    ])
    #place(top + center, dx: -0.6cm, dy: 6pt, rect(width: 4.6cm, height: 1cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Leyenda de modos* y conmutador «Semáforos»
    ])
    #place(center + horizon, dx: 0.4cm, text(size: 9pt, fill: luma(100))[mapa kepler.gl con viajes animados])
    #place(top + right, dx: -6pt, dy: 6pt, rect(width: 3.8cm, height: 2.6cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Ficha de intersección*\ accesos, volúmenes, fases, Webster
    ])
    #place(bottom + right, dx: -6pt, dy: -30pt, rect(width: 3.8cm, height: 1.8cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: luma(245))[
      *Tarjeta de actividad* barras de progreso, cancelar
    ])
    #place(bottom + left, dx: 5cm, dy: -4pt, rect(width: 9cm, height: 0.6cm, stroke: 0.5pt, radius: 2pt, inset: 3pt, fill: luma(245))[
      #align(center)[línea de tiempo de kepler.gl]
    ])
  ],
  caption: [Esquema de la pantalla principal del visor.],
) <fig-ui-principal>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Elemento], [Descripción]),
    [Panel de demanda], [Elige un preset, ajusta viajes por modo (el total se valida contra el máximo de 100.000), escala, semilla y estilo. Si los valores coinciden con una precalculada, el botón principal es «Cargar simulación» y la carga es inmediata; si no, «Simular» lanza una corrida.],
    [Panel de cierres], [Lista de cierres viales (tramo y horario) que se envían con la solicitud de simulación.],
    [Ficha de intersección], [Pestaña «Intersección», con tres subpestañas: «Ficha» (accesos y volumen simulado por acceso, programa de fases), «Configurar» (editar duraciones de fase o calcular tiempos con Webster) y «Comparar» (lanza simulaciones con distintos programas y compara métricas de demora, cola y peatones).],
    [Panel «Semaforizar»], [Lista de cruces candidatos por puntaje, selección en el mapa, tráfico de fondo por modo y botón para abrir el simulador 3D.],
    [Leyenda de modos], [Colores por modo y conmutador de la capa «Semáforos».],
    [Capas de intersecciones], [«Semáforos» (puntos, con la ficha al hacer clic) y «Priorización» (cruces candidatos por nivel: prioritario, recomendado, observación). Las notas de la API (por ejemplo, «sin datos de siniestros») se muestran al usuario.],
    [Tarjeta de actividad], [Muestra la etapa actual, el avance global y el de la etapa, y permite cancelar. Al terminar una corrida bien, el visor carga sus trips solo. También muestra la barra de progreso de la descarga, calculada con `X-Tamano-Original` en las precalculadas.],
    [Línea de tiempo], [Control de kepler.gl para animar los viajes.],
  ),
  caption: [Elementos de la pantalla principal.],
)

=== Simulador 3D

#figure(
  block(width: 100%, height: 8cm, stroke: 0.6pt + luma(120), radius: 3pt, inset: 0pt)[
    #set par(justify: false)
    #set text(size: 8.5pt)
    #place(top + left, rect(width: 50%, height: 100%, stroke: 0.5pt, inset: 6pt, fill: luma(250))[
      #align(center)[*Sin semáforo (actual)*]
      #v(1fr)
      #align(center)[escena three.js lado A]
      #v(1fr)
    ])
    #place(top + right, rect(width: 50%, height: 100%, stroke: 0.5pt, inset: 6pt, fill: luma(250))[
      #align(center)[*Con semáforo propuesto*]
      #v(1fr)
      #align(center)[escena three.js lado B]
      #v(1fr)
    ])
    #place(top + center, dy: 30pt, rect(width: 6.4cm, height: 0.8cm, stroke: 0.5pt, radius: 8pt, inset: 4pt, fill: white)[
      #align(center)[píldora: tiempo · velocidad · pausa]
    ])
    #place(bottom + center, dy: -6pt, rect(width: 10cm, height: 1.7cm, stroke: 0.5pt, radius: 2pt, inset: 4pt, fill: white)[
      *Tarjeta inferior:* telemetría del actor seguido (velocidad, aceleración, líder, riesgo TTC/DRAC/PET, acción) · comparación de métricas por lado · pestañas Comparar / Sin / Con
    ])
    #place(bottom + left, dx: 6pt, dy: -6pt, rect(width: 2.2cm, height: 1.7cm, stroke: 0.5pt, radius: 2pt, inset: 3pt, fill: white)[
      #align(center)[Minimapa OSM]
    ])
  ],
  caption: [Esquema del simulador 3D comparativo.],
) <fig-ui-3d>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Elemento], [Descripción]),
    [Pantalla dividida], [Pestañas «Comparar» (los dos lados), «Sin semáforo» y «Con semáforo» (un lado a pantalla completa). Cada lado es una escena three.js (`Escena3D`).],
    [Píldora superior], [Tiempo simulado, factor de velocidad (0,25--20) y pausa.],
    [Tarjeta inferior], [Telemetría del actor seguido y el índice de riesgo (TTC, DRAC, PET), con la acción en lenguaje natural, y las métricas comparadas por lado (vehículos en el cruce, espera, conflictos, riesgo máximo).],
    [Actor seguido], [Se puede cambiar o inyectar uno propio (auto, moto, taxi, bici, peatón, entre otros) eligiendo el acceso, el giro y el estilo de conducción.],
    [Modo manual], [El teclado acelera, frena y elige el giro; los comandos se aplican igual en los dos lados.],
    [Cámara], [De persecución, con colisión contra edificios, o aérea.],
    [Minimapa], [Mapa OSM con la posición y el rumbo del actor seguido (sin token).],
  ),
  caption: [Elementos del simulador 3D.],
)

El simulador se carga de forma diferida (`lazy`) porque three.js y maplibre pesan, y queda envuelto en `LimiteErrores`, de modo que un fallo gráfico no tumba el mapa.
