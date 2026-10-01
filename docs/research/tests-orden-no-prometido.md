# Reference Brief: tests que dependen de un orden que Swift no promete (TaskGroup, Task y MainActor)

Slug: tests-orden-no-prometido | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Cambio: arreglar desde el lado del test el flake de `mentionSelectorTabDuringDialogTests`, que falla bajo carga con "16m-7 review: el diálogo sigue abierto". Segun la peticion de la sesion orquestadora, el fallo aparece en corridas de gates y de TSan. Ningun log del repo registra esa falla; el unico rastro es que TSan no dio avisos en ese test.

Preguntas que este brief responde con fuentes:

1. Que garantizan Swift 6 y su runtime sobre los hijos de un `withTaskGroup`: el orden de arranque, el orden de terminacion, y cuando corre el cuerpo del `for await` frente a un hijo que tiene que saltar al MainActor.
2. Que garantiza un `Task {}` creado desde codigo `@MainActor` frente a otro trabajo del MainActor.
3. Que patrones documentados existen para que un test espere una precondicion: esperar el estado exacto que la asercion necesita (o un fake que avise que de verdad se alcanzo), en vez de un estado proxy que casi siempre llega antes; sondeo con deadline frente a continuaciones y compuertas; y el API `confirmation` de Swift Testing.

Decisiones a tomar:

1. Si la hipotesis se confirma: que `isRequestingAccess` lo pone el hijo `people` del grupo, en un salto al MainActor, y que nada lo ordena antes de que publiquen los hijos de apps y archivos.
2. Si el comportamiento de producto (la bandera se pone un momento despues de que aparecen las filas) es un bug o es aceptable.
3. El arreglo minimo, solo en el test, que siga un patron documentado.
4. Si se puede tener un RED deterministico primero y, si no se puede, que alternativa honesta lo sustituye.
5. Una regla general que otra sesion pueda aplicar a un flake hermano: el auto-deny de aprobaciones frente a un `pumpUntil` de 5 s.

## 2. Estado actual

