# Reference Brief: las manos no crean una nota nueva en Notas

Slug: manos-escribir-en-notas | Nivel: quick | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Caso: el 2026-10-02 hacia las 15:42 UTC Karen pidio por voz "abre Notas y escribe hola". Companion abrio Notas, no escribio, y la isla dijo "No hay un campo activo para escribir. Necesito abrir una nueva nota y luego escribir" y "Aparecio una lista de notas. No hay un campo activo para escribir alli". El cambio previsto toca las manos (tools `press_key`, `menu`, `look`), el prompt del padre y su gate de aprobacion.

Respuesta corta a la pregunta 1 (por que no crea la nota): no es solo que falten modificadores. La tool `menu` existe, se le ofrecio al cerebro de voz y ya creo notas por el puente MCP el 2026-09-28 (`menu` de 2 pasos y luego `type_text` escrito via AX). El turno de voz fallo por tres causas que se suman: (a) `look` sobre Notas devuelve cero controles (9 de 9 veces en el log: el recorrido se corta por tiempo en la lista de ~88 notas y nunca llega a la barra de herramientas), asi que el boton "Nueva nota" no existe para el modelo; (b) ni el prompt ni el error `no_focused_field` dicen que hacer cuando no hay campo, y gpt-oss-120b nunca probo `menu`; (c) `press_key` no admite Cmd+N por diseno (lista cerrada de 15g).

Decisiones abiertas:

1. D1, arreglo minimo del caso (sin revertir reglas): que el error `no_focused_field` y la regla de manos del prompt apunten a `menu` ("Archivo > Nueva nota" / "File > New Note") cuando la app necesita un documento nuevo. Recomendado.
2. D2, que `look` vea la barra de herramientas de la ventana antes que las listas largas (toolbar primero, o el presupuesto de 600 ms repartido). Recomendado; es lo que deja a `click` pulsar "Nueva nota".
3. D3, paridad con Incredible en atajos con modificadores. Directiva transmitida por el orquestador el 2026-10-02 (no leida de Karen directamente): Incredible fija el minimo y su `press_key` acepta acordes (Cmd, Ctrl, Alt, Shift). Recomendacion: aceptar acordes en `press_key`, resolviendo cada acorde contra la barra de menus de la app (`AXMenuItemCmdChar` + `AXMenuItemCmdModifiers`) y pulsando el item con AXPress bajo el mismo gate que `menu`; un acorde sin item de menu pide la hoja; los acordes de sistema se niegan siempre.
4. D3 revierte una regla firmada. Regla: `NamedKey` es una lista cerrada en la que "none of them is a shortcut" (Sources/CompanionCore/Voice/Dictation.swift:94-98) y el presionador limpia los flags para que ningun modificador convierta una tecla en atajo (Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:55-66), decidida en la spec cerrada 15g ("sin modificadores", evidencia linea 34) porque entonces se creia que la lista blanca de Incredible era sin modificadores. Riesgo de revertirla: Cmd+Q, Cmd+W, Cmd+Opcion+Esc, Ctrl+Cmd+Q o Cmd+Shift+Q llegan a la app por voz o por el puente; mitigado por la resolucion por menu, la negacion de acordes de sistema y la familia nueva de cerrar/salir (D4). Karen decide.
5. D4, hueco existente que D3 hereda: `menu` ya puede pulsar "Salir de Notas" o "Cerrar ventana" sin hoja, porque cerrar/salir no esta en ninguna familia destructiva y "cerrar"/"close" figuran como palabras de cancelar. Recomendacion: familia nueva quit/close con la misma regla que las otras (hoja salvo que la usuaria lo haya dicho), coherente con DM1, que ya trata `quit_app` como irreversible.
6. D5, `ApprovalRisk` no cambia: `press_key` y `menu` siguen en `high` (la hoja exige clic, no un "si" hablado). Si Karen quiere que un "si" hablado baste para salir de una app, eso es otra reversion.

