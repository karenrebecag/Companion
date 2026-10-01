# Reference Brief: SIGPIPE en el bridge MCP, en sus tests y en los demas escritores de sockets y pipes

Slug: bridge-sigpipe | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Pregunta de producto: puede la app (BridgeListener / BridgeConnection / BridgeSession en `Sources/CompanionServices/Bridge/`) morir por SIGPIPE cuando un cliente MCP se desconecta a mitad de una respuesta. Disparador: cinco corridas de CI cuyo job `gates` muere sin resumen y una corrida cuyo job `tsan` sale con "unexpected signal code 13".

Respuesta corta, con el detalle en 2, 3 y 8: el camino del bridge NO puede morir por SIGPIPE con el codigo de 570dca0, porque todo fd aceptado recibe SO_NOSIGPIPE antes de su primera escritura y XNU respeta esa bandera en `write(2)`. Los que si pueden morir son los clientes de prueba (`PosixTestClient`, `BridgePair`), que escriben sobre sockets sin la bandera; y fuera del bridge, la escritura al stdin del CLI delegado (`ExecutorIntegration.sendLine`) es un candidato de producto sin confirmar.

Correccion a la evidencia recibida: solo 3 de las 5 corridas de gates terminan en "Test bridgeListenerTests() started." (36907039863, 36906941949, 36903280273); 36668333244 termina en bridgeConnectionScopeTests y 36728272208 en approvals16q1Tests.

Decisiones a tomar:

1. Arreglo del flake de CI: proteger los clientes de prueba por fd (SO_NOSIGPIPE en `PosixTestClient` y en ambos extremos de `BridgePair`) o ignorar SIGPIPE en todo el proceso de tests.
2. Donde vive la invariante del producto: solo en el accept loop (hoy) o tambien dentro de `BridgeConnection.init`, para que ningun constructor futuro (ni un test) cree una conexion sin proteccion.
3. Si el stdin del proceso delegado (pipe) necesita F_SETNOSIGPIPE, y si se confirma antes con un RED.
4. Si la app adopta `signal(SIGPIPE, SIG_IGN)` global, con el costo de que los hijos de `posix_spawn` lo heredan.
5. Que RED deterministas entran en la spec (lado test y lado producto).

## 2. Estado actual

Contextos: app instalada (/Applications/Companion.app, proceso AppKit, BridgeListener para bridge.sock y browser.sock), relay del navegador (mismo binario lanzado por Chrome, sin AppKit), modo sonda de recursos (mismo binario, escribe a stdout y sale), swift test local en paralelo, CI gates (swift test --no-parallel), CI tsan (swift test --sanitize=thread --no-parallel)

### Escritores sobre sockets en el producto

- El socket que escucha se crea sin SO_NOSIGPIPE: `socket(AF_UNIX, SOCK_STREAM, 0)` y despues solo bind/listen/chmod [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:51]
- El accept loop recibe el fd del cliente con `Darwin.accept(fd, nil, nil)` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:123]
- Lo primero que hace con ese fd es `BridgeSocket.suppressSigpipe(on: clientFD)`, y si falla cierra el fd sin escribir [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:130]
- `suppressSigpipe` es `setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, 1)` y devuelve si dio 0 [repo:Sources/CompanionServices/Bridge/BridgeSocketSupport.swift:58]
- `sigpipeIsSuppressed` lee la bandera de vuelta con `getsockopt(SO_NOSIGPIPE)` [repo:Sources/CompanionServices/Bridge/BridgeSocketSupport.swift:66]
- La respuesta `busy` se escribe solo despues de la proteccion, en el mismo cuerpo del loop [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:141]
- `sendBusy` hace un `Darwin.write` crudo sobre ese fd ya protegido [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:160]
- Tras el `busy` el listener cierra el fd aceptado de inmediato [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:142]
- `BridgeConnection` se construye con el fd ya protegido, despues de la verificacion de uid [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:145]
- `BridgeConnection.init(fd:onClosed:)` no aplica ninguna proteccion por su cuenta: confia en quien le pasa el fd [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:249]
- `send(line:)` comprueba `isClosed()` y escribe despues, fuera del lock [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:279]
- `writeAll` hace `Darwin.write(fd, ...)` en bucle y devuelve false ante EPIPE en vez de lanzar [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:400]
- `close()` hace shutdown y close del fd sin coordinarse con un `send` que ya paso su chequeo de `isClosed()` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:289]
- El comentario dice que un peer cerrado no se puede provocar de forma determinista porque el lector cierra primero [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:329]
- BridgeSession escribe a traves de `connection.send(line:)`, nunca con un write propio (respuesta busy) [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:98]
- BridgeSession escribe la respuesta de cada linea con `connection.send(line: reply)` [repo:Sources/CompanionServices/Bridge/BridgeSession.swift:127]
- El lado cliente del relay aplica `suppressSigpipe` justo despues de `connect` y antes de devolver el fd [repo:Sources/CompanionServices/Bridge/BridgeSocketSupport.swift:38]

