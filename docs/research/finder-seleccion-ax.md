# Reference Brief: Seleccion de Finder, texto seleccionado y clics para el modo pasivo (b2b-2)

Slug: finder-seleccion-ax | Nivel: standard | Fecha: 2026-10-03 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-03 ESCALATE

## 1. Pregunta y decisiones abiertas

Spec b2b-2 (modo pasivo de Companion, replica de Incredible 0.2.36, pedido "igual que Incredible" segun el encargo del orquestador). Companion tiene que leer tres cosas con APIs publicas de macOS 26:

1. La seleccion actual de Finder (archivos y carpetas, como rutas).
2. El texto seleccionado en la app del frente.
3. Los clics de la usuaria: app, elemento y posicion.

Decisiones que el brief deja abiertas para la spec:

- D1. Mecanismo de la seleccion de Finder: Accesibilidad (`AXSelectedRows` / `AXSelectedChildren` mas `AXURL` o `AXFilename` de cada item) o Apple Events a Finder (`selection`, pide Automatizacion).
- D2. Mecanismo del texto seleccionado: lectura AX de `kAXSelectedTextAttribute` del elemento con foco, con o sin el respaldo de text markers para WebKit/Chromium; nunca Cmd+C sintetico.
- D3. Mecanismo de los clics: `NSEvent.addGlobalMonitorForEvents` con mascara solo de raton, un `CGEventTap` `.listenOnly`, o un `CGEventTap` `.defaultTap` como el de la tecla FN.
- D4. Que aviso de TCC aparece en cada camino, y como se prueba que NO aparece Entrada (Input Monitoring).
- D5. Cuando se lee: en cada notificacion AX (stream continuo) o solo mientras la usuaria sostiene FN, que es donde Incredible muestra lo capturado.

Lo que se ve de Incredible (analisis estatico local, extractos fuera del repo; no citable con URL, por eso va aqui y no en 2-8):

- El overlay convierte un stream de eventos con kinds `surface_changed`, `clicked` (con `element`), `typed`, `hovered`, `selected_text` (con `text`), `selected` (con `paths`), `copied` y `dialog_opened`: `~/Desktop/incredible-ref/frontend-0.2.36/overlay-DstkIEbM.js`, bytes ~41100-41900 (sha1 del archivo empieza 7e3f1e443c26).
- `selected` se pinta un chip por ruta: etiqueta = nombre, detalle = ruta completa; `selected_text` y `copied` van entre comillas; `hovered` no se pinta (mismo rango).
- Los chips viven en el "hold companion" (`ov-hold-collect`, maximo 3 a la vez, tiempos 1400 y 1700 ms), bytes ~44137-44600, y se alimentan de una suscripcion con `generation` y `events`, byte ~47086.
- El helper de manos de Incredible contiene los nombres `AXFocusedUIElementChanged`, `AXSelectedChildrenChanged`, `AXSelectedRowsChanged`, `AXSelectedTextRange(s)` y `AXFocusedUIElement`: `~/Desktop/incredible-ref/accessibility-helper.md` lineas 71-77, 104-106 y 242 (sha1 4c0687f49e56).
- En los extractos de Incredible no aparecen `CGEventTapCreate`, `addGlobalMonitor`, `ListenEvent`, `IOHID`, `CGPreflight` ni un script de Finder `selection`; son extractos de cadenas legibles, asi que la ausencia NO prueba que no los use (ver seccion 9).
- La `NSAppleEventsUsageDescription` de Incredible habla de "accessibility access to type text": `~/Desktop/incredible-ref/incredible.md` lineas 15-16 (sha1 3eda83cd0015). Tener la clave no prueba que mande Apple Events a Finder.
- En Incredible, "passive" es el estado de presencia (`passive_after_secs`, por defecto 600), no un modo de percepcion: `frontend-0.2.36/main-BL-DABKy.js` bytes ~1604592 y ~338809.

## 2. Estado actual

