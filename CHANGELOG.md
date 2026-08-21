# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Una
entrada por wave cerrada; sin releases versionados hasta Wave 5.

## [Unreleased]

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
