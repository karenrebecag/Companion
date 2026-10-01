# Reference Brief: como un agente externo hace QA de Companion sobre Companion, sin inventar caminos y sin abrir la puerta de las aprobaciones

Slug: self-qa-puente | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Respuestas de Karen (2026-10-01) a las preguntas abiertas: (1) D2 y D3 se activan con el mismo toggle "Prestar las manos a otros agentes", sin ajuste aparte: un producto que conecta Claude al computador debe ser una sola configuracion; (2) las tools de inspeccion devuelven probablemente solo metadatos, a auditar con un research corto (brief self-qa-inspeccion-datos); (3) D7 va a su propio brief (brief self-qa-clic-fuera-de-banda). Decision final (misma fecha): D1 queda como recomienda el brief (el puente no hace clic, teclas ni texto sobre Companion), no por prohibicion sino porque con buena UX no hace falta: un pedido de cambiar un ajuste lleva ese control a la isla y el usuario lo cambia. D2-D6 firmadas como recomienda el brief. Nueva D8 "ajuste en la isla": cualquier pedido de cambiar un ajuste (voz, texto o agente) abre ese control en el notch para que el usuario lo cambie; funcionalidad aparte con su propio brief (ajuste-en-la-isla). Karen: "si. vamos con todo eso". [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Origen: QA en vivo del 2026-10-01. El orquestador intento probar Companion de punta a punta por su propio puente MCP y toda accion sobre Companion devolvio `self_in_front`. Improviso UI scripting con System Events y vio un arbol de Ajustes casi vacio. Posicion de Karen, segun el pedido del orquestador: "Companion deberia suministrar todo lo necesario como para que tu no tengas que buscar o inventar soluciones."

Preguntas: Q1 por que existe el rechazo y que superficie minima tiene que seguir rechazada; Q2 como lo resuelven otros productos y frameworks; Q3 opciones (a) denylist en el puente, (b) tools de inspeccion, (c) canal solo en debug, (d) arreglar el arbol AX, y combinaciones; Q4 cambio de idioma verificable; Q5 que evidencia necesita el agente como oraculo.

Decisiones para Karen (recomendacion de este brief entre parentesis; la decision es de ella):

- D1. Clics, teclas y texto del puente sobre las ventanas de Companion: se siguen rechazando todos, o se abren con una denylist. (Recomendado: se siguen rechazando. Ver la seccion 6: la hoja de aprobacion vive en la misma ventana, "Permitir" no cae en ninguna familia destructiva, y el texto tecleado en el chat cuenta como palabras de la usuaria.)
- D2. Lectura de las ventanas propias por el puente (`look` y `read_focused` sobre Companion, nunca `click`): se habilita, solo dentro de una sesion de QA, con los campos seguros redactados. (Recomendado: si, como lectura pura.)
- D3. Un juego de tools `companion_*` de inspeccion y navegacion acotada, servido por el puente con su propia allowlist: estado estructurado, pantalla actual, valores de ajustes no secretos, estado de la isla, ultimas N lineas del log, y solo tres escrituras reversibles (abrir una pagina de Ajustes, cerrarla, cambiar idioma). (Recomendado: si; es la opcion (b) y el oraculo principal.)
- D4. Identificadores AX (`accessibilityIdentifier`) estables en todo control interactivo, con un id obligatorio en el inicializador de los controles del design system para que el compilador lo exija. (Recomendado: si; es la opcion (d), sirve a VoiceOver y a cualquier cliente AX.)
- D5. Canal de automatizacion solo en builds debug. (Recomendado: no. Karen hace QA sobre el release instalado, y el debug no esta instalado en esta Mac.)
- D6. Captura de las ventanas propias: render en proceso de la ventana de Companion devuelto al agente local, nunca enviado al modelo de vision de la nube. (Recomendado: si, detras de D3, y solo como evidencia visual complementaria.)
- D7. El agujero que el puente no cierra: un cliente AX fuera de banda con su propio permiso (el `osascript` que uso el orquestador) puede pulsar la hoja de aprobacion igual. (Recomendado: abrir un brief aparte; no se resuelve dentro de este cambio.)

Restricciones de seguridad que este cambio no puede relajar (se repiten como criterios en la seccion 10):

- R1. La hoja de aprobacion la contesta solo un clic de la usuaria; el modelo o un agente jamas contesta su propia pregunta de permiso.
- R2. Toda llamada del puente corre con `said: ""`; ningun camino puede hacer pasar texto del agente por el chat, donde cuenta como palabras de la usuaria.
- R3. Grants, destinos de confianza y modos de autorizacion los escribe solo la usuaria en Ajustes; el puente nunca los escribe.
- R4. Nunca se teclea en Companion ni se lee un campo seguro.
- R5. `BridgeScope` sigue siendo una allowlist: cada tool nueva entra por una edicion deliberada con test.
- R6. Los logs nunca llevan argumentos ni `output` de las tools.
- R7. "Prestar las manos" sigue naciendo apagado, y la primera llamada de cada conexion sigue pidiendo la hoja.

## 2. Estado actual

- `readyHands` devuelve nil si las manos no tienen permiso de Accesibilidad o si Companion esta al frente; sin manos listas el puente no ofrece ni ejecuta ninguna tool de manos ni de vista [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:63]
- `unavailability(for:)` devuelve `self_in_front` cuando la tool existe, tiene respaldo, hay permiso y Companion esta al frente [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:107]
- El codigo `self_in_front` se define en el protocolo del puente con la razon "there is no other app to act on" [repo:Sources/CompanionCore/Bridge/BridgeProtocol.swift:189]
- El puente responde a ese codigo con "Companion is in front; bring the app to act on to the front" [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:251]
- La wave 20b D4 solo convirtio el `unknown_tool` previo en un codigo explicito; no creo el rechazo [repo:docs/specs/wave-20b-qa-en-vivo.md:44]
- El rechazo nacio en la wave 15g como hallazgo M de revision: el chat escrito anunciaba manos con Companion delante, y `selfInFront` las oculto (spec borrada en d13a9f1; se lee con `git show d13a9f1^:docs/specs/wave-15g-manos.md`) [repo:docs/specs/wave-15g-manos.md:170]
- El criterio de done de 15g ya decia "nunca se escribe en un campo seguro ni en Companion" (misma spec borrada) [repo:docs/specs/wave-15g-manos.md:12]
- La razon documentada en el codigo es funcional, no de seguridad: con el chat escrito delante, el campo que las manos necesitan no es el que esta delante [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:18]
- El test que fija el rechazo es `testTheHandsAreHiddenWhileCompanionIsInFront` [repo:Tests/CompanionServicesTests/HandsPolicyTests.swift:133]
- El rechazo no es una sola linea: el objetivo de las manos es `lastOtherPID`, que nunca es Companion [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:6]
- `FrontmostAppSensor` marca `ownInFront` por bundle id y no guarda nunca a Companion como "la otra app" [repo:Sources/CompanionServices/Perception/ContextSensors.swift:275]
- `runHands` rechaza con `no_target` si el pid objetivo es el propio [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:227]
- `AXScreen.actable` rechaza el pid propio y el bundle id propio antes de leer o pulsar [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:347]
- `AXTextInjector.actable` repite el mismo doble cierre, con el comentario "the one process the hands must never touch is the one running them" [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:119]
- La captura de `see` devuelve `.nothing` cuando el objetivo es el pid propio [repo:Sources/CompanionCore/Perception/ScreenSeePrompt.swift:93]
- La captura sin objetivo excluye la app propia del display con `excludingApplications` [repo:Sources/CompanionServices/Perception/ScreenCapture.swift:61]
- `REFERENCE.md` ya fija para el dictado que la sonda AX mira "la app de delante (nunca Companion)" [repo:docs/REFERENCE.md:346]
- Ajustes no es una ventana aparte: es un overlay dentro de la unica ventana principal [repo:Sources/CompanionUI/Window/CompanionRootView.swift:182]
- La hoja de aprobacion tambien es un overlay de esa misma ventana principal [repo:Sources/CompanionUI/Window/CompanionRootView.swift:277]
- La hoja tiene un solo anfitrion a la vez: la ventana principal mientras es key y la isla en otro caso [repo:Sources/CompanionApp/CompanionMainWindow.swift:131]
- Toda la ventana principal es un unico `NSHostingView` instalado como `contentView` [repo:Sources/CompanionApp/CompanionMainWindow.swift:125]
- Los botones de la hoja son `approval.deny` y `approval.allow` [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:86]
- En espanol esos botones dicen "No permitir" y "Permitir" [repo:Sources/CompanionUI/es.lproj/Localizable.strings:171]
- Las familias destructivas que hacen pedir hoja a un `click` son borrar, pagar, suscribir, enviar, cerrar sesion y publicar; "permitir" o "allow" no estan [repo:Sources/CompanionCore/Tools/HandsWords.swift:23]
- `clickVerdict` actua sin hoja si la etiqueta tiene texto y no cae en una familia destructiva [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:133]
- En el chat escrito, el texto que se envia se convierte en `said`, las palabras de la usuaria que relajan la puerta de las manos [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:16]
- El puente, en cambio, llama la puerta con `said: ""` [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:162]
- La spec del puente justifica `said: ""` en que "el agente no es la usuaria" y la hoja es el sustituto de sus palabras [repo:docs/specs/wave-17-puente-mcp.md:59]
- La wave 20c resume su endurecimiento en una idea: donde el propio modelo puede contestar la pregunta de permiso, la respuesta no vale [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:9]
- La wave 20d fija que el modelo nunca contesta su propia pregunta de permiso en las bandas confirmar y critica [repo:docs/specs/wave-20d-modos-autorizacion.md:20]
- La wave 20d fija que grants y destinos de confianza se editan solo en Ajustes y el modelo jamas los escribe [repo:docs/specs/wave-20d-modos-autorizacion.md:90]
- "Prestar las manos" se guarda en UserDefaults y nace apagado [repo:Sources/CompanionUI/Settings/UserPreferences.swift:319]
- El switch de "Prestar las manos" vive en la pagina de Privacidad de Ajustes [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:52]
- `BridgeScope` es una allowlist de tools del puente; una tool nueva queda fuera hasta que se nombra ahi [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:76]
- Los entregables quedan solo locales porque la memoria de aprobaciones es de todo el proceso [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:90]
- `Log.bridge` nunca registra argumentos ni `output`, solo nombre, resultado, objetivo y conteo de caracteres [repo:Sources/CompanionServices/Platform/Log.swift:46]
- El log de la app se escribe en `~/Library/Logs` con el nombre de la identidad del producto [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:39]
- El idioma se guarda en UserDefaults bajo `companion.language`; nil significa seguir al sistema [repo:Sources/CompanionUI/Settings/UserPreferences.swift:11]
- El cambio de idioma en vivo depende de que Ajustes publique `companionLanguageDidChange` [repo:Sources/CompanionUI/Settings/SettingsView.swift:150]
- Ya existe una navegacion estructurada a una pagina de Ajustes: una notificacion `companionOpenSettings` con la pagina como objeto [repo:Sources/CompanionApp/CompanionMainWindow.swift:209]
- Las paginas de Ajustes tienen un `rawValue` que es un identificador estable que no sigue al idioma [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:5]
- Un test ya comprueba que los dos catalogos cubren las mismas claves [repo:Tests/CompanionUITests/LocalizedTests.swift:22]
- Ese test no ve los literales fuera del catalogo: el aviso de actualizacion esta escrito en espanol en el codigo [repo:Sources/CompanionApp/CompanionMainWindow.swift:93]
- El design system ya expone controles propios a AX con cuidado: el switch usa `accessibilityRepresentation` con un `Toggle` real [repo:Sources/CompanionUI/DesignSystem/IncredibleControls.swift:94]
- Los controles se nombran con `accessibilityLabel` (46 usos en CompanionUI); ningun archivo de Sources usa `accessibilityIdentifier` (grep de esta corrida) [repo:Sources/CompanionUI/DesignSystem/Dropdown.swift:233]
- Los campos de claves usan `SecureField`, que AX expone como campo seguro [repo:Sources/CompanionUI/DesignSystem/Controls.swift:189]
- `AXScreen` ya pulsa con `kAXPressAction`, que es como pulsaria cualquier otro cliente AX [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:241]
- `AXScreen` activa `AXManualAccessibility` antes del primer escaneo de cada app, porque algunos arboles solo se construyen para un cliente que lo pide [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:212]
- Incredible, segun el analisis estatico de 20b, excluye sus ventanas de la captura (`capture_exclusion`) y no se le encontro un rechazo explicito de actuar sobre si mismo [repo:docs/specs/wave-20b-qa-en-vivo.md:25]
- Re-verificado en esta corrida sobre Incredible 0.2.36: el binario contiene `crates/desktop-host-support/src/capture_exclusion_macos.rs`, `setSharingType:` y el aviso "capture exclusion NOT applied (Incredible's own windows may appear in the recording)"; un prompt dice "Skip utilities and background tools: ... and Incredible itself"; no hay `accessibilityIdentifier` ni un servidor de pruebas (detalle en la seccion 11, fuente 17) [repo:docs/research/evidence/incredible-0.2.36-strings-2026-10-01.txt:1]
- La app que Karen usa es el release instalado en `/Applications`; no hay segunda copia [repo:CLAUDE.md:50]
- `bundle.sh` empaqueta debug por defecto y solo el release se instala en `/Applications` [repo:scripts/bundle.sh:8]
- El shim MCP vive en un repo hermano, `companion-mcp` [repo:docs/specs/wave-17-puente-mcp.md:4]
- La plataforma minima es macOS 26 [repo:Package.swift:9]
Contextos: app release instalada en /Applications (com.karen.companion, la que Karen prueba); bundle debug de bundle.sh (identidad Companion Next, no instalado en esta Mac); `swift test` local y en CI via scripts/gates.sh (sin permiso de Accesibilidad, sin ventana real); cliente MCP externo (Claude Code por el shim de companion-mcp, otro proceso del mismo uid); clientes AX fuera de banda con su propio permiso (osascript/System Events, Accessibility Inspector); VoiceOver.

## 3. Fuentes primarias

- Apple, SwiftUI `accessibilityIdentifier(_:)`: "Use this value for testing. It isn't visible to the user."; disponible desde macOS 11 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilityidentifier(_:).json@macOS26-sdk-docs]
- Apple, AppKit: `accessibilityIdentifier()` es un metodo requerido de `NSAccessibilityProtocol` que devuelve la identidad del elemento [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsaccessibilityprotocol/accessibilityidentifier().json@macOS26-sdk-docs]
- Apple, AppKit: `NSAccessibility.Attribute.identifier` (`NSAccessibilityIdentifierAttribute`) es "The identity of the element", el atributo que lee un cliente AX de otro proceso [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsaccessibility-swift.struct/attribute/identifier.json@macOS26-sdk-docs]
- Apple, XCUIAutomation: `XCUIElementAttributes.identifier` es "The element's accessibility identifier", la misma propiedad que fija la app [doc:https://developer.apple.com/tutorials/data/documentation/xcuiautomation/xcuielementattributes/identifier.json@macOS26-sdk-docs]
- Apple, `AXUIElementCreateApplication(_:)` crea el elemento de nivel superior de la app con ese pid; es la puerta de entrada de todo cliente AX externo [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1459374-axuielementcreateapplication.json@macOS26-sdk-docs]
- Apple, `XCUIApplication.launchArguments`: los argumentos que recibe la app al lanzarse, la via con la que un test fija estado de arranque [doc:https://developer.apple.com/tutorials/data/documentation/xcuiautomation/xcuiapplication/launcharguments.json@macOS26-sdk-docs]
- Apple, `performAccessibilityAudit(for:_:)` de `XCUIApplication` existe en macOS 14 o posterior [doc:https://developer.apple.com/tutorials/data/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:).json@macOS26-sdk-docs]
- Apple, PackageDescription: los tipos de target son regular, binary, system, test, executable, plugin y macro; no hay un tipo de target de UI test [doc:https://developer.apple.com/tutorials/data/documentation/packagedescription/target/targettype.json@swift-tools-6.2]
- Apple, `UserDefaults.argumentDomain`: los valores pasados por linea de comandos van a un dominio volatil que se reinicia en cada lanzamiento y "override most other domains, including your app-specific settings" [doc:https://developer.apple.com/tutorials/data/documentation/foundation/userdefaults/argumentdomain.json@macOS26-sdk-docs]
- Apple, Xcode: para probar una localizacion se elige App Language en el esquema de Run, y cambiar el idioma del sistema cambia todo el sistema, no solo la app [doc:https://developer.apple.com/tutorials/data/documentation/xcode/testing-localizations-when-running-your-app.json@macOS26-sdk-docs]
- Apple, `NSWindow.SharingType.none`: "A legacy constant that macOS no longer uses", y "Don't use this value to hide or omit content from being captured" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/sharingtype-swift.enum/none.json@macOS26-sdk-docs]
- Apple, `SCContentFilter(display:including:exceptingWindows:)` captura solo las ventanas de las apps indicadas, con excepciones por ventana [doc:https://developer.apple.com/tutorials/data/documentation/screencapturekit/sccontentfilter/init(display:including:exceptingwindows:).json@macOS26-sdk-docs]
- Apple, `NSView.cacheDisplay(in:to:)` dibuja un area de la vista y sus descendientes en un bitmap, dentro del proceso [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsview/cachedisplay(in:to:).json@macOS26-sdk-docs]
- MCP 2025-06-18, Tools: "there SHOULD always be a human in the loop with the ability to deny tool invocations" [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- MCP 2025-06-18, Tools: los clientes "MUST consider tool annotations to be untrusted unless they come from trusted servers" [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- MCP 2025-06-18, Tools: los servidores MUST validar entradas, aplicar control de acceso, limitar la tasa y sanear salidas; un resultado puede llevar `structuredContent` validable con `outputSchema` [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- Playwright, Locators: se priorizan los localizadores por rol, "the closest way to how users and assistive technology perceive the page" [doc:https://playwright.dev/docs/locators@current]
- Playwright, Locators: el test id es "the most resilient way of testing", pero "testing by test ids is not user facing" [doc:https://playwright.dev/docs/locators@current]
- Electron, Fuses: el fuse `nodeCliInspect` decide si se respetan `--inspect` y SIGUSR1, y "Most apps can safely disable this fuse" [doc:https://www.electronjs.org/docs/latest/tutorial/fuses@latest]
- Electron, Fuses: apagar `runAsNode` evita "a subset of 'living off the land' attacks" en apps que no usan esa variable [doc:https://www.electronjs.org/docs/latest/tutorial/fuses@latest]

## 4. Implementaciones de referencia

- Appium Mac2 Driver (organizacion Appium, ultimo push 2026-10-01): maneja apps macOS ajenas desde otro proceso con XCTest; los localizadores `name`, `id` y `accessibility id` se resuelven por identificador AX de los descendientes [ref:https://github.com/appium/appium-mac2-driver/blob/71e46ec72e13d14553f261bb8a50da2ef32ce131/WebDriverAgentMac/WebDriverAgentLib/Commands/FBFindElementCommands.m#L127-L131@71e46ec72e13d14553f261bb8a50da2ef32ce131]
- CodeEdit (app macOS SwiftUI, ~23k estrellas, push 2026-08-18): un control propio se expone como boton con `accessibilityElement(children: .combine)`, rasgo, identificador, valor, etiqueta, pista y accion [ref:https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/ActivityViewer/Tasks/TaskDropDownView.swift#L39-L45@fa2aebd86373211c78626074b53ab75010767575]
- CodeEdit: sus UI tests lanzan la app con argumentos (`-ApplePersistenceIgnoreState YES`) para fijar el estado de arranque [ref:https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEditUITests/App.swift#L27-L32@fa2aebd86373211c78626074b53ab75010767575]
- CodeEdit: el UI test encuentra el control por su etiqueta visible ("Active Task"), lo que se rompe al cambiar de idioma [ref:https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEditUITests/Features/ActivityViewer/Tasks/TasksMenuUITests.swift#L32-L35@fa2aebd86373211c78626074b53ab75010767575]
- Flutter Driver (Google, framework de UI): la extension que deja manejar la app desde otro proceso cambia el comportamiento del framework, y "Applications intended for release should never include this method" [ref:https://github.com/flutter/flutter/blob/16bf22f3923acb85b1a780496c1f834b29ce6142/packages/flutter_driver/lib/src/extension/extension.dart#L97-L104@16bf22f3923acb85b1a780496c1f834b29ce6142]

## 5. Opciones

| Opcion | Pros | Contras | Tamano | Testabilidad | Recomendacion |
|---|---|---|---|---|---|
| (a) `look`/`click`/`menu`/`type_text` sobre Companion menos una denylist en el puente | Usa las tools que el agente ya conoce | La hoja de aprobacion, Privacidad, grants y modos viven en el mismo arbol; "Permitir" no es destructivo; `type_text` en el chat convierte el texto del agente en palabras de la usuaria; denylist = falla abierta ante cada control nuevo; hay que relajar cinco cierres independientes | media | Media: tests de runner con fakes, pero la denylist depende de identificadores que hoy no existen | No en su mitad de escritura |
| (a-lectura) `look` y `read_focused` sobre Companion, sin `click` ni teclas | El agente ve lo que hay en pantalla con la misma tool; riesgo bajo: leer no aprueba nada | Expone hilos y memoria al agente prestado (ya aprobado por hoja); campos seguros deben seguir fuera; depende de que el arbol AX sea legible | baja-media | Alta con fakes de `ScreenActing` | Si, detras de D2 |
| (b) Tools `companion_*` de inspeccion: estado estructurado, pantalla, ajustes no secretos, isla, log; tres escrituras reversibles | Oraculo estructurado y estable entre idiomas; allowlist propia; no toca la hoja ni el canal de palabras; mismo patron de allowlist que `BridgeScope` | Codigo nuevo que mantener sincronizado con la UI; no prueba que la UI real se vea bien | media | Alta: puro y con fakes en CompanionServicesTests | Si, oraculo principal |
| (c) Canal de automatizacion solo en debug | Patron de Flutter Driver; aislado del producto | Karen prueba el release instalado; el debug no esta instalado; un canal en release seria la superficie que Electron recomienda apagar; duplica el puente | baja-media | Media | No |
| (d) Identificadores AX estables y arbol accesible | Sirve a VoiceOver, a Accessibility Inspector, a la propia (a-lectura) y a cualquier cliente AX; es lo que XCUITest y Appium esperan | No da permiso al puente por si solo; mejora tambien el camino fuera de banda que pulsa la hoja (D7); SwiftPM no tiene target de UI test | media-alta (todos los controles) | Media: el compilador puede exigir el id; la lectura real necesita Accesibilidad | Si, en paralelo |
| (b)+(d)+(a-lectura) | Oraculo estructurado, arbol util para todos y lectura visual; ninguna escritura generica sobre Companion | Tres piezas; orden de entrega a decidir | alta en total, divisible | Alta en (b), media en (d) | Recomendada |

## 6. Evidencia en contra

- La razon mas fuerte contra la recomendacion: Karen pidio que el agente pruebe "de punta a punta", y sin `click` sobre Companion el agente no puede probar que un switch real cambia algo [KAREN:pedido del orquestador 2026-10-01]
- Se resuelve en parte: las tres escrituras de (b) cubren navegacion e idioma, y los demas ajustes los prueba la usuaria o un test unitario del modelo de Ajustes; se acepta que el agente no pulse controles de Companion [repo:docs/specs/wave-20d-modos-autorizacion.md:90]
- Contra el rechazo total: la razon escrita del rechazo en 15g era funcional (el campo delante no era el buscado), no una amenaza; leer Companion no repite ese problema [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:18]
- Se acepta y por eso D2 abre la lectura; pero las amenazas reales aparecieron despues, en 17, 20c y 20d, y mandan sobre la escritura [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:9]
- Amenaza real 1, auto-aprobacion: la hoja se pinta dentro de la ventana principal cuando es key, y un `click` del puente sobre "Permitir" no pide hoja porque no es destructivo [repo:Sources/CompanionApp/CompanionMainWindow.swift:131]
- Amenaza real 2, lavado de palabras: lo tecleado en el chat es `said`, y `said` relaja la puerta de `type_text`, Return y clics destructivos; un agente que escribe en el chat de Companion obtiene la autoridad de la usuaria [repo:Sources/CompanionUI/Chat/ChatViewModel+Turn.swift:16]
- Amenaza real 3, autoconfiguracion: grants, destinos de confianza y modos los fija la usuaria en Ajustes; clics del agente en Ajustes serian el modelo escribiendolos [repo:docs/specs/wave-20d-modos-autorizacion.md:22]
- Amenaza real 4, secretos: las claves de API viven en `SecureField`; la regla de campos seguros ya existe y no se relaja [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:157]
- Amenaza menor, bucle de retroalimentacion: el aura, el chip y la isla reaccionan a la actividad del puente, asi que `look` sobre Companion durante una sesion ve su propio efecto; se acepta como dato, no como riesgo [repo:docs/specs/wave-20b-qa-en-vivo.md:31]
- Contra (a) con denylist en vez de allowlist: el propio proyecto eligio allowlist para el puente porque una tool nueva quedaria expuesta por omision; la misma logica aplica a controles nuevos [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:76]
- Contra (b): duplica en estructura lo que la UI muestra, y la estructura puede decir "espanol" mientras un literal sale en espanol fijo; por eso (b) no reemplaza la lectura visual [repo:Sources/CompanionApp/CompanionMainWindow.swift:93]
- Contra (d): un arbol AX mejor hace mas facil que un cliente AX fuera de banda pulse "Permitir"; no se resuelve aqui y queda como D7 [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1459374-axuielementcreateapplication.json@macOS26-sdk-docs]
- Contra (c): es el camino que Flutter documenta, pero solo sirve a builds que no son el producto, y Karen prueba el producto [ref:https://github.com/flutter/flutter/blob/16bf22f3923acb85b1a780496c1f834b29ce6142/packages/flutter_driver/lib/src/extension/extension.dart#L97-L104@16bf22f3923acb85b1a780496c1f834b29ce6142]
- Contra (c) en release: un canal de depuracion en un binario distribuido es la superficie que Electron recomienda apagar con fuses [doc:https://www.electronjs.org/docs/latest/tutorial/fuses@latest]
- Contra copiar a Incredible: excluir las ventanas propias de la captura con `setSharingType` es lo que Apple marca como constante legacy que no debe usarse para ocultar contenido [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/sharingtype-swift.enum/none.json@macOS26-sdk-docs]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, control propio de SwiftUI expuesto a AX con identificador estable y etiqueta legible (CodeEdit) [ref:https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEdit/Features/ActivityViewer/Tasks/TaskDropDownView.swift#L39-L45@fa2aebd86373211c78626074b53ab75010767575]

```swift
.accessibilityElement(children: .combine)
.accessibilityAddTraits(.isButton)
.accessibilityIdentifier("TaskDropdown")
.accessibilityValue(taskManager.selectedTask?.name ?? "Create Tasks")
.accessibilityLabel("Active Task")
```

- Bien hecho, en el propio repo: el switch del design system ya se presenta a VoiceOver como un `Toggle` real; solo le falta el identificador [repo:Sources/CompanionUI/DesignSystem/IncredibleControls.swift:94]
- Bien hecho, en el propio repo: el puente es una allowlist con test que falla ante una tool sin decision; las tools `companion_*` deben seguir el mismo patron [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:76]
- Bien hecho, en el propio repo: las paginas de Ajustes ya tienen un identificador estable independiente del idioma, reutilizable como argumento de una tool de navegacion [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:5]
- Anti-ejemplo, buscar por etiqueta visible: el UI test de CodeEdit busca "Active Task", que deja de existir al cambiar el idioma; un QA bilingue tiene que localizar por identificador [ref:https://github.com/CodeEditApp/CodeEdit/blob/fa2aebd86373211c78626074b53ab75010767575/CodeEditUITests/Features/ActivityViewer/Tasks/TasksMenuUITests.swift#L32-L35@fa2aebd86373211c78626074b53ab75010767575]
- Anti-ejemplo, literal fuera del catalogo: el aviso de actualizacion ignora el idioma elegido y el test de catalogos no lo ve [repo:Sources/CompanionApp/CompanionMainWindow.swift:93]
- Anti-ejemplo, ocultar ventanas con la constante legacy de AppKit, que es lo que el binario de Incredible llama via `setSharingType` [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/sharingtype-swift.enum/none.json@macOS26-sdk-docs]

## 8. Trampas

- Una denylist por ventana no sirve: Ajustes y la hoja son overlays del mismo `NSHostingView`, asi que cualquier filtro tiene que ser por subarbol identificado, no por ventana [repo:Sources/CompanionApp/CompanionMainWindow.swift:125]
- La hoja cambia de anfitrion: en la ventana principal mientras es key y en la isla si no; un filtro que mire solo una de las dos deja la otra abierta [repo:Sources/CompanionApp/CompanionMainWindow.swift:131]
- La tecla Escape en la ventana principal contesta "no" a la hoja; un `press_key` sobre Companion podria denegar una peticion de la usuaria [repo:Sources/CompanionUI/Window/CompanionRootView.swift:138]
- Abrir la lectura exige tocar cinco cierres a la vez (`readyHands`, `lastOtherPID`, `runHands`, `AXScreen.actable`, `CaptureScope`); relajar uno sin los demas da errores confusos, y relajar `AXTextInjector.actable` abriria la escritura [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:119]
- Cambiar idioma escribiendo `companion.language` en UserDefaults desde fuera no repinta la app viva: el repintado depende de la notificacion que publica Ajustes [repo:Sources/CompanionUI/Settings/SettingsView.swift:150]
- Lanzar con `-companion.language es` pone el idioma en el dominio de argumentos, que manda sobre lo guardado; durante ese lanzamiento, cambiar el idioma en Ajustes parecera no funcionar [doc:https://developer.apple.com/tutorials/data/documentation/foundation/userdefaults/argumentdomain.json@macOS26-sdk-docs]
- XCUITest no entra en el paquete: SwiftPM no tiene target de UI test, asi que un `performAccessibilityAudit` exige un proyecto de Xcode aparte [doc:https://developer.apple.com/tutorials/data/documentation/packagedescription/target/targettype.json@swift-tools-6.2]
- Las ultimas lineas del log son datos no confiables: el log recibe texto del cable y de errores, saneado a una linea pero no a "no instrucciones" [repo:Sources/CompanionServices/Platform/Log.swift:52]
- Una captura de las ventanas propias por `see` saldria al modelo de vision de la nube con hilos y memoria; por eso hoy `see` sobre Companion es `.nothing`, y D6 propone devolverla solo al agente local [repo:Sources/CompanionCore/Perception/ScreenSeePrompt.swift:93]
- Las anotaciones MCP como `readOnlyHint` no protegen nada: el cliente las trata como no confiables; la proteccion de las tools `companion_*` tiene que vivir en Companion [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- El shim vive en `companion-mcp`: si fija la lista de tools en vez de reenviar la de Companion, (b) necesita un cambio alli tambien [repo:docs/specs/wave-17-puente-mcp.md:4]
- Contexto app release: es donde Karen prueba; todo lo recomendado (D2, D3, D4, D6) tiene que existir en release, detras de "Prestar las manos" y de la hoja de sesion [repo:CLAUDE.md:50]
- Contexto bundle debug: tiene otra identidad (Companion Next) y otro bundle id, asi que los cierres por bundle id se comportan igual pero con otro id; no esta instalado en esta Mac [repo:scripts/bundle.sh:8]
- Contexto `swift test` y CI: no hay permiso de Accesibilidad ni ventana; (b) y la logica de D2 se prueban con fakes, y nada de (d) se puede afirmar desde la suite [repo:Tests/CompanionServicesTests/HandsPolicyTests.swift:133]
- Contexto cliente MCP: cualquier proceso del mismo uid que lea el token puede conectar; la hoja de la primera llamada sigue siendo la barrera y no se toca [repo:docs/specs/wave-17-puente-mcp.md:56]
- Contexto clientes AX fuera de banda: no pasan por el puente, asi que ninguna decision de este brief los limita; es D7 [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:241]
- Contexto VoiceOver: (d) cambia lo que oye la usuaria; un identificador no se lee, pero `accessibilityElement(children: .combine)` si cambia la lectura y hay que revisarlo con VoiceOver [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilityidentifier(_:).json@macOS26-sdk-docs]

## 9. Incertidumbre

- ASSUMPTION: la medicion del orquestador (un AXGroup y tres botones de ventana, `entire contents` en 0) es un artefacto de la consulta y no un arbol vacio; ademas se contradice sola, porque un grupo y tres botones ya son cuatro elementos. prueba: con Ajustes abierto, inspeccionar la ventana principal con Accessibility Inspector y con el propio `AXScreen` contra el pid de Companion (en un build donde `actable` lo permita para la prueba) y contar los elementos con rol boton y switch
- ASSUMPTION: el arbol SwiftUI de la ventana principal se construye completo para un cliente AX externo sin activar `AXManualAccessibility`. prueba: la misma inspeccion, antes y despues de fijar ese atributo sobre el elemento de aplicacion de Companion
- ASSUMPTION: una issue publica de otro proyecto SwiftUI reporta etiquetas vacias por System Events en la app instalada (github.com/SpaceTrucker2196/henge/issues/1); no es fuente primaria y no se uso para decidir. prueba: la inspeccion de arriba sobre `IncredibleSwitch` y `AppButton`
- ASSUMPTION: macOS no le da a la app una forma soportada de distinguir un `AXPress` de otro proceso de un clic humano, asi que la hoja no puede rechazarlo por origen. prueba: pulsar "Permitir" con `kAXPressAction` desde otro proceso y registrar `NSApp.currentEvent` en la accion del boton
- ASSUMPTION: el shim de `companion-mcp` reenvia la lista de tools que devuelve `hello` y no la fija. prueba: leer su codigo de `tools/list`
- ASSUMPTION: `cacheDisplay(in:to:)` reproduce fielmente los materiales (`ultraThinMaterial`) del overlay de Ajustes. prueba: comparar un render en proceso con una captura de SCK que incluya solo la app propia
- [NEEDS CLARIFICATION: D2 y D3 se activan con el mismo "Prestar las manos" o con un ajuste aparte "Dejar que un agente inspeccione Companion", apagado por defecto?]
- [NEEDS CLARIFICATION: el contenido de hilos y memoria entra en las tools de inspeccion, o solo metadatos (cuantos hilos, titulos, estados)?]
- [NEEDS CLARIFICATION: D7 (cliente AX fuera de banda pulsando la hoja) se investiga en un brief propio ahora o queda anotado como riesgo aceptado?]

## 10. Checklist de estandar

- [ ] Con una sesion del puente abierta y Companion al frente, `click`, `menu`, `scroll`, `type_text`, `press_key` y `focus_window` sobre Companion siguen rechazados, con test.
- [ ] Ninguna tool del puente puede contestar la hoja de aprobacion, este en la ventana principal o en la isla; test que intenta `click` sobre "Permitir" por el puente y comprueba que no se resolvio nada.
- [ ] Ninguna tool del puente escribe en el chat de Companion; el `said` de toda llamada del puente sigue siendo "" (test existente sigue verde).
- [ ] Las tools `companion_*` estan en una allowlist propia con un test que falla ante una tool sin decision, igual que `BridgeAllowlistTests`.
- [ ] Las unicas escrituras de `companion_*` son abrir una pagina de Ajustes por su `SettingsTab.rawValue`, cerrar Ajustes y cambiar el idioma; ninguna toca grants, destinos, modos, "Prestar las manos" ni claves.
- [ ] Cambiar idioma por la tool publica `companionLanguageDidChange` y la app repinta sin relanzar; un test lo comprueba con el catalogo en los dos idiomas.
- [ ] La respuesta de inspeccion es `structuredContent` con `outputSchema`; nunca incluye valores de `SecureField` ni del Keychain.
- [ ] Las lineas de log devueltas se marcan como datos, con la misma frase fija que el shim usa para la pantalla.
- [ ] Si se adopta D2, `look` y `read_focused` sobre Companion son solo lectura, redactan campos seguros y no emiten ids pulsables.
- [ ] Si se adopta D4, `AppButton`, `IncredibleSwitch`, `Dropdown` y los campos del design system exigen un identificador en el inicializador; un control nuevo sin id no compila.
- [ ] Si se adopta D4, los identificadores son estables entre idiomas y no contienen texto visible.
- [ ] Si se adopta D6, la captura de ventanas propias vuelve solo al agente local y nunca se manda al modelo de vision.
- [ ] Ningun canal de automatizacion nuevo existe solo en debug ni se activa por variable de entorno en release.
- [ ] "Prestar las manos" sigue naciendo apagado y la primera llamada de cada conexion sigue pidiendo la hoja.
- [ ] security-reviewer revisa el cambio como frontera de confianza (puente, hoja, canal `said`, Ajustes).

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | View.accessibilityIdentifier(_:) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 2 | NSAccessibilityProtocol.accessibilityIdentifier(), NSAccessibility.Attribute.identifier | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 3 | XCUIElementAttributes.identifier, XCUIApplication.launchArguments, performAccessibilityAudit | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 4 | AXUIElementCreateApplication(_:) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 5 | Target.TargetType | Apple, PackageDescription | swift-tools 6.2 | 2026-10-01 | high |
| 6 | UserDefaults.argumentDomain | Apple Developer Documentation | SDK actual | 2026-10-01 | high (la sintaxis de ejemplo de la pagina es imprecisa) |
| 7 | Testing localizations when running your app | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 8 | NSWindow.SharingType.none | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 9 | SCContentFilter init(display:including:exceptingWindows:) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 10 | NSView.cacheDisplay(in:to:) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 11 | MCP Specification, Server Tools | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 12 | Locators | Playwright | sitio actual, sin version visible | 2026-10-01 | medium |
| 13 | Electron Fuses | Electron | latest | 2026-10-01 | high |
| 14 | appium-mac2-driver FBFindElementCommands.m | Appium | 71e46ec | 2026-10-01 | high |
| 15 | CodeEdit TaskDropDownView.swift, App.swift, TasksMenuUITests.swift | CodeEditApp | fa2aebd | 2026-10-01 | high |
| 16 | flutter_driver extension.dart | Flutter (Google) | 16bf22f | 2026-10-01 | high |
| 17 | Incredible.app 0.2.36, analisis estatico: grep de cadenas en `Contents/MacOS/incredible` y `accessibility-helper` (capture_exclusion, setSharingType, "Incredible itself"; sin accessibilityIdentifier ni servidor de pruebas) | Norditech, binario instalado | 0.2.36 | 2026-10-01 | medium (solo cadenas, sin logica) |
| 18 | Issue "app controls expose no accessibility labels to the AX API", SpaceTrucker2196/henge | GitHub, tercero | abierta | 2026-10-01 | low (pista, no evidencia) |
| 19 | Specs del repo: wave-15g (borrada en d13a9f1), 17, 20b, 20c, 20d | companion-next | d563ca3 (HEAD del worktree) | 2026-10-01 | high |
