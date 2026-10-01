# Reference Brief: liberacion del WKWebView colgado en diagramPageFailureTests

Slug: diagram-page-liberacion | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 AUTO

## 1. Pregunta y decisiones abiertas

`diagramPageFailureTests` espera 1 s fijo tras el `.timeout` de una pagina colgada y luego exige `weakView == nil`; bajo carga falla a veces (QA: MEDIUM).
Toolchain medido en esta Mac al investigar: `xcrun --show-sdk-version` = 26.5, Swift 6.3.3 (swiftlang-6.3.3.1.3), Xcode 26.6 (17F113), target arm64-apple-macosx26.0; CI corre en `macos-26`.
Decisiones:
- D1. Que cambia en el test: un sleep mas largo, o esperar el estado observable (`pumpUntil` sobre `weakView == nil`).
- D2. Si ademas hay que drenar el autorelease pool o girar el run loop a mano.
- D3. (fuera del test) Si el producto debe garantizar que una pagina colgada se suelte en un plazo acotado, en vez de depender del recolector de JavaScript.

Respuesta corta: el ultimo release del WKWebView no lo fija el timeout ni `tearDown`, sino la llegada del completion de `callAsyncJavaScript`, que para una promesa que nunca se resuelve WebKit solo entrega cuando el recolector de JSC finaliza sus handlers; ese momento no tiene cota documentada, asi que 1 s fijo es una apuesta. Esperar el estado observable con `pumpUntil` es lo correcto y no hace falta drenar pools a mano.

## 2. Estado actual

- El test baja el plazo del renderer a 400 ms para la pagina colgada [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:453]
- El test guarda la vista solo en una referencia weak a traves del observador [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:455]
- Tras el render siguiente duerme 1 s fijo [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:461]
- Y exige que la vista ya este liberada [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:462]
- El script falso, ante una fuente con "hang", devuelve una promesa que nunca se resuelve [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:94]
- El renderer entrega la vista al observador al crear la pagina [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:95]
- El scheduler corre el draw dentro de `DiagramTimeout.run` y devuelve `.timeout` sin esperar a que el draw termine [repo:Sources/CompanionCore/Deliverables/DiagramScheduler.swift:83]
- Al vencer el plazo, el timer llama `finish(nil)` [repo:Sources/CompanionCore/Deliverables/DiagramPorts.swift:88]
- `finish(nil)` cancela la Task del trabajo [repo:Sources/CompanionCore/Deliverables/DiagramPorts.swift:68]
- La cancelacion no desmonta en el acto: `onCancel` encola una Task nueva en el main actor que llama `tearDown`, que corre en un turno posterior [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:101]
- `tearDown` navega a una pagina vacia para fallar el script pendiente [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:146]
- `tearDown` suelta la unica propiedad que guarda la vista [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:150]
- `DiagramWebPage` solo retiene la vista por la propiedad `webView` [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:126]
- `DiagramWebPage` solo adopta los protocolos de navegacion y UI, no registra ningun WKScriptMessageHandler [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:125]
- El draw esta suspendido en `try await webView?.callAsyncJavaScript(...)`, con la vista evaluada antes de suspender [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:164]
- Cuando ese await falla, draw devuelve el fallo y libera su referencia temporal en ese turno [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:169]
- Despues `Self.draw` vuelve a llamar `tearDown` y retorna, soltando la pagina [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:103]
- `pumpUntil` tiene plazo de 30 s por defecto [repo:Tests/CompanionTestKit/TestKit.swift:104]
- Cada vuelta de `pumpUntil` hace `Task.yield` y luego `Task.sleep` de 2 ms, o sea suspende y devuelve el hilo principal a quien drena la cola main [repo:Tests/CompanionTestKit/TestKit.swift:110]
- Al vencer, `pumpUntil` registra el fallo con `expect` y la ubicacion del llamador [repo:Tests/CompanionTestKit/TestKit.swift:112]
- El test hermano de terminacion de proceso ya reemplazo una espera fija por un sondeo, citando que la espera fija es flake con la maquina ocupada [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:489]
- `watchedWeb` serializa los tests con WebKit real [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:162]
- `watchedWeb` impone su propio tope por test [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:177]
- En CI la suite corre sin paralelismo [repo:scripts/gates.sh:266]
- El runner de CI es macos-26 [repo:.github/workflows/ci.yml:15]
- Un job aparte corre la suite bajo ThreadSanitizer [repo:scripts/tsan.sh:18]
Contextos: swift test local (Swift Testing, @MainActor, watchedWeb, paralelo por defecto); swift test en CI macos-26 con --no-parallel; swift test --sanitize=thread en el job tsan; la app instalada (el mismo renderer en la isla)

