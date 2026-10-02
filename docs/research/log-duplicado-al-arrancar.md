# Reference Brief: lineas duplicadas en Companion.log al arrancar (log o registro doble)

Slug: log-duplicado-al-arrancar | Nivel: quick | Fecha: 2026-10-02 | Estado: AUTO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 AUTO

## 1. Pregunta y decisiones abiertas

Pregunta de Karen (via el orquestador, 2026-10-02): al arrancar la app el log principal muestra lineas repetidas. Es solo el log (dos sinks, un observador doble) o la app registra varias veces los mismos taps, listeners u observadores? Si es lo segundo, puede producir acciones dobles (una tecla atendida dos veces, dos listeners del puente, la isla presentada dos veces, notificaciones duplicadas)?

Evidencia leida en este run, solo lineas de ciclo de vida de `~/Library/Logs/Companion.log` (lineas 9264-9290 del archivo):

- 15:34:52.640 y .641: dos `[bridge] listening`.
- 15:34:52.647-.648: `hold: FN tap listening` + `hold: dictation tap listening`, dos veces seguidas.
- 15:34:52.792: `[app] launched` (una vez).
- 15:34:52.797: otro par FN + dictation; 15:34:52.814: `conversation: rolled over after idle window`.
- 15:34:52.879: dos `island: pebble` en el mismo milisegundo.
- 15:34:52.925: otro par FN + dictation (sin rollover detras).
- 15:35:04.462: `[browser] connected browser=chrome`; 15:35:05.975: un tercer `[bridge] listening`.
- 15:35:17.845: otro par FN + dictation.
- 15:35:25.392/.393 `island: nudge` x2; 15:35:25.508/.509 `island: card` x2.
- Contraste util: las transiciones `session: a -> b` salen una sola vez, y `island: bar` a las 15:36:15.228 y 15:36:15.508 sale una sola vez (cambio de alto sin cambio de tamano).
- El patron de dos `[bridge] listening` al arrancar se repite en los arranques del 2026-10-01 08:26 y 14:50, y el `[bridge] listening` suelto tras volver a la app aparece tambien el 2026-10-01 16:06.

Decisiones por hallazgo: (H1) taps FN/dictado, (H2) `[bridge] listening`, (H3) `island: <size>`, (H4) observadores de NotificationCenter, (H5) sink del log. Para cada uno: sin cambio, cambio solo de log (loguear en la transicion) o guarda (arranque idempotente).

Respuesta corta: con el codigo de main 9085264 no hay recurso duplicado. Hay un solo sink; cada tap y cada socket se crea una vez y las llamadas repetidas son idempotentes y se vuelven a loguear. El unico efecto real de una llamada doble es H3: `IslandPanel.present` corre dos veces por cambio de tamano. No produce una segunda presentacion visible ni una notificacion doble, solo la region de clic puede quedar hasta 0,3 s con el alto anterior (supuesto sin probar, ver seccion 9).

## 2. Estado actual

