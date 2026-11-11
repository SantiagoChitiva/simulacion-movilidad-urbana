#import "uml.typ": *

== Vista de procesos del sistema <sec-vista-procesos>

La vista de procesos muestra las principales acciones con las que el usuario interactúa con el sistema. Se representan con diagramas de actividad (uno por proceso, sin repetir la misma información en otro tipo de diagrama) y son consistentes con el diagrama de navegación de la interfaz gráfica (@fig-navegacion). Las pantallas citadas se describen en la @sec-interfaz-usuario y el detalle de las acciones complejas, con diagramas de secuencia, en la @sec-comportamiento.

Los tres procesos principales son: simular un escenario de demanda (P1), consultar y ajustar un semáforo existente (P2) y evaluar en 3D un cruce sin semáforo (P3).

=== P1. Simular un escenario de demanda <sec-proceso-simular>

El usuario elige o ajusta la demanda. Si coincide exactamente con un preset precalculado, la simulación se carga al instante; si no, se lanza una corrida en segundo plano, cuyo avance se consulta hasta que termina.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (8mm, 9mm),
      inicio((0, 0), name: <i>),
      accion((1, 0), [*1.* Elegir preset y ajustar\ conteos, semilla,\ estilo y cierres], name: <a1>),
      decision((2, 0), [*2.* ¿Coincide con\ precalculada?], name: <d1>),
      accion((3, 0), [*3.* Cargar simulación\ (precalculada)], name: <a2>),
      accion((2, 1), [*4.* Lanzar corrida\ `POST /simulaciones`], name: <a3>),
      accion((2, 2), [*5.* Consultar estado\ cada 2 s], name: <a4>),
      decision((2, 3), [*6.* ¿Estado?], name: <d2>),
      accion((3, 3), [*7.* Descargar los\ viajes de la corrida], name: <a6>),
      accion((3, 1), [*8.* Animar los viajes\ en el mapa], name: <a7>),
      accion((1, 3), [*9.* Mostrar el error\ o la cancelación], name: <a8>),
      fin((4, 1), name: <f1>),
      fin((0, 3), name: <f2>),
      edge(<i>, <a1>, "->"),
      edge(<a1>, <d1>, "->"),
      edge(<d1>, <a2>, "->", label: [sí]),
      edge(<d1>, <a3>, "->", label: [no], label-side: left),
      edge(<a3>, <a4>, "->"),
      edge(<a4>, <d2>, "->"),
      edge(<d2>, <a6>, "->", label: [terminado]),
      edge(<d2>, <a8>, "->", label: [error /\ cancelada], label-side: left),
      edge(<d2>, <a4>, "->", bend: -50deg, label: [en curso], label-side: right),
      edge(<a2>, <a7>, "->"),
      edge(<a6>, <a7>, "->"),
      edge(<a7>, <f1>, "->"),
      edge(<a8>, <f2>, "->"),
    ))
  ],
  caption: [Diagrama de actividad P1: simular un escenario de demanda.],
) <fig-proceso-simular>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Paso], [Descripción]),
    [1], [En el panel «Demanda» el usuario selecciona uno de los presets (`encuesta`, `mas_vehiculos`, `mas_peatones`, `dia_sin_carro`), modifica los viajes por modo (el total debe estar entre 1 y 100.000), la semilla y el estilo de conducción, y opcionalmente define cierres viales en el panel «Cierres».],
    [2], [El visor compara los valores del panel con las simulaciones precalculadas (`GET /precalculadas`). Si coinciden exactamente con una, el botón principal es «Cargar simulación»; si no, es «Simular».],
    [3], [Camino precalculado: el visor descarga `GET /precalculadas/{preset}/kepler-trips`, que llega comprimido; la barra de progreso se calcula con la cabecera `X-Tamano-Original`.],
    [4], [Camino con simulación: el visor envía `POST /simulaciones`. La API valida el cuerpo y responde `202` con el `id` de la corrida, que queda en cola.],
    [5], [El visor consulta `GET /simulaciones/{id}` cada 2 s y muestra en la tarjeta de actividad la etapa (generando demanda, ruteando, simulando, exportando) y el avance. El usuario puede cancelar con `POST /simulaciones/{id}/cancelar`.],
    [6], [Decisión según el estado de la corrida: `terminado`, `error`, `cancelada` o aún en curso (se vuelve al paso 5).],
    [7], [Con la corrida terminada, el visor descarga `GET /simulaciones/{id}/kepler-trips`.],
    [8], [El visor reemplaza el conjunto de datos de kepler.gl y muestra los viajes animados, coloreados por modo.],
    [9], [Si la corrida falló, se muestra el mensaje de error; si se canceló, la corrida queda como cancelada en el historial.],
  ),
  caption: [Pasos del proceso P1.],
)