### Escritores sobre pipes y stdio en el producto

- El relay del navegador ignora SIGPIPE en todo su proceso por defecto (`ignoreSIGPIPE: Bool = true`) [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:23]
- El relay aplica ademas F_SETNOSIGPIPE al fd de stdout [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:24]
- `RelayIO.suppressSigpipe` es `fcntl(fd, F_SETNOSIGPIPE, 1)` y solo registra el fallo [repo:Sources/CompanionServices/Browser/BrowserRelayIO.swift:28]
- `RelayIO.writeAll` escribe con `Darwin.write` y devuelve false ante cualquier error que no sea EINTR [repo:Sources/CompanionServices/Browser/BrowserRelayIO.swift:13]
- El relay crea su pipe de despertar con `Darwin.pipe` sin F_SETNOSIGPIPE; lo cubre el SIG_IGN del propio relay [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:99]
- El relay escribe en el pipe de despertar [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:109]
- El relay es el mismo binario que la app y sale antes de tocar AppKit [repo:Sources/CompanionApp/CompanionMain.swift:16]
- El modo sonda escribe a stdout con `FileHandle.standardOutput.write` sin proteccion y sin SIG_IGN [repo:Sources/CompanionCore/Platform/ResourceProbe.swift:59]
- La app entra al modo sonda antes de AppKit y sale con `exit` [repo:Sources/CompanionApp/CompanionMain.swift:25]
- El stdin del proceso delegado es un `Pipe()` creado en `spawnSession` sin F_SETNOSIGPIPE despues (el grep de SIGPIPE en Sources solo encuentra Bridge y Browser) [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:263]
- `RealProcessHandle.sendLine` escribe al stdin del hijo con `fileHandleForWriting.write(contentsOf:)` [repo:Sources/CompanionServices/Delegation/ExecutorIntegration.swift:110]
- ClaudeCodeExecutor espera que esa escritura LANCE si el CLI murio entre encargos, y reintenta con un proceso nuevo [repo:Sources/CompanionServices/Delegation/ClaudeCodeExecutor.swift:131]
- `posix_spawn` solo fija POSIX_SPAWN_SETPGROUP, sin POSIX_SPAWN_SETSIGDEF: un SIG_IGN del padre lo heredaria el hijo [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:111]
- El log escribe en un archivo con FileHandle; un archivo regular no produce EPIPE [repo:Sources/CompanionServices/Platform/Log.swift:96]
- La app no llama a `signal(SIGPIPE, ...)` en su arranque: el unico `signal(SIGPIPE` de Sources es el del relay [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:23]

### Escritores en los tests