- `MentionSelectorModel` es `@Observable` y `@MainActor` [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:26]
- `isRequestingAccess` es una propiedad del modelo, privada para escribir, que arranca en false [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:58]
- El comentario de `refresh` fija el diseño: cada fuente publica cuando llega y una fuente lenta no frena a las demas [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:178]
- `refresh` crea un `Task {}` no estructurado desde un metodo del MainActor [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:185]
- Dentro de esa tarea, `refresh` abre un `withTaskGroup` [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:191]
- El primer hijo pide las apps conectadas [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:192]
- El segundo hijo pide los archivos recientes [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:193]
- El tercer hijo, que solo existe si hay proveedor de contactos, llama `self.people(matching:)`, un metodo del MainActor [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:194]
- El `for await` consume los resultados del grupo en el orden en que llegan [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:195]
- Cada resultado que llega publica las filas en el momento, sin esperar a los demas [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:207]
- `people(matching:)` llama `askOnce` antes de buscar [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:215]
- `askOnce` solo consulta `contacts.access()`, que es sincrono, antes de poner la bandera [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:225]
- `askOnce` pone `isRequestingAccess = true` [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:227]
- Justo despues, en el mismo trabajo del MainActor, crea el `Task` que va a llamar `requestAccess` [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:228]
- Ese `Task` llama `contacts.requestAccess()` y al volver baja la bandera [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:229]
- El puerto documenta que `requestAccess` es la unica llamada que puede mostrar el dialogo del sistema [repo:Sources/CompanionCore/Island/MentionPorts.swift:12]
- `IslandView` usa la bandera para que la isla no se pliegue mientras el dialogo tiene el teclado [repo:Sources/CompanionUI/Island/IslandView.swift:213]
- `CompanionUI` compila con aislamiento por defecto `MainActor` [repo:Package.swift:36]
- El target `CompanionUITests` se declara sin `swiftSettings` [repo:Package.swift:94]
- El test con flake es `mentionSelectorTabDuringDialogTests` [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:269]
- El test retiene el dialogo antes de escribir `@` [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:272]
- El test espera a que haya dos filas, apps y archivos [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:277]
- Justo despues exige que la bandera ya este en true; esta es la asercion que falla [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:278]
- El test suelta el dialogo al final [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:284]
- `FakeContacts.requestAccess` guarda la continuacion cuando el dialogo esta retenido; ese es el punto en que el dialogo esta abierto de verdad [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:46]
- `FakeContacts` no expone hoy si hay un dialogo en espera; solo `requests`, que sube al responder [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:42]
- `answerDialog` reanuda la continuacion guardada, si existe, y apaga la retencion [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:33]
- `mentionSelectorCursorFollowsItsRowTests` usa el mismo proxy (dos filas) antes de soltar el dialogo [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:293]
- Alli el proxy no rompe nada: `answerDialog` antes de que exista el dialogo deja la retencion apagada y `requestAccess` vuelve en el acto [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:296]
- `mentionSelectorClosedDialogHoldsTheIslandTests` ya espera la bandera misma con `pumpUntil` [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:138]
- `mentionSelectorPermissionRacesTests` hace lo mismo y explica por que en un comentario [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:350]
- `pumpUntil` es `@MainActor` y fija un deadline de reloj de pared, de 30 s por defecto [repo:Tests/CompanionTestKit/TestKit.swift:103]
- Su bucle cede el MainActor con `Task.yield` y duerme 2 ms entre consultas [repo:Tests/CompanionTestKit/TestKit.swift:108]
- Al vencer registra un issue con la etiqueta; no lanza [repo:Tests/CompanionTestKit/TestKit.swift:112]
- El comentario de `pumpUntilAsync` registra que en CI el MainActor y el pool cooperativo pueden quedar sin atender mas tiempo del que da un deadline corto [repo:Tests/CompanionTestKit/TestKit.swift:124]
- `TestGate` suspende a quien llama `wait()` hasta `open()`, y `entered` le dice al test que el codigo llego a la compuerta [repo:Tests/CompanionTestKit/TestKitFakes.swift:3]
- `ManualSleeper.armed` es el mismo patron aplicado a relojes: esperar a que la espera exista antes de dispararla [repo:Tests/CompanionTestKit/TestKitFakes.swift:50]
- El flake hermano usa un auto-deny real de 0,15 s [repo:Tests/CompanionTests/Approvals16q1ReviewTests.swift:247]
- Y lo espera con un `pumpUntil` de 5 s en vez de los 30 s por defecto [repo:Tests/CompanionTests/Approvals16q1ReviewTests.swift:249]
- En CI, `gates.sh` corre la suite con `--no-parallel` [repo:scripts/gates.sh:266]
- `tsan.sh` corre la suite con `--sanitize=thread --no-parallel` [repo:scripts/tsan.sh:18]
- El toolchain medido, local y en el runner, es Apple Swift 6.3.3 [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:34]
- En la corrida TSan medida, `mentionSelectorTabDuringDialogTests` no produjo ningun aviso: el flake no es una carrera de datos [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:30]
Contextos: (1) `swift test` local en paralelo, el que corre `gates.sh` fuera de CI; (2) job `gates` de CI en macos-26 con `--no-parallel`; (3) job TSan (`scripts/tsan.sh`) con `--sanitize=thread --no-parallel`; (4) la app empaquetada, donde `IslandView` lee la bandera y el dialogo es el real de Contactos.

## 3. Fuentes primarias

