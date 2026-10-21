= Contexto del Proyecto

== Antecedentes

*Simular el tránsito a distintas escalas.* Un modelo de tránsito puede mirar la red desde lejos o de cerca. Los modelos macroscópicos tratan el flujo
como un fluido; vienen de la teoría de ondas cinemáticas de Lighthill y Whitham @lighthill, que Daganzo discretizó en el modelo de transmisión de
celdas @daganzo. Sirven para redes enormes, pero no distinguen un vehículo de otro. Los microscópicos, en cambio, mueven cada vehículo según su
velocidad, la distancia al de adelante y las reglas de la vía. Cuestan más cómputo y piden más datos, pero dejan ver lo que pasa en una intersección
concreta: quién espera, quién frena y quién se mete. Este proyecto necesitaba ese nivel de detalle, porque las preguntas que quería responder eran
sobre cruces y vías específicas.

*De una encuesta a una demanda.* La forma clásica de describir la demanda es una matriz origen–destino: cuántos viajes van de cada zona a cada otra en
un periodo @ortuzar. Una encuesta no entrevista a toda la ciudad. Cada respuesta trae un factor de expansión que indica a cuántos viajes reales
representa, y con esos factores se reconstruye la demanda total. En este proyecto no se armó una matriz agregada. Cada viaje de la encuesta se
replicó tantas veces como indica su factor (con un tope para no saturar la red) y se conservaron su hora de salida y su modo. Así la simulación
mantiene la variedad de la encuesta en lugar de promediarla.

*SUMO y el comportamiento de los conductores.* SUMO @sumo @sumodocs es un simulador microscópico de código abierto que mantiene el Centro Aeroespacial
Alemán (DLR) bajo la Fundación Eclipse. Por defecto, cada vehículo sigue al de adelante con el modelo de Krauß @krauss, que elige la mayor velocidad
con la que todavía puede frenar a tiempo si el líder frena. Algunos de sus parámetros sirven para representar conductores más o menos agresivos:
- la imperfección (`sigma`);
- el factor de velocidad;
- el tiempo de reacción (`tau`).

Las rutas se calculan con duarouter, que busca el camino más corto en tiempo para cada viaje. Una asignación de equilibrio en el sentido de Wardrop
@wardrop requeriría iterar esa búsqueda (SUMO lo hace con duaIterate @duaiterate); el proyecto usó una sola pasada, como se discute en el capítulo
VII. TraCI @traci es la interfaz que deja a un programa externo avanzar la simulación paso a paso, leer el estado de cada actor y darle órdenes.

*Los semáforos y el método de Webster.* Un semáforo reparte el derecho de paso entre los movimientos de un cruce mediante un programa de fases; cada
fase tiene una duración y una luz para cada movimiento. Webster @webster propuso en 1958 una fórmula para el ciclo que minimiza la demora media:
$C_0 = (1,5 L + 5) / (1 - Y)$, donde $L$ es el tiempo perdido por ciclo e $Y$ la suma, entre las fases, de la razón entre el flujo del movimiento más
cargado y su flujo de saturación. El verde de cada fase se reparte en proporción a esas razones. Sigue siendo el punto de partida en los cursos y
manuales de tránsito, y es lo que el sistema usa para proponer tiempos.

*Medir la seguridad sin esperar choques.* Los choques son eventos raros; esperar a que ocurran para evaluar una medida no es una opción. Por eso se
usan medidas sustitutas de seguridad, calculadas sobre trayectorias @gettman:
- el *tiempo a la colisión* (TTC): segundos que faltan para alcanzar al de adelante si nadie cambia de velocidad;
- la *desaceleración requerida para evitarla* (DRAC);
- el *tiempo posterior a la invasión* (PET): diferencia entre los momentos en que dos actores pasan por el mismo punto de conflicto.

Un TTC o un PET menores a 1,5 s se consideran conflictos serios. En una simulación microscópica estas medidas salen directamente del estado de
cada vehículo.

*¿Dónde poner un semáforo?* Decidir dónde instalar un semáforo nuevo es una pregunta de priorización antes que de simulación: hay cientos de cruces y
solo se puede estudiar a fondo unos pocos. El proyecto Semáforos de Barranquilla @barranquilla mostró una forma transparente de hacerlo. Primero
aplica reglas duras: el cruce debe ser de una vía colectora o mayor, a nivel, con un conflicto real y sin otro semáforo en la misma cuadra. Después
busca evidencia, como siniestros, tramos largos sin semáforo y colegios o centros de salud cerca. Esa evidencia se calibra contra los cruces que la
ciudad ya decidió semaforizar. El resultado es una lista para estudiar primero, no un dictamen.

*Comparar con la realidad.* Para saber si una simulación reproduce la calle, se comparan sus volúmenes con conteos reales (aforos). El estadístico
GEH es la medida usual; la práctica británica, que se volvió referencia, pide que al menos el 85 % de los puntos tenga un GEH menor a 5 @dmrb. Esta
validación quedó pendiente en el proyecto (capítulo VIII).

== Análisis de contexto

Hay varias herramientas que resuelven partes del mismo problema. La @tabContexto las compara con el sistema construido en los aspectos que más
importaban para el usuario objetivo: un analista o directivo de una secretaría de movilidad que no programa.

#figure(
  table(
    columns: (19%, 1fr, 1fr),
    table.header([*Solución*], [*Fortalezas*], [*Debilidades para este problema*]),
    [PTV Vissim / Visum @vissim], [Estándar comercial de la ingeniería de tránsito; calibración y reportes maduros; soporte técnico.], [Licencias
    costosas; modelo cerrado; armar la demanda desde una encuesta sigue siendo trabajo manual del consultor.],
    [Aimsun Next @aimsun], [Integra modelos macro, meso y micro en una sola herramienta; usado por administraciones de tráfico.], [Licencia comercial;
    curva de aprendizaje alta; no está pensado para que un directivo lo use por su cuenta.],
    [MATSim @matsim], [Código abierto; simula agentes con planes diarios completos; muy usado en investigación.], [Es mesoscópico (no ve carriles ni
    semáforos en detalle) y requiere configurar y programar en Java.],
    [SUMO + OSMWebWizard @osmwebwizard], [Gratuito; genera un escenario desde OpenStreetMap en minutos.], [La demanda es aleatoria, no viene de una
    encuesta; no compara escenarios ni explica resultados.],
    [Semáforos de Barranquilla @barranquilla], [Priorización clara y honesta, con lenguaje para no técnicos; ilustra el efecto de un semáforo.], [La
    simulación es ilustrativa (tráfico supuesto y un cruce aislado); no se conecta con la demanda de una encuesta ni con una red completa.],
    [*Este proyecto*], [Demanda desde la Encuesta 2023; red real de Usaquén; parametrización desde el navegador; priorización con siniestros;
    comparación 3D con y sin semáforo sobre la misma demanda y con resumen en palabras; código abierto.], [Sin validación GEH; transporte público
    representado como caminata; solo la mañana y los viajes internos de la localidad.],
  ),
  caption: [Comparación con soluciones relacionadas.],
) <tabContexto>

Las herramientas comerciales son más completas en calibración y reportes, pero dejan el trabajo de preparar la demanda en manos de un especialista y
cuestan lo que una secretaría de una ciudad intermedia, o un grupo académico, no siempre puede pagar. Las alternativas abiertas resuelven pedazos: MATSim
la demanda de agentes, OSMWebWizard la red, Barranquilla la priorización. Lo que el proyecto aporta es la cadena completa, desde la encuesta oficial
hasta una frase que un directivo puede leer, con todo el código y los datos abiertos para que un tercero repita cada resultado.
