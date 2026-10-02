# Reference Brief: el "si" hablado a una hoja del padre en voz clasica

Slug: classic-spoken-yes-parent-sheet | Nivel: standard | Fecha: 2026-10-02 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Q1, que quedo abierta en `docs/research/approval-after-cut.md` (seccion 9, NEEDS CLARIFICATION). En voz clasica, una herramienta del padre puede abrir una hoja de permiso; el caso de referencia es `open_url` a un host que la usuaria no dijo. La pregunta es si un "si" hablado debe poder contestar esa hoja y, si debe, como hacerlo sin debilitar el consentimiento.

Procedencia de la decision: Karen delego los pendientes a la sesion orquestadora ("dale solucion a los pendientes", 2026-10-01). El orquestador decidio que SI, como PR propio, y anoto que Touch ID va a proteger despues las hojas criticas. Esa eleccion concreta es del orquestador, no son palabras de Karen. [KAREN:chat 2026-10-01 via orquestador, delegado]

Hallazgo que cambia el planteamiento (seccion 2): hoy toda hoja del padre es de riesgo alto (`ApprovalRisk.high`). Eso incluye `open_url` a un host no dicho, las manos (`click`, `type_text` y Return en terminal, `menu`) y los entregables (`sheet_write`, `create_document`). La regla 20c D1, firmada por Karen, deja el "si" hablado solo para lo de riesgo bajo. Por eso un "SI" literal no se puede construir sin una de dos cosas: cambiar la clasificacion de riesgo, o esperar a Touch ID. Las dos son decisiones de Karen, no del orquestador.

Decisiones:

