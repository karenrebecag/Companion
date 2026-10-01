# Reference Brief: interrupciones por causa (barge-in, red, herramienta atascada, stop)

Slug: interrupciones-por-causa | Nivel: standard | Fecha: 2026-10-01 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Decision de Karen (2026-10-01): R1, una sola regla para toda causa de interrupcion (2 s, P1', semantica de Q3); R3, un stop explicito ya no deja la nota de steer, en PR aparte; seguimientos, cada uno en su PR y en este orden: (b) conversation.item.truncate en el barge-in de realtime, (c) timeout comun de herramientas en clasico (R4), (a) fallo de red a mitad de voz en clasico alineado con C2. [KAREN:chat 2026-10-01 via orquestador]

Nota del verificador (2026-10-01): unverified=1 contradictions=1 por la cifra de Pipecat. Se re-verifico contra `frame_processor.py` en da37523: la interrupcion pasa por `_start_interruption` (linea 1147) y `__cancel_process_task`, que llama `cancel_task` sin plazo (linea 1259), con el 1 s por defecto. La constante de 3 s solo la usa `__cancel_input_task`, llamada desde `cleanup()` (linea 665), es decir el teardown. La cifra de 1 s queda.

## 1. Pregunta y decisiones abiertas

Seguimiento de Karen (transmitido por el orquestador el 2026-10-01) al brief `classic-turn-serialize` (ESCALADO): los agentes de voz en produccion, reaccionan distinto segun POR QUE se corto un turno, o tratan todos los casos igual? Causas: (1) la usuaria habla encima o pulsa con la red bien; (2) caida de red o desconexion; (3) una herramienta atascada o lenta; (4) cancelacion explicita (stop).

Numeracion de este brief (la del orquestador, no la de la seccion 1 de `classic-turn-serialize`):

- Q1. Plazo de la espera del turno nuevo sobre el cortado (propuesto 2 s).
- Q2. Que pasa al vencer (P1' propuesto: empezar igual mas una compuerta de generacion que descarta las escrituras tardias de `cutTurn` del turno atascado, es decir el parcial y la nota steer).
- Q3. Cambio de comportamiento: un turno cortado mientras su oido terminaba no deja rastro.

Lo que se pide concluir: (a) si la industria diferencia por causa o generaliza; (b) una tabla por causa con la practica de la industria y la nuestra lado a lado; (c) si Q1 y Q3 deben variar por causa.

## 2. Estado actual

Contextos: app empaquetada en modo clasico (sintetizador `SpeechSynthesis`, oido real, tecla de hold), app empaquetada en modo realtime (WebSocket de OpenAI, `RealtimeWSTransport`), `swift test` local (paralelo), CI (`swift test --no-parallel`), `swift test --sanitize=thread` local. Este brief no ejecuto codigo: todo lo de abajo es lectura de fuentes en dfd3aeb.

### Quien corta, segun la causa (maquina de turnos)

- Pulsacion durante `.thinking`/`.speaking` en clasico: `cutClassicTurn()`, que marca `interruptionPending`, pasa a `.listening` y emite `.cancelAgentOutput` mas `.requestClassicListen` [repo:Sources/CompanionCore/Session/TurnMachine.swift:150]
- Pulsacion durante `.thinking`/`.speaking` en realtime: `.cancelAgentOutput` y abre el mic, sin `requestClassicListen` [repo:Sources/CompanionCore/Session/TurnMachine.swift:79]
- Hablar encima en clasico manos libres: `heardWhileSpeaking` solo corta si `EchoGuard` dice que es interrupcion real, y emite `.cancelAgentOutput` [repo:Sources/CompanionCore/Session/TurnMachine.swift:336]
- Stop explicito (Esc, el boton Stop o un "para" hablado) entra por `VoiceSession.interrupt()` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:374]
- En clasico ese stop corta y cuelga: `[.cancelAgentOutput] + hangUp()`, sin reabrir el mic [repo:Sources/CompanionCore/Session/TurnMachine.swift:137]
- En realtime ese stop corta y vuelve a `.listening` sin colgar [repo:Sources/CompanionCore/Session/TurnMachine.swift:140]
- El freno de la sesion anade el evento de isla `.interrupted` cuando corto algo [repo:Sources/CompanionCore/Session/SessionMachine+Brakes.swift:47]
- Ese evento llega al modelo en el bloque de contexto como "la usuaria interrumpio" [repo:Sources/CompanionCore/Perception/ContextBlock.swift:278]
- `.cancelAgentOutput` se reparte por pipeline: realtime llama `realtime.cancelAgent()`, clasico `cancelClassicTurn()` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:71]

### Clasico: barge-in, pulsacion y stop comparten un solo camino