- El paquete apunta a macOS 26 (`platforms: [.macOS(.v26)]`); el SDK local reporta 26.5 [repo:Package.swift:9]
- El "modo pasivo" de Companion hoy es solo el estado de presencia tras 10 minutos, igual que `passive_after_secs` de Incredible [repo:Sources/CompanionUI/Voice/PassivePreference.swift:4]
- No hay en `origin/main` ninguna lectura de la seleccion de Finder: ni `AXSelectedRows`, ni `AXSelectedChildren`, ni `AXURL`, ni un script de Finder (grep de esos nombres en Sources sin resultados) [repo:Sources/CompanionServices/Perception/ContextSensors.swift:329]
- Lo mas cercano a Finder es `OpenDocumentsSensor`, que lee `kAXDocumentAttribute` o el titulo de cada ventana de la app del frente, no la seleccion [repo:Sources/CompanionServices/Perception/ContextSensors.swift:336]
- Ya se lee `kAXSelectedTextAttribute` del elemento con foco, pero como respaldo de `kAXValueAttribute` para las manos, no como sensor de seleccion [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:31]
- Esa lectura ya salta campos seguros antes de leer (`AXSecure.isSecure`) [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:29]
- Ya se lee `kAXSelectedTextRangeAttribute` para ubicar el caret [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:46]
- Ya existe un `AXObserver` por proceso sobre el elemento aplicacion, con su fuente en el run loop y un solo slot vivo a la vez [repo:Sources/CompanionServices/Accessibility/AXChangeWatcher.swift:216]
- Ese observer registra notificaciones con `AXObserverAddNotification` sobre el elemento aplicacion [repo:Sources/CompanionServices/Accessibility/AXChangeWatcher.swift:222]
- Ese observer solo atiende notificaciones dentro de una llamada de manos; fuera de ella las ignora, asi que no sirve tal cual para un stream pasivo [repo:Sources/CompanionServices/Accessibility/AXChangeWatcher.swift:59]
- Ya hay un hit test AX bajo el cursor (`AXUIElementCopyElementAtPosition` sobre el elemento system-wide) que devuelve app, rol y texto acotado, y descarta el propio pid [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:113]
- Ese hit test pone un timeout de mensajeria de 50 ms por app [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:78]
- Ya hay un monitor global de NSEvent, pero solo de `.mouseMoved` y `.leftMouseDragged` para la isla [repo:Sources/CompanionUI/Island/IslandChrome.swift:339]
- El atajo de teclado usa un monitor local, no global [repo:Sources/CompanionUI/Window/KeyboardMonitor.swift:35]
- La tecla FN usa un `CGEventTap` `.defaultTap` en `.cghidEventTap`, condicionado a `AXIsProcessTrusted()`, no a Entrada [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:80]
- Ese tap se crea con `options: .defaultTap` [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:88]
- El puerto de Entrada (Input Monitoring) sigue declarado pero marcado como API sobrante: "FN now uses Accessibility" [repo:Sources/CompanionCore/Perception/Permissions.swift:11]
- Su adaptador llama `CGPreflightListenEventAccess` y `CGRequestListenEventAccess` [repo:Sources/CompanionServices/Permissions/InputMonitoringPermission.swift:13]
- Ya existe el enlace a Ajustes de Entrada (`Privacy_ListenEvent`) [repo:Sources/CompanionCore/Perception/Permissions.swift:39]
- El permiso de Accesibilidad se consulta en cada lectura y solo la fila de Ajustes lo pide [repo:Sources/CompanionServices/Permissions/AccessibilityPermission.swift:14]
- Companion ya manda Apple Events con `NSAppleScript` (hojas de Excel/Numbers y acciones de sistema) [repo:Sources/CompanionServices/Deliverables/AppleEventSheets.swift:156]
- El entitlement de Apple Events ya esta en el archivo de entitlements [repo:scripts/companion.entitlements:8]
- El archivo de entitlements no tiene `com.apple.security.app-sandbox`: la app no esta en sandbox [repo:scripts/companion.entitlements:4]
- La `NSAppleEventsUsageDescription` actual solo habla de hojas de calculo en Excel o Numbers [repo:scripts/bundle.sh:91]
- El bundle de desarrollo se firma con la identidad estable "Companion Dev" (o ad hoc) y sin `--options runtime` [repo:scripts/bundle.sh:114]
- El release se firma con hardened runtime y los entitlements [repo:scripts/release.sh:53]
- La identidad estable existe para que TCC conserve los permisos entre builds; ad hoc los pierde [repo:scripts/bundle.sh:104]
- Precedente de privacidad: el sensor de portapapeles salta contenido oculto y para archivos da nombres, no rutas [repo:Sources/CompanionServices/Perception/ContextSensors.swift:409]
- Companion ya activa `AXManualAccessibility` al cebar una app (Electron/Chromium) [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:228]
- Los tests en vivo leen `AXIsProcessTrusted()` del proceso de test, no de la app [repo:Tests/CompanionServicesTests/LiveScreenTests.swift:12]
- Sin `NSApplication` (proceso de test) no hay ventanas propias que excluir [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:98]
Contextos: app de desarrollo (bundle.sh, identidad Companion Dev, sin hardened runtime), app de release (hardened runtime + entitlements), swift test local (proceso de test con la confianza AX de la terminal que lo lanza), CI (sin concesiones TCC, sin sesion grafica con permisos)

