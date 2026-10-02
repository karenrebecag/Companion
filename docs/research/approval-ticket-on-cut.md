# Reference Brief: ticket concedido a un turno cortado (approval-ticket-on-cut)

Slug: approval-ticket-on-cut | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Despues de PR #87, `ParentToolGuard.verdict` llama a `tools?.granted(request)` cuando la hoja dice si y la tarea no esta cancelada; `actRound` vuelve a mirar `Task.isCancelled` antes de `execute` y, si la tarea ya esta cancelada, contesta `.interrupted` sin ejecutar. El ticket concedido queda gastable hasta 60 s. Lo mismo pasa con el ticket que `handsApproval` emite sin hoja en el camino `.act`. La revision de seguridad lo califico MEDIUM y pidio "drop the ticket on actRound's cancel branch".

Reusa `approval-after-cut` (APROBADO), que dejo en su seccion 9 como supuesto sin probar "un ticket concedido a un turno cortado no se puede gastar en el turno siguiente sin una hoja nueva". Este brief no repite su analisis de la hoja ni del aviso de corte.

Decisiones:

- D1: forma del arreglo. (a) `withdraw(_ call:)` en `ParentToolExecuting` con default no-op, implementado por los runners con tickets y el composite, y llamado en la rama de corte; (b) sacar `granted` de `verdict` y que cada caller lo llame justo antes de `execute`, despues de su recheck; (c) tickets con alcance de turno, vaciados en `beginTurn` o al cortar; (d) atar el ticket al id de la llamada.
- D2: alcance. Solo la rama de corte del clasico (lo que pidio la revision) o tambien las otras ramas que descartan una llamada despues de que el guard ya concedio: chat escrito y bridge.

Hallazgos que cambian el planteamiento:

- La ventana es solo un `cancel` desde otro hilo; no hay ningun punto de suspension entre `granted` y el recheck (seccion 2, P1).
- Ningun caller llama a `execute` sin pasar antes por `approval(for:)`; el ticket sobrante solo se gasta por dos caminos estrechos (seccion 2, P2). Es sobre todo defensa en profundidad, no un exploit directo.
- El clasico no es el unico: el chat escrito y el bridge tambien descartan llamadas despues de conceder, y quedan tickets sobrantes por fallos de `execute` anteriores al `redeem`, sin ningun corte de por medio.

## 2. Estado actual

### P1. Puntos de suspension entre `granted` y el recheck

- `verdict` mira la cancelacion despues de la espera de la hoja y, si esta cancelada, sale sin conceder [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:78]
- Si no esta cancelada, llama a `onSettled`, un closure sincrono [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:83]
- Despues concede con `tools?.granted(request)` y devuelve, sin ningun `await` entre medio [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:84]
- `granted` es sincrono en el protocolo [repo:Sources/CompanionCore/Tools/ParentTools.swift:319]
- `check` solo envuelve a `verdict` y devuelve `.denial` [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:54]
- `actRound` recibe ese resultado y mira `Task.isCancelled` de inmediato, antes de `execute` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:68]
- En esa rama contesta `.interrupted` y no llama a ningun metodo de `parentTools`: el ticket concedido se queda [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:71]
- `ParentToolGuard` es un struct sin aislamiento de actor [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:14]
- `ClassicRuntime` es una clase final sin aislamiento de actor [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:12]
- El target `CompanionServices` no declara `defaultIsolation` ni otros `swiftSettings`, a diferencia de UI y App [repo:Package.swift:25]
- `actRound` corre como tarea hija de un `withTaskGroup` dentro del turno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:70]
- Quien cancela es `VoiceSession`, que es un actor: otro contexto de ejecucion distinto del que corre `actRound` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:4]
- `cancelClassicTurn` cancela la tarea del turno desde ese actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:32]
- `startClassicTurn` tambien cancela el turno anterior desde el mismo actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- Conclusion P1: entre la concesion y el recheck solo hay codigo sincrono y retornos de funciones async no aisladas; la unica forma de que el recheck vea una cancelacion que la comprobacion del guard no vio es un `cancel` que llega desde otro hilo en esa ventana de microsegundos [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:78]
- El ticket emitido sin hoja (`.act`) tiene la misma ventana: se emite dentro de `approval(for:)` sincrono [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:208]
- Y `verdict` devuelve sin `await` cuando `approval(for:)` es nil [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:64]