- `cancelClassicTurn` cancela la tarea del turno, corta el aviso, para el sintetizador y cancela la vision [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:31]
- El turno cancelado llega a `cutTurn` en el siguiente punto de cancelacion del stream [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:326]
- `cutTurn` enhebra como respuesta parcial lo que devuelve `spokenSoFar()` y luego pone `steerPending = true` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:444]
- `spokenSoFar` une `spokenDone` [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:136]
- Una frase entra en `spokenDone` solo despues de terminar de sonar: el parcial es lo oido, con granularidad de frase [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:358]
- `stop()` no borra lo dicho (`resetSpoken: false`); solo `begin()` lo borra [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:172]
- `steerPending` no se reinicia en ningun otro sitio: solo lo consume el siguiente `submit`, aunque haya colgado en medio [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:94]
- La nota steer dice "La usuaria corto tu respuesta anterior para corregir el rumbo. No la repitas" [repo:Sources/CompanionCore/Perception/ContextBlock.swift:204]
- Por eso un stop explicito en clasico deja hoy la misma nota "para corregir el rumbo" que una pulsacion, mas el evento de isla [repo:Sources/CompanionCore/Session/TurnMachine.swift:137]
- El turno nuevo no espera al cortado: `startClassicTurn` cancela y crea sin esperar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]

### Clasico: herramienta lenta o atascada

- A 1 s de herramienta sin respuesta, el turno dice una linea propia de "trabajando" [repo:Sources/CompanionCore/Session/Acknowledgement.swift:10]
- La carrera herramienta contra espera vive en `actAcknowledging`, con `withTaskGroup` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:70]
- Si el turno ya esta cancelado, las llamadas aun no iniciadas se responden "cancelled: the user interrupted" sin ejecutarse [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:58]
- La llamada en curso no se interrumpe; la ubicacion espera hasta 30 s de permiso, 10 s de fix y 10 s de geocodificacion [repo:Sources/CompanionServices/Perception/CoreLocationCity.swift:67]
- La ronda de herramientas no tiene un plazo comun; solo algunas herramientas traen el suyo, como el shell, 60 s por defecto [repo:Sources/CompanionServices/Tools/NativeToolRunner.swift:54]
- Otra con plazo propio: la lectura de una URL, 30 s [repo:Sources/CompanionServices/Tools/NativeToolRunner.swift:499]

### Clasico: caida de red

- Si el stream del chat lanza antes de que el turno hablara, el turno falla con la causa mapeada [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:352]
- `unreachable` y `timeout` de chat se mapean a `.networkUnavailable` [repo:Sources/CompanionServices/Voice/Session/VoiceFailureMapping.swift:17]
- Si lanza a mitad de habla, solo marca `failed = true` y sale del bucle [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:356]
- Despues dice lo que quedaba en el buffer y enhebra todo lo dicho como respuesta completa, sin nota ni aviso [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:430]
- Una caida de red en clasico no cancela la tarea del turno: no pasa por `cutTurn`, asi que no hay turno cortado que esperar [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:364]

### Realtime: barge-in, pulsacion y stop

- `cancelAgent` manda `response.cancel` y vacia el reproductor; no manda `conversation.item.truncate` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:270]
- Un turno de usuaria que llega con respuesta activa la adelanta con `response.cancel` y luego `response.create`, confiando en el orden del servidor [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:175]
- `commitWithText` solo anade al contexto la nota de red (`cutNote`); en realtime no existe nota steer [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:254]
- El hilo local recibe la respuesta del agente solo con `output_audio_transcript.done` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:331]

### Realtime: caida de red (C2, #65/#67, y #59)

- Al terminar el stream de eventos con la sesion activa, reconecta una vez si hay red y queda presupuesto; si no, `.turnFailed(.sessionDropped)` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:148]
- El presupuesto es 3 reconexiones por ventana de 60 s [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:116]
- La reconexion abre una sesion NUEVA del servidor y reenvia la configuracion con el historial [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:206]
- `resetConnection` saca el parcial de la respuesta que murio con el socket y lo guarda como `unthreadedCut` y `cutNote` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:126]
- Ese parcial es la transcripcion GENERADA, no el audio reproducido; el propio codigo lo marca `HACK` con `conversation.item.truncate` como mejora [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:143]
- El parcial se enhebra cuando termina de sonar el audio en cola, y solo entonces se anuncia en la isla [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:322]
- Sin audio en cola, se enhebra justo tras reconectar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:223]
- El aviso de isla se omite con la voz apagada o con un fallo o permiso en pantalla, y se va solo [repo:Sources/CompanionCore/Session/SessionMachine.swift:205]
- El texto del aviso: "Se corto la conexion a media respuesta" / "Ya hay conexion. Di sigue y continuo." [repo:Sources/CompanionUI/es.lproj/Localizable.strings:699]
- El siguiente turno de usuaria lleva la nota reply_cut con la cola de lo dicho [repo:Sources/CompanionCore/Perception/ContextBlock.swift:147]
- La nota reply_cut dice "se corto por la red despues de... si te piden seguir, continua sin repetir" [repo:Sources/CompanionCore/Perception/ContextBlock.swift:219]
- `TurnContext` documenta la diferencia: en la red "nadie la corto: no se le debe decir al modelo que la usuaria lo hizo" [repo:Sources/CompanionCore/Session/TurnContext.swift:49]
- Una respuesta nueva que nadie pidio borra la nota de red, porque "sigue" apuntaria a otra frase [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:362]
- CHANGELOG: con la red cortada, lo dicho queda en el chat, la voz vuelve a escuchar y "sigue" continua; al reconectar nunca habla sola [repo:CHANGELOG.md:14]

