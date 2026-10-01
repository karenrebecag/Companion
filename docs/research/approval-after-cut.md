# Reference Brief: aprobacion despues del corte (approval-after-cut)

Slug: approval-after-cut | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

En modo voz clasico, una hoja de permiso puede quedar estacionada dentro de un turno que la usuaria ya corto (pulsacion, barge-in o stop). Si la hoja se contesta "si" despues, la accion se ejecuta igual. Como debe revalidar el turno despues de esperar la aprobacion, para que nunca corra una accion de un turno abandonado, y si la hoja estacionada debe retirarse cuando el turno se corta.

Decisiones:

- D1: donde va la revalidacion. En `actRound`, entre la aprobacion y `execute`, contestando el mismo turno de herramienta "cancelled: the user interrupted"; o en `ParentToolGuard`, para que la hereden todos los que llaman (clasico, realtime, bridge); o en los dos sitios.
- D2: que pasa con la hoja estacionada al cortar el turno clasico. Retirarla con `withTaskCancellationHandler` mas `withdraw`; dejarla abierta e inerte; o cerrarla en la UI cuando la espera termina.
- D3: si realtime recibe el mismo arreglo en este PR o en uno aparte.

Decision de Karen (2026-10-01): al cortar con una hoja pendiente, la tarjeta desaparece y "tiene que existir una linea de estado o indicador de interrupted que le diga al usuario por que dejo de escuchar", sin tecnicismos. En realtime, un barge-in tambien retira la hoja del padre: "si que desaparezca, pero hay que informar al usuario sin tecnicismos". El texto va por el catalogo Localized en es y en. El "si" hablado a hojas del padre en clasico sigue abierto. [KAREN:chat 2026-10-01 via orquestador]

Hallazgo que cambia el planteamiento: el actor `Approvals` de produccion ya resuelve como denegada la espera de un turno cancelado (seccion 2). El hueco real es mas angosto que "si despues del corte siempre ejecuta": es una ventana TOCTOU y una hoja que queda en pantalla sin efecto. El fake de los tests ignora la cancelacion, y por eso el test RED la reproduce de punta a punta.

Nota de procedencia: ADR 008 (contadores de generacion) no esta en `origin/main` d563ca3; solo existe en la rama `origin/fix/classic-turn-serialize`, leida con `git show`. Este brief no propone ningun contador nuevo, asi que no depende de ella.

## 2. Estado actual

