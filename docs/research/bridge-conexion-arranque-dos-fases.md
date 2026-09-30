# Reference Brief: arrancar el hilo lector de BridgeConnection solo despues de cablear sus callbacks

Slug: bridge-conexion-arranque-dos-fases | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

## 1. Pregunta y decisiones abiertas

Cambio: spec aprobada `races-produccion.md`, hallazgo 1 y "Cambio 1" (Bridge). Un cliente que ya cerro hace que el hilo lector de `BridgeConnection` consuma la liberacion one-shot del slot mientras `onClosed` todavia es nil; el listener se queda con una conexion muerta como activa y responde `busy` a todos hasta reiniciar la app.

Decisiones a tomar:

1. Donde arranca el hilo lector: dentro de `init(fd:)` (hoy) o en un `start()` separado que el listener llama al final (spec).
2. Que orden exacto sigue el accept loop: crear, cablear `onClosed`, marcar activa, `start()`, `onConnection` (spec) u otro.
3. Como se publica `onClosed`: `var` mutable asignada despues de `init` (hoy), `let` inyectada en el inicializador, `var` leida y escrita bajo el lock, o `var` con "replay" al asignarla.
4. Que garantia de visibilidad de memoria sostiene el arreglo (`Thread.start`) y si esta documentada.
5. Como interactua con la retencion del slot de la ola 20c D5 (`holdSlotUntilServed` / `releaseSlot`).
6. Como se verifica (TSan, test determinista de 500 iteraciones, test a nivel listener).

## 2. Estado actual

- El accept loop construye la conexion y solo despues le asigna `onClosed` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:145]
- La asignacion de `onClosed` es una escritura sobre una `var` sin lock, en el hilo "bridge-accept" [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:146]
- La conexion se marca activa despues de asignar `onClosed` y antes de entregarla a `onConnection` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:149]
- `onConnection` se llama al final del cuerpo del accept loop [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:150]
- El hilo de accept ya sigue el patron de dos fases: el listener fija todo su estado bajo lock y despues crea y arranca el `Thread` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:86]
- Mientras exista una conexion activa, todo cliente nuevo recibe `busy` y se cierra [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:140]
- `clearActiveConnection` solo libera el slot si la conexion que avisa es identica (`===`) a la activa [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:178]
- `onClosed` se declara como `var` opcional en una clase `@unchecked Sendable` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:240]
- `BridgeConnection` se declara `@unchecked Sendable` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:225]
- `init(fd:)` crea y arranca el hilo "bridge-connection" dentro del propio inicializador, capturando `self` debil [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:253]
- El `thread.start()` dentro de `init` es la linea que abre la ventana de la carrera [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:255]
- `close()` consume la liberacion del slot bajo el lock de la conexion [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:270]
- `close()` lee `onClosed` fuera del lock, despues de `unlock` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:276]
- `holdSlotUntilServed` solo retiene el slot si todavia no se libero (`!slotFreed`) [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:285]
- `releaseSlot` tambien lee `onClosed` fuera del lock [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:294]
- `takeSlotRelease` devuelve true exactamente una vez: si ese true llega con `onClosed == nil`, el aviso se pierde para siempre [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:301]
- El lector llama `close()` en cuanto `read` devuelve 0 o error, que es lo inmediato con un peer que ya cerro [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:328]
- `BridgeSession.serve` retiene el slot al empezar y lo libera en `defer` (ola 20c D5) [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:92]
- La liberacion diferida de D5 es `defer { connection.releaseSlot() }` [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:93]
- En la app, el bridge de Claude Code entrega la conexion a `serve` dentro de un `Task.detached`, asi que `holdSlotUntilServed` corre despues de que el lector ya pudo cerrar [repo:Sources/CompanionApp/BridgeHost.swift:51]
- El relay del navegador usa el mismo `BridgeListener` y entrega a `attach` dentro de un `Task.detached` [repo:Sources/CompanionServices/Browser/BrowserHost.swift:43]
- `BrowserChannel.attach` no llama `holdSlotUntilServed`: en el relay el slot se libera directo al cerrar [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:64]
- Los tests construyen `BridgeConnection(fd:)` directo y asignan `onClosed` despues, con el hilo ya corriendo [repo:Tests/CompanionTests/BridgeAbandonTests.swift:59]
- El helper `BridgePair` de los tests construye la conexion en su `init` [repo:Tests/CompanionTests/BridgeConnectionScopeTests.swift:24]
- Otro test construye dos conexiones directas sin cablear `onClosed` [repo:Tests/CompanionTests/BrowserChannelHardeningTests.swift:70]
- El worktree ya trae, sin commitear, el test rojo del spec: socketpair con el cliente cerrado, 500 iteraciones, `onClosed` asignado tras construir [repo:Tests/CompanionTests/BridgeConnectionScopeTests.swift:99]
- El worktree tambien trae, sin commitear, un test a nivel listener para un cliente que cierra antes de que se cablee `onClosed` [repo:Tests/CompanionTests/BridgeListenerTests.swift:283]
- `scripts/gates.sh` corre `swift test` sin `--sanitize=thread`, asi que TSan no es parte del gate hoy [repo:scripts/gates.sh:246]
- En CI el gate agrega `--no-parallel`, lo que cambia el intercalado de hilos respecto de local [repo:scripts/gates.sh:245]
- La plataforma minima es macOS 26 [repo:Package.swift:9]
Contextos: app firmada (dos listeners: bridge de Claude Code en BridgeHost y relay del navegador en BrowserHost), `swift test` local en paralelo, `swift test --no-parallel` en CI via gates.sh, `swift test --sanitize=thread` a mano (criterio de aceptacion del spec, no en gates), tests que construyen BridgeConnection directo sin listener.