## 2. Estado actual

Contextos: app instalada, voz clasica (cerebro cerebras/gpt-oss-120b por la capa de chat); app instalada, voz manos libres (Realtime); chat escrito; puente MCP (Claude Code y otros clientes, sin palabras dichas); `swift test` (sin permiso de Accesibilidad no se ofrecen las manos).
- `press_key` se describe al modelo como "Press one key ... with no modifiers. Only:" la lista cerrada [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:32]
- La lista es `return, tab, escape, up, down, left, right, backspace`, cerrada a proposito y comentada como "none of them is a shortcut" [repo:Sources/CompanionCore/Voice/Dictation.swift:95]
- Una tecla desconocida se rechaza con `invalid_args`, nunca se aproxima [repo:Sources/CompanionCore/Voice/Dictation.swift:103]
- El presionador real crea eventos con fuente privada, fija `flags = []` y los manda con `postToPid` [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:65]
- El gate de manos solo pregunta por `press_key` cuando la tecla es Return [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:101]
- `menu` es una tool de vista, ofrecida junto a `look`, `click` y `scroll` [repo:Sources/CompanionCore/Tools/ParentTools.swift:95]
- El runner anade las manos con vista cuando hay adaptador de pantalla, asi que `menu` estaba en las tools del turno (el turno llamo `look`) [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:83]
- La descripcion de `menu` es "Choose a menu-bar item of the app in front, e.g. File > Export as PDF" [repo:Sources/CompanionCore/Tools/ParentTool+Sight.swift:65]
- `menu` resuelve la ruta desde `kAXMenuBarAttribute` de la app [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:330]
- Y pulsa el item resuelto con `kAXPressAction` solo si su titulo sigue siendo el aprobado [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:319]
- Cada paso de la ruta acepta nombre parcial y sin acentos (`bestMatch`) [repo:Sources/CompanionCore/Voice/Dictation.swift:171]
- El gate de `menu` solo pide ticket si el item final cae en una familia destructiva [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:149]
- Las familias destructivas son borrar, pagar, suscribirse, enviar, cerrar sesion y publicar; no hay familia de salir ni de cerrar ventana [repo:Sources/CompanionCore/Tools/HandsWords.swift:23]
- "cerrar" y "close" estan en las palabras de cancelar, que el gate trata como inocuas [repo:Sources/CompanionCore/Tools/HandsWords.swift:48]
- `ApprovalRisk` es lista blanca: solo `look`, `see`, `read_focused`, `list_apps`, `read_skill` y `find_places` son `low`; `press_key` y `menu` son `high` [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:13]
- Un tool no clasificado es `high` [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:26]
- DM1 trata `quit_app`, `send_message` y `enter` como irreversibles [repo:Sources/CompanionCore/Decision/Plan.swift:158]
- El conjunto cerrado de atajos de DM1 incluye `close_tab_or_window` y `quit_app`, sin ejecutor todavia [repo:Sources/CompanionCore/Decision/Candidates.swift:44]
- La spec DM1 deja volumen, atajos y type_text sin ejecutor hasta DM1d [repo:docs/specs/wave-dm1-router.md:253]
- Y fija que lo irreversible confirma siempre y que un "si" hablado a algo irreversible no se recuerda [repo:docs/specs/wave-dm1-router.md:258]
- La spec 15c ya registro el caso "Abre una nota en blanco: necesita una accion (atajo Cmd+N en Notas)" como fuera de alcance [repo:docs/specs/wave-15c-tubo-rapido.md:109]
- La spec 15g eligio `press_key` sin modificadores "como la lista blanca de Incredible" [repo:docs/research/evidence/manos-notas-2026-10-02.txt:34]
- `look` recorre la ventana enfocada en profundidad con un tope de 600 ms [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:14]
- El recorrido arranca en la ventana enfocada y visita hijos en el orden que da AX [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:72]
- Guarda nodos de texto y de control por igual, asi que una lista larga de textos consume el presupuesto [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:127]
- Solo los roles de control reciben numero; el texto se lista sin id [repo:Sources/CompanionCore/Perception/ScreenScan.swift:93]
- `type_text` sin campo enfocado falla con "no focused text field in the app in front", sin sugerir otra ruta [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:304]
- La regla de manos del prompt dice "nunca le digas al usuario que lo haga; si no puedes, di en una frase por que", sin mencionar documentos nuevos [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:255]
- La regla de vista menciona `menu` solo como "elegir una opcion de la barra de menus" [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:280]
- La regla de vista se anade cuando `look` esta entre las tools, tambien en voz clasica (capa de chat) [repo:Sources/CompanionServices/Chat/ChatSSEAttempt.swift:174]
- Y en manos libres (Realtime) [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:241]
- El puente MCP trata `press_key` y `menu` como tools de escritura [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:37]
- Y les aplica la misma politica que a la voz con cero palabras dichas [repo:docs/specs/wave-17-puente-mcp.md:59]
- Log del turno: `type_text` fallo con `no_focused_field` [repo:docs/research/evidence/manos-notas-2026-10-02.txt:6]
- Luego `look` dio `elements=0 nodes=164 partial=true` [repo:docs/research/evidence/manos-notas-2026-10-02.txt:8]
- El modelo pulso un id que no existia (`click unknown_id`) [repo:docs/research/evidence/manos-notas-2026-10-02.txt:10]
- Desplazo la lista y volvio a mirar sin encontrar controles [repo:docs/research/evidence/manos-notas-2026-10-02.txt:13]
- Repitio `type_text` dos turnos mas con el mismo error y nunca llamo `menu` [repo:docs/research/evidence/manos-notas-2026-10-02.txt:16]
- El cerebro del turno fue cerebras/gpt-oss-120b [repo:docs/research/evidence/manos-notas-2026-10-02.txt:19]
- Los 9 `look` sobre Notas registrados en el log dan `elements=0` [repo:docs/research/evidence/manos-notas-2026-10-02.txt:20]
- El 2026-09-28, por el puente y con Claude Code como cliente, `menu` de 2 pasos creo la nota [repo:docs/research/evidence/manos-notas-2026-10-02.txt:28]
- Y el `type_text` siguiente escribio 174 caracteres via AX, prueba de que tras "Nueva nota" el cuerpo queda enfocado [repo:docs/research/evidence/manos-notas-2026-10-02.txt:29]