### P2. Callers de `execute` y si pasan por la puerta antes

- Clasico: `parentGuard.check` y despues `execute` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:65]
- Realtime: `parentGuard.check` y despues `execute`, sin recheck de cancelacion entre medio [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:393]
- Bridge: `guardian.verdict` y despues `execute` [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:161]
- Chat escrito: su propio `gate`, que llama a `tools.approval(for:said:)` primero [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:238]
- `DecisionGate`: llama a `tools.approval(for:said:)` y, si pide hoja, se abstiene; solo ejecuta cuando es nil [repo:Sources/CompanionServices/Decision/DecisionGate.swift:234]
- `CompositeParentTools.execute` solo reenvia a un runner; no es un caller de origen [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:346]
- Conclusion P2: no hay caller que llegue a `execute` sin `approval(for:)` antes; los cinco de origen pasan por la puerta [repo:Sources/CompanionServices/Decision/DecisionGate.swift:240]

### P3. Donde se gasta un ticket sobrante hoy (camino estrecho, no general)

- El ticket se compara por igualdad de nombre, argumentos y pid (o tab, item, nodo y generacion), no por id de la llamada [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:172]
- Vive hasta 60 s [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:99]
- Un ticket ya concedido no lo toca `park`; solo reemplaza la peticion pendiente [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:146]
- Con hoja nueva en el turno siguiente, la llamada solo llega a `execute` despues de otro si; el sobrante no cambia nada en ese camino [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:74]
- Camino 1, manos: `handsApproval` devuelve nil si en ese instante no hay manos listas o no hay app al frente [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:192]
- Un nil de `approval(for:)` significa seguir adelante sin hoja [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:64]
- `runHands` vuelve a leer las manos y el pid, y si ahora es una terminal pide el ticket y gasta el sobrante [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:246]
- Camino 2, entregables: si `actsWithoutSheet` dijo que solo agrega, el guard sigue sin hoja [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:68]
- `runDeliverable` recalcula esa banda y, si el rango se lleno entre medio, aprueba con un ticket sobrante identico [repo:Sources/CompanionServices/Tools/ParentToolRunner+Deliverables.swift:113]
- El comentario del entregable dice que sin hoja ni ticket ese rango se rechaza; un sobrante rompe esa promesa [repo:Sources/CompanionServices/Tools/ParentToolRunner+Deliverables.swift:34]
- `AppToolRunner` guarda las concesiones por nombre de herramienta, sin argumentos ni caducidad [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:255]
- Sus herramientas de escritura siempre piden hoja, asi que una concesion sobrante no se gasta sin otro si hoy [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:238]

### P4. Otras ramas que descartan una llamada despues de conceder

- Chat escrito: concede tras el si de la hoja [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:257]
- Chat escrito: concede tambien con un si recordado [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:249]
- Chat escrito: despues de conceder, un turno cancelado hace `break` sin ejecutar y sin retirar el ticket [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:210]
- Bridge: un epoch distinto descarta la llamada despues del veredicto ya concedido [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:164]
- Bridge: un si con la conexion cerrada tampoco ejecuta, y el ticket ya concedido se queda [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:172]
- Sin ningun corte: `runHands` rechaza por `target_changed` antes de gastar el ticket, asi que un ticket `.act` o concedido queda vivo [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:231]
- Sin ningun corte: el navegador falla por id caducado o campo sensible antes del `redeem` [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:120]

### P5. Quien guarda tickets y como se comparten

- `ScreenHands` tiene su `ApprovalTickets` [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:24]
- `ParentToolRunner` es un struct, pero `deliverableTickets` es una referencia a clase: las copias comparten tickets [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:29]
- `ParentToolRunner.granted` concede en los dos almacenes [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:155]
- `BrowserToolRunner` tiene sus propios tickets [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:31]
- El navegador ya vacia sus tickets cuando cambia el epoch de la conexion, dentro de su lock [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:186]
- `CompositeParentTools.granted` reenvia a todos los runners, no solo al que maneja la herramienta [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:368]
- La app crea un solo `ParentToolRunner` [repo:Sources/CompanionApp/CompanionMainSensing.swift:93]
- Ese mismo runner entra en las herramientas de conversacion (chat y las dos voces) [repo:Sources/CompanionApp/CompanionMainSensing.swift:206]
- Y en las del bridge [repo:Sources/CompanionApp/CompanionMain.swift:142]
- `beginTurn` lo llaman el clasico al empezar un hold [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:77]
- El chat al enviar [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:10]
- Y el bridge al abrir la sesion y al reanudar despues de un turno de voz [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:237]
- `execute` no recibe el id de la llamada; `runHands` arma una `ToolCallRef` con id vacio [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:143]