- `PosixTestClient.init` solo configura SO_RCVTIMEO; no aplica SO_NOSIGPIPE [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:368]
- `PosixTestClient.sendRaw` hace `Darwin.write` sobre ese fd sin proteccion [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:382]
- `testClientsThatCloseAtOnceNeverLeaveTheSlotTaken` espera a proposito respuestas `busy` transitorias y reintenta [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:286]
- En ese bucle el cliente escribe `hello` justo despues de conectar, con `try?`, que no atrapa una senal; si el listener ya cerro tras `busy`, esa escritura va a un peer cerrado [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:319]
- `testOversizedLineGetsFrameTooLargeAndCloses` escribe 70000 bytes en un solo write bloqueante mientras el servidor cierra al pasar 65536 [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:142]
- `BridgePair` entrega a `BridgeConnection` el extremo servidor de un `socketpair` sin SO_NOSIGPIPE [repo:Tests/CompanionServicesTests/BridgeConnectionScopeTests.swift:26]
- `BridgePair.send` escribe en el extremo cliente del socketpair sin proteccion [repo:Tests/CompanionServicesTests/BridgeConnectionScopeTests.swift:33]
- Los tests que cuentan SIGPIPE viven en una suite `.serialized` porque la disposicion es de todo el proceso [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:16]
- `withSigpipeCounter` instala un handler que cuenta y restaura el anterior al salir [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:49]
- Ya existe un control positivo: socketpair, cerrar el peer y escribir levanta SIGPIPE; con `suppressSigpipe` da EPIPE [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:88]
- Ya existe un test que lee la bandera del fd aceptado de vuelta del kernel [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:124]
- Ya existe un test que envia 500 lineas mientras el peer cuelga y no cuenta senales [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:145]
- Ya existe un control sobre un `Pipe()`: un pipe sin proteccion levanta SIGPIPE y uno con F_SETNOSIGPIPE no [repo:Tests/CompanionServicesTests/BrowserHostRelayHardeningTests.swift:41]

### CI

- gates usa `--no-parallel` solo cuando `CI=true` [repo:scripts/gates.sh:266]
- gates imprime solo las ultimas 20 lineas de `swift test` al fallar, asi que la linea "signal code 13" puede quedar fuera [repo:scripts/gates.sh:273]
- tsan corre `swift test --sanitize=thread` con `--no-parallel` [repo:scripts/tsan.sh:18]
- El paquete apunta a macOS 26, lo que fija el SDK y el kernel minimo [repo:Package.swift:9]

## 3. Fuentes primarias