- H5: `Log` tiene un unico sink estatico de proceso [repo:Sources/CompanionServices/Platform/Log.swift:12]
- H5: `write` escribe cada linea una sola vez: al capture del task-local si lo hay, si no al archivo del sink [repo:Sources/CompanionServices/Platform/Log.swift:94]
- H5: el sink se configura una sola vez, en el entorno de arranque [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:37]
- H5: el relay nativo del navegador (mismo binario, lanzado por Chrome) no usa `Log`: escribe en stderr con prefijo `companion-host:` [repo:Sources/CompanionServices/Browser/BrowserRelayIO.swift:61]
- H1: `presentWindow` llama `installDictationTap`, que al final llama `startHoldKeyIfAllowed` [repo:Sources/CompanionApp/CompanionMainWindow.swift:51]
- H1: `installDictationTap` termina llamando `startHoldKeyIfAllowed` [repo:Sources/CompanionApp/CompanionMain.swift:217]
- H1: `presentWindow` vuelve a llamar `startHoldKeyIfAllowed` veinte lineas despues: segundo par del log, antes de `launched` [repo:Sources/CompanionApp/CompanionMainWindow.swift:71]
- H1: `presentWindow` activa la app con `NSApp.activate(ignoringOtherApps: true)` [repo:Sources/CompanionApp/CompanionMainWindow.swift:130]
- H1: `presentWindow` loguea `launched` al final [repo:Sources/CompanionApp/CompanionMainWindow.swift:217]
- H1: `applicationDidBecomeActive` llama `startHoldKeyIfAllowed` en cada activacion: par de 15:34:52.797, el de 15:35:17 y siguientes [repo:Sources/CompanionApp/CompanionMain.swift:124]
- H1: el mismo `applicationDidBecomeActive` llama `rolloverIfIdle`, que explica el `rolled over` de 15:34:52.814 justo despues del tercer par [repo:Sources/CompanionApp/CompanionMain.swift:127]
- H1: tercera via, `onPermissionChanged` llama `startHoldKeyIfAllowed` [repo:Sources/CompanionApp/CompanionMainWindow.swift:31]
- H1: `onPermissionChanged` solo se dispara desde `request()`, tras la respuesta al dialogo del sistema [repo:Sources/CompanionUI/Settings/HoldSettings.swift:57]
- H1: `startHoldKeyIfAllowed` loguea `FN tap listening` siempre que `holdKey.start()` devuelve true [repo:Sources/CompanionApp/CompanionMain.swift:230]
- H1: y `dictation tap listening` siempre que `dictationTap.start()` devuelve true [repo:Sources/CompanionApp/CompanionMain.swift:236]
- H1: `HoldKeyTap.start()` devuelve true sin crear nada si ya hay `port`: la llamada repetida es idempotente [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:79]
- H1: solo la primera llamada crea el tap con `CGEvent.tapCreate` [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:85]
- H1: el `port` se guarda bajo lock despues de crearlo; la comprobacion de la linea 79 y esta asignacion no son atomicas entre si [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:99]
- H1: todos los llamadores de `start()` estan en `CompanionApp`, cuyo aislamiento por defecto es `MainActor` [repo:Package.swift:43]
- H1: el FN tap se construye una sola vez por lanzamiento, en `presentWindow` [repo:Sources/CompanionApp/CompanionMainWindow.swift:29]
- H1: un solo consumidor itera `holdKey.events` [repo:Sources/CompanionApp/CompanionMainWindow.swift:35]
- H1: `installDictationTap` para y descarta el tap de dictado anterior antes de crear el nuevo [repo:Sources/CompanionApp/CompanionMain.swift:190]
- H1: cada `installDictationTap` arranca una `Task` nueva que itera `tap.events` del tap nuevo [repo:Sources/CompanionApp/CompanionMain.swift:201]
- H1: `stop()` invalida el port pero no llama `continuation.finish()`, asi que la `Task` del tap anterior queda suspendida para siempre sin recibir eventos [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:122]
- H2: `BridgeListener.start()` loguea `listening` sin decir que socket [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:84]
- H2: el nombre del socket es un parametro del listener, `bridge.sock` por defecto [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:27]
- H2: `BrowserHost` crea su propio `BridgeListener` sobre `browser.sock` [repo:Sources/CompanionServices/Browser/BrowserHost.swift:40]
- H2: `installBridge` arranca primero el listener del navegador si hay un manifiesto instalado [repo:Sources/CompanionApp/CompanionMain.swift:142]
- H2: `installBridge` arranca despues el del puente si "Prestar las manos" esta activo [repo:Sources/CompanionApp/CompanionMain.swift:162]
- H2: `BrowserHost.startIfInstalled` solo arranca con un manifiesto instalado [repo:Sources/CompanionServices/Browser/BrowserHost.swift:67]
- H2: `BrowserHost.start` es idempotente: sale con true si ya arranco [repo:Sources/CompanionServices/Browser/BrowserHost.swift:151]
- H2: `BridgeHost.apply(enabled:)` es idempotente: sale si el estado pedido ya es el actual [repo:Sources/CompanionApp/BridgeHost.swift:102]
- H2: `BridgeListener.stop()` no loguea nada, asi que un apagado y reencendido solo deja ver el segundo `listening` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:94]
- H2: el ajuste "Prestar las manos" publica `.companionHandsLendingDidChange` solo en un cambio real de valor [repo:Sources/CompanionUI/Settings/UserPreferences.swift:324]
- H2: el toggle de Ajustes escribe ese ajuste en cada cambio del switch [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:69]
- H3: el cierre `onSize` presenta el panel y luego loguea `island: <size>` [repo:Sources/CompanionApp/CompanionMainWindow.swift:154]
- H3: `IslandView` llama `onSize` desde `onPreferenceChange(IslandSizeKey.self)` cuando cambia el alto del contenido [repo:Sources/CompanionUI/Island/IslandView.swift:170]
- H3: y otra vez desde `onChange(of: state.size, initial: true)`, con el `contentHeight` guardado hasta ese momento [repo:Sources/CompanionUI/Island/IslandView.swift:178]
- H3: el alto viene de un `GeometryReader` que publica `IslandSizeKey` [repo:Sources/CompanionUI/Island/IslandView.swift:155]
- H3: hay un solo `IslandPanel` y una sola `IslandView` por lanzamiento [repo:Sources/CompanionApp/CompanionMainWindow.swift:149]
- H3: el primer `present(.pebble)` lo hace `presentWindow` directamente y no loguea [repo:Sources/CompanionApp/CompanionMainWindow.swift:177]
- H3: `present` cancela la tarea de encogimiento pendiente en cada llamada [repo:Sources/CompanionUI/Island/IslandChrome.swift:250]
- H3: `present` solo trae el panel al frente si no estaba visible, asi que una segunda llamada no lo vuelve a mostrar [repo:Sources/CompanionUI/Island/IslandChrome.swift:270]
- H3: si el blanco es mas chico que la region actual, `hitSizes` conserva la actual y encoge despues [repo:Sources/CompanionUI/Island/IslandChrome.swift:93]
- H3: ese encogimiento diferido espera 0,3 s [repo:Sources/CompanionUI/Island/IslandChrome.swift:97]
- H4: `installBridge` agrega una vez el observador de `.companionHandsLendingDidChange` [repo:Sources/CompanionApp/CompanionMain.swift:164]
- H4: `presentWindow` agrega una vez el observador de `.companionDictationKeyDidChange` [repo:Sources/CompanionApp/CompanionMainWindow.swift:57]
- H4: ambos se agregan desde `applicationDidFinishLaunching` [repo:Sources/CompanionApp/CompanionMain.swift:97]
- H4: los tokens que devuelve `addObserver` se descartan y no se quitan nunca [repo:Sources/CompanionApp/CompanionMain.swift:169]
Contextos: (1) la app empaquetada en /Applications, unico contexto donde se observo el log; (2) `swift test`, donde `Log.capturing` redirige a un archivo por test y no hay test target de `CompanionApp`, asi que `startHoldKeyIfAllowed`, `installBridge` y el cierre `onSize` no se ejecutan bajo test; (3) el relay nativo del navegador, mismo binario lanzado por Chrome, que sale antes de configurar `Log`; (4) CI, igual que (2).

