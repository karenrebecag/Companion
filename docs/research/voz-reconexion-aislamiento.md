# Reference Brief: reconexion Realtime y aislamiento de RealtimeRuntime

Slug: voz-reconexion-aislamiento | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

## 1. Pregunta y decisiones abiertas

Decision de Karen (2026-09-30): A+B; reset por conexion sin tocar micEnabled; nonisolated(nonsending) por metodo. Decision C: C2 silencio avisado, sin C5 (PR aparte tras este fix). El gate de TSan va despues, en un PR aparte. [KAREN:chat 2026-09-30]

Origen: spec aprobada `races-produccion.md`, hallazgos 2 y 3. Karen aprobo los fixes y pidio que cada uno pase por /research antes de codear. No hay discovery.

Decision A (hallazgo 2, reconexion). Tras reabrir el WebSocket de OpenAI Realtime, que secuencia de mensajes hay que mandar, que estado de `RealtimeRuntime` hay que resetear (y cual NO), y como se vuelve a consumir el stream de eventos.

Decision B (hallazgo 3, aislamiento). Si `nonisolated(nonsending)` (SE-0461) en los metodos async de `RealtimeRuntime` es la herramienta correcta en Swift 6.2 para confinarlos al actor `VoiceSession`, sin activar `NonisolatedNonsendingByDefault` en `Package.swift`; frente a parametro `isolated` con `#isolation`, convertirlo en actor, o un `Mutex`.

Decision C (agregada despues, profundidad quick). Si el WebSocket se cae mientras el asistente esta hablando y la sesion reconecta, que hace el asistente: callar hasta que la usuaria hable, regenerar o continuar la respuesta cortada, o decir una linea corta de recuperacion; y que oye la usuaria en cada caso. Pregunta de Karen, literal, transmitida por /research: "research sobre esto, como lo hace incredible instalada en local u openai y chatbots comerciales ?" [KAREN:chat 2026-09-30]
Anclaje de citas: las [repo:] de las decisiones A y B (secciones 2, 6, 7 y 8) leen origin/main 08cd9cb, es decir `git show 08cd9cb:<ruta>`, el estado ANTES del fix; no se reescriben. Las de la decision C leen el arbol actual de la rama fix/voice-reconnect (08cd9cb mas cambios sin commitear en RealtimeRuntime, VoiceSession+Pumps, VoiceAudit y los fakes). Lo que el fix ya aplico esta en la nota al final de la seccion 10.

## 2. Estado actual

Contextos: app empaquetada (RealtimeWSTransport real sobre URLSession), swift test local en paralelo con fakes (ScriptedVoiceTransport), swift test --sanitize=thread local (oraculo de la spec), CI macos-26 via scripts/gates.sh con --no-parallel. CompanionUI no importa Services: no hay previews de VoiceSession.

