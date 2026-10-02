# Reference Brief: ajuste en la isla, cuando alguien pide cambiar un ajuste Companion trae ese control al notch y la usuaria lo cambia

Slug: ajuste-en-la-isla | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Brief hijo de `self-qa-puente` (es su D8). Las restricciones R1-R7 de ese brief se heredan sin relajar ninguna. Su R3 cubre solo grants, destinos de confianza y modos de autorizacion (self-qa-puente.md, linea 29). Este brief agrega una regla nueva, R8, que extiende R3 a todo ajuste: ninguna tool del modelo ni del puente escribe ningun ajuste de Companion; el unico escritor es el control que toca la usuaria. R8 no esta en R3: es propuesta de este brief y la firma Karen.

Decision de Karen (2026-10-01): D1-D7 y D9 firmadas como recomienda el brief, incluida la regla nueva R8. D8: la velocidad de voz vuelve como ajuste de la conversacion que el modelo entiende y aplica (no un ajuste persistente); mecanismo en el brief velocidad-de-voz-por-conversacion. Despues de un cambio la voz dice "listo". Un pedido del puente mientras hay una tarjeta abierta queda en cola. [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Funcionalidad (Karen, 2026-10-01, via orquestador): cuando la usuaria pide a Companion cambiar uno de sus propios ajustes ("cambia mi nombre de usuario", "pon la voz mas rapida", "cambia el idioma a ingles"), por voz, por texto o desde un agente externo por el puente MCP, Companion no hace clic sobre si mismo. Lleva el control de ese ajuste (campo de texto, switch, selector, slider) a la isla, enfocado, y la usuaria lo cambia con un gesto. Encuadre de Karen: con buena UX el auto-clic no hace falta.

Preguntas: Q1 inventario de ajustes y cuales se pueden llevar a la isla, cuales nunca y cuales necesitan la pagina entera; Q2 como lo pide el modelo (tool, esquema de ids, que devuelve, como falla un id viejo o desconocido); Q3 UX de la isla (tarjetas existentes, foco, cierre, tiempo, convivencia con la hoja y los avisos; como lo resuelven otros productos); Q4 accesibilidad e i18n; Q5 seguridad del pedido que llega por el puente.

Decisiones para Karen (recomendacion de este brief entre parentesis; la decision es de ella):

- D1. Inventario en tres listas: isla, pagina de Ajustes con la fila resaltada, nunca. (Recomendado: isla = idioma, sonidos, brillo de pantalla, tecla de dictado, voz, volumen, aspecto, tamano de texto, nombre, ciudad, agregar una palabra al vocabulario; pagina = sobre ti, instrucciones, foto, lista de vocabulario, voz de ElevenLabs (selector de preset y voz propia con Aplicar, que solo existe con una clave guardada), tarjeta del navegador (conectar o quitar la extension), memoria, permisos, version, "ver la bienvenida otra vez", contexto de pantalla, documentos y ubicacion; nunca = claves, "Prestar las manos", grants, destinos de confianza, modos de autorizacion y borrar adjuntos. Regla: un control que depende de una clave guardada nunca va a la isla.)
- D2. Un solo identificador por ajuste, declarado en CompanionCore (`SettingID`, raw value `pagina.nombre`, por ejemplo `general.language`, `you.name`), que sirve a la vez de argumento de la tool, de `accessibilityIdentifier` (D4 del puente) y de clave de resaltado de la fila. (Recomendado: si; el inventario de UI gana un campo `id` y una clase de superficie (isla, pagina, nunca), con test que falla si una opcion o un panel no la tiene. Clases de los casos dudosos: `voice.elevenLabs` = pagina, `privacy.browser` = pagina, `system.welcomeAgain` = pagina.)
- D3. Una tool `show_setting(id)` con el mismo nombre en chat, voz y puente. Devuelve al instante `shown` u `opened_page`, nunca el valor; el resultado posterior sale como metadato (`changed`, `dismissed`, `expired`) sin valor. Errores: `unknown_setting`, `not_surfaceable`, `busy`. (Recomendado: si; ver la seccion 5 para la alternativa de esperar a la usuaria.)
- D4. Tarjeta de ajuste en la isla: una a la vez; la hoja de aprobacion siempre gana; con la ventana principal delante no hay tarjeta, se abre Ajustes en esa pagina con la fila resaltada; switch y selector aplican al tocar; texto confirma con Return y Escape cancela; reusa el retardo anti-clic de la hoja. (Recomendado: si.)
- D5. Foco del teclado: si el pedido viene del campo de la isla (ya tiene el teclado), el control recibe el foco; si viene por voz, el control se ve enfocado y VoiceOver va a el, pero el teclado lo toma un clic; si viene del puente, nunca toma el teclado. (Recomendado: si.)
- D6. Etiqueta de la tarjeta = titulo y subtitulo del inventario por `Localized`; anuncio a VoiceOver al aparecer; test de que todo id de isla tiene texto en los dos catalogos. (Recomendado: si.)
- D7. Puente: `show_setting` solo con sesion abierta ("Prestar las manos" y hoja de sesion); la tarjeta dice quien la pidio con el nombre que el agente declara; el agente no manda texto propio; tres cierres sin cambio en diez minutos enfrian al llamante, como `maxDenials`. (Recomendado: si.)
- D8. "Pon la voz mas rapida": la velocidad salio de Ajustes a proposito en 16g y un test lo fija; o se responde que ese ajuste no existe en la app, o se reabre como control solo de isla. (Recomendado: responder que no existe hasta que Karen decida; ver la seccion 9.)
- D9. Los canales de contexto (pantalla, documentos, ubicacion) van a la pagina, no a la isla, porque amplian lo que el modelo ve y disparan avisos del sistema. (Recomendado: si.)

## 2. Estado actual

- Ajustes declara su inventario en un solo lugar: 18 opciones y 7 paneles, cada uno con su pagina y su clave de titulo [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:46]
- Los paneles (memoria, permisos, claves, navegador, version, adjuntos, bienvenida) muestran estado o corren una accion y no cuentan como opciones [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:71]
- Las paginas de Ajustes tienen un `rawValue` estable que no sigue al idioma, porque la isla y los menus nombran la pagina con el [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:4]
- La busqueda de Ajustes ya usa la clave de titulo del inventario como id de cada entrada [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:94]
- Un resultado de busqueda abre su pagina y enciende la fila durante 1,6 s [repo:Sources/CompanionUI/Settings/SettingsView.swift:135]
- El resaltado se pinta en la fila cuyo `key` coincide con la clave del inventario [repo:Sources/CompanionUI/Settings/SettingsPieces.swift:70]
- Abrir Ajustes en una pagina ya es una notificacion con el `rawValue` de la pagina como objeto [repo:Sources/CompanionUI/Window/CompanionRootView.swift:238]
- Esa notificacion cae a General en silencio si la pagina no existe [repo:Sources/CompanionUI/Window/CompanionRootView.swift:242]
- General: tecla de dictado como selector [repo:Sources/CompanionUI/Settings/HoldSettings.swift:95]
- General: sonidos como switch [repo:Sources/CompanionUI/Settings/HoldSettings.swift:110]
- General: brillo de pantalla como switch [repo:Sources/CompanionUI/Settings/HoldSettings.swift:117]
- General: "Hablar" no tiene control, solo la tecla fn dibujada [repo:Sources/CompanionUI/Settings/HoldSettings.swift:88]
- General: el idioma es un selector sistema, ingles o espanol que escribe `LanguagePreference` y avisa del cambio [repo:Sources/CompanionUI/Settings/SettingsLanguageRow.swift:22]
- El repintado en vivo del idioma depende de un contador propio de la hoja y de publicar `companionLanguageDidChange` [repo:Sources/CompanionUI/Settings/SettingsView.swift:148]
- Hoy solo el menu de la app escucha `companionLanguageDidChange` (grep de esta corrida) [repo:Sources/CompanionApp/AppMenu.swift:17]
- Voz: arriba, un selector de voz OpenAI con boton de muestra [repo:Sources/CompanionUI/Settings/SettingsVoiceSection.swift:22]
- Voz: debajo, una tarjeta propia para la voz de ElevenLabs [repo:Sources/CompanionUI/Settings/SettingsVoiceSection.swift:38]
- La tarjeta de ElevenLabs solo muestra controles si hay clave guardada; sin clave dice que voz se usa en su lugar [repo:Sources/CompanionUI/Settings/SettingsElevenLabsVoice.swift:17]
- Con clave, la tarjeta tiene un selector de presets y un campo de voz propia con boton Aplicar [repo:Sources/CompanionUI/Settings/SettingsElevenLabsVoice.swift:40]
- La voz de ElevenLabs se guarda en `ElevenLabsVoicePreference`, y un valor que no valida cae al de fabrica [repo:Sources/CompanionUI/Settings/ElevenLabsVoiceSettings.swift:8]
- La tarjeta del navegador conecta la extension escribiendo el manifiesto del host nativo [repo:Sources/CompanionUI/Settings/SettingsBrowserCard.swift:4]
- La tarjeta del navegador tiene "conectar" y un "quitar" destructivo [repo:Sources/CompanionUI/Settings/SettingsBrowserCard.swift:31]
- `BrowserSettingsModel` solo guarda estado; las acciones las cablea la raiz de composicion [repo:Sources/CompanionUI/Settings/BrowserSettingsModel.swift:5]
- "Ver la bienvenida otra vez" reabre la bienvenida y cierra Ajustes [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:196]
- La R3 de self-qa-puente cubre grants, destinos de confianza y modos de autorizacion, no todo ajuste [repo:docs/research/self-qa-puente.md:29]
- Voz: velocidad, deteccion de turno, tono y cancelacion de eco quedaron fuera de Ajustes en 16g, "each was a knob only the builder understood" [repo:Sources/CompanionUI/Settings/SettingsVoiceSection.swift:5]
- Un test fija que `settings.voice.speed`, `settings.app.decision.local` y los demas vivan en Config y no en la UI [repo:Tests/CompanionUITests/SettingsParityTests.swift:45]
- La velocidad sigue guardada en `VoiceProfile.settings`, con 1.0 por defecto [repo:Sources/CompanionUI/Settings/UserPreferences.swift:248]
- Los ajustes de voz se leen para construir la Config "on each session open" [repo:Sources/CompanionUI/Settings/UserPreferences.swift:216]
- El setter de `VoiceProfile.settings` reescribe todos los campos de voz en cada escritura [repo:Sources/CompanionUI/Settings/UserPreferences.swift:258]
- La isla ya tiene un ajuste dentro: el slider de volumen de la voz, que escribe la preferencia una sola vez al soltar [repo:Sources/CompanionUI/Island/IslandPopover.swift:134]
- Ese slider lleva etiqueta de accesibilidad del catalogo [repo:Sources/CompanionUI/Island/IslandPopover.swift:143]
- El popover del volumen solo sobrevive en tamano `.nudge`; cualquier otro tamano lo cierra [repo:Sources/CompanionUI/Island/IslandPopover.swift:24]
- Tu: nombre y ciudad son `TextField` de una linea [repo:Sources/CompanionUI/Settings/SettingsPages.swift:21]
- Tu: "sobre ti" e "instrucciones" son campos de 2 a 6 lineas [repo:Sources/CompanionUI/Settings/SettingsPages.swift:159]
- Tu: la foto se elige con un `NSOpenPanel` [repo:Sources/CompanionUI/Settings/SettingsPages.swift:134]
- Tu: aspecto como selector y tamano de texto como dos botones menos y mas [repo:Sources/CompanionUI/Settings/SettingsPages.swift:46]
- La pagina Tu copia las preferencias a `@State` al aparecer [repo:Sources/CompanionUI/Settings/SettingsPages.swift:7]
- Al editar cualquier campo, la pagina Tu escribe los cuatro campos de perfil de golpe desde su copia [repo:Sources/CompanionUI/Settings/SettingsPages.swift:126]
- Nombre, sobre ti, instrucciones y ciudad entran en la Config que recibe el modelo [repo:Sources/CompanionApp/StoredConfigProvider.swift:51]
- Vocabulario: un campo para agregar palabra y una lista con boton de quitar por palabra [repo:Sources/CompanionUI/Settings/SettingsPages.swift:226]
- Privacidad: pantalla, documentos y ubicacion son switches del contexto que viaja con cada turno [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:29]
- Encender "pantalla" sin permiso dispara el aviso de grabacion de pantalla del sistema [repo:Sources/CompanionUI/Settings/ContextSettings.swift:62]
- Encender "documentos" sin permiso dispara el aviso de Accesibilidad del sistema [repo:Sources/CompanionUI/Settings/ContextSettings.swift:78]
- Privacidad: el switch "Prestar las manos" [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:52]
- "Prestar las manos" nace apagado y su cambio arranca o para el puente sin relanzar [repo:Sources/CompanionUI/Settings/UserPreferences.swift:318]
- Privacidad: las claves son `AppField` con `secure: true` [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:157]
- Sistema: borrar adjuntos es una accion destructiva con confirmacion propia [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:208]
- 20d fija que grants y destinos de confianza se editan solo en Ajustes y el modelo jamas los escribe [repo:docs/specs/wave-20d-modos-autorizacion.md:90]
- 20d esta EN CURSO; en este worktree no hay todavia una pagina de grants ni de destinos (grep de `grant` en CompanionUI solo da permisos del sistema) [repo:docs/specs/wave-20d-modos-autorizacion.md:3]
- `IslandState` decide en un solo lugar puro que pinta la isla [repo:Sources/CompanionCore/Island/IslandState.swift:3]
- Con una aprobacion pendiente la isla pasa a tarjeta y muestra la hoja, salvo que la ventana principal este delante [repo:Sources/CompanionCore/Island/IslandState.swift:162]
- La oferta de actualizacion es la ultima de las tarjetas en reposo: nunca delante de algo que necesita a la usuaria, ni con la ventana principal delante [repo:Sources/CompanionCore/Island/IslandState.swift:138]
- El chip de manos con el nombre del cliente del puente va junto a lo que sea que pinte la isla, no en su lugar [repo:Sources/CompanionCore/Island/IslandState.swift:170]
- El recibo con deshacer tambien va al lado, y agranda la isla si estaba en reposo [repo:Sources/CompanionCore/Island/IslandState.swift:178]
- Con la hoja delante la isla suelta el teclado, para que un Return pensado para el borrador no conteste la hoja [repo:Sources/CompanionCore/Island/IslandState.swift:91]
- La hoja ignora clics durante 0,6 s tras aparecer, porque un clic en camino no debe contestarla [repo:Sources/CompanionCore/Island/IslandState.swift:276]
- Los avisos con salida viven 6 s y muestran la cuenta atras en un anillo [repo:Sources/CompanionCore/Session/SessionMachine.swift:26]
- Cada aviso declara su vida; una oferta sin cuenta atras tiene su propia palabra para cerrarse [repo:Sources/CompanionUI/Island/Notices/IslandNotice.swift:70]
- Al aparecer un aviso se arma su anuncio para VoiceOver con titulo y cuerpo [repo:Sources/CompanionUI/Island/Notices/IslandNotice.swift:142]
- El recibo y el dictado publican `AccessibilityNotification.Announcement` al aparecer; ningun archivo usa `AccessibilityFocusState` (grep de esta corrida) [repo:Sources/CompanionUI/Island/Receipt/IslandReceiptCard.swift:73]
- La tarjeta de pregunta con opciones solo toma el teclado cuando la usuaria la toca [repo:Sources/CompanionUI/Island/Choice/IslandChoiceCard.swift:72]
- Las acciones de un aviso que necesitan la ventana piden a la principal que se levante y solo nombran la pagina [repo:Sources/CompanionUI/Island/Notices/IslandView+Notices.swift:4]
- El panel de la isla es no activante [repo:Sources/CompanionUI/Island/IslandChrome.swift:209]
- La isla usa `becomesKeyOnlyIfNeeded`: solo un clic en el campo la hace key y la app de delante sigue activa [repo:Sources/CompanionUI/Island/IslandChrome.swift:223]
- El panel de la isla declara que puede ser key [repo:Sources/CompanionUI/Island/IslandChrome.swift:381]
- Cuando otra app toma el teclado, la isla suelta el campo y descansa [repo:Sources/CompanionUI/Island/IslandView.swift:214]
- `releaseKey` devuelve el teclado a la app activa sacando y volviendo a poner el panel [repo:Sources/CompanionUI/Island/IslandChrome.swift:395]
- Las tools del modelo tienen nombre fijo de cable y descripcion en el idioma de la respuesta [repo:Sources/CompanionCore/Tools/ToolSpec.swift:39]
- `ToolProperty` no expresa enums; `rawParametersJSON` pasa un esquema entero cuando hace falta [repo:Sources/CompanionCore/Tools/ToolSpec.swift:20]
- El runner del padre solo anuncia tools de manos y vista con manos listas, y no estan listas con Companion delante [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:62]
- La voz en tiempo real recibe las mismas specs del runner del padre [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:194]
- `BridgeScope` es una allowlist; una tool nueva queda fuera del puente hasta nombrarla [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:76]
- El protocolo del puente define solo tres metodos, `hello`, `call` y `bye`; que no haya eventos empujados por Companion es inferencia de este brief a partir de esa lista, no algo que el codigo diga [repo:Sources/CompanionCore/Bridge/BridgeProtocol.swift:9]
- Codigos existentes que sirven de modelo: `invalid_args`, `stale_id`, `secure_field`, `not_available` [repo:Sources/CompanionCore/Bridge/BridgeProtocol.swift:174]
- El nombre del cliente es lo que `hello` puso en el cable, no una identidad: cualquier proceso del mismo uid con el token puede decir "claude-code" [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:88]
- Tres aprobaciones denegadas en diez minutos enfrian al llamante [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:97]
- Hay un tope de 20 hojas por ventana de diez minutos, cuente o no como denegacion [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:107]
- Una herramienta que nadie clasifico como lectura cuenta contra el presupuesto de escritura [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:205]
- El puente llama la puerta con `said: ""` [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:162]
- La hoja se deniega sola a los 60 s [repo:Sources/CompanionCore/Approvals/ApprovalPorts.swift:7]
- `Localized` busca cada texto por clave en el `.lproj` del idioma elegido, no en el del proceso [repo:Sources/CompanionUI/Localization/Localized.swift:7]
- Un test comprueba que los catalogos ingles y espanol tienen las mismas claves [repo:Tests/CompanionUITests/LocalizedTests.swift:22]
- Un test pasa todas las etiquetas visibles del inventario por un filtro de jerga en los dos idiomas [repo:Tests/CompanionUITests/SettingsParityTests.swift:57]
- CompanionCore no puede importar UI: las dependencias entre targets son la arquitectura [repo:Package.swift:4]
Contextos: app release instalada en /Applications (com.karen.companion, la que Karen prueba), con la isla como panel no activante y la ventana principal que puede estar delante o no; bundle debug de bundle.sh (otra identidad, no instalado en esta Mac); turno de chat escrito (desde la ventana principal o desde el campo de la isla); turno de voz en tiempo real (FN sostenido, la app de delante sigue activa); cliente MCP externo por el shim de companion-mcp; `swift test` local y en CI (sin ventana ni VoiceOver); VoiceOver.

## 3. Fuentes primarias

- Apple HIG, Live Activities: "Only include interactive elements for essential functionality that's directly related to your Live Activity" [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026-10-01]
- Apple HIG, Live Activities: "If you offer interactivity, prefer limiting it to a single element to help people avoid accidentally tapping the wrong control." [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026-10-01]
- Apple HIG, Live Activities: para mas detalle la persona toca la actividad y abre la app, que da el detalle adicional [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026-10-01]
- Apple HIG, Live Activities: "avoid alerting people too often or with updates that aren't crucial" [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026-10-01]
- Apple HIG, Controls: un control es un boton o un toggle; los botones pueden "link to a specific area of your app" y los toggles cambian entre dos estados [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/controls.json@HIG-2026-10-01]
- Apple HIG, Controls: "The title describes what the control relates to, and the value represents the state of the control." [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/controls.json@HIG-2026-10-01]
- Apple HIG, Controls: "Require authentication for actions that affect security." [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/controls.json@HIG-2026-10-01]
- Apple WidgetKit: `ControlWidgetToggle` ("A control template representing a toggle") existe en macOS 26.0 o posterior [doc:https://developer.apple.com/tutorials/data/documentation/widgetkit/controlwidgettoggle.json@macOS26-sdk-docs]
- Apple HIG, Focus and selection: "Avoid changing focus without people's interaction." [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/focus-and-selection.json@HIG-2026-10-01]
- Apple HIG, Focus and selection: en macOS el acceso completo por teclado alcanza todo control, y el foco propio solo hace falta en elementos de contenido como campos de texto [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/focus-and-selection.json@HIG-2026-10-01]
- Apple AppKit: `nonactivatingPanel`, "a panel or a subclass of NSPanel that does not activate the owning app" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel.json@macOS26-sdk-docs]
- Apple AppKit: con `becomesKeyOnlyIfNeeded`, un panel no activante "becomes key only if the hit view returns true from needsPanelToBecomeKey" [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nspanel/becomeskeyonlyifneeded.json@macOS26-sdk-docs]
- Apple AppKit: Apple recomienda `becomesKeyOnlyIfNeeded` solo si la mayoria de los elementos del panel no son campos de texto [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nspanel/becomeskeyonlyifneeded.json@macOS26-sdk-docs]
- Apple SwiftUI: `AccessibilityFocusState` mueve el foco de VoiceOver al elemento asociado al fijar su valor; disponible desde macOS 12 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/accessibilityfocusstate.json@macOS26-sdk-docs]
- Apple SwiftUI: el valor de `AccessibilityFocusState` debe ser opcional o booleano, porque el foco puede faltar o la tecnologia asistiva no estar activa [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/accessibilityfocusstate.json@macOS26-sdk-docs]
- Apple Accessibility: `AccessibilityNotification.Announcement` transmite un anuncio a una app asistiva; macOS 14 o posterior [doc:https://developer.apple.com/tutorials/data/documentation/accessibility/accessibilitynotification/announcement.json@macOS26-sdk-docs]
- MCP 2025-06-18, Elicitation: "Servers MUST NOT use elicitation to request sensitive information." [doc:https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation@2025-06-18]
- MCP 2025-06-18, Elicitation: los clientes SHOULD indicar con claridad que servidor pide la informacion, dejar declinar en cualquier momento e implementar limite de tasa [doc:https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation@2025-06-18]
- MCP 2025-06-18, Elicitation: la respuesta distingue `accept`, `decline` (rechazo explicito) y `cancel` (cerrado sin elegir, por ejemplo Escape) [doc:https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation@2025-06-18]
- MCP 2025-06-18, Tools: los servidores MUST validar entradas, aplicar control de acceso, limitar la tasa y sanear salidas [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- MCP 2025-06-18, Tools: herramienta y argumentos invalidos son errores de protocolo; los errores de negocio van en el resultado con `isError: true` [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- Raycast API: `openExtensionPreferences` y `openCommandPreferences` abren la pantalla de preferencias, no un campo suelto [doc:https://developers.raycast.com/api-reference/preferences@current]
- Raycast API: "Required preferences need to be set by the user before a command opens." [doc:https://developers.raycast.com/api-reference/preferences@current]

## 4. Implementaciones de referencia

- VS Code (Microsoft, editor de escala masiva, commit del 2026-10-01): el comando de abrir Ajustes acepta `revealSetting: { key, edit }`, es decir, revelar un solo ajuste por su id con punto y opcionalmente poner el foco en su control [ref:https://github.com/microsoft/vscode/blob/d04893d507790cc1aa567b41fbbad049f5f14fa0/src/vs/workbench/contrib/preferences/browser/preferences.contribution.ts#L161-L168@d04893d507790cc1aa567b41fbbad049f5f14fa0]
- VS Code: los argumentos del comando se sanean campo a campo; un `revealSetting.key` que no es texto se descarta en vez de pasar [ref:https://github.com/microsoft/vscode/blob/d04893d507790cc1aa567b41fbbad049f5f14fa0/src/vs/workbench/contrib/preferences/browser/preferences.contribution.ts#L179-L200@d04893d507790cc1aa567b41fbbad049f5f14fa0]
- VS Code: `focusSettings(focusSettingInput)` enfoca la fila y, si se pide, el control de esa fila [ref:https://github.com/microsoft/vscode/blob/d04893d507790cc1aa567b41fbbad049f5f14fa0/src/vs/workbench/contrib/preferences/browser/settingsEditor2.ts#L704-L718@d04893d507790cc1aa567b41fbbad049f5f14fa0]
- boring.notch (app de notch para macOS, ~10,9k estrellas, push 2026-10-01): el HUD abierto del notch muestra un solo control, un slider arrastrable de volumen o brillo que aplica el valor mientras se arrastra [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/components/Live%20activities/OpenNotchHUD.swift#L49-L60@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- boring.notch: la ventana del notch es un `NSPanel` que nunca puede ser key, asi que el notch no lleva campos de texto [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/components/Notch/BoringNotchWindow.swift#L43-L45@d58240cc160d5e54da1a8a5925e095d067a8e1e0]

## 5. Opciones

Q2, que devuelve `show_setting`:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Respuesta inmediata `shown` / `opened_page`; resultado posterior como metadato (`changed`, `dismissed`, `expired`) sin valor | No bloquea el turno de voz ("te lo deje en la isla"); el puente no se queda ocupado; encaja con metadatos de self-qa-inspeccion-datos | El modelo no sabe en el mismo turno si cambio; hace falta un canal para el metadato posterior (contexto del siguiente turno en chat y voz, tools `companion_*` en el puente) | media | Si |
| B. La llamada espera a la usuaria hasta un tope (como la hoja, 60 s) y devuelve `changed` / `dismissed` / `expired` | Un solo ida y vuelta, igual que la elicitacion MCP (accept, decline, cancel); el agente del puente sabe el resultado | Bloquea la voz mientras la usuaria decide; ocupa la sesion del puente; 60 s es largo para un switch y corto para escribir un nombre | media | No, salvo para el puente si A no basta |
| C. Devolver tambien el valor nuevo | El modelo confirma en voz "listo, ahora te llamo Ana" | Contradice la direccion de solo metadatos; el valor de nombre, ciudad o instrucciones llega al agente externo | baja | No |

Q2, esquema de ids:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Reusar la clave de titulo del inventario (`settings.you.name`) | Ya existe, ya la usan la busqueda y el resaltado | Vive en CompanionUI y la tool se define en Core; es una clave de catalogo, mezcla prefijos (`settings.app.language` esta en General) | baja | No |
| B. `SettingID` en Core, raw value `pagina.nombre`, mapeado 1:1 al inventario | Core lo ve; mismo patron que `SettingsTab.rawValue` y que los ids con punto de VS Code; un id para tool, AX (D4 del puente) y resaltado | Un mapa mas que mantener; el test de paridad tiene que cubrirlo | media | Si |

Q3, como se ve:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Tarjeta de ajuste en la isla (familia nueva, como la de pregunta) | Un gesto; mismo idioma visual que el volumen y la pregunta; Apple pide un solo control interactivo | Familia nueva en `IslandState`; teclado de un panel no activante | media | Si para la lista de isla |
| B. Abrir Ajustes en la pagina con la fila resaltada (lo que ya hace la busqueda) | Codigo existente; sirve para todo ajuste | Levanta la ventana principal y saca a la usuaria de lo que hacia; mas de un gesto | baja | Si para la lista de pagina, y siempre que la ventana principal ya este delante |
| C. Control Center (`ControlWidgetToggle`) | Nativo de macOS 26 | Solo botones y toggles; vive fuera de la isla; requiere extension de widget | alta | No |

## 6. Evidencia en contra

- La razon mas fuerte contra la tarjeta en la isla: el notch no esta pensado para escribir; boring.notch hace su panel incapaz de ser key y Apple recomienda `becomesKeyOnlyIfNeeded` solo si casi nada es campo de texto [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/components/Notch/BoringNotchWindow.swift#L43-L45@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Se acepta en parte: la isla de Companion ya escribe (su campo de chat la hace key con un clic), asi que un campo de una linea mas no cambia el modelo del panel; los campos de varias lineas van a la pagina [repo:Sources/CompanionUI/Island/IslandChrome.swift:223]
- Contra "enfocado" sin mas: Apple pide no mover el foco sin interaccion de la persona; por eso D5 separa el foco visual y de VoiceOver del foco de teclado, y el puente nunca toma el teclado [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/focus-and-selection.json@HIG-2026-10-01]
- Contra "un gesto" para texto: cambiar el nombre es clic mas escribir mas Return; se acepta, porque un gesto menos significaria tomar el teclado de la app de delante [repo:Sources/CompanionUI/Island/IslandView.swift:214]
- Contra la respuesta inmediata (opcion A de Q2): MCP modela pedir algo a la persona como una sola peticion que espera accept, decline o cancel [doc:https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation@2025-06-18]
- Se acepta la diferencia: la elicitacion pide datos para el servidor, y aqui el dato nunca sale; lo unico que el agente necesita es saber si paso algo, y eso cabe en un metadato posterior [doc:https://modelcontextprotocol.io/specification/2025-06-18/client/elicitation@2025-06-18]
- Contra mostrar algo pedido por el puente: un agente puede insistir con el mismo control hasta que la usuaria lo cambie por cansancio; Apple pide no alertar demasiado y MCP pide limite de tasa [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json@HIG-2026-10-01]
- Se resuelve con el patron que el puente ya tiene: los cierres sin cambio cuentan como denegaciones y tres en diez minutos enfrian al llamante [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:97]
- Contra la atribucion "Claude Code quiere...": el nombre del cliente lo declara el propio cliente y no es identidad, asi que la tarjeta debe decir que es el nombre que el agente da [repo:Sources/CompanionServices/Bridge/BridgeSession+Calls.swift:88]
- Contra llevar a la isla los canales de contexto: encenderlos amplia lo que el modelo ve y dispara avisos del sistema, el mismo tipo de autoconfiguracion de alcance que 20d deja solo en manos de la usuaria [repo:Sources/CompanionUI/Settings/ContextSettings.swift:62]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, en el propio repo: el slider de volumen de la isla escribe la preferencia una sola vez al soltar, porque el setter reescribe todos los campos de voz [repo:Sources/CompanionUI/Island/IslandPopover.swift:134]

```swift
Slider(value: $volume, in: IslandVolume.floor...1) { editing in
    guard !editing else { return }
    var settings = VoiceProfile.settings
    settings.volume = IslandVolume.clamped(volume)
    VoiceProfile.settings = settings
}
```

- Bien hecho, en el propio repo: la busqueda de Ajustes abre la pagina y enciende la fila por su clave; es el camino de la lista de pagina [repo:Sources/CompanionUI/Settings/SettingsView.swift:135]
- Bien hecho, en el propio repo: la tarjeta de pregunta solo toma el teclado al tocarla [repo:Sources/CompanionUI/Island/Choice/IslandChoiceCard.swift:72]
- Bien hecho, en el propio repo: el retardo de 0,6 s contra el clic que ya venia en camino [repo:Sources/CompanionCore/Island/IslandState.swift:276]
- Bien hecho: VS Code revela un ajuste por id y enfoca su control solo si se pide `edit` [ref:https://github.com/microsoft/vscode/blob/d04893d507790cc1aa567b41fbbad049f5f14fa0/src/vs/workbench/contrib/preferences/browser/preferences.contribution.ts#L161-L168@d04893d507790cc1aa567b41fbbad049f5f14fa0]
- Bien hecho: un solo control interactivo en el notch, como pide Apple para las Live Activities [ref:https://github.com/TheBoredTeam/boring.notch/blob/d58240cc160d5e54da1a8a5925e095d067a8e1e0/boringNotch/components/Live%20activities/OpenNotchHUD.swift#L49-L60@d58240cc160d5e54da1a8a5925e095d067a8e1e0]
- Anti-ejemplo, en el propio repo: abrir Ajustes con una pagina desconocida cae a General sin decir nada; `show_setting` con un id desconocido tiene que fallar con codigo [repo:Sources/CompanionUI/Window/CompanionRootView.swift:242]
- Anti-ejemplo, en el propio repo: la pagina Tu escribe los cuatro campos de perfil desde su copia, y pisaria un cambio hecho desde la isla mientras esta abierta [repo:Sources/CompanionUI/Settings/SettingsPages.swift:126]
- Anti-ejemplo: Raycast solo abre la pantalla de preferencias entera; sirve para la lista de pagina, no para "un gesto" [doc:https://developers.raycast.com/api-reference/preferences@current]

## 8. Trampas

- La tool tiene que anunciarse fuera de `readyHands`: con Companion delante o sin Accesibilidad las tools de manos desaparecen, y `show_setting` no es una mano [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:62]
- `show_setting` entra al puente solo nombrandola en `BridgeScope`, con su decision en `BridgeAllowlistTests` [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:76]
- Si no se clasifica como lectura, `show_setting` gasta el presupuesto de escritura del puente; es lo que se quiere, porque cambia lo que la usuaria ve [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:205]
- El esquema con enum de ids no cabe en `ToolProperty`; hay que pasarlo por `rawParametersJSON` [repo:Sources/CompanionCore/Tools/ToolSpec.swift:20]
- El inventario vive en CompanionUI y la tool en Core: el id tiene que nacer en Core o la capa no compila [repo:Package.swift:4]
- Escribir un ajuste de voz desde la isla sin leer el valor fresco pisa los demas campos de voz, porque el setter los reescribe todos [repo:Sources/CompanionUI/Settings/UserPreferences.swift:258]
- La voz, la velocidad y el idioma de la voz entran a la Config al abrir sesion; el cambio desde la isla puede no oirse hasta la siguiente sesion [repo:Sources/CompanionUI/Settings/UserPreferences.swift:216]
- Cambiar el idioma desde la isla tiene que publicar `companionLanguageDidChange` igual que Ajustes; hoy nadie en la isla lo escucha [repo:Sources/CompanionUI/Settings/SettingsView.swift:148]
- Con la pagina Tu abierta, un cambio de nombre o ciudad desde la isla se pierde al siguiente tecleo en la pagina; con la ventana principal delante no debe haber tarjeta [repo:Sources/CompanionUI/Settings/SettingsPages.swift:126]
- Encender pantalla o documentos dispara un aviso del sistema; desde la isla abriria un dialogo encima del notch [repo:Sources/CompanionUI/Settings/ContextSettings.swift:78]
- Un campo de texto que toma el teclado sin clic recibe lo que la usuaria tecleaba para otra app, y nombre, ciudad e instrucciones viajan al modelo en la Config [repo:Sources/CompanionApp/StoredConfigProvider.swift:51]
- La tarjeta no puede taparle el sitio a la hoja: la hoja ya fuerza tamano `.card` y quita el teclado [repo:Sources/CompanionCore/Island/IslandState.swift:162]
- El popover de volumen muere en cualquier tamano distinto de `.nudge`; una tarjeta de volumen no puede reusarlo tal cual [repo:Sources/CompanionUI/Island/IslandPopover.swift:24]
- Una vida de 6 s como la de los avisos es corta para escribir; la tarjeta no debe contar mientras tiene el puntero o el foco [repo:Sources/CompanionCore/Session/SessionMachine.swift:26]
- Las anotaciones MCP no protegen nada; la prohibicion de mostrar claves y "Prestar las manos" tiene que vivir en Companion, no en la descripcion de la tool [doc:https://modelcontextprotocol.io/specification/2025-06-18/server/tools@2025-06-18]
- Inferido de que el protocolo solo define `hello`, `call` y `bye`: el puente no empuja eventos, asi que el metadato posterior al puente solo puede salir por una consulta (`companion_*`) o por una llamada que espera [repo:Sources/CompanionCore/Bridge/BridgeProtocol.swift:9]
- Contexto app release: la tarjeta, la tool y los limites tienen que existir en release, que es lo que Karen prueba [repo:CLAUDE.md:50]
- Contexto bundle debug: otra identidad (bundle id y nombre, lineas 24-28 de bundle.sh) y otros UserDefaults; un ajuste cambiado ahi no es el del release [repo:scripts/bundle.sh:24]
- Contexto chat escrito desde la isla: el panel ya es key, asi que la tarjeta puede tomar el foco del campo sin robar nada [repo:Sources/CompanionUI/Island/IslandChrome.swift:223]
- Contexto chat escrito desde la ventana principal: la ventana esta delante, no hay tarjeta y se usa la pagina con resaltado [repo:Sources/CompanionCore/Island/IslandState.swift:162]
- Contexto voz: la app de delante sigue activa durante y despues del FN; tomar el teclado ahi es mover el foco fuera de lo que la usuaria hacia [repo:Sources/CompanionUI/Island/IslandChrome.swift:223]
- Contexto cliente MCP: el shim puede fijar la lista de tools en vez de reenviarla; si es asi `show_setting` tambien necesita un cambio en companion-mcp [repo:docs/specs/wave-17-puente-mcp.md:4]
- Contexto `swift test` y CI: sin ventana ni VoiceOver; se prueban la decision pura de `IslandState`, el mapa de ids y los codigos de error, no el foco real [repo:Sources/CompanionCore/Island/IslandState.swift:3]
- Contexto VoiceOver: el panel es no activante y nada en el repo mueve hoy el foco de VoiceOver; que `AccessibilityFocusState` alcance un panel no key esta sin probar (seccion 9) [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/accessibilityfocusstate.json@macOS26-sdk-docs]

## 9. Incertidumbre

- ASSUMPTION: `AccessibilityFocusState` mueve el cursor de VoiceOver a un control dentro del panel no activante de la isla sin que el panel sea key. prueba: con VoiceOver activo y otra app delante, mostrar una tarjeta de prueba con un switch, fijar el estado de foco y comprobar con VoiceOver y con Accessibility Inspector donde queda el cursor
- ASSUMPTION: un cambio de voz o de idioma hecho con la sesion de voz abierta no se aplica hasta la siguiente sesion. prueba: abrir voz, cambiar la voz desde Ajustes y escuchar la siguiente respuesta antes y despues de colgar
- ASSUMPTION: las vistas de la isla repintan en el idioma nuevo sin un contador como el de Ajustes. prueba: cambiar idioma con la isla en `.card` y comprobar que el titulo de la tarjeta cambia sin otro evento
- ASSUMPTION: el shim de companion-mcp reenvia la lista de tools de `hello` y no la fija. prueba: leer su codigo de `tools/list`
- ASSUMPTION: 20 s sin puntero ni foco es una vida razonable para la tarjeta; no hay medicion publicada para un control en un notch. prueba: probar 10, 20 y 30 s con Karen sobre tres ajustes (switch, selector, nombre)
- ASSUMPTION: Incredible tiene un comando de UI por ajuste y una categoria de cambio de ajustes en su taxonomia de intenciones, pero no se sabe si su modelo puede cambiar ajustes ni como se ve (referencia local); no se uso para decidir. prueba: pedirle a Incredible por voz "apaga el brillo de pantalla" y observar si lo hace, si abre Ajustes o si se niega
- [NEEDS CLARIFICATION: D8, "pon la voz mas rapida". La velocidad salio de Ajustes en 16g y un test lo fija. Se responde "ese ajuste no esta en la app", o se reabre la velocidad como control solo de isla (y se cambia el test)?]
- [NEEDS CLARIFICATION: D9, pantalla, documentos y ubicacion van a la pagina y no a la isla. Karen nombro como "nunca" las claves, "Prestar las manos", grants y destinos; los canales de contexto no estaban en su lista.]
- [NEEDS CLARIFICATION: con la opcion A de Q2, el resultado posterior (`changed`, `dismissed`, `expired`) le llega al modelo de chat y voz como contexto del siguiente turno; se quiere tambien que la voz lo diga en voz alta ("listo"), o basta con la tarjeta?]
- [NEEDS CLARIFICATION: si un agente del puente pide un ajuste mientras la usuaria tiene abierta una tarjeta que pidio ella, se descarta la del agente (recomendado) o se encola?]

## 10. Checklist de estandar

- [ ] Existe `SettingID` en CompanionCore; cada opcion del inventario tiene un id y una clase de superficie (isla, pagina, nunca); un test falla si una opcion no la tiene.
- [ ] La voz de ElevenLabs, la tarjeta del navegador y "ver la bienvenida otra vez" tienen clase pagina; ningun control que depende de una clave guardada tiene clase isla; un test lo fija por id.
- [ ] Las claves, "Prestar las manos", borrar adjuntos y, cuando existan, grants, destinos de confianza y modos de autorizacion estan en la clase nunca; un test lo fija por id.
- [ ] El esquema de `show_setting` solo enumera ids de isla y de pagina; un id de la clase nunca devuelve `not_surfaceable` sin abrir nada; un id desconocido devuelve `unknown_setting`; ninguno cae a una pagina por defecto.
- [ ] `show_setting` se anuncia con Companion delante y sin permiso de Accesibilidad; un test lo comprueba fuera de `readyHands`.
- [ ] `show_setting` esta en `BridgeScope` con su decision en `BridgeAllowlistTests` y gasta el presupuesto de escritura.
- [ ] Ninguna respuesta de `show_setting`, inmediata o posterior, lleva el valor del ajuste; un test con nombre y ciudad lo comprueba sobre el texto y el `structuredContent`.
- [ ] Ninguna tool del modelo ni del puente escribe ningun ajuste; el unico escritor es el control que toca la usuaria. Es la regla nueva R8 de este brief, que extiende R3 de self-qa-puente (R3 solo cubre grants, destinos de confianza y modos de autorizacion).
- [ ] Con una aprobacion pendiente no se pinta la tarjeta de ajuste; test puro sobre `IslandState`.
- [ ] Con la ventana principal delante, `show_setting` abre Ajustes en la pagina y enciende la fila; no hay tarjeta.
- [ ] Hay a lo sumo una tarjeta de ajuste; un pedido del puente no reemplaza una tarjeta pedida por la usuaria.
- [ ] La tarjeta ignora clics durante el mismo retardo que la hoja.
- [ ] Un pedido del puente nunca hace key al panel; un pedido por voz no toma el teclado sin clic; un pedido desde el campo de la isla puede dar el foco al control.
- [ ] Toda escritura de voz desde la isla lee `VoiceProfile.settings` fresco antes de escribir; el slider escribe al soltar.
- [ ] Cambiar idioma desde la tarjeta publica `companionLanguageDidChange` y la isla repinta en el idioma nuevo.
- [ ] El titulo y el subtitulo de la tarjeta salen del inventario por `Localized`; un test recorre todos los ids de isla en es y en en y pasa el filtro de jerga.
- [ ] La tarjeta publica un anuncio para VoiceOver al aparecer, y el control lleva `accessibilityLabel` del catalogo y el `SettingID` como `accessibilityIdentifier`.
- [ ] Una tarjeta pedida por el puente muestra el nombre que el agente declara, marcado como declarado, y no muestra texto del agente.
- [ ] Tres cierres sin cambio pedidos por el puente en diez minutos devuelven `cooling_down` a la siguiente llamada; reconectar no reinicia la cuenta.
- [ ] security-reviewer revisa el cambio como frontera de confianza (puente, isla, teclado, Config que va al modelo).

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Human Interface Guidelines: Live Activities | Apple | sitio actual | 2026-10-01 | high |
| 2 | Human Interface Guidelines: Controls | Apple | sitio actual | 2026-10-01 | high |
| 3 | Human Interface Guidelines: Focus and selection | Apple | sitio actual | 2026-10-01 | high |
| 4 | ControlWidgetToggle | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 5 | NSWindow.StyleMask.nonactivatingPanel, NSPanel.becomesKeyOnlyIfNeeded | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 6 | AccessibilityFocusState, AccessibilityNotification.Announcement | Apple Developer Documentation | SDK actual | 2026-10-01 | high |
| 7 | MCP Specification: Elicitation | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 8 | MCP Specification: Server Tools | Model Context Protocol | 2025-06-18 | 2026-10-01 | high |
| 9 | Raycast API: Preferences | Raycast | sitio actual | 2026-10-01 | medium |
| 10 | vscode preferences.contribution.ts, settingsEditor2.ts | Microsoft | d04893d | 2026-10-01 | high |
| 11 | boring.notch OpenNotchHUD.swift, BoringNotchWindow.swift | TheBoredTeam | d58240c | 2026-10-01 | medium (app de comunidad, sin pruebas de accesibilidad vistas) |
| 12 | Incredible.app 0.2.36, analisis estatico de cadenas (solo consulta local) | Norditech, app instalada | 0.2.36 | 2026-10-01 | low (solo cadenas, sin logica) |
| 13 | Codigo y specs de companion-next (Settings, Island, Bridge, wave-20d) | companion-next | d563ca3 (HEAD del worktree) | 2026-10-01 | high |
| 14 | Brief padre self-qa-puente (R1-R7, D4, D8) y borrador hermano self-qa-inspeccion-datos (solo metadatos) | companion-next docs/research | 2026-10-01 | 2026-10-01 | medium (el hermano es BORRADOR) |
