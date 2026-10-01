# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Una
entrada por wave cerrada; sin releases versionados hasta Wave 5.

## [Unreleased]

### Fixed
- **Un test de permisos ya no falla cuando la Mac se congela unos segundos (2026-10-01).** Solo
  tests: cuatro esperas de permisos MCP tenían un tope de 5 s de reloj de pared. Si el proceso
  quedaba parado más que eso, la espera fallaba antes de que llegara el rechazo automático. Ahora
  usan el tope común de 30 s. La app no cambia.
- **En el modo clásico, el turno nuevo espera al que cortaste (2026-10-01).** Si cortabas a
  Companion mientras usaba una herramienta lenta y hablabas de nuevo, tu turno nuevo arrancaba antes
  de que el viejo terminara: no sabía que lo habías interrumpido y el chat quedaba en desorden.
  Ahora espera hasta 2 s a que el turno cortado se detenga. Si una herramienta no lo deja, arranca
  igual y lo que el viejo diga tarde se descarta. Un turno que cortas antes de que tus palabras
  lleguen al modelo ya no deja rastro.
- **Los tests encuentran los textos aunque se compile en otra carpeta (2026-09-30).** Con
  `swift test --scratch-path` (el que usan los builds aislados y TSan) unos 555 tests veían
  claves como `island.hands.stop` en vez del texto, porque los recursos solo se buscaban en el
  `.build` por defecto. Ahora se buscan junto al bundle de tests cargado, y ya no queda ningún
  camino que evalúe `Bundle.module`, el único que podía cerrar la app si faltaba un bundle.
- **Si se corta la red mientras Companion habla, no pierdes lo que dijo (2026-09-30).**
  Lo que alcanzó a decir queda en el chat cuando termina de sonar, la voz vuelve a escucharte en
  vez de quedarse "hablando", y si dices "sigue" continúa donde se quedó sin repetir. Al
  reconectar nunca habla sola.
- **Instalar desde main ya no falla el smoke de empaquetado (2026-09-30).** Las 5 fuentes
  propietarias que solo viven en este Mac (ignoradas por git) hacían que `bundle.sh` rechazara la
  carpeta `Fonts`. Ahora una lista explícita las admite si están presentes; cualquier otro archivo
  ajeno sigue siendo un stray.
- **La isla avisa cuando la red corta a Companion a media respuesta (2026-09-30).** Ves
  "Se cortó la conexión a media respuesta" y cómo seguir. El aviso se va solo, no tapa un error
  ni un permiso pendiente, y no aparece si la voz está apagada o si ya hablaste encima.
- **Un aviso y tu siguiente turno ya no se pisan en el modo clásico (2026-09-30).** Si
  hablabas mientras Companion leía un aviso, o cortabas un turno y empezabas otro, los dos
  compartían el estado del turno: una tarjeta o una acción de uno podía colarse en la respuesta
  del otro. Ahora cada turno lleva su propio estado.