- `VoiceSession` es un `package actor` y guarda el runtime como `let realtime: RealtimeRuntime` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:4]
- `RealtimeRuntime` es `final class RealtimeRuntime: @unchecked Sendable` sin lock ni actor [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:6]
- Su comentario justifica el `@unchecked` por "exclusive access in VoiceSession", es decir, confinamiento por convencion, no por compilador [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:5]
- El target CompanionServices no declara `swiftSettings`, asi que sus metodos no tienen aislamiento por defecto (solo UI y App usan defaultIsolation MainActor) [repo:Package.swift:24]
- El toolchain declarado es `swift-tools-version: 6.2` [repo:Package.swift:1]
- CI corre en macos-26 con el Xcode por defecto y ejecuta scripts/gates.sh [repo:.github/workflows/ci.yml:15]
- gates.sh agrega `--no-parallel` solo cuando CI=true [repo:scripts/gates.sh:245]
- `reset()` limpia micEnabled, didBecomeReady, pendingUpdate, voiceSent, transportDown, responseActive, pendingResponse y agentSpeech [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:93]
- `reset()` pone `micEnabled = true` sin mirar si la maquina tenia el mic apagado [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:94]
- `micEnabled` solo se escribe desde el efecto `.setMicEnabled` de la maquina de turnos [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:86]
- `prepareSessionUpdate` omite la voz si `voiceSent` ya es true [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:127]
- `prepareSessionUpdate` siembra la historia en las instrucciones via `RealtimeCodec.seed(from:)` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:410]
- `flushPendingUpdate` pone `pendingUpdate = nil` antes del `await send`, asi que es de un solo disparo si nadie lo corre en paralelo [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:157]
- `send` descarta todo en silencio mientras `transportDown` sea true [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:166]
- Un fallo de envio pone `transportDown = true` y solo `reset()` lo limpia [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:170]
- `handle(.sessionCreated)` vuelve a llamar `flushPendingUpdate` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:236]
- `handle` escribe `agentSpeech` al llegar cada delta [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:254]
- `handle` espera `parentTools.execute`, que puede tardar (manos, pantalla), dentro del mismo metodo async [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:320]
- La apertura normal hace `realtime.reset()` antes de todo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:12]
- La apertura normal prepara el update con la historia del hilo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:51]
- La apertura normal abre, arranca pumps y hace flush explicito, ademas del flush en session.created [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:62]
- `startPumps` solo crea el pump de eventos si `eventTask == nil` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:11]
- `pumpEvents` itera `transport.events()` una sola vez; al terminar el `for await` decide reconectar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:120]
- La reconexion se llama DESDE dentro de `pumpEvents`, es decir, desde la propia tarea `eventTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:140]
- `reconnectRealtimeSession` solo hace `transport.open` y luego `startPumps()`: no llama reset, prepareSessionUpdate ni flushPendingUpdate [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:157]
- Verificado (pendiente de la spec): como `eventTask` sigue apuntando a la tarea en curso, `startPumps()` NO relanza el pump de eventos; al volver, `pumpEvents` retorna y nadie consume el stream nuevo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:160]
- Solo `closeRealtime` cancela y anula `eventTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Teardown.swift:19]
- El transporte real reemplaza el stream de eventos en cada `open` si el anterior termino [repo:Sources/CompanionServices/Voice/Realtime/RealtimeWSTransport.swift:48]
- En un fallo de recepcion, el transporte emite `.serverError("connection lost")` y cierra el stream [repo:Sources/CompanionServices/Voice/Realtime/RealtimeWSTransport.swift:108]
- "connection lost" no contiene "session", asi que `handle` lo ignora y es el fin del stream lo que dispara la reconexion [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:357]
- `.realtimeSessionReady` solo cambia estado si la maquina esta en `.connecting`; tras una reconexion en listening es un no-op [repo:Sources/CompanionCore/Session/TurnMachine.swift:315]
- El fake de tests usa un solo `StreamBox` para toda su vida [repo:Tests/CompanionTests/VoiceSessionFakes.swift:161]
- `ScriptedVoiceTransport.open` no crea stream nuevo: los autoEvents de un segundo open caen en un stream ya terminado [repo:Tests/CompanionTests/VoiceSessionFakes.swift:184]
- `simulateReceiveFailure` termina ese unico stream para siempre [repo:Tests/CompanionTests/VoiceSessionFakes.swift:195]
- El test de reconexion existente solo afirma `openCount`, no que se reenvie el update ni que los eventos vuelvan a fluir [repo:Tests/CompanionTests/VoiceSilentDropoutTests.swift:86]
- Todas las llamadas async a `realtime.*` en Sources salen de metodos del actor VoiceSession (ej. handle desde pumpEvents) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:126]
- VoiceSession lee estado del runtime de forma sincrona (didBecomeReady en el bucle de espera) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:130]
- VoiceSession lee `agentSpeech` de forma sincrona para el EchoGuard [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:103]
- VoiceSession lee `micEnabled` de forma sincrona en cada frame del mic [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:200]
- C: en el arbol actual, la reconexion llama `resetConnection()`, que termina en `dropInFlightResponse()`; su comentario deja abierta, a proposito, la decision de que hacer si el corte cae hablando [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:118]
- C: `dropInFlightResponse` vacia `agentSpeech`, asi que lo que el agente llevaba dicho se pierde [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:123]
- C: `agentSpeech` acumula el transcript de los deltas GENERADOS por el servidor, no de lo que el parlante ya reprodujo [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:276]
- C: la respuesta del asistente solo entra al hilo en `assistantTranscriptDone`; si la conexion muere antes, el hilo no guarda nada de esa respuesta [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:284]
- C: la reconexion re-siembra con `historyTurns()` del hilo, que por lo anterior termina en la pregunta de la usuaria sin respuesta [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:170]
- C: la reconexion no manda `response.create`: hoy el comportamiento efectivo es callar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:172]
- C: cada delta de audio va directo al player local; el audio ya recibido antes del corte sigue en su cola [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:287]
- C: la maquina sale de `speaking` por `agentAudioStopped` [repo:Sources/CompanionCore/Session/TurnMachine.swift:424]
- C: o por `responseCompleted` sin audio pendiente [repo:Sources/CompanionCore/Session/TurnMachine.swift:436]
- C: o por `playerDrained`, que no depende del servidor: pasa a listening con echo guard [repo:Sources/CompanionCore/Session/TurnMachine.swift:443]
- C: `responseCompleted` solo nace de `response.done`, que la conexion muerta ya no entrega [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:319]
- C: `agentAudioStopped` solo nace de los eventos `output_audio_buffer.stopped/cleared` del servidor [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:73]
- C: `playerDrained` lo aplica `pumpDrained` por cada senal de `player.drained` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:271]
- C: el player emite esa senal en `bufferDidFinish` cuando su cola de buffers pendientes llega a cero [repo:Sources/CompanionServices/Voice/Realtime/RealtimePlayer.swift:173]
- C: hay test de "drained -> listening" en la maquina [repo:Tests/CompanionTests/TurnMachineTests.swift:287]
- C: en realtime, cortar durante speaking pasa a listening y emite `cancelAgentOutput` [repo:Sources/CompanionCore/Session/TurnMachine.swift:265]
- C: `pending` solo sube cuando un delta produce un buffer con frames; un delta que no decodifica no se encola [repo:Sources/CompanionServices/Voice/Realtime/RealtimePlayer.swift:123]
- C: `replyCompleted` (transcript terminado) pone la maquina en speaking sin mirar el player [repo:Sources/CompanionCore/Session/TurnMachine.swift:380]
- C: mientras la maquina esta en `speaking`, el oido descarta `speechStarted` (manos libres) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:88]
- C: sin AEC, el mic no se reenvia mientras la maquina esta en `speaking` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:209]
- C: en push-to-talk, una pulsacion durante `speaking` no es local, es decir, va por el camino de corte del turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:57]
- C: el pipeline clasico ya resuelve un turno cortado: enhebra como respuesta parcial lo que la voz DIJO (no el texto generado) y marca una nota de un solo uso para el turno siguiente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:417]
- C: esa parcial sale de `synthesizer.spokenSoFar()`, es decir, de lo reproducido [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:418]
- C: la nota se inyecta como `<steer>` en el contexto del turno siguiente [repo:Sources/CompanionCore/Perception/ContextBlock.swift:143]
- C: su texto es "La usuaria corto tu respuesta anterior para corregir el rumbo. No la repitas; sigue desde lo que dice ahora." y habla de un corte de la usuaria, no de la red [repo:Sources/CompanionCore/Perception/ContextBlock.swift:200]
- C: el unico aviso de caida de voz que existe hoy es "La sesion de voz se cayo.", y solo aparece cuando la reconexion falla [repo:Sources/CompanionUI/es.lproj/Localizable.strings:52]
- C: durante `speaking` el runtime puede estar esperando una herramienta del padre; una respuesta regenerada podria volver a pedirla [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:342]

## 3. Fuentes primarias