- `actRound` comprueba `Task.isCancelled` solo al empezar cada llamada y contesta "cancelled: the user interrupted" [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:58]
- Despues espera a `parentGuard.check`, que puede quedar estacionado en la hoja [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:65]
- Cuando `check` devuelve nil, `parentTools.execute` corre sin volver a mirar la cancelacion [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:69]
- La ronda corre dentro de un `withTaskGroup`, asi que la cancelacion del turno llega a `actRound` de forma estructurada [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:70]
- El turno clasico es su propia `Task`, guardada en `classicTurnTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- `cancelClassicTurn` cancela esa tarea; es lo que corre ante `.cancelAgentOutput` en clasico [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:32]
- `.cancelAgentOutput` en clasico llama a `cancelClassicTurn`; en realtime llama a `realtime.cancelAgent()` y no cancela ninguna tarea [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:72]
- Una pulsacion en `.thinking` o `.speaking` del clasico corta el turno con `cutClassicTurn` [repo:Sources/CompanionCore/Session/TurnMachine.swift:76]
- `interrupt` (Stop, "para") en clasico tambien emite `.cancelAgentOutput` [repo:Sources/CompanionCore/Session/TurnMachine.swift:137]
- `ParentToolGuard.verdict` espera la respuesta de la hoja con `answer` [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:68]
- Con un si, el guard llama a `tools?.granted(request)` antes de devolver, sin mirar la cancelacion [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:69]
- `granted` convierte el ticket estacionado en uno gastable [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:156]
- Un ticket concedido vive hasta 60 s si no se gasta [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:99]
- El gancho `parked:` corre justo antes de mostrar la hoja y puede vetarla [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:105]
- `answer` espera en `approvals.request` [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:107]
- `withdraw` resuelve como denegada una hoja estacionada, a traves del mismo proveedor [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:118]
- El actor `Approvals` de produccion devuelve denegado si la tarea ya estaba cancelada al pedir [repo:Sources/CompanionServices/Approvals/Approvals.swift:36]
- `Approvals.request` envuelve la espera en `withTaskCancellationHandler` [repo:Sources/CompanionServices/Approvals/Approvals.swift:44]
- Su `onCancel` lanza una `Task` no estructurada que resuelve la hoja como denegada [repo:Sources/CompanionServices/Approvals/Approvals.swift:60]
- La app usa ese actor real para la voz [repo:Sources/CompanionApp/CompanionMainVoice.swift:136]
- El fake `ScriptedApprovals(park: true)` espera en una continuacion sin manejar la cancelacion [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:191]
- No hay test de `Approvals` que cubra la cancelacion; la lista de tests no incluye ninguno [repo:Tests/CompanionServicesTests/ApprovalsTests.swift:10]
- El guard de la voz anuncia la hoja con `.job(.approvalRequested(request))` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:328]
- El mismo guard se comparte entre realtime y clasico [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:336]
- La tarjeta queda en `approvalQueue` hasta que algo la quita [repo:Sources/CompanionCore/Session/SessionMachine+Jobs.swift:181]
- `.approvalSettled` quita la tarjeta sin resolver nada [repo:Sources/CompanionCore/Session/SessionMachine.swift:131]
- El camino MCP de la voz emite `.approvalSettled` cuando la decision vuelve [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:39]
- El chat escrito emite `.approvalSettled` despues de `approvals.request` [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:255]
- El chat escrito retira las hojas propias del padre cuando cambia de turno [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:264]
- Los frenos del reductor (`stop`, `stopVoice`) niegan las peticiones sin dueno, entre ellas la hoja del padre [repo:Sources/CompanionCore/Session/SessionMachine+Brakes.swift:67]
- Precedente bridge: el guard recibe `parked:` y despues `settleCurrent` [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:163]
- Precedente bridge: tras el veredicto, un epoch distinto descarta la llamada [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:164]
- Precedente bridge, guardia M4: un si que llega con la conexion cerrada no ejecuta nada [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:172]
- Precedente bridge: `stop()` retira la hoja estacionada ("Stop hands", spec 3 "Corte") [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:252]
- Realtime: el manejador de `functionCall` hace `parentGuard.check` y luego `execute`, con la misma forma check-then-execute [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:393]
- Realtime: `execute` corre sin volver a mirar la cancelacion [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:397]
- Realtime: `handle` se llama en linea dentro del bucle de eventos, uno tras otro [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:136]
- Realtime: ese bucle vive en `eventTask`, marcado con `realtimeGeneration` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:17]
- Realtime: solo `closeRealtime` cancela `eventTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Teardown.swift:18]
- Realtime: un barge-in emite `.cancelAgentOutput` y abre el micro, sin cancelar el manejador [repo:Sources/CompanionCore/Session/TurnMachine.swift:79]
- La arquitectura pide cancelacion estructurada y no contadores de generacion [repo:docs/ARCHITECTURE.md:79]
Contextos: app en produccion con el actor `Approvals` real (clasico y realtime); `swift test` con `ScriptedApprovals`, que no atiende la cancelacion; job de CI con ThreadSanitizer sobre la suite completa; bridge MCP hacia clientes externos (comparte `ParentToolGuard` pero no la voz); chat escrito, que no usa `ParentToolGuard` y tiene su propia espera.

## 3. Fuentes primarias

