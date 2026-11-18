# Guion del video de demostración

Duración objetivo: **7 a 8 minutos**. Una sola toma de pantalla con voz en off; se puede grabar por escenas y unirlas.

## Antes de grabar

1. Levantar el sistema (dos terminales):
   ```bash
   cd simulation-service/src && ../../.venv/Scripts/python.exe -m uvicorn api.api:app --port 8000
   cd kepler && npm run dev
   ```
   Abrir `http://localhost:5173` en Chrome a pantalla completa (F11), 1920 × 1080.
2. Esperar a que cargue la simulación precalculada "Encuesta" (barra de progreso arriba). Si aparece una tarjeta roja de una simulación interrumpida, cerrarla con la ×.
3. Ocultar el panel izquierdo de kepler.gl (flecha `<` arriba a la izquierda) para dejar más mapa.
4. **Preparar el 3D con anticipación**: en *Semaforizar*, abrir "Calle 163A × Carrera 13B" y pulsar *Ver simulación*. La primera vez tarda 1–2 minutos en recortar la zona. Cerrarlo y volver a abrirlo justo antes de grabar esa escena (la segunda vez es inmediata si no se cambió nada).
5. Grabar con OBS Studio (gratuito): fuente "Captura de pantalla", 30 fps, micrófono aparte. Desactivar notificaciones de Windows.
6. Ensayar una vez la ruta de clics. Hablar despacio; cada escena tiene su texto sugerido.

## Escena 1 — El problema (0:00–0:40)

**Pantalla:** el mapa de Usaquén con los viajes animados (pulsar ▶ en la línea de tiempo abajo, velocidad alta).

**Decir:**
> "Decidir dónde poner un semáforo, cómo manejar un cierre o qué pasa en un día sin carro normalmente exige estudios de tránsito de semanas. Este proyecto convierte los datos abiertos de Bogotá en simulaciones de tráfico que cualquier persona puede explorar desde el navegador. Lo probamos en la localidad de Usaquén."

## Escena 2 — De los datos a la simulación (0:40–1:30)

**Pantalla:** dejar correr la animación; señalar la leyenda de arriba (Auto, Moto, Bus SITP, TransMilenio, Peatón…).

**Decir:**
> "Cada punto es un viaje real de la Encuesta de Movilidad 2023, expandido con su factor oficial, que se mueve por la red de OpenStreetMap en SUMO, un simulador microscópico de código abierto. Los buses del SITP y de TransMilenio salen del GTFS de la ciudad: tienen sus paradas y sus horarios, y quien viaja en transporte público camina a la parada, espera y se sube. Todo esto lo genera un pipeline automático: no hay pasos manuales entre la encuesta y la simulación."

## Escena 3 — Escenarios de demanda (1:30–2:30)

**Pantalla:** pestaña *Demanda*.
1. Mostrar el horario *Mañana / Tarde*.
2. Pulsar el escenario *Día sin carro* → aparece "Cargar simulación" (precalculada) → cargarla.
3. Señalar en la leyenda cómo cambian los modos (menos autos, más bicicletas y peatones).
4. Bajar y mostrar los contadores por actor vial y el estilo de conducción (sin lanzar).

**Decir:**
> "En la pestaña de demanda se elige el horario y un escenario: la encuesta tal cual, más vehículos, más peatones o un día sin carro. Los escenarios reparten los viajes entre modos según la duración de cada viaje, así que se conserva el total. Los más usados ya están simulados y cargan en segundos; cualquier otra combinación se simula en el servidor y aquí se ve el avance."

## Escena 4 — Cierres viales (2:30–3:00)

**Pantalla:** pestaña *Cierres*; hacer clic en una avenida del mapa (se pinta en rojo), mostrar la lista y la opción de ambos sentidos. No lanzar.

**Decir:**
> "Para un cierre por obras basta con hacer clic en la vía. El cierre se aplica en la simulación y los conductores buscan rutas alternativas."

## Escena 5 — Un semáforo existente (3:00–4:00)

**Pantalla:** pulsar *Semáforos* en la leyenda; hacer clic en un semáforo de una avenida (por ejemplo, Carrera 15 con Calle 153). Pestaña *Intersección*:
1. *Ficha*: accesos con su volumen, las fases explicadas en palabras y el recuadro "Semáforo real (Secretaría de Movilidad)".
2. *Configurar*: pulsar *Calcular tiempos óptimos* (Webster).
3. *Comparar*: elegir actual vs. Webster, comparar y mostrar la frase de resultado, los rangos con varias semillas y los botones CSV/PDF.

