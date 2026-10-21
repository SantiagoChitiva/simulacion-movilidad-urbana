= Introducción

Este documento cuenta cómo se construyó, a lo largo de 2026, un sistema para generar y comparar escenarios de movilidad en la localidad de Usaquén, en
Bogotá. El punto de partida fue una pregunta práctica: si la Secretaría Distrital de Movilidad quiere saber qué pasa al cerrar una vía, al cambiar la
proporción de carros y peatones o al poner un semáforo en un cruce, ¿qué tanto trabajo le cuesta simularlo con los datos que ya tiene? La respuesta
corta era "mucho": la Encuesta de Movilidad 2023 @encuesta describe con detalle cómo se mueve la ciudad, y SUMO @sumo puede simular el tránsito
vehículo por vehículo, pero entre una cosa y la otra había días de limpieza de datos, archivos XML escritos a mano y comandos que solo maneja un
especialista.

El proyecto cerró esa distancia en dos frentes. El primero es un pipeline que lee los viajes de la encuesta, los convierte en la demanda de una
simulación de la mañana (7:00 a 10:00) sobre la red vial real de Usaquén, corre SUMO y deja los resultados listos para un mapa. El segundo es un visor
web desde el que cualquier persona lanza nuevas simulaciones y analiza los semáforos de la localidad. Con el tiempo el visor creció en una dirección
que no estaba en la propuesta original: una lista de cruces donde convendría estudiar un semáforo, armada con datos de siniestros, y un simulador 3D
que muestra el mismo cruce con y sin semáforo, lado a lado, y al final del recorrido dice en palabras si el semáforo ayudó.

El documento sigue la estructura de la carrera. El capítulo II describe el problema y los objetivos tal como se plantearon y se resolvieron. El III
presenta los conceptos necesarios y compara el sistema con otras herramientas. El IV resume los requisitos (el detalle está en el SRS) y el V, el
diseño (detallado en el SDD). El VI narra el desarrollo por fases y muestra el producto. El VII presenta los resultados de las pruebas y de las
simulaciones, con sus limitaciones. El VIII discute el impacto, revisa el cumplimiento de los objetivos y propone el trabajo que sigue. Los
documentos de soporte (SPMP, SRS, SDD y propuesta) están listados en los anexos.

Una aclaración antes de empezar: la simulación representa un día hábil típico según la encuesta, no un promedio de varios días, e incluye solo los
viajes que empiezan y terminan en Usaquén. Sus resultados sirven para comparar alternativas entre sí, no para predecir cifras exactas de la calle.
Esa diferencia vuelve a aparecer en los capítulos VII y VIII.