## 3. Fuentes primarias

- `applicationDidFinishLaunching(_:)` se llama despues de arrancar el run loop principal y antes de procesar eventos: los observadores que agrega corren una vez por lanzamiento [doc:https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidfinishlaunching(_:)@macOS-26]
- `applicationDidBecomeActive(_:)` "Tells the delegate that the app is now active", y recibe `didBecomeActiveNotification` [doc:https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidbecomeactive(_:)@macOS-26]
- `didBecomeActiveNotification` se publica "immediately after the app becomes active", en el main actor; no dice que sea una sola vez: se publica en cada activacion [doc:https://developer.apple.com/documentation/appkit/nsapplication/didbecomeactivenotification@macOS-26]
- `CGEvent.tapCreate` devuelve un mach port "that represents the new event tap", o NULL si no se pudo crear: cada llamada que llega ahi crea un tap nuevo [doc:https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)@macOS-26]
- `CGEvent.tapEnable`: los taps "are normally enabled when created"; si un tap deja de responder llega `kCGEventTapDisabled` al callback y se puede reactivar con esta funcion [doc:https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)@macOS-26]
- `addObserver(forName:object:queue:using:)` "Adds an entry" por llamada y devuelve un token que el centro retiene hasta quitarlo; si una notificacion dispara varios bloques, todos corren [doc:https://developer.apple.com/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:)@macOS-26]
- `onChange(of:initial:_:)`: `initial` indica si la accion corre "when this view initially appears"; despues corre cuando cambia el valor [doc:https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg@macOS-26]
- `onPreferenceChange(_:perform:)` corre la accion "when the specified preference key's value changes", y exige `Value: Equatable` [doc:https://developer.apple.com/documentation/swiftui/view/onpreferencechange(_:perform:)@macOS-26]
- Ninguna de las dos paginas de SwiftUI documenta el orden entre `onChange` y `onPreferenceChange` cuando ambos cambian en la misma actualizacion [doc:https://developer.apple.com/documentation/swiftui/view/onpreferencechange(_:perform:)@macOS-26]

## 4. Implementaciones de referencia

- No hace falta referencia externa: el patron recomendado (loguear en la transicion, no en la llamada) ya existe en el repo, en `BridgeHost.apply`, que solo actua cuando el estado cambia [repo:Sources/CompanionApp/BridgeHost.swift:102]

## 5. Opciones

| Hallazgo | Que emite la linea doble | Recurso creado mas de una vez? | Accion doble posible? | Opcion recomendada |
|---|---|---|---|---|
| H1 taps FN/dictado | tres vias llaman `startHoldKeyIfAllowed`: `installDictationTap`, `presentWindow` y cada `applicationDidBecomeActive` | No: `start()` sale en la linea 79 si ya hay port | No: un tap, un consumidor por tap | Solo log: loguear `listening` cuando `start()` crea el tap, no cuando ya existia |
| H2 `[bridge] listening` x2 | dos listeners distintos, `browser.sock` (BrowserHost) y `bridge.sock` (BridgeHost), con el mismo texto | No: cada host tiene su guarda `started` | No | Solo log: incluir el nombre del socket y loguear tambien `stopped` |
| H2 tercer `listening` | un `start()` posterior de uno de los dos listeners | No se puede afirmar (ver seccion 9) | No en el mismo socket: el host lo impide | Lo explica el mismo cambio de log; no tocar la logica |
| H3 `island: <size>` x2 | `onChange(of: state.size, initial: true)` y `onPreferenceChange` llaman `onSize` en el mismo cambio | `present` corre dos veces; no se crea panel ni vista nueva | No hay presentacion visible doble ni notificacion; posible region de clic con el alto viejo hasta 0,3 s | Solo log (registrar solo si cambia el tamano) y medir antes de poner guarda en `present` |
| H4 observadores | se agregan una vez por lanzamiento | No | No | Sin cambio |
| H5 sink | un sink, un `configure` | No | No | Sin cambio |

Alternativa a la opcion de H1 descartada por ahora: una guarda en `startHoldKeyIfAllowed` que no llame a `start()` si el tap ya corre. No agrega seguridad, porque `start()` ya es idempotente, y esconderia la reactivacion cuando el permiso cambia.

Alternativa a la opcion de H3: guarda de igualdad en `IslandPanel.present` (salir si `(size, contentHeight)` es igual a `presented`). Arregla el log y la doble llamada, pero cambia el comportamiento de la region de clic. Solo se justifica si la prueba de la seccion 9 muestra la region sobredimensionada.

## 6. Evidencia en contra

- Contra "es solo log" en H1: la comprobacion de `port == nil` y la asignacion del port no son atomicas, asi que dos `start()` concurrentes crearian dos taps; hoy no ocurre porque todos los llamadores estan en `MainActor`, y se acepta con la trampa anotada en la seccion 8 [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:79]
- Contra "es solo log" en H3: la segunda llamada no es identica, porque `onChange` usa el `contentHeight` guardado y `onPreferenceChange` usa el alto nuevo; por eso es un efecto real (doble `present`) y no un log repetido, aunque acotado a la region de clic [repo:Sources/CompanionUI/Island/IslandView.swift:178]
- Contra "solo log" en H2: el tercer `listening` sin `stopped` previo no se puede atribuir con el log actual; podria ser otro camino de arranque que no encontre, y por eso la recomendacion incluye loguear `stopped` [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:94]
- Contra cambiar el log de H1: el par repetido en cada activacion es la unica senal de que `applicationDidBecomeActive` corrio y reconfirmo el permiso; si solo se loguea la transicion, esa senal se pierde y hace falta otra linea si se quiere conservar [repo:Sources/CompanionApp/CompanionMain.swift:122]

## 7. Ejemplares y anti-ejemplos

- Bien hecho: `apply(enabled:)` sale si el estado pedido ya es el actual y solo entonces arranca o detiene [repo:Sources/CompanionApp/BridgeHost.swift:102]
- Anti-ejemplo: loguear el resultado booleano de una llamada idempotente como si fuera un evento (`if holdKey.start() { Log.app("... listening") }`) [repo:Sources/CompanionApp/CompanionMain.swift:230]
- Anti-ejemplo: dos componentes distintos con el mismo texto de log, sin identificar cual habla [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:84]

## 8. Trampas

- Si algun dia se llama `HoldKeyTap.start()` fuera del main actor (por ejemplo desde un callback de permiso en otra cola), la ventana entre la linea 79 y la 99 permite dos `tapCreate` y dos taps sobre la misma tecla; el FN tap ademas consume eventos [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:99]
- Cada cambio de "Tecla de dictado" deja una `Task` suspendida para siempre, porque `stop()` no termina el stream; no produce acciones dobles pero es una fuga por cambio de ajuste [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:122]
- Un cambio de log que mueva `Log.app("hold: ...")` dentro de `HoldKeyTap` no se puede probar en CI en el camino de creacion, porque `start()` exige `AXIsProcessTrusted()` antes de crear el tap [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:80]
- `CompanionApp` no tiene test target: un test en rojo para H1 o H3 necesita que la decision de loguear viva en Core, Services o UI, no en el cierre de la App [repo:Package.swift:41]
- Una guarda de igualdad en `IslandPanel.present` tambien saltaria `syncCatcher` y la cancelacion de `shrinkTask` en las llamadas repetidas; hay que revisar que ninguna llamada dependa de eso [repo:Sources/CompanionUI/Island/IslandChrome.swift:260]
- En el contexto `swift test`, `Log.capturing` es un task-local: un test del log de `BridgeListener.start()` funciona porque `start()` loguea en el hilo de quien llama, no en el hilo de accept [repo:Sources/CompanionServices/Platform/Log.swift:30]

## 9. Incertidumbre

- ASSUMPTION: el par FN + dictado de 15:34:52.925 viene de un segundo `applicationDidBecomeActive` en el arranque (activacion de la ventana y despues del panel), no de `onPermissionChanged`. prueba: loguear `active` dentro de `applicationDidBecomeActive` en un build local y contar las lineas en un arranque.
- ASSUMPTION: el tercer `[bridge] listening` (15:35:05.975, y el de 2026-10-01 16:06) es un apagado y reencendido de "Prestar las manos" o del enlace del navegador, porque `stop()` no loguea. prueba: con el cambio de log de H2 (nombre del socket y `stopped`), repetir el uso y leer que socket se reinicia.
- ASSUMPTION: en un cambio de tamano, `onChange` corre antes que `onPreferenceChange` y le pasa a `present` el alto anterior; si ese alto es mayor, la region de clic queda grande hasta 0,3 s. Apple no documenta el orden. prueba: en un build local, loguear el `contentHeight` de cada llamada a `onSize` y abrir y cerrar una tarjeta, comparando las dos alturas del mismo milisegundo.
- ASSUMPTION: solo corria un proceso de la app (una sola linea `launched` y una sola `prewarm` en el arranque). prueba: `pgrep -lf Companion.app` durante un arranque.
- Evidencia en contra de la conclusion global ("ningun recurso duplicado"): (a) no ejecute la app ni los tests; todo sale de leer el codigo de main 9085264 y el log, y la app instalada podria venir de otro commit; (b) el orden SwiftUI de H3 no esta documentado; (c) el tercer `listening` no tiene explicacion probada; (d) la idempotencia de `HoldKeyTap.start()` depende de que todos los llamadores sigan en el main actor, algo que el codigo no impone en el tipo (`@unchecked Sendable`).
- [NEEDS CLARIFICATION: en el arranque del 2026-10-02 a las 15:35, cambiaste "Prestar las manos" o reconectaste el navegador en Ajustes? Eso cerraria el tercer `[bridge] listening` sin otro build.]
- Inyecciones sospechadas en el contenido leido: ninguna.

RED tests propuestos (no escritos, el brief no toca codigo):

- H2 (Services, `BridgeListenerTests`): dentro de `Log.capturing(to:)`, arrancar un listener con `socketName: "browser.sock"` y otro con el valor por defecto; esperar dos lineas distintas que contengan `browser.sock` y `bridge.sock`. Falla hoy porque las dos dicen `listening`. Segundo caso: `stop()` deja una linea `stopped` con el socket; falla hoy porque no hay linea.
- H1 (Core o Services): extraer la decision a una funcion pura, por ejemplo `HoldTapLog.line(wasRunning:started:)`, que devuelve el texto solo si `wasRunning == false && started == true`. El test en rojo pide `nil` para `(wasRunning: true, started: true)`. La App lee `holdKey.isRunning` antes de `start()`, lo que obliga a exponer `isRunning` en `HoldKeyTap` (lectura de `port != nil` bajo lock, testeable sin Accesibilidad para el caso `false`).
- H3 (UI): si se decide solo el log, una funcion pura de deduplicacion `IslandSizeLog.shouldLog(previous:next:)` con test en rojo que pide `false` para `.pebble -> .pebble`. Si la prueba de la seccion 9 confirma la region sobredimensionada, el test en rojo va sobre `IslandPanel.present`: dos llamadas con el mismo tamano y alturas distintas no deben dejar `hitSize` mayor que el blanco de la segunda.

## 10. Checklist de estandar

- [ ] Cada linea `listening` del log identifica su socket (`bridge.sock` o `browser.sock`) y cada `stop()` deja una linea `stopped`.
- [ ] `hold: FN tap listening` y `hold: dictation tap listening` aparecen una vez por creacion real del tap, no por llamada a `startHoldKeyIfAllowed`.
- [ ] `island: <size>` aparece una vez por cambio de tamano.
- [ ] Ningun cambio altera la idempotencia de `HoldKeyTap.start()`, `BrowserHost.start()` ni `BridgeHost.apply(enabled:)`.
- [ ] Cada fix llega con su test en rojo previo en Core, Services o UI (no en `CompanionApp`, que no tiene test target).
- [ ] Si se toca `IslandPanel.present`, un test prueba que dos llamadas con el mismo tamano y alturas distintas dejan la region de clic en el blanco de la segunda.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | applicationDidFinishLaunching(_:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 2 | applicationDidBecomeActive(_:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 3 | NSApplication.didBecomeActiveNotification | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 4 | CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 5 | CGEvent.tapEnable(tap:enable:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 6 | NotificationCenter.addObserver(forName:object:queue:using:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 7 | View.onChange(of:initial:_:) | Apple | macOS 14+ / macOS 26 SDK docs | 2026-10-02 | high |
| 8 | View.onPreferenceChange(_:perform:) | Apple | macOS 26 SDK docs | 2026-10-02 | medium |
| 9 | Codigo de companion-next (Log, HoldKeyTap, BridgeListener, BridgeHost, BrowserHost, IslandView, IslandChrome, CompanionMain, CompanionMainWindow) | repo | main 9085264 | 2026-10-02 | high |
| 10 | ~/Library/Logs/Companion.log, lineas de ciclo de vida 2026-10-01 y 2026-10-02 | app instalada | 2026-10-02 | 2026-10-02 | medium |