**Decir:**
> "Cada semáforo tiene su ficha: por dónde llegan los carros, cuántos pasan y cómo cambian las luces, en palabras. El sistema la cruza con el inventario de la Secretaría de Movilidad, que dice cuántas fases tiene el semáforo real. Con el método de Webster se calculan tiempos óptimos para el tráfico simulado, y la comparación corre el mismo tráfico con cada programa varias veces para dar un rango, no un solo número. El resultado se descarga en PDF o CSV."

## Escena 6 — ¿Dónde hace falta un semáforo? (4:00–4:50)

**Pantalla:** pestaña *Semaforizar*. Mostrar los niveles (prioritario, recomendado, observación), el filtro "Cerca de colegio" y abrir "Calle 163A × Carrera 13B": insignia, "Por qué", cifras, foto del cruce (Street View).

**Decir:**
> "Esta pestaña responde dónde estudiar un semáforo nuevo. Aplica las reglas del proyecto Semáforos de Barranquilla a la red: descarta lo que no es un cruce real y usa como evidencia los siniestros registrados por la Secretaría, la cercanía a colegios y hospitales, los tramos largos sin semáforo y el tráfico simulado. Cada cruce explica por qué está en la lista."

## Escena 7 — El simulador 3D (4:50–6:30)

**Pantalla:** pulsar *Ver simulación: hoy y con semáforo*.
1. Mostrar la pantalla partida: izquierda *sin semáforo*, derecha *con semáforo propuesto*; el minimapa de cada lado.
2. En el panel izquierdo: Tipo *Carro*, llega por *Calle 163A*, sigue *Recto* → *Lanzar y seguir*. La cámara sigue al carro en los dos lados a la vez.
3. Señalar el HUD: velocidad, acción (frena, cede el paso), indicador de riesgo, conflictos.
4. Cambiar a *Aérea* un momento y volver a *3ª persona*. Subir la velocidad a 5×.
5. (Opcional) *Manual*: acelerar con las flechas unos segundos.
6. Cuando termine el viaje aparece el *Resumen*: duración, paradas, frenadas y el balance del cruce por hora. Leer la frase de veredicto.

**Decir:**
> "El simulador 3D pone el mismo cruce dos veces: como está hoy y con el semáforo propuesto, con exactamente el mismo tráfico. Lanzamos un carro que entra al mismo tiempo en los dos lados. Arriba se ve su velocidad, qué está haciendo y el riesgo, calculado con medidas usadas en seguridad vial como el tiempo para la colisión. Al final, el resumen compara el viaje y el balance del cruce: el semáforo suele cambiar casi choques por espera, y aquí se ve cuánto."

## Escena 8 — Validación con datos reales (6:30–7:20)

**Pantalla:** la tabla de GEH del capítulo de resultados de la memoria (el visor ya no tiene pestaña de validación).

**Decir:**
> "Un modelo tiene que compararse con la realidad. El sistema compara los vehículos simulados con los aforos de la Secretaría en 33 puntos de Usaquén, con el estadístico GEH, que es el estándar. Hoy el modelo no cumple el criterio: la encuesta solo describe los viajes que empiezan o terminan en la localidad, y la red de OpenStreetMap no tiene la capacidad real de las avenidas ni los tiempos reales de los semáforos, que la Secretaría no publica. Por eso el sistema sirve para comparar alternativas entre sí con la misma demanda, y lo dice explícitamente. Calibrar la red con datos de campo es el siguiente paso."

## Escena 9 — Cierre (7:20–7:50)

**Pantalla:** volver al mapa general con la animación corriendo.

**Decir:**
> "En resumen: datos abiertos de Bogotá convertidos automáticamente en simulaciones, escenarios que se lanzan desde el navegador, análisis de semáforos con evidencia y un simulador 3D para explicar las decisiones. Todo es código abierto y reproducible, y se puede llevar a otras localidades. Gracias."

## Consejos

- Si algo tarda (preparar el 3D, descargar una simulación), cortar en edición; no esperar en cámara.
- Mantener el mouse quieto mientras se habla; mover solo para hacer clic.
- El tema claro (botón de luna arriba a la derecha del panel) se ve mejor en video.
- Si hay que acortar a 5 minutos: quitar las escenas 4 y 8.
