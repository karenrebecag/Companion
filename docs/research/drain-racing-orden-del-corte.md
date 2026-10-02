# Reference Brief: orden del corte cuando el drain compite con el siguiente turno

Slug: drain-racing-orden-del-corte | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 AUTO

## 1. Pregunta y decisiones abiertas

El test aDrainRacingTheNextTurnThreadsTheCutReplyOnceAndFirst fallo una vez en gates locales bajo carga (9.852 s contra 0.356 s), sobre main 10341d9 (ya con #78): got ["go", cutWords], want [cutWords, "go"]; la asercion "one note" paso.
Toolchain observado en esta corrida con swift --version: Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0.

Decisiones:
- D1. Cual de H1 (la caida no se proceso cuando corre el commit), H2 (ventana de reentrada en threadCutReply) o H3 (el test exige algo que el codigo no promete) sostiene el codigo.
- D2. Que RED determinista separa H1 de H2.
- D3. Si H2 se sostiene: el commit espera un threading en vuelo (a), se limpia el estado despues del await (b), o un funnel unico de escrituras al hilo (c); y si la correccion va al test o a RealtimeRuntime/VoiceSession.

Respuesta corta: el codigo sostiene H2, pero con un mecanismo distinto del que propuso b6. No hay reordenamiento por prioridad en un executor serial. En los tests, ScriptedThread es una clase sin aislamiento, asi que appendAssistant y appendUser corren en el executor generico concurrente y compiten en paralelo por el NSLock del fake. H1 queda refutada por el orden del codigo y por la asercion "one note". H3 se acepta solo en parte: el invariante depende del executor del presentador y el protocolo no lo exige.

## 2. Estado actual

- RealtimeRuntime es una clase final @unchecked Sendable, no un actor; sus metodos async son nonisolated(nonsending) y corren en el actor del llamador (VoiceSession) [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:13]
- El comentario de la clase declara esa regla: cada metodo async corre en el actor del llamador [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:6]
- unthreadedCut guarda la respuesta cortada hasta que el reproductor drena [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:92]
- resetConnection es sincrono y fija unthreadedCut y cutNote al parcial cuando hubo corte [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:121]
- La asignacion de cutNote ocurre solo dentro de resetConnection, junto con unthreadedCut [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:132]
- threadCutReply es nonisolated(nonsending), toma el parcial y lo pone a nil antes de suspenderse en appendAssistant [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:158]
- El primer await de threadCutReply es thread.appendAssistant(partial), con unthreadedCut ya en nil [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:161]
- commitWithText llama threadCutReply(announce: false) y despues thread.appendUser [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:248]
- El comentario sobre ese llamado promete el orden: un turno que le gana al drain igual va despues de la respuesta que contesta [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:246]
- El appendUser del commit es la linea siguiente, sin otra sincronizacion con un threading en curso [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:249]
- Otro escritor del hilo en el mismo runtime: assistantTranscriptDone hace finishStream y appendAssistant [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:334]
- VoiceSession es un actor (default actor), asi que los llamadores de threadCutReply corren en su executor [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:4]
- El drain pump se crea con Task {} sin prioridad explicita, desde startPumps, aislado al actor VoiceSession [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:30]
- pumpDrained hace apply(.playerDrained) y luego threadCutReply(announce: true), en el actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:322]
- El otro llamador del drain es settleSpeechAfterReconnect, solo si el reproductor no tiene audio pendiente [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:223]
- En la reconexion, resetConnection corre antes de prepareSessionUpdate y flushPendingUpdate, sin await de por medio [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:206]
- El segundo session.update sale por flushPendingUpdate, despues del reset en el mismo trabajo del actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:210]
- didBecomeReady pasa a true solo al llegar sessionUpdated en el pump de eventos [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:131]
- connectionReady espera openCount == n, sessionUpdates == n y ready leido en el actor [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:201]
- dropWhileSpeaking termina con simulateStreamEnd y connectionReady(h, 2) [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:417]
- probeCommit corre commitWithText en el actor VoiceSession [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:400]
- El test lanza dos Task @MainActor: yieldDrained (sincrono) y probeCommit("go"), sin prioridad explicita [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:700]
- La asercion que fallo exige [cutWords, "go"] en h.thread.turns [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:706]
- El comentario del test atribuye el entrelazado al main actor, pero los dos caminos corren en el actor VoiceSession [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:694]
- yieldDrained es sincrono: solo cede un elemento al stream drained [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:356]
- ScriptedThread es una final class @unchecked Sendable sin aislamiento de actor, con un NSLock [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:510]
- appendAssistant del fake es async no aislado y toma el lock sin suspenderse [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:555]
- appendUser(_:context:) del fake es async no aislado y toma el mismo lock [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:548]
- El target de soporte de tests no declara swiftSettings, asi que no tiene defaultIsolation ni NonisolatedNonsendingByDefault [repo:Package.swift:57]
- Package.swift solo pone defaultIsolation(MainActor) en CompanionUI y CompanionApp [repo:Package.swift:36]
- El presentador de produccion, ChatViewModel, es @MainActor [repo:Sources/CompanionUI/Chat/ChatViewModel.swift:6]
- El protocolo ConversationPresenting solo exige Sendable; no exige un executor serial ni un orden de entrega [repo:Sources/CompanionCore/Chat/ChatPorts.swift:100]
- Gates locales corren swift test en paralelo; solo con CI=true pasan --no-parallel [repo:scripts/gates.sh:266]
- El job de TSan corre la suite con --sanitize=thread y --no-parallel [repo:scripts/tsan.sh:15]
- CI corre gates y TSan en runners macos-26 separados [repo:.github/workflows/ci.yml:30]
Contextos: swift test local bajo carga (gates.sh en paralelo, presentador ScriptedThread no aislado); CI macOS (macos-26, gates.sh con --no-parallel, mismo fake); job de TSan (scripts/tsan.sh, --sanitize=thread --no-parallel, mismo fake, mas lento por la instrumentacion); app real (presentador ChatViewModel @MainActor).

