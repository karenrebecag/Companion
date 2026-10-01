# Reference Brief: la hoja de aprobacion frente a un clic que no viene de la usuaria (cliente AX o eventos sintetizados fuera del puente)

Slug: self-qa-clic-fuera-de-banda | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Decision de Karen (2026-10-01): en lugar de D1+D2, D3: Touch ID (LocalAuthentication, .deviceOwnerAuthentication) en cada aprobacion critica sin importar el origen del clic, porque es el unico metodo documentado como garantia (Apple CVE-2017-7150, 1Password, KeePassXC) y no depende de que el pid del evento sea infalsificable; el clasificador por pid queda como mejora futura solo si el experimento de la seccion 9 lo valida. D4 y D7 firmadas. Incredible 0.2.36 no protege su dialogo (sin LocalAuthentication ni chequeo de pid en el binario). [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Origen: D7 del brief `self-qa-puente`. La hoja de aprobacion ("Permitir" / "No permitir", `ApprovalSheet`) es la frontera de confianza y R1 dice que solo la contesta un clic de la usuaria. El puente de Companion ya se niega a pulsarla, pero cualquier proceso con permiso de Accesibilidad (un `osascript` con System Events, otro agente, malware) puede pulsarla con `AXPress` o con eventos `CGEvent` sintetizados sin pasar por el puente. El 2026-10-01 el orquestador tuvo ese camino funcionando contra los menus de Companion, aunque no pulso la hoja.

Preguntas: Q1 si una app macOS puede distinguir un clic humano de una accion AX o de un `CGEvent` sintetizado; Q2 como lo resisten las UIs sensibles (SecurityAgent, gestores de contrasenas, 1Password, Secure Event Input); Q3 opciones (a) confirmacion que el canal AX no produce, (b) botones inertes para AX, (c) detectar y degradar, (d) Touch ID / LocalAuthentication, (e) aceptar y documentar, con el costo para VoiceOver; Q4 modelo de amenaza: si el atacante ya maneja Terminal, sirve de algo proteger la hoja.

Respuestas cortas (detalle y citas en 2-8):

- Q1. En parte. Un `AXPress` no llega como evento: AppKit llama `accessibilityPerformPress`, y lo esperable es que SwiftUI ejecute la accion del boton sin un evento nuevo que la acompane (sin verificar en vivo; ver la seccion 9). Un `CGEvent` sintetizado si llega como evento, y su campo `kCGEventSourceUnixProcessID` dice que proceso lo publico (0 para hardware); Chromium usa exactamente ese campo para negar un ajuste de seguridad a eventos de otro proceso. `kCGEventSourceStatePrivate` frente a `HIDSystemState` y `eventSourceUserData` los elige quien publica el evento, asi que no prueban nada por si solos. SwiftUI `Button` no expone el origen; hay que leer `NSApp.currentEvent` dentro de la accion y separar el camino AX con una accion de accesibilidad propia.
- Q2. Lo que resiste de verdad saca la prueba de presencia del proceso atacable: SecurityAgent corre en otro proceso y exige presencia fisica; Apple cerro el clic sintetico sobre el aviso del llavero (CVE-2017-7150) pidiendo la contrasena; 1Password usa el dialogo biometrico del sistema y aun asi declara como riesgo aceptado que una app con Accesibilidad puede saltarse su aviso. Secure Event Input solo impide interceptar teclas; no cubre raton, `AXPress` ni eventos publicados.
- Q3. Recomendado: (c)+(d). Detectar el origen en la hoja y, si "Permitir" no viene de raton o teclado fisicos, no aprobar: pedir Touch ID o contrasena con `LAContext` (politica `deviceOwnerAuthentication`). "No permitir" vale desde cualquier canal. VoiceOver conserva dos caminos: Tab y Espacio (teclado fisico) o la confirmacion del sistema, que es accesible. (a) y (b) no; (e) solo como residuo documentado.
- Q4. Proteger la hoja si sirve, pero como subida de costo y no como muro: un atacante con Accesibilidad ya puede hacer casi todo lo que la usuaria hace, pero la hoja reparte permisos que ese atacante quiza no tiene (las manos del puente y su vista, que captura con el permiso de Grabacion de pantalla de Companion), y el actor realista hoy es un agente bien intencionado que improvisa, no malware dirigido.

Decisiones para Karen (recomendacion entre parentesis; la decision es de ella):

- D1. Clasificar el origen de cada pulsacion de "Permitir" en las dos anfitrionas de la hoja (ventana principal e isla): humano solo si llega un evento de raton o teclado con `kCGEventSourceUnixProcessID` igual a 0; todo lo demas (un `AXPress`, un evento de otro proceso, un evento publicado por el propio Companion, ningun evento) es "no humano". (Recomendado: si; es la opcion (c) y no cambia nada para quien hace clic con el raton.)
- D2. Que hace un "Permitir" no humano: negar, volver a preguntar, o subir a una prueba de presencia del sistema. (Karen eligio Touch ID el 2026-10-01; ver la seccion 9. Recomendado y elegido: subir a `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` con la razon de la peticion; si falla o se cancela, la hoja sigue abierta sin respuesta y corre su plazo de 60 s. Nunca aprueba en silencio.)
- D3. Touch ID para toda aprobacion de banda critica, venga de donde venga el clic. (Recomendado: todavia no; empezar con D2, que solo cobra el paso extra cuando el origen no es humano. Reabrir si D1 muestra falsos positivos o si se quiere cubrir el caso del atacante que tambien publica eventos con pid 0. Ver la seccion 9.)
- D4. "No permitir" y Escape se aceptan desde cualquier canal, incluido `AXPress`. (Recomendado: si; negar es la direccion segura y quita cualquier costo de accesibilidad para negar.)
- D5. Opcion (a), confirmacion por mantener pulsado, codigo tecleado o codigo hablado. (Recomendado: no; un `CGEvent` sintetizado puede mantener pulsado y teclear, un cliente AX puede leer el codigo de la pantalla, y mantener pulsado excluye a quien pulsa por `AXPress`.)
- D6. Opcion (b), botones inertes para acciones AX. (Recomendado: no; no hay API documentada que bloquee `AXPress` de otro proceso sin bloquearlo tambien para VoiceOver, y dejaria a quien usa VoiceOver sin hoja.)
- D7. Documentar el riesgo residual en la seccion de seguridad de `docs/ARCHITECTURE.md`: un proceso con Accesibilidad que ademas conozca la contrasena o tenga a la usuaria tocando Touch ID por otra razon sigue pudiendo aprobar. (Recomendado: si, junto con D1 y D2; es la opcion (e) aplicada solo al residuo.)

## 2. Estado actual

- La hoja ofrece dos `AppButton`: "No permitir" llama `answer(false, remember)` y "Permitir" llama `answer(true, remember)` [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:82]
- El boton "Permitir" aplica `.keyboardShortcut(Self.allowShortcut)` [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:88]
- y `allowShortcut` vale `nil`, asi que "Permitir" no tiene atajo de teclado [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:173]
- "Permitir" sin atajo es una decision de seguridad ya escrita: "Allowing is a click, never a stray Return" (revision 16) [repo:Sources/CompanionUI/Voice/ApprovalSheet.swift:171]
- Un test fija que permitir no tiene atajo de teclado [repo:Tests/CompanionUITests/ApprovalSheetTests.swift:33]
- `AppButton` guarda la accion como `() -> Void`: el cierre no recibe evento ni origen [repo:Sources/CompanionUI/DesignSystem/Controls.swift:17]
- `AppButton` es un `Button(action:)` de SwiftUI con estilo propio, asi que hereda el `AXPress` estandar de un boton [repo:Sources/CompanionUI/DesignSystem/Controls.swift:41]
- La hoja tiene dos anfitrionas: un overlay de la ventana principal [repo:Sources/CompanionUI/Window/CompanionRootView.swift:277]
- y la isla, que antes de responder pasa por `ApprovalClickGuard` [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:97]
- `ApprovalClickGuard` ignora clics durante 0,6 s tras aparecer la hoja, contra un clic que ya iba en camino; no mira el origen del clic [repo:Sources/CompanionCore/Island/IslandState.swift:276]
- La ventana principal no pasa por `ApprovalClickGuard`: su cierre llama `chat.answerApproval` directo [repo:Sources/CompanionUI/Window/CompanionRootView.swift:278]
- Escape en la ventana principal contesta "no" a la hoja [repo:Sources/CompanionUI/Window/CompanionRootView.swift:138]
- Las dos anfitrionas terminan en el mismo `answerApproval` del modelo de chat [repo:Sources/CompanionUI/Chat/ChatViewModel+Jobs.swift:142]
- Si nadie contesta, la hoja se niega sola a los 60 s [repo:Sources/CompanionCore/Approvals/ApprovalPorts.swift:7]
- Companion publica sus propios clics con `CGEventSource(stateID: .privateState)` [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:261]
- y los entrega con `postToPid`, directo al proceso objetivo [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:267]
- Companion ya pulsa con `kAXPressAction`, el mismo camino que usaria un cliente AX externo contra la hoja [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:241]
- La tecla de mantener (FN) se escucha con un event tap en `cghidEventTap`, que exige Accesibilidad [repo:Sources/CompanionServices/Voice/Audio/HoldKeyTap.swift:80]
- Un "si" hablado solo resuelve aprobaciones de riesgo bajo, y la lista de tools de riesgo bajo es una allowlist [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:13]
- El "si" hablado exige ademas que la pulsacion empiece despues de la pregunta y pase el `dwell` del guardia de clic [repo:Sources/CompanionCore/Session/Acknowledgement.swift:62]
- La banda critica es "siempre hoja + ticket de un uso: nunca por voz, grant, confianza ni plan" [repo:docs/specs/wave-20d-modos-autorizacion.md:24]
- `bridge_session` (entregar los controles a un agente) esta en la banda critica [repo:docs/specs/wave-20d-modos-autorizacion.md:40]
- El token del puente es un archivo 0600 que se regenera al arrancar: cualquier proceso del mismo usuario puede leerlo [repo:docs/specs/wave-17-puente-mcp.md:55]
- La primera llamada de cada conexion del puente abre la hoja "Claude Code quiere usar tus manos" [repo:docs/specs/wave-17-puente-mcp.md:56]
- La vista del puente captura las ventanas del objetivo con un `SCContentFilter` de ScreenCaptureKit [repo:Sources/CompanionServices/Perception/ScreenCapture.swift:58]
- Las claves de API viven en el Llavero a traves de `KeychainSecretStore` [repo:Sources/CompanionServices/Platform/KeychainSecretStore.swift:32]
- Ningun archivo de Sources usa LocalAuthentication; el unico framework de seguridad importado es `Security` (grep de esta corrida) [repo:Sources/CompanionServices/Platform/KeychainBackend.swift:2]
- El 2026-10-01 el orquestador improviso UI scripting con System Events contra Companion cuando el puente le devolvio `self_in_front` [repo:docs/research/self-qa-puente.md:11]
- El brief del puente registra la decision final: D1 queda como se recomendo y el puente no hace clic, teclas ni texto sobre Companion [repo:docs/research/self-qa-puente.md:7]
- D7 de ese brief dejo este agujero abierto a proposito: el cliente AX fuera de banda no pasa por el puente [repo:docs/research/self-qa-puente.md:23]
- La plataforma minima es macOS 26 [repo:Package.swift:9]
Contextos: app release instalada en /Applications (com.karen.companion, donde Karen aprueba de verdad); bundle debug de bundle.sh (otra identidad, no instalado en esta Mac); `swift test` local y CI via scripts/gates.sh (sin ventana, sin Accesibilidad, sin Touch ID); la hoja en la ventana principal y la hoja en la isla (dos anfitrionas, una a la vez); el puente MCP (en banda, controlado por el codigo de Companion); clientes AX fuera de banda con su propio permiso (osascript/System Events, otro agente, malware); productores de `CGEvent` fuera de banda (cliclick, Hammerspoon, un script); VoiceOver, Control por voz y Control por botones (tambien usan acciones AX); teclado fisico con Tab y Espacio.

## 3. Fuentes primarias

- Apple, `CGEventField.eventSourceUnixProcessID`: "Key to access a field that contains the event source Unix process ID" [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventfield/eventsourceunixprocessid.json@macOS26-sdk-docs]
- Apple, `CGEventField.eventSourceStateID`: el campo contiene "the event source state ID used to create this event", es decir, el que eligio quien creo el evento [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventfield/eventsourcestateid.json@macOS26-sdk-docs]
- Apple, `CGEventField.eventSourceUserData`: "the event source user-supplied data, up to 64 bits"; lo pone quien publica [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventfield/eventsourceuserdata.json@macOS26-sdk-docs]
- Apple, `CGEventSourceStateID`: `hidSystemState` "reflects the combined state of all hardware event sources posting from the HID system"; `privateState` es para "remote control programs" que quieren un estado propio [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventsourcestateid.json@macOS26-sdk-docs]
- Apple, `CGEventSource.init(stateID:)`: crea una fuente con el estado pedido y solo devuelve NULL si el estado no es valido; no documenta ninguna restriccion para pedir `hidSystemState` [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventsource/init(stateid:).json@macOS26-sdk-docs]
- Apple, `CGEvent.setIntegerValueField(_:value:)` fija el valor entero de un campo del evento; la pagina no excluye ningun campo [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/setintegervaluefield(_:value:).json@macOS26-sdk-docs]
- Apple, `CGEvent.postToPid(_:)` publica un evento a un proceso por su pid, disponible desde macOS 10.11 [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/posttopid(_:).json@macOS26-sdk-docs]
- Apple, `NSApplication.currentEvent`: "The last event object that the app retrieved from the event queue" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsapplication/currentevent.json@macOS26-sdk-docs]
- Apple, `NSEvent.cgEvent`: el `CGEvent` correspondiente, o NULL si no se puede crear [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/cgevent.json@macOS26-sdk-docs]
- Apple, `accessibilityPerformPress()`: "Simulates clicking the accessibility element"; es un metodo que AppKit invoca, no un evento [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsaccessibilityprotocol/accessibilityperformpress().json@macOS26-sdk-docs]
- Apple, SwiftUI `accessibilityAction(_:_:)`: las acciones permiten que "assistive technologies, such as the VoiceOver" interactuen con la vista invocando la accion; el tipo por defecto es `.default` [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilityaction(_:_:).json@macOS26-sdk-docs]
- Apple, SwiftUI `accessibilityRespondsToUserInteraction(_:)` (macOS 12+) declara si el elemento seria usado por Switch Control, Voice Control o Full Keyboard Access; no promete bloquear acciones de otro proceso [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilityrespondstouserinteraction(_:).json@macOS26-sdk-docs]
- Apple, `NSWorkspace.isVoiceOverEnabled` dice si VoiceOver esta corriendo (macOS 10.13+), no quien pulso [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/isvoiceoverenabled.json@macOS26-sdk-docs]
- Apple, Security Overview: el Security Agent es "a separate process that provides the user interface for the Security Server", y eso permite autorizar sin que la app vea las credenciales [doc:https://developer.apple.com/library/archive/documentation/Security/Conceptual/Security_Overview/Architecture/Architecture.html@2012-12-13]
- Apple, Security Overview: "The Security Agent requires that the user be physically present in order to be authenticated" [doc:https://developer.apple.com/library/archive/documentation/Security/Conceptual/Security_Overview/Architecture/Architecture.html@2012-12-13]
- Apple, notas de seguridad de macOS High Sierra 10.13 Supplemental Update, CVE-2017-7150: "A method existed for applications to bypass the keychain access prompt with a synthetic click. This was addressed by requiring the user password when prompting for keychain access." [doc:https://support.apple.com/en-us/HT208165@2017-10]
- Apple, TN2150: `EnableSecureEventInput` protege la entrada de teclado contra procesos que la interceptan (seize de HID, event taps, `GetKeys`) [doc:https://developer.apple.com/library/archive/technotes/tn2150/_index.html@2007-06-08]
- Apple, TN2150: habilitarlo solo cuando el foco entra en un campo privado y "never enable secure event input for general text input or just enable this function for the life of the application" [doc:https://developer.apple.com/library/archive/technotes/tn2150/_index.html@2007-06-08]
- Apple, `LAContext.evaluatePolicy(_:localizedReason:reply:)`: "Evaluating a policy may involve prompting the user for various kinds of interaction or authentication"; el dialogo lo presenta el sistema y la app solo aporta `localizedReason` [doc:https://developer.apple.com/tutorials/data/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:).json@macOS26-sdk-docs]
- Apple, `LAPolicy.deviceOwnerAuthentication` (macOS 10.11+): en macOS usa Touch ID, Apple Watch o la contrasena de la usuaria, en ese orden de disponibilidad [doc:https://developer.apple.com/tutorials/data/documentation/localauthentication/lapolicy/deviceownerauthentication.json@macOS26-sdk-docs]
- Apple, `LAPolicy.deviceOwnerAuthenticationWithBiometrics`: falla si Touch ID no esta disponible o no esta enrolado, y la app debe ofrecer otra via [doc:https://developer.apple.com/tutorials/data/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics.json@macOS26-sdk-docs]
- Apple, ScreenCaptureKit: pide solicitar el permiso de grabacion de pantalla a la persona antes de capturar contenido [doc:https://developer.apple.com/tutorials/data/documentation/screencapturekit.json@macOS26-sdk-docs]
- Apple Support, Accesibilidad: una app que "tries to access and control your Mac through accessibility features" necesita permiso explicito en Privacidad y seguridad; "grant access only to apps that you know and trust" (pagina para macOS 10.15 en adelante) [doc:https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac@macOS-26]
- 1Password, seguridad de la integracion con la CLI: en macOS usa "the OS's default biometrics prompt", con Touch ID o Apple Watch [doc:https://www.1password.dev/cli/biometric-security/@2026-10-01]
- 1Password, misma pagina, riesgo aceptado: "Applications that are granted accessibility permissions on macOS may be able to circumvent the authorization prompt." [doc:https://www.1password.dev/cli/biometric-security/@2026-10-01]

## 4. Implementaciones de referencia

- Chromium (Google, navegador; repo principal, push diario): el ajuste "Allow JavaScript from Apple Events" lee `NSApp.currentEvent.CGEvent` y, si no hay evento, no hace nada [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/chrome/browser/ui/browser_commands_mac.mm#L54-L58@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Chromium, mismo archivo: rechaza el evento si `kCGEventSourceUnixProcessID` no es 0 ni el pid propio ("If the event is from another process, do not allow it to toggle this secure setting") [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/chrome/browser/ui/browser_commands_mac.mm#L60-L69@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Chromium, mismo archivo: ademas exige `kCGEventSourceStateID == kCGEventSourceStateHIDSystemState` ("Only allow events generated in the HID system") [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/chrome/browser/ui/browser_commands_mac.mm#L71-L79@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Chromium Remote Desktop: el monitor de raton local trata pid 0 como hardware y los eventos de otro pid como "synthetic events from other local software (e.g. accessibility and assistive tools)" [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/remoting/host/input_monitor/local_mouse_input_monitor_mac.mm#L102-L106@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Chromium, `ScopedPasswordInputEnabler`: activa `EnableSecureEventInput` solo mientras hay un campo de contrasena enfocado, con contador, siguiendo TN2150 [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/ui/base/cocoa/secure_password_input.mm#L20-L43@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Hammerspoon (automatizacion macOS, ~16k estrellas, push 2026-07-08): expone `setProperty` sobre cualquier `CGEventField` entero con `CGEventSetIntegerValueField`, incluidos los campos de origen; muestra que el autor de un evento controla esos campos antes de publicarlo [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/libeventtap_event.m#L809-L826@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- Hammerspoon, mismo archivo: documenta `eventSourceUnixProcessID`, `eventSourceStateID` y `eventSourceUserData` como propiedades que su API lee y escribe [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/libeventtap_event.m#L1412-L1416@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- Hammerspoon, mismo archivo: un contribuidor anoto que `kCGEventSourceStateHIDSystemState` y `kCGEventSourceStateCombinedSessionState` no parecian distintos de `kCGEventSourceStatePrivate` al publicar; es una observacion, no prueba sobre si el estado se puede falsificar [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/libeventtap_event.m#L1814-L1817@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- KeePassXC (gestor de contrasenas, ~29k estrellas, push 2026-09-30): desbloqueo rapido con `SecAccessControl` de biometria, con Apple Watch y contrasena del equipo como alternativas `kSecAccessControlOr` [ref:https://github.com/keepassxreboot/keepassxc/blob/9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd/src/quickunlock/TouchID.mm#L164-L185@9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd]
- KeePassXC, mismo archivo: comprueba con `canEvaluatePolicy` si hay Touch ID y si hay alternativa por contrasena antes de ofrecerlos [ref:https://github.com/keepassxreboot/keepassxc/blob/9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd/src/quickunlock/TouchID.mm#L356-L392@9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd]

## 5. Opciones

| Opcion | Que frena | Que no frena | Riesgo | Tamano | Testabilidad | Accesibilidad | Recomendacion |
|---|---|---|---|---|---|---|---|
| (a) Mantener pulsado, codigo tecleado o codigo hablado | `AXPress` simple (un AXPress no tiene duracion) | `CGEvent` sintetizado que mantiene o teclea; cliente AX que lee el codigo; audio de `say` mas una pulsacion FN sintetizada | Falsa sensacion de seguridad; choca con 20c, donde la voz solo resuelve riesgo bajo | media | media | Mala: mantener pulsado no se puede hacer con VoiceOver por `AXPress` | No |
| (b) Botones inertes para acciones AX | Quiza `AXPress` de otro proceso | `CGEvent` sintetizado; no hay API documentada que distinga VoiceOver de otro cliente AX | Deja a VoiceOver sin hoja; depende de comportamiento no documentado | baja | baja | Rompe VoiceOver, Control por voz y por botones | No |
| (c) Detectar origen y degradar | `AXPress` (separado por accion AX propia); `CGEvent` de otro proceso o del propio Companion (pid distinto de 0) | Un publicador que logre pid 0 (sin verificar, seccion 9) | Falsos positivos si `currentEvent` es viejo o nulo; mitigados porque degradar no niega | baja-media | Alta: clasificador puro en Core; cableado se prueba a mano | Si degrada a reconfirmar, VoiceOver no pierde la hoja | Si, como deteccion |
| (d) Touch ID / LocalAuthentication | Todo lo que no tenga dedo, reloj o contrasena: el dialogo lo pinta el sistema | Un atacante que conozca la contrasena (alternativa del sistema) | Sin Touch ID cae a contrasena: fricción alta si se pide siempre | media | Media: puerto en Core con fake; el dialogo real solo a mano | El dialogo del sistema es accesible (sin verificar en vivo, seccion 9) | Si, como respuesta de (c) |
| (e) Aceptar y documentar | Nada | Todo | El estado actual: un `AXPress` aprueba `bridge_session` | minima | n/a | Sin cambio | Solo para el residuo |
| (c)+(d)+(e residual) | `AXPress` y sintetizados de otro pid, sin costo para el clic humano | Publicador con pid 0 sin verificar; atacante con contrasena | Bajo y acotado | media en total | Alta en el clasificador, manual en el dialogo | VoiceOver aprueba via Tab+Espacio o via el dialogo | Recomendada |

## 6. Evidencia en contra

- La razon mas fuerte contra la recomendacion: un proceso con Accesibilidad ya controla el Mac; si puede abrir Terminal y teclear, proteger un boton parece teatro [doc:https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac@macOS-26]
- Se resuelve en parte: la hoja reparte capacidades de Companion que el atacante quiza no tiene, como la captura de pantalla del puente, que vive detras del permiso de grabacion de pantalla que ScreenCaptureKit exige a Companion [doc:https://developer.apple.com/tutorials/data/documentation/screencapturekit.json@macOS26-sdk-docs]
- Y el puente se abre a cualquier proceso del mismo usuario que lea el token; el unico freno de la sesion es la hoja de la primera llamada [repo:docs/specs/wave-17-puente-mcp.md:56]
- La cadena concreta: leer `bridge.token`, conectar, pedir `bridge_session`, pulsar "Permitir" por AX, y usar las manos y la vista de Companion sin haber pedido nunca Grabacion de pantalla [repo:docs/specs/wave-20d-modos-autorizacion.md:40]
- Se acepta el resto: contra malware decidido con Accesibilidad no hay defensa completa dentro del proceso; hasta 1Password lo declara riesgo aceptado [doc:https://www.1password.dev/cli/biometric-security/@2026-10-01]
- El actor que motivo este brief no fue malware sino un agente que improviso System Events; contra ese actor, una hoja que detecta el origen y pide Touch ID convierte una auto-aprobacion accidental en una pregunta visible a Karen [repo:docs/research/self-qa-puente.md:11]
- Contra (c): si un publicador puede escribir 0 en `eventSourceUnixProcessID` antes de publicar, la deteccion de sintetizados cae; la pagina de `setIntegerValueField` no excluye ningun campo [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/setintegervaluefield(_:value:).json@macOS26-sdk-docs]
- Se acota: Chromium protege un ajuste de seguridad real con ese mismo campo, lo que sugiere que el servidor de ventanas lo sella al publicar; queda como supuesto sin verificar con su prueba en la seccion 9, y D3 es la salida si la prueba falla [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/chrome/browser/ui/browser_commands_mac.mm#L60-L69@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]
- Contra copiar a Chromium al pie de la letra: la documentacion de `CGEventSource.init(stateID:)` no pone ninguna restriccion a crear una fuente con `hidSystemState`, asi que el chequeo de estado HID no se puede tomar como prueba de origen sin la prueba de la seccion 9 [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventsource/init(stateid:).json@macOS26-sdk-docs]
- Contra copiar a Chromium al pie de la letra: Chromium acepta su propio pid, pero en Companion el propio proceso es el que lleva las manos del agente; un evento con el pid de Companion es del agente, no de Karen [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:267]
- Contra (d) para todo (D3): Apple eligio la contrasena para el aviso del llavero tras CVE-2017-7150, pero eso cobra el paso extra en cada aprobacion; con la hoja apareciendo en cada sesion del puente el costo seria diario [doc:https://support.apple.com/en-us/HT208165@2017-10]
- Contra (d) en general: si el Mac no tiene Touch ID, `deviceOwnerAuthentication` pide la contrasena, y un atacante que la conozca la teclea; se acepta como residuo documentado (D7) [doc:https://developer.apple.com/tutorials/data/documentation/localauthentication/lapolicy/deviceownerauthentication.json@macOS26-sdk-docs]
- Contra Secure Event Input como atajo: TN2150 solo enumera tecnicas de interceptar teclado y pide no dejarlo encendido fuera de campos privados; no toca raton ni acciones AX [doc:https://developer.apple.com/library/archive/technotes/tn2150/_index.html@2007-06-08]
- Contra (c) por falsos positivos: `currentEvent` es "the last event ... retrieved"; si un `AXPress` llega sin evento nuevo, el ultimo evento puede ser un clic humano viejo y la deteccion por evento sola lo dejaria pasar; por eso el camino AX se separa con su propia accion y no por el evento [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsapplication/currentevent.json@macOS26-sdk-docs]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, Chromium niega un ajuste de seguridad a todo evento que no sea de hardware o del propio proceso, y a la ausencia de evento [ref:https://github.com/chromium/chromium/blob/fa8830b3c327aac5b6a1926884ff457c3b4fcedf/chrome/browser/ui/browser_commands_mac.mm#L54-L69@fa8830b3c327aac5b6a1926884ff457c3b4fcedf]

```objc
CGEventRef cg_event = NSApp.currentEvent.CGEvent;
if (!cg_event) {
  return;
}
int sender_pid =
    CGEventGetIntegerValueField(cg_event, kCGEventSourceUnixProcessID);
if (sender_pid != 0 && sender_pid != getpid()) {
  return;
}
```

- Ajuste para Companion: la misma idea, pero solo pid 0 cuenta como humano, porque el pid propio es el de las manos del agente [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:261]
- Bien hecho, Apple frente al clic sintetico sobre el aviso del llavero: no intento detectar el clic, pidio la contrasena, algo que el canal sintetico no tiene [doc:https://support.apple.com/en-us/HT208165@2017-10]
- Bien hecho, el Security Agent: la prueba de presencia vive en otro proceso que la app no puede pintar ni leer [doc:https://developer.apple.com/library/archive/documentation/Security/Conceptual/Security_Overview/Architecture/Architecture.html@2012-12-13]
- Bien hecho, KeePassXC: antes de ofrecer biometria pregunta con `canEvaluatePolicy` si existe, y deja la contrasena como alternativa [ref:https://github.com/keepassxreboot/keepassxc/blob/9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd/src/quickunlock/TouchID.mm#L383-L392@9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd]
- Bien hecho, en el propio repo: el guardia de la isla falla cerrado cuando no existe ("A guard never set means not yet safe, never always safe"); el clasificador de origen debe hacer lo mismo con un evento ausente [repo:Sources/CompanionCore/Island/IslandState.swift:287]
- Bien hecho, en el propio repo: el riesgo de la voz es una allowlist, y lo no clasificado sube a la hoja; el origen no clasificado debe subir a la prueba de presencia [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:11]
- Anti-ejemplo, confiar en `eventSourceStateID` o `eventSourceUserData`: los dos los fija quien crea el evento [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventfield/eventsourceuserdata.json@macOS26-sdk-docs]
- Anti-ejemplo, Secure Event Input encendido toda la vida de la app, que TN2150 prohibe y que ademas no cubre clics [doc:https://developer.apple.com/library/archive/technotes/tn2150/_index.html@2007-06-08]
- Anti-ejemplo, el guardia actual solo en la isla: la ventana principal responde sin pasar por el, y un control de origen puesto en una sola anfitriona deja la otra abierta [repo:Sources/CompanionUI/Window/CompanionRootView.swift:278]

## 8. Trampas

- Dos anfitrionas: la hoja vive en la ventana principal y en la isla; el control de origen tiene que estar en un solo punto comun a las dos (el cierre que llama `answerApproval` o un envoltorio de `ApprovalSheet`), no en cada host [repo:Sources/CompanionUI/Island/Work/IslandView+Status.swift:96]
- El propio pid no es humano: hoy el puente no pulsa Companion (D1 final del brief del puente), pero si un cambio futuro o un fallo lo permitiera, los clics que Companion publica con `postToPid` llevarian el pid de Companion y no deben contar como de Karen [repo:docs/research/self-qa-puente.md:7]
- `currentEvent` viejo: dentro de una accion disparada por `AXPress` el ultimo evento puede ser un clic humano anterior; la separacion AX tiene que venir de la accion de accesibilidad, no del evento [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsapplication/currentevent.json@macOS26-sdk-docs]
- Teclado: Espacio sobre "Permitir" con foco es un evento de teclado real; el clasificador debe aceptar `keyDown` y `keyUp` de hardware ademas de raton, o deja a quien usa teclado sin camino directo [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsevent/cgevent.json@macOS26-sdk-docs]
- Escape y "No permitir" no deben pasar por la clasificacion: negar desde cualquier canal es seguro, y bloquearlo empeoraria la accesibilidad sin ganar nada [repo:Sources/CompanionUI/Window/CompanionRootView.swift:138]
- El dialogo de LocalAuthentication responde en una cola privada del framework; la respuesta tiene que volver al `MainActor` antes de tocar la hoja [doc:https://developer.apple.com/tutorials/data/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:).json@macOS26-sdk-docs]
- El plazo de 60 s sigue corriendo mientras el dialogo del sistema esta abierto; si vence, la hoja se niega sola y la respuesta tardia del dialogo no debe aprobar una peticion ya cerrada [repo:Sources/CompanionCore/Approvals/ApprovalPorts.swift:7]
- La hoja se recrea por `requestId`; una confirmacion de Touch ID tiene que ligarse al `requestId` que la pidio, no a "la hoja que este abierta" [repo:Sources/CompanionUI/Window/CompanionRootView.swift:277]
- Capas: Core no puede importar LocalAuthentication ni AppKit; el clasificador va en Core como funcion pura sobre numeros y la prueba de presencia como puerto con adaptador en Services [repo:Package.swift:9]
- Contexto app release: es el unico donde hay Touch ID, Accesibilidad y eventos reales; toda la verificacion de D1 y D2 en vivo se hace ahi [repo:docs/research/self-qa-puente.md:91]
- Contexto bundle debug: misma logica, otra identidad; no cambia el pid propio que el clasificador compara [repo:docs/research/self-qa-puente.md:91]
- Contexto `swift test` y CI: no hay ventana, eventos reales ni Touch ID; se prueba el clasificador puro y el flujo con un fake del puerto de presencia; el dialogo real no se puede afirmar desde la suite [repo:Tests/CompanionUITests/ApprovalSheetTests.swift:33]
- Contexto puente MCP: en banda; su exclusion de la hoja se decide en el codigo del puente, y esta deteccion es una segunda cerradura si esa exclusion fallara [repo:docs/specs/wave-17-puente-mcp.md:59]
- Contexto clientes AX y productores de `CGEvent` fuera de banda: la recomendacion los degrada a Touch ID o contrasena, salvo un productor que logre pid 0 (seccion 9) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventfield/eventsourceunixprocessid.json@macOS26-sdk-docs]
- Contexto VoiceOver, Control por voz y por botones: pulsan por accion AX, asi que "Permitir" les pide Touch ID o contrasena; Tab y Espacio con teclado fisico siguen aprobando directo [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/accessibilityaction(_:_:).json@macOS26-sdk-docs]
- Contexto voz: el "si" hablado ya no resuelve riesgo alto; esta recomendacion no lo toca [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:13]

## 9. Incertidumbre

- ASSUMPTION: el servidor de ventanas sella `kCGEventSourceUnixProcessID` con el pid real al publicar, y un publicador no puede dejar 0 con `CGEventSetIntegerValueField`. prueba: un ejecutable de prueba que crea un clic con fuente `hidSystemState`, fija el campo a 0, lo publica con `postToPid` y con `post(tap: .cghidEventTap)` contra una ventana de prueba que registra el campo recibido; si llega 0, D1 no frena sintetizados y se reabre D3
- ASSUMPTION: dentro de la accion de un `Button` de SwiftUI disparada por `AXPress` de otro proceso, `NSApp.currentEvent` es nulo o es el ultimo evento real, nunca uno nuevo con el pid del cliente AX. prueba: registrar `currentEvent?.type` y su pid en la accion mientras `osascript` pulsa el boton con System Events (`click button`) y con `AXPress` directo
- ASSUMPTION: anadir `.accessibilityAction(.default)` a un `Button` de SwiftUI en macOS reemplaza la pulsacion AX del boton en vez de sumarse. prueba: en una app de prueba, un boton con accion A y accion de accesibilidad B; pulsar con VoiceOver (VO-Espacio) y con `AXPress` desde otro proceso y ver cual corre
- ASSUMPTION: VoiceOver pulsa con `AXPress` y no con un clic sintetizado, asi que su pulsacion cae en el camino AX. prueba: la misma app de prueba con VoiceOver encendido, registrando que camino corre
- ASSUMPTION: Espacio sobre un `AppButton` con foco llega como `keyDown` de hardware con pid 0. prueba: registrar el evento en la accion pulsando con Tab y Espacio
- ASSUMPTION: el dialogo de `LAContext` es usable con VoiceOver y no se puede aprobar con `AXPress` de otro proceso. prueba: con VoiceOver, completar el dialogo; luego, con `osascript`, intentar pulsar sus botones y ver si se aprueba sin dedo ni contrasena
- ASSUMPTION: no existe API publica de AppKit o SwiftUI que de el pid del cliente AX que invoca una accion. prueba: revisar `NSAccessibility` y los encabezados de AppKit del SDK de macOS 26 instalado buscando un llamador en las acciones
- Respuestas de Karen (2026-10-01) a las tres preguntas abiertas: el Mac donde aprueba tiene Touch ID; no usa VoiceOver, Control por voz ni Control por botones; ante un "Permitir" no humano quiere que Companion pida Touch ID (D2). [KAREN:chat 2026-10-01 via orquestador]

## 10. Checklist de estandar

- [ ] Un clasificador puro en Core decide el origen de una pulsacion a partir del tipo de evento, el pid de origen y el pid propio; con tests: pid 0 de raton o teclado es humano; pid ajeno, pid propio, sin evento y camino AX son no humanos.
- [ ] El clasificador falla cerrado: un evento ausente o de tipo inesperado nunca es humano.
- [ ] "Permitir" pasa por el clasificador en un unico punto comun a la ventana principal y a la isla; un test comprueba que las dos anfitrionas usan ese punto.
- [ ] Un "Permitir" no humano nunca aprueba directo: abre la prueba de presencia (puerto en Core, adaptador `LAContext` con `deviceOwnerAuthentication` en Services) o, segun D2, niega.
- [ ] La prueba de presencia se liga al `requestId`; una respuesta que llega despues del plazo de 60 s o para otra peticion no aprueba nada, con test sobre el fake del puerto.
- [ ] "No permitir" y Escape funcionan desde cualquier canal, incluido `AXPress`, con test.
- [ ] "Permitir" sigue sin atajo de teclado (test existente sigue verde).
- [ ] Ningun mecanismo bloquea a VoiceOver: con VoiceOver, "Permitir" lleva a un camino que se puede completar (dialogo del sistema o Tab y Espacio), verificado a mano en la app release.
- [ ] No se usa `EnableSecureEventInput` como defensa de la hoja.
- [ ] No se confia en `eventSourceStateID` ni en `eventSourceUserData` para decidir el origen.
- [ ] Antes de firmar D1, las pruebas de la seccion 9 sobre el sellado del pid y sobre `currentEvent` en `AXPress` tienen resultado registrado en `docs/research/evidence/`.
- [ ] El riesgo residual (atacante con Accesibilidad que conoce la contrasena, o publicador con pid 0 si la prueba lo permite) queda escrito en la seccion de seguridad de `docs/ARCHITECTURE.md`.
- [ ] El log registra cada "Permitir" degradado con el origen clasificado y el `requestId`, sin argumentos de la tool.
- [ ] security-reviewer revisa el cambio como frontera de confianza.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | CGEventField (eventSourceUnixProcessID, eventSourceStateID, eventSourceUserData) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 2 | CGEventSourceStateID, CGEventSource.init(stateID:) | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 3 | CGEvent.setIntegerValueField, CGEvent.postToPid | Apple Developer Documentation | SDK actual | 2026-10-01 | high (las paginas no hablan del sellado del pid) |
| 4 | NSApplication.currentEvent, NSEvent.cgEvent | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 5 | NSAccessibilityProtocol.accessibilityPerformPress() | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 6 | SwiftUI accessibilityAction, accessibilityRespondsToUserInteraction | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 7 | NSWorkspace.isVoiceOverEnabled | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 8 | Security Overview, Security Server and Security Agent | Apple Developer Archive | 2012-12-13 | 2026-10-01 | medium (archivo, sin actualizar) |
| 9 | About the security content of macOS High Sierra 10.13 Supplemental Update (CVE-2017-7150) | Apple Support | 2017 | 2026-10-01 | high |
| 10 | TN2150 Using EnableSecureEventInput | Apple Developer Archive | 2007-06-08 | 2026-10-01 | medium (antiguo, sin actualizar) |
| 11 | LAContext.evaluatePolicy, LAPolicy.deviceOwnerAuthentication, deviceOwnerAuthenticationWithBiometrics | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 12 | Allow accessibility apps to access your Mac | Apple Support | macOS 10.15 en adelante | 2026-10-01 | high |
| 13 | 1Password app integration security | 1Password | sitio actual | 2026-10-01 | high (fabricante, sobre su propio producto) |
| 14 | browser_commands_mac.mm, local_mouse_input_monitor_mac.mm, secure_password_input.mm | Chromium | fa8830b | 2026-10-01 | high |
| 15 | libeventtap_event.m | Hammerspoon | 23e387e | 2026-10-01 | high |
| 16 | src/quickunlock/TouchID.mm | KeePassXC | 9e0f57a | 2026-10-01 | high |
| 17 | Brief self-qa-puente y specs wave-17, wave-20d | companion-next | d563ca3 | 2026-10-01 | high |
