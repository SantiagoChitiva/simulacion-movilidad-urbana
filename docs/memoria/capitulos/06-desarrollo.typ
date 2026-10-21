#let captura(archivo, leyenda, ancho: 100%) = figure(image("../figures/" + archivo, width: ancho), caption: leyenda)

= Desarrollo de la Solución

== Proceso

=== Fases 1 y 2: entender y preparar los datos (CRISP-DM)

La exploración arrancó con tres fuentes en paralelo:
- los aforos vehiculares de hora de máxima demanda (HMD), que exploró Samuel Campos;
- la Encuesta de Movilidad 2023, que exploró Erick Salazar;
- la red de OpenStreetMap, que evaluó Santiago Chitiva.

Felipe Garrido consolidó lo encontrado en un informe de brechas. Tres hallazgos cambiaron el plan:

- *Los aforos no tenían coordenadas.* Las 336 estaciones HMD traían solo un texto libre con la dirección. Se escribió un geocodificador que interpreta
  direcciones como "AC 80 X KR 116A" y calcula la intersección de las dos vías en OpenStreetMap, pero los aforos no llegaron a alimentar la
  simulación. La validación GEH, que dependía de ellos, quedó pendiente.
- *La cobertura de la encuesta no era pareja.* Una de las nueve UTAM de Usaquén, Paseo de los Libertadores, tenía apenas el 44 % de la cobertura
  muestral esperada, y coincidía con la zona de borde hacia los cerros donde la red era más pobre.
- *La red de OpenStreetMap tenía pocos atributos.* Solo el 23 % de las vías tenía velocidad máxima, el 28 % número de carriles y el 42 % nombre.
  netconvert completó velocidades y carriles por tipo de vía; los nombres se recuperaron después cruzando cada tramo de SUMO con su vía de OSM.

Con eso se construyó la red 3D de Usaquén, con la elevación de cada nodo para que la escena 3D siguiera la pendiente de los cerros, y las zonas de
análisis. La encuesta se filtró a los viajes internos de la localidad.

=== Fase 3: construir el sistema (Scrum)

La @tabSprints resume lo que entregó cada sprint. Los cinco primeros siguieron el plan; del sexto en adelante, el alcance creció a pedido del director,
con su aprobación registrada en el SPMP.

#figure(
  table(
    columns: (10%, 1fr),
    table.header([*Sprint*], [*Entrega*]),
    [1], [Escenario base: generación de viajes desde la encuesta, rutas con duarouter y primera corrida completa en SUMO. Aquí se descubrió que SUMO
    descartaba casi todos los viajes si no venían ordenados por hora de salida.],
    [2–3], [Todos los modos de la encuesta como tipos de vehículo; el transporte público quedó como caminata a falta de GTFS. La calibración global
    quedó pendiente junto con el GEH.],
    [4], [Escenarios: cuatro presets de cambio modal que conservan el total de viajes, estilos de conducción y cierres viales.],
    [5], [Módulo web: API, visor con kepler.gl, parametrización, avance real y cancelación de corridas, y simulaciones precalculadas.],
    [6], [Intersecciones: catálogo de 220 semáforos con su ficha, programas, Webster, recorte de zonas y primera priorización.],
    [7], [Simulador 3D comparativo: dos SUMO en paralelo, cámara en tercera persona, riesgo (TTC, DRAC, PET), modo manual y escena con edificios
    reales. La priorización se rehízo con la lógica de Semáforos de Barranquilla.],
    [8], [Estabilidad del 3D (SUMO 1.27 se caía al suscribir actores que ya habían salido de la red, y el minimapa fallaba con actores que aún no
    entraban). El reporte exportable, el programa editable del semáforo propuesto y el transporte público con GTFS quedaron pendientes.],
    [9], [Usabilidad para perfiles no técnicos: tarjeta de cruces, cierres con un clic, ficha en palabras, comparación de programas con SUMO real,
    entrada simultánea del actor, resumen del viaje y tema claro.],
  ),
  caption: [Entregas por sprint.],
) <tabSprints>

Dos lecciones del proceso merecen mención. La primera vino de las pruebas con datos reales, que encontraron errores que las pruebas con datos de
juguete no veían. El orden de los viajes es un ejemplo. Otro es la comparación de programas, que parecía funcionar porque devolvía una tabla, aunque
todos los programas daban exactamente lo mismo. La segunda llegó en el sprint 9, al mostrarle el sistema a alguien que no lo había construido: casi
nada de lo técnico estaba mal, pero casi todo estaba escrito para el equipo. Reescribir textos, esconder ids y agregar un resumen final cambió más la
utilidad del sistema que muchas funciones nuevas.

