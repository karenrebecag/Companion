# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Una
entrada por wave cerrada; sin releases versionados hasta Wave 5.

## [Unreleased]

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