## 3. Fuentes primarias

- `kAXSelectedChildrenAttribute`: arreglo de hijos seleccionados de primer orden; "required for accessibility objects that contain selectable child objects" [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedchildrenattribute.json@macOS26]
- `kAXSelectedRowsAttribute`: las filas seleccionadas de una tabla o outline [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedrowsattribute.json@macOS26]
- `kAXURLAttribute`: la URL que describe la ubicacion del documento o app que representa el objeto [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxurlattribute.json@macOS26]
- `kAXFilenameAttribute`: el nombre de archivo asociado al objeto, atributo opcional [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxfilenameattribute.json@macOS26]
- `kAXSelectedTextAttribute`: el texto seleccionado; solo es obligatorio en objetos que representan texto editable [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedtextattribute.json@macOS26]
- `kAXSelectedTextChangedNotification`: se selecciono otro texto [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedtextchangednotification.json@macOS26]
- `kAXSelectedChildrenChangedNotification`: se selecciono otro subconjunto de hijos [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedchildrenchangednotification.json@macOS26]
- `kAXSelectedRowsChangedNotification`: cambio el conjunto de filas seleccionadas [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedrowschangednotification.json@macOS26]
- `AXObserverAddNotification`: el objeto system-wide no admite notificaciones (`kAXErrorNotificationUnsupported`); hay que observar cada app [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462089-axobserveraddnotification.json@macOS26]
- `addGlobalMonitorForEvents`: solo observa copias de eventos de otras apps, no las modifica, y "key-related events may only be monitored if accessibility is enabled or if your application is trusted" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:).json@macOS26]
- La misma pagina lista los tipos de raton (`leftMouseDown`, `rightMouseDown`, `otherMouseDown`...) entre los que un monitor global puede observar, y no pone condicion de permiso a los de raton [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:).json@macOS26]
- `CGEvent.tapCreate`: si el tap no puede monitorear algun tipo pedido, limpia esos bits de la mascara y devuelve nil si queda vacia (la pagina sigue describiendo la regla de 10.4 y no menciona Entrada) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:).json@macOS26]
- `CGPreflightListenEventAccess` existe desde 10.15 y dice si la app puede escuchar eventos del sistema; la pagina no tiene discusion [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgpreflightlisteneventaccess().json@macOS26]
- WWDC19 701: monitorear todo el teclado de otras apps pide aprobacion; "a listen-only event [tap] requires authorization for input monitoring, a modifying event [tap] requires authorization for accessibility features" [doc:https://developer.apple.com/videos/play/wwdc2019/701/@2019]
- WWDC19 701: la primera vez, `CGEventTapCreate` de teclado devuelve nil y el sistema muestra el dialogo hacia Privacidad; `IOHIDCheckAccess` con `kIOHIDRequestTypeListenEvent` consulta sin pedir [doc:https://developer.apple.com/videos/play/wwdc2019/701/@2019]
- Quinn (Apple DTS, jun 2022): un monitor global de `NSEvent` requiere el privilegio de Accesibilidad, mientras un `CGEventTap` requiere Entrada; las apps en sandbox no pueden usar el privilegio de Accesibilidad [doc:https://developer.apple.com/forums/thread/707680@2022-06]
- Entitlement de Apple Events: indica que la app puede pedir permiso para mandar Apple Events; se activa con hardened runtime [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events.json@macOS26]
- `NSAppleEventsUsageDescription` es obligatoria si la app usa APIs que mandan Apple Events, y explica por que se pide [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.json@macOS26]
- Secundaria (foro, no Apple): con `.listenOnly` aparece el pedido de Entrada y con `.defaultTap` el de Accesibilidad; si la app ya tiene Accesibilidad, el de Entrada no sale (observacion de un desarrollador, abr 2021) [doc:https://developer.apple.com/forums/thread/122492@2021-04]

## 4. Implementaciones de referencia

- Easydict (tisfeng, ~14.8k estrellas, push 2026-09-30): traductor de seleccion; escucha teclado con un `CGEventTap` `.listenOnly`, es decir el camino que pide Entrada [ref:https://github.com/tisfeng/Easydict/blob/cfda6e2f43741a3210a290e422846f1d83742d38/Easydict/Swift/Utility/EventMonitor/Engine/EventTapMonitor.swift#L65-L72@cfda6e2]
- Easydict detecta el fin de una seleccion con monitores NSEvent local y global sobre `leftMouseDown`, `leftMouseUp`, `rightMouseDown` y `leftMouseDragged` [ref:https://github.com/tisfeng/Easydict/blob/cfda6e2f43741a3210a290e422846f1d83742d38/Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift#L129-L144@cfda6e2]
- Easydict pide Accesibilidad con `AXIsProcessTrustedWithOptions` y el prompt, y manda a `Privacy_Accessibility` [ref:https://github.com/tisfeng/Easydict/blob/cfda6e2f43741a3210a290e422846f1d83742d38/Easydict/Swift/Utility/EventMonitor/Core/EventMonitor.swift#L178-L191@cfda6e2]
- SelectedTextKit (mismo autor, la libreria de seleccion que usa Easydict, push 2026-09-27): lee `focusedUIElement` de la app del frente y su texto seleccionado, fuera del main actor [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Accessibility/AXManager.swift#L56-L66@93dc960]
- SelectedTextKit cae a `AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange` cuando el atributo nativo viene vacio (texto web) [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Accessibility/AXManager.swift#L93-L116@93dc960]
- SelectedTextKit ofrece estrategias AppleScript, menu Copiar y atajo como respaldo; esas tocan el portapapeles o mandan teclas [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Core/TextStrategy.swift#L14-L19@93dc960]
- OpenInTerminal (Ji4n1ng, ~7k estrellas, push 2026-07-14): lee la seleccion de Finder por ScriptingBridge (`finder.selection`) y la convierte en URLs; es el camino de Automatizacion [ref:https://github.com/Ji4n1ng/OpenInTerminal/blob/537ac2a5ee69ae46d4948c9b259e067a0c179a5f/OpenInTerminalCore/FinderManager.swift#L59-L91@537ac2a]
- OpenInTerminal sin seleccion cae al target de la ventana de Finder del frente [ref:https://github.com/Ji4n1ng/OpenInTerminal/blob/537ac2a5ee69ae46d4948c9b259e067a0c179a5f/OpenInTerminalCore/FinderManager.swift#L74-L83@537ac2a]
- Hammerspoon (~16k estrellas, push 2026-07-08): un observer por pid con `AXObserverCreateWithInfoCallback` y su fuente en el run loop principal en modos comunes [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/axuielement/observer.m#L135-L168@23e387e]
- Hammerspoon expone `selectedChildrenChanged`, `selectedRowsChanged` y `selectedTextChanged` como notificaciones observables [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/axuielement/observer.m#L443-L453@23e387e]
- Hammerspoon crea todos sus event taps como `kCGEventTapOptionDefault` en la sesion y su error dice "Is Accessibility enabled?": el camino Accesibilidad, no Entrada [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/libeventtap.m#L217-L229@23e387e]
- No se encontro una implementacion abierta mantenida que lea la seleccion de Finder por `AXSelectedRows` + `AXURL`; la busqueda de codigo de GitHub no devolvio resultados para esa combinacion [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/axuielement/observer.m#L452@23e387e]

## 5. Opciones

Seleccion de Finder (D1):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. AX: observer en el pid de Finder (`AXSelectedRowsChanged` / `AXSelectedChildrenChanged` / `AXFocusedUIElementChanged`), al cambiar leer filas o hijos seleccionados y su `AXURL` | solo Accesibilidad, que Companion ya tiene; sin aviso nuevo; sigue los cambios sin sondear; coincide con los nombres que trae el helper de Incredible | estructura AX de Finder por vista y del escritorio sin documentar; `AXURL` en items de Finder sin verificar; costo con miles de filas | media | Recomendada, condicionada a la prueba de la seccion 9 |
| B. Apple Events: `tell application "Finder" to get selection` (NSAppleScript o ScriptingBridge) | semantica documentada de Finder, devuelve items con URL en todas las vistas y el escritorio | aviso de Automatizacion "Companion quiere controlar Finder"; sondeo (sin notificaciones); bloquea mientras Finder responde; cambiar la usage description | baja | Respaldo solo si A falla en una vista, y solo con decision de Karen |
| C. Leer `kAXDocumentAttribute` / titulo de la ventana | ya existe | da la carpeta, no la seleccion | baja | No |

Texto seleccionado (D2):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `kAXSelectedTextChangedNotification` en la app del frente + leer `kAXSelectedTextAttribute` del elemento con foco, respaldo `AXSelectedTextMarkerRange` | solo Accesibilidad; no toca portapapeles ni teclado | Electron/Terminal/PDF pueden no exponerlo; Chromium necesita `AXManualAccessibility` | media | Recomendada |
| B. Cmd+C sintetico y leer el portapapeles | funciona casi en todas partes | escribe el portapapeles de la usuaria, manda teclas, puede disparar acciones; contradice el modo pasivo | media | No |

Clics (D3):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `NSEvent.addGlobalMonitorForEvents([.leftMouseDown, .rightMouseDown])` + hit test AX en la posicion | doc de Apple: solo los eventos de teclado piden confianza; Companion ya usa un monitor global de raton; no se pone en el camino del evento | no ve clics en la propia app (falta un monitor local); hay que probar que no salta Entrada | baja | Recomendada |
| B. `CGEventTap` `.listenOnly` de raton | no bloquea el evento | WWDC19: un tap listen-only pide Entrada; justo el aviso que Karen no quiere | baja | No |
| C. `CGEventTap` `.defaultTap` de raton (como FN) | Accesibilidad, no Entrada | cada clic del sistema espera al callback; un callback lento lo deshabilita por timeout | media | No para clics pasivos |

## 6. Evidencia en contra

- Contra AX para Finder: Apple documenta los atributos pero no como los usa Finder en cada vista ni en el escritorio, y `AXURL` se describe para documentos o apps, no para items de un navegador de archivos [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxurlattribute.json@macOS26]
- Se acepta con una condicion: la spec no se firma hasta que la prueba de la seccion 9 (las cuatro vistas mas el escritorio con Accessibility Inspector) muestre una ruta por item; si falla en alguna, esa vista cae a la opcion B con decision de Karen [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedchildrenattribute.json@macOS26]
- Contra Apple Events: es el unico camino documentado y estable para la seleccion de Finder, y un referente maduro lo usa [ref:https://github.com/Ji4n1ng/OpenInTerminal/blob/537ac2a5ee69ae46d4948c9b259e067a0c179a5f/OpenInTerminalCore/FinderManager.swift#L59-L91@537ac2a]
- Se rechaza como primario porque agrega un aviso de Automatizacion y obliga a sondear, y la usage description actual no lo cubre [repo:scripts/bundle.sh:91]
- Contra el monitor global para clics: Quinn dice que el monitor global pide Accesibilidad "por razones historicas"; si Apple moviera los monitores globales a Entrada en una version futura, el supuesto se rompe [doc:https://developer.apple.com/forums/thread/707680@2022-06]
- Se acepta porque Companion ya exige Accesibilidad y la prueba empirica del checklist (sin aviso de Entrada, `CGPreflightListenEventAccess` en false mientras llegan clics) detecta el cambio en cada version de macOS [repo:Sources/CompanionServices/Permissions/InputMonitoringPermission.swift:13]
- Contra replicar "exactamente" a Incredible: los extractos no muestran con que mecanismo Incredible lee la seleccion ni los clics, solo los kinds que pinta; copiar el mecanismo es una inferencia [repo:Sources/CompanionUI/Voice/PassivePreference.swift:4]

## 7. Ejemplares y anti-ejemplos

- Bien: leer la seleccion fuera del main actor sobre un pid fijo, y caer a text markers solo si el atributo nativo viene vacio [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Accessibility/AXManager.swift#L68-L90@93dc960]
- Anti-ejemplo de privacidad: la misma libreria escribe en el log el texto seleccionado completo (`logInfo("Selected text via AX: ...")`); Companion nunca debe registrar contenido [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Accessibility/AXManager.swift#L51@93dc960]
- Bien: un observer por pid, fuente en el run loop en modos comunes, y liberar el anterior antes de crear el nuevo [repo:Sources/CompanionServices/Accessibility/AXChangeWatcher.swift:12]
- Bien: timeout de mensajeria corto por llamada AX para que una app colgada no congele el sensor [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:111]
- Bien: hit test en la posicion del clic que descarta el propio pid y acota el texto a 120 caracteres [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:118]
- Anti-ejemplo para el modo pasivo: un tap `.listenOnly` global, que es el que dispara Entrada [ref:https://github.com/tisfeng/Easydict/blob/cfda6e2f43741a3210a290e422846f1d83742d38/Easydict/Swift/Utility/EventMonitor/Engine/EventTapMonitor.swift#L65-L72@cfda6e2]
- Anti-ejemplo para el modo pasivo: estrategias de copia sintetica que tocan el portapapeles de la usuaria [ref:https://github.com/tisfeng/SelectedTextKit/blob/93dc960a5ef8d52de98af41d4abd7a89576d091c/Sources/SelectedTextKit/Core/TextStrategy.swift#L14-L19@93dc960]
- Bien: saltar campos seguros antes de leer texto [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:29]

## 8. Trampas

- El elemento system-wide no admite notificaciones: hay que crear un observer por app (Finder y la app del frente) y rehacerlo al cambiar de app [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462089-axobserveraddnotification.json@macOS26]
- El `AXChangeWatcher` actual tiene un solo slot e ignora notificaciones fuera de una llamada de manos; reutilizarlo para el stream pasivo le quitaria el observer a las manos, o al reves [repo:Sources/CompanionServices/Accessibility/AXChangeWatcher.swift:8]
- `kAXSelectedTextAttribute` solo es obligatorio en texto editable: en texto no editable (web, PDF, Terminal) puede faltar aunque se vea la seleccion [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedtextattribute.json@macOS26]
- En Chromium y Electron el arbol AX esta apagado hasta que alguien pone `AXManualAccessibility`; Companion ya lo hace al cebar, pero el sensor pasivo tambien lo necesita para la app del frente [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:228]
- Finder en segundo plano: con AX hay que leer la ventana de Finder con foco o principal del pid de Finder, no el elemento con foco del sistema, que pertenece a otra app [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedrowsattribute.json@macOS26]
- Seleccion grande: `AXSelectedRows` devuelve el arreglo completo; leer `AXURL` de miles de items es una ida y vuelta por item contra Finder, asi que hay que acotar (primeros N mas el total) [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxselectedrowsattribute.json@macOS26]
- Un `CGEventTap` `.listenOnly` pide Entrada; un `.defaultTap` pide Accesibilidad pero pone a Companion en el camino sincronico de cada clic [doc:https://developer.apple.com/videos/play/wwdc2019/701/@2019]
- El monitor global no recibe eventos dirigidos a la propia app: los clics sobre la isla necesitan un monitor local, como ya hace `IslandChrome` [repo:Sources/CompanionUI/Island/IslandChrome.swift:343]
- Sandbox: la Accesibilidad no esta disponible para apps en sandbox; Companion no esta en sandbox y no debe estarlo para esta spec [doc:https://developer.apple.com/forums/thread/707680@2022-06]
- Hardened runtime: los Apple Events a Finder (opcion B) solo funcionan en release con el entitlement, que ya esta; el bundle de desarrollo se firma sin runtime, asi que una prueba en dev no prueba release [repo:scripts/release.sh:53]
- La `NSAppleEventsUsageDescription` es obligatoria y hoy solo menciona hojas de calculo; si se usa la opcion B el aviso de Automatizacion mostraria un motivo falso [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.json@macOS26]
- Identidad: un build ad hoc pierde las concesiones de TCC, asi que la prueba de "sin aviso de Entrada" solo vale firmada con Companion Dev o Developer ID [repo:scripts/bundle.sh:104]
- Contexto swift test: la confianza AX es la de la terminal que lanza el test, y en CI no hay concesiones; los tests del sensor deben inyectar lectores falsos, no llamar AX real [repo:Tests/CompanionServicesTests/LiveScreenTests.swift:12]
- Contexto swift test: sin `NSApp` no hay ventanas propias; el filtro de clics sobre Companion debe tolerarlo [repo:Sources/CompanionServices/Accessibility/PointerSampler.swift:98]
- Contexto app de desarrollo y release: el monitor global y el observer AX funcionan igual en ambos (no dependen de entitlements), pero el pedido de Accesibilidad se ata a la firma de cada uno [repo:scripts/bundle.sh:114]
- Privacidad: el precedente del repo es nombres en vez de rutas para archivos del portapapeles, e Incredible muestra la ruta como detalle; la spec tiene que elegir y nunca escribir rutas ni texto en `Companion.log` [repo:Sources/CompanionServices/Perception/ContextSensors.swift:409]

## 9. Incertidumbre

- ASSUMPTION: el monitor global de NSEvent con mascara solo de raton no dispara el aviso de Entrada en macOS 26 con Accesibilidad concedida. prueba: build firmado, `tccutil reset ListenEvent com.karen.companion`, arrancar, hacer 10 clics en otras apps, confirmar que llegan los eventos, que no aparece ningun dialogo y que `CGPreflightListenEventAccess()` sigue en false y Companion no figura en Ajustes > Privacidad > Entrada.
- ASSUMPTION: el mismo monitor sin Accesibilidad tampoco dispara Entrada (solo deja de ver teclado). prueba: repetir lo anterior con `tccutil reset Accessibility com.karen.companion`.
- ASSUMPTION: Finder expone `AXSelectedRows` en lista y columnas y `AXSelectedChildren` en iconos y galeria, y cada item seleccionado tiene `AXURL` file. prueba: Accessibility Inspector sobre Finder en las cuatro vistas, con 1, 3 y 0 items seleccionados, anotando rol del contenedor, atributo de seleccion y `AXURL`/`AXFilename` de cada item.
- ASSUMPTION: los iconos del escritorio son una ventana AX de Finder con la misma seleccion leible. prueba: Accessibility Inspector sobre el escritorio con dos iconos seleccionados y sin ventanas de Finder abiertas.
- ASSUMPTION: Finder emite `AXSelectedRowsChanged`/`AXSelectedChildrenChanged` aunque su ventana este en segundo plano. prueba: observer de prueba en el pid de Finder, cambiar la seleccion con Finder en segundo plano por script de UI y contar notificaciones.
- ASSUMPTION: leer 5000 items seleccionados por AX tarda mas que el presupuesto de un evento pasivo. prueba: carpeta con 5000 archivos, Cmd+A, medir el tiempo de `AXSelectedRows` mas `AXURL` de los primeros 50 y de todos.
- ASSUMPTION: Terminal, VS Code y Slack no exponen `kAXSelectedTextAttribute` pero si text markers o nada. prueba: seleccionar texto en cada una y leer ambos atributos con Accessibility Inspector, con y sin `AXManualAccessibility`.
- ASSUMPTION: Incredible lee la seleccion y los clics solo con Accesibilidad (los nombres `AXSelected*Changed` del helper y la falta de cadenas de taps sugieren eso, pero los extractos son parciales). prueba: con Incredible instalado y sin tocar el .app, mirar en Ajustes > Privacidad si Incredible figura en Entrada y en Automatizacion > Finder despues de usarlo con archivos seleccionados.
- Firmado por Karen: solo mientras FN esta pulsada, como Incredible.
- Firmado por Karen: sin respaldo de Automatizacion por ahora; se decide tras la prueba manual de la seccion 9.
- Firmado por Karen: ruta completa, como Incredible.
- Firmado por Karen: b2b-2 cubre clics, seleccion y rutas; copied y dialog_opened van despues (Incredible es el piso). Privacidad: se capturan rutas y texto seleccionado, nunca su contenido en logs.

## 10. Checklist de estandar

- [ ] La seleccion de Finder se lee solo con Accesibilidad (observer en el pid de Finder), sin Apple Events, salvo decision escrita de Karen para una vista concreta
- [ ] Prueba manual firmada: tras `tccutil reset ListenEvent`, usar los tres sensores no muestra aviso de Entrada, Companion no aparece en esa lista y `CGPreflightListenEventAccess()` sigue en false
- [ ] Prueba manual firmada: usar los tres sensores no muestra aviso de Automatizacion (Companion no aparece bajo Finder en Automatizacion)
- [ ] Los clics se observan con `NSEvent.addGlobalMonitorForEvents` de raton mas un monitor local; ningun `CGEventTap` nuevo
- [ ] Cada clic produce app, rol/etiqueta acotada del elemento y posicion, y descarta los clics sobre ventanas propias
- [ ] El texto seleccionado se lee de `kAXSelectedTextAttribute` del elemento con foco, con respaldo de text markers; nunca Cmd+C sintetico ni lectura de portapapeles para obtenerlo
- [ ] Los campos seguros (`AXSecureTextField`) nunca se leen
- [ ] La seleccion de Finder funciona en lista, columnas, iconos, galeria y escritorio, o la spec nombra la vista que no y que hace en ella
- [ ] La seleccion grande se acota (primeros N items mas el total) y cada llamada AX tiene timeout de mensajeria
- [ ] El sensor pasivo usa su propio observer, no el slot de `AXChangeWatcher` de las manos
- [ ] Ningun log contiene texto seleccionado, rutas ni etiquetas de elementos; solo conteos y kinds
- [ ] Los tests del sensor inyectan lectores falsos y pasan en CI sin permisos TCC

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute, kAXURLAttribute, kAXFilenameAttribute, kAXSelectedTextAttribute | Apple | macOS 26 SDK docs | 2026-10-03 | high |
| 2 | kAXSelectedTextChanged, kAXSelectedChildrenChanged, kAXSelectedRowsChanged notifications | Apple | macOS 26 SDK docs | 2026-10-03 | high |
| 3 | AXObserverAddNotification | Apple | macOS 26 SDK docs | 2026-10-03 | high |
| 4 | NSEvent.addGlobalMonitorForEvents | Apple | macOS 26 SDK docs | 2026-10-03 | high |
| 5 | CGEvent.tapCreate, CGPreflightListenEventAccess | Apple | macOS 26 SDK docs (texto antiguo) | 2026-10-03 | medium |
| 6 | WWDC19 701 Advances in macOS Security | Apple | 2019 | 2026-10-03 | high |
| 7 | Foro 707680, respuesta de Quinn (DTS) | Apple Developer Forums | 2022-06 | 2026-10-03 | high |
| 8 | Foro 122492 (desarrolladores, sin Apple) | Apple Developer Forums | 2019-2021 | 2026-10-03 | low |
| 9 | Apple Events entitlement, NSAppleEventsUsageDescription | Apple | macOS 26 SDK docs | 2026-10-03 | high |
| 10 | Easydict | tisfeng | cfda6e2 | 2026-10-03 | medium |
| 11 | SelectedTextKit | tisfeng | 93dc960 | 2026-10-03 | medium |
| 12 | OpenInTerminal | Ji4n1ng | 537ac2a | 2026-10-03 | medium |
| 13 | Hammerspoon | Hammerspoon | 23e387e | 2026-10-03 | high |
| 14 | Analisis estatico local de Incredible (extractos solo en la referencia local) | analisis propio | 0.2.36 | 2026-10-03 | medium |
