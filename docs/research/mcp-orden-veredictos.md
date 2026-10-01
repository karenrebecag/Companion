# Reference Brief: orden de los veredictos MCP en el transporte realtime

Slug: mcp-orden-veredictos | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

El CI 36906986048 (PR #81, que solo toca CI) fallo en `testQueuedMCPRequestsAnswerInOrder` (MCPToolsTests.swift:182-183): llegaron `["req10","req9"]` y `[false,true]`, se esperaba `["req9","req10"]` y `[true,false]`.
Pregunta: por que camino viaja `approvalAnswered` desde `SessionModel` (MainActor) hasta el `mcp_approval_response` en el transporte, y en que punto se pierde el orden.
Decision 1: el orden en el cable entre veredictos de ids distintos, es requisito de producto o solo lo exige el test.
Decision 2: si es requisito, que patron documentado lo garantiza; si no lo es, que debe asertar el test en su lugar.
Decision 3: que RED determinista demuestra el defecto (o su ausencia) sin depender del planificador.
Toolchain local al investigar: Apple Swift 6.3.3 (swift --version), tools-version 6.2; sin la upcoming feature NonisolatedNonsendingByDefault.

## 2. Estado actual

Contextos: swift test local (paralelo), CI macos-26 con `swift test --no-parallel` (gates.sh), CI tsan con `swift test --sanitize=thread --no-parallel` (tsan.sh), app real con RealtimeWSTransport.
- La hoja avanza de forma sincrona dentro de `send`: el reductor corre y la proyeccion se publica antes de ejecutar ningun efecto [repo:Sources/CompanionUI/Voice/SessionModel.swift:59]
- La proyeccion nueva (req10 al frente) ya es visible al volver de `send`, antes de que el veredicto de req9 salga [repo:Sources/CompanionUI/Voice/SessionModel.swift:60]
- Los efectos se ejecutan despues de publicar la proyeccion [repo:Sources/CompanionUI/Voice/SessionModel.swift:84]
- El reductor saca la peticion de la cola y emite `.resolveApproval` con su id [repo:Sources/CompanionCore/Session/SessionMachine.swift:121]
- Cada `.resolveApproval` lanza su propia Task no estructurada hacia el actor `Approvals` (H1, primer salto) [repo:Sources/CompanionUI/Voice/SessionModel.swift:112]
- CompanionUI tiene aislamiento por defecto MainActor, asi que esa Task hereda MainActor y luego salta al actor Approvals [repo:Package.swift:36]
- `Approvals.resolveNow` reanuda la continuacion de la peticion; no envia nada por si mismo [repo:Sources/CompanionServices/Approvals/Approvals.swift:82]
- Cada peticion MCP que llega del server vive en su propia Task no estructurada, aparcada hasta el veredicto (segundo y principal punto de desorden) [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:320]
- Esa Task espera `mcpGuard.decide`, que es la que recibe la reanudacion [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:32]
- `ParentToolGuard` es un struct, asi que `decide` es una funcion async no aislada [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:14]
- `decide` se declara sin anotacion de aislamiento [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:85]
- CompanionServices no declara swiftSettings, luego no activa NonisolatedNonsendingByDefault [repo:Package.swift:25]
- Tras el veredicto, la Task vuelve al actor VoiceSession y manda el frame `mcp_approval_response` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:41]
- Cada veredicto va seguido de su propio `response.create` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:43]
- `RealtimeRuntime.send` es nonisolated(nonsending): corre en el actor del llamador, VoiceSession [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:224]
- De ahi llama `transport.send`, requisito de protocolo async sin anotacion de aislamiento [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:230]
- El requisito del protocolo es `func send(_ json: String) async throws` [repo:Sources/CompanionCore/Voice/VoicePorts.swift:15]
- El fake cuenta el intento y anexa el frame dentro de un mismo lock, en el orden en que llegan las llamadas (H2: el lock no reordena) [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:243]
- El fake ya expone `sendAttempts`, contado bajo el mismo lock [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:241]
- `mcpVerdicts` solo filtra y decodifica `transport.sent`; preserva el orden de anexado [repo:Tests/CompanionIntegrationTests/MCPToolsTests.swift:111]
- El transporte real es un actor, otro salto con cola de actor [repo:Sources/CompanionServices/Voice/Realtime/RealtimeWSTransport.swift:14]
- El harness inyecta `Approvals` y crea `SessionModel` sin puerto de voz [repo:Tests/CompanionIntegrationTests/MCPToolsTests.swift:96]
- El test manda el segundo clic en cuanto la proyeccion muestra req10, que ocurre de forma sincrona tras el primer clic [repo:Tests/CompanionIntegrationTests/MCPToolsTests.swift:179]
- El test aserta el orden de ids en el cable [repo:Tests/CompanionIntegrationTests/MCPToolsTests.swift:182]
- El test aserta el orden de los booleanos, que depende del mismo orden [repo:Tests/CompanionIntegrationTests/MCPToolsTests.swift:183]
- La spec 10c promete cola en orden de llegada para la hoja (lo que se muestra), no para el cable [repo:docs/specs/wave-10c-nada-se-pierde.md:503]
- En CI el suite corre con --no-parallel [repo:scripts/gates.sh:266]
- El job TSan corre el suite con --sanitize=thread [repo:scripts/tsan.sh:18]