- Trazado del turno en que cae la ultima referencia, armado con las lineas citadas arriba [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:98]
- Turno A (timer, main actor): `finish(nil)` cancela el trabajo, el `onCancel` encola la Task de `tearDown`, y el scheduler devuelve `.timeout` al test [repo:Sources/CompanionCore/Deliverables/DiagramPorts.swift:68]
- Turno B (main actor, cuando corre la Task encolada): `tearDown` navega a vacio y pone `webView = nil`; la vista sigue viva si el marco suspendido de draw la retiene (supuesto 1 de la seccion 9) [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:150]
- Turno C (main actor, cuando WebKit entrega el completion fallido): draw retoma, devuelve `.failed`, y su temporal es la ultima referencia fuerte [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:169]
- El turno C depende del recolector de JavaScript del proceso de contenido, no de un plazo del codigo propio (seccion 3) [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:94]

## 3. Fuentes primarias

- Apple: si el recolector reclama la promesa antes de resolverse, WebKit devuelve el error JavaScriptAsyncFunctionResultUnreachable al completion; el completion es @MainActor [doc:https://developer.apple.com/tutorials/data/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:).json@macOS-SDK-26.5]
- La pagina de Apple no dice que navegar fuera falle un callAsyncJavaScript pendiente; solo menciona el frame invalido al empezar la evaluacion [doc:https://developer.apple.com/tutorials/data/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:).json@macOS-SDK-26.5]
- Codigo de WebCore: para un thenable, el completion solo se llama desde fulfill, reject, o el finalizador de heap de ambos handlers ("no longer reachable"); no hay camino por navegacion [doc:https://github.com/WebKit/WebKit/blob/c95c0ba164f97fb789aa5db695cd7bec1791ad79/Source/WebCore/bindings/js/ScriptController.cpp#L884-L893@c95c0ba164f9]
- Codigo de WebKit (UIProcess): el callback de `_evaluateJavaScript` captura solo el bloque del completion, no la vista, asi que WebKit no retiene el WKWebView por la llamada pendiente [doc:https://github.com/WebKit/WebKit/blob/c95c0ba164f97fb789aa5db695cd7bec1791ad79/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm#L1561-L1577@c95c0ba164f9]
- Apple: `navigationDelegate` es `weak var`, el delegado no retiene la vista ni al reves [doc:https://developer.apple.com/tutorials/data/documentation/webkit/wkwebview/navigationdelegate.json@macOS-SDK-26.5]
- Runtime de Swift 6.3.3: un job del main actor se encola con dispatch en la cola main [doc:https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L394-L402@swift-6.3.3-RELEASE]
- Runtime de Swift 6.3.3: con CoreFoundation cargado, el main executor es CFMainExecutor, que corre CFRunLoopRun [doc:https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/Concurrency/PlatformExecutorDarwin.swift#L20-L26@swift-6.3.3-RELEASE]
- CFMainExecutor.run es CFRunLoopRun [doc:https://github.com/swiftlang/swift/blob/swift-6.3.3-RELEASE/stdlib/public/Concurrency/CFExecutor.swift#L52-L56@swift-6.3.3-RELEASE]
- libdispatch: la cola main se declara sin la bandera de autorelease por item, y su drenaje no abre un pool por bloque [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/init.c#L259-L268@2361ffb78a76]
- libdispatch: `_dispatch_main_queue_callback_4CF` no drena si ya esta drenando (reentrada), via `dq_side_suspend_cnt` [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/queue.c#L8325-L8336@2361ffb78a76]
- CoreFoundation (corelibs): el run loop envuelve el servicio de la cola main en `CFRUNLOOP_ARP_BEGIN(NULL)`, y el comentario dice que con rl nulo empuja un pool incondicional; en corelibs la macro esta vacia, asi que esto es indicio del CF de Darwin, no prueba [doc:https://github.com/swiftlang/swift-corelibs-foundation/blob/6f21ccf1461d160ffb27eb946e515d71269d8c1e/Sources/CoreFoundation/CFRunLoop.c#L3227-L3233@6f21ccf1461d]
- Apple: AppKit y UIKit procesan cada iteracion del event loop dentro de un pool; un programa sin framework de UI (herramienta de linea de comandos) debe crear los suyos [doc:https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html@archive-2016]
- Apple: cada cola de dispatch mantiene su pool pero no garantiza cuando lo drena [doc:https://developer.apple.com/library/archive/documentation/General/Conceptual/ConcurrencyProgrammingGuide/OperationQueues/OperationQueues.html@archive-2012]

## 4. Implementaciones de referencia

- WebKit TestWebKitAPI, test de fugas de WKURLSchemeHandler: crea vistas en `@autoreleasepool` anidados y al cerrar cada uno gira el run loop hasta que el contador observable baje; referencia porque es la suite de API del propio equipo de WebKit [ref:https://github.com/WebKit/WebKit/blob/334dd2883a2c25b8ba9839a86db632738101155f/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/WKURLSchemeHandler-leaks.mm#L68-L106@334dd2883a2c]
- WebKit TestWebKitAPI, `Util::run` y `spinRunLoop`: esperan una bandera girando el run loop, nunca con un sleep fijo [ref:https://github.com/WebKit/WebKit/blob/334dd2883a2c25b8ba9839a86db632738101155f/Tools/TestWebKitAPI/Helpers/cocoa/UtilitiesCocoa.mm#L32-L53@334dd2883a2c]
- Nimble (Quick), `pollBlock` async: evalua el predicado, duerme con `Task.sleep` el intervalo y corta al plazo; mismo esquema que `pumpUntil`; referencia por ser la libreria de matchers mas usada del ecosistema Swift, mantenida por la org Quick [ref:https://github.com/Quick/Nimble/blob/727f75d91a0f7501d08d938966d17e6728b76a2a/Sources/Nimble/Utils/AsyncAwait.swift#L208-L236@727f75d91a0f]
- Nimble, defaults de sondeo: 1 s de plazo y 10 ms de intervalo [ref:https://github.com/Quick/Nimble/blob/727f75d91a0f7501d08d938966d17e6728b76a2a/Sources/Nimble/Polling.swift#L40-L41@727f75d91a0f]
- Nimble, guia: en maquinas lentas recomienda subir el plazo por defecto [ref:https://github.com/Quick/Nimble/blob/727f75d91a0f7501d08d938966d17e6728b76a2a/Sources/Nimble/Nimble.docc/Guides/PollingExpectations.md#L155-L164@727f75d91a0f]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Dejar el sleep de 1 s | nada que cambiar | apuesta contra el tiempo de GC de JSC, sin cota documentada | nula | no |
| B. Subir el sleep (p. ej. 5 s) | una linea | paga siempre el plazo entero y sigue siendo una apuesta | baja | no |
| C. `pumpUntil("...") { weakView == nil }` con el tope de 30 s | sale en cuanto se cumple; mismo patron que 900+ esperas del repo, Nimble y TestWebKitAPI; registra issue con ubicacion | si el GC tarda mas de 30 s sigue fallando | baja | si |
| D. C mas drenar pool o girar RunLoop.main a mano | cubre un autorelease que nadie drene | `autoreleasepool` es sincrono y no cruza un await; girar el run loop dentro de un job main no drena la cola main (reentrada) | media | no |
| E. Producto: cota propia para soltar la pagina colgada (p. ej. completion propio reanudado en tearDown, o rechazar la promesa al descargar la pagina) | release determinista en la app, no solo en el test | cambio de producto con spec propia; sin verificar | media | decide Karen (D3) |

## 6. Evidencia en contra

- La razon mas fuerte contra C: el release depende de que JSC finalice los handlers de la promesa, y nada documenta un plazo; si en CI con TSan el GC tardara mas de 30 s, C seguiria fallando; se acepta porque 30 s es el tope comun del repo y el supuesto 2 de la seccion 9 mide la distribucion antes de dar el flake por cerrado [doc:https://github.com/WebKit/WebKit/blob/c95c0ba164f97fb789aa5db695cd7bec1791ad79/Source/WebCore/bindings/js/ScriptController.cpp#L884-L893@c95c0ba164f9]
- Un sondeo largo esconde una regresion de latencia (una pagina que tarda 20 s en soltarse pasaria); se acepta porque el contrato del test es "se suelta", no "en cuanto"; la latencia necesitaria su propio criterio [repo:Tests/CompanionTestKit/TestKit.swift:104]
- Nimble usa 1 s por defecto, la misma cifra que el test; no la respalda como plazo seguro, porque su propia guia manda subirlo en maquinas lentas [ref:https://github.com/Quick/Nimble/blob/727f75d91a0f7501d08d938966d17e6728b76a2a/Sources/Nimble/Nimble.docc/Guides/PollingExpectations.md#L155-L164@727f75d91a0f]
- WebKit, en sus tests de fugas, si envuelve en `@autoreleasepool` antes de mirar el contador, lo que sugiere que un pool sin drenar puede retener vistas; aqui no aplica igual porque el codigo propio no autoreleasea la vista y cada vuelta de `pumpUntil` termina el job main [ref:https://github.com/WebKit/WebKit/blob/334dd2883a2c25b8ba9839a86db632738101155f/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/WKURLSchemeHandler-leaks.mm#L86-L106@334dd2883a2c]
- El tope de `watchedWeb` cubre 400 ms, el render siguiente, hasta 30 s de sondeo y el bloque de cancelacion; si el render siguiente tambien se alarga bajo carga, la suma se acerca al tope y el fallo saldria como "no termino" en vez de con el label del sondeo [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:177]

## 7. Ejemplares y anti-ejemplos

- Bien: esperar una condicion observable con plazo, saliendo en cuanto se cumple, como hace `pumpUntil` [repo:Tests/CompanionTestKit/TestKit.swift:108]
- Bien: el sondeo del test de terminacion de proceso, que reemplazo una espera fija [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:491]
- Bien: TestWebKitAPI gira el run loop hasta que el contador de instancias baja [ref:https://github.com/WebKit/WebKit/blob/334dd2883a2c25b8ba9839a86db632738101155f/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/WKURLSchemeHandler-leaks.mm#L68-L76@334dd2883a2c]
- Anti-ejemplo: dormir un tiempo fijo y afirmar despues [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:461]

## 8. Trampas

- Girar `RunLoop.main.run(until:)` desde un test @MainActor (estilo sincrono de Nimble) no corre jobs del main actor: la cola main ya esta drenando y libdispatch no reentra [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/queue.c#L8325-L8336@2361ffb78a76]
- `tearDown` en el `onCancel` corre en un turno posterior, no en el de la cancelacion; afirmar el release en el mismo turno del `.timeout` siempre fallaria [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:101]
- Navegar a vacio no completa el `callAsyncJavaScript` pendiente por si solo segun el codigo de WebCore leido; el comentario del producto que dice lo contrario es, a lo sumo, cierto solo de forma indirecta (via GC) [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:145]
- El WebKit leido es la rama main fijada a un commit, no el WebKit de macOS 26.5; el camino puede diferir (supuesto 4 de la seccion 9) [doc:https://github.com/WebKit/WebKit/blob/c95c0ba164f97fb789aa5db695cd7bec1791ad79/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm#L1561-L1577@c95c0ba164f9]
- swift test no tiene event loop de AppKit; los pools por iteracion que documenta Apple para AppKit no aplican a este proceso [doc:https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html@archive-2016]
- Contexto swift test local (paralelo): C sale en cuanto el GC finaliza; el paralelismo solo alarga la espera, no cambia el resultado [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:162]
- Contexto CI macos-26 con --no-parallel: menos nucleos, misma logica; el tope de 30 s es el que el repo ya calibro para ese runner [repo:Tests/CompanionTestKit/TestKit.swift:97]
- Contexto job tsan: la instrumentacion alarga todo; es el contexto donde mas pesa el supuesto 2 de la seccion 9 [repo:scripts/tsan.sh:18]
- Contexto app instalada: el cambio es solo del test; en la app la pagina colgada sigue viva (con su proceso de contenido) hasta el GC, que es la decision D3 [repo:Sources/CompanionServices/Deliverables/WebKitDiagramRenderer.swift:164]

## 9. Incertidumbre

- ASSUMPTION 1: el marco suspendido de draw retiene el WKWebView durante el await de `callAsyncJavaScript` (la temporal de `webView?` vive hasta que el await retoma), y esa es la ultima referencia fuerte. prueba: en un probe, tras el `.timeout` y un `pumpUntil` sobre `page.webView == nil`, comprobar que `weakView != nil` hasta que se loguea "the page did not draw", y que pasa a nil en ese mismo turno.
- ASSUMPTION 2: el tiempo hasta el release lo fija el GC de JSC que finaliza los handlers de la promesa colgada, y en CI (incluido tsan) queda por debajo de 30 s. prueba: loguear el intervalo entre el `.timeout` y el release en 50 corridas locales con carga y en CI; RED por stall: en un probe, retener la vista con una Task que la suelta a los 1.5 s; el sleep de 1 s falla y `pumpUntil` pasa.
- ASSUMPTION 3: el CF de Darwin abre un autorelease pool al servicio de la cola main (corelibs solo lo sugiere), de modo que cualquier autorelease se drena entre vueltas de `pumpUntil`. prueba: en un test @MainActor, autoreleasear un NSObject via un metodo ObjC que devuelve +0, guardar un weak, y ver con `pumpUntil` que llega a nil.
- ASSUMPTION 4: el WebKit de macOS 26.5 sigue el mismo camino que el commit leido (completion solo por resolucion o finalizador, sin capturar la vista). prueba: la del supuesto 1 corrida en esta Mac y en CI.
- [NEEDS CLARIFICATION: D3, si la app debe soltar una pagina colgada en un plazo propio (opcion E) en vez de esperar al GC de JavaScript; es una spec de producto aparte, no parte de arreglar el flake.]

## 10. Checklist de estandar

- [ ] El test no contiene ningun sleep fijo entre el render siguiente y la afirmacion del release.
- [ ] La afirmacion es `pumpUntil` con label propio sobre `weakView == nil`, con el tope por defecto de 30 s o uno explicito no menor.
- [ ] No hay `RunLoop.main.run` ni `autoreleasepool` alrededor de la espera.
- [ ] Un probe de stall (release retrasado 1.5 s) deja el test viejo en rojo y el nuevo en verde, y se describe en el PR.
- [ ] La suma de plazos del test sigue por debajo del tope de `watchedWeb`.
- [ ] Ningun cambio de producto en este PR; la opcion E solo con spec aprobada por Karen.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | WKWebView callAsyncJavaScript | Apple | macOS SDK 26.5 | 2026-10-01 | high |
| 2 | WKWebView navigationDelegate | Apple | macOS SDK 26.5 | 2026-10-01 | high |
| 3 | ScriptController.cpp (executeAsynchronousUserAgentScriptInWorld) | WebKit | main c95c0ba164f9 | 2026-10-01 | medium (no es el WebKit del sistema) |
| 4 | WKWebView.mm (_evaluateJavaScript) | WebKit | main c95c0ba164f9 | 2026-10-01 | medium |
| 5 | DispatchGlobalExecutor.cpp, PlatformExecutorDarwin.swift, CFExecutor.swift | Swift project | swift-6.3.3-RELEASE | 2026-10-01 | high |
| 6 | libdispatch init.c, queue.c | Apple OSS | 2361ffb78a76 | 2026-10-01 | high |
| 7 | CFRunLoop.c | swift-corelibs-foundation | 6f21ccf1461d | 2026-10-01 | low (corelibs, no Darwin) |
| 8 | Using Autorelease Pool Blocks | Apple | archivo 2016 | 2026-10-01 | high |
| 9 | Concurrency Programming Guide, Operation Queues | Apple | archivo 2012 | 2026-10-01 | medium |
| 10 | WKURLSchemeHandler-leaks.mm, UtilitiesCocoa.mm | WebKit | 334dd2883a2c | 2026-10-01 | high |
| 11 | Nimble AsyncAwait.swift, Polling.swift, PollingExpectations.md | Quick | 727f75d91a0f | 2026-10-01 | high |

[KAREN:chat 2026-10-01] Aprobada la recomendacion: pumpUntil { weakView == nil } con tope de 30 s, solo en el test. D3: no ahora; la cota propia del producto (opcion E) queda como pendiente con su spec aparte.