- **La voz sigue escuchando después de un corte de red (2026-09-30, #59).** Al reconectar,
  nadie leía la conexión nueva y la voz quedaba sorda; además arrancaba sin instrucciones, tools
  ni voz elegida, y volvía a encender el micrófono aunque lo hubieras silenciado. Ahora reanuda
  con su configuración y tu mute. Colgar durante una reconexión ya no revive la sesión, y un
  servidor que corta en bucle se rinde tras 3 reconexiones por minuto.
- **El puente con otros agentes no se queda "ocupado" para siempre (2026-09-30, #57).** Un
  cliente que cerraba al instante podía dejar el puente tomado hasta reiniciar la app.
- **Un texto sin traducir muestra el inglés, no la clave interna (2026-09-30, #58).** Antes una
  sola clave faltante en español pintaba algo como `chat.job.done` en pantalla.
- **La app instalada ya no depende de la carpeta de compilación (2026-09-30, #52, #54, #56).**
  Fuentes, mascota, skills y diagramas se buscaban primero junto al build de desarrollo; sin él,
  la app podía cerrarse al abrir. La extensión del navegador se empaqueta desde una lista fija de
  archivos, así un archivo ajeno no se cuela en la app.
- **Tu voz se ve en la isla mientras hablas (2026-09-25).** En el modo clásico la isla leía el oído
  de OpenAI, que ahí no recibe audio; ahora lee el oído que escucha.
- **Las respuestas se leen con formato (2026-09-25).** Negrita, cursiva y enlaces en párrafos y
  viñetas en vez de asteriscos; solo los enlaces web se abren.

### Changed
- **El gate de capas ya no depende de cómo se llame un target de soporte (2026-10-01).** Todo
  target bajo `Tests/` que no sea de test cuenta como soporte, se llame como se llame y aunque la
  ruta se escriba distinto (`./Tests/x`, `tests/x`); un target de producción tampoco puede
  depender de un target de test, y si un target de la tabla de capas desaparece del manifest el
  gate falla en vez de saltarse sus chequeos.
- **La voz también vive en el target de su capa (2026-10-01).** Los tests de voz pasan a Services
  e integración y el target de transición `CompanionTests` desaparece; los imports de soporte son
  explícitos en todos los archivos.
- **Decidido como un agente prueba a Companion sin tocarse a si misma (2026-10-01).** Cinco
  briefs de research: el puente puede mirar y consultar el estado de Companion pero no pulsarla,
  solo con metadatos; cada aprobacion critica pedira Touch ID; un pedido de cambiar un ajuste
  traera ese control a la isla; y la velocidad de voz sera por conversacion. Todavia no cambia la app.
  La spec de la velocidad ya esta firmada: "habla mas rapido" vale hasta colgar, tambien entre
  pulsaciones de FN, y nunca se guarda en Ajustes.
- **CI corre ThreadSanitizer sobre toda la suite (2026-09-30).** Un job `tsan` aparte busca
  carreras de datos en cada PR; fue la única herramienta que destapó las del puente y del modo
  clásico. Por ahora es informativo: un aviso lo pone en rojo sin bloquear el merge, y pasa a
  requerido tras 5 corridas limpias seguidas. En local se corre igual con `scripts/tsan.sh`.
  Para que arranque en verde se arreglaron dos carreras que solo existían en los tests (el
  contador de SIGPIPE y el motor falso del transcriptor); la app no cambia.
- **Los tests se dividen en un target por capa (2026-09-30).** Core, Services, UI e integración
  tienen su propio target y un gate impide que uno importe la capa que no le toca; la voz sigue
  en `CompanionTests` y se mueve en el paso siguiente.
- **Los gates de capas cubren más (2026-09-30).** Tienen casos negativos para cada dependencia
  prohibida entre targets de test, y rechazan que código de test aparezca en un producto del paquete.
- **Código ordenado por dominio y API interna de paquete (2026-09-30, #50, #51).** Las carpetas
  siguen el dominio de cada pieza y las librerías ya no exponen nada `public`; un gate lo impide.
- **La suite de tests dejó de fallar al azar (2026-09-30, #53).** Carreras en los dobles de test,
  esperas con reloj real y un hook global compartido hacían fallar 3 o 4 de cada 10 corridas;
  ahora pasan 10 de 10.
- **Specs aprobadas de los siguientes pasos (2026-09-30, #55):** tests por módulo, catálogo
  único de textos y división de VoiceSession, cada una con su research verificado.

### Added
- **Documentos, hojas y gráficas (Wave 20, 2026-09-28).** "Hazme un PDF del
  informe" termina en un PDF de verdad, con tablas y gráficas, sin instalar
  nada; lo mismo en `.xlsx`. Companion lee y escribe en el Excel o el Numbers
  que tienes abierto, con tu aprobación, una copia del libro antes y la
  relectura de lo escrito después; rechaza fórmulas que llaman a la red o
  ejecutan algo, también disfrazadas con `+`, `-` o `@`. Las cifras, tablas
  y series llegan al chat como tarjetas con gráfica.
- **Conectores como Incredible (Wave 16k-2, 2026-09-28).** Tocar una app abre
  su panel: descripción y Conectar sin cuenta; con cuenta, las acciones en
  Leer / Crear y cambiar / Borrar según lo que el servidor declara, con
  buscador y la descripción remota visualmente distinta del copy propio.
  Conectar abre el modal con los dos iconos y el punto que viaja, consulta
  cada 3 s (40 intentos, tope duro 2.5 min — números auditados del binario
  de Incredible) y termina en "Vamos"; Reintentar pide enlace fresco. La
  página pone "Tus apps" arriba sin repetirlas en el catálogo, y Desconectar
  confirma avisando que el grant del lado de la app no se revoca solo. Cada
  intento y el panel llevan su epoch: dobles taps y respuestas tardías ya no
  pisan al intento vivo ni duplican DELETEs.
- **Las manos para Claude Code (Wave 17, 2026-09-28).** Nuevo ajuste en
  Privacidad, "Prestar las manos a otros agentes" — apagado por defecto en
  todo build. Encendido, la primera acción de una sesión del puente abre la
  misma hoja de aprobación de siempre ("quiere usar tus manos"); aprobada, la
  isla muestra el chip "Manos: Claude Code" y parpadea con cada acción de
  escritura, y "Detener manos" (en el chip y en el menú de la barra) cierra
  la sesión en un gesto. Presupuesto de 30 acciones de escritura por minuto;
  un turno propio de Karen pausa el puente y lo retoma al terminar. El shim
  que Claude Code arranca vive en el repo hermano `companion-mcp`, no aquí.
- **Página Apps (Wave 16k-1, 2026-09-25).** Personalizar › Apps como en Incredible: buscador,
  destacadas con el total, rejilla de dos columnas y "Mostrar más". "+ Conectar" abre la conexión
  de Pipedream en el navegador. La primera vez pide la dirección y la clave de tu función
  `companion-apps`; la clave queda en el llavero y nunca sigue una redirección a otro sitio.
- **La ventana como la de Incredible (Wave 16j-1/2, 2026-09-25).** Barra lateral, Inicio con la
  tarjeta "Mantén fn", primeros pasos y las tareas por día; cada tarea abre su conversación y
  "Seguir" la pasa a la isla con la etiqueta TAREA. Sin chat en la ventana ni líneas internas. La ventana es horizontal 16:10 (1120×700) como la de
  Incredible, en vez de la columna 2:3 del chat.
- **La isla más útil, primera parte (Wave 16i-1, 2026-09-25).** El panel ya no se ve abierto y
  vacío: el contenido entra con el panel y se va con él. Al pasar el ratón la muesca se asoma con
  rebote y sombra como NotchNook, y solo abre si el puntero se queda 150 ms. El menú "…" y el nuevo
  volumen de la voz son popovers propios, oscuros, que crecen desde su botón; tooltips en hablar,
  enviar y volumen. Mientras habla, el orb es el botón rojo de parar, y al parar sale "Cancelado".
  "No te oí" y los avisos con salida son tarjetas con icono, anillo de cuenta atrás y botón.
- **Movimiento suave en toda la app (Wave 16f-2, 2026-09-25).** Ocho reglas de smooth motion
  (spec 16f §9) con test: una sola curva de entrada, resortes casi sin rebote, cerrar más rápido
  que abrir, desenfoques y desplazamientos chicos, escalonado de 40 ms y reducir movimiento como
  fundido corto. En la isla, la línea de estado cambia con un deslizamiento suave, las palabras se
  aclaran una a una, las tarjetas entran escalonadas, la luz de "hecho" aparece con un rebote leve y
  la hoja de aprobación sube. Ninguna vista puede escribir su propia curva.
- **La isla nace del notch (Wave 16f, 2026-09-25).** En reposo es la muesca; al pasar el ratón se
  estira en dos tiempos (píldora y panel) con los resortes medidos en la grabación de Incredible, y
  el contenido entra después con fundido y desenfoque; al cerrar, al revés. La ventana ya no se
  mueve: crece la forma. Los clics pasan a la app de atrás fuera de la forma. La respuesta se lee en
  grande y sus palabras se aclaran al ritmo de la voz; tres huecos de tareas arriba a la derecha.
- **Ajustes con la forma de Incredible (Wave 16g, 2026-09-25).** Hoja con barra lateral y buscador
  (sin acentos, es/en, salta a la fila y la ilumina); siete páginas: General, Voz, Vocabulario,
  Memoria, Tú, Privacidad, Sistema; tarjetas blancas de filas con el control al final. Vocabulario
  como lista con ejemplo y "Añadir palabra". Memoria nueva: ves lo que Companion guardó y olvidas lo
  que quieras. Sistema con zona de peligro. Siguen 14 opciones. Seguridad: la memoria ya no lee
  enlaces simbólicos (ni archivos ni carpetas), que podían meter cualquier archivo tuyo en el prompt.
- **UX como Incredible (Wave 16c–16e, 2026-09-25).** La isla es la app: al pasar el ratón,
  campo "Pídele algo a Companion…", adjuntar, enviar, menú de 5 y tus últimas respuestas como
  tarjetas; luz ámbar cuando te necesita y verde al terminar; al escuchar solo barras y lo que va
  oyendo; "no te oí" se va a los 6 s; los errores traen su salida. Bienvenida de 7 pantallas con
  los 4 permisos en una, medidor de micro y un hold real al final. Ajustes en 3 pestañas con 14
  opciones y sin jerga; palabras que el oído debe entender bien; menús en tu idioma; icono en la
  barra de menús. Geist como tipografía. Permitir en una hoja ya no responde a Return.
- **Vista y click como Incredible (Wave 16a, 2026-09-25).** `look` lee la ventana de delante como
  una lista numerada de sus controles y texto; `click` pulsa por número (acción del elemento, foco
  o click de ratón enviado a esa app, sin mover tu puntero); `scroll`, `menu` ("Archivo > Exportar
  como PDF…") y `see` (captura descrita, solo cuando se pregunta por algo visual). Las apps Electron
  y Chromium se preparan al pasar al frente para que muestren su contenido. Pulsar "Permitir" o
  "Aceptar" va directo; borrar, pagar, suscribir, enviar o publicar piden confirmación salvo que lo
  pidieras con esa palabra; un icono sin nombre o el "Sí" de un diálogo de borrar también la piden.
  La visión ya no corre en cada turno (ahorra 3,3–3,7 s). El asistente puede encadenar hasta 8
  acciones por turno.
- **El especialista ya no pide permisos (Wave 16b).** Claude Code corre en modo `auto` con una lista
  de prohibidos (sudo, git push, borrar el disco o tu carpeta, curl/wget a una shell, AppleScript);
  lo que aún pregunte se niega solo, sin hoja.
- **Manos sobre la pantalla (Wave 15g, 2026-09-25).** El asistente escribe,
  pulsa una tecla, trae una ventana al frente y lee el campo enfocado de la
  app que tenías delante (`type_text`, `press_key`, `focus_window`,
  `read_focused`), por Accesibilidad y sin subagente ni AppleScript. Se
  ofrecen solo con Accesibilidad concedida y nunca con Companion delante.
  Lo que escribe o envía se ata a lo que dijiste: en terminales y apps de
  agentes, Return siempre pide confirmación y solo se escribe sin preguntar
  una línea que dijiste; en el resto, Return va directo si pediste enviar y
  una dirección que no dijiste pide confirmación. Actúa sobre la app que
  tenías delante al hablar (salvo que en el turno pidas abrir otra). El
  prompt dice actuar en vez de instruir, y la visión ya no bloquea cada
  turno: si llega tarde viaja al siguiente, solo en la misma app y 30 s.
- **Boca sin huecos, con voz de verdad, y sin leer JSON (Wave 15f, 2026-09-25).**
  ElevenLabs (Flash v2.5, voz Ana María, elegida a ciegas entre 6 candidatas)
  como boca del hold cuando hay clave: primer byte en 180–210 ms frente a
  500–700 de OpenAI; OpenAI (alloy, `speed 1.1`, `instructions`) de respaldo,
  con cortacircuito de 60 s si ElevenLabs falla y pausa hasta clave nueva en
  401. La frase N+1 se pide mientras suena la N (una en vuelo por delante).
  Un `{"goal":…}` escrito como texto por el modelo ya no se pronuncia: si es
  eco de la pantalla o del portapapeles se descarta; si no, se propone
  ("¿Lo delego?") y solo corre con tu sí. Una frase de razonamiento en otro
  idioma se descarta; las citas, errores y traducciones se respetan. El
  encargo al especialista se anuncia con una frase fija y un resumen de dos
  frases, nunca con el prompt literal. Ajustes: fila ElevenLabs en Claves y
  selector de voz con 6 presets, id libre y muestra. Timeline: `firstCut→
  ttsRequest`, `ttsRequest→firstByte`, `firstByte→audible`. Cerebro: se
  queda Cerebras gpt-oss-120b (banco: 299 ms TTFT, cero fugas con frases
  sueltas). Medido en vivo: soltar→audio 1,0–1,2 s en turnos sin tool.

### Security
- **Campos de contraseña de verdad detectados (15g).** El dictado (12e), la
  lectura de pantalla y las manos comparaban el rol con `AXSecureTextField`,
  que es un subrol: un `NSSecureTextField` real nunca se reconocía. Ahora se
  miran rol y subrol en un solo sitio.
- **El portapapeles de un gestor de contraseñas no entra al contexto (15g).**
  Contenido marcado `org.nspasteboard.ConcealedType` o `TransientType` se salta.
- **La red ya no deja claves en disco (15f).** `URLSession` guardaba en
  `~/Library/Caches/<bundle>/Cache.db` las peticiones a OpenAI, Cerebras, Groq
  y ElevenLabs con sus cabeceras de autorización y cuerpos (conversación,
  texto de pantalla y portapapeles). Todos los caminos de red usan ahora una
  sesión sin cache ni cookies; el cache viejo se purga al arrancar y un gate
  estático impide que vuelva. Hay que rotar las claves que estuvieron ahí.
- El log de depuración de transcripts redacta también claves `sk_`; el id de
  voz de ElevenLabs se valida antes de tocar la red o el Keychain.

### Added
- **Oye la frase entera y sin Groq (Waves 15d y 15e, 2026-09-24).** El
  micrófono abre al bajar FN (antes esperaba 250 ms de umbral + 200 ms de
  arranque: media frase perdida) y deja una cola de 300 ms al soltar; un
  tap descarta el audio en memoria sin que nada salga de la máquina. El
  oído es `SpeechAnalyzer` de Apple en el dispositivo (final a 23–39 ms
  tras la cola; spike: 54 ms p50 frente a 430 ms de WhisperKit y 500–750 ms
  de Groq), con tu nombre y tus apps como vocabulario. Groq desaparece:
  ni oído, ni cerebro, ni fila en Ajustes; una clave guardada antes se
  purga sola del Keychain. Cerebro del hold: Cerebras gpt-oss-120b, y si
  falla OpenAI gpt-4o-mini. Un hold sin voz vuelve a reposo con el
  micrófono apagado. Instrucción de idioma delante del transcript, prompt
  de voz al estilo "router con voz" (dos frases, sin markdown), primer
  corte de la boca a la coma / 40 caracteres / 400 ms. Modo depuración
  opt-in `COMPANION_DEBUG_TRANSCRIPTS=1`: `heard=`/`said=` en
  `~/Library/Logs/Companion-transcripts.log` (0600, claves redactadas,
  borrado al arrancar sin la variable) con aviso en la barra de estado y
  la island. Plataforma mínima: macOS 26. Medido en vivo (22 holds):
  `release→earFinal` p50 360 ms; `release→audio` p50 1,65 s — el tramo que
  queda es la boca (TTS 730 ms p50), siguiente wave.

### Added
- **Dicta en el campo donde está tu cursor (Wave 12e).** La misma tecla,
  otro destino: con un campo de texto de otra app enfocado (Slack, Notas,
  Safari), mantener FN y soltar pega ahí lo que dijiste; la island dice
  "Dictando en Slack" con el parcial y luego "Pegado en Slack"; nada
  viaja a la conversación ni al log (solo cuántos caracteres y dónde).
  Sin campo, con una contraseña, con Companion delante o sin el permiso
  de Accesibilidad, el hold habla con Companion como siempre. Ajustes ›
  App › HABLAR gana "Al mantener FN": Automático (por defecto), Hablar
  con Companion, Dictar; cuando puede dictar y falta Accesibilidad, la
  fila del permiso aparece ahí mismo. El texto entra por Accesibilidad
  (texto seleccionado del elemento enfocado) y, si la app lo ignora, por
  el portapapeles con un Cmd+V, devolviendo después lo que había en el
  portapapeles, de todos los tipos y solo si nadie más lo tocó mientras
  tanto. Nunca en un campo seguro, nunca en una app distinta de la que
  estaba delante al pulsar. Preguntar por el campo no retrasa el
  micrófono: va en su propia tarea, con tope de 0,25 s por llamada.
- **La island ya no enseña una tecla muerta (12e).** Sin el permiso de
  Monitoreo de entrada, pasar el ratón dice "FN está apagada. Clic para
  permitirla" en vez de "Mantén FN para hablar"; el clic abre la ventana.
- **El oído deja de escribir lo que oye en el log (12e).** Las líneas
  `ear: hearing` y `ear: segment` cuentan caracteres, nunca palabras.
  Cierra la deuda abierta por la revisión de seguridad de 12b.
- **Mantén FN y habla (Wave 12b).** El micrófono ya no es un toggle dentro
  de la ventana: con Companion detrás, mantener FN abre la sesión y el
  micro, soltar envía lo que el oído nativo oyó (ForceEndpoint), un tap
  enseña el hold, mantener mientras Companion habla la calla. La tecla se
  oye con un event tap listen-only sobre `flagsChanged` (solo FN, nunca
  lo que escribes) que exige el permiso de Monitoreo de entrada, con su
  fila en Ajustes › App › HABLAR. La **island**: un `NSPanel` que no se
  activa, encima de todas las apps y en todos los Spaces, bajo la banda
  del notch: pebble en reposo (ocultable), nudge con "Mantén FN para
  hablar" al pasar el ratón, medidor en Listening, fase en Processing,
  fila del encargo con Stop, y la hoja de permiso hospedada ahí mismo.
  Cerrar la ventana principal ya no cierra la app; el Dock y el pebble la
  traen de vuelta. `Cmd+Opt+Space` sigue como manos libres.
- **Los contratos del HUD, ejecutables (Wave 12d).** Nada cambia en
  pantalla. Las puertas del auditor de la spec de producto (hold sin abrir
  main, la island solo escucha, cuatro kinds, Stop es Idle y los hijos
  mueren, las cards no son la conversación, el encargo tiene fila, sin
  cuerpo de skill en el historial, sin actor de permisos se deniega, una
  hoja tiene un solo anfitrión) viven en `conformance/hud-gates.json`: cada
  puerta cita los tests que la prueban y `hudGatesTests` falla si cita uno
  que ya no existe o que nadie llama, o si el libro pierde una puerta. La
  regla `session-kind-write` cubre los once campos de la proyección (y
  `+=`, subíndice, `insert`) y la nueva `main-activation` impide que la
  UI active la app por cualquiera de sus formas (`activate(options:)`,
  `makeKey()`, `orderFront(` incluidas). La denegación del padre es un
  `ContractError` (`denied_by_user`) con el mismo texto de siempre para
  el modelo, fijado como string literal en las pruebas.
- **Ver lo que oye (Wave 12c).** Mientras mantienes FN la island muestra
  el texto que el oído va reconociendo, y lo conserva en "Enviando…"
  hasta que Companion empieza a pensar. El oído arranca al pulsar, en
  paralelo con el socket: la primera palabra de un hold ya no se pierde
  en el handshake. Un hold es un solo turno: una pausa dentro del hold ya
  no envía (al soltar viaja lo que el oído lleva oído desde la
  pulsación: la tecla es dueña del turno y el VAD del servidor no cierra
  ni abre turnos mientras dura la sesión del hold). Cada hold deja en el
  log una línea `voice timeline:` con
  press→mic, press→ear, press→ready, press→partial, release→commit y
  commit→audio en milisegundos, y el arranque una línea `prewarm:` con lo
  que se preparó antes del primer hold (motor del micro si ya tiene
  permiso, red; nunca el llavero ni un permiso). La pista "Mantén FN para hablar" del hover se
  enseña hasta el primer hold completado; un tap la pide siempre.
- **Revisiones de la 12b (2026-09-06).** Seguridad: una sesión abierta
  por un hold que reposa con el micro cerrado cuelga sola a los 20 s (el
  micro físico seguía tomado con la ventana cerrada); el pebble no se
  oculta mientras la voz vive; la hoja de la island ignora el clic que ya
  iba en camino (0,6 s). Código: una pulsación durante una suelta manda
  (la suelta tardía se descarta); re-pulsar mientras conecta ya no deja
  el micro cerrado; la hoja tiene un solo anfitrión (main si es key, si
  no la island); el tap de FN guarda puerto y run loop bajo un lock y se
  para al salir.
- **El reductor de sesión (Wave 12a).** Un estado para toda la sesión, no
  tres: `SessionMachine` en Core (kinds Idle / Hover / Listening /
  Processing con fases Pending, Thinking, Speaking, ToolExecuting,
  SubAgentRunning, Completed) observa la máquina de voz y suma lo que ésta
  no ve: el turno tecleado, las manos del padre, el encargo del especialista
  y la cola de la hoja. `SessionModel` (UI) es el único que muta la
  proyección y ejecuta los efectos (`cancelJob`, `resolveApproval`, el timer
  de Completed, el log `session: a -> b`). `VoiceSession.events` es un solo
  stream hacia fuera donde había seis closures. Cancelar y fallar vuelven a
  Idle con un `InterruptReason`; un micrófono denegado ya no deja la voz en
  un modo "error": es una card con enlace a Ajustes. Regla de conformidad
  `session-kind-write`: ninguna vista escribe el kind.
- **Skills y knowledge (Wave 11a).** Companion es un cliente Agent Skills
  (agentskills.io): `~/Library/Application Support/Companion/skills/default/`
  lleva doce skills del sistema (texto propio, sembradas desde el bundle en
  cada arranque), `skills/custom/` las de la usuaria y `knowledge/` un
  hecho por carpeta. El prompt del padre y el encargo del especialista llevan
  el catálogo `<active_skills>` / `<active_knowledge>` (nombre — descripción
  — ruta, datos con topes); el cuerpo se lee bajo demanda: `read_skill` en
  la conversación, `read_file` en el encargo. `default/` es solo lectura para
  el modelo (`denied_path`); escribir en `custom/` o `knowledge/` pasa por la
  aprobación de siempre y el resultado termina con `Skill sync: saved |
  failed — por qué | already up to date`. La memoria apunta a la skill
  knowledge-builder; `notes/` sigue leyéndose. Las cuatro skills que
  dependen de capacidades que no existen (scheduling, browser-use,
  excel-live, premium-documents) dicen lo que Companion sí puede y cierran
  con "What Companion cannot do yet".

### Changed
- Los gates comprueban el build de release y que los tests respeten las capas (2026-09-30).
- Los fakes y helpers compartidos de los tests viven en cuatro targets de soporte, uno por capa (2026-09-30).
- `JobTimeline` vive en Core (la proyección lo lleva). `ChatViewModel.job` y
  `pendingApproval` son lecturas de `session.projection`; `approvalQueue` y
  `jobHasApprovedAction` desaparecen. Negar el primer paso o pulsar Stop
  niega también las peticiones que quedaban en cola, en vez de dejarlas al
  auto-deny de 120 s.

### Fixed
- **El "sí" hablado podía conceder otra petición.** La voz resolvía su
  propio "pendiente" (un slot que se sobreescribía) mientras la hoja
  mostraba otra petición; y aprobar un `open_url` del padre desarmaba la
  regla "negar el primer paso para el encargo" (security review
  2026-09-06). Ahora la voz manda `approvalSpoken` al reductor, que
  contesta lo que la hoja muestra con las reglas de la hoja, y solo las
  peticiones del especialista cuentan como acciones del encargo.
- **Un turno tecleado abandonado dejaba el chrome pegado.** Cambiar de
  conversación o de clave con una respuesta en vuelo no cerraba el turno en
  la sesión (code review 2026-09-06).
- **La memoria no llegaba al chat tecleado.** `makeRequest` la recibía y no
  la reenviaba a `makeBody`: solo la voz realtime la veía. Medido al cablear
  el catálogo por el mismo hueco; test de regresión en
  `ChatProviderClientTests`.
- **Nada se pierde (Wave 10c).** Dos tool calls en una respuesta se fundían
  en `"read_filewrite_file"`; ahora se cosen por `index` (spec 07) y viajan
  juntas en `ChatDelta.toolCalls`: un `assistant` con todas, un `tool` por
  cada una, deduplicadas. Los argumentos rotos se evitan con `strict: true`
  en OpenAI y se reparan (lista de json_repair) para el resto; lo
  irreparable devuelve `invalid_args` con lo que el modelo mandó, nunca
  `[:]`. Los permisos esperan en una continuation (sin polling), la hoja
  tiene "Recordar durante esta sesión" (clave `Tool(patrón *)`, deny gana,
  muere con el proceso) y negar devuelve `denied_by_user`, una instrucción
  que el modelo no reintenta. `open_url` pide permiso por la misma hoja
  cuando la URL no salió de las palabras de la usuaria (3D).
- **El turno lleva contexto y fuente (Wave 10a).** El modelo recibía el
  string crudo y nada más: "resume esto" no tenía *esto*. Ahora cada turno
  viaja con un bloque `<context>` — fuente (voz/tecleado), hora, app enfrente,
  documentos abiertos y, solo si se enciende, portapapeles — enmarcado como
  DATOS, nunca instrucciones, escapado, con topes visibles, y **solo en el
  turno actual**: el historial y la memoria guardan una línea compacta
  (`[voz · Safari · 2 docs]`); el disco no guarda nada de lo sensado. Los
  sensores corren bajo un presupuesto de 150 ms y nunca retrasan el turno:
  lo que no llegó, no viaja. Accesibilidad es el único permiso nuevo, se
  muestra en Ajustes › Contexto como una fila con "Abrir Ajustes del
  Sistema" (nunca un diálogo sorpresa), y sin ella el producto es el de hoy
  más el nombre de la app enfrente. La negativa del mic también gana botón.
  Se borran `Escalation.voicePreamble` / `voiceTurnPrompt` (cero llamadores
  desde Wave 8): la pista "máximo 2 frases, sin markdown" viaja ahora en
  `<how_to_reply>` de cada turno de voz.
  Revisiones (2026-09-05): la nota de sesión lee `memoryTurns()` (palabras, sin la línea compacta ni la app al frente); los topes cuentan lo escapado y el bloque entero degrada hasta caber; los documentos se leen de la última app que no es Companion (`lastOtherPID`); el prompt dice que lo que hay en `<context>` nunca abre una URL, archivo o app por sí solo.
- **El padre actúa (Wave 10b).** El turno conversacional tenía una sola tool,
  `delegate`, así que "abre Safari" era un encargo: cola, especialista, hasta
  diez rondas de modelo, `run_shell` y una hoja de permiso para algo que la
  usuaria acababa de pedir en voz alta. Ahora el padre tiene manos propias
  — `open_app`, `open_url`, `open_file`, `list_apps` (y `find_places`, que
  ya no necesitaba disco) — sin permiso, sin subproceso: todo por
  `NSWorkspace` detrás de un puerto. Los validadores vienen de Relay con las
  dos correcciones de su review (home canonicalizado, symlink a oculto), y
  el error viaja como contrato: `denied_path: …` para que el modelo pida otra
  ruta en vez de rodearla. Chat y voz clásica hacen un loop de hasta tres
  rondas; en realtime el server ya lo hace y el cliente responde en línea.
  Cada acción deja su línea en el hilo y su `Recall` de tool en la memoria,
  como el encargo deja el suyo. El prompt deja de decir "nunca digas que no
  puedes ver el disco — delega".
- **Voz híbrida (Wave 9i): el oído transcribe, el modelo lee y habla.** El mic
  ya no llega al modelo conversacional: `gpt-live-transcribe` (sesión realtime
  de solo transcripción, con buffer de arranque para no perder ni el primer
  fonema) produce el texto, y ese texto — fiel — arma el turno. Apple es-MX
  queda como oído del pipeline clásico. Los turnos los deciden las palabras
  (el transcript crece/se asienta), no el volumen; el barge-in sigue siendo
  local y vetado. Medido en uso real: "crea un archivo de prueba en mi
  escritorio" termina en archivo real, y los turnos siguientes continúan el
  encargo.
- **El especialista alcanza toda la cuenta.** El default de alcance de 9h se
  revocó por decisión de la dueña: sin carpeta elegida, el workdir es el home
  — como el CLI. Los edits pasan solos; los comandos siguen pidiendo permiso.

### Changed
- **Un solo dueño del ciclo de respuesta realtime.** Cinco call sites de
  `response.create` corrían a ciegas contra un server que sostiene UNA
  respuesta; un turno commiteado a media respuesta era rechazado y quedaba
  huérfano. Ahora hay un embudo con prioridad: el turno del usuario preempta,
  tools y anuncios esperan.
- **El especialista actúa en vez de interrogar.** Su rol exige completar con
  defaults razonables y anotar la decisión — cada encargo moría en una
  pregunta aclaratoria que el bucle de voz no sostiene.
- **La voz no canta victoria por un rechazo.** El acuse de encargo se remite a
  lo que el especialista respondió; la orden incondicional de "di que terminó"
  convertía un "no pude" en un "listo".
- **Companion arranca sin clave.** Chat, encargos y voz por turnos funcionan
  con lo que ya corre en la Mac. La escalera de proveedores ya degradaba sola;
  el muro estaba en tres lineas del arranque y en un tag de Ollama escrito a
  mano que casi ninguna Mac tiene instalado — el probe decia que si y el primer
  mensaje moria en un 404. Ahora el modelo local se resuelve leyendo lo que hay
  (Wave 9b).
- **`list_directory`.** El especialista podia leer un archivo si sabia la ruta
  y no podia mirar alrededor sin pedir permiso por comando. Pidio "busca una
  carpeta en el escritorio" y contesto que no existia una carpeta que estaba
  ahi: no le faltaba inteligencia, le faltaban ojos.
- **`find_places` sobre MapKit**, y las tarjetas nacidas de una consulta viajan
  por su propio canal: el modelo lee nombres y direcciones, nunca coordenadas,
  asi que no puede reescribirlas mal. Las que escribe el modelo en un fence
  siguen pintandose y **dicen que Companion no las verifico**.
- **`web_search` de verdad** (Brave), como clave secundaria. Era un munon que
  siempre fallaba y aun asi se anunciaba: capturaba la intencion y se moria.
- **Parar un encargo**, con boton y por voz. `JobRunner.cancel()` existia desde
  la Wave 4 sin un solo llamador.
- **Reintento en limite de tasa** antes de bajar de peldano.

### Changed
- **Lo que se ve deja de ser lo que se recuerda.** El informe completo del
  especialista entraba en el historial como algo que el modelo de charla habia
  dicho: se comia el contexto, le ensenaba a escribir informes contra su propio
  prompt, y le dejaba releer un resultado que nunca produjo. Medido en una
  sesion real, un solo informe era el 23% del historial. Ahora vuelve como
  resultado de tool, acotado, y atado a la llamada que lo pidio (Wave 9d).
- **El trabajo va al carril que tiene herramientas**, no al que dice el
  desplegable. El prototipo ya lo hacia; el rebuild corria el encargo en lo
  seleccionado, y el default era el mas debil.
- **Pedir otra cosa mientras trabaja encola**, no cancela. La primera version
  rechazaba y salio peor: el mensaje de rechazo ofrecia "dime para", el modelo
  lo leyo como instruccion y mato el encargo vivo. Copy que llega a un modelo
  no es copy, es prompt.
- **Negar el primer paso para el encargo entero.** Negar uno posterior solo
  acota: para entonces va donde tu lo mandaste.
- **La carpeta personal deja de ser el alcance por defecto.** Se repartia el
  home entero desde el primer arranque sin preguntar. Elegirlo sigue siendo
  posible y **no se recuerda entre sesiones**, que es donde la referencia
  tambien traza la linea.
- **El historial se comprime en vez de truncarse.** Lo que salia de la ventana
  desaparecia sin rastro.
- **Una tool que no puede correr no se le ensena al modelo**, y el prompt dejo
  de prometer busqueda web sin condicion.

### Fixed
- **"No hay conexion a internet" con la red perfecta.** `noProvider` — la
  escalera agotada — se contaba como red caida, y mandaba a arreglar lo que no
  estaba roto. Mismo defecto que un 429 leyendose como "no hay proveedor".
- **Un fallo salia dos veces con dos redacciones**, una desde Services con
  texto cableado y otra desde el catalogo. Un solo dueno, y es el del catalogo.
- **El especialista perdia el disco al caer a batch.** El respaldo corria sin
  una sola bandera de permisos: sin manos y con boca, contestaba "no encontre
  nada" a preguntas que si tenian respuesta.
- **`temperature` iba cableada** y los modelos de razonamiento la rechazan con
  400. Latente hoy, garantizado en cuanto el panel deje elegir modelo.
- **El llavero prometia lo que no cumplia:** `kSecAttrAccessible` no aplica al
  llavero de archivo, que es el que usamos. Se quitaron los atributos muertos y
  el comentario dice lo que de verdad pasa.
- **Una lectura del llavero por proveedor y por turno** eran hasta cinco
  dialogos de contrasena por mensaje. Ahora una por clave.
- **El registro de un encargo no decia nada si lo corrio el ejecutor nativo:**
  solo conocia los nombres de herramienta de Claude Code.
- **La app anunciaba que "el especialista llega en una proxima version"**
  mientras el especialista trabajaba: copy vieja reutilizada sin leerla.
- **Salida de shell mayor que un pipe (~64 KB)** se reportaba como timeout: se
  leia despues de esperar, asi que el hijo se bloqueaba escribiendo.
- **Los subprocesos morian sin su descendencia**, y ninguno moria al cerrar la
  app. Ahora cada uno vive en su propio grupo, con escalada a SIGKILL.
- **La suite era intermitente** y nadie lo habia medido: `pumpUntil` esperaba
  2 s ocupando el main actor, con todos los tests en el main actor.

### Changed
- **El encargo es UI asistiva: no habla por su cuenta.** Decision de producto.
  El resultado vuelve una sola vez — el texto del especialista es el mensaje
  del hilo, con su codigo, sus rutas y sus cards, y la voz solo acusa que
  termino en vez de releerlo. Antes eran dos mensajes por un resultado, y el
  que sonaba era una parafrasis del que estaba escrito. Es la forma en que
  OpenAI cierra una tool — vuelve como salida, no como un segundo mensaje —
  aplicada hasta donde no cuesta producto: copiarla del todo habria borrado
  del hilo el texto integro del especialista, y con el las cards.
- **El permiso del especialista deja de preguntarse en voz alta.** Vive en la
  hoja. `resolve_approval` sigue declarada, asi que quien la ve y dice "si,
  autorizalo" resuelve sin tocar el trackpad; lo que se pierde, y es el precio
  elegido, es que un permiso que nadie mira muere en el auto-deny de los 120 s
  sin que la voz lo mencione. Revierte la parte hablada de la Wave 8.

### Fixed
- **La tool de permiso ya no se condiciona a un anuncio que no ocurre.** Al
  callar el anuncio, `resolve_approval` seguia diciendole al modelo que la
  usara "solo despues de que el sistema anuncie": se le prohibia la unica via
  que quedaba para aprobar hablando.
- **La voz ya no intentaba leer una card.** Un encargo que devolvia un mapa o
  una galeria hacia que el modelo recibiera «```companion:locations» como
  texto a narrar.
- **Un encargo que falla dice por que.** Los dos ejecutores de CLI devolvian
  una salida vacia cuando el proceso no arrancaba o terminaba sin reportar, y
  una salida vacia dejaba a la voz sin motivo: rellenaba el hueco diciendo que
  el encargo "fallo o se quedo sin tiempo", un reloj que nunca corrio. Misma
  familia que el bug que la Wave 8 creyo cerrar.
- **Un permiso negado se reporta como permiso.** Negar el reconocimiento de
  voz mandaba al usuario a "revisar el TTS": el lugar equivocado para un
  permiso de entrada. Ahora manda a Ajustes del sistema.
- **Lo que no puede ser una clave se responde sin salir a la red.** Pegar la
  URL de donde se sacan las claves, o media clave, costaba un viaje a OpenAI
  para volver como "esta clave no es valida", que culpa a la clave.
- **La voz tambien habla el idioma del usuario.** Wave 9 llevo el idioma a la
  interfaz y a los prompts de texto, pero el plano de voz se quedo atras: el
  reconocedor escuchaba siempre en es-MX, asi que quien hablaba ingles era
  transcrito como si fuera espanol; y el permiso del especialista se
  preguntaba en voz alta siempre en ingles aunque la hoja lo mostrara en
  espanol. Las dos veces la decision existia y nadie la invocaba — el patron
  de bug de este repo — y dos tests que ya existian daban por buena la
  omision, fijando "es-MX" sobre un arnes en ingles. El tercer punto donde se
  decidia un locale a mano — la voz sintetizada sin red — quedo derivado del
  mismo idioma: era el que contestaba en espanol a quien eligio ingles justo
  cuando no queda otro canal.

## [0.10.0] — 2026-08-22

Primera version publicada. Sin notarizar (no hay cuenta de Apple Developer):
al abrirla la primera vez hay que sortear Gatekeeper — el README dice como,
en macOS 14 y en macOS 15+, que ya no son lo mismo.

### Added
- La app habla el idioma de quien la usa, ingles o espanol, y **el modelo
  contesta en ese idioma**: no era barniz de interfaz, los prompts fijaban el
  idioma de las respuestas. Se elige en Ajustes o se sigue al sistema.
- El especialista puede pedir permiso **por voz**: con las manos ocupadas, la
  solicitud se pregunta en voz alta y tu respuesta la resuelve.
- El especialista recuerda en que iban entre arranques, y un encargo cuyo
  canal se cae se termina por la via lenta en vez de perderse.
- La espera del encargo es una tarjeta con paso vivo, reloj y resumen; al
  cerrar deja una linea con lo que se delego.

### Fixed
- **La voz ya no inventa el final.** Narraba encargos que no podia leer: se le
  pedia contar un resultado que nunca se le pasaba, y rellenaba con lo mas
  plausible — que habia salido bien. Ahora recibe lo que reporto el
  especialista, con instruccion explicita de no adornar.

### Changed
- El producto se llama **Companion** (`com.karen.companion`); el build de
  trabajo es Companion Next y nunca comparten identidad.

## [0.9.0] — 2026-08-22

### Added
- Se puede autorizar al especialista **por voz**: cuando pide permiso, la voz
  lo pregunta en su turno y tu respuesta lo resuelve. Antes la solicitud solo
  existia en la hoja de la pantalla y, con las manos ocupadas, moria en el
  auto-rechazo de los dos minutos.
- El especialista **recuerda en que iban** entre arranques de la app: el hilo
  de cada carpeta se guarda y se retoma. Si el guardado ya no le sirve, se
  olvida y empieza limpio, una sola vez.
- Un encargo cuyo canal se cae a media tarea **se termina por la via lenta**
  en vez de perderse, retomando la sesion; el hilo dice que hubo desvio.
- La espera del encargo es una **tarjeta con paso vivo y reloj**: que esta
  haciendo ahora, desde hace cuanto, y un resumen ("2 busquedas · 1 archivo").

### Changed
- Los pasos del encargo dejan de caer como lineas de status sueltas en el
  hilo: viven en la tarjeta mientras corre. El informe final no cambia.
- Documentacion honesta: NOTICE atribuye RiveRuntime (6.23.1, MIT) y lo fija
  por checksum; el ROADMAP mide de nuevo (16.828 lineas contra 15.307 del
  prototipo, 13.622 de tests contra 1.228) y deja de decir "cero
  dependencias"; ADR 002 anota que su premisa perdio una parte.
- Los tres archivos que rozaban el limite quedaron partidos por tema
  (tipografia, encargos del chat, bombas de la sesion de voz): gates sin un
  solo aviso.

## [0.8.1] — 2026-08-21

### Fixed
- La delegacion por voz funciona end-to-end (Wave 7). El cable con
  `claude -p` estaba roto de seis maneras: ruta hardcodeada equivocada,
  deteccion via `which` sin PATH de shell, flag `-m` inexistente, sin
  `--verbose` ni `--permission-prompt-tool stdio` ni rol del ejecutor, y un
  readLine que entregaba bloques del pipe como si fueran lineas NDJSON.
- La voz se entera del resultado: el cierre del encargo se anuncia como
  system item cuando la sesion vuelve a escuchar — antes seguia prometiendo
  "voy en camino" sobre un encargo muerto.
- Errores en humano: "Job failed: processLaunchFailed" jamas vuelve a
  pintarse en el hilo; presupuesto/cancelacion/launch tienen su frase.
- Los eventos del encargo por voz (pasos, pensamientos, aprobaciones) llegan
  al hilo y a la hoja de permisos por el mismo seam que los de chat; antes
  se drenaban y tiraban, y las aprobaciones morian en el auto-deny de 120 s.
- El proceso del especialista persiste entre encargos y se termina al
  cancelar; hermes recibe el prompt como argumento (-q) en vez de un stdin
  que esperaba para siempre; los adjuntos del turno viajan en el prompt.

## [0.8.0] — 2026-08-21

### Added
- La mascota del prototipo saluda al arrancar, con su animacion y sus
  reacciones al click.
- Cinco tipografias elegibles de verdad (antes el control existia pero no
  cambiaba nada).
- Los bloques de codigo salen resaltados, en tema claro y oscuro.
- El orb pasa a tener capas: blob, halo, particulas y sombra, siguiendo la
  voz y el estado de la conversacion.
- Controles propios en toda la app: menus desplegables, botones, campos y
  toggles con sus estados, en vez de los del sistema.

### Changed
- El contraste de cada par de colores se verifica contra WCAG AA en ambos
  temas: un cambio que lo rompa falla la suite.

### Added
- Inter viaja con la app (OFL). Las otras fuentes, si las tienes en esta
  Mac, se usan; si no, Inter o la del sistema.

## [0.7.0] — 2026-08-21

### Added
- Pensar ya no es silencio: un acorde suave de fondo mientras el modelo
  trabaja, con su toggle en Ajustes.
- Adjuntar una imagen durante una conversacion de voz se la muestra al
  agente al momento.
- La interfaz se adapta a como puedes interrumpir: boton visible con
  bocinas, flujo limpio con audifonos, cambiando en vivo al conectarlos.
- Ajustes de voz completos: criterio de fin de turno, velocidad (aplica en
  caliente), volumen, tono y cancelacion de eco con rearme.
- Avisos con sonido de interfaz para permisos y encargos.

### Added
- Avisos breves arriba a la derecha cuando se resuelve un permiso o termina
  un encargo, con un tono corto si los sonidos de interfaz están activos
  (se apagan en Ajustes).
- En una sesión de voz activa, adjuntar una imagen (menú o arrastre) se la
  enseña al agente y espera a que preguntes; no se reenvía si se reconecta.

## [0.6.0] — 2026-08-21

### Added
- Orb: la mascota reacciona a la conversacion — respira en reposo, sigue tu
  voz al escuchar, pulsa al pensar y acompana la del agente al hablar. En
  SwiftUI puro, sin dependencias ni binarios.
- Especialistas opcionales: si tienes Claude Code o Hermes instalados,
  aparecen para elegir; si no, no se nota nada. Si desinstalas el que tenias
  elegido, vuelve solo al nativo.

## [0.5.0-wave5a] — 2026-08-21

### Added
- Tema oscuro y color de acento elegible en toda la app.
- Ajustes: como quieres que te llame, apariencia y voz, con muestra para
  escuchar cada voz antes de elegirla. Todo sobrevive al reinicio.
- Onboarding que explica que necesita y por que, con enlace a donde se
  obtiene la clave y errores que dicen que hacer.

- Tarjetas en el hilo: mapas, galerias de imagenes y fuentes con sus enlaces;
  si el contenido viene mal formado se muestra como bloque de codigo en vez
  de romper la conversacion.
- Atajos de teclado reasignables, con la regla de que escribir gana: si estas
  en un campo de texto, la tecla escribe en vez de disparar el atajo.
- Distribucion: script de release que firma y notariza (o avisa que la build
  va sin firmar), y CI que corre las mismas comprobaciones en cada PR.
- Licencia MIT, NOTICE y guia de contribucion.

### Changed
- Las animaciones usan duraciones nombradas y respetan la preferencia de
  reducir movimiento del sistema.

## [0.4.0-wave4a] — 2026-08-21

### Added
- Delegacion a un especialista nativo que funciona solo con tu API key: el
  modelo de charla le pasa el encargo, trabaja en segundo plano con sus
  herramientas y devuelve el resultado al mismo hilo, desde texto o voz.
- Seis herramientas con nivel de riesgo declarado: leer, escribir y editar
  archivos, ejecutar comandos, y consultar la web. Escribir y ejecutar
  siempre piden permiso.
- Hoja de permisos con el comando o la ruta en claro (no JSON): permitir o
  denegar, y si no respondes se deniega solo a los dos minutos.
- Doble barrera de rutas: ninguna herramienta sale de tu carpeta de trabajo,
  ni siquiera por un enlace simbolico.
- Cola serial con presupuesto de quince minutos y cancelacion.

## [0.3.1-wave3] — 2026-08-21

### Fixed
- La caida del WebSocket ya no deja una sesion zombi: error observable,
  reconexion unica con historial sembrado, y el envio se detiene al primer
  fallo en vez de insistir en silencio.
- El microfono sobrevive a Macs donde el AEC de Apple no inicializa
  (kAUInitialize -10875 con dispositivos virtuales en la cadena): veto
  persistente, espera del HAL con engines frescos al reintentar, y watchdog
  de silencio que falla visible en vez de escuchar la nada.
- El tap interrumpe en vez de colgar; los fallos llegan a pantalla con su
  razon (incluida "sin conexion", distinguida de "el servidor no contesta"
  con NWPathMonitor); AVAudioEngine ya no aborta el proceso al arrancar.

### Added
- Pin de los buses del VPIO al par de dispositivos integrados (tecnica
  documentada por Apple) para esquivar agregados rotos.
- Con salida sin eco (audifonos/bluetooth) se envian frames mientras el
  agente habla: barge-in por voz sin AEC.
- Trazas del turno de voz (transiciones, eventos del servidor, permiso,
  formato del mic, primer buffer): esta ronda fue indiagnosticable sin ellas.
- Firma estable obligatoria en bundle.sh (los permisos TCC sobreviven) e
  identidad/log propios para convivir con el prototipo instalado.

## [0.3.0-wave3] — 2026-08-20

### Added
- Voz en tiempo real sobre OpenAI Realtime (WebSocket) con barge-in, mute que
  cierra turno como exige el servidor, y echo guard de 350 ms; si el
  WebSocket no abre en 6 s cae al pipeline clasico (mic + transcripcion del
  sistema + chat + TTS) sin perder el hilo.
- TTS con voz de OpenAI, cache en disco de frases cortas y voz del sistema
  como respaldo offline. Cero Python (ADR 001).
- Watchdog de Voice Processing: si el engine arranca y el tap nunca entrega
  audio, veta AEC y reintenta una vez — la cicatriz mas cara del prototipo.
- `scripts/bundle.sh`: empaqueta el .app con las usage descriptions que macOS
  exige para pedir microfono y reconocimiento de voz.

### Fixed
- Delegates de AVFoundation reescritos para Swift 6 (aislamiento) y con
  reanudacion idempotente: parar y terminar ya no pueden reanudar dos veces
  la misma continuacion.
- Los caminos de voz (WebSocket y TTS) ahora pasan por las policies de
  endpoint de Wave 2, que se habian saltado.
- Directorios de cache, logs y conversaciones se crean con permisos 0700.

## [0.2.0-wave2] — 2026-08-20

### Added
- Chat usable: onboarding con API key de OpenAI (Keychain, ping
  `GET /models`), hilo con streaming, historial de las ultimas 30
  conversaciones en Application Support.
- Fallback OpenAI → Groq → Ollama (Groq si hay key; Ollama si el probe
  lo ve). Un fallo a media frase no concatena proveedores.

### Fixed
- Hardening del review de cierre (tdd-guide, rojo primero): redirects
  cross-host o https→http rechazados (RedirectPolicy); http permitido solo
  hacia localhost (EndpointPolicy); logs sin errores del sistema ni rutas, y
  las fallas de prune ya no son silenciosas.

### Changed
- `swift run companion` abre ventana. Todavia sin voz.
- Harness de tests migrado a Swift Testing (`swift test`, 22 suites @Test);
  expect/expectEq quedan como shims sobre #expect con sourceLocation, y el
  bombeo de los tests del ViewModel es async (la main queue no es reentrante
  bajo swift test). Muere el runner ejecutable.

## [0.1.0-wave1] — 2026-08-20

### Added
- Nucleo puro de dominio: maquina de estados del turno, codecs Realtime/SSE
  /NDJSON, splitter de frases, endpointer, escalacion, markdown y cards
  `companion:*`, catalogo de proveedores y ejecutores (nativo siempre).
- Suite de caracterizacion portada del prototipo (mismos casos, tipos
  nuevos). 640 tests. `approval: 1` ya no concede permiso.

### Fixed
- Review post-cierre (code-reviewer + security-reviewer + tdd-guide, rojo
  primero): `request_id` vacio ya no crea solicitudes de permiso; URLs de
  `companion:locations` solo https; paths de gallery absolutos y sin `..`;
  suite de robustez ante JSON hostil (anidado 200+, multi-MB, tipos
  inesperados, UTF-8 invalido) en los cuatro codecs. 656 tests.
- Defensa anti-inyeccion de prompt: requisito estructural anadido al spec de
  Wave 4 (tools destructivas siempre via approvals).

### Changed
- `Build.version` a `0.1.0-wave1`.

## [0.1.0-wave0] — 2026-08-20

### Added
- Paquete SPM con 4 targets (Core/Services/UI/App); las dependencias entre
  targets codifican la arquitectura y las vigila el compilador.
- Swift 6.2 tools, strict concurrency; UI y App con MainActor por default.
- Suite de compliance `scripts/gates.sh`: build, estatico (secretos, prints,
  `try?` prohibido en Core/Services, topes de tamano), arquitectura (imports
  por capa) y tests.
- Harness de tests ejecutable (CLT no trae Swift Testing ni XCTest); API
  espejo de Swift Testing para migracion mecanica.
- Programa de reconstruccion por waves, ledger de cicatrices del prototipo
  de referencia, ADR 001 (desacople de Hermes).