=== P2. Consultar y ajustar un semáforo existente <sec-proceso-semaforo>

Con una simulación cargada, el usuario puede inspeccionar cada semáforo de la red, editar su programa, calcular uno por el método de Webster o comparar programas por sus métricas.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (7mm, 9mm),
      inicio((0, 0), name: <i>),
      accion((1, 0), [*1.* Activar la capa\ «Semáforos»], name: <b1>),
      accion((2, 0), [*2.* Clic en un semáforo:\ abrir la ficha], name: <b2>),
      decision((2, 1), [*3.* ¿Qué\ desea hacer?], name: <d1>),
      accion((0, 2), [*4.* Editar fases\ y duraciones], name: <b3>),
      accion((0, 3), [*5.* Guardar el programa\ `PUT .../programas/{pid}`], name: <b4>),
      decision((1, 3), [*6.* ¿Válido?], name: <d2>),
      accion((2, 2), [*7.* Calcular Webster\ `POST .../webster`], name: <b5>),
      accion((2, 3), [*8.* Revisar ciclo y\ verdes propuestos], name: <b6>),
      accion((3.5, 2), [*9.* Crear escenario de\ zona y comparar\ programas], name: <b8>),
      accion((3.5, 3), [*10.* Revisar métricas\ por programa], name: <b9>),
      accion((2, 4), [*11.* Ver el resultado\ en la ficha], name: <b7>),
      fin((2, 5), name: <f>),
      fin((3.5, 1), name: <f0>),
      edge(<i>, <b1>, "->"),
      edge(<b1>, <b2>, "->"),
      edge(<b2>, <d1>, "->"),
      edge(<d1>, <b3>, "->", label: [editar], label-side: left),
      edge(<d1>, <b5>, "->", label: [Webster], label-side: right),
      edge(<d1>, <b8>, "->", label: [comparar], label-side: left),
      edge(<d1>, <f0>, "->", label: [solo\ consultar], label-side: left),
      edge(<b3>, <b4>, "->"),
      edge(<b4>, <d2>, "->"),
      edge(<d2>, <b3>, "->", label: [no (422)], label-side: left),
      edge(<d2>, <b7>, "->", label: [sí], label-side: left),
      edge(<b5>, <b6>, "->"),
      edge(<b6>, <b7>, "->"),
      edge(<b8>, <b9>, "->"),
      edge(<b9>, <b7>, "->"),
      edge(<b7>, <f>, "->"),
    ))
  ],
  caption: [Diagrama de actividad P2: consultar y ajustar un semáforo existente.],
) <fig-proceso-semaforo>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Paso], [Descripción]),
    [1--2], [El conmutador «Semáforos» muestra los semáforos de la red como puntos (`GET /intersecciones`, con el volumen de la corrida cargada). Un clic abre la pestaña «Intersección» con la ficha (`GET /intersecciones/{tl_id}`): accesos, volúmenes, fases y notas sobre el origen del programa. La ficha tiene tres subpestañas: «Ficha» (consultar), «Configurar» (editar y Webster) y «Comparar».],
    [3], [Desde la ficha el usuario escoge entre editar el programa, calcular uno de Webster, comparar programas o solo consultar.],
    [4--6], [Editar: el usuario cambia fases y duraciones y guarda. La API valida el programa (un estado por movimiento, un amarillo ≥ 3 s si hay verdes, ciclo ≥ 15 s); si no es válido responde `422` y el usuario vuelve a editar.],
    [7--8], [Webster: la API calcula el ciclo y los verdes con los volúmenes de una corrida y los devuelve; el usuario los revisa y, si quiere, los edita como un programa nuevo.],
    [9--10], [Comparar: el visor pide un escenario de zona (`POST /intersecciones/{tl_id}/escenarios`), se comparan los programas elegidos (`POST .../comparaciones`) y la tabla de comparación muestra las métricas de cada uno.],
    [11], [El resultado queda visible en la ficha de la intersección.],
  ),
  caption: [Pasos del proceso P2.],
)

=== P3. Evaluar en 3D un cruce sin semáforo <sec-proceso-3d>

