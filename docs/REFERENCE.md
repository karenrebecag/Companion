# Ledger de referencia — companion original

El valor del repo original (`../companion`) no esta en su estructura sino en
las cicatrices: comportamientos ganados a base de bugs reales. Antes de portar
cualquier feature, buscarla aqui. Las referencias archivo:linea apuntan al
repo original.

## Audio / AEC (las mas caras de redescubrir)

- Voice Processing de Apple a veces no entrega NINGUN buffer del microfono.
  Watchdog de 1.5 s: si no llego ni un buffer, apagar Voice Processing y
  reintentar una vez (`RealtimeWiring.swift:306-318`). Sin backoff en el
  original; el rebuild debe limitar reintentos.
- Echo guard: ~350 ms tras audio del agente donde una "interrupcion" se trata
  como eco, no como barge-in (`RealtimeVoice.swift`, `echoGuardUntil`).
- Con AEC del engine compartido, el player de Realtime se cuelga del engine
  del microfono en vez de crear el suyo (`RealtimeAudio.swift`, `ownsEngine`).
- PCM 24 kHz mono int16 little-endian en ambos sentidos; el encoder reserva
  +16 frames de slack para el resampling (`RealtimeAudio.swift:24`).
- Firma estable ("Companion Dev" cert) o TCC revoca microfono/voz en cada
  build (`build.sh` del original, `docs/make-signing-cert.sh`).

## OpenAI Realtime (contratos no obvios)

- Mute NO es dejar de mandar audio: el server espera oir silencio. Hay que
  mandar commit + response.create a mano al mutear
  (`RealtimeVoice.swift:347-370`).
- La voz NO puede cambiar despues del primer audio de la sesion; la velocidad
  si (contrato session.update, `docs/PROTOCOL-REALTIME.md`).
- El schema de tools en Realtime es PLANO, no anidado como en chat/completions
  (`RealtimeProtocol.sessionUpdate`).
- turn_detection: server_vad (silence_duration_ms, default 700) vs
  semantic_vad (eagerness low/auto/high = 8s/4s/2s).
- No hay resume de sesion: al caerse, sesion nueva sembrada con los ultimos
  6 turnos recortados a 200 chars; las imagenes no sobreviven
  (`RealtimeVoice.swift:170-177`).
- WebRTC: el audio viaja por tracks, no por deltas (`carriesAudio`); fases
  llegan por output_audio_buffer.started/stopped; mute = track.enabled=false.
- Cadena de fallback: WebRTC (timeout 12 s) -> WebSocket (6 s) -> pipeline
  clasico (mic + STT local + TTS). Cada caida se loguea.

## Chat / TalkClient

- Cadena de proveedores OpenAI -> Groq -> Ollama; si ya se HABLARON frases de
  una respuesta parcial, no se reintenta con el siguiente proveedor
  (`spokePartial`, `TalkClient.swift:278-283`).
- Corte de frases para TTS: terminador (.!?) SEGUIDO de espacio/salto (no
  parte "3.14"), minimo 25 caracteres (`TalkClient.swift:135-161`).
- Tool call `delegate` {goal, context}: un call malformado o truncado NO
  delega — se habla el texto que haya (`TalkClient.swift:374-385`).
- Timeout por proveedor: 15 s de INACTIVIDAD, no total; 60 s tope del turno.
- Ventana de historial: 20 turnos; adjuntos inline (imagen -> image_url,
  texto legible -> bloque de texto, binario -> no viaja).

## Delegacion (claude -p / Hermes)

- `claude -p` con stream-json bidireccional NDJSON por stdin/stdout; el
  proceso PERSISTE entre encargos si el workdir no cambio
  (`ClaudeStream.swift`, `JobRunner.swift:110-115`).
- Approvals: `control_request` subtype `can_use_tool` -> dialogo o voz;
  auto-deny a los 120 s con mensaje "sin respuesta" para que el especialista
  busque otra ruta (`JobRunner.swift:142-150`).
- `--allowedTools WebSearch,WebFetch` pre-aprobados para no pedir permiso por
  cada lectura web (`ClaudeStream.swift:183`).