## 3. Fuentes primarias

- SE-0338: una funcion async no aislada a un actor corre formalmente en un executor generico, sin actor, y cambia a el en cada entrada y en cada reanudacion [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@5.7]
- SE-0461: nonisolated(nonsending) corre siempre en el actor del llamador; el cambio de comportamiento por defecto va detras de la feature NonisolatedNonsendingByDefault [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- En Swift 6.3.3, NonisolatedNonsendingByDefault es una upcoming feature que se activa recien en el modo de lenguaje 7 [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/include/swift/Basic/Features.def#L305@6.3.3]
- El executor generico en Darwin manda cada job a una cola global concurrente de dispatch segun su prioridad [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L245-L251@6.3.3]
- La cola global sale de dispatch_get_global_queue por QoS, que es concurrente [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L146-L211@6.3.3]
- El executor principal encola en dispatch_get_main_queue [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L393-L401@6.3.3]
- DispatchMainExecutor.enqueue delega en _dispatchEnqueueMain, y CFMainExecutor hereda de el [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchExecutor.swift#L59-L60@6.3.3]
- Un default actor guarda sus jobs en una cola por prioridad: los trabajos entrantes pasan de LIFO a FIFO y se insertan en el balde de su prioridad [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Actor.cpp#L1259-L1271@6.3.3]
- handleUnprioritizedJobs invierte la lista a FIFO y la mete en prioritizedJobs; drainOne saca el primero de mayor prioridad [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Actor.cpp#L1772-L1790@6.3.3]
- SE-0306: el runtime elige el siguiente trabajo del actor considerando la prioridad, a diferencia de una DispatchQueue serial, que es estrictamente FIFO [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@5.5]
- SE-0306: la reentrada entrelaza en cada punto de suspension; el codigo sincrono del actor es la seccion critica y un await la interrumpe [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@5.5]
- WWDC21 10133: hay que mutar el estado en codigo sincrono, restaurar la consistencia antes de un await y guardar la Task en curso para que un segundo llamador la espere en vez de repetir el trabajo [doc:https://developer.apple.com/videos/play/wwdc2021/10133/@2021]

## 4. Implementaciones de referencia

- apollo-ios-codegen (Apollo GraphQL, mantenido, push 2026-09-11): un actor guarda .inProgress(Task) en la cache y un segundo llamador hace await task.value en vez de reconstruir [ref:https://github.com/apollographql/apollo-ios-codegen/blob/3b5fb815f53e03da37b4f0599a1661123aabc384/Sources/IR/IRBuilder.swift#L55-L80@3b5fb815f53e03da37b4f0599a1661123aabc384]
- Gravatar-SDK-iOS (Automattic, push 2026-09-30): CacheEntry.inProgress(Task) documenta que el descargador espera la tarea en curso en vez de lanzar otra [ref:https://github.com/Automattic/Gravatar-SDK-iOS/blob/cc2275f3f533f7f24b134f6e352a76cbeb4a1dc6/Sources/Gravatar/Cache/ImageCaching.swift#L19-L55@cc2275f3f533f7f24b134f6e352a76cbeb4a1dc6]
- groue/Semaphore (Gwendal Roue, autor de GRDB; 630 estrellas, sin push desde 2024-08): AsyncSemaphore(value: 1) serializa los metodos de un actor contra la reentrada; es el funnel de la opcion c [ref:https://github.com/groue/Semaphore/blob/2543679282aa6f6c8ecf2138acd613ed20790bc2/README.md#L32-L48@2543679282aa6f6c8ecf2138acd613ed20790bc2]

## 5. Opciones

D1, que sostiene el codigo:

| Hipotesis | Veredicto | Por que |
|---|---|---|
| H1: el commit corre antes de resetConnection | Refutada | El segundo session.update que espera connectionReady sale en Pumps:210, despues del reset sincrono en Pumps:206 dentro del mismo trabajo del actor. Ademas, si el commit hubiera corrido sin reset, cutNote seria nil y la asercion "one note" habria fallado, y paso |
| H2: ventana de reentrada en threadCutReply | Se sostiene la ventana; el mecanismo es otro | El drain pone unthreadedCut a nil (:160) y se suspende en appendAssistant (:161). El actor queda libre, el commit encuentra nil y llama appendUser (:249). En tests, las dos llamadas van al executor generico concurrente (SE-0338) y compiten en paralelo por el NSLock del fake, asi que el orden queda al planificador. No hace falta prioridad: bajo carga basta con que el hilo del drain tarde |
| H2 por prioridad en un executor serial | No es lo que pasa en tests | Los appends no corren en un actor ni en el main queue, sino en el pool global. En la app, el destino es el main queue: una DispatchQueue serial FIFO (SE-0306), que encola primero el append del drain |
| H3: el test exige algo no prometido | Parcial | El codigo si promete el orden (:246). Lo que falta es el contrato: ConversationPresenting no exige un executor FIFO, y el invariante solo se cumple por accidente con un presentador @MainActor |

D3, si H2 se sostiene:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| a. Guardar la Task del threading en curso y que commitWithText la espere (await inFlight?.value) | Patron documentado (WWDC21 10133, Apollo, Gravatar). unthreadedCut sigue limpiandose de forma sincrona, sin doble threading. El orden ya no depende del executor del presentador | Una Task no estructurada no hereda la cancelacion del drain pump, asi que el append termina aunque el pump se cancele (lo que se busca: no perder la respuesta). Hay que limpiar inFlight por identidad, y reset() debe decidir si la espera o la suelta. Agrega un salto de executor | baja | Recomendada |
| b. Limpiar unthreadedCut despues del await | Un cambio de una linea | Un commit que entra durante el await ve el parcial todavia puesto y lo anexa otra vez, y la asercion "once" falla por doble threading. Contradice la guia de restaurar la consistencia antes del await. Un reset() durante el await tambien se pisa con el nil tardio | baja | Descartar sola |
| c. Funnel unico (AsyncSemaphore o cola) para toda escritura al hilo desde el runtime | Cubre a todos los escritores (:161, :249, :329, :334, :400), no solo al par drain/commit | Mas superficie. Riesgo de deadlock si algo dentro de la seccion espera al funnel. La cancelacion exige elegir entre wait y waitUnlessCancelled. Agrega una dependencia o un primitivo propio | media | Si (a) no alcanza |
| d. Solo el fake: ScriptedThread con metodos nonisolated(nonsending) o @MainActor | El test vuelve a modelar la app | Deja el invariante implicito en el executor del presentador; un presentador futuro no aislado lo rompe en silencio | baja | Complemento, no correccion |

D2, el RED: la sonda de H2 es determinista y no depende de la carga. La de H1 sirve como evidencia, no como RED (ver seccion 10).

## 6. Evidencia en contra

- En contra de corregir el codigo: en la app, el presentador es @MainActor y el main queue es FIFO, asi que el bug podria no existir en produccion [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@5.5]
- Se acepta corregir igual: el invariante queda prometido en el comentario del codigo y no en el protocolo, que solo exige Sendable [repo:Sources/CompanionCore/Chat/ChatPorts.swift:100]
- En contra de la opcion a: el default actor reordena por prioridad, asi que con varios commits en espera el orden entre ellos sigue sujeto a prioridad; solo el par drain-commit queda ordenado [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Actor.cpp#L1259-L1271@6.3.3]
- Se acepta porque el test y la promesa de :246 solo hablan del par respuesta cortada y turno siguiente [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:246]
- En contra de H2 como causa unica: no se reprodujo en esta corrida; la falla se observo una vez y el brief infiere el mecanismo solo leyendo el codigo [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:706]

## 7. Ejemplares y anti-ejemplos

- Bien hecho: el actor guarda la Task en curso antes de suspenderse, y el segundo llamador hace await task.value [ref:https://github.com/apollographql/apollo-ios-codegen/blob/3b5fb815f53e03da37b4f0599a1661123aabc384/Sources/IR/IRBuilder.swift#L63-L79@3b5fb815f53e03da37b4f0599a1661123aabc384]
- Bien hecho: la seccion serializada toma el semaforo con await y lo suelta con defer [ref:https://github.com/groue/Semaphore/blob/2543679282aa6f6c8ecf2138acd613ed20790bc2/README.md#L38-L46@2543679282aa6f6c8ecf2138acd613ed20790bc2]
- Anti-ejemplo: comprobar el estado y suspenderse sin dejar rastro de la operacion en curso, que es el sad cat de WWDC21 10133 [doc:https://developer.apple.com/videos/play/wwdc2021/10133/@2021]
- Anti-ejemplo local: threadCutReply suelta el estado en :160 y se suspende en :161 sin marca de en vuelo que el commit pueda esperar [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:160]

## 8. Trampas

- En el swift test local bajo carga, el fake corre los appends en el pool global en paralelo, asi que la carrera aparece de forma intermitente [repo:scripts/gates.sh:266]
- En CI macOS, --no-parallel baja la carga pero no la elimina: el pool global sigue siendo concurrente con pocos vCPU [repo:scripts/gates.sh:259]
- En el job de TSan, la instrumentacion ensancha la ventana; TSan no la reporta porque el NSLock del fake hace que no haya data race, solo un orden indeterminado [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:515]
- En la app, con ChatViewModel @MainActor, los dos appends se encolan en el main queue en orden de programa, que es FIFO [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L393-L401@6.3.3]
- Activar NonisolatedNonsendingByDefault en el target de soporte cambiaria en silencio donde corren todos los fakes; hoy ese target no declara swiftSettings [repo:Package.swift:57]
- La opcion b produce doble threading: el commit veria el parcial todavia puesto y lo anexaria de nuevo [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:159]
- assistantTranscriptDone tambien escribe al hilo; un funnel que solo cubra el par drain/commit deja ese escritor fuera [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:334]
- reset() pone unthreadedCut a nil; con la opcion a, un reset durante un threading en vuelo tiene que decidir que hace con la Task [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:115]
- El comentario del test (:694) atribuye el entrelazado al main actor; si se arregla solo el comentario o solo el fake, el siguiente lector busca en el lugar equivocado [repo:Tests/CompanionIntegrationTests/VoiceReconnectTests.swift:694]

## 9. Incertidumbre

- ASSUMPTION: la falla observada es el entrelazado drain(nil) -> commit(appendUser) con los dos appends en paralelo en el pool global. prueba: el RED con el fake retenido de la seccion 10, que da ["go", cutWords] de forma determinista con el codigo actual.
- ASSUMPTION: en la app, el append del drain se encola en el main queue antes que el del commit, porque el salto de VoiceSession a MainActor encola al suspenderse. prueba: un fake @MainActor del presentador y 1000 iteraciones del test bajo `swift test --parallel` en paralelo con una carga de CPU, con 0 fallas esperadas.
- ASSUMPTION: el drain pump y la Task del commit tienen la misma prioridad, asi que la prioridad no participa. prueba: registrar Task.currentPriority dentro de pumpDrained y de probeCommit en una corrida del test.
- ASSUMPTION: H1 no ocurre nunca despues de connectionReady. prueba: una sonda en el actor que devuelva unthreadedCut != nil justo despues de connectionReady(h, 2), en 1000 iteraciones.
- [NEEDS CLARIFICATION: el contrato de ConversationPresenting, si debe exigir entrega FIFO de un mismo llamador (documentado en el protocolo) o si el runtime debe ordenar por su cuenta (opcion a). La recomendacion es la a, que no depende del presentador.]

## 10. Checklist de estandar

- [ ] RED H2 determinista: ScriptedThread gana un hold de appendAssistant (continuacion liberada por el test) y una senal de entrada. El test suelta el drain, espera a que appendAssistant entre (unthreadedCut ya en nil), lanza probeCommit("go"), espera hasta 0.2 s y libera. Con el codigo actual falla con ["go", cutWords]; con la correccion pasa.
- [ ] El RED no depende de la carga ni de prioridades: pasa o falla igual en el swift test local, en CI macOS y en el job de TSan.
- [ ] Evidencia de H1: tras connectionReady(h, 2), una sonda en el actor confirma que el corte esta pendiente (unthreadedCut no nil), en 1000 de 1000 iteraciones.
- [ ] La correccion vive en RealtimeRuntime: commitWithText no anexa el turno del usuario mientras un threading del corte siga en vuelo.
- [ ] unthreadedCut se sigue limpiando de forma sincrona antes de cualquier await (sin doble threading); el test conserva "once" y "one note".
- [ ] reset() durante un threading en vuelo queda definido y probado: no deja el commit esperando para siempre ni anexa un parcial de la sesion anterior.
- [ ] Una cancelacion del drain pump no deja al commit esperando para siempre.
- [ ] El comentario del test en :694 describe el mecanismo real: actor VoiceSession y executor del presentador, no el main actor.
- [ ] El brief no exige cambiar el fake; si se cambia, la correccion del runtime igual queda probada con el fake no aislado.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0338 Clarify the execution of non-actor-isolated async functions | Swift Evolution | Swift 5.7 | 2026-10-01 | high |
| 2 | SE-0461 Run nonisolated async functions on the caller's actor by default | Swift Evolution | Swift 6.2 | 2026-10-01 | high |
| 3 | SE-0306 Actors | Swift Evolution | Swift 5.5 | 2026-10-01 | high |
| 4 | swift Features.def, DispatchGlobalExecutor.cpp, DispatchExecutor.swift, Actor.cpp | swiftlang/swift | swift-6.3.3-RELEASE 064859e | 2026-10-01 | high |
| 5 | WWDC21 10133 Protect mutable state with Swift actors | Apple | 2021 | 2026-10-01 | high |
| 6 | apollo-ios-codegen IRBuilder.swift | Apollo GraphQL | 3b5fb81 | 2026-10-01 | medium |
| 7 | Gravatar-SDK-iOS ImageCaching.swift | Automattic | cc2275f | 2026-10-01 | medium |
| 8 | groue/Semaphore README | Gwendal Roue | 2543679 | 2026-10-01 | medium |

[KAREN:chat 2026-10-01] D1: H2. D2: la sonda de H2 es el RED. D3: opcion (a), el commit espera la Task del threading en curso, en RealtimeRuntime; (c) solo si (a) no alcanza.