- D1, alcance: que hojas del padre puede aprobar un "si" hablado. (a) Ninguna por ahora: la hoja se anuncia, el "no" la resuelve y el "si" contesta "necesita tu clic". (b) `open_url` a un host no dicho. (c) Tambien las criticas, solo a traves de Touch ID cuando este implementado.
- D2, conflicto de la pulsacion: como se distingue "pulsar para contestar una hoja anunciada" de "pulsar para cortar", sin reabrir el hueco de #87.
- D3, el texto hablado: que dice la voz, por que camino y en que catalogo.
- D4, realtime: si cambia algo (`resolve_approval`, #92).

## 2. Estado actual

- El comentario del guard de voz dice que la hoja del padre "is parked for the spoken yes, like a job's request" [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:324]
- `onRequest` del guard del padre solo llama `noteApproval`, es decir, arma la peticion pero no la dice en voz alta [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:330]
- Solo el `onEvent` de un trabajo llama a `askApprovalAloud` despues de `noteApproval` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:304]
- `approvalAnnounced` solo lo llama `markQuestionSaid`, y esta funcion exige una pregunta encolada por el camino de anuncios (`askedAloud`) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:97]
- `markQuestionSaid` corre cuando el sintetizador emite `.finished`, o sea cuando el audio de la pregunta termino de sonar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:339]
- `SpokenYes.admits` devuelve falso en realtime, sin `announcedAt`, sin palabras del hold o si las palabras no afirman [repo:Sources/CompanionCore/Session/Acknowledgement.swift:60]
- Ademas, el hold que contesta tiene que empezar al menos `ApprovalClickGuard.dwell` despues del anuncio [repo:Sources/CompanionCore/Session/Acknowledgement.swift:62]
- `dwell` vale 0.6 s [repo:Sources/CompanionCore/Island/IslandState.swift:279]
- `affirms` es una lista cerrada de hasta 4 palabras, sin numeros ni signos de pregunta, marcada HACK hasta que exista el juez de 16q-3 [repo:Sources/CompanionCore/Session/Acknowledgement.swift:70]
- Las palabras que cuentan son las del hold que contesta: `noteHeard` las guarda solo si su pulsacion es la pulsacion viva [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:63]
- El turno clasico entrega sus palabras con `onHeard`, y vacias si el turno ya estaba cancelado [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:286]
- En clasico, el "si" llega como llamada del modelo a `resolve_approval`; un `.needsClick` agrega la linea hablada "necesita tu clic" [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:601]
- `answerPendingApproval` exige que la hoja muestre esa peticion; si muestra otra, pide el clic [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:193]
- Un "no" hablado resuelve sin clic, venga de quien venga; solo el "si" tiene que probar que es de la usuaria [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:199]
- Las escrituras de apps (`app:`) piden siempre el clic [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:215]
- Fuera de lo de riesgo bajo, o si es MCP, pide el clic (20c D1) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:222]
- El "si" admitido no resuelve en la sesion: emite `.approvalSpoken` con el id exacto [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:205]
- El reductor solo resuelve `.approvalSpoken` si la hoja muestra ese id [repo:Sources/CompanionCore/Session/SessionMachine.swift:128]
- `ApprovalRisk` es una allowlist de lecturas, y su comentario excluye `open_url` porque un host no dicho es "the exfil sink" [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:14]
- `ParentToolGate` solo pide hoja para `open_url` cuando la usuaria no dijo el host [repo:Sources/CompanionCore/Tools/ParentToolPolicy.swift:197]
- El runner del padre tambien pide hoja para los entregables y para las manos [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:150]
- Un entregable pide hoja solo si su `riskLevel` es `.requiresApproval` (escrituras) [repo:Sources/CompanionServices/Tools/ParentToolRunner+Deliverables.swift:22]
- Las manos piden hoja en el veredicto `.ask` de `HandsGate` [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:224]
- Un test fija `open_url`, `click`, `type_text`, `press_key`, `menu` y `sheet_write` como riesgo alto [repo:Tests/CompanionIntegrationTests/ApprovalRiskTests.swift:38]
- Otro test fija que un "si" a `open_url` contesta `.needsClick` y deja la peticion pendiente [repo:Tests/CompanionIntegrationTests/ApprovalRiskTests.swift:74]
- La spec 20c D1 la firmo Karen ("dale todo", 2026-09-29) [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:3]
- Su texto pone `open_url` a un host dicho entre lo de riesgo bajo; un host dicho nunca abre hoja, asi que el texto no cubre la hoja que si existe [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:27]
- La implementacion de 20d resolvio ese borde del lado seguro: un host no dicho sigue en confirmar, por ser el sumidero de exfiltracion [repo:docs/specs/wave-20d-modos-autorizacion.md:169]
- La spec de Touch ID esta APROBADA: todo "si" sobre una peticion critica, hablado incluido, pasa por `.verifyOwner` [repo:docs/specs/touch-id-aprobaciones-criticas.md:48]
- En esa spec, `open_url` a un host no dicho es `.confirm` y no pide Touch ID [repo:docs/specs/touch-id-aprobaciones-criticas.md:30]
- Touch ID todavia no esta en el codigo: `ActionBand` existe, pero un grep no encuentra `verifyOwner` ni `atSheet` en Sources [repo:Sources/CompanionCore/Tools/ActionBand.swift:6]
- La llamada del padre espera la hoja dentro del turno clasico, en `parentGuard.check` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:65]
- Si la ronda tarda mas que `slowToolWait`, el turno dice su linea de trabajo ("Dame un momento") mientras la llamada sigue esperando [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:88]
- Una pulsacion en `.thinking` o `.speaking` del clasico corta el turno [repo:Sources/CompanionCore/Session/TurnMachine.swift:76]
- Cortar emite `.cancelAgentOutput(steer: true)` y pide escuchar [repo:Sources/CompanionCore/Session/TurnMachine.swift:154]
- En clasico, `.cancelAgentOutput` cancela la tarea del turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:75]
- Empezar un turno nuevo tambien cancela el anterior, aunque la pulsacion no lo haya cortado [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:21]
- Con la tarea cancelada, el guard termina la hoja como `.abandoned` y devuelve una interrupcion; no concede nada [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:78]
- `.abandoned` se publica como `.approvalWithdrawn`, la tarjeta sale y la isla avisa (#87) [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:340]
- El aviso en es es "Me interrumpiste mientras esperaba tu permiso, asi que no hice nada" [repo:Sources/CompanionUI/es.lproj/Localizable.strings:704]
- En un hold, cuando la voz del turno termina de sonar, el reductor pasa a `.idle` y apaga el IO [repo:Sources/CompanionCore/Session/TurnMachine.swift:359]
- Los anuncios clasicos solo suenan con el hueco abierto, y el hueco esta cerrado en `.thinking` y `.speaking` [repo:Sources/CompanionCore/Session/Acknowledgement.swift:153]
- La pregunta hablada es fija y no lleva nada de la peticion: "Hay un permiso en la tarjeta: ¿lo permito?" [repo:Sources/CompanionCore/Delegation/Escalation+Copy.swift:245]
- La linea de "necesita tu clic" tambien es fija, en la misma tabla de Core [repo:Sources/CompanionCore/Delegation/Escalation+Copy.swift:235]
- Esas frases viven en tablas Swift de Core y no en `Localizable.strings`, porque los actores de Services no alcanzan `Localized` [repo:docs/specs/catalogo-de-textos.md:18]
- Realtime: `SpokenYes.admits` es falso con `realtime: true` [repo:Sources/CompanionCore/Session/Acknowledgement.swift:60]
- Realtime: un `.needsClick` de `resolve_approval` contesta al modelo con `approvalNeedsClick` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:521]
- Realtime (#92): un barge-in cancela la llamada del padre estacionada, y con eso retira su hoja [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:317]
- Test de caracterizacion: con el actor real, `open_url` estacionado, pulsar y decir "si" no ejecuta nada y no deja la hoja estacionada [repo:Tests/CompanionIntegrationTests/ApprovalWithdrawnTests.swift:137]
- Precedente de trabajos: la pregunta queda anunciada solo al terminar de sonar, y despues un hold con "si" la resuelve [repo:Tests/CompanionIntegrationTests/Approvals16q1Tests.swift:293]
- Precedente de trabajos: una pulsacion sobre la pregunta la corta, y lo no dicho pide el clic [repo:Tests/CompanionIntegrationTests/Approvals16q1Tests.swift:315]
- Precedente de trabajos: una escritura de app se pregunta en voz alta, pero el "si" nunca la aprueba y el "no" si la rechaza [repo:Tests/CompanionIntegrationTests/Approvals16q1Tests.swift:331]
- La hoja vence a los 60 s con una negativa (`ApprovalTiming.autoDeny`) [repo:Sources/CompanionCore/Approvals/ApprovalPorts.swift:7]
- La arquitectura pide cancelacion estructurada y no contadores de generacion [repo:docs/ARCHITECTURE.md:79]
- El job de CI con ThreadSanitizer corre la suite completa en su propio runner [repo:.github/workflows/ci.yml:47]
Contextos: app instalada con el actor `Approvals` real, en clasico y en realtime (Q1 es solo clasico); `swift test` con `ScriptedApprovals`, que no atiende la cancelacion, y con el actor real en `ApprovalWithdrawnTests`; job TSan de CI sobre la suite completa; bridge MCP, que comparte `ParentToolGuard` pero no la voz; chat escrito, que no usa la voz ni este guard.

## 3. Fuentes primarias

- Swift 6.2: cuando `isCancelled` pasa a true, se queda asi; "There is no way to uncancel a task" [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]
- Por eso, una pulsacion que ya cancelo el turno no puede despues "salvar" su hoja; la decision de cortar tiene que tomarse antes de cancelar [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]
- Alexa `Dialog.ConfirmIntent`: Alexa pide a la persona que confirme con si o no antes de que el skill actue, y el resultado queda en `confirmationStatus` como CONFIRMED o DENIED [doc:https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html@2023-11-28]
- La misma referencia pide repetir en el prompt los valores que se confirman y dejar la sesion abierta para la respuesta [doc:https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html@2023-11-28]
- Apple App Intents: `IntentAuthenticationPolicy.requiresAuthentication` exige autenticar antes de correr el intent, y `alwaysAllowed` lo deja correr incluso con el equipo bloqueado [doc:https://developer.apple.com/documentation/appintents/intentauthenticationpolicy@macOS-13.0]
- OpenAI Agents SDK, guia realtime: una tool con aprobacion emite `tool_approval_required` y pausa su ejecucion hasta `approve_tool_call()` o `reject_tool_call()` [doc:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/docs/realtime/guide.md@a575a6e]
- La misma guia: lo que pasa el chequeo previo a la aprobacion se vuelve a chequear despues de aprobar y antes de ejecutar [doc:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/docs/realtime/guide.md@a575a6e]
- OpenAI Agents SDK, human in the loop: la corrida se pausa con `interruptions`, y se reanuda con `state.approve` o `state.reject` mas `Runner.run(agent, state)` [doc:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/docs/human_in_the_loop.md@a575a6e]

## 4. Implementaciones de referencia

- OpenAI Agents SDK (Python), de OpenAI, unas 29.8k estrellas, push el 2026-10-02. Es la capa realtime de voz del mismo proveedor que usa Companion [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]
- En ese SDK, la llamada que necesita aprobacion se guarda en `_pending_tool_calls`, emite el evento y la funcion vuelve; la sesion no queda bloqueada esperando [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]
- `approve_tool_call` no hace nada si la sesion esta cerrando o si el id ya no esta pendiente (lo saca con `pop`) [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]
- `interrupt()` solo manda la interrupcion al modelo y no toca las aprobaciones pendientes: en ese SDK, la aprobacion es de la sesion, no de la respuesta [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]
- LangGraph, de LangChain: `interrupt()` detiene el grafo, y al reanudar con `Command` el nodo se re-ejecuta desde el principio, asi que lo anterior a la aprobacion se vuelve a evaluar [ref:https://github.com/langchain-ai/langgraph/blob/157a06dda988d85afeb8751ff27b35ab3f4f8bf4/libs/langgraph/langgraph/types.py@157a06d]

## 5. Opciones

D1, alcance del "si" hablado a una hoja del padre:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| a. Ninguna aprueba todavia. La hoja se anuncia y el hold de respuesta no la mata. El "no" la rechaza y el "si" contesta "necesita tu clic". | No toca `ApprovalRisk` ni 20c D1. Arregla lo que se rompe hoy (la pulsacion mata la tarjeta). Mismo trato que las escrituras de app de los trabajos. | El "si" todavia no aprueba nada del padre; la voz sigue pidiendo clic | media | **Recomendada ahora** |
| b. `open_url` a un host no dicho entra a lo que un "si" aprueba | Es el caso que nombra Q1, y en Touch ID es `.confirm`, no critico | Revierte el comentario "exfil sink", el test de riesgo y 20d §11. Lo protegen solo `affirms` y el anuncio | baja en codigo, alta en riesgo | Solo con la firma de Karen |
| c. Las criticas (manos, entregables), solo a traves de `.verifyOwner` | Es la capa que pide Apple (voz y despues autenticacion), y Touch ID A5 ya la preve | Touch ID no esta implementado; sin el, esto reabre 20c F1 | alta | Despues de Touch ID, con su propia firma |

D2, la pulsacion que contesta:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| P1. Terminar el turno y estacionar la llamada fuera de el. La tool contesta "esperando permiso", la accion corre al aprobar, y un turno nuevo se lo cuenta al modelo | Es la forma del SDK de OpenAI y de LangGraph; la pulsacion ya no corta nada | Saca la accion del turno, y con eso de la cancelacion estructurada que sostiene #87. Hay que inventar la revalidacion y el retorno del resultado al modelo. Contrato nuevo entre Classic y VoiceSession | alta | No en este PR |
| P2. Hold de respuesta: con una hoja del padre anunciada y estacionada, la pulsacion abre el micro sin cancelar el turno. Al soltar, las palabras deciden: un "si" va por la regla de D1; cualquier otra cosa es un corte como hoy (`.abandoned`, aviso) y esas palabras abren el turno nuevo | La decision de cortar se toma con las palabras ya oidas. El turno sigue estructurado. Un "si" tardio para un turno cortado sigue sin actuar (#87 intacto) | Un estado nuevo en `TurnMachine`; el "si" se juzga sin modelo (`affirms` directo), distinto del camino de los trabajos | media | **Recomendada** |
| P3. Dejarlo como esta (solo clic) | Cero codigo | Q1 queda sin resolver; la pulsacion sigue matando la tarjeta y el comentario de VoiceSession.swift:324 sigue prometiendo algo que no pasa | nula | No |

D3, el texto: reusar `Escalation.approvalAskedSpoken` y `approvalNeedsClickSpoken`, dichos por el turno estacionado y no por la cola de anuncios, que espera un hueco. Sin frases nuevas, salvo que Karen quiera un aviso distinto para un "no" explicito.

D4, realtime: sin cambios. `SpokenYes` sigue siendo falso en realtime, y un barge-in retira la hoja (#92).

## 6. Evidencia en contra

- La mas fuerte: Q1 pregunta por `open_url` a un host no dicho, y el codigo lo clasifica a proposito como alto porque es el sumidero de exfiltracion [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:14]
- No se resuelve en este brief, se escala: con la recomendacion (a), el "si" a esa hoja contesta "necesita tu clic", y aprobarlo por voz (b) queda como decision de Karen [repo:Tests/CompanionIntegrationTests/ApprovalRiskTests.swift:74]
- Contra (b): `resolve_approval` lo llama el modelo, y lo que el modelo lee (una pagina, la pantalla) puede plantarle las palabras; es la raiz de 20c [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:9]
- Se acepta parcialmente: con P2, el "si" de una hoja del padre se juzga con las palabras del hold (`affirms`) y no con el booleano del modelo, lo que endurece y no debilita [repo:Sources/CompanionCore/Session/Acknowledgement.swift:73]
- Contra P2: en el SDK de OpenAI la aprobacion no bloquea la sesion y sobrevive a `interrupt()`; P1 seria la forma de la referencia [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]
- Se acepta: Karen ya decidio que un corte retira la hoja (#87, #92); P1 cambiaria esa semantica y el contrato del turno clasico, y P2 respeta las dos cosas [repo:docs/research/approval-after-cut.md:17]
- Contra una pregunta fija: Alexa pide repetir en el prompt los valores que se confirman [doc:https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html@2023-11-28]
- Se acepta: la frase fija evita que el payload de una tool ponga palabras en la boca de la voz, y Karen la aprobo para Touch ID (Q2: "perfecto") [repo:docs/specs/touch-id-aprobaciones-criticas.md:12]
- Contra (c) antes de Touch ID: Apple separa la voz que dispara la accion de la autenticacion que la autoriza; un "si" hablado sin prueba de duena no basta para lo critico [doc:https://developer.apple.com/documentation/appintents/intentauthenticationpolicy@macOS-13.0]
- Se acepta como orden: (c) va despues de que exista `.verifyOwner`, y la invariante A5 de Touch ID lo prueba [repo:docs/specs/touch-id-aprobaciones-criticas.md:50]
- Contradiccion entre fuentes de la casa: 20c D1 pone `open_url` a un host dicho como bajo, pero ese caso nunca abre hoja; el codigo y 20d, que son posteriores, tratan como alto el host no dicho [repo:docs/specs/wave-20d-modos-autorizacion.md:169]
- Se resuelve a favor del codigo y de 20d: son posteriores, los dos firmados, y piden mas y no menos [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:14]

## 7. Ejemplares y anti-ejemplos

- Bien hecho en el repo: el camino de los trabajos anuncia solo cuando el audio termino, y asi lo no dicho no se puede contestar [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:95]

```swift
// VoiceSession+Announcements.swift, citado tal cual
func markQuestionSaid() {
    guard announcementUnlogged, let id = askedAloud else { return }
    approvalAnnounced(id)
}
```

- Bien hecho en el repo: el "si" no resuelve en la sesion, viaja con el id exacto al reductor, que lo descarta si la hoja muestra otra cosa [repo:Sources/CompanionCore/Session/SessionMachine.swift:128]
- Bien hecho afuera: aprobar un id que ya no esta pendiente no ejecuta nada [ref:https://github.com/openai/openai-agents-python/blob/a575a6e637feb9aea1b591237b007dd4991ddfba/src/agents/realtime/session.py@a575a6e]

```python
# openai-agents-python, RealtimeSession.approve_tool_call
if self._closing or self._closed:
    return
pending = self._pending_tool_calls.pop(call_id, None)
if pending is None:
    return
```

- Bien hecho afuera: un si o un no explicito, con estado CONFIRMED o DENIED, antes de actuar [doc:https://developer.amazon.com/en-US/docs/alexa/custom-skills/dialog-interface-reference.html@2023-11-28]
- Anti-ejemplo, el de hoy: el comentario promete un "si" hablado que ningun camino arma, porque la hoja del padre nunca se anuncia [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:324]
- Anti-ejemplo que hay que evitar: decidir "contestar o cortar" en la pulsacion, antes de oir las palabras; una vez cancelado, el turno no se puede descancelar [doc:https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/Concurrency/TaskCancellation.swift@6.2]

## 8. Trampas

- Hay dos caminos que matan la hoja, no uno: la pulsacion en `.thinking`/`.speaking` y el turno nuevo que cancela al anterior; P2 tiene que cubrir los dos [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:21]
- Si la linea de trabajo ya sono en un hold, el reductor puede estar en `.idle` con el turno todavia esperando la hoja; entonces la pulsacion no corta pero el turno nuevo si (sin verificar en ejecucion, seccion 9) [repo:Sources/CompanionCore/Session/TurnMachine.swift:359]
- Anunciar por `jobAnnounce` depende del hueco, que esta cerrado en `.thinking`/`.speaking`; la pregunta del padre tiene que salir del propio turno [repo:Sources/CompanionCore/Session/Acknowledgement.swift:153]
- Si el turno ya dijo "Dame un momento", la pregunta es una segunda linea; la regla de una linea por turno no la debe tragar [repo:Sources/CompanionCore/Session/Acknowledgement.swift:33]
- El hold de respuesta tiene que empezar 0.6 s despues del anuncio, o `admits` lo rechaza aunque diga "si" [repo:Sources/CompanionCore/Session/Acknowledgement.swift:62]
- Las palabras del hold de respuesta tienen que estamparse con su propia pulsacion, o `heardOfThisHold` las descarta [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:151]
- Con (a), el "si" se rechaza en `admitsSpokenYes` por riesgo, antes de mirar el anuncio; un test que solo pruebe el anuncio no ve la regla de riesgo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:222]
- Un "no" convertido en corte publica `.abandoned` y el aviso "me interrumpiste", que para un "no" explicito no es exacto [repo:Sources/CompanionUI/es.lproj/Localizable.strings:704]
- `ScriptedApprovals(park: true)` ignora la cancelacion; el test de P2 que prueba "el corte sigue retirando" tiene que usar tambien el actor real [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:191]
- Contexto app: el actor real deniega al cancelar; con P2 la pulsacion que contesta no cancela, asi que la hoja sigue viva hasta el veredicto o hasta los 60 s [repo:Sources/CompanionServices/Approvals/Approvals.swift:44]
- Contexto `swift test`: el test de caracterizacion usa el actor real y cambia de resultado: con (a), la hoja sigue estacionada y `executeCalls` sigue vacio [repo:Tests/CompanionIntegrationTests/ApprovalWithdrawnTests.swift:156]
- Contexto TSan: P2 agrega estado al actor `VoiceSession` y al snapshot del reductor, nada fuera de ellos; el job corre la suite entera [repo:.github/workflows/ci.yml:47]
- Contexto realtime: no cambia; `SpokenYes` es falso alli y un barge-in sigue retirando la hoja [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:317]
- Contexto bridge: comparte `ParentToolGuard` pero no `TurnMachine` ni `noteApproval`; P2 no lo toca [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:328]
- No hay que agregar un contador de generacion para distinguir el hold de respuesta; la arquitectura pide cancelacion estructurada [repo:docs/ARCHITECTURE.md:79]

## 9. Incertidumbre

- ASSUMPTION: mientras la llamada del padre espera la hoja en un hold, el estado es `.thinking`, o `.speaking` mientras suena la linea de trabajo, y despues `.idle`. prueba: test de `VoiceSession` clasico con `slowToolWait` controlado que lee `machine.snapshot.state` antes y despues de `.finished` de la linea de trabajo, con la hoja estacionada.
- ASSUMPTION: si el estado ya es `.idle`, la pulsacion arranca un turno nuevo que cancela al estacionado por `startClassicTurn`, y no por `cutClassicTurn`. prueba: el mismo test, pulsando despues del `.finished`, y comprobando que llega `.approvalWithdrawn` sin un `.cancelAgentOutput` previo.
- ASSUMPTION: en modo manos libres (sin hold) el turno estacionado tambien bloquea el hueco, y la regla de P2 aplica igual. prueba: test clasico con `holdArmed == false` que estaciona una hoja del padre y registra que anuncios y que estados aparecen.
- ASSUMPTION: decir la pregunta desde el turno estacionado no choca con `mouth.started` ni con `.firstSentence`, que solo actua en `.thinking`. prueba: test que cuenta en `synth.queue` exactamente una `approvalAskedSpoken` por hoja del padre, con y sin la linea de trabajo previa.
- ASSUMPTION: juzgar el "si" del hold de respuesta con `SpokenYes.affirms` sin pasar por el modelo da el mismo resultado que el camino `resolve_approval` en los casos de los tests de trabajos. prueba: tabla de casos de `Approvals16q1*` corrida contra la funcion nueva.
- [NEEDS CLARIFICATION: Karen firma, todo junto. (1) D1: con la opcion (a) recomendada, un "si" hablado no aprueba hoy ninguna hoja del padre (todas son riesgo alto segun 20c D1 y el test de riesgo); la hoja se anuncia, el "no" rechaza y el "si" pide el clic. ¿Aceptas (a), o quieres (b), que `open_url` a un host no dicho se apruebe por voz, revirtiendo el "exfil sink" de ApprovalRisk y 20d §11? (2) (c), lo critico por voz, solo despues de que Touch ID este en el codigo: ¿lo quieres en ese momento o nunca? (3) D2: hold de respuesta (P2), donde una pulsacion sobre una hoja anunciada no corta hasta oir las palabras, y cualquier cosa que no sea un "si" corta como en #87. (4) Un "no" explicito: ¿basta el aviso actual de corte o quieres una frase propia en es/en?]

## 10. Checklist de estandar

- [ ] RED primero: el test de caracterizacion `characterizationASpokenYesToAParentSheetInClassicActsOnNothing` se reescribe para el comportamiento nuevo y falla en `origin/main` d0da1b0: tras el hold con "si", la hoja sigue estacionada (`resolve` devuelve true) y `execute` no corrio.
- [ ] Test: una hoja del padre estacionada en clasico encola una sola `Escalation.approvalAskedSpoken` y queda con `announcedAt` solo cuando el sintetizador emite `.finished`.
- [ ] Test: una pulsacion que corta esa pregunta antes de que termine deja `announcedAt` en nil, y el "si" siguiente pide el clic.
- [ ] Test con el actor `Approvals` real: hoja anunciada, hold con "si" despues del `dwell`, la tarjeta sigue en `approvalQueue`, no hay `.approvalWithdrawn`, la voz dice `approvalNeedsClickSpoken` y `execute` no corre (opcion a).
- [ ] Test: hoja anunciada y hold con otra frase ("mejor abre el correo"): se publica `.approvalWithdrawn`, `execute` no corre, y el turno nuevo recibe esas palabras.
- [ ] Test de no regresion de #87: Stop o "para" con la hoja anunciada siguen retirandola, y un "si" posterior contesta `.nothingPending`.
- [ ] Test de no regresion de #87 con `ScriptedApprovals(park: true)`: turno cortado y despues `resolve(approved: true)`, y `execute` no corre.
- [ ] Test: una hoja NO anunciada (pregunta cortada o aun sonando) se comporta como hoy: la pulsacion corta y la retira.
- [ ] Test: el hold de respuesta que empieza antes de `announcedAt + dwell` no se admite como "si".
- [ ] Los tests de `ApprovalRiskTests` siguen pasando sin cambios (opcion a); `open_url`, manos y entregables siguen siendo `.high`.
- [ ] Realtime sin cambios: `RealtimeBargeInWithdrawsTests` y `testARealtimeYesNeverReachesTheJob` siguen pasando.
- [ ] El comentario de `VoiceSession.swift:324` dice lo que el codigo hace despues del cambio.
- [ ] Sin frases nuevas sin decision de Karen; si se agrega una, va en es y en en, y el test de completitud del catalogo la cubre.
- [ ] Sin contador de generacion; el hold de respuesta se distingue por estado del reductor y por `Task.isCancelled`.
- [ ] La suite completa pasa en el job de ThreadSanitizer.
- [ ] Si Karen firma (b) o (c), cada una va en un PR aparte con su propio RED (`ApprovalRiskTests` cambia de forma explicita) y, para (c), despues de que `.verifyOwner` exista.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | TaskCancellation.swift (isCancelled, withTaskCancellationHandler) | swiftlang/swift | swift-6.2-RELEASE | 2026-10-02 | high |
| 2 | Dialog Interface Reference (Dialog.ConfirmIntent) | Amazon Alexa | actualizado 2023-11-28 | 2026-10-02 | high |
| 3 | IntentAuthenticationPolicy | Apple App Intents | macOS 13.0+ | 2026-10-02 | high |
| 4 | Realtime guide, Tool approvals | OpenAI Agents SDK | a575a6e | 2026-10-02 | high |
| 5 | Human in the loop | OpenAI Agents SDK | a575a6e | 2026-10-02 | high |
| 6 | src/agents/realtime/session.py | OpenAI Agents SDK | a575a6e | 2026-10-02 | high |
| 7 | libs/langgraph/langgraph/types.py (interrupt) | LangChain | 157a06d | 2026-10-02 | medium |

[KAREN:chat 2026-10-02] Reemplaza el 'si' delegado por el orquestador el 2026-10-01: se mantiene 20c D1. D1: opcion (a), ninguna hoja del padre se aprueba por voz; el 'no' la rechaza y el 'si' contesta que necesita su clic. No (b). Las criticas (c) nunca solo por voz: pasan por Touch ID segun su propia spec, con su propia firma. D2: P2, el hold de respuesta. D3: el 'no' explicito tiene su propia frase, no 'me interrumpiste'.

[KAREN:chat 2026-10-02] Despues del plan (el planner leyo el codigo): el primer supuesto de la seccion 9 es falso en produccion. El synth solo emite `.finished` al cerrar su stream, y el turno clasico lo cierra despues de su ultima ronda (`ClassicRuntime.swift:477`), asi que el turno con la hoja estacionada nunca llega a `.idle`. Por eso el turno cierra su stream y descansa al estacionar la hoja. Karen decide: (1) acepta desviarse de D3 en la forma: la pregunta va por la cola de anuncios (`askApprovalAloud` -> `markQuestionSaid`), que estampa `announcedAt` solo en `.finished`; (2) cinco PR chicos, cada uno con merge propio, a lo mas 4 archivos de fuente, su fragmento y tres revisores: 1a vocabulario del reducer, 1b el turno descansa y pregunta, 2a hold de respuesta, 2b-1 vocabulario del "no", 2b-2 cableado del "no"; (3) despues de un "no" hablado el turno termina solo con la frase fija del "no", sin segunda ronda del modelo; el rechazo por clic sigue como hoy. Quedan los defaults: manos libres fuera de alcance, y una pulsacion sobre una pregunta sin terminar es un corte (gana el item 8 de la seccion 10). La lista de palabras del "no" y la copia es/en las propone el agente y la copia la decide Karen.