- XNU, `write(2)` sobre un socket: `soo_write` solo levanta SIGPIPE si el error es EPIPE y el socket NO tiene SOF_NOSIGPIPE [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/sys_socket.c#L155@f6217f8]
- XNU, `write(2)` sobre cualquier otro fd (pipe, FIFO): `dofilewrite` levanta SIGPIPE ante EPIPE salvo que el fileglob tenga FG_NOSIGPIPE, y excluye los sockets de esa rama [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/sys_generic.c#L601@f6217f8]
- XNU, F_SETNOSIGPIPE: sobre un socket se traduce a SO_NOSIGPIPE; sobre cualquier otro fd pone FG_NOSIGPIPE, asi que SI funciona en pipes [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_descrip.c#L2944@f6217f8]
- Man page fcntl(2) de XNU: F_SETNOSIGPIPE decide si se genera SIGPIPE cuando falla una escritura "on a pipe or socket for which there is no reader" [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/man/man2/fcntl.2#L246@xnu-f6217f8]
- XNU, herencia: `sonewconn` copia SOF_NOSIGPIPE del socket que escucha al socket aceptado ("inherit socket options stored in so_flags") [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_socket2.c#L393@f6217f8]
- XNU, `setsockopt` devuelve EINVAL sobre un socket con lectura y escritura ya cerradas, que es el rechazo que usa el accept loop para tirar peers muertos [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_socket.c#L4749@f6217f8]
- XNU, AF_UNIX: `uipc_send` devuelve EPIPE cuando el socket tiene SS_CANTSENDMORE, que es el estado tras cerrar el peer [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_usrreq.c#L616@f6217f8]
- XNU, MSG_NOSIGNAL SI existe en Darwin: `sendit` (sendto/sendmsg) no levanta SIGPIPE si el socket tiene SOF_NOSIGPIPE o la llamada pasa MSG_NOSIGNAL [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_syscalls.c#L1378@f6217f8]
- XNU define `MSG_NOSIGNAL 0x80000` bajo `__DARWIN_C_LEVEL >= 200809L`; el SDK local de Xcode (MacOSX.sdk, sys/socket.h:594) trae la misma linea, de modo que la premisa "no existe en Darwin" es falsa [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/socket.h#L637@f6217f8]
- MSG_NOSIGNAL solo aplica a send/sendto/sendmsg: el bridge escribe con `write(2)`, que pasa por `soo_write` y solo mira SOF_NOSIGPIPE [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/sys_socket.c#L157@f6217f8]
- Apple DTS (Quinn, enero 2025): la disposicion por defecto de SIGPIPE termina el proceso; SO_NOSIGPIPE por socket convierte la senal en EPIPE; SIG_IGN global afecta a todo el proceso y no sirve en codigo de biblioteca [doc:https://developer.apple.com/forums/thread/773307@2025-01]
- La documentacion de `FileHandle.write(contentsOf:)` dice que lanza si el pipe o socket no esta conectado, y no menciona SIGPIPE ni EPIPE [doc:https://developer.apple.com/documentation/foundation/filehandle/write(contentsof:)@macOS-26]

## 4. Implementaciones de referencia

### Patron por fd: la invariante vive en el tipo que posee el fd

- SwiftNIO (Apple, el runtime de red de Swift en servidor): `BaseSocket.init` llama a `ignoreSIGPIPE()` en el constructor de todo socket, incluidos los aceptados [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/BaseSocket.swift#L253@d09ffc8]
- SwiftNIO en Darwin usa `fcntl(fd, F_SETNOSIGPIPE, 1)`, cierra el fd si falla y trata EINVAL como un error propio [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/SocketProtocols.swift#L113@d09ffc8]
- SwiftNIO acepta conexiones construyendo `Socket(socket: fd)`, que pasa por ese mismo init [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/ServerSocket.swift#L125@d09ffc8]
- SwiftNIO protege tambien los pipes (`PipePair.ignoreSIGPIPE` sobre input y output) [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/PipePair.swift#L90@d09ffc8]
- SwiftNIO documenta que en Darwin `F_SETNOSIGPIPE` a veces devuelve EINVAL (issues 1030 y 1598) y no cierra el canal servidor por ese error [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/SocketChannel.swift#L405@d09ffc8]
- curl (biblioteca de red de uso universal) aplica SO_NOSIGPIPE a cada socket recien creado y aborta la conexion si no puede [ref:https://github.com/curl/curl/blob/4d36408a6bff8b24327f70a9a79adcab8061726c/lib/cf-socket.c#L477@4d36408]
- libdispatch (swift-corelibs-libdispatch, la misma base que Dispatch en Darwin) pone F_SETNOSIGPIPE a los FIFO que entran a un dispatch_io y lo restaura al soltarlos [ref:https://github.com/swiftlang/swift-corelibs-libdispatch/blob/8a2c456a010d995cfa6a9efada08ea40be46b056/src/io.c#L1517@8a2c456]

### Patron global: SIG_IGN para todo el proceso

- Node.js (runtime de un solo proceso, no biblioteca) pone SIGPIPE en SIG_IGN al arrancar [ref:https://github.com/nodejs/node/blob/adcd028c0e4fddb9c8c10237ccce50dc58b3abc7/src/node.cc#L515@adcd028]
- SwiftNIO cae a SIG_IGN global solo en Linux, porque alli no hay F_SETNOSIGPIPE [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/SocketProtocols.swift#L85@d09ffc8]
- swift-subprocess (swiftlang) ignora SIGPIPE globalmente SOLO en sus tests, "to prevent us from crashing", y no en la biblioteca [ref:https://github.com/swiftlang/swift-subprocess/blob/8f099c6ee12d9b31e1050e9b25daf96bfd7afae4/Tests/SubprocessTests/TestSupport.swift#L26@8f099c6]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Proteger los clientes de prueba por fd: SO_NOSIGPIPE en `PosixTestClient.init` y en ambos extremos de `BridgePair` | Ataca la causa probable del flake; mismo patron que el producto; no oculta senales del producto en otros tests | Hay que repetirlo en cada helper de socket de los tests | baja | Si, para el flake |
| B. Mover la proteccion a `BridgeConnection.init` (ademas del accept loop) | La invariante vive en el tipo, como SwiftNIO `BaseSocket`; ningun constructor futuro ni test la olvida | Duplica un setsockopt en el camino real; init no puede rechazar el fd con EINVAL sin cambiar su firma | baja | Si, como endurecimiento |
| C. SO_NOSIGPIPE en el socket que escucha, para que los aceptados la hereden (sonewconn) | El fd nace protegido; cierra la ventana entre accept y setsockopt | Pierde el EINVAL que hoy descarta peers muertos antes de escribir; solo cubre aceptados | baja | Opcional, sumado a la actual, nunca en su lugar |
| D. `signal(SIGPIPE, SIG_IGN)` global en la app | Cubre pipes, stdout y cualquier fd futuro, incluido el stdin del delegado | Los hijos de posix_spawn lo heredan (no hay POSIX_SPAWN_SETSIGDEF); cambia la semantica de `cmd | head` en las shells del agente | media | No sin SETSIGDEF en ProcessGroup |
| E. SIG_IGN global en el proceso de tests | Una linea; precedente swift-subprocess | Enmascara un SIGPIPE real del producto en todo test fuera de `withSigpipeCounter`; los tests dejan de representar a la app | baja | No como unica medida |
| F. F_SETNOSIGPIPE en el stdin del delegado (`spawnSession`) | Per-fd sobre pipe, como libdispatch y SwiftNIO; convierte la muerte en el error que `attempt` ya espera | Solo tras confirmar el RED; otro fd que recordar | baja | Si, si el RED de 9 confirma la muerte |
| G. Cambiar `write` por `send(..., MSG_NOSIGNAL)` | Existe en Darwin | Por llamada: el siguiente write lo olvida; no aplica a pipes | baja | No |

## 6. Evidencia en contra

- Contra "el bridge esta protegido": el foro de Apple dice que en Apple "no hay forma" de deshabilitar SIGPIPE en un pipe; se resuelve con la fuente del kernel, que muestra FG_NOSIGPIPE para todo fd no socket [doc:https://developer.apple.com/forums/thread/773307@2025-01]
- Y con la evidencia del propio repo: el control con `Pipe()` + F_SETNOSIGPIPE pasa sin senal [repo:Tests/CompanionServicesTests/BrowserHostRelayHardeningTests.swift:44]
- Contra la opcion A: arreglar el cliente de prueba podria esconder un SIGPIPE del producto; se acepta porque el lado servidor ya tiene control positivo y negativo en la suite serializada [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:88]
- Contra A tambien: no esta probado que el SIGPIPE de CI venga de `PosixTestClient`; el log de gates corta a 20 lineas y no muestra la senal [repo:scripts/gates.sh:273]
- Contra "todas las muertes son del bridge": la corrida 36728272208 murio con approvals16q1Tests como ultimo test arrancado, un dispatcher de integracion cuyo archivo no menciona sockets, `Pipe(` ni `Darwin` (importa CompanionServices, asi que un escritor indirecto no queda descartado) [repo:Tests/CompanionIntegrationTests/Approvals16q1Tests.swift:19]
- La corrida 36668333244 murio con bridgeConnectionScopeTests como ultimo test arrancado, cuyo `BridgePair` escribe sin proteccion en ambos extremos [repo:Tests/CompanionServicesTests/BridgeConnectionScopeTests.swift:26]
- Contra la opcion B: el accept loop ya cubre el unico constructor de produccion; B se justifica porque `BridgePair` demuestra que hoy se puede construir una conexion sin la bandera [repo:Tests/CompanionServicesTests/BridgeConnectionScopeTests.swift:26]
- Contra la opcion D: Node la usa, pero Node es dueno de su proceso; aqui ProcessGroup lanza shells y CLIs que heredarian SIG_IGN [ref:https://github.com/nodejs/node/blob/adcd028c0e4fddb9c8c10237ccce50dc58b3abc7/src/node.cc#L515@adcd028]
- Contra el riesgo del delegado: `FileHandle.write(contentsOf:)` podria proteger el fd por dentro (Foundation de Darwin es codigo cerrado); por eso queda como supuesto en la seccion 9 y no como bug [doc:https://developer.apple.com/documentation/foundation/filehandle/write(contentsof:)@macOS-26]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, por fd y en el constructor del tipo: SwiftNIO `BaseSocket.init` llama `try self.ignoreSIGPIPE()` y deshace el fd si falla [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOPosix/BaseSocket.swift#L253@d09ffc8]
- Bien hecho en este repo: proteger antes de la primera escritura y descartar el fd si el kernel rechaza la opcion [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:130]
- Bien hecho en este repo: un test con control positivo (la senal SI llega sin proteccion) antes de afirmar la negativa [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:95]
- Anti-ejemplo: un cliente de prueba que escribe en un socket que el servidor puede cerrar, protegido solo por `try?`, que no atrapa senales [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:319]
- Anti-ejemplo: una conexion de producto construida sobre un socketpair crudo, sin la proteccion que el listener si aplica [repo:Tests/CompanionServicesTests/BridgeConnectionScopeTests.swift:26]
- Anti-ejemplo: codigo que espera un `throw` de una escritura a un pipe cuyo lector murio, cuando el kernel manda la senal antes [repo:Sources/CompanionServices/Delegation/ClaudeCodeExecutor.swift:131]

## 8. Trampas

- La premisa "MSG_NOSIGNAL no existe en Darwin" es falsa en el SDK y el kernel actuales, pero no importa aqui: el codigo usa `write`, no `send` [ref:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/uipc_syscalls.c#L1378@f6217f8]
- La herencia de SO_NOSIGPIPE del socket que escucha existe en XNU, pero este listener nunca la pone en el socket que escucha, asi que no protege nada hoy [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:51]
- Contexto app instalada: los fd del bridge y de browser.sock pasan por el mismo accept loop y quedan protegidos; el stdin del delegado y la carrera fd-reuse siguen abiertos [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:130]
- Contexto relay del navegador: SIG_IGN global + F_SETNOSIGPIPE en stdout + SO_NOSIGPIPE en el socket; los tres escritores estan cubiertos [repo:Sources/CompanionServices/Browser/BrowserHostRelay.swift:23]
- Contexto modo sonda: escribe a stdout sin proteccion; si el script que lo lee cierra antes, el proceso muere por SIGPIPE en vez de dar su codigo de salida [repo:Sources/CompanionCore/Platform/ResourceProbe.swift:59]
- Contexto swift test local en paralelo: si un test de la suite serializada tiene instalado `withSigpipeCounter` mientras corre otro test, el SIGPIPE del otro se cuenta en vez de matar, lo que puede esconder el bug en local [repo:Tests/CompanionServicesTests/BrowserListenerTests.swift:49]
- Contexto CI gates y tsan: con `--no-parallel` ningun handler esta instalado durante bridgeListenerTests, asi que un SIGPIPE del cliente mata al proceso de tests entero y swift-testing no llega a imprimir el resumen [repo:scripts/gates.sh:266]
- Contexto CI tsan: el mensaje "exited with unexpected signal code 13" sale de swiftpm-testing-helper, el proceso que corre los tests; no prueba que la app haria lo mismo [repo:scripts/tsan.sh:18]
- Carrera fd-reuse en `send`: `isClosed()` y el `write` no son atomicos frente a `close()`, asi que un write tardio puede caer en un numero de fd ya reutilizado por otro open (un pipe sin proteccion incluido) [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:280]
- Un SIG_IGN global en la app lo heredan los hijos de posix_spawn porque ProcessGroup no pide SETSIGDEF [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:111]
- El comentario "un peer cerrado no se puede provocar de forma determinista" es cierto solo si se llama a `start()`: sin lector, nada cierra el fd y el write post-cierre es determinista [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:329]

## 9. Incertidumbre

- ASSUMPTION: el SIGPIPE de CI lo levanta el `hello` de `PosixTestClient` en testClientsThatCloseAtOnceNeverLeaveTheSlotTaken, escrito despues de que el listener cerro tras `busy`. prueba: RED lado test en la suite `SigpipeSensitive`: con un primer cliente sosteniendo el slot, un segundo cliente lee la linea `busy`, espera EOF (`waitForEOF()` true), escribe con `send` dentro de `withSigpipeCounter` y se asserta `waitForSigpipes(atLeast: 1)`; tras agregar SO_NOSIGPIPE a `PosixTestClient.init` el mismo test debe dar `stayedBelow(sigpipes: 1)` y error EPIPE
- ASSUMPTION: el lado producto de BridgeConnection no levanta SIGPIPE con un peer muerto. prueba: RED determinista sin hilo lector: `socketpair`, `BridgeSocket.suppressSigpipe` en el extremo servidor, `BridgeConnection(fd:)` SIN `start()`, cerrar el extremo cliente, `connection.send(line:)` 100 veces dentro de `withSigpipeCounter`; debe quedar en 0 senales con el codigo actual (si pasa, la busqueda se dirige al lado test); la variante sin `suppressSigpipe` debe contar al menos 1 (control)
- ASSUMPTION: la app muere por SIGPIPE si el CLI delegado sale antes de que `sendLine` escriba. prueba: `Pipe()`, cerrar `fileHandleForReading`, `try fileHandleForWriting.write(contentsOf:)` dentro de `withSigpipeCounter`; si cuenta al menos 1, Foundation no protege el fd y la opcion F es un bug de producto; si lanza sin senal, se descarta. Medido 2026-10-01 con una sonda fuera del repo (binario de linea de comandos, swiftc -O, Swift 6.3.3): `Pipe()`, cerrar el lector y `write(contentsOf:)` mata el proceso con salida 141 (SIGPIPE) sin lanzar. Foundation no protege el fd; lo unico que queda abierto es la ASSUMPTION siguiente (si AppKit ignora SIGPIPE)
- ASSUMPTION: una app AppKit no ignora SIGPIPE por defecto; no se encontro fuente de Apple que lo diga en ningun sentido. prueba: en un build de desarrollo, leer `sigaction(SIGPIPE, nil, &old)` despues de `NSApplication.shared` y registrar si el handler es SIG_IGN
- ASSUMPTION: la corrida 36728272208 (ultimo test approvals16q1Tests) murio por SIGPIPE y no por otra senal o un fatalError. prueba: cambiar el `tail -20` de gates por un grep de "signal code" sobre la salida completa, o releer el log completo de esa corrida si sigue disponible
- ASSUMPTION: el write de 70000 bytes de testOversizedLine termina antes de que el servidor cierre (los buffers AF_UNIX de 8192 bytes alcanzan para el resto), asi que no es el culpable. prueba: correr ese test 200 veces con `withSigpipeCounter` instalado y contar senales
- ASSUMPTION: Network.framework y su NWConnection protegen sus fds de SIGPIPE; es codigo cerrado y no se pudo leer. prueba: no aplica al bridge (el listener documenta que NWListener rechaza endpoints .unix); solo si se migra el transporte
- ASSUMPTION: el kernel de los runners macos-26 de CI y el de esta Mac (macOS 26.5.1) se comportan como XNU main en f6217f8 para soo_write, dofilewrite y sonewconn. prueba: los controles existentes de `SigpipeSensitive` ya lo ejercitan en CI; si pasan en ambos entornos, el comportamiento coincide
- ASSUMPTION: la carrera fd-reuse de `BridgeConnection.send` es alcanzable en la app. prueba: test de estres que alterna `close()` desde otro hilo con `send` y abre pipes en paralelo, contando bytes que aparecen en el pipe ajeno
- [NEEDS CLARIFICATION: el riesgo del stdin del delegado y la carrera fd-reuse quedan fuera de la pregunta del bridge; van en esta misma spec o en una aparte]

## 10. Checklist de estandar

- [ ] Todo helper de socket en Tests (PosixTestClient, BridgePair y cualquier socketpair que escriba) aplica SO_NOSIGPIPE antes de su primera escritura
- [ ] Existe un RED lado test que escribe tras EOF del servidor y cuenta 1 SIGPIPE sin la proteccion y 0 con ella, dentro de la suite `SigpipeSensitive`
- [ ] Existe un RED lado producto determinista (BridgeConnection sin `start()`, peer cerrado, `send`) con su control positivo
- [ ] Si se adopta B, `BridgeConnection.init` aplica la proteccion y un test la lee de vuelta con `sigpipeIsSuppressed` sobre una conexion construida desde un socketpair crudo
- [ ] Ningun cambio introduce `signal(SIGPIPE, SIG_IGN)` en la app sin POSIX_SPAWN_SETSIGDEF en ProcessGroup
- [ ] El test de la prueba de FileHandle sobre pipe se corre y su resultado decide la opcion F
- [ ] gates.sh muestra la linea "signal code" cuando `swift test` muere por senal, aunque quede fuera de las ultimas 20 lineas
- [ ] bridgeListenerTests pasa 50 corridas seguidas con `--no-parallel` en CI sin muerte por senal

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | XNU bsd/kern sys_socket.c, sys_generic.c, kern_descrip.c, uipc_socket.c, uipc_socket2.c, uipc_usrreq.c, uipc_syscalls.c, bsd/sys/socket.h | Apple (apple-oss-distributions) | main f6217f8 | 2026-10-01 | high |
| 2 | fcntl(2) man page en XNU | Apple | main f6217f8 | 2026-10-01 | high |
| 3 | MacOSX.sdk sys/socket.h y sys/fcntl.h (Xcode local, Swift 6.3.3) | Apple | macOS 26 SDK | 2026-10-01 | high |
| 4 | Debugging Broken Pipes (Quinn, DTS) | Apple Developer Forums | 2025-01 | 2026-10-01 | medium |
| 5 | FileHandle.write(contentsOf:) | Apple Developer Documentation | macOS 26 | 2026-10-01 | medium |
| 6 | SwiftNIO NIOPosix (BaseSocket, SocketProtocols, ServerSocket, PipePair, SocketChannel) | Apple | d09ffc8 | 2026-10-01 | high |
| 7 | curl lib/cf-socket.c | curl project | 4d36408 | 2026-10-01 | high |
| 8 | swift-corelibs-libdispatch src/io.c | swiftlang | 8a2c456 | 2026-10-01 | high |
| 9 | Node.js src/node.cc | Node.js | adcd028 | 2026-10-01 | high |
| 10 | swift-subprocess Tests/SubprocessTests/TestSupport.swift | swiftlang | 8f099c6 | 2026-10-01 | high |
| 11 | Logs de CI 36907039863, 36906941949, 36903280273, 36668333244, 36728272208, 36907018031 (attempt 1) | GitHub Actions karenrebecag/Companion | 2026-09-30 a 2026-10-01 | 2026-10-01 | high |

[KAREN:chat 2026-10-01] D1: opcion A, SO_NOSIGPIPE en PosixTestClient y en ambos extremos de BridgePair; no E. D2: opcion B, la proteccion tambien en BridgeConnection.init. C no. D3: opcion F en esta misma spec pero en su propio PR, solo si su RED confirma la muerte con FileHandle sobre pipe; incluye confirmar que AppKit no ignora SIGPIPE. D4: no SIG_IGN global (D) ni MSG_NOSIGNAL (G). D5: entran los tres RED: lado test, lado producto con BridgeConnection sin start(), y FileHandle sobre pipe.