## 3. Fuentes primarias

- Apple: en Notas para Mac, Command-N crea una nota nueva (seccion General); la pagina cubre hasta macOS 27 [doc:https://support.apple.com/guide/notes/keyboard-shortcuts-and-gestures-apd46c25187e/mac@macOS-27]
- Apple: Command-Q sale de la app actual; Command-W cierra la ventana de delante; Option-Command-Esc fuerza la salida; Command-Delete mueve el item a la Papelera [doc:https://support.apple.com/en-us/102650@2026-10-02]
- Apple: `kAXMenuBarAttribute` es el objeto de accesibilidad de la barra de menus de la app, pensado para que un asistente la encuentre [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxmenubarattribute.json@macOS-26]
- Apple: `kAXMenuItemCmdCharAttribute` es la tecla principal del atajo del comando del item [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxmenuitemcmdcharattribute.json@macOS-26]
- Apple: `kAXMenuItemCmdModifiersAttribute` es la mascara de modificadores del atajo del item [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxmenuitemcmdmodifiersattribute.json@macOS-26]
- Apple: `AXUIElementPerformAction` pide al objeto que haga la accion y puede devolver `kAXErrorCannotComplete` sin haber fallado si la app tarda [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462091-axuielementperformaction.json@macOS-26]
- Apple: un evento de teclado debe incluir las pulsaciones de los modificadores (Shift abajo, tecla, Shift arriba) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:).json@macOS-26]
- Apple: `CGEvent.flags` es de lectura y escritura y lleva el estado de modificadores del evento [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/flags.json@macOS-26]
- Apple: `postToPid` existe desde macOS 10.11 y su pagina no documenta acuse ni garantia de entrega [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/posttopid(_:).json@macOS-26]