- SE-0304: un executor exclusivo no tiene que correr los trabajos en el orden en que se le enviaron, y en general debe respetar la prioridad antes que el orden de envio [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0304-structured-concurrency.md#L180@Swift-5.5]
- SE-0304: los hijos de un grupo corren en concurrencia y pueden avanzar en cualquier orden; solo se garantiza que todos terminaron cuando `withTaskGroup` vuelve [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0304-structured-concurrency.md#L293@Swift-5.5]
- SE-0304: `next()` devuelve los valores en orden de terminacion, no de envio; con dos hijos imprime "1" o "2" [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0304-structured-concurrency.md#L1191@Swift-5.5]
- SE-0304: un `Task {}` hereda el contexto de actor de donde se forma y corre en el executor de ese actor [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0304-structured-concurrency.md#L475@Swift-5.5]
- SE-0306: las tareas que esperan un actor no tienen garantia de correr en el orden en que lo esperaron; el runtime considera la prioridad, a diferencia de una DispatchQueue serial, que es FIFO estricta [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0306-actors.md#L115@Swift-5.5]
- SE-0306: la ejecucion "esperada" sin intercalado puede darse muchas veces, asi que el problema aparece de forma intermitente, como muchas carreras [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0306-actors.md#L359@Swift-5.5]
- SE-0431: antes de `@isolated(any)`, un `Task` aislado a un actor arrancaba en el executor global y saltaba despues, asi que el orden de encolado en el actor no era el de creacion [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0431-isolated-any-functions.md#L156@Swift-6.0]
- SE-0431: `Task.init` y `TaskGroup.addTask` encolan la tarea nueva de forma sincrona en el executor de su aislamiento dinamico [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0431-isolated-any-functions.md#L466@Swift-6.0]
- SE-0431: la garantia de arrancar en orden en el actor solo vale para funciones aisladas de forma explicita; un closure no aislado o un `Task {}` aislado solo de forma implicita quedan fuera [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0431-isolated-any-functions.md#L492@Swift-6.0]
- SE-0466 (Swift 6.2): con aislamiento por defecto `MainActor`, los closures de `Task.init` y los closures no `@Sendable` toman el aislamiento del contexto; la propuesta no cambia las demas reglas de inferencia de closures [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0466-control-default-actor-isolation.md#L130@Swift-6.2]
- stdlib 6.2: `Task.init` declara su operacion con `@_inheritActorContext` [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/Task%2Binit.swift.gyb#L29@release-6.2]
- stdlib 6.2: `addTask` declara su operacion como `sending @escaping @isolated(any)`, sin `@_inheritActorContext` [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/TaskGroup%2BaddTask.swift.gyb#L43@release-6.2]
- Compilador 6.2: un closure pasado a un parametro `sending` es una frontera de inferencia de aislamiento salvo que herede el contexto del actor; por eso los hijos de `addTask` no heredan el MainActor [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/lib/Sema/TypeCheckConcurrency.cpp#L733-L743@release-6.2]
- stdlib 6.2: `withTaskGroup` recibe `isolation: isolated (any Actor)? = #isolation`, asi que su cuerpo, y con el el `for await`, corre en el actor de quien lo llama [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/TaskGroup.swift#L53-L57@release-6.2]
- stdlib 6.2: la documentacion de `next()` repite que los valores salen en el orden en que las tareas terminaron [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/TaskGroup.swift#L380-L390@release-6.2]
- Apple, TaskGroup: las tareas de un grupo corren en concurrencia y pueden programarse en cualquier orden [doc:https://developer.apple.com/tutorials/data/documentation/swift/taskgroup.json@macOS26-sdk-docs]
- Joe Groff (equipo de Swift) en los foros: ante cualquier pregunta de si hay garantia de orden entre tareas, lo mas seguro es suponer que no, y comunicar de forma explicita cuando el orden importa [doc:https://forums.swift.org/t/is-the-order-of-task-execution-in-this-code-deterministic/60342/5@post-5-2022-09-19]
- John McCall (equipo de Swift) en los foros: solo las tareas aisladas de forma explicita al actor se encolan en orden; las que arrancan en el executor global por defecto no tienen garantia de correr en el orden de encolado, porque ese executor es concurrente [doc:https://forums.swift.org/t/task-execution-order-guarantees-when-targeting-mainactor/86306/6@post-6-2026-04-29]
- Swift Testing: por defecto los tests corren en paralelo, dentro del mismo proceso, con grupos de tareas [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/Parallelization.md#L17-L20@release-6.2]
- Swift Testing: `confirmation` sirve para eventos que no se pueden esperar con `await`, como un handler o un callback [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/testing-asynchronous-code.md#L29-L39@release-6.2]
- Swift Testing: al volver el closure, `confirmation` comprueba la cuenta y registra un issue si no se cumplio [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Issues/Confirmation.swift#L95-L96@release-6.2]
- Swift Testing: a diferencia de las expectativas de XCTest, las confirmaciones no bloquean ni suspenden al que llama mientras espera; el evento tiene que ocurrir antes de que `confirmation()` vuelva [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/MigratingFromXCTest.md#L410-L414@release-6.2]
- Swift Testing: la guia de migracion pide preferir concurrencia de Swift, `await` y continuaciones, para validar condiciones asincronas [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/MigratingFromXCTest.md#L395-L400@release-6.2]
- Swift Testing, known issues: ante un fallo no deterministico, el primer paso es encontrar la fuente y, si es una carrera, arreglar la causa [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/known-issues.md#L114-L118@release-6.2]
- Swift Testing, known issues: `withKnownIssue(isIntermittent: true)` es para un problema que falla al azar y no registra issue cuando no hubo fallo [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/known-issues.md#L139-L142@release-6.2]
- Swift Testing: su punto de entrada lee `--repetitions` y `--repeat-until` [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/ABI/EntryPoints/EntryPoint.swift#L454-L458@release-6.2]
- XCTest: `XCTNSPredicateExpectation` es una expectativa que se cumple cuando un predicado se satisface, y con `fulfillment(of:timeout:)` lo evalua en el MainActor; es el sondeo con deadline que documenta Apple [doc:https://developer.apple.com/tutorials/data/documentation/xctest/xctnspredicateexpectation.json@macOS26-sdk-docs]

## 4. Implementaciones de referencia

- swift-async-algorithms (Apple, 3711 estrellas, push 2026-09-30) tiene en sus tests un `Gate` con `open()` y `enter()` sobre una continuacion bajo estado critico: una compuerta, no un temporizador [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/Support/Gate.swift#L14-L57@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- swift-async-algorithms usa dos compuertas como cita: cada consumidor abre la suya cuando ya creo su iterador y espera la del otro, asi el test sabe que ambos llegaron antes de que fluyan valores [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/TestShare.swift#L26-L49@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- swift-async-algorithms tambien construye una secuencia con una compuerta por elemento: el test decide cuando avanza cada valor [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/Support/GatedSequence.swift#L12-L30@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- swift-concurrency-extras (Point-Free, 490 estrellas, push 2026-07-24) ofrece `withMainSerialExecutor` para correr en serie y de forma determinista las tareas de un test, y advierte que solo "intenta" hacerlo porque depende de una variable global mutable del runtime [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/README.md#L119-L131@5fa253428866f2360c3754e88537f700ed2656b5]
- swift-concurrency-extras implementa eso con el hook global `swift_task_enqueueGlobal_hook`, que vale para todo el proceso [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/Sources/ConcurrencyExtras/MainSerialExecutor.swift#L83-L100@5fa253428866f2360c3754e88537f700ed2656b5]
- swift-concurrency-extras describe `Task.megaYield()` como herramienta tosca que solo baja la probabilidad del flake y pide preferir la ejecucion serial [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/README.md#L114-L117@5fa253428866f2360c3754e88537f700ed2656b5]

## 5. Opciones

Respuesta a la hipotesis, armada con las secciones 2 y 3: se confirma por las garantias. Los tres hijos de `addTask` no heredan el MainActor, asi que arrancan en el executor global. El hijo `people` tiene que saltar al MainActor para llegar a la linea 227. El cuerpo del `for await` tambien corre en el MainActor, y cada resultado de apps o de archivos le encola ahi un trabajo. Ningun documento ordena el salto del hijo `people` antes de esos dos trabajos. El executor global no garantiza el orden de arranque, y el MainActor no es FIFO. Con el pool cargado (3 vCPU, TSan, tests en paralelo), el hijo `people` puede no haber arrancado siquiera cuando ya hay dos filas. Falta lo empirico: no se corrio swift en esta sesion (seccion 9).

Producto: es aceptable, no es un bug. El contrato real de la bandera es que este en true antes de que se muestre el dialogo del sistema, para que la isla no se pliegue. Eso si esta garantizado, porque la bandera se escribe en el mismo trabajo del MainActor que crea la tarea que llama `requestAccess` (lineas 227-229), y `requestAccess` es la unica llamada que muestra el dialogo. Que las apps y los archivos se pinten antes es justo lo que pide el comentario de diseño de `refresh`.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Meter la bandera en el predicado: `pumpUntil { rows.count == 2 && isRequestingAccess }` | Una linea; espera el estado exacto; igual que los tests vecinos de las lineas 138 y 350 | La bandera pasa a ser precondicion y deja de ser una asercion aparte; si el producto deja de ponerla, el test falla a los 30 s, con la etiqueta del `pumpUntil` | baja | Alternativa minima valida |
| B. El fake avisa cuando lo alcanzan: `FakeContacts.isAsking` (hay continuacion guardada); `pumpUntil { contacts.isAsking && rows.count == 2 }` y despues `expect(selector.isRequestingAccess)` | Espera el hecho del mundo (dialogo abierto), no un proxy; la asercion sigue siendo una comprobacion real, porque la bandera se escribe antes de llamar `requestAccess`; es el mismo patron que `ManualSleeper.armed` y `TestGate.entered` | Unas 4 lineas en el fake privado del mismo archivo | baja | Si |
| C. `confirmation` de Swift Testing | API oficial | No espera: comprueba al volver el closure, y el dialogo retenido nunca devuelve el control por si solo | media | No, no es la herramienta |
| D. `withMainSerialExecutor` (swift-concurrency-extras) | Hace deterministico el orden de los saltos | Dependencia nueva; hook global al proceso con tests en paralelo; el autor dice que solo lo intenta | media | No |
| E. Producto: poner la bandera en `refresh`, antes del grupo | La bandera llegaria antes que las filas | Cambia producto por un test; adelanta un estado que el contrato no pide; duplica la regla de `askOnce` | media | No |
| F. Mas tiempo, `settle` o `megaYield` antes de la asercion | Trivial | Solo baja la probabilidad; la condicion sigue siendo un proxy | baja | No |
| G. `withKnownIssue(isIntermittent: true)` | Pone el gate en verde | Esconde un test mal escrito; la guia pide arreglar la causa | baja | No |

RED primero. Un RED deterministico del flake original no se puede construir solo desde el test. Antes de la linea 227, el unico punto donde el fake toma el control es `access()`, que es sincrono y corre en el MainActor. Bloquearlo bloquea tambien la publicacion de apps y archivos, porque comparten el MainActor. No hay ningun `await` del fake en ese tramo donde una `TestGate` pueda retener al hijo `people`. Retenerlo exigiria una costura en el producto, y eso ya no es un arreglo del test.

Alternativa honesta, en tres partes:

- RED por mutacion de la asercion nueva: con la linea 227 comentada a mano, B falla siempre, porque el fake esta abierto y la bandera esta en false. Eso prueba que el test sigue vigilando el contrato. La mutacion se revierte y no entra en el PR.
- Conteo de estres antes y despues: N corridas filtradas del test en el job TSan o en serie con carga, contando los fallos. Antes se espera mas de 0; despues, 0 de N.
- Si se quiere ver la ventana sin repetir el proceso: un test desechable, sin commit, que en un bucle de K modelos cuente cuantas veces hay dos filas con la bandera en false. Que salga mas de 0 confirma la hipotesis. Que salga 0 no la refuta, porque sin carga la ventana casi no se abre.

Regla general para el flake hermano: un `pumpUntil` debe esperar el estado exacto que necesita la siguiente asercion, con el deadline generoso por defecto. Si lo que se espera es un temporizador real (auto-deny de 0,15 s esperado con 5 s), hay dos caminos: subir el deadline al valor por defecto, o cambiar el reloj por `ManualSleeper` y esperar `armed` antes de `fire`. El segundo es el patron de "el fake avisa que lo alcanzaron" que ya existe en el repo.

## 6. Evidencia en contra

- Contra B: acopla el test a que la bandera se escribe antes de llamar `requestAccess`; se acepta, porque ese orden es el contrato que protege la isla y es sincrono en un solo trabajo del MainActor [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:227]
- Contra B: si un cambio futuro mueve la bandera despues de que arranca `requestAccess`, la asercion volveria a ser intermitente; se acepta, porque esa intermitencia avisaria de un retroceso real del producto [repo:Sources/CompanionUI/Island/IslandView.swift:213]
- Contra B y A: siguen siendo sondeo con deadline, que gasta ciclos y depende del reloj de pared; se acepta, porque la condicion es exacta y el deadline solo limita cuanto tarda en reportarse un fallo real, igual que `XCTNSPredicateExpectation` [doc:https://developer.apple.com/tutorials/data/documentation/xctest/xctnspredicateexpectation.json@macOS26-sdk-docs]
- A favor de una continuacion en vez de sondeo: Swift Testing pide preferir `await` y continuaciones; no se adopta aqui, porque lo que se espera es la combinacion de dos estados (filas y dialogo) que no tienen un unico punto de aviso [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/MigratingFromXCTest.md#L395-L400@release-6.2]
- Contra declarar aceptable el producto: la isla depende de la bandera; se resuelve porque el dialogo solo puede aparecer despues de que la bandera esta en true [repo:Sources/CompanionCore/Island/MentionPorts.swift:12]
- Contra la hipotesis: TSan no vio nada en ese test; no la contradice, porque la falla es de orden entre trabajos bien sincronizados del MainActor, no una carrera de datos [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:30]

## 7. Ejemplares y anti-ejemplos

- Anti-ejemplo: esperar un proxy y despues afirmar otra cosa que llega por otro camino [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:277]

```swift
await pumpUntil("apps y archivos ya están") { selector.rows.count == 2 }
expect(selector.isRequestingAccess, "el diálogo sigue abierto")   // otro hijo, otro salto
```

- Bien hecho en el mismo archivo: esperar la condicion misma antes de seguir [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:350]
- Bien hecho en el repo: un fake que dice cuantas esperas registro, para no disparar antes de que existan [repo:Tests/CompanionTestKit/TestKitFakes.swift:54]
- Bien hecho fuera: una compuerta como cita, en la que cada lado avisa que llego [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/TestShare.swift#L29-L44@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- Forma de B, como referencia para la spec; el fake ya guarda la continuacion bajo su lock [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:44]

```swift
var isAsking: Bool { lock.withLock { dialog != nil } }   // en FakeContacts

await pumpUntil("16m-7 review: diálogo abierto y apps y archivos ya están") {
    contacts.isAsking && selector.rows.count == 2
}
expect(selector.isRequestingAccess, "16m-7 review: el diálogo sigue abierto")
```

- Anti-ejemplo documentado: ceder mas veces solo mejora las probabilidades [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/README.md#L114-L117@5fa253428866f2360c3754e88537f700ed2656b5]

## 8. Trampas

- Creer que el orden de `addTask` es el orden de arranque o de llegada; no lo es [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0304-structured-concurrency.md#L1191@Swift-5.5]
- Creer que un hijo de `addTask` escrito dentro de un tipo `@MainActor` corre en el MainActor; el closure va a un parametro `sending` y no hereda [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/lib/Sema/TypeCheckConcurrency.cpp#L733-L743@release-6.2]
- Creer que el MainActor atiende en FIFO lo que se le encola desde varios hilos; no hay esa garantia [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0306-actors.md#L115@Swift-5.5]
- Creer que dos `Task {}` implicitos del MainActor arrancan en el orden de creacion; SE-0431 los deja fuera de esa garantia [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0431-isolated-any-functions.md#L492@Swift-6.0]
- Usar `confirmation` como si esperara; registra un issue si el evento no ocurrio antes de volver [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Issues/Confirmation.swift#L95-L96@release-6.2]
- Llamar `answerDialog` antes de que el dialogo exista: no reanuda nada y solo apaga la retencion, asi que el test deja de probar "durante el dialogo" sin fallar [repo:Tests/CompanionUITests/Mention16m7SelectorTests.swift:33]
- Contexto (1), local en paralelo: el resto de la suite compite por el pool; con B el test espera el estado exacto y no depende de esa carga [doc:https://github.com/swiftlang/swift-testing/blob/5ee435b15ad40ec1f644b5eb9d247f263ccd2170/Sources/Testing/Testing.docc/Parallelization.md#L17-L20@release-6.2]
- Contexto (2), CI en serie con 3 vCPU: el MainActor puede quedar sin atender mas que un deadline corto; B usa el deadline de 30 s, que solo limita cuanto tarda en reportarse un fallo real [repo:Tests/CompanionTestKit/TestKit.swift:124]
- Contexto (3), TSan: el slowdown abre la ventana del proxy; con B no hay ventana, porque la condicion esperada implica la que se afirma [repo:scripts/tsan.sh:18]
- Contexto (4), la app: no cambia nada; la bandera sigue escribiendose antes del dialogo real [repo:Sources/CompanionUI/Island/Mention/MentionSelectorModel.swift:227]
- Flake hermano: un deadline de 5 s contra un temporizador real de 0,15 s vuelve a la carga parte del contrato del test [repo:Tests/CompanionTests/Approvals16q1ReviewTests.swift:249]

## 9. Incertidumbre

- ASSUMPTION: la falla observada sale de la ventana descrita (dos filas publicadas antes del salto del hijo `people`), y no de otra causa; en esta sesion no se corrio swift por pedido expreso, porque la maquina es compartida. prueba: el test desechable con un bucle de K modelos que cuente las veces que hay dos filas con la bandera en false, corrido bajo `scripts/tsan.sh` con `--filter`; mas de 0 la confirma.
- ASSUMPTION: con B el test pasa 0 fallos en N corridas bajo carga. prueba: N=200 corridas de `swift test --filter mentionSelectorTabDuringDialogTests` en serie dentro del job TSan o con `--sanitize=thread`, contando los fallos antes y despues del cambio.
- MEDIDO (b6, 2026-10-01, despues de la verificacion), sobre main d563ca3 con `--jobs 6`:
  - Antes del cambio:
    - 300 corridas de `--filter mentionSelector` con 4 burners `yes` en nice 5 dieron 0 fallos.
    - 24 suites completas con la misma carga (load ~15) tampoco fallaron en esta asercion. En 23 de esas 24 corridas fallaron otros tests sensibles a carga.
    - La ventana no se abre en esta Mac, asi que el estres no confirma ni refuta la hipotesis. Los dos primeros supuestos de abajo siguen abiertos: la causa descansa en las garantias citadas, no en una reproduccion.
  - Mutacion: quitar `isRequestingAccess = true` (MentionSelectorModel.swift:227) hace fallar el test con B en la primera corrida, con "el diálogo sigue abierto". Restaurada la linea, los 13 tests del selector pasan.
  - Despues de B: 100 corridas filtradas con la misma carga, 0 fallos. B no agrega espera colgada ni otro fallo.
- Evidencia hermana: d2 reprodujo el flake de aprobaciones con un stall del proceso (SIGSTOP de 6 s) y no con carga de CPU (55 corridas a load ~100 sin fallo): `docs/research/evidence/flake-approvals-autodeny-2026-10-01.txt` en la rama `test/flake-approvals-autodeny` (#74). Apoya la regla de esperar el estado observable con el deadline por defecto.
- ASSUMPTION: `swift test` de SwiftPM 6.3.3 no reenvia `--repetitions` a Swift Testing; en el codigo de `SwiftTestCommand` de esa version no aparece la cadena. prueba: correr `swift test --filter mentionSelectorTabDuringDialogTests --repetitions 50` y ver si el informe muestra 50 iteraciones; si no, se usa un bucle de shell.
- ASSUMPTION: en la app, el dialogo real de Contactos no toma el teclado antes de que SwiftUI aplique `geometry.picking` por el `onChange` de la bandera. prueba: con `tccutil reset AddressBook` para la app, escribir `@` por primera vez y ver que la isla no se pliega mientras el dialogo esta abierto.
- ASSUMPTION: el flake hermano de aprobaciones es un deadline corto contra un MainActor sin atender, y no un proxy; no se leyo el rig `mcp(timeout:)` entero. prueba: leer `mcp(timeout:)` en `Approvals16q1ReviewTests.swift` y ver si acepta un `ManualSleeper`; si lo acepta, esperar `armed` y luego `fire`; si no, quitar `timeout: 5`.
- Decision B [KAREN:chat 2026-10-01 via orquestador].

## 10. Checklist de estandar

- [ ] El `pumpUntil` previo a la asercion de `mentionSelectorTabDuringDialogTests` espera el estado exacto que necesita: el dialogo del fake abierto (o la bandera misma) y las dos filas, no solo las dos filas
- [ ] Ningun test nuevo o tocado afirma un estado que llega por otro hijo de un grupo o por otro salto al MainActor sin esperarlo antes
- [ ] El cambio no toca `Sources/`: el producto queda como esta
- [ ] No se agrega `settle`, `megaYield`, sueño fijo ni `withKnownIssue` para tapar el orden
- [ ] El deadline del `pumpUntil` tocado es el valor por defecto (30 s), no uno mas corto
- [ ] La mutacion manual de la linea 227 (bandera comentada) hace fallar el test de forma deterministica, y se revierte antes del commit
- [ ] El PR registra un conteo de estres antes y despues (N corridas filtradas bajo TSan o en serie con carga), con 0 fallos despues
- [ ] `scripts/gates.sh` y `scripts/tsan.sh` siguen verdes
- [ ] El CHANGELOG `[Unreleased]` registra el arreglo en español, con fecha

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0304 structured concurrency | Swift Evolution | Swift 5.5, 42ee8fb | 2026-10-01 | high |
| 2 | SE-0306 actors | Swift Evolution | Swift 5.5, 42ee8fb | 2026-10-01 | high |
| 3 | SE-0431 isolated(any) | Swift Evolution | Swift 6.0, 42ee8fb | 2026-10-01 | high |
| 4 | SE-0466 default actor isolation | Swift Evolution | Swift 6.2, 42ee8fb | 2026-10-01 | high |
| 5 | Task+init.swift.gyb, TaskGroup+addTask.swift.gyb, TaskGroup.swift | swiftlang/swift | release/6.2, 635acfa | 2026-10-01 | high |
| 6 | TypeCheckConcurrency.cpp | swiftlang/swift | release/6.2, 635acfa | 2026-10-01 | high |
| 7 | TaskGroup | Apple Developer | SDK actual | 2026-10-01 | high |
| 8 | Is the order of Task execution in this code deterministic, post 5 (Joe Groff) | Swift Forums | 2022-09-19 | 2026-10-01 | medium |
| 9 | Task execution order guarantees when targeting MainActor, post 6 (John McCall) | Swift Forums | 2026-04-29 | 2026-10-01 | medium |
| 10 | Testing asynchronous code, Confirmation.swift, MigratingFromXCTest, known-issues, Parallelization, EntryPoint.swift | swiftlang/swift-testing | release/6.2, 5ee435b | 2026-10-01 | high |
| 11 | XCTNSPredicateExpectation | Apple Developer | SDK actual | 2026-10-01 | high |
| 12 | swift-async-algorithms Gate, GatedSequence, TestShare | Apple | 13713a4 | 2026-10-01 | high |
| 13 | swift-concurrency-extras README y MainSerialExecutor | Point-Free | 5fa2534 | 2026-10-01 | medium |

Recomendacion de este brief: B, implementado en el PR; Karen eligio B.

Estado: APROBADO