## 3. Fuentes primarias

- La documentacion de Apple de `Thread.start()` dice que "asynchronously spawns the new thread and invokes the receiver's main() method"; no menciona visibilidad de memoria, sincronizacion ni happens-before [doc:https://developer.apple.com/tutorials/data/documentation/foundation/thread/start().json@macOS26-sdk-docs]
- POSIX.1-2024, seccion 4.15.2 "Memory Synchronization": `pthread_create()` esta en la lista de funciones que "shall synchronize memory with respect to other threads on all successful calls" [doc:https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html@POSIX.1-2024]
- La misma lista de POSIX 4.15.2 incluye `pthread_mutex_lock()` y `pthread_mutex_unlock()`, que es lo que sostiene la opcion de leer `onClosed` bajo lock [doc:https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html@POSIX.1-2024]
- SE-0282 (implementada en Swift 5.3) adopta un modelo de memoria estilo C/C++ y declara la intencion de ser "fully interoperable with its C/C++ counterparts" [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0282-atomics.md@Swift5.3]
- SE-0282 enmienda la ley de exclusividad: dos accesos a la misma variable no pueden solaparse salvo que ambos sean lecturas o ambos atomicos; la escritura de `onClosed` en "bridge-accept" contra la lectura en "bridge-connection" es exactamente ese solapamiento prohibido [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0282-atomics.md@Swift5.3]
- El libro de Swift, "Two-Phase Initialization": en la fase 2 "Initializers are now able to access `self`", asi que el compilador permite que `self` escape a otro hilo desde `init` una vez inicializadas las propiedades almacenadas [doc:https://github.com/swiftlang/swift-book/blob/1c0598430507e6c2b9a0f068b6dd7c618392fea6/TSPL.docc/LanguageGuide/Initialization.md@1c05984]
- Apple, `Sendable`: una clase es Sendable si es `final` y solo tiene propiedades almacenadas inmutables y Sendable [doc:https://developer.apple.com/tutorials/data/documentation/swift/sendable.json@macOS26-sdk-docs]
- Apple, `Sendable`: con `@unchecked Sendable` "You are responsible for the correctness of unchecked sendable types, for example, by protecting all access to its state with a lock or a queue" [doc:https://developer.apple.com/tutorials/data/documentation/swift/sendable.json@macOS26-sdk-docs]
- JLS 17.4.5 (Java, como contraste): "A call to start() on a thread happens-before any actions in the started thread"; Java lo documenta explicitamente, Foundation no [doc:https://docs.oracle.com/javase/specs/jls/se21/html/jls-17.html@SE21]
- JLS 17.5: "do not write a reference to the object being constructed in a place where another thread can see it before the object's constructor is finished" es la regla de no dejar escapar `this` del constructor [doc:https://docs.oracle.com/javase/specs/jls/se21/html/jls-17.html@SE21]
- Apple, Thread Sanitizer: detecta "Swift access races" y "Data races" y registra cada lectura y escritura para reportar accesos a la misma direccion sin sincronizacion [doc:https://developer.apple.com/tutorials/data/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early.json@macOS26-sdk-docs]
- Apple, Thread Sanitizer: se activa con `-sanitize=thread` en swiftc y solo sirve para apps macOS de 64 bits o en Simulator [doc:https://developer.apple.com/tutorials/data/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early.json@macOS26-sdk-docs]
- Clang, ThreadSanitizer: es una herramienta dinamica que exige todo el codigo instrumentado; el codigo no instrumentado puede dar falsos positivos o carreras no vistas [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- swift.org: "your tests need to actually exercise multithreaded code, otherwise Thread Sanitizer will not find data races", y se usa con SwiftPM via el target `test` [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]
- swift.org: TSan exige build en Debug porque "relies on debug information to describe the problems it finds" [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]
- La guia de servidores de swift.org lista `swift test --sanitize=thread` como la forma de correr la suite con TSan [doc:https://www.swift.org/documentation/server/guides/llvm-sanitizers.html@swift.org-guides]

## 4. Implementaciones de referencia

- SwiftNIO (Apple, base de red del ecosistema Swift server; commit del 2026-09-30): `AcceptHandler.channelRead` corre primero el `childChannelInitializer` del canal aceptado y solo al completarse lo pasa por el pipeline [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/Bootstrap.swift#L465-L507@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- SwiftNIO: `ServerSocketChannel.channelRead0` registra el hijo en su event loop y, si el hijo ya esta cerrado, falla con `_ioOnClosedChannel` en lugar de activarlo [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/SocketChannel.swift#L430-L443@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- SwiftNIO: `becomeActive0` dispara `channelActive` y solo despues llama `registerForReadEOF()` y `readIfNeeded0()`; la lectura y el EOF nunca llegan antes de que los handlers esten puestos [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/BaseSocketChannel.swift#L1402-L1441@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- Netty (framework de red JVM, mantenido activamente; commit del 2026-09-30 en la rama 4.2), implementacion independiente: `ServerBootstrapAcceptor.channelRead` agrega el handler, fija opciones y atributos del hijo, y recien entonces lo registra en su event loop [ref:https://github.com/netty/netty/blob/e66ce34777f9c4a0c57ac74bb97396ca2f54b43c/transport/src/main/java/io/netty/bootstrap/ServerBootstrap.java#L223-L247@e66ce34777f9c4a0c57ac74bb97396ca2f54b43c]
- swift-corelibs-foundation (implementacion open source de Foundation para Linux, no la de Darwin): `Thread.start()` termina en `_CFThreadCreate` [ref:https://github.com/swiftlang/swift-corelibs-foundation/blob/6f21ccf1461d160ffb27eb946e515d71269d8c1e/Sources/Foundation/Thread.swift#L274-L294@6f21ccf1461d160ffb27eb946e515d71269d8c1e]
- swift-corelibs-foundation: `_CFThreadCreate` llama `pthread_create`, que es la operacion a la que POSIX 4.15.2 le da la sincronizacion de memoria [ref:https://github.com/swiftlang/swift-corelibs-foundation/blob/6f21ccf1461d160ffb27eb946e515d71269d8c1e/Sources/CoreFoundation/CFPlatform.c#L1766-L1784@6f21ccf1461d160ffb27eb946e515d71269d8c1e]
- swift-corelibs-foundation: `Thread.start()` tiene `precondition(_status == .initialized, ...)`, asi que arrancar dos veces el mismo `Thread` es un crash, no un no-op [ref:https://github.com/swiftlang/swift-corelibs-foundation/blob/6f21ccf1461d160ffb27eb946e515d71269d8c1e/Sources/Foundation/Thread.swift#L274-L276@6f21ccf1461d160ffb27eb946e515d71269d8c1e]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `start()` separado del `init`; orden: crear, `onClosed`, marcar activa, `start()`, `onConnection` (spec) | Cierra la carrera de raiz: nada del hilo lector corre antes de que el estado este listo; mismo patron que NIO y Netty; diff chico | `onClosed` sigue siendo `var`: un llamador que asigne despues de `start()` reintroduce la carrera (los tests lo hacen hoy); API de dos pasos, olvidar `start()` deja una conexion que nunca lee | baja | Si, minimo obligatorio |
| B. `onClosed` como `let` inyectado en el `init` (recibe la conexion como argumento), combinado con A | Hace imposible la asignacion tardia: el compilador lo impide; cumple el contrato de `Sendable` (propiedad inmutable); quita la lectura sin lock de una `var` | Sin A no alcanza: si el hilo arranca en `init`, el aviso puede llegar antes de `setActiveConnection`, la comparacion `===` lo ignora y queda la conexion muerta como activa; cambia la firma que usan ~5 sitios de test | baja-media | Si, como endurecimiento junto con A |
| C. `onClosed` leido y escrito bajo el lock de la conexion, hilo sigue en `init` | Elimina el data race que ve TSan | No arregla el bug: si `close()` corre antes de la asignacion, `takeSlotRelease` ya consumio el true one-shot y el aviso se pierde igual | baja | No sola |
| D. Replay al asignar: el setter, bajo lock, invoca el callback si el slot ya se libero | Arregla la perdida sin tocar el orden de arranque | Mas estado (entregado/pendiente), callback invocado desde el hilo que asigna; si el replay corre antes de `setActiveConnection`, la comparacion `===` lo ignora y el bug vuelve; parche de sintoma | media | No |

## 6. Evidencia en contra

- Contra A: Foundation no documenta que `Thread.start` establezca happens-before con el hilo nuevo; el arreglo se apoya en algo no escrito en la doc de Apple [doc:https://developer.apple.com/tutorials/data/documentation/foundation/thread/start().json@macOS26-sdk-docs]
- Resolucion parcial: POSIX si garantiza la sincronizacion de `pthread_create`, y en la Foundation open source `Thread.start` es `pthread_create`; en Darwin (NSThread cerrado) queda sin verificar y figura en la seccion 9 [doc:https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap04.html@POSIX.1-2024]
- Resolucion de fondo: el codigo actual ya depende de esa misma garantia para `fd` y las continuaciones que el hilo lector lee, asi que A no agrega una dependencia nueva, solo pone `onClosed` del lado correcto de ella [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:245]
- Resolucion verificable: TSan intercepta la creacion de hilos y hoy reporta esta carrera; si tras el cambio la suite con `--sanitize=thread` queda limpia en esta ruta, la arista happens-before existe en la practica [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- Contra A sola: deja `onClosed` como `var`, y los tests ya asignan `onClosed` despues de construir; si `BridgePair` llama `start()` en su `init`, esos tests conservan la carrera y TSan puede marcarlos [repo:Tests/CompanionTests/BridgeAbandonTests.swift:59]
- Se acepta o se resuelve con B; si se queda en A, el `start()` de los tests tiene que ir despues de asignar `onClosed` [repo:Tests/CompanionTests/BridgeConnectionScopeTests.swift:24]
- Contra B: el cierre del listener hoy captura `[weak connection]`, que no existe mientras se ejecuta su propio `init`; B obliga a que el callback reciba la conexion como argumento [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:146]
- Contra el orden del spec respecto de D5: con A, un cliente que cierra antes de que `serve` corra libera el slot antes de `holdSlotUntilServed`, que entonces es no-op; se acepta porque esa conexion nunca paso `hello`, no tiene autorizacion que proteger [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:285]
- Mover `holdSlotUntilServed` al listener antes de `start()` no es alternativa: el mismo listener sirve al relay, que nunca llama `releaseSlot`, y el slot quedaria tomado para siempre [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:64]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, SwiftNIO: la lectura y el EOF se habilitan al final de la activacion, despues de los handlers de usuario [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/BaseSocketChannel.swift#L1402-L1441@d09ffc8ad6437bc278897279e33150d8e39ee3d5]

```swift
self.lifecycleManager.finishActivation()(nil, self.pipeline)
guard self.lifecycleManager.isOpen else { return }
self.registerForReadEOF()
// ...
self.readIfNeeded0()
```

- Bien hecho, Netty: primero handler, opciones y atributos del hijo; el registro (que habilita I/O) va al final [ref:https://github.com/netty/netty/blob/e66ce34777f9c4a0c57ac74bb97396ca2f54b43c/transport/src/main/java/io/netty/bootstrap/ServerBootstrap.java#L223-L247@e66ce34777f9c4a0c57ac74bb97396ca2f54b43c]

```java
child.pipeline().addLast(childHandler);
setChannelOptions(child, childOptions, logger);
setAttributes(child, childAttrs);
childGroup.register(child)
```

- Bien hecho, en el propio repo: el listener fija `listenFD`, `_token` y `running` bajo lock y arranca el hilo de accept despues [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:88]
- Anti-ejemplo, el codigo actual: el hilo arranca dentro de `init` y el callback se cablea despues, desde otro hilo [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:253]

```swift
let thread = Thread { [weak self] in self?.readLoop() }
thread.name = "bridge-connection"
thread.start()          // dentro de init(fd:)
// ... y en acceptLoop, ya con el hilo corriendo:
connection.onClosed = { ... }
```

- Anti-ejemplo de la opcion D: cualquier aviso que llegue antes de `setActiveConnection` es ignorado por la comparacion de identidad y deja la conexion muerta como activa [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:178]

## 8. Trampas

- Marcar activa despues de `start()` rompe el arreglo aunque `onClosed` ya este puesto: `clearActiveConnection` corre primero, no encuentra la conexion, y el `setActiveConnection` posterior guarda una muerta [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:178]
- `start()` llamado dos veces crearia un segundo hilo lector sobre el mismo fd; necesita un flag bajo lock que lo haga idempotente o un precondition [ref:https://github.com/swiftlang/swift-corelibs-foundation/blob/6f21ccf1461d160ffb27eb946e515d71269d8c1e/Sources/Foundation/Thread.swift#L274-L276@6f21ccf1461d160ffb27eb946e515d71269d8c1e]
- `close()` antes de `start()` (por ejemplo `stop()` del listener entre marcar activa y arrancar) debe seguir funcionando: el lector sale en su primer `isClosed()` y el aviso lo da `close()` desde el hilo de `stop` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:323]
- Contexto app, bridge de Claude Code: `serve` corre en un `Task.detached` posterior, asi que el lector puede cerrar y liberar el slot antes de `holdSlotUntilServed`; el comportamiento correcto es liberar, no perder el aviso [repo:Sources/CompanionApp/BridgeHost.swift:51]
- Contexto app, relay del navegador: comparte `BridgeListener` y sufre el mismo bug hoy; el arreglo lo cubre sin cambios en `BrowserChannel` porque el relay no retiene el slot [repo:Sources/CompanionServices/Browser/BrowserHost.swift:43]
- Contexto tests directos: todo test que construye `BridgeConnection(fd:)` sin listener debe llamar `start()` o no leera nunca y quedara colgado hasta el timeout [repo:Tests/CompanionTests/BrowserChannelHardeningTests.swift:70]
- Contexto `swift test` sin sanitizer (gates.sh): el test de 500 iteraciones es probabilistico; en verde no prueba ausencia de carrera, solo que no se perdio el aviso en esas corridas [repo:scripts/gates.sh:246]
- Contexto `swift test --sanitize=thread`: TSan solo ve carreras que ocurren en esa ejecucion y exige build Debug; hay que correrlo sobre los tests nuevos, que si ejercitan los dos hilos [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]
- Contexto CI con `--no-parallel`: el intercalado cambia respecto de local; la reproduccion del rojo puede ser menos frecuente ahi, por eso el test itera [repo:scripts/gates.sh:245]
- Frontera de confianza: cualquier proceso del mismo uid puede conectar y cerrar al instante; hoy eso es una primitiva de denegacion de servicio del bridge y del relay hasta reiniciar la app [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:135]
- El arreglo no debe mover el chequeo de uid del peer ni el `sendBusy` antes de crear la conexion; el orden de rechazo previo a construir `BridgeConnection` se conserva [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:140]
- Con `var onClosed`, la lectura en `releaseSlot` ocurre en el hilo del `Task` de `serve`; queda publicada solo si la escritura del accept loop es anterior a `onConnection` y la creacion del task la publica [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:294]

## 9. Incertidumbre

- ASSUMPTION: en Darwin, `Thread.start` (NSThread, codigo cerrado) crea el hilo con `pthread_create` y hereda su sincronizacion POSIX, igual que la Foundation open source. prueba: tras el cambio, correr el test de 500 iteraciones y el test de listener con `swift test --sanitize=thread --filter Bridge` y confirmar cero avisos en `BridgeListener.swift`; si TSan no reconociera la arista, marcaria `onClosed` como carrera
- ASSUMPTION: la creacion de un `Task.detached` publica al task lo escrito antes por el hilo que lo crea, de modo que `releaseSlot` ve el `onClosed` asignado en el accept loop. prueba: con la opcion A sola (`var`), el test de listener bajo TSan no reporta carrera entre "bridge-accept" y el hilo del task de `serve`; con la opcion B la duda desaparece porque `onClosed` es `let`
- ASSUMPTION: que `serve(A)` corra tarde, despues de aceptar una conexion B, no pisa el estado de B (A esta cerrada, `serve` ve `current` abierta y responde busy, o el epoch nuevo corta el bucle de A). prueba: test a nivel listener con A que cierra al instante y B que manda `hello` y una llamada; afirmar que B recibe su respuesta y que la sesion queda abierta para B
- [NEEDS CLARIFICATION: el spec aprobado describe solo la opcion A. Adoptar ademas la B (`onClosed` como `let` en el `init`) cambia la firma que usan unos cinco sitios de test y el helper `BridgePair`. Queda dentro del Cambio 1 o se deja para despues?]
- [NEEDS CLARIFICATION: agregar `swift test --sanitize=thread` a `scripts/gates.sh` o dejarlo como verificacion manual del criterio de aceptacion; el spec lo pide en la aceptacion pero no en el gate]

## 10. Checklist de estandar

- [ ] `BridgeConnection.init(fd:)` no crea ni arranca ningun `Thread`; el hilo lector se arranca solo desde un metodo `start()` explicito.
- [ ] En `BridgeListener.acceptLoop` el orden es: construir la conexion, cablear `onClosed`, `setActiveConnection`, `start()`, `onConnection`. Un reviewer lo verifica leyendo el bloque.
- [ ] `start()` es idempotente o falla ruidosamente si se llama dos veces; nunca crea dos hilos lectores sobre el mismo fd.
- [ ] Si se adopta la opcion B: `onClosed` es `let` y se recibe en el inicializador; no queda ninguna asignacion a `onClosed` fuera del `init`.
- [ ] Si se queda en A: todo `start()` en tests va despues de asignar `onClosed`.
- [ ] Test rojo antes y verde despues: socketpair con el cliente ya cerrado, `onClosed` avisa exactamente una vez, 500 iteraciones.
- [ ] Test a nivel listener: N clientes que cierran al instante y un cliente nuevo recibe `hello`, no `busy`.
- [ ] `swift test --sanitize=thread` sin avisos en `BridgeListener.swift`, ni en "bridge-connection" contra "bridge-accept".
- [ ] `testTheSlotIsHeldUntilTheSessionReleasesIt` y `testServingReleasesTheSlotOnlyAfterTheStateIsReset` (D5) siguen verdes.
- [ ] El chequeo de uid del peer y la respuesta `busy` siguen ocurriendo antes de construir la conexion.
- [ ] security-reviewer revisa el cambio como frontera de confianza (peers del mismo uid, token).

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Thread.start() | Apple Developer Documentation | SDK actual | 2026-09-30 | high |
| 2 | Base Definitions, 4.15.2 Memory Synchronization | The Open Group, POSIX.1-2024 | 2024 | 2026-09-30 | high |
| 3 | SE-0282 Clarify the Swift memory consistency model | Swift Evolution | Swift 5.3 | 2026-09-30 | high |
| 4 | The Swift Programming Language, Initialization | swiftlang/swift-book | 1c05984 | 2026-09-30 | high |
| 5 | Sendable | Apple Developer Documentation | SDK actual | 2026-09-30 | high |
| 6 | Java Language Specification, cap. 17 | Oracle | SE 21 | 2026-09-30 | high (contraste, no Swift) |
| 7 | Diagnosing memory, thread, and crash issues early | Apple Developer Documentation | SDK actual | 2026-09-30 | high |
| 8 | ThreadSanitizer | LLVM/Clang | actual | 2026-09-30 | high |
| 9 | Thread Sanitizer for Swift on Linux | swift.org blog | sin fecha visible | 2026-09-30 | medium |
| 10 | LLVM TSAN / ASAN | swift.org server guides | actual | 2026-09-30 | medium |
| 11 | swift-nio NIOPosix Bootstrap, SocketChannel, BaseSocketChannel | Apple | d09ffc8 | 2026-09-30 | high |
| 12 | netty ServerBootstrap | Netty project | e66ce34 | 2026-09-30 | high |
| 13 | swift-corelibs-foundation Thread.swift, CFPlatform.c | swiftlang | 6f21ccf | 2026-09-30 | high (Linux, no Darwin) |