## 4. Implementaciones de referencia

- Incredible 0.2.36 (Norditech, la referencia de producto de Companion; binario instalado, solo cadenas): su `press_key()` acepta "one key/chord" con Cmd, Ctrl, Alt y Shift [repo:docs/research/evidence/manos-notas-2026-10-02.txt:36]
- Incredible pide comprobar el foco antes de cualquier tecla y nombra los atajos de la app como ruta valida [repo:docs/research/evidence/manos-notas-2026-10-02.txt:38]
- Su helper de accesibilidad valida modificadores ("Invalid key or modifiers", "Unsupported keyboard modifier") [repo:docs/research/evidence/manos-notas-2026-10-02.txt:41]
- Su helper lee `AXMenuItemCmdChar`/`AXMenuItemCmdModifiers` y pulsa items de menu con AXPress [repo:docs/research/evidence/manos-notas-2026-10-02.txt:43]
- Exige que la ventana enfocada coincida con el objetivo antes de teclear [repo:docs/research/evidence/manos-notas-2026-10-02.txt:44]
- Su control de destructivos visible en cadenas es un juez de alineacion para comandos de subagentes (ALLOW o ASK contra lo dicho); no se pudo ver si cubre teclas [repo:docs/research/evidence/manos-notas-2026-10-02.txt:46]
- Peekaboo (steipete, CLI y MCP de automatizacion macOS en Swift, ~5.2k estrellas, push 2026-10-01): rechaza Cmd+W, Cmd+Q, Cmd+H y Cmd+M enviados a un proceso en segundo plano porque el evento no tiene acuse, y deriva a comandos semanticos verificables [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundHotkeyPolicy.swift#L9-L25@016240d908566e54b702336ba39abc0f621b5b60]
- Peekaboo publica el menu como ruta "File > Export > PDF", igual que la tool `menu` de Companion [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Apps/CLI/Sources/PeekabooCLI/Commands/System/MenuCommand+Click.swift#L16-L17@016240d908566e54b702336ba39abc0f621b5b60]
- Hammerspoon (automatizacion macOS, ~16k estrellas, mantenido desde 2014): `selectMenuItem` pulsa el item con `AXUIElementPerformAction(kAXPressAction)` [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/application/libapplication.m#L905@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- Hammerspoon lee `kAXMenuItemCmdChar` y `kAXMenuItemCmdModifiers` de cada item, la base para traducir un acorde a su item de menu [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/application/libapplication.m#L923-L924@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- Hammerspoon `keyStroke` manda tecla con modificadores (abajo y arriba) opcionalmente a una app concreta [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L258-L278@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- El prototipo `../companion` (commit b8a4fd0, solo lectura) no tiene manos propias: no usa AXUIElement, CGEvent ni osascript; delega en Claude Code, asi que no aporta patron para este caso [repo:docs/research/evidence/manos-notas-2026-10-02.txt:49]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Prompt y error que enrutan a `menu` ("Archivo > Nueva nota") cuando no hay campo | Usa una tool que ya funciono en Notas (2026-09-28); no revierte ninguna regla; cambia texto y un test | Depende de que gpt-oss-120b siga la pista y de acertar el nombre localizado del menu | baja | Si, ya |
| B. `look` ve la barra de herramientas antes que las listas (toolbar primero o presupuesto repartido) | El boton "Nueva nota" pasa a tener id; sirve a todas las apps con listas largas | Toca el recorrido AX que comparten todas las apps; hay que medir que no empeore Chrome | media | Si, ya |
| C. `press_key` con acordes, resuelto por la barra de menus y pulsado por AXPress bajo el gate de `menu`; sin item, hoja; acordes de sistema negados; familia quit/close nueva | Paridad con Incredible; el modelo usa Cmd+N sin saber el idioma del menu; verificable (AXPress devuelve resultado, el CGEvent no) | Revierte 15g (Dictation.swift:94-98); mas superficie en el puente; acordes sin menu (Cmd+Enter en chats) siempre piden hoja | media | Si, si Karen firma D3 |
| D. Acordes libres por `postToPid` sin gate (paridad literal) | Lo mas simple | Cmd+Q, Cmd+W y Cmd+Opcion+Esc sin aprobacion; sin acuse de entrega | baja | No |
| E. Solo la familia quit/close en el gate de `menu` (D4), sin acordes | Cierra un hueco que existe hoy | No resuelve el caso por si sola | baja | Si, va con A o con C |

## 6. Evidencia en contra

- Contra C: la regla 15g se firmo para que ninguna tecla de las manos fuera un atajo, y el puente MCP hereda cualquier tecla nueva con cero palabras dichas [repo:docs/specs/wave-17-puente-mcp.md:59]
- Se resuelve asi: en el puente `said` es vacio, de modo que todo acorde destructivo o no resuelto pide la hoja y `ApprovalRisk` `high` exige clic [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:13]
- Contra C: el premio del caso no exige acordes, porque `menu` ya creo la nota por el puente [repo:docs/research/evidence/manos-notas-2026-10-02.txt:28]
- Se acepta: la directiva transmitida pide paridad con Incredible como minimo, y Incredible si acepta acordes [repo:docs/research/evidence/manos-notas-2026-10-02.txt:36]
- Contra mandar el acorde con `postToPid`: el evento no tiene acuse, y Peekaboo por eso rechaza Cmd+W/Q en segundo plano [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundHotkeyPolicy.swift#L9-L10@016240d908566e54b702336ba39abc0f621b5b60]
- Se resuelve en C pulsando el item de menu resuelto con AXPress, que devuelve un resultado, y dejando el CGEvent solo para acordes sin item y tras la hoja [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462091-axuielementperformaction.json@macOS-26]
- Contra A: un modelo rapido puede ignorar la pista igual que ignoro la regla de vista que ya nombraba `menu` [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:280]
- Por eso A no basta sola: el criterio de aceptacion se mide con corridas reales, no con el texto del prompt [repo:docs/research/evidence/manos-notas-2026-10-02.txt:16]

## 7. Ejemplares y anti-ejemplos

- Bien: politica que separa acordes verificables de los que no, y nombra la alternativa semantica [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundHotkeyPolicy.swift#L28-L40@016240d908566e54b702336ba39abc0f621b5b60]
- Bien: leer el atajo que cada item de menu declara en vez de suponer el mapa de teclas [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/application/libapplication.m#L923-L924@23e387e2805a9890066366e0ac96c71b27f0cfd5]
- Bien, propio: el gate de `menu` juzga el titulo que de verdad se pulsara, no el nombre parcial del modelo; un acorde resuelto debe pasar por el mismo sitio [repo:Sources/CompanionServices/Tools/ParentToolRunner+Sight.swift:43]
- Anti-ejemplo: el error `no_focused_field` describe el fallo pero no la salida, y el modelo reintento `type_text` tres veces [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:304]
- Anti-ejemplo: tratar "cerrar"/"close" como cancelar deja "Cerrar ventana" y "Salir" sin hoja en `menu` [repo:Sources/CompanionCore/Tools/HandsWords.swift:48]
- Anti-ejemplo: `keyStroke` de Hammerspoon manda cualquier acorde sin gate; vale para scripts de la propia usuaria, no para un modelo [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L275-L277@23e387e2805a9890066366e0ac96c71b27f0cfd5]

## 8. Trampas

- La familia nueva quit/close no puede reutilizar "cerrar" tal cual, porque hoy es palabra de cancelar y el gate la usa para no preguntar en botones "Cancelar/Cerrar" de un dialogo [repo:Sources/CompanionCore/Tools/HandsWords.swift:47]
- "cerrar sesion" ya se funde en el token `signout`; la familia nueva debe distinguir cerrar ventana de cerrar sesion [repo:Sources/CompanionCore/Tools/HandsWords.swift:40]
- `bestMatch` acepta nombres parciales: un acorde resuelto debe juzgarse por el titulo resuelto, como ya hace `menu` [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:146]
- El presionador actual limpia los flags para que el FN que sostiene la usuaria no convierta Return en atajo; un acorde nuevo debe fijar exactamente sus flags, no heredar los del teclado [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:57]
- Los acordes de sistema (Cmd+Tab, Cmd+Espacio, Cmd+Opcion+Esc, Ctrl+Cmd+Q, Cmd+Shift+Q) no viven en el menu de la app; Apple documenta Cmd+Opcion+Esc como forzar salida [doc:https://support.apple.com/en-us/102650@2026-10-02]
- DM1 ya tiene `quit_app` como irreversible; si las manos lo dejan pasar sin hoja, las dos rutas se contradicen [repo:Sources/CompanionCore/Decision/Plan.swift:158]
- Contexto voz clasica: el prompt nuevo y el error nuevo llegan por la capa de chat [repo:Sources/CompanionServices/Chat/ChatSSEAttempt.swift:174]
- Contexto manos libres: Realtime arma sus propias instrucciones con los mismos flags; el texto nuevo debe ir alli tambien [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:241]
- Contexto puente MCP: publica los mismos esquemas, asi que el cambio de `press_key` llega a Claude Code el mismo dia; su `said` vacio hace que todo acorde destructivo pida hoja [repo:docs/specs/wave-17-puente-mcp.md:57]
- Contexto `swift test`: sin Accesibilidad las manos no se ofrecen; el gate y la resolucion acorde-a-item deben ser puros para probarse ahi, y la prueba AX real queda en vivo [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:82]
- `look` se corta por tiempo y no por cuenta en Notas (164 nodos de 400 posibles), asi que subir `maxCollected` no arregla D2 [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:16]

## 9. Incertidumbre

- ASSUMPTION: en Notas la barra de herramientas (con "Nueva nota") es hija de la ventana despues del split de la lista, y por eso el recorrido de 600 ms nunca llega. prueba: Accessibility Inspector sobre Notas con ~88 notas, anotar el orden de hijos de la ventana y el tiempo hasta el AXToolbar
- ASSUMPTION: la ruta en espanol es "Archivo > Nueva nota" en macOS 26 (la de 2026-09-28 tenia 26 caracteres de argumento, no se registra el texto). prueba: llamar `menu` por el puente con esa ruta y con "File > New Note" y ver cual resuelve
- ASSUMPTION: Cmd+N mandado con `postToPid` a Notas en segundo plano crea la nota igual que AXPress del item. prueba: mandar el acorde con Companion delante y contar notas antes y despues
- ASSUMPTION: gpt-oss-120b elige `menu` si el error `no_focused_field` lo nombra. prueba: 10 corridas por voz de "abre Notas y escribe hola" antes y despues del cambio A
- ASSUMPTION: Incredible 0.2.36 no pide aprobacion para Cmd+N y si para Cmd+Q (las cadenas no lo muestran). prueba: pedirle por voz "abre Notas y crea una nota" y luego "cierra Notas" y observar si aparece dialogo
- ASSUMPTION: el segundo chip vacio de la isla (captura 3) es el chip de `look`/`click` sin objetivo mostrable y no pertenece a este brief. prueba: repetir el turno y leer `parentActing` de cada llamada
- [NEEDS CLARIFICATION: D3, revertir la regla 15g de `press_key` sin modificadores (Dictation.swift:94-98) para igualar a Incredible: si o no]
- [NEEDS CLARIFICATION: D4, salir de una app o cerrar una ventana por voz cuando la usuaria lo dijo ("cierra Notas"): actua sin hoja como borrar con palabra de su familia, o siempre hoja como la regla de irreversibles de DM1]
- [NEEDS CLARIFICATION: D5, si un "si" hablado debe bastar para un acorde de salir, lo que exigiria mover `press_key`/`menu` fuera de `high` en ApprovalRisk]

## 10. Checklist de estandar

- [ ] Por voz clasica, "abre Notas y escribe hola" termina con una nota nueva cuyo cuerpo es "hola", en 9 de 10 corridas, y el log muestra `menu` (o `press_key` con acorde) seguido de `type_text typed chars=4 via=ax`
- [ ] El mismo pedido en manos libres (Realtime) cumple lo mismo, o la spec dice por que no aplica
- [ ] En ninguna corrida aparece `no_focused_field` mas de una vez seguida ni `click unknown_id`
- [ ] El error `no_focused_field` nombra la salida (`menu`, p. ej. Archivo > Nuevo) y un test fija el texto en es y en
- [ ] Si se adopta D2: `look` sobre Notas con 80+ notas devuelve al menos un control con id, incluido "Nueva nota"
- [ ] Si se adopta D3: tests puros de gate dan `ask` o `refuse`, nunca `act`, para Cmd+Q, Cmd+W, Cmd+Opcion+Esc, Ctrl+Cmd+Q y Cmd+Shift+Q, con `said` vacio (puente) y con una frase que no los pide
- [ ] Si se adopta D3: los acordes de sistema se niegan siempre, aun con hoja aprobada
- [ ] Si se adopta D3: un acorde que resuelve a un item no destructivo (Cmd+N a "Nueva nota") actua sin hoja y por AXPress del item
- [ ] Si se adopta D3: un acorde que no resuelve a ningun item de menu pide la hoja con el acorde y la app en el resumen
- [ ] `menu` con "Notas > Salir de Notas" o "Archivo > Cerrar" pide la hoja salvo lo que Karen decida en D4, con test
- [ ] `ApprovalRisk` sigue con `press_key` y `menu` en `high` salvo decision explicita de Karen en D5

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Keyboard shortcuts and gestures in Notes on Mac | Apple | macOS 27 a 10.15 | 2026-10-02 | high |
| 2 | Mac keyboard shortcuts | Apple | pagina viva | 2026-10-02 | high |
| 3 | kAXMenuBarAttribute, kAXMenuItemCmdChar, kAXMenuItemCmdModifiers, AXUIElementPerformAction | Apple Developer | macOS 26 | 2026-10-02 | high |
| 4 | CGEvent init(keyboardEventSource:), flags, postToPid | Apple Developer | macOS 26 | 2026-10-02 | high |
| 5 | Peekaboo BackgroundHotkeyPolicy y MenuCommand+Click | steipete | 016240d | 2026-10-02 | high |
| 6 | Hammerspoon libapplication.m y eventtap.lua | Hammerspoon | 23e387e | 2026-10-02 | high |
| 7 | Incredible.app 0.2.36, cadenas de incredible y accessibility-helper | Norditech, binario instalado | 0.2.36 | 2026-10-02 | medium (solo cadenas, sin flujo) |
| 8 | Companion.log, turnos 2026-09-28 y 2026-10-02 | maquina de Karen | 2026-10-02 | 2026-10-02 | high |
| 9 | Spec cerrada wave-15g-manos.md en ab1637a | companion-next | ab1637a | 2026-10-02 | high |
| 10 | Prototipo companion | companion | b8a4fd0 | 2026-10-02 | high (ausencia de manos) |