Contextos: app en produccion (clasico, realtime, chat escrito y bridge comparten el mismo `ParentToolRunner` y sus tickets); `swift test` con `FakeParentTools`, cuyo `granted` solo registra; job de CI con ThreadSanitizer sobre la suite; bridge MCP hacia clientes externos; `DecisionGate`, que ejecuta sin hoja en clasico.

## 3. Fuentes primarias

- La concurrencia de Swift usa cancelacion cooperativa: cada tarea comprueba si fue cancelada en los puntos apropiados y responde [doc:https://github.com/swiftlang/swift-book/blob/swift-6.2-fcs/TSPL.docc/LanguageGuide/Concurrency.md@6.2]
- El mismo libro dice que leer `isCancelled` permite hacer limpieza como parte de detener la tarea [doc:https://github.com/swiftlang/swift-book/blob/swift-6.2-fcs/TSPL.docc/LanguageGuide/Concurrency.md@6.2]
- SE-0338: las funciones async no aisladas corren en un ejecutor generico sin actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@5.7]
- SE-0338: formalmente cambian de ejecutor al entrar, al volver de una llamada y al reanudar, pero si no hay trabajo significativo pueden quedarse en el ejecutor actual [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@5.7]
- La fuente de `withTaskCancellationHandler` en Swift 6.2 dice que el handler corre de inmediato al cancelar y en concurrencia con la operacion [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]
- RFC 7009 define la revocacion de un token que el cliente ya no necesita [doc:https://www.rfc-editor.org/rfc/rfc7009@RFC7009]
- RFC 7009: la invalidacion es inmediata y el token no se puede volver a usar despues de revocarlo [doc:https://www.rfc-editor.org/rfc/rfc7009@RFC7009]
- RFC 7009: la motivacion es que no queden concesiones validas que la usuaria no sabe que existen [doc:https://www.rfc-editor.org/rfc/rfc7009@RFC7009]

## 4. Implementaciones de referencia

- OpenAI Agents SDK (Python), mantenido por OpenAI y ya usado como referencia en `approval-after-cut`: la aprobacion pendiente es un registro de un solo uso que se saca con `pop` [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- En ese SDK, aprobar o rechazar sale sin hacer nada si la sesion esta cerrandose o cerrada [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Al cerrar, `_cleanup` cancela las tareas de herramientas y vacia `_pending_tool_calls` y `_active_tool_invocations`: la concesion muere con la operacion [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Precedente en el propio repo: el navegador vacia sus tickets al cambiar de sesion para que un si de la sesion vieja no se gaste en la nueva [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:175]

## 5. Opciones

D1, forma del arreglo:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| (a) `withdraw(_ call:)` en `ParentToolExecuting` con default no-op; `ApprovalTickets.revoke(name:arguments:)` borra pendiente y concedidos que coinciden; lo implementan `ParentToolRunner` (manos y entregables), `BrowserToolRunner`, `AppToolRunner` (quita la concesion por nombre) y `CompositeParentTools` (reenvia a todos, como `granted`); se llama en cada rama que descarta tras la puerta | Cubre tickets concedidos Y emitidos sin hoja (`.act`), porque revoca por nombre y argumentos sin importar como llegaron; no cambia el contrato de `verdict`; es lo que pidio la revision. Archivos: ParentTools.swift, ParentToolRunnerHands.swift, ParentToolRunner.swift, BrowserToolRunner.swift, AppToolRunner.swift, ClassicRuntime+Act.swift (mas ChatViewModel+Turn.swift y BridgeSession+Calls.swift si D2 amplia) | Falla abierto: un caller nuevo que descarte sin llamar `withdraw` deja el sobrante, igual que hoy; revocar por nombre en `AppToolRunner` puede quitar una concesion concurrente del mismo nombre en otro carril (falla cerrado) | media | **Recomendada** |
| (b) `verdict` deja de llamar `granted` y devuelve el request; cada caller llama `tools.granted(request)` despues de su recheck y justo antes de `execute` | Falla cerrado: un caller que olvide conceder obtiene `approval_required` en las herramientas con ticket; el ticket concedido nunca existe para una llamada descartada | No cubre los tickets `.act`, que `approval(for:)` emite antes del guard; cambia el contrato de `verdict` en clasico, realtime y bridge (realtime hoy no tiene recheck); `open_url` no usa tickets, asi que olvidar `granted` no se nota ahi y un test por caller es obligatorio. Archivos: ParentToolGuard.swift, ClassicRuntime+Act.swift, RealtimeRuntime.swift, BridgeSession+Calls.swift, ChatViewModel+Turn.swift | media | Alternativa, si Karen prefiere fallar cerrado |
| (c) Tickets con alcance de turno: vaciarlos en `beginTurn` o al cortar | Un solo punto; tambien limpia sobrantes de fallos anteriores al `redeem` | El runner y sus tickets se comparten entre clasico, chat y bridge, y el bridge llama `beginTurn` al reanudar: un turno de un carril borraria el ticket recien concedido de otro; realtime no llama `beginTurn` por turno, asi que no lo cubre | baja de escribir, alta de razonar | No |
| (d) Atar el ticket al id de la llamada | El ticket solo vale para esa llamada | `execute(name:argumentsJSON:)` no recibe el id; cambiar la firma toca cada runner, cada caller y cada fake | alta | No |

D2, alcance:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| Solo la rama de corte del clasico | Lo que pidio la revision; diff chico | Deja la misma forma en el chat (`break` tras conceder) y en el bridge (epoch e `isOpen` tras conceder) | baja | No |
| Clasico, chat y bridge en el mismo PR | Una regla para todas las ramas que descartan tras la puerta | Tres callers y tres tests | media | **Recomendada** |
| Ademas, revocar en los fallos de `execute` antes del `redeem` (`target_changed`, id caducado) | Cierra los sobrantes sin corte | Toca la logica interna de cada runner; otro problema, otra revision | media | PR aparte |

## 6. Evidencia en contra

- La ventana del clasico es un `cancel` desde otro hilo entre dos lineas sin `await`; en la practica son microsegundos, y MEDIUM puede sonar alto [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:84]
- Se acepta igual: el ticket sobrante vive 60 s y hay dos caminos estrechos donde se gasta sin hoja nueva [repo:Sources/CompanionServices/Tools/ParentToolRunner+Deliverables.swift:113]
- Y RFC 7009 pide que la concesion que ya no se necesita deje de valer de inmediato [doc:https://www.rfc-editor.org/rfc/rfc7009@RFC7009]
- Contra (a): falla abierto si alguien agrega una rama de descarte y olvida `withdraw`; (b) falla cerrado [repo:Sources/CompanionCore/Tools/ParentTools.swift:344]
- Se resuelve en parte: (b) no cubre los tickets `.act`, que nacen en `approval(for:)` antes de que el guard decida, asi que solo (a) cubre las dos fuentes de tickets [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:208]
- Y se mitiga con un test por cada rama de descarte, que es lo que la seccion 10 exige [repo:Tests/CompanionServicesTestSupport/ScreenHandsFakes.swift:72]
- Contra revocar por nombre y argumentos: una llamada identica de otro carril (bridge y voz comparten el runner) perderia su ticket [repo:Sources/CompanionApp/CompanionMain.swift:142]
- Se acepta: el efecto es `approval_required`, que falla cerrado, y dos llamadas identicas en el mismo instante desde dos carriles es raro [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:250]
- Contra `AppToolRunner`: sus concesiones son por nombre de herramienta, asi que revocar por nombre puede quitar la concesion de otra llamada de la misma herramienta en curso [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:299]
- Se acepta por la misma razon: falla cerrado con `approval_required` [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:271]
- Ninguna comprobacion cierra la ventana del todo, porque la cancelacion es cooperativa y puede llegar durante `execute` [doc:https://github.com/swiftlang/swift-book/blob/swift-6.2-fcs/TSPL.docc/LanguageGuide/Concurrency.md@6.2]
- Se acepta, igual que en `approval-after-cut`: el resto vive dentro de `execute`, cuyas guardias releen el destino antes de actuar [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:231]
- La referencia externa revoca al cerrar la sesion, no por llamada interrumpida; no prueba que revocar por llamada sea lo habitual [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]
- Se acepta: lo que si muestra es que una aprobacion es de un solo uso y que el registro se vacia cuando la operacion que la pidio termina, que es la regla que (a) aplica a la llamada [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, en el repo: el navegador vacia tickets y paginas en el mismo lock cuando cambia el epoch [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:182]

```swift
// BrowserToolRunner.syncEpoch, citado tal cual
lock.withLock {
    guard current != seenEpoch else { return }
    seenEpoch = current
    pages.removeAll()
    tickets.reset()
}
```

- Bien hecho, referencia externa: la aprobacion pendiente se saca del registro antes de actuar, asi que no se puede usar dos veces [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/realtime/session.py@28e9f4f]

```python
# openai-agents-python, RealtimeSession.approve_tool_call
if self._closing or self._closed:
    return
pending = self._pending_tool_calls.pop(call_id, None)
if pending is None:
    return
```

- Anti-ejemplo, el hueco de este brief: la rama de corte contesta `.interrupted` y no retira lo que el guard concedio [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:68]
- Anti-ejemplo, la misma forma en el chat: `break` despues de un `granted` [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:210]
- Anti-ejemplo, la misma forma en el bridge: `.dropped` despues de un veredicto que concedio [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:164]

## 8. Trampas

- `withdraw` no puede reconstruir el ticket exacto desde la llamada: el pid o la generacion pudieron cambiar; hay que revocar por nombre y argumentos [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:101]
- Tambien hay que limpiar la peticion pendiente si coincide, o un si tardio la convierte en concedida despues de la revocacion [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:149]
- `CompositeParentTools` enruta `execute` al primer runner que maneja el nombre, pero `granted` va a todos; `withdraw` debe ir a todos como `granted` [repo:Sources/CompanionServices/Apps/AppToolRunner.swift:367]
- Vaciar tickets en `beginTurn` borraria tickets de otro carril, porque el bridge llama `beginTurn` al reanudar con el mismo runner [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:237]
- Un RED con `FakeParentTools` no demuestra nada sobre el gasto: su `granted` solo registra [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:130]
- El test de PR #87 solo cubre el corte antes de que llegue la respuesta, no el que cae despues de la comprobacion del guard [repo:Tests/CompanionServicesTests/ApprovalAfterCutTests.swift:52]
- El RED debe usar el runner real con manos falsas en una terminal; ya existe el patron de ticket gastado [repo:Tests/CompanionServicesTests/HandsPolicyTests.swift:100]
- `granted` y `approval(for:)` son sincronos: el fake delegante no puede esperar a que otro hilo cancele, tiene que cancelar la tarea actual el mismo (ver la seccion 9) [repo:Sources/CompanionCore/Tools/ParentTools.swift:319]
- Realtime no tiene rama de corte despues del guard, asi que (a) no le agrega nada; (b) si lo obligaria a cambiar [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:397]
- Contexto app: los cuatro carriles comparten el runner; la revocacion por llamada no toca los tickets de otras llamadas distintas [repo:Sources/CompanionApp/CompanionMainSensing.swift:206]
- Contexto `swift test`: los fakes heredan el no-op por defecto, asi que ningun test existente cambia de resultado salvo los nuevos [repo:Sources/CompanionCore/Tools/ParentTools.swift:344]
- Contexto CI con TSan: `ApprovalTickets` y `AppToolRunner` ya protegen su estado con lock; la revocacion debe tomar el mismo lock [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:136]
- Contexto bridge: dos ramas de descarte despues de conceder (epoch e `isOpen`) [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:172]
- Contexto chat escrito: su `gate` concede sin pasar por `ParentToolGuard`, asi que el recheck del guard de PR #87 no lo cubre [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:254]
- Contexto `DecisionGate`: no concede nada y solo ejecuta sin hoja; la revocacion no aplica [repo:Sources/CompanionServices/Decision/DecisionGate.swift:234]

## 9. Incertidumbre

- ASSUMPTION: el camino 1 (manos) es alcanzable en la app: `approval(for:)` ve las manos no listas o sin app al frente y `execute` las ve listas sobre una terminal. prueba: test con `handsRunner` y un `FakeHands` cuyo `selfInFront` cambia entre `approval(for:)` y `execute`, con un ticket sobrante concedido para la misma llamada; esperar que hoy escribe.
- ASSUMPTION: el camino 2 (entregables) es alcanzable: `actsWithoutSheet` dice que solo agrega y el rango se llena antes de `runDeliverable`. prueba: test con `SpreadsheetDriving` falso que cambia la banda entre las dos lecturas y un ticket `sheet_write` sobrante identico; esperar que hoy escribe con `approved: true`.
- ASSUMPTION: `withUnsafeCurrentTask { $0?.cancel() }` dentro del `granted` de un fake delegante marca la tarea de `actRound` como cancelada y el recheck la ve, de forma determinista. prueba: el propio RED de la seccion 10; si el recheck no ve la cancelacion, el test pasa en ambos lados y hay que cancelar desde `approval(for:)`.
- ASSUMPTION: la decision de 60 s en `ApprovalTickets.lifetime` no tiene otro consumidor que dependa de que un ticket sobreviva a un descarte. prueba: con (a) aplicado, correr la suite completa y la de integracion; ningun test previo debe cambiar.
- Resuelto por lectura de codigo: no hay punto de suspension entre `granted` y el recheck; la ventana es un `cancel` desde otro hilo (seccion 2, P1).
- Resuelto por lectura de codigo: no hay caller de `execute` que se salte `approval(for:)`; el sobrante es defensa en profundidad salvo los dos caminos de arriba (seccion 2, P2 y P3).
- [NEEDS CLARIFICATION: Karen decide D1 y D2. Recomendacion: (a) `withdraw(_ call:)` con default no-op, llamado en las tres ramas que descartan tras la puerta (clasico, chat, bridge), aceptando que falla abierto si un caller futuro lo olvida. Alternativa: (b), que falla cerrado pero no cubre los tickets `.act` y obliga a tocar realtime. Y si los sobrantes por fallos de `execute` antes del `redeem` van en un PR aparte.]

## 10. Checklist de estandar

- [ ] RED clasico, concedido: fake delegante `ParentToolExecuting` sobre un `ParentToolRunner` real (`handsRunner`, terminal) cuyo `granted` reenvia y luego cancela la tarea actual; `actRound` con una llamada `type_text` que pide hoja y `ScriptedApprovals` que aprueba; `actRound` contesta `cancelled`; despues `runner.execute` con la misma llamada devuelve `approval_required`. Falla en la base de PR #87 y pasa con el arreglo.
- [ ] RED clasico, emitido sin hoja: igual, pero el fake cancela dentro de `approval(for:)` con una llamada `type_text` dicha (`.act`); despues `execute` devuelve `approval_required`.
- [ ] Mismo par de tests para el chat escrito (rama `break` tras conceder) y para el bridge (epoch distinto y conexion cerrada), si D2 se amplia.
- [ ] `ApprovalTickets.revoke(name:arguments:)` borra los concedidos que coinciden y la pendiente que coincide, bajo el mismo lock; test unitario con reloj falso.
- [ ] `CompositeParentTools.withdraw` reenvia a todos los runners; test con dos fakes.
- [ ] `AppToolRunner.withdraw` quita la concesion por nombre; test que muestra `approval_required` despues.
- [ ] Un ticket de otra llamada distinta sigue gastable despues de revocar; test.
- [ ] El default del protocolo es no-op y ningun fake existente necesita cambios.
- [ ] La suite completa pasa tambien en el job de ThreadSanitizer.
- [ ] CHANGELOG en [Unreleased], en espanol y con fecha.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | The Swift Programming Language, Concurrency (Task Cancellation) | swiftlang/swift-book | swift-6.2-fcs | 2026-10-01 | high |
| 2 | SE-0338 Clarify the Execution of Non-Actor-Isolated Async Functions | Swift Evolution | Swift 5.7 | 2026-10-01 | high |
| 3 | TaskCancellation.swift (withTaskCancellationHandler) | swiftlang/swift | swift-6.2-RELEASE | 2026-10-01 | high |
| 4 | RFC 7009 OAuth 2.0 Token Revocation | IETF | RFC 7009 | 2026-10-01 | high |
| 5 | openai-agents-python, src/agents/realtime/session.py | OpenAI | 28e9f4f | 2026-10-01 | high |

[KAREN:chat 2026-10-01] Q1: opcion A (withdraw en el protocolo, no-op por defecto) mas un test que escanea las fuentes y falla si un llamador del gate no llama withdraw en su rama de cancelacion. Q2: clasico, chat y puente en un PR; los restos por fallos de execute antes del redeem van en otro PR. Q3: aprobado el metodo nuevo en el protocolo de Core. Q4: aceptado, falla cerrado. Q5: suficiente (RFC 7009 + OpenAI Agents SDK + syncEpoch del repo).