## 3. Fuentes primarias

- Las Tasks que esperan un actor no tienen garantizado ejecutarse en el orden en que lo esperaron; el runtime prioriza evitar inversiones de prioridad [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- En un actor reentrante otro trabajo puede intercalarse en cada punto de suspension [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- Una funcion async no aislada corre en el ejecutor generico y, llamada desde un actor, sale de el de inmediato [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@6.2]
- Sin la upcoming feature NonisolatedNonsendingByDefault, una funcion nonisolated async es @concurrent; nonisolated(nonsending) corre en el actor del llamador [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- Solo dos Tasks con aislamiento explicito al mismo actor tienen garantizado empezar en ese actor en el orden de creacion; esa garantia es del arranque, no de los saltos posteriores [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md@6.2]
- `AsyncStream.Continuation.yield` es sincrono y vuelve al llamador sin esperar al consumidor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md@6.2]
- AsyncStream entrega lo encolado en orden FIFO y la iteracion concurrente es un error de programacion: un solo consumidor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md@6.2]
- El cliente contesta cada `mcp_approval_request` con un item `mcp_approval_response` que lleva su `approval_request_id` y `approve` [doc:https://developers.openai.com/api/docs/guides/realtime-mcp@2026-10-01]
- La guia de Realtime con MCP no dice nada sobre el orden entre respuestas a peticiones distintas ni sobre varias peticiones pendientes a la vez [doc:https://developers.openai.com/api/docs/guides/realtime-mcp@2026-10-01]

## 4. Implementaciones de referencia

- LiveKit client-sdk-swift (SDK oficial de LiveKit, activo): encola las peticiones salientes en un AsyncStream y las drena una sola Task, citando que una Task por callback puede desordenar un par publish/unpublish [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/Room+DataTrack.swift#L320-L338@404f4a1]
- cmux de manaflow-ai (unos 27.5k estrellas, push del 2026-10-01): `log` solo hace yield a un AsyncStream y un consumidor unico de larga vida conserva el orden de emision [ref:https://github.com/manaflow-ai/cmux/blob/15cf1ed6b99bfb009caea567c2c47c02ed6fd0f1/Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/DebugSupport/BackgroundLogWriter.swift#L24-L31@15cf1ed]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. El test aserta pares (id, approve) sin orden | Alinea el test con lo que el protocolo documenta: el veredicto se casa por id; cero cambio de producto | No protege si el orden resultara importar al server; deja dos response.create en carrera | baja | Recomendada salvo que Karen declare el orden requisito |
| B. Buzon de salida: VoiceSession hace yield de cada veredicto a un AsyncStream y una sola Task lo envia | Patron documentado (SE-0314 + LiveKit + cmux); orden de cable = orden de resolucion | Toca VoiceSession y su ciclo de vida (finish al colgar); orden de resolucion aun puede diferir del orden de clic por los saltos de :112 y :320 | media | Solo si el orden es requisito |
| C. B mas orden de clic de punta a punta: SessionModel tambien pasa sus resolve por un stream de un solo consumidor | Orden de clic preservado hasta Approvals | Dos colas que mantener; las Tasks por peticion (:320) siguen reanudandose fuera de orden, asi que no basta sin B | alta | No, salvo evidencia de que B no alcanza |
| D. Subir la prioridad de la segunda Task o esperar en el test a que salga el primero | Rapido | La prioridad es una pista, no un orden (SE-0306); esperar en el test oculta el defecto sin decidir el requisito | baja | No |

## 6. Evidencia en contra

- Contra A: cada veredicto dispara su propio response.create, y si req10 y su response.create salen antes que req9 el server podria arrancar una respuesta con req9 aun pendiente; la guia no documenta ese caso [doc:https://developers.openai.com/api/docs/guides/realtime-mcp@2026-10-01]
- Se acepta para A porque cada peticion MCP ya manda su veredicto desde su propia Task, asi que dos clics separados por milisegundos pueden cruzarse hoy igual que en el test [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:320]
- Y cada peticion lleva su propio temporizador de auto-deny, que resuelve por id sin mirar el orden de las demas [repo:Sources/CompanionServices/Approvals/Approvals.swift:52]
- Contra B: un buffer con drop-oldest perderia un veredicto en rafaga; la referencia de cmux usa buffer acotado con descarte, que aqui seria incorrecto [ref:https://github.com/manaflow-ai/cmux/blob/15cf1ed6b99bfb009caea567c2c47c02ed6fd0f1/Packages/macOS/CmuxTerminalCore/Sources/CmuxTerminalCore/DebugSupport/BackgroundLogWriter.swift#L33-L36@15cf1ed]
- Contra B tambien: B ordena por resolucion, no por clic, porque las dos Tasks de :320 se reanudan desde Approvals sin orden garantizado [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]

## 7. Ejemplares y anti-ejemplos

- Bien: productor sincrono hace `continuation.yield(x)` y una unica Task hace `for await x in stream { await send(x) }` [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/Room+DataTrack.swift#L320-L338@404f4a1]
- Anti-ejemplo: una Task por evento hacia un actor, como `Task { _ = await approvals.resolve(...) }` por cada clic [repo:Sources/CompanionUI/Voice/SessionModel.swift:112]
- Anti-ejemplo: una Task por peticion que envia al reanudarse, sin cola comun de salida [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:320]

## 8. Trampas

- La proyeccion avanza antes de que salga el veredicto, asi que esperar a "req10 al frente" no ordena nada en el cable [repo:Sources/CompanionUI/Voice/SessionModel.swift:60]
- Con --no-parallel en CI el proceso tiene menos carga que en local; el desorden depende de la planificacion y puede aparecer en cualquiera de los tres contextos [repo:scripts/gates.sh:266]
- TSan ralentiza y cambia el intercalado; un test que pasa sin TSan no prueba nada del orden bajo TSan [repo:scripts/tsan.sh:18]
- `sendAttempts` cuenta todos los frames (session.update, response.create), no solo veredictos; un RED que lo use debe filtrar por tipo [repo:Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift:241]
- El transporte real es un actor: aunque el fake se arreglara, el cable real tiene su propio salto no FIFO [repo:Sources/CompanionServices/Voice/Realtime/RealtimeWSTransport.swift:14]
- Activar NonisolatedNonsendingByDefault quitaria los saltos @concurrent de `decide` y del fake, pero no las dos Tasks independientes de :320 [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]

## 9. Incertidumbre

- ASSUMPTION: el desorden observado nace tras la reanudacion en Approvals (dos Tasks de :320 compitiendo por saltos a VoiceSession y al ejecutor generico), no en el salto de :112. prueba: en una rama, registrar con un contador atomico el orden de entrada a `Approvals.resolveNow` y el orden de anexado en el fake durante 500 repeticiones del test bajo `swift test --sanitize=thread`; si resolveNow sale siempre req9,req10 y el fake a veces no, el punto es :320.
- ASSUMPTION: RED determinista para el estado actual: el fake retiene el primer `mcp_approval_response` en una continuacion; el test hace pumpUntil hasta que el fake registra un segundo intento de veredicto mientras el primero sigue retenido, y entonces aserta que no deberia haberlo. Hoy eso ocurre siempre porque las dos Tasks son independientes; con la opcion B nunca ocurre. prueba: implementarlo y correrlo 200 veces local y bajo TSan; debe fallar en las 200 hoy.
- ASSUMPTION: el lado GREEN de ese RED con la opcion B necesita una espera negativa (settle) para afirmar que el segundo no salio, lo que no es determinista en sentido estricto. prueba: liberar el primero y asertar el orden final [req9, req10] en lugar de la ausencia; comprobar que ese assert falla hoy con el retenido.
- ASSUMPTION: subir la prioridad de la segunda Task no da un RED fiable, porque la prioridad es una pista para el planificador. prueba: correr 200 veces con `Task(priority: .high)` en el segundo clic y contar fallos; menos de 200 lo descarta.
- ASSUMPTION: el server de OpenAI acepta veredictos de ids distintos en cualquier orden. prueba: en una sesion real con dos herramientas MCP con aprobacion, contestar primero la segunda y verificar en los eventos que ambas llamadas MCP se ejecutan o niegan segun su id.
- [NEEDS CLARIFICATION: Karen, el orden en que salen al server los veredictos de dos permisos MCP en cola es una promesa del producto (opcion B) o basta con que cada uno llegue con su id y su respuesta (opcion A)? Ninguna spec lo dice y la guia de OpenAI tampoco.]

## 10. Checklist de estandar

- [ ] El test de cola MCP no depende del planificador: o aserta pares (id, approve) sin orden, o el producto garantiza el orden con un unico consumidor.
- [ ] Si se elige orden: un solo AsyncStream de salida con buffer unbounded y una sola Task consumidora por sesion; ningun veredicto se envia desde la Task de su peticion.
- [ ] Si se elige orden: el stream se cierra (finish) al colgar y un veredicto tardio tras el cierre no se envia.
- [ ] Existe un RED que retiene el primer veredicto en el fake y falla en el 100% de las corridas sobre el codigo actual.
- [ ] El test pasa 200 veces seguidas en local, con --no-parallel y bajo --sanitize=thread.
- [ ] El emparejamiento id con approve se aserta siempre, decodificado del frame, no por subcadena.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0306 Actors | Swift Evolution (swiftlang) | Implementado en Swift 5.5 | 2026-10-01 | high |
| 2 | SE-0338 Clarify the Execution of Non-Actor-Isolated Async Functions | Swift Evolution (swiftlang) | Implementado en Swift 5.7 | 2026-10-01 | high |
| 3 | SE-0461 Run nonisolated async functions on the caller's actor by default | Swift Evolution (swiftlang) | Implementado en Swift 6.2 | 2026-10-01 | high |
| 4 | SE-0431 @isolated(any) Function Types | Swift Evolution (swiftlang) | Implementado en Swift 6.0 | 2026-10-01 | high |
| 5 | SE-0314 AsyncStream and AsyncThrowingStream | Swift Evolution (swiftlang) | Implementado en Swift 5.5 | 2026-10-01 | high |
| 6 | Realtime with tools (MCP) | OpenAI | sin fecha en la pagina | 2026-10-01 | medium |
| 7 | client-sdk-swift Room+DataTrack.swift | LiveKit | 404f4a1 | 2026-10-01 | high |
| 8 | cmux BackgroundLogWriter.swift | manaflow-ai | 15cf1ed | 2026-10-01 | medium |

[KAREN:chat 2026-10-01] Q1: opcion A, el orden no es promesa de producto; el test aserta pares (id, approve) sin orden. Antes del commit del brief se corrige la cita sin respaldo de Approvals.swift:52. Q2: no se corren las sondas de la opcion B (200 corridas y TSan); basta el test nuevo en RED/GREEN y unas 20 corridas locales en serie. La prueba con el server real (veredictos cruzados) queda para la QA por MCP de la app.