### Compuertas de generacion que ya existen (precedente de P1')

- `realtimeGeneration` se incrementa al crear el bombeo de eventos, es decir una vez por sesion [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:14]
- El bombeo captura su generacion al nacer [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:16]
- Cada evento de un socket viejo se descarta: `if Task.isCancelled || generation != realtimeGeneration { return }` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:128]
- `isCurrent` combina cancelacion, generacion y `voiceClosed` para que una reconexion tardia no reviva una sesion cerrada [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:167]
- Declaracion: "Bumped each time the event pump is created, i.e. once per session" [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:113]
- Lo introdujo #59, commit 72c36eb ("a Realtime reconnect keeps listening with its config and mute") [repo:CHANGELOG.md:29]
- `holdGeneration` hace lo mismo con la pulsacion: una suelta compara la generacion tras suspenderse y se retira si otra pulsacion la adelanto [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:178]
- `armGeneration` hace lo mismo en el tap de la tecla [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:212]
- La regla de arquitectura dice lo contrario ("cancelacion estructurada, no contadores de generacion"); el codigo ya tiene tres excepciones para escrituras tardias que la cancelacion no alcanza [repo:docs/ARCHITECTURE.md:79]

## 3. Fuentes primarias

- OpenAI Realtime: el modelo necesita saber donde lo interrumpieron; truncar quita la parte no reproducida de la ultima respuesta [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- OpenAI Realtime: con WebRTC o SIP el servidor trunca solo; con WebSocket el cliente reproduce el audio y "debe parar la reproduccion y encargarse de truncar" [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- OpenAI Realtime: en push-to-talk por WebSocket, al pulsar se cancela la respuesta en curso [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- OpenAI Realtime: una sesion contiene su Conversation, con los items "generados durante la sesion actual", y dura como maximo 60 minutos; la guia no documenta reanudar una sesion tras desconectar [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- OpenAI Realtime: `response.cancel` cancela la respuesta en curso y el servidor responde `response.done` con `status=cancelled` [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- OpenAI Realtime: `conversation.item.truncate` borra tambien la transcripcion del servidor "para que no haya texto en el contexto que la usuaria no oyo"; un `audio_end_ms` mayor que el audio da error [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- LiveKit Agents: al interrumpir, el agente calla y trunca su historial a la parte que la usuaria oyo [doc:https://docs.livekit.io/agents/logic/turns/@2026-10-01]
- LiveKit Agents: una interrupcion falsa (VAD sin palabras) se reanuda por defecto desde donde quedo [doc:https://docs.livekit.io/agents/logic/turns/@2026-10-01]
- Retell: cuando hace falta respuesta nueva llega otro `response_id` y "todas las respuestas anteriores se descartan" [doc:https://docs.retellai.com/api-references/llm-websocket@2026-10-01]
- Retell: con `auto_reconnect`, si no llega ping-pong en 5 s cierra y reabre la conexion hasta 2 veces [doc:https://docs.retellai.com/api-references/llm-websocket@2026-10-01]
- Retell: `user_hangup` y `agent_hangup` son finales esperados; `error_llm_websocket_lost_connection` es un error distinto ("la conexion se rompio durante la llamada") [doc:https://docs.retellai.com/reliability/debug-call-disconnect@2026-10-01]
- Vapi: el plazo de la peticion de una herramienta es 20 s por defecto, y una herramienta `async` deja seguir al asistente sin esperar [doc:https://docs.vapi.ai/api-reference/tools/get@2026-10-01]

## 4. Implementaciones de referencia

LiveKit Agents (LiveKit Inc., framework de voz en produccion; main en d251b89, el mismo commit del brief anterior) [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L16@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
Pipecat (Daily; main en da37523) [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L1221-L1228@da37523d8692f13649ccf1b3a90ccc223a17d69b]
Vapi server SDK (VapiAI, tipos generados por Fern desde la definicion de la API de Vapi; main en dfa08b8): es el esquema oficial de la plataforma, no una implementacion [ref:https://github.com/VapiAI/server-sdk-typescript/blob/dfa08b87a134e80306796d17d5aa55d1f434e516/src/api/types/StopSpeakingPlan.ts#L3-L6@dfa08b87a134e80306796d17d5aa55d1f434e516]

### Interrupcion por la usuaria o por codigo: un solo camino

- LiveKit: el origen de una interrupcion es `audio_activity`, `user_turn` o `programmatic` (stop por codigo, una herramienta, el cierre), y se guarda "para la traza" [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L27-L30@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: `interrupt(source=...)` registra el origen y llama al mismo `_cancel()` sea cual sea [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L201-L227@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: `_cancel()` arma un unico plazo `INTERRUPTION_TIMEOUT` (5 s); al vencer registra error, cancela las tareas y da la respuesta por terminada [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L284-L304@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: al cerrar el turno de usuaria, interrumpe la respuesta en curso con `source="user_turn"`, y si no es interrumpible descarta la respuesta a la usuaria [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L2774-L2786@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: tras interrumpir usa la transcripcion sincronizada con la reproduccion; si no sono nada propio, el texto enhebrado es vacio [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3296-L3322@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: el mensaje del asistente se guarda con `interrupted=speech_handle.interrupted`; no anade una nota en prosa [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3344-L3349@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit realtime: si el mensaje sono a medias, manda `truncate` con `audio_end_ms` = posicion de reproduccion [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L4544-L4552@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: el mensaje de la usuaria entra al contexto persistente solo si su respuesta llego a programarse; una interrumpida antes no lo deja [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3618-L3624@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: el cierre sin drenar fuerza la interrupcion con `interrupt(force=True)` [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_session.py#L1371-L1379@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: `shutdown` cierra con `CloseReason.USER_INITIATED` [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_session.py#L1247-L1248@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Pipecat: `InterruptionFrame` interrumpe la salida en curso, "por ejemplo cuando la usuaria empieza a hablar", y la puede empujar cualquier procesador [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L1221-L1228@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: al interrumpir, el agregador del asistente cierra el turno con `interrupted=True` y empuja lo agregado al contexto [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/aggregators/llm_response_universal.py#L1902-L1908@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: cada procesador atiende `InterruptionFrame` llamando a `_start_interruption()` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L838-L839@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `_start_interruption()` cancela y recrea la tarea de proceso con `__cancel_process_task()` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L1129-L1148@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `__cancel_process_task()` llama `cancel_task` sin plazo explicito, asi que usa el de por defecto [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L1256-L1260@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: ese plazo por defecto de `cancel_task` es 1 s [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/utils/base_object.py#L154-L159@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: al vencer, `except TimeoutError` solo registra un aviso y sigue [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/utils/asyncio/task_manager.py#L253-L254@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `INPUT_TASK_CANCEL_TIMEOUT_SECS = 3` existe, pero lo usa `__cancel_input_task()` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L1211-L1218@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: y `__cancel_input_task()` solo se llama desde `cleanup()` (teardown del procesador), no desde la interrupcion [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L654-L666@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat realtime: al interrumpir manda `response.cancel` (con deteccion de turno local) y trunca al menor entre tiempo transcurrido y duracion del audio [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/openai/realtime/llm.py#L554-L621@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: su nota al modelo existe solo para un turno de usuaria VACIO que interrumpio, y afirma que "la conversacion solo incluye la parte que oyeron" [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/turns/empty_user_turn.py#L11-L16@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Vapi (otra cosa, no una espera al turno cortado): `backoffSeconds` (1 s por defecto) es cuanto tarda el agente en volver a hablar tras ser interrumpido; "stop", "no" interrumpen siempre [ref:https://github.com/VapiAI/server-sdk-typescript/blob/dfa08b87a134e80306796d17d5aa55d1f434e516/src/api/types/StopSpeakingPlan.ts#L7-L42@dfa08b87a134e80306796d17d5aa55d1f434e516]

### Herramienta en curso o atascada: plazo propio, distinto del de interrupcion

- LiveKit: una respuesta interrumpida cancela la ejecucion de herramientas y registra las que si terminaron, para no volver a ejecutarlas [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3894-L3912@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: esos resultados se guardan con `reply_required = False`; un traspaso interrumpido se registra como error "no ocurrio" [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/generation.py#L1203-L1214@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Pipecat: `cancel_on_interruption` (True por defecto) cancela la llamada al interrumpir; con False la llamada es asincrona y su resultado llega despues [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py#L186-L189@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: al recibir la interrupcion cancela cada funcion marcada `cancel_on_interruption` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py#L826-L829@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `function_call_timeout_secs` cancela la llamada vencida, la cierra como cancelada y corre inferencia "para que el LLM informe que no termino" [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py#L330-L333@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `FunctionCallCancelFrame.run_llm` lo pone solo el plazo de la propia llamada; "una interrupcion no debe disparar inferencia" [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L1472-L1484@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: una llamada cancelada con `cancel_on_interruption=True` queda en el contexto con resultado `CANCELLED`; una asincrona recibe en su lugar un mensaje developer de cancelacion; sin `run_llm` no se corre el modelo [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/aggregators/llm_response_universal.py#L2122-L2133@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Vapi: `request-response-delayed` es la frase que se dice cuando la herramienta pasa de `timingMilliseconds` [ref:https://github.com/VapiAI/server-sdk-typescript/blob/dfa08b87a134e80306796d17d5aa55d1f434e516/src/api/types/ToolMessageDelayed.ts#L5-L22@dfa08b87a134e80306796d17d5aa55d1f434e516]
- Vapi: `request-failed` se dice en voz alta o se pasa al modelo como pista de sistema para una respuesta consciente del error [ref:https://github.com/VapiAI/server-sdk-typescript/blob/dfa08b87a134e80306796d17d5aa55d1f434e516/src/api/types/ToolMessageFailed.ts#L19-L34@dfa08b87a134e80306796d17d5aa55d1f434e516]

### Caida de red o error: otro camino, sin esperar al turno

- LiveKit realtime: al caer el socket reintenta con `max_retry`; agotado, emite error no recuperable [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L1042-L1077@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit realtime: al reconectar reenvia configuracion, herramientas y el historial local a la sesion nueva [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L979-L1007@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit realtime: las respuestas pendientes fallan con "descartada por reconexion" y la generacion en curso se cierra [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L1029-L1040@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit realtime: `_DiscardedGeneration` marca una respuesta cancelada para saltarse sus eventos tardios (compuerta de generacion por id) [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L282-L285@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: los errores no recuperables de STT, LLM o TTS se cuentan; pasado `max_unrecoverable_errors` (3) la sesion cierra con `CloseReason.ERROR` [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_session.py#L1988-L2019@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Pipecat: `ErrorFrame` notifica errores y `CancelFrame` para el pipeline "de inmediato, sin procesar lo encolado" [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L1078-L1110@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: `EndFrame` es el fin ordenado y no se pierde con una interrupcion [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L2010-L2024@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: con `CancelFrame` el turno del asistente se cierra `interrupted=True`; con `EndFrame`, `interrupted=False` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/aggregators/llm_response_universal.py#L1906-L1908@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat realtime: un error de envio por el WebSocket se trata como fatal, sin reintento [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/openai/realtime/llm.py#L741-L756@da37523d8692f13649ccf1b3a90ccc223a17d69b]

## 5. Opciones

### (a) Diferencia la industria por causa?

Si, entre CLASES de fallo; no, dentro de la clase "interrupcion". Interrumpir (usuaria o codigo), fallar la red, vencer una herramienta y terminar la sesion son primitivas distintas en las tres referencias. Pero una pulsacion, un barge-in y un stop por codigo van por el MISMO `interrupt()` con el MISMO plazo (LiveKit 5 s; Pipecat 1 s en el camino de interrupcion, el plazo por defecto de `cancel_task`; su constante de 3 s es solo para el teardown); el origen solo se registra para la traza. Nadie espera al turno cortado por una caida de red: se reconecta (LiveKit, Retell) o se trata como error (Pipecat realtime, LiveKit tras reintentos).

### (b) Tabla por causa

| Causa | Quien | Espera antes del turno siguiente | Hilo con el parcial (lo oido) | Nota al modelo | Lo que la usuaria ve u oye |
|---|---|---|---|---|---|
| Barge-in o pulsacion | Industria | Interrumpe y espera al cortado con un plazo generico: LiveKit 5 s, Pipecat 1 s (por defecto de `cancel_task`) | Si, truncado a lo oido (transcripcion sincronizada o `audio_end_ms`) | No en prosa; LiveKit marca `interrupted=True` en el mensaje; Pipecat solo con turno vacio | Calla al instante y responde a lo nuevo; Vapi retoma la voz tras `backoffSeconds` (1 s), que es una pausa antes de hablar, no una espera al cortado |
| Barge-in o pulsacion | Nuestro clasico | Ninguna hoy (carrera de orden); propuesta Q1: hasta 2 s | Si, frases completas que sonaron | Si, nota steer, una vez; hoy puede llegar un turno tarde | Calla, mic abierto para el hold nuevo |
| Barge-in o pulsacion | Nuestro realtime | Ninguna: `response.cancel` y `response.create` en orden en el servidor | Sin truncate: el servidor conserva la respuesta generada entera; hilo local sin verificar (seccion 9) | No | Calla, mic abierto |
| Caida de red | Industria | No se espera al turno: reconexion con reintentos (LiveKit `max_retry`, Retell 2 tras 5 s sin ping) o error | La generacion en curso se descarta; se reenvia el historial local a la sesion nueva | Ninguna documentada | Silencio; si se agotan los reintentos, fin con razon de error |
| Caida de red | Nuestro realtime (C2) | No se espera: 1 reconexion por conexion lista, 3 por minuto | Si, pero la transcripcion generada, no lo oido (`HACK`) | Si, reply_cut con la cola de lo dicho, en el siguiente turno | Aviso de isla "Se corto la conexion... Di sigue"; nunca habla sola |
| Caida de red | Nuestro clasico | No aplica: no hay corte, el turno termina solo | Antes de hablar: nada y tarjeta de error; a mitad: dice el resto del buffer y lo enhebra como completo | No | Antes de hablar: error de red; a mitad: la respuesta acaba antes, sin aviso |
| Herramienta lenta o atascada | Industria | Plazo POR HERRAMIENTA, aparte del de interrupcion (Pipecat `timeout_secs`, Vapi 20 s); si la usuaria interrumpe, el plazo generico de interrupcion | Herramientas terminadas registradas; en Pipecat las canceladas quedan como `CANCELLED` si tienen `cancel_on_interruption=True` | Al vencer la herramienta: inferencia para que el modelo diga que no termino (Pipecat) o pista de sistema (Vapi); al interrumpir: sin inferencia | Frase de espera a los N ms (Vapi), luego aviso de fallo |
| Herramienta lenta o atascada | Nuestro clasico | Sin plazo comun de herramienta (ubicacion hasta 50 s, shell 60 s); con la pulsacion, hoy ninguna espera, propuesta Q1 2 s y P1' | Si al llegar a `cutTurn`; con P1', el parcial tardio se descarta | Steer si llega a `cutTurn` a tiempo; con P1' se descarta la tardia | Linea "trabajando" a 1 s; luego silencio hasta que vuelva la herramienta |
| Stop explicito | Industria | El mismo `interrupt()` con el mismo plazo; el cierre fuerza la interrupcion | Si, el turno cerrado como interrumpido (Pipecat `CancelFrame`) | Ninguna documentada | Silencio; la sesion queda escuchando o termina |
| Stop explicito | Nuestro clasico | Mismo camino que la pulsacion, y cuelga | Si, frases que sonaron | Si: steer "para corregir el rumbo" en el siguiente turno, cuando sea, mas el evento de isla | Silencio, voz apagada |
| Stop explicito | Nuestro realtime | Ninguna | Igual que barge-in | Solo el evento de isla "la usuaria interrumpio" | Silencio, sigue escuchando |

### (c) Deben Q1 y Q3 variar por causa?

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| R1. Una sola regla: plazo inyectable de 2 s y P1' para todo corte de turno clasico, y Q3 igual para pulsacion, barge-in y stop | Es lo que hacen LiveKit y Pipecat; la espera depende de DONDE esta el turno cortado (stream: ms; herramienta: hasta 50 s), no de por que se corto; un solo test | El stop no necesita esperar a nadie (no hay turno siguiente inmediato), pero esperar no le cuesta nada | baja | Recomendada para Q1, Q2 y Q3 |
| R2. Plazo por causa (p. ej. 0 s para stop, 2 s para pulsacion, otro para herramienta) | Afina cada caso | La causa no esta en el turno cortado sino en quien lo corto; ninguna referencia lo hace; mas estados y tests; la herramienta atascada se resuelve mejor con su propio plazo | media | No |
| R3. R1 mas nota por causa: steer solo tras pulsacion o barge-in; el stop no deja nota de "corregir el rumbo" | La nota describe lo que paso; el stop explicito no es una correccion de rumbo y ninguna referencia anade nota por un stop | Toca la decision 15b-11 de cuando nace la nota; es otro cambio, no el de Q1 | baja-media | A decidir por Karen, en PR aparte |
| R4. R1 mas plazo comun por herramienta en clasico (como Pipecat o Vapi) con respuesta del modelo al vencer | Es la respuesta de la industria a la causa "herramienta atascada" | Fuera del alcance de la serializacion; necesita su propio brief | media | Seguimiento, no ahora |

Recomendacion concreta por causa:

- Pulsacion o barge-in con la red bien: Q1 = 2 s inyectable; al vencer, P1'; Q3 como esta propuesto (un turno cortado durante su oido no deja rastro, como LiveKit no guarda la frase de una respuesta que no llego a programarse).
- Caida de red: Q1, Q2 y Q3 no aplican. En clasico la red no cancela el turno; en realtime C2 ya separa este caso con su propia compuerta (`realtimeGeneration`) y su propia nota. No cambiar nada en este PR.
- Herramienta lenta o atascada: la misma regla de Q1 y P1'. Es justo el caso para el que existe el plazo. El arreglo que usa la industria para esta causa es un plazo propio de la herramienta, y queda como seguimiento (R4).
- Stop explicito: la misma regla. No hay turno siguiente que esperar al instante, y si llega una pulsacion pronto, la espera acotada la cubre. Lo que si conviene variar es la nota (R3), no el plazo.

## 6. Evidencia en contra

- Lo mas fuerte contra una sola regla: Pipecat si distingue por causa en las herramientas: el plazo de la herramienta corre inferencia y la interrupcion no [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/frames/frames.py#L1472-L1484@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Se resuelve: esa distincion es entre "la herramienta vencio" e "interrupcion", dos eventos distintos; la espera tras interrumpir sigue siendo una sola, la de `__cancel_process_task()` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/frame_processor.py#L1129-L1148@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Y Q1 es la espera tras interrumpir, no un plazo de herramienta; nuestra ronda de herramientas clasica no tiene un plazo comun que vencer [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:58]
- Contra la nota steer en general: ninguna referencia anade una nota en prosa por un barge-in con palabras; LiveKit solo marca `interrupted` en el mensaje [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3344-L3349@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Se acepta: la nota es una decision de producto previa (15b-11) y no es lo que se decide aqui; lo que el hallazgo cambia es el stop, donde la nota describe algo falso ("para corregir el rumbo") [repo:Sources/CompanionCore/Perception/ContextBlock.swift:204]
- Contra P1' (descartar la escritura tardia): la regla de arquitectura pide cancelacion estructurada y no contadores de generacion [repo:docs/ARCHITECTURE.md:79]
- Se resuelve: el codigo ya tiene tres compuertas por la misma razon, entre ellas `realtimeGeneration` (#59) para lo que escribe un socket muerto [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:128]
- Y la industria hace lo mismo: LiveKit salta los eventos de una respuesta descartada [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/llm/_realtime/openai.py#L282-L285@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Y Retell descarta todas las respuestas de un `response_id` anterior [doc:https://docs.retellai.com/api-references/llm-websocket@2026-10-01]
- Contra Q3 (sin rastro): perder las palabras de la usuaria puede parecer peor que una nota tardia [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:258]
- Se acepta con matiz: LiveKit tampoco guarda la frase de una respuesta interrumpida antes de programarse, pero ese paralelo no es exacto (su turno de usuaria lo cierra el detector, no una pulsacion), y la decision sigue siendo de Karen [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L3618-L3624@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, una sola puerta para todo origen de interrupcion: el origen va a la traza, el comportamiento no cambia [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L201-L227@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]

```python
# livekit-agents voice/speech_handle.py @ d251b89 (abridged)
def interrupt(self, *, force=False, source="programmatic"):
    if self.interrupted or self.done():
        return self
    if not force and not self._allow_interruptions:
        raise RuntimeError("This generation handle does not allow interruptions")
    self._interrupt_source = source   # first interrupt only, for the trace
    self._cancel()                    # same 5 s INTERRUPTION_TIMEOUT for every source
    return self
```

- Bien hecho, el plazo de la herramienta separado de la interrupcion: solo el plazo propio pide respuesta al modelo [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/processors/aggregators/llm_response_universal.py#L2122-L2133@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Bien hecho, nota que dice la causa real: reply_cut aclara que fue la red y no la usuaria, distinta de steer [repo:Sources/CompanionCore/Session/TurnContext.swift:49]
- Bien hecho, compuerta de generacion para escrituras tardias que la cancelacion no alcanza (precedente directo de P1') [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:128]
- Anti-ejemplo: la nota "corto para corregir el rumbo" tras un stop explicito, que no corrige nada; nace del mismo `cutTurn` que la pulsacion [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:450]
- Anti-ejemplo: barge-in en realtime por WebSocket sin `conversation.item.truncate`; la doc lo pone a cargo del cliente [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]

## 8. Trampas

- La causa no viaja con el turno cortado: `cancelClassicTurn` es igual para pulsacion, barge-in y stop; un plazo por causa exigiria pasar la causa por `.cancelAgentOutput` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:74]
- `steerPending` sobrevive a un colgado: tras un stop, la nota aparece en el siguiente turno aunque llegue minutos despues [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:94]
- Con P1', una compuerta que descarte la escritura tardia de `cutTurn` tambien descarta su nota steer; si el turno nuevo ya empezo, nadie la recibe, como hoy cuando llega tarde [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:450]
- En realtime el parcial de red es la transcripcion generada; ponerla como "lo oido" en la nota puede hacer que el modelo no repita lo que la usuaria nunca oyo [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:143]
- Truncar en realtime exige medir lo reproducido: un `audio_end_ms` mayor que el audio da error, por eso Pipecat usa el minimo entre tiempo y duracion [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Contexto app clasica: la regla unica actua sobre pulsacion, barge-in y stop; la caida de red no pasa por `cutTurn` y no la toca [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:356]
- Contexto app realtime: nada de Q1, Q2 o Q3 corre ahi; el barge-in usa `response.cancel` y la red usa `realtimeGeneration` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:270]
- Contexto `swift test` y CI: el plazo debe ser inyectable o el test de la herramienta atascada depende del reloj; ver el brief anterior [repo:docs/research/classic-turn-serialize.md:262]
- Contexto TSan: este brief no anade estado compartido; si R3 cambia como nace la nota, el flag sigue bajo el `Mutex` existente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:88]

## 9. Incertidumbre

- ASSUMPTION: tras `response.cancel`, el servidor de OpenAI manda `output_audio_transcript.done` con el texto generado hasta el corte, y nuestro hilo realtime enhebra ese texto entero (no lo oido) en un barge-in. prueba: en la app realtime, cortar a mitad de una respuesta larga con el log de eventos del servidor activo y comparar el texto enhebrado con lo que sono
- ASSUMPTION: LiveKit, al reconectar con una respuesta a medias, enhebra lo que alcanzo a reenviar como mensaje NO interrumpido. prueba: leer `_realtime_generation_task_impl` de agent_activity.py en d251b89 cuando la generacion se cierra por "session reconnection"
- ASSUMPTION: Vapi y Retell no documentan que se escribe en el contexto ni que nota se da al modelo segun la causa; solo el `response_id` de Retell y los mensajes de herramienta de Vapi. prueba: buscar en docs.vapi.ai y docs.retellai.com "transcript" e "interrupted" en las paginas de mensajes y del websocket
- ASSUMPTION: aparte de shell (60 s), lectura de URL (30 s) y ubicacion (hasta 50 s), ninguna herramienta padre del camino clasico tiene plazo propio (por ejemplo `open_app`). prueba: `grep -rn -i "timeout\|Duration" Sources/CompanionServices/Tools` y revisar cada ejecutor de `ParentToolRunner`
- ASSUMPTION: la falta de nota por un barge-in en LiveKit no se compensa en el prompt del proveedor con el flag `interrupted`. prueba: leer como el formateador de chat de LiveKit para OpenAI serializa `ChatMessage.interrupted` en d251b89
- [NEEDS CLARIFICATION: Q1 y Q2. Recomendacion: una sola regla para toda causa (plazo inyectable de 2 s y P1'), como LiveKit y Pipecat. Karen confirma o pide plazo por causa.]
- [NEEDS CLARIFICATION: Q3. Recomendacion: misma semantica para pulsacion, barge-in y stop; no aplica a la red. Karen confirma que las palabras de un hold cortado antes de llegar al modelo no se guardan.]
- [NEEDS CLARIFICATION: R3. Un stop explicito (Esc, Stop, "para") deja hoy la nota "corto para corregir el rumbo" en el siguiente turno, aunque llegue mucho despues. Quitarla tras un stop, en un PR aparte?]
- [NEEDS CLARIFICATION: en clasico, una caida de red a mitad de habla se enhebra como respuesta completa, sin nota ni aviso, al contrario que en realtime. Igualarlo con C2 es seguimiento o se deja?]
- [NEEDS CLARIFICATION: en realtime, el barge-in no manda `conversation.item.truncate`, que la doc de OpenAI pone a cargo del cliente por WebSocket. Abrir seguimiento?]

## 10. Checklist de estandar

- [ ] El plazo de espera del turno nuevo es uno solo para toda causa de corte, inyectable como `slowToolWait`, con valor por defecto 2 s
- [ ] Al vencer, la compuerta de generacion descarta el parcial y la nota tardios del turno cortado, siguiendo el patron de `realtimeGeneration`, y el vencimiento deja una linea en `Log.app`
- [ ] Un test cubre la pulsacion sobre una herramienta atascada, y otro el stop explicito sobre la misma, con el mismo resultado de orden en el hilo
- [ ] El modo realtime y su camino de reconexion (C2) no cambian en este PR
- [ ] El CHANGELOG dice que la regla es la misma para pulsacion, barge-in y stop
- [ ] Si Karen aprueba R3, otro PR hace que un stop explicito no deje la nota steer, con un test que lo pruebe
- [ ] Los seguimientos (plazo comun por herramienta en clasico, truncate en realtime, aviso de red en clasico) quedan anotados, no implementados aqui

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Realtime conversations (guia) | OpenAI | pagina viva | 2026-10-01 | high |
| 2 | Realtime client events (referencia) | OpenAI | pagina viva | 2026-10-01 | high |
| 3 | Turns overview | LiveKit | pagina viva | 2026-10-01 | high |
| 4 | LiveKit Agents: speech_handle.py, agent_activity.py, agent_session.py, generation.py, llm/_realtime/openai.py | LiveKit | d251b89 | 2026-10-01 | high |
| 5 | Pipecat: frames.py, frame_processor.py, llm_service.py, llm_response_universal.py, empty_user_turn.py, base_object.py, task_manager.py, openai/realtime/llm.py | Daily (pipecat-ai) | da37523 | 2026-10-01 | high |
| 6 | LLM WebSocket; Debug call disconnection | Retell AI | pagina viva | 2026-10-01 | medium |
| 7 | Get Tool (referencia API) | Vapi | pagina viva | 2026-10-01 | medium |
| 8 | server-sdk-typescript: StopSpeakingPlan.ts, ToolMessageDelayed.ts, ToolMessageFailed.ts | VapiAI (Fern) | dfa08b8 | 2026-10-01 | medium |
| 9 | Codigo de companion-next (voz clasica y realtime, maquinas de turno y sesion) | propio | dfd3aeb | 2026-10-01 | high |
| 10 | Brief classic-turn-serialize | propio | 2026-10-01 | 2026-10-01 | high |