- Rol del ejecutor se inyecta UNA vez por sesion (`Escalation.executorRole`).
- Cola serial: un job a la vez, presupuesto 15 min, fallback a Hermes batch
  si el proceso de claude murio (`JobRunner.swift:69,167-179`).
- Timeline de pasos: tool_use -> JobStepInfo -> resumen "2 busquedas · 1
  archivo" (`JobSteps.swift`).

## Endpointing (pipeline clasico)

- Dos umbrales sobre transcript estable: 0.6 s frase completa / 2.6 s frase
  colgante (heuristica de ultima palabra, `SpeechCues`); voiceFloor 0.06;
  tope absoluto de utterance 45 s (`Endpointer.swift:72-74`).
- Endpointer RMS de respaldo cuando no hay permiso de Speech: calibracion
  0.4 s, margen 0.045 sobre el piso, 0.25 s de habla antes de speechStarted.

## TTS clasico

- Frases <=80 chars se cachean en disco por hash fnv1a (avisos repetidos).
- OpenAI `gpt-4o-mini-tts` primero, Hermes/Python fallback con kill a 30 s.

## UI / contratos de cards

- Fences `companion:locations` y `companion:gallery` en el markdown del
  agente se renderizan como cards nativas; JSON invalido degrada a bloque de
  codigo (`CompanionBlocks`, `ChatMarkdown.swift:59-66`).
- `reportCut`: primer bloque = resumen visible, resto plegado, fuentes
  extraidas de la seccion "Sources/Fuentes" (`MarkdownSplitter.swift:34-48`).

## Anti-patrones del original que NO se portan

- Semaforo bloqueando `Task.detached` (`TalkClient.swift:345-372`).
- Contador `generation` manual para cancelar turnos (usar Task cancellation).
- 10+ callbacks cableados a mano (`RealtimeWiring.swift:13-177`) -> AsyncStream.
- AppDelegate god-object con ~20 vars de estado (`main.swift:10-44`).
- `try?` silencioso en I/O (EnvKeyStore, ClaudeStream.submit).
- Paths hardcodeados a `~/.hermes/*` — en el rebuild todo pasa por Config.
- Dos sistemas de color (Palette vs Tokens) y dos de timing (Motion vs
  MotionTime): aqui hay UNO de cada uno.

## Cicatrices propias del rebuild (no venian del prototipo)

Descubiertas en prueba manual de Wave 3; ningun test las vio.

- **AVAudioEngine vacio mata el proceso.** `prepare()`/`start()` sobre un
  engine recien creado, antes de conectar nodos, hace que AVFoundation arme
  su grafo de I/O por defecto y toque el microfono que el engine del mic ya
  tiene abierto: lanza una NSException que Swift NO puede capturar y el
  proceso aborta. Reglas: conectar el grafo ANTES de arrancar, y nunca
  `prepare()` — `start()` reporta el fallo como error de Swift, del que si se
  puede degradar (`RealtimePlayer.start`).
- **Un bundle sin usage descriptions no puede pedir microfono.** `swift run`
  produce un binario suelto; macOS jamas muestra el prompt. Ver
  `scripts/bundle.sh` y el gate que lo vigila.
- **Bundle id compartido con el prototipo.** Con el mismo
  `com.karen.companion`, LaunchServices abria la app vieja al pedir la nueva.
  El rebuild usa `com.karen.companion.next` y su propio archivo de log.

## El patron de bug que se repite en este repo

Cuatro veces en Wave 3 aparecio lo mismo: **la logica correcta y testeada,
sin cablear al camino real.** El watchdog de VP existia y nadie lo llamaba;
`disableVoiceProcessing()` idem; el barge-in del reducer estaba probado pero
la vista llamaba `hangUp()`; `VoiceCopy.failure(...)` estaba escrito y nadie
lo mostraba; `.networkUnavailable` se agrego al enum sin que ningun camino lo
emitiera. Los tests verdes NO prueban que el cableado exista. Al revisar una
wave, buscar cada capacidad nueva con grep y confirmar que alguien la invoca
desde el flujo real.