El usuario identifica los cruces que justificarían un semáforo y compara, en tiempo real, el cruce tal como está contra el mismo cruce con un semáforo propuesto.

#figure(
  [
    #set text(size: 7.5pt)
    #ajustar(diagram(
      node-inset: 5pt,
      spacing: (7mm, 9mm),
      inicio((0, 0), name: <i>),
      accion((1, 0), [*1.* Activar la capa\ «Priorización»], name: <c1>),
      accion((2, 0), [*2.* Elegir un cruce\ candidato], name: <c2>),
      accion((3, 0), [*3.* Configurar el tráfico\ de fondo por modo], name: <c3>),
      accion((3, 1), [*4.* Abrir el simulador 3D\ `POST .../comparacion3d`], name: <c4>),
      accion((2, 1), [*5.* Consultar la\ preparación], name: <c5>),
      decision((1, 1), [*6.* ¿Estado?], name: <d1>),
      accion((0, 1), [*7.* Mostrar\ el error], name: <c9>),
      accion((1, 2), [*8.* Obtener la geometría\ y conectar el WebSocket], name: <c6>),
      accion((2, 2), [*9.* Observar los lados A y B:\ telemetría y métricas], name: <c7>),
      decision((3, 2), [*10.* ¿Intervenir?], name: <d2>),
      accion((3, 3), [*11.* Pausar, cambiar actor,\ inyectar o conducir], name: <c8>),
      accion((2, 3), [*12.* Cerrar el simulador\ `DELETE .../{id}`], name: <c10>),
      fin((0, 3), name: <f>),
      edge(<i>, <c1>, "->"),
      edge(<c1>, <c2>, "->"),
      edge(<c2>, <c3>, "->"),
      edge(<c3>, <c4>, "->"),
      edge(<c4>, <c5>, "->"),
      edge(<c5>, <d1>, "->"),
      edge(<d1>, <c9>, "->", label: [error], label-side: left),
      edge(<d1>, <c6>, "->", label: [lista]),
      edge(<d1>, <c5>, "->", bend: 45deg, label: [preparando], label-side: left),
      edge(<c6>, <c7>, "->"),
      edge(<c7>, <d2>, "->"),
      edge(<d2>, <c8>, "->", label: [sí]),
      edge(<c8>, <c7>, "->", bend: -40deg),
      edge(<d2>, <c10>, "->", label: [no], label-side: left, corner: right),
      edge(<c10>, <f>, "->"),
      edge(<c9>, <f>, "->"),
    ))
  ],
  caption: [Diagrama de actividad P3: evaluar en 3D un cruce sin semáforo.],
) <fig-proceso-3d>

#figure(
  table(
    columns: (auto, 1fr),
    table.header([Paso], [Descripción]),
    [1--2], [La capa «Priorización» (`GET /intersecciones/priorizacion`) muestra los cruces sin semáforo por nivel (prioritario, recomendado, observación). El usuario elige uno con un clic en el mapa o desde la lista ordenada por puntaje en la pestaña «Semaforizar».],
    [3], [El usuario fija las intensidades del tráfico de fondo por modo (veh/h, 0--3.000), porque los viajes de la encuesta son demasiado escasos en una zona de 350 m.],
    [4], [El visor pide la comparación (`POST /cruces/{nodo}/comparacion3d`). La API responde `202` con el `id` y prepara la zona en un hilo; si ya hay dos comparaciones abiertas responde `429`.],
    [5--7], [El visor consulta `GET /comparacion3d/{id}` hasta que el estado sea `lista` o `error`; en este último caso se muestra el mensaje.],
    [8], [Con la comparación lista, el visor descarga la geometría de la escena y abre el WebSocket. Al conectar, el servidor arranca los dos SUMO y los calienta 240 s simulados.],
    [9], [El usuario observa en pantalla dividida el cruce sin semáforo (A) y con el semáforo propuesto (B): el actor seguido, su telemetría de riesgo (TTC, DRAC, PET) y las métricas comparadas por lado.],
    [10--11], [El usuario puede pausar, cambiar la velocidad, seguir otro actor, inyectar uno propio (auto, moto, taxi, bici, peatón...) eligiendo acceso y giro, o conducirlo con el teclado. Los comandos se aplican igual en los dos lados.],
    [12], [Al cerrar el simulador, el visor elimina la comparación y la API borra sus archivos. Si nadie se conecta en 180 s, la comparación expira.],
  ),
  caption: [Pasos del proceso P3.],
)
