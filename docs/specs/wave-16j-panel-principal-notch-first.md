# Wave 16j — Panel principal, con la isla como producto

**Estado: APROBADO EN DIRECCIÓN (2026-09-25): "copia exactamente la interacción de Incredible". 16j-1 hecha; 16j-2 espera capturas de la ventana de Incredible.** Karen: "vamos a planear el rediseño del panel principal de
companion centrando la UX de producto sobre el notch". Evidencia: su captura de las 18:54 (ventana
principal hoy), sus capturas de Incredible (Apps, "Connecting Slack", "We use Pipedream…") y dos
investigaciones de solo lectura (Incredible 0.2.36 por nombres de recursos y archivos de
`~/.incredible` sin abrir credenciales; Pipedream Connect por su documentación pública).

## 1. El problema

Hoy la ventana principal es un chat que repite lo que la isla ya dijo, y encima enseña la maquinaria:

| En pantalla (18:54) | Qué es | Qué debería pasar |
|---|---|---|
| "Entendí: «…». Dime para si no es eso." | Confirmación de lo oído antes de delegar | Nunca como mensaje. Si hace falta, una frase en la isla |
| "Encargo: … · 1 búsqueda" | Estado del trabajo en segundo plano | Tarjeta de tarea en la isla (16i-3), no una línea en el chat |
| "Nativo ⌄", onda, teclado | Selector de modo y de entrada | Fuera de la cabecera: van a Ajustes o desaparecen |
| Micro y × abajo | Controles de la sesión de voz | La isla ya es el control de voz; la ventana no los repite |
| La respuesta entera | El resultado | Sí: aquí vive el detalle, pero como documento, no como burbuja |

Incredible no usa su ventana para hablar: la isla es donde se pide y se ve el estado; la ventana
guarda lo que queda (resultados, tareas, conocimiento, apps).

## 2. Lo que hace Incredible (medido, no supuesto)

- Dos superficies: la isla ("Island", con tarjetas) y una ventana con barra lateral. El detalle de
  la ventana no se pudo leer (su interfaz va comprimida dentro del binario); solo "Home" es seguro.
- Sus datos nombran las secciones: `knowledge/`, `memory/`, `tasks/`, `agents/`, y guías vistas de
  *knowledge, tasks, reminders, autopilot, dictation*.
- Cada resultado es una **tarjeta**: título, frase dicha y un documento con bloques; puede tener
  varias versiones y descartarse. Cada tarea en segundo plano tiene su propio hilo, aparte de la
  conversación.