- OpenAI: al abrir una conexion nueva el servidor emite `session.created` como primer evento y trae la configuracion POR DEFECTO de la sesion [doc:https://developers.openai.com/api/reference/resources/realtime/server-events@gpt-realtime-2026-09-30]
- OpenAI: `session.update` solo actualiza los campos presentes; se puede mandar en cualquier momento salvo `voice` y `model` [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- OpenAI: `voice` solo se puede fijar mientras la sesion no haya emitido audio; la sesion dura como maximo 60 minutos [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- OpenAI: `conversation.item.create` sirve para poblar historia, pero no puede crear mensajes de audio del asistente [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- OpenAI: el evento `error` suele ser recuperable y la sesion sigue abierta, asi que un error no equivale a una caida [doc:https://developers.openai.com/api/reference/resources/realtime/server-events@gpt-realtime-2026-09-30]
- Swift (SE-0338): una funcion async no aislada corre en el executor generico y libera el actor del que venia [doc:https://github.com/swiftlang/swift-evolution/blob/60444bd1f5a9b76b8a67f780f62dd1fb1872e670/proposals/0338-clarify-execution-non-actor-async.md#L33@swift-5.7]
- Swift (diagnostico oficial del compilador): sin el feature, las funciones async no aisladas nunca corren en el executor de un actor [doc:https://github.com/swiftlang/swift/blob/32ec5a61b726ffbea62c5879e67a7396674d571c/userdocs/diagnostics/nonisolated-nonsending-by-default.md#L8@swift-6.2]
- Swift (mismo documento): el modificador `nonisolated(nonsending)` se puede usar ANTES de activar el feature para correr en el actor del llamador [doc:https://github.com/swiftlang/swift/blob/32ec5a61b726ffbea62c5879e67a7396674d571c/userdocs/diagnostics/nonisolated-nonsending-by-default.md#L45@swift-6.2]
- SE-0461 (Implemented, Swift 6.2): la sintaxis nueva fija la semantica de una funcion async en cualquier modo de lenguaje, independiente del feature flag [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L209@swift-6.2]
- SE-0461: una funcion `nonisolated(nonsending)` siempre corre en el actor del llamador y sus argumentos no cruzan frontera de aislamiento [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L266@swift-6.2]
- SE-0461: tras cada llamada async interna, la funcion vuelve al executor del actor implicito, no al generico [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L799@swift-6.2]
- SE-0461: el patron `isolated (any Actor)? = #isolation` logra lo mismo pero es boilerplate y el argumento por defecto se pierde en uso de orden superior [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L122@swift-6.2]
- SE-0461: un closure `@Sendable` o pasado a un parametro `sending` se infiere `nonisolated` [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L546@swift-6.2]
- Stdlib Swift 6.2: `TaskGroup.addTask` recibe `operation: sending @escaping @isolated(any)`, o sea que sus closures no heredan el actor [doc:https://github.com/swiftlang/swift/blob/6f3099b564595b0b8075c06e472c140d2ca97d2d/stdlib/public/Concurrency/TaskGroup+addTask.swift.gyb#L43@swift-6.2]
- SE-0420 (Swift 6.0): `#isolation` como argumento por defecto se expande al aislamiento estatico del llamador [doc:https://github.com/swiftlang/swift-evolution/blob/3a5614025e4877118f48e719acb71361bad54d11/proposals/0420-inheritance-of-actor-isolation.md#L358@swift-6.0]
- SE-0433 (Swift 6.0): los actores intercalan en cada `await`; `Mutex.withLock` es sincrono y no puede sostenerse a traves de un punto de suspension [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L299@swift-6.0]
- OpenAI: la Conversation de una sesion Realtime son los items de entrada y salida "generated during the current session" [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- C, OpenAI: truncar es quitar de la conversacion la parte no reproducida de la ultima respuesta, para que el modelo sepa donde lo cortaron y siga con naturalidad [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- C, OpenAI: en WebRTC y SIP el servidor sabe cuanto audio se reprodujo; por WebSocket el cliente maneja la reproduccion y debe parar el audio y truncar el mismo [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- C, OpenAI: `conversation.item.truncate` con `audio_end_ms` borra el transcript de texto del lado del servidor para que no quede en contexto texto que la usuaria no oyo [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- C, OpenAI: la referencia de client events no tiene ningun evento para reanudar, continuar o reintentar una respuesta; solo `response.create` (respuesta nueva) y `response.cancel` [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- C, OpenAI: `response.create` acepta `instructions` que reemplazan las de la sesion solo para esa respuesta, y `conversation: none` crea una respuesta fuera de banda que no agrega items a la conversacion [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- C, Google Gemini Live (contraste): es el unico proveedor revisado con reanudacion de sesion por handle, valido 2 horas, y su doc no afirma que una generacion cortada continue [doc:https://ai.google.dev/gemini-api/docs/live-session@2026-09-30]
- C, Retell: con `auto_reconnect`, tras 5 s sin ping pong Retell cierra y reabre la conexion con el servidor LLM del cliente hasta 2 veces [doc:https://docs.retellai.com/api-references/llm-websocket@2026-09-30]
- C, Retell: cada `response_id` nuevo descarta todas las respuestas anteriores; no hay reanudacion de una respuesta a medias [doc:https://docs.retellai.com/api-references/llm-websocket@2026-09-30]

## 4. Implementaciones de referencia

- pipecat (Daily; framework de agentes de voz de produccion, mantenido activamente) manda `session.update` al recibir `session.created`, en cada conexion [ref:https://github.com/pipecat-ai/pipecat/blob/55589db6e141aadcad39ad6efb9b6aed927bdd66/src/pipecat/services/openai/realtime/llm.py#L879-L882@55589db6e141aadcad39ad6efb9b6aed927bdd66]
- pipecat, al desconectar, baja `_api_session_ready` y limpia las tool calls completadas: el estado por conexion muere con la conexion [ref:https://github.com/pipecat-ai/pipecat/blob/55589db6e141aadcad39ad6efb9b6aed927bdd66/src/pipecat/services/openai/realtime/llm.py#L725-L740@55589db6e141aadcad39ad6efb9b6aed927bdd66]
- pipecat, al reconectar, re-siembra la conversacion desde su contexto local y vuelve a mandar el session.update antes del primer response.create [ref:https://github.com/pipecat-ai/pipecat/blob/55589db6e141aadcad39ad6efb9b6aed927bdd66/src/pipecat/services/openai/realtime/llm.py#L1160-L1203@55589db6e141aadcad39ad6efb9b6aed927bdd66]
- openai-agents-js (SDK oficial de OpenAI) llama `updateSessionConfig(sessionConfig)` en cada `connect`, despues de que el socket queda conectado [ref:https://github.com/openai/openai-agents-js/blob/00bfb9dc340a518fe250adc5c022d96a042dfc9b/packages/agents-realtime/src/openaiRealtimeWebsocket.ts#L585@00bfb9dc340a518fe250adc5c022d96a042dfc9b]
- openai-agents-js, al pasar a desconectado, libera el secuenciador de response.create y resetea el estado de reproduccion [ref:https://github.com/openai/openai-agents-js/blob/00bfb9dc340a518fe250adc5c022d96a042dfc9b/packages/agents-realtime/src/openaiRealtimeWebsocket.ts#L132-L138@00bfb9dc340a518fe250adc5c022d96a042dfc9b]
- swift-nio (Apple) adopta `nonisolated(nonsending)` bajo `#if compiler(>=6.2)` y depreca su sobrecarga con `isolated (any Actor)? = #isolation` [ref:https://github.com/apple/swift-nio/blob/21de5f08c1a166a6dd293d0e587ad977bf8dac5d/Sources/NIOCore/AsyncAwaitSupport.swift#L25-L45@21de5f08c1a166a6dd293d0e587ad977bf8dac5d]
- C, LiveKit Agents (LiveKit Inc.; framework open source de agentes de voz, main activo): al reconectar reenvia session.update, tools y el contexto de chat, falla los response pendientes con "pending response discarded due to session reconnection" y cierra la generacion en curso, sin pedir una respuesta nueva [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L979-L1040@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- C, LiveKit: la reconexion planificada por `max_session_duration` espera a que termine la generacion en curso antes de cortar, para no partir una frase [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L1296-L1304@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- C, LiveKit: tras una interrupcion, al historial va solo el texto sincronizado con lo reproducido, marcado `interrupted` [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3295-L3348@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- C, pipecat: `reset_conversation` desconecta, marca la conversacion para re-sembrar y reconecta; el re-sembrado ocurre recien en el siguiente `_create_response`, es decir, calla hasta el proximo turno [ref:https://github.com/pipecat-ai/pipecat/blob/55589db6e141aadcad39ad6efb9b6aed927bdd66/src/pipecat/services/openai/realtime/llm.py#L1160-L1179@55589db6e141aadcad39ad6efb9b6aed927bdd66]
- C, openai-agents-python (SDK oficial, PR #5069 mergeado): `_reset_connection_state` descarta los ids de item y el estado de audio de la conexion cerrada, porque la nueva mandaria truncate y retrieve de ids que el servidor no conoce [ref:https://github.com/openai/openai-agents-python/blob/a34b3964283a2d4cd32efce00bcc1783a3cf5be1/src/agents/realtime/openai_realtime.py#L1302-L1314@a34b3964283a2d4cd32efce00bcc1783a3cf5be1]
- C, openai-agents-js: `_interrupt` calcula `audio_end_ms` desde la reproduccion local y manda `conversation.item.truncate`, el patron de barge-in por WebSocket [ref:https://github.com/openai/openai-agents-js/blob/00bfb9dc340a518fe250adc5c022d96a042dfc9b/packages/agents-realtime/src/openaiRealtimeWebsocket.ts#L711-L730@00bfb9dc340a518fe250adc5c022d96a042dfc9b]
- C, Incredible (producto de referencia): la auditoria del proyecto registra en su binario la nota "(Your previous turn was interrupted — the user pressed abort." para el turno siguiente a un corte [repo:docs/research/auditoria-decisiones-incredible.md:134]

## 5. Opciones

Decision A: reconexion.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A1. Tras `open` exitoso: reset por conexion, `prepareSessionUpdate` con historia, `flushPendingUpdate`; y `pumpEvents` como bucle que vuelve a iterar `transport.events()` | Misma secuencia que la apertura normal y que pipecat/agents-js; el pump sigue siendo UNA tarea, sin carrera con `eventTask` | Hay que partir `reset()` o restaurar `micEnabled`; toca pumpEvents | media | Recomendada |
| A2. Igual que A1 pero relanzar el pump con `eventTask = nil; startPumps()` desde dentro de la tarea vieja | Cambio minimo | Una tarea crea a su sucesora; `closeRealtime` puede cancelar la equivocada si se cruza; mas dificil de razonar | baja | No |
| A3. Solo limpiar `transportDown` y reenviar el JSON guardado del primer update | Sin tocar reset | El JSON viejo trae la historia sembrada vieja y quizas voz omitida; deja responseActive y agentSpeech de la conexion muerta | baja | No |
| A4. Delegar la reconexion al transporte (reabre solo) | Encapsula red | El transporte no conoce instrucciones ni tools; igual hace falta avisar a la sesion | alta | No |

Decision B: aislamiento de RealtimeRuntime.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| B1. `nonisolated(nonsending)` en cada metodo async de RealtimeRuntime, sin feature flag | Soportado en Swift 6.2 sin flag; corre en el actor del llamador; sin locks; los accesos sincronos del actor siguen sincronos; es la direccion que toma Apple (swift-nio) | No quita reentrancia en cada `await`; con `@unchecked Sendable` el compilador no impide un llamador fuera del actor | baja | Recomendada, idealmente quitando `@unchecked Sendable` si compila |
| B2. Parametro `isolation: isolated (any Actor)? = #isolation` en cada metodo | Funciona desde Swift 6.0 | Boilerplate; se pierde en uso de orden superior; swift-nio lo depreca a favor de B1 | media | No |
| B3. Convertir RealtimeRuntime en `actor` | Aislamiento verificado por compilador | 11 lecturas sincronas pasan a `await` (incluida una por frame de mic); doble salto por evento; un segundo dominio reentrante | alta | No |
| B4. `Mutex` del modulo Synchronization sobre el estado | Proteccion fina, sin async | `withLock` no cruza `await`; no da orden entre handle y reset; muchos campos | media | No |

Decision C: que hace el asistente si el corte cae mientras habla. "Oye" describe lo que escucha la usuaria.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| C1. Silencio puro (lo que hace hoy el arbol): descartar la respuesta y no dejar rastro | Cero codigo; es lo que hacen LiveKit, pipecat y los SDK de OpenAI al reconectar; el drenaje del player ya devuelve la maquina a listening | Oye: el audio ya recibido suena hasta vaciarse, se corta a media frase y despues nada, sin saber si fue la red o el fin. El hilo pierde lo dicho, asi que "que me decias?" falla | baja | No |
| C2. Silencio informado: dejar que el audio recibido suene y que el drenaje del player pase a listening (ya existe), enhebrar lo que sono como parcial cortada, avisar en la isla y dejar una nota de un solo uso para el turno siguiente ("tu respuesta se corto por la red tras: ...; si te piden seguir, continua sin repetir") | Nada suena sin que la usuaria lo pida; "sigue" o "que decias" funcionan; reusa el patron del pipeline clasico y de Incredible; no re-ejecuta herramientas; no necesita una salida nueva de speaking | Oye: la parte recibida, se corta, silencio; ve un aviso en la isla y tiene que decir "sigue" (un turno extra). La parcial solo es fiel si se enhebra despues del drenaje | media | Recomendada |
| C3. Regenerar solo: `response.create` apenas se re-siembra | La respuesta llega completa sin pedirla | Oye: la parte recibida, una pausa de reconexion y la respuesta DESDE EL PRINCIPIO con otras palabras. Puede pedir otra vez una herramienta con efectos; puede hablar encima de una usuaria que ya siguio (manos libres) | baja | No |
| C4. Continuar solo: enhebrar la parcial, nota "continua desde donde te cortaron" y `response.create` | Emula el "resume" que la API no tiene | Oye: la parte recibida, pausa, y una continuacion que el modelo reconstruye (puede repetir o saltar); mismos riesgos de herramientas y de hablar encima que C3 | media | No por defecto |
| C5. Linea hablada de recuperacion: `response.create` fuera de banda con `instructions` de una frase ("se corto, quieres que siga?") y luego esperar | Feedback audible en la misma voz; no inventa contenido | Oye: la parte recibida, pausa, "Perdon, se corto la conexion. Sigo?". Gasta una respuesta; con TTS local sonaria otra voz; en manos libres puede pisar a la usuaria | media | Variante valida de C2 si Karen quiere aviso audible |

## 6. Evidencia en contra

- Contra B1: `nonisolated(nonsending)` elimina la carrera de datos pero no la reentrancia; mientras `handle` espera, el actor puede correr `reset()` o `closeRealtime` y `handle` retoma con estado ya cambiado [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L15@swift-6.0]
- Se acepta: es la semantica normal de cualquier actor, el mismo riesgo que ya tiene todo el codigo de VoiceSession; el invariante de un solo update se mantiene porque `flushPendingUpdate` anula antes del await [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:157]
- Contra B1: con `@unchecked Sendable` el compilador no avisa si un llamador futuro (Task.detached, un task group) invoca estos metodos fuera del actor, y ahi vuelven a correr en el executor generico [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L546@swift-6.2]
- Se resuelve quitando `@unchecked Sendable`: SE-0461 muestra que un valor no Sendable guardado en un actor puede llamar metodos nonsending sin error, y cualquier envio fuera del actor pasa a ser error de compilacion [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L266@swift-6.2]
- Contra A1: resetear todo el runtime tambien re-enciende el mic si el usuario lo tenia apagado, porque `reset()` fuerza `micEnabled = true` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:94]
- Se resuelve: la reconexion restaura `micEnabled` desde `machine.snapshot.muted` o usa un reset por conexion que no toque micEnabled; queda como decision de diseno para la spec [repo:Sources/CompanionCore/Session/TurnMachine.swift:321]
- Contra C2: en push-to-talk la usuaria pidio algo y espera la respuesta; un silencio a media frase puede leerse como app colgada, y el precedente de los frameworks es debil porque son librerias que dejan la politica a la app [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L979-L1040@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Se resuelve en parte: el aviso en la isla dice que fue la red y que "sigue" continua; el hueco que queda (sin aviso audible) lo cierra C5 como variante si Karen lo pide [repo:Sources/CompanionUI/es.lproj/Localizable.strings:52]
- Contra C2: la parcial enhebrada puede decir palabras que la usuaria no oyo, porque `agentSpeech` es texto generado, no reproducido [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:276]
- Se resuelve dejando que el audio ya recibido suene completo antes de enhebrar (asi lo generado y lo oido coinciden hasta el corte), o recortando por la posicion de reproduccion como hace el clasico; OpenAI pide justamente no dejar en contexto texto no oido [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]
- Contra rechazar C3/C4: la API no ofrece reanudar, asi que "retomar" solo se puede emular; se acepta que C4 quede como opcion explicita a pedido ("sigue"), que es C2 [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@gpt-realtime-2026-09-30]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, secuencia de reconexion: cada conexion nueva recibe su session.update completo porque arranca con defaults del servidor [ref:https://github.com/pipecat-ai/pipecat/blob/55589db6e141aadcad39ad6efb9b6aed927bdd66/src/pipecat/services/openai/realtime/llm.py#L879-L882@55589db6e141aadcad39ad6efb9b6aed927bdd66]
- Bien hecho, adopcion del modificador: swift-nio lo pone en la declaracion y marca la variante `#isolation` como deprecated [ref:https://github.com/apple/swift-nio/blob/21de5f08c1a166a6dd293d0e587ad977bf8dac5d/Sources/NIOCore/AsyncAwaitSupport.swift#L28@21de5f08c1a166a6dd293d0e587ad977bf8dac5d]

```swift
nonisolated(nonsending) func withNIOUnsafeThrowingContinuation(...) async throws -> sending T
```

- Anti-ejemplo en este repo: la reconexion reabre el socket pero no reenvia configuracion, y la sesion nueva queda con los defaults que anuncia session.created [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:157]
- Anti-ejemplo en este repo: relanzar el pump con `if eventTask == nil` desde dentro de la propia eventTask nunca crea uno nuevo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:11]
- Anti-ejemplo para el test de B: dos flushes desde `group.addTask { await rt.flushPendingUpdate() }` corren en el executor generico incluso con nonsending, porque el closure de addTask es `sending` y se infiere nonisolated [doc:https://github.com/swiftlang/swift/blob/6f3099b564595b0b8075c06e472c140d2ca97d2d/stdlib/public/Concurrency/TaskGroup+addTask.swift.gyb#L43@swift-6.2]
- C, bien hecho en este repo: el corte de turno del pipeline clasico enhebra solo lo que la voz dijo y deja una nota de un solo uso; C2 es ese mismo patron con otra causa y otro texto de nota [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:417]
- C, bien hecho: LiveKit descarta la generacion en curso al reconectar y guarda en el historial solo lo reproducido, marcado interrupted [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3344-L3348@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- C, anti-ejemplo: mandar `conversation.item.truncate` o `response.cancel` con ids de la conexion muerta; el servidor nuevo responde `error` porque nunca vio esos items [ref:https://github.com/openai/openai-agents-python/blob/a34b3964283a2d4cd32efce00bcc1783a3cf5be1/src/agents/realtime/openai_realtime.py#L1302-L1308@a34b3964283a2d4cd32efce00bcc1783a3cf5be1]

## 8. Trampas

- El pump de eventos no se relanza hoy: sin arreglar esto, reenviar session.update no basta porque nadie procesa session.created, audio ni tool calls de la conexion nueva [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:160]
- La Conversation de Realtime son los items generados durante la sesion actual y cada conexion nueva es una sesion nueva; tras reconectar solo existe lo que se re-siembre, aqui via instrucciones con `RealtimeCodec.seed` [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- Mandar la voz de nuevo es correcto en la conexion nueva: el candado de voz es por sesion y la sesion nueva no emitio audio; por eso `voiceSent` debe resetearse [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- `responseActive` y `pendingResponse` de la conexion muerta deben limpiarse, o `requestResponse` encola para siempre esperando un response.done que nunca llega [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:109]
- `micEnabled` NO es estado de conexion: es un espejo del mute de la maquina y `reset()` lo pisa [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:94]
- `didBecomeReady` vuelve a false con reset; el siguiente session.updated aplica `.realtimeSessionReady`, que la maquina ignora fuera de connecting pero que marca otra vez `sessionReady` en el timeline [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:24]
- La pagina de OpenAI "WebSockets" hoy describe GPT-Live (`/v1/live/sessions`, `session.start`), otro protocolo; el proyecto usa `/v1/realtime` con `session.update` y no debe seguir esa guia [doc:https://developers.openai.com/api/docs/guides/realtime-websocket@gpt-live-2026-09-30]
- El proyecto apunta a `wss://api.openai.com/v1/realtime?model=gpt-realtime` [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:29]
- Contexto swift test: el fake no reabre el stream en `open`, asi que un test que dependa de session.created tras reconectar queda verde o rojo por el fake, no por el codigo; el fake necesita un stream nuevo por open como hace EventPipe [repo:Tests/CompanionTests/VoiceSessionFakes.swift:184]
- Contexto swift test: el test de B tiene que llamar desde un actor (por ejemplo `addTask { @MainActor in ... }` o un actor de prueba); desde closures de addTask sin anotar no prueba el confinamiento [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L546@swift-6.2]
- Contexto CI: con `--no-parallel` las carreras son menos probables; el oraculo real de B es TSan local, no CI [repo:scripts/gates.sh:245]
- Contexto app: la reconexion solo corre si la maquina esta en listening o speaking y hay red; en speaking, el audio ya encolado del player sigue sonando y la respuesta del servidor murio con la conexion [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:135]
- Contexto app: la sesion Realtime dura como maximo 60 minutos, asi que un corte por limite tambien entra por esta ruta de reconexion [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@gpt-realtime-2026-09-30]
- `nonisolated(nonsending)` no cambia a los Task no estructurados creados dentro: no heredan el actor [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L410@swift-6.2]
- C: tras un corte en speaking, `response.done` y `output_audio_buffer.stopped` ya no llegan, pero speaking tiene una tercera salida que no depende del servidor: `playerDrained`, cuando el player local vacia su cola [repo:Sources/CompanionCore/Session/TurnMachine.swift:443]
- C: la reconexion no vacia el player, asi que el audio ya recibido suena completo y su drenaje devuelve la maquina a listening con echo guard; la usuaria no queda sorda en manos libres en el caso normal [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:120]
- C, contexto app manos libres: mientras dura ese audio el oido sigue descartando el inicio de habla, igual que en cualquier respuesta; el caso borde sin drenaje queda en la seccion 9 [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:88]
- C, contexto app push-to-talk: una pulsacion en speaking corta la salida del agente y pasa a listening, independiente del servidor [repo:Sources/CompanionCore/Session/TurnMachine.swift:265]
- C: la nota `<steer>` actual dice que la usuaria corto para cambiar de rumbo; reusarla tal cual tras un corte de red le mentiria al modelo y lo empujaria a no continuar [repo:Sources/CompanionCore/Perception/ContextBlock.swift:200]
- C: el estado por conexion que nombra items (ids de respuesta, audio) debe descartarse; un truncate o cancel con ids viejos llega como error a la conexion nueva [ref:https://github.com/openai/openai-agents-python/blob/a34b3964283a2d4cd32efce00bcc1783a3cf5be1/src/agents/realtime/openai_realtime.py#L1302-L1314@a34b3964283a2d4cd32efce00bcc1783a3cf5be1]
- C: regenerar o continuar solo (C3, C4) puede volver a pedir una herramienta del padre cuyo efecto ya ocurrio antes del corte [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:342]
- C: el corte por el limite de 60 minutos se puede evitar en medio de una frase si la reconexion planificada espera a que termine la respuesta, como hace LiveKit [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L1296-L1304@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- C, contexto swift test: ningun test que usa `simulateReceiveFailure` llega a speaking antes del corte; probar C necesita un guion que llegue a speaking con audio, corte y reabra [repo:Tests/CompanionTests/VoiceSessionFakes.swift:201]

## 9. Incertidumbre

- ASSUMPTION: quitar `@unchecked Sendable` de RealtimeRuntime compila una vez que sus metodos async son nonsending. prueba: quitarlo en una rama, `swift build` y `swift build --build-tests`, y leer los errores (tests que lo capturan en closures Sendable)
- ASSUMPTION: el compilador de CI (Xcode por defecto de macos-26) acepta `nonisolated(nonsending)`; localmente hay Swift 6.3.3. prueba: el paso "Show toolchain" del primer run de CI y que gates.sh compile
- ASSUMPTION: con B1, el test de dos flushes concurrentes desde un actor queda rojo antes y verde despues bajo TSan. prueba: escribirlo primero, correr `swift test --sanitize=thread --filter` sobre el codigo actual y confirmar aviso o doble envio
- ASSUMPTION: OpenAI no expone reanudar una sesion Realtime por id tras un corte de WebSocket; la reconexion siempre es sesion nueva. La referencia de client events no tiene evento de reanudacion (seccion 3), pero no se probo en vivo. prueba: cortar la red en vivo y ver si session.created trae un id distinto
- ASSUMPTION: re-sembrar la historia solo en instrucciones basta para que el agente siga el hilo tras reconectar. prueba: la prueba en vivo de Karen de la spec, preguntando por algo dicho antes del corte
- ASSUMPTION: el drenaje del player saca siempre de speaking tras un corte. Caso borde sin cubrir: el corte cae despues de que la cola ya se habia vaciado (maquina en listening) y un audioDelta o transcript posterior la volvio a poner en speaking sin audio nuevo encolado, o un delta decodifica a cero frames y `pending` nunca sube; en ambos no llega ningun drenaje. prueba: test con el fake que drene la cola, mande `replyCompleted` o un delta vacio, corte y reabra, y afirme que la maquina no queda en speaking
- ASSUMPTION: los eventos `output_audio_buffer.*` no llegan por WebSocket (la guia dice que en WebSocket el cliente maneja la reproduccion); la pagina de server events leida no lo confirma. prueba: loguear en una sesion real por WebSocket si llega algun output_audio_buffer.stopped
- ASSUMPTION: si el audio ya recibido se deja sonar completo, `agentSpeech` en ese momento coincide con lo oido hasta el corte. prueba: sesion real, comparar el transcript acumulado con lo que se oyo al cortar la red a mitad de una respuesta larga
- ASSUMPTION: Incredible no usa OpenAI Realtime sino una cascada STT, LLM y TTS (strings del binario 0.2.36: ElevenLabs y AssemblyAI para STT, ElevenLabs e Inworld para TTS, Anthropic, Groq, Cerebras y otros como LLM), asi que su "reconexion" no es la de este socket. prueba: con la app cerrada, `strings` sobre `Contents/MacOS/incredible` y buscar `api.openai.com/v1/realtime` (cero coincidencias en este run)
- ASSUMPTION: tras un corte de la usuaria, Incredible no regenera ni sigue solo: el siguiente turno lleva la nota "Your last words may not have fully played: pick up from where the user is now, don't repeat yourself." (string del binario, en las variantes "pressed abort" y "pressed the activation key to steer"). prueba: en Incredible, cortarlo a mitad de frase y ver si retoma sin pedirlo
- ASSUMPTION: para un stream de LLM cortado por limite de tiempo, Incredible SI continua solo, con la nota "Your previous response was interrupted after ... Continue the work from the preserved partial response" (string del binario); es trabajo de agente en texto, no voz hablada. prueba: no hay experimento barato; leerlo como indicio, no como regla de voz
- ASSUMPTION: no se encontro en los strings de Incredible ninguna politica especifica para una caida de red en medio del habla (solo "Reconnecting" como texto de UI y reintentos de STT). prueba: con Karen, cortar el wifi mientras Incredible habla y anotar que oye y que ve
- ASSUMPTION: el prototipo `../companion` no reconecta: ante un fallo de recepcion emite "la conexion de voz se cerro" y, como no contiene "session", solo lo reporta sin cerrar ni reabrir (leido en Sources/RealtimeVoice.swift del arbol local, con cambios sin commitear y sin remoto accesible para permalink). prueba: cortar la red en el prototipo mientras habla
- ASSUMPTION: el comportamiento de ChatGPT Advanced Voice ante una caida a mitad de respuesta no esta documentado; la FAQ de Voice devolvio 403 en este run y la busqueda en help.openai.com solo trajo requisitos de red y un reintento automatico de dictado. prueba: cortar la red con ChatGPT Voice hablando y observar
- ASSUMPTION: Vapi no se verifico en este run. prueba: leer su documentacion de eventos de llamada y desconexion
- [NEEDS CLARIFICATION: la recomendacion para C es C2 (silencio informado: aviso en la isla y "sigue" continua sin repetir). Karen elige si ademas quiere la linea hablada corta de C5, o si prefiere que retome solo (C4) aceptando que puede hablar encima o repetir.]

## 10. Checklist de estandar

- [ ] Tras un `open` exitoso en la reconexion se envia exactamente un `session.update` con instrucciones, tools y voz, antes de cualquier `response.create`
- [ ] Tras la reconexion, `transportDown`, `responseActive`, `pendingResponse`, `agentSpeech`, `voiceSent` y `didBecomeReady` quedan en su valor inicial
- [ ] Tras la reconexion, `micEnabled` refleja el mute de la maquina, no `true` fijo
- [ ] El update reenviado incluye la historia actual del hilo sembrada en instrucciones
- [ ] Tras la reconexion hay una tarea consumiendo el stream de eventos nuevo (test: el fake entrega session.created en el segundo open y se observa su efecto)
- [ ] El fake de transporte crea un stream nuevo en cada `open` despues de un fin de stream, igual que el transporte real
- [ ] Todos los metodos async de RealtimeRuntime llevan `nonisolated(nonsending)` y `Package.swift` no cambia
- [ ] Si compila, RealtimeRuntime deja de ser `@unchecked Sendable`; si no, la razon queda escrita en su comentario
- [ ] El test de concurrencia llama al runtime desde un contexto aislado a un actor, no desde closures de addTask sin anotar
- [ ] `swift test --sanitize=thread` sin avisos en RealtimeRuntime; scripts/gates.sh verde con y sin CI=true
- [ ] C: un corte en speaking termina en listening por el drenaje del player, sin esperar response.done ni output_audio_buffer (test con el fake: speaking con audio, corte, reapertura, drenaje)
- [ ] C: el caso borde sin drenaje (seccion 9) tiene un test o una salida explicita
- [ ] C: tras un corte en speaking, la reconexion no manda `response.create` por su cuenta (salvo la linea de C5 si Karen la elige)
- [ ] C: lo que la usuaria alcanzo a oir queda en el hilo como respuesta parcial del asistente, y nunca texto que no sono
- [ ] C: el turno siguiente lleva una nota de un solo uso que dice que la respuesta se corto por la red, distinta de la nota de corte de la usuaria
- [ ] C: la isla muestra un aviso de corte y reconexion aunque la reconexion salga bien
- [ ] C: ningun `conversation.item.truncate` ni `response.cancel` sale con ids de la conexion anterior
- [ ] C: prueba en vivo de Karen: cortar el wifi a mitad de una respuesta larga, volver, decir "sigue" y oir la continuacion sin repeticion

Resuelto por fix/voice-reconnect (arbol actual de esa rama, cambios sin commitear al 2026-09-30):

- [x] A1: `pumpEvents` es un bucle `while true` que vuelve a leer `transport.events()` tras reconectar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:149]
- [x] A1: la reconexion llama `resetConnection()`, que no toca `micEnabled` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:109]
- [x] A1: la reconexion re-siembra con la historia actual del hilo y hace flush del update [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:170]
- [x] A1: `reconnectAttempted` se limpia cuando la conexion llega a session.updated [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:129]
- [x] B1: los metodos async de RealtimeRuntime llevan `nonisolated(nonsending)` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:130]
- [x] B1: tambien los de VoiceAudit [repo:Sources/CompanionServices/Voice/Ear/VoiceAudit.swift:53]
- [ ] Diferido: `@unchecked Sendable` se mantiene porque quitarlo rompe VoiceSession.init; la razon queda en su comentario [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:9]
- [ ] Diferido: el gate de TSan va en un PR aparte, despues [KAREN:chat 2026-09-30]
- [ ] Sin tocar: ClassicRuntime; la decision C sigue pendiente (seccion 9) [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:118]

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Realtime server events (session.created, error) | OpenAI | gpt-realtime, sin version | 2026-09-30 | high |
| 2 | Realtime client events (session.update, conversation.item.create, truncate, response.create) | OpenAI | gpt-realtime, sin version | 2026-09-30 | high |
| 3 | Realtime conversations guide (Conversation, interruption and truncation, 60 min) | OpenAI | gpt-realtime, sin version | 2026-09-30 | high |
| 4 | WebSockets guide (GPT-Live, no aplica) | OpenAI | sin version | 2026-09-30 | medium |
| 5 | SE-0461 nonisolated(nonsending) | Swift Evolution | Swift 6.2, fb22d3e | 2026-09-30 | high |
| 6 | Diagnostico NonisolatedNonsendingByDefault | swiftlang/swift | 32ec5a6 | 2026-09-30 | high |
| 7 | SE-0338 ejecucion de async no aisladas | Swift Evolution | Swift 5.7, 60444bd | 2026-09-30 | high |
| 8 | SE-0420 herencia de aislamiento | Swift Evolution | Swift 6.0, 3a56140 | 2026-09-30 | high |
| 9 | SE-0433 Mutex | Swift Evolution | Swift 6.0, f4c21d2 | 2026-09-30 | high |
| 10 | TaskGroup+addTask.swift.gyb | swiftlang/swift | release/6.2, 6f3099b | 2026-09-30 | high |
| 11 | pipecat OpenAI realtime llm.py | pipecat-ai | 55589db | 2026-09-30 | high |
| 12 | openai-agents-js openaiRealtimeWebsocket.ts | OpenAI | 00bfb9d | 2026-09-30 | high |
| 13 | swift-nio AsyncAwaitSupport.swift | Apple | 21de5f0 | 2026-09-30 | high |
| 14 | LiveKit Agents llm/_realtime/openai.py y voice/agent_activity.py | LiveKit | d251b89 | 2026-09-30 | high |
| 15 | openai-agents-python realtime/openai_realtime.py (PR #5069) | OpenAI | a34b396 | 2026-09-30 | high |
| 16 | Retell LLM WebSocket | Retell AI | sin version | 2026-09-30 | medium |
| 17 | Gemini Live API session management | Google | sin version | 2026-09-30 | medium |
| 18 | Incredible.app 0.2.36, strings del binario (sin abrir la app) | Incredible | 0.2.36 | 2026-09-30 | low |
| 19 | ChatGPT Voice FAQ (403, no leida) | OpenAI | sin version | 2026-09-30 | low |