- CWE-367 define TOCTOU como comprobar el estado de un recurso antes de usarlo cuando ese estado puede cambiar entre la comprobacion y el uso [doc:https://cwe.mitre.org/data/definitions/367.html@4.20]
- CWE-367 da como mitigacion volver a comprobar y hacer que lo comprobado sea lo mismo que se usa [doc:https://cwe.mitre.org/data/definitions/367.html@4.20]
- La guia de codigo seguro de Apple llama time-of-check-time-of-use al hueco entre comprobar una condicion y actuar, aunque dure una fraccion de segundo [doc:https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html@archive-2016]
- SE-0304 dice que la cancelacion es cooperativa: no tiene efecto hasta que algo la comprueba, por ejemplo con `Task.isCancelled` [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md@5.5]
- La fuente de `withTaskCancellationHandler` en Swift 6.2 dice que el handler corre de inmediato al cancelar y en concurrencia con la operacion [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]
- La misma fuente sugiere que el handler marque una bandera que la operacion compruebe de forma atomica antes de hacer trabajo real [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]

## 4. Implementaciones de referencia

- OpenAI Agents SDK (Python), mantenido por OpenAI, unos 29.8k estrellas, push el 2026-10-01: `approve_tool_call` sale sin hacer nada si la sesion esta cerrandose o cerrada [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- En ese SDK la aprobacion pendiente es un registro que se saca con `pop`; aprobar un id que ya no esta no ejecuta nada [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Al cerrar la sesion, `_cleanup` cancela las tareas de herramientas y vacia `_pending_tool_calls` [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- En cambio, su `interrupt()` solo envia la interrupcion al modelo y no toca las aprobaciones pendientes [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Pipecat, el framework de agentes de voz de pipecat-ai, unos 16.1k estrellas, push el 2026-10-01: ante una `InterruptionFrame` cancela las llamadas a funcion registradas con `cancel_on_interruption` [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py@da37523]
- En Pipecat ese valor cae a True si nadie lo fija: por defecto, interrumpir cancela la llamada en curso [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py@da37523]
- Pipecat entrega `CancelledError` al handler y emite `FunctionCallCancelFrame` para que el resto del pipeline cierre la llamada [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py@da37523]
- LangGraph, de LangChain, unos 42.6k estrellas, push el 2026-10-01: `interrupt()` detiene el grafo, y al reanudar el nodo se re-ejecuta desde el principio, asi que todo lo anterior a la aprobacion vuelve a evaluarse [ref:https://github.com/langchain-ai/langgraph/blob/b36b1d58a8b408455b512cfad3b1b26e02927282/libs/langgraph/langgraph/types.py@b36b1d5]

## 5. Opciones

D1, donde va la revalidacion:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `Task.isCancelled` en `actRound` justo antes de `execute` | Diff minimo; misma respuesta "cancelled"; cubre tambien las esperas sin hoja de `check` (`bound`, `actsWithoutSheet`, `remembered`) | `granted` ya corrio y deja un ticket gastable hasta 60 s; realtime y bridge no lo heredan | baja | parte de C |
| B. En `ParentToolGuard.verdict`: si la respuesta es si pero la tarea esta cancelada, devolver denegacion sin `granted` | Un solo punto para clasico, realtime y bridge; no deja ticket concedido | Con el texto actual, el modelo recibiria "denied by user" en vez de "cancelled"; un caso nuevo de `SheetAnswer` no debe contar como negativa del bridge | baja-media | parte de C |
| C. B mas A | El guard no concede nada a un turno muerto, y la ultima comprobacion antes del efecto queda lo mas tarde posible | Dos comprobaciones; hay que mantenerlas alineadas | baja-media | **Recomendada** |

D2, la hoja estacionada al cortar:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `withTaskCancellationHandler` mas `withdraw` en el clasico | Explicito en el sitio del turno | Repite lo que `Approvals.request` ya hace al cancelar; no quita la tarjeta de la UI, porque `withdraw` solo resuelve el actor | media | No |
| B. Dejarla abierta e inerte (hoy, con el actor real) | Cero codigo | Tarjeta viva que no hace nada: el clic no tiene efecto y nadie lo dice; queda hasta otro freno o una respuesta | nula | No |
| C. Cerrar la tarjeta cuando la espera del guard termina, emitiendo `.approvalSettled(requestId)` como ya hacen MCP y el chat | Simetrico con dos caminos existentes; la tarjeta se va sola al cancelar y es inocuo tras un clic (`remove` de un id ausente no hace nada) | Necesita el id de la peticion en la voz (via `onRequest` o `parked:`); toca tambien realtime por compartir guard | baja | **Recomendada** |

D3, realtime:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Mismo PR: la comprobacion en el guard (D1-B) ya cubre el cierre de realtime | Sin codigo extra en realtime; un test de cierre lo fija | No resuelve el barge-in de realtime, que no cancela nada | baja | **Recomendada para el cierre** |
| B. PR aparte para el barge-in de realtime | Decision de producto separada: el SDK de OpenAI conserva las aprobaciones al interrumpir; el bucle de eventos queda bloqueado mientras la hoja espera | Deja el barge-in de realtime como esta mientras tanto | media | **Recomendada para el barge-in** |
| C. Todo en este PR | Un solo cambio | Mezcla una correccion de seguridad con un cambio de semantica que pide decision de Karen | alta | No |

## 6. Evidencia en contra

- En la app, el actor real ya deniega la espera de un turno cancelado, asi que el caso "si despues del corte ejecuta" no es el camino normal [repo:Sources/CompanionServices/Approvals/Approvals.swift:44]
- Se resuelve asi: ese `onCancel` resuelve en una `Task` suelta, y un clic que llegue antes al actor gana con un si; un si ya entregado antes de cancelar tambien sigue hasta `execute` [repo:Sources/CompanionServices/Approvals/Approvals.swift:60]
- Se resuelve tambien porque Swift hace la cancelacion cooperativa: sin una comprobacion despues de la espera, nada impide el efecto [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md@5.5]
- Una comprobacion extra nunca cierra la ventana del todo; CWE-367 recomienda que lo comprobado sea lo mismo que se usa [doc:https://cwe.mitre.org/data/definitions/367.html@4.20]
- Se acepta: el resto de la ventana vive dentro de `execute`, cuyas propias guardias releen el destino justo antes de actuar [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:7]
- Descartar un si real tira un consentimiento que la usuaria si dio [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:69]
- Se resuelve: ese consentimiento era para un turno que ella misma abandono, y el SDK de OpenAI ignora las aprobaciones que llegan con la sesion cerrandose [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- En clasico, el "si" hablado llega en una pulsacion posterior, y una pulsacion en `.thinking` o `.speaking` corta el turno; retirar la hoja al cortar podria matar la misma respuesta que se queria dar [repo:Sources/CompanionCore/Session/TurnMachine.swift:76]
- Sin resolver: si el turno estacionado esta en `.thinking` o `.speaking`, el `onCancel` del actor real ya denegaria la hoja hoy con esa pulsacion; es una hipotesis a probar y una pregunta para Karen, ambas en la seccion 9 [repo:Sources/CompanionServices/Approvals/Approvals.swift:60]
- El SDK de OpenAI no retira aprobaciones pendientes ante una interrupcion, solo al cerrar: es evidencia contra tratar el barge-in de realtime como abandono [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Se acepta acotando D3: este PR cubre el cierre de realtime y deja el barge-in para un PR con decision propia [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:72]
- Pipecat, en cambio, cancela por defecto la llamada al interrumpir; las dos referencias no coinciden en el barge-in, y por eso no se adopta un patron para ese caso [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py@da37523]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, en el propio repo: el bridge vuelve a validar despues del veredicto y antes de `execute`, y registra que no ejecuto nada [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:172]

```swift
// BridgeSession+Calls.swift, guardia M4, citado tal cual
guard current?.isOpen ?? true else {
    Log.bridge("call approved after the client left; nothing executed")
    return .dropped
}
let outcome = await tools.execute(name: call.name, argumentsJSON: call.argumentsJSON)
```

- Bien hecho, referencia externa: aprobar comprueba primero si la sesion sigue viva [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]

```python
# openai-agents-python, RealtimeSession.approve_tool_call
if self._closing or self._closed:
    return
pending = self._pending_tool_calls.pop(call_id, None)
if pending is None:
    return
```

- Bien hecho, cancelacion por defecto ante una interrupcion en un agente de voz [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/services/llm_service.py@da37523]

```python
# pipecat, LLMService._handle_interruptions
for function_name, entry in self._functions.items():
    if entry.cancel_on_interruption:
        await self._cancel_function_call(function_name)
```

- Bien hecho, cerrar la tarjeta al volver la espera, en el camino MCP de la voz [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:39]
- Anti-ejemplo, el hueco de este brief: comprobar al entrar a la llamada y ejecutar despues de una espera larga sin volver a mirar [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:69]
- Anti-ejemplo, la misma forma en realtime [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:397]

## 8. Trampas

- Un test con `ScriptedApprovals` no ve el `onCancel` del actor real: el fake ignora la cancelacion, y eso es justo lo que hace reproducible el si tardio [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:191]
- Un test solo con el actor real casi nunca falla, porque el `onCancel` suele ganar la carrera; el RED tiene que usar el fake [repo:Sources/CompanionServices/Approvals/Approvals.swift:60]
- Si la comprobacion va solo en `actRound`, `granted` ya dejo un ticket gastable de hasta 60 s [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:149]
- Contestar con la negativa del guard en vez de "cancelled: the user interrupted" le dice al modelo que la usuaria nego, cuando en realidad interrumpio [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:60]
- Toda llamada de la ronda necesita su turno de herramienta, o la ronda queda mal formada; la rama nueva tambien debe agregar uno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:57]
- En el bridge, una respuesta nueva no debe contar como negativa del cool-down; hoy solo cuenta `.denied` [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:201]
- Un contador de generacion para esto chocaria con la regla de cancelacion estructurada; `Task.isCancelled` es la senal estructurada que la regla pide [repo:docs/ARCHITECTURE.md:79]
- `withTaskCancellationHandler` corre su handler en concurrencia con la operacion; un segundo handler en el clasico que llame a `withdraw` competiria con el del actor por el mismo id [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]
- Realtime: mientras el manejador espera la hoja, el bucle de eventos no lee el siguiente evento, porque `handle` se llama en serie [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:127]
- Contexto app: el actor real ya deniega al cancelar; la recomendacion cierra la ventana restante y quita la tarjeta [repo:Sources/CompanionApp/CompanionMainVoice.swift:136]
- Contexto `swift test`: el fake no deniega al cancelar; la recomendacion es la unica barrera y el RED lo demuestra [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:187]
- Contexto CI con TSan: la comprobacion no agrega estado compartido, solo lee la cancelacion de la tarea actual [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md@5.5]
- Contexto bridge: hereda la comprobacion del guard; su tarea no se cancela al cerrar la conexion (usa epoch e `isOpen`), asi que el cambio no altera su comportamiento hoy [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:164]
- Contexto chat escrito: no pasa por `ParentToolGuard`, asi que D1-B no lo cubre; ya cierra la tarjeta y retira las hojas al cambiar de turno [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:254]

## 9. Incertidumbre

- ASSUMPTION: mientras un turno clasico espera la hoja, el estado es `.thinking` o `.speaking`, asi que una pulsacion para decir "si" corta el turno y el actor real deniega la hoja antes de que llegue la respuesta hablada. prueba: test de `VoiceSession` clasico con el actor `Approvals` real: estacionar una llamada `open_url` no dicha, pulsar, leer `machine.snapshot.state` y la respuesta de `request`.
- Evidencia estatica de esa hipotesis (lectura de codigo; el test de caracterizacion es el primer punto de la seccion 10, porque research-gate cuenta los tests como codigo y no deja escribirlo antes de aprobar este brief). Cuatro eslabones:
  - La hoja del padre si se arma para un "si" hablado: el guard de voz llama `noteApproval` y el comentario dice que queda estacionada para el "si" hablado como la de un trabajo [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:323] [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:329]
  - Pero solo la peticion de un trabajo se dice en voz alta: `askApprovalAloud` corre en el `onEvent` del trabajo y en ningun otro sitio [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:303], y `approvalAnnounced` solo lo llama `markQuestionSaid`, que exige una pregunta dicha por ese camino [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:97]
  - Sin anuncio, `announcedAt` queda en nil y `SpokenYes.admits` devuelve falso sea cual sea el momento, asi que el "si" hablado contesta `.needsClick` [repo:Sources/CompanionCore/Session/Acknowledgement.swift:60]
  - Ademas, pulsar en `.thinking` o `.speaking` clasico corta el turno [repo:Sources/CompanionCore/Session/TurnMachine.swift:76] y el `onCancel` del actor real niega la hoja antes de que existan las palabras de la nueva pulsacion [repo:Sources/CompanionServices/Approvals/Approvals.swift:59]
  - Conclusion probable, no verificada en ejecucion: en clasico, un "si" hablado a una hoja del padre nunca ha funcionado; solo el clic.
- [NEEDS CLARIFICATION: pregunta de producto. Debe funcionar un "si" hablado para las hojas del padre en clasico, como dice el comentario de VoiceSession.swift:323, o la intencion es solo clic? Si debe funcionar, es un bug propio en otro PR: falta anunciar la hoja y que la pulsacion de respuesta no la niegue.]
- ASSUMPTION: la carrera en la que el clic gana al `onCancel` del actor real es alcanzable en la app. prueba: test con `Approvals` real que cancela la tarea y llama `resolve(approved: true)` seguidos, repetido N veces, contando cuantas veces la respuesta sale aprobada.
- ASSUMPTION: un ticket concedido a un turno cortado no se puede gastar en el turno siguiente sin una hoja nueva. prueba: test de `ParentToolRunner` que llama a `granted` y luego `execute` con la misma llamada desde otro turno, sin pasar por `approval(for:said:)`.
- ASSUMPTION: con el bucle de realtime bloqueado en la hoja, un `resolve_approval` hablado o un evento de voz del servidor quedan detenidos hasta que la hoja se resuelve. prueba: test de `VoiceSession` realtime con transporte falso que estaciona una llamada y empuja un segundo evento.
- ASSUMPTION: el bridge no cancela la tarea de `performCall` al cerrar la conexion, asi que la comprobacion del guard no cambia su comportamiento. prueba: correr la suite `Bridge*Tests` con el cambio y comprobar que ningun test cambia de resultado.
- Resuelto por Karen: al cortar, la tarjeta desaparece con una linea de estado sin tecnicismos que diga por que dejo de escuchar. [KAREN:chat 2026-10-01 via orquestador]
- Resuelto por Karen: en realtime, un barge-in retira la hoja del padre (la forma de Pipecat), con el mismo aviso. [KAREN:chat 2026-10-01 via orquestador]

## 10. Checklist de estandar

- [ ] Primero, test de caracterizacion con el actor `Approvals` real: hold, una llamada `open_url` no dicha estaciona la hoja del padre, nueva pulsacion con "si", y se afirma el resultado actual (se espera denegada o `.needsClick`, sin `execute`). Su resultado reemplaza la evidencia estatica de la seccion 9.
- [ ] Aviso de interrupcion, segun la decision de Karen: cuando una hoja del padre se retira por un corte (clasico o barge-in de realtime), la tarjeta sale y la isla muestra un aviso sin tecnicismos de por que dejo de escuchar. Precedente a reusar: el aviso `island.replyCut` de C2, que la isla muestra con su estado propio y que vive en el catalogo es/en [repo:Sources/CompanionUI/es.lproj/Localizable.strings:699]; claves nuevas en los dos `Localizable.strings`, con test de completitud del catalogo.
- [ ] Test RED, clasico: con `ScriptedApprovals(park: true)`, un turno estaciona una llamada en la hoja, la tarea del turno se cancela, despues se aprueba con `resolve(approved: true)`, y `execute` no corre ni una vez.
- [ ] En ese test, la llamada recibe su turno de herramienta con "cancelled: the user interrupted", y la ronda tiene una respuesta por llamada.
- [ ] El test falla en `origin/main` d563ca3 antes del cambio y pasa despues.
- [ ] Test del guard: con la tarea cancelada y la hoja aprobada, `verdict` devuelve denegacion y `granted` no se llama.
- [ ] Test de realtime: con la llamada estacionada, `closeRealtime` cancela `eventTask`, el si posterior no ejecuta nada.
- [ ] Test del bridge: la respuesta nueva del guard no cuenta como negativa del cool-down.
- [ ] Test de UI: cuando la espera del guard termina en voz, se emite `.approvalSettled` con el id de la peticion, y `approvalQueue` queda sin esa tarjeta.
- [ ] Test de `Approvals` (hoy no existe): una peticion de una tarea cancelada mientras espera vuelve denegada.
- [ ] No se agrega ningun contador de generacion; la revalidacion usa `Task.isCancelled`.
- [ ] La suite completa pasa tambien en el job de ThreadSanitizer.
- [ ] El barge-in de realtime queda fuera de este PR, con su propio ticket y la decision de Karen.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | CWE-367 Time-of-check Time-of-use Race Condition | MITRE | CWE 4.20 | 2026-10-01 | high |
| 2 | Secure Coding Guide, Race Conditions and Secure File Operations | Apple | archivo | 2026-10-01 | high |
| 3 | SE-0304 Structured Concurrency | Swift Evolution | Swift 5.5 | 2026-10-01 | high |
| 4 | TaskCancellation.swift (withTaskCancellationHandler) | swiftlang/swift | swift-6.2-RELEASE | 2026-10-01 | high |
| 5 | openai-agents-python, src/agents/realtime/session.py | OpenAI | 28e9f4f | 2026-10-01 | high |
| 6 | pipecat, src/pipecat/services/llm_service.py | pipecat-ai | da37523 | 2026-10-01 | high |
| 7 | langgraph, libs/langgraph/langgraph/types.py | LangChain | b36b1d5 | 2026-10-01 | medium |