- **Apps**: catálogo con icono y una línea de uso por app ("Schedule Outlook meetings… by
  talking"), búsqueda, "Featured apps", botón "+ Connect". Conectar abre un modal "Connecting
  Slack" con los dos iconos y una línea animada, abre el login en el navegador ("this window updates
  on its own", "Open it again") y termina en una página "You're connected". Detrás está Pipedream.
- Permisos uno por pantalla, con ilustración propia y una frase de por qué.

## 3. La propuesta: la ventana como archivo de lo que la isla hace

Barra lateral (misma pieza que Ajustes 16g) con cinco secciones:

1. **Inicio**: lo último que pasó, como tarjetas grandes (resultado, recibo de acción, tarea en
   curso). Vacío: "Mantén fn y pide algo" con la tecla dibujada. Sin campo de chat fijo: escribir
   abre la isla con el campo enfocado.
2. **Tareas**: lo que corre y lo que terminó, cada una con su progreso, pasos, "Parar" y su
   resultado. Es el destino de "Ver →" de la tarjeta de tarea de la isla (16i-3).
3. **Conversaciones**: el historial actual, leído como documentos (títulos, viñetas con formato,
   fuentes plegadas), sin líneas de estado internas.
4. **Apps**: conectores (ver §4).
5. **Memoria y Vocabulario**: ya existen en Ajustes 16g; se mueven aquí porque son contenido, no
   configuración. Ajustes queda en el pie de la barra.

La cabecera pierde el selector de modo, la onda y el teclado. La voz vive en la isla.

## 4. Apps con Pipedream Connect

Diseño de seguridad (no negociable):
- La clave secreta del proyecto de Pipedream **nunca** va en la app ni en argumentos, variables de
  entorno, archivos o logs de esta Mac. Vive solo en una función de servidor.
- **Una función mínima** (Vercel, cuenta de Karen) con dos rutas:
  `POST /connect-token` (devuelve el enlace de conexión de una app para su usuario) y
  `POST /tool` (ejecuta una herramienta de una app conectada vía el MCP de Pipedream).
  La app se autentica ante ella con una clave propia guardada en el Llavero, como hoy la de OpenAI.
- Entorno `development` de Pipedream: gratis, hasta 10 usuarios, y exige que Karen esté conectada a
  pipedream.com en el navegador donde conecta. Suficiente para esta fase.
- Conectar: botón "+ Conectar" → la app pide el enlace → lo abre en el navegador → modal
  "Conectando Slack" con "Abrir de nuevo" → la app consulta la función hasta ver la cuenta
  (no depende de un esquema `companion://`, que Pipedream no documenta).
- Desconectar borra la cuenta en Pipedream y avisa de que el acceso también se revoca en la propia
  app (Slack, Google).
- Por voz: "¿qué tengo hoy en el calendario?" → el agente pide las herramientas de esa app a la
  función; si la app no está conectada, la isla muestra una tarjeta "Conectar Google Calendar".

Sin la función, Apps se ve con el catálogo y un aviso de que falta; el resto de la app funciona
igual (ADR 001: basta la clave de OpenAI).

## 5. Sesiones

1. **16j-1 Limpieza**: fuera "Entendí…", "Encargo…" y los controles repetidos de la ventana; las
   respuestas se leen como documento (el formato ya se arregló el 2026-09-25). Tests de que ninguna
   línea de estado interna llega al hilo.
2. **16j-2 Barra lateral**: Inicio, Conversaciones, Memoria/Vocabulario movidos, Ajustes al pie.
3. **16j-3 Tareas**: la vista de tareas y "Ver →" desde la isla (va junto a 16i-3).
4. **16k Apps**: la función de servidor (repo aparte), la sección Apps, el modal y una app de prueba
   (Google Calendar o Slack) usable por voz.

## 6. Decisiones de Karen antes de firmar

- D1. ¿La ventana deja de ser un chat (sin campo fijo; escribir abre la isla)? Recomendado: sí.
- D2. ¿Memoria y Vocabulario salen de Ajustes a la barra lateral? Recomendado: sí.
- D3. Función de servidor: ¿Vercel en tu equipo personal (`karenrebecags-projects`) y repo aparte?
  El despliegue lo haces tú.
- D4. Primera app conectada: Google Calendar (lectura, bajo riesgo) o Slack.
- D5. El selector "Nativo ⌄": ¿se va a Ajustes › Voz o desaparece?

## 6b. Resueltas copiando a Incredible (Karen, 2026-09-25)

- D1: como Incredible. Lo verificado: su conversación guardada solo tiene turnos del usuario y del
  asistente, y la voz vive en la isla. Si su ventana tiene campo de texto no se pudo leer: hasta ver
  su ventana, se queda el campo de texto y se va todo control de voz.
- D2: sí. Conocimiento, memoria y tareas son secciones propias en sus datos.
- D3: Incredible tiene su propio servidor delante de Pipedream; el equivalente es la función en
  Vercel personal de Karen. Despliega Karen.
- D4: Slack, el flujo que Karen capturó ("Connecting Slack" y "We use Pipedream…").
- D5: desaparece. Incredible no deja elegir el cerebro.

16j-1 (2026-09-25): el hilo ya no muestra líneas de estado; fuera el selector "Nativo" (el
cambio de ejecutor ya no tiene control visible), el cambio voz/texto y el micro y el × de abajo.
El aviso de lo oído antes de un trabajo sigue protegido: el objetivo literal sale en la línea de
tarea de la isla, con Parar.

## 7. Riesgos

- Pipedream: el modo `development` no sirve para otras personas; pasar a producción es de pago.
- Las herramientas de una app conectada pueden escribir (enviar un Slack): todo lo que escribe pasa
  por la hoja de aprobación existente.
- Mover Memoria/Vocabulario rompe la búsqueda de Ajustes 16g: el inventario se actualiza en 16j-2.

## 8. La ventana de Incredible, observada (grabación 19:11, 83 s)

Reemplaza lo supuesto en §2-§3 y la D2 de §6b (Memoria y Vocabulario siguen en Ajustes, como en
Incredible, cuyos Ajustes tienen General, Incredible, Vocabulario, Contactos, Memoria, Sistema,
Cuenta, Miembros, Facturación y Datos y privacidad).

- **Barra lateral**: logo; *Home*; grupo *Customize*: Apps, Browser, Knowledge; grupo
  *Superpowers*: Saved tasks, Scheduled, Autopilot, Dictation; abajo una tarjeta "Use cases" y la fila
  del perfil (avatar, nombre, chevron) que abre un menú: Settings, Give feedback, Support, Learning
  center, Use cases, Sign out.
- **Home**: "Welcome, Karen"; tarjeta oscura grande "Hold [fn] to talk to Incredible" con una línea;
  a la derecha "Get Started 0 of 3" (Connect an app con botón negro, Add your browser, Schedule a
  task); debajo "Today" y la lista de tareas: título, icono de conversación, estado "Done" en verde,
  "1 hour ago", chevron. No hay campo de chat en la ventana.
- **Detalle de tarea** (modal sobre Home): título, "Done", hora, ×; la conversación (tu mensaje en
  burbuja negra a la derecha con tus iniciales, las respuestas en burbujas grises a la izquierda);
  a la derecha "No live picture" y *Details*: Started, Finished, Took. Abajo: "Your next message
  continues this task." y el botón negro "Follow up".
- **Follow up**: el modal y la ventana se van, y la isla se abre como barra con una etiqueta
  **TASK**: la tarea queda adjunta como contexto y lo siguiente que digas la continúa. Toda la
  conversación ocurre en la isla.

## 9. Sesiones (reemplaza §5)

1. **16j-1** hecha (§6b).
2. **16j-2** (ahora): barra lateral y Home como Incredible; la lista de tareas son las
   conversaciones; detalle de tarea en modal; Follow up abre la isla con la etiqueta TAREA y el
   siguiente turno continúa esa conversación. Solo aparecen en la barra las secciones que ya hacen
   algo (Home); Apps entra con 16k. Browser, Knowledge, Saved tasks, Scheduled, Autopilot y Dictation
   quedan para waves propias: una entrada que no hace nada sería mentir.
3. **16j-3** Tareas vivas: estado y duración reales por tarea (hoy una conversación no guarda su
   estado de trabajo).
4. **16k** Apps con Pipedream (§4).

## 10. Cierre de 16j-2 (2026-09-25)

Hecho e instalado, 392 tests, gates 0 fallos:
- Ventana: barra lateral (Inicio; perfil abajo con Ajustes y Enviar comentario), Home con saludo,
  tarjeta "Mantén fn para hablar con Companion", Primeros pasos (2 comprobables: pedir algo, tu
  perfil) y las tareas por día (Hoy, Ayer, Antes) con "Hace 1 h". Sin campo de chat.
- Detalle de tarea en modal: la conversación (tuya en negro a la derecha, respuestas en gris),
  Detalles (última actividad, mensajes), "Tu próximo mensaje continúa esta tarea." y "Seguir".
- Seguir: la tarea pasa a ser la conversación, la ventana se esconde y la isla abre como barra con
  la etiqueta TAREA y el título; al hablar, la etiqueta se va y el turno continúa esa conversación.

Revisiones: seguridad MEDIUM (un enlace podía mostrar un sitio y abrir otro: ahora queda como
texto) con test; código HIGH: Seguir con un trabajo en curso lo mataba en silencio (ahora espera,
con test); el detalle leía el disco en cada redibujo (ahora una vez al abrir); el pump de parciales
se quedaba con el oído del modo anterior (ahora se reinicia si cambia; sin test, no hay arnés de
hold en realtime); `Day` Hashable en su módulo. Pendiente de Karen: borrar el código muerto de la
ventana vieja (HeaderView, ThreadView salvo `visible`, StatusLine, ControlBar, ChatInputView,
AttachmentStrip, ChoiceDropdown, HistoryOverlay), porque borrar archivos es suyo.

Diferencias con Incredible que quedan: no hay estado "Done" ni duración por tarea (16j-3), ni
"No live picture"; Apps, Browser, Knowledge, Saved tasks, Scheduled, Autopilot y Dictation no se
muestran hasta que hagan algo.