=== Fase 4: evaluación

La evaluación se hizo en tres niveles. Hubo pruebas automatizadas de cada módulo y pruebas de integración con SUMO real: la API por WebSocket y
recorridos del visor con un navegador sin interfaz. A eso se sumaron corridas de los cuatro presets y comparaciones sobre cruces concretos. El
capítulo VII presenta los resultados.

== Producto final

Al abrir el visor se carga la simulación de la encuesta y los viajes de la mañana se animan sobre el mapa, con un color por modo (@figMapa). La
columna derecha tiene cuatro pestañas: Demanda, Intersección, Cierres y Semaforizar.

#captura("m01_mapa.png", [Visor con la simulación de la encuesta en tema claro.]) <figMapa>

*Demanda y cierres.* En Demanda se elige un preset (encuesta, más vehículos, más peatones o día sin carro), se ajustan los viajes por modo y el estilo
de conducción, y se ejecuta la corrida. Si el panel coincide con una simulación precalculada, el botón la carga en segundos en lugar de simular. En
Cierres las vías aparecen en gris. Un clic en una calle la selecciona y el usuario decide si cierra los dos sentidos y en qué franja horaria; lo
cerrado se pinta en rojo (@figCierres). Los cierres se aplican a la siguiente corrida.

#captura("m04_cierre.png", [Cierre vial elegido con un clic en el mapa.]) <figCierres>

*Semaforizar.* La lista agrupa los cruces sin semáforo en prioritarios, recomendados y en observación, con búsqueda por calle y filtros de cercanía a
colegios y hospitales (@figLista). Al elegir uno, un anillo lo marca en el mapa y se abre su tarjeta (@figTarjeta), que incluye:
- el tipo de vías;
- la medida sugerida;
- el porqué en frases ("Calle 163A lleva 1384 m sin un semáforo");
- las cifras de siniestros;
- la vista del cruce en Street View, satélite o mapa.

#grid(columns: 2, gutter: 14pt,
  [#captura("m06_lista.png", [Lista de cruces por prioridad.], ancho: 88%) <figLista>],
  [#captura("m07_tarjeta.png", [Tarjeta del cruce elegido.], ancho: 88%) <figTarjeta>],
)

*Simulador 3D comparativo.* El botón "Ver simulación: hoy y con semáforo" prepara en unos 30 s dos escenarios de la zona: el cruce como está y el
mismo cruce con un semáforo propuesto. Los muestra lado a lado, en tercera persona o en vista aérea (@fig3d). El usuario lanza un carro, una moto, una
bicicleta o un peatón por cualquier acceso, y el actor entra a la vez en los dos lados. También puede tomar el control con el teclado. Cada lado
tiene su minimapa, con el actor de ese escenario y, en gris, el del otro.

#captura("m09b_3d_aerea.png", [Simulador 3D: sin semáforo (izquierda) y con semáforo propuesto (derecha).]) <fig3d>

Cuando el viaje termina en los dos escenarios aparece el resumen (@figResumen). Muestra cuánto tardó, cuánto estuvo detenido, cuántas veces frenó en
seco, su riesgo máximo y su CO₂ en cada lado, y lo sintetiza en una frase que no afirma mejoras que no hubo. Debajo va el balance del cruce durante
la sesión, con frenadas, casi choques, colas y esperas por hora. Una nota recuerda que el tráfico de fondo es un supuesto y que la decisión final
requiere un aforo.

#captura("m10_resumen.png", [Resumen del viaje y balance del cruce.]) <figResumen>

*Intersección.* Un clic en un semáforo existente abre su ficha. Muestra el tráfico simulado por acceso y cómo cambian las luces en palabras ("Fase 1
· 27 s: pasan A. Avenida Carrera 9 de frente…"). Desde ahí se editan las fases con un clic en la luz de cada acceso, se calculan tiempos óptimos con
Webster y se compara el programa actual con el optimizado en una hora punta simulada (@figComparar).

#captura("22_comparar.png", [Comparación del programa actual con el de Webster.], ancho: 60%) <figComparar>
