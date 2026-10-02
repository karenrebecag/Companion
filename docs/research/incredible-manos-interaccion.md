# Reference Brief: las manos de Incredible y como replicarlas en Companion

Slug: incredible-manos-interaccion | Nivel: deep | Fecha: 2026-10-02 | Estado: ESCALADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Objetivo, en palabras de Karen (encargo de /research del 2026-10-02, citado por el orquestador): "comprender totalmente la interaccion de las manos de Incredible con el computador para replicarlo exactamente sobre Companion".

"Manos" es todo lo que el agente hace para operar la Mac por la usuaria: ver (arbol AX, capturas, OCR), apuntar y clicar, teclear (con atajos y modificadores), menus, abrir apps/archivos/URLs, desplazar y arrastrar, cambiar de ventana, leer que cambio, recuperarse de un fallo, el puntero/glow que muestra lo que hacen, aprobaciones y riesgo, y los permisos (Accesibilidad, Grabacion de pantalla, Automatizacion).

Este brief es el paraguas. El brief rapido `manos-escribir-en-notas`, escrito en paralelo, resuelve solo el caso "abre Notas y escribe hola"; este lo explica dentro del modelo completo.

Hallazgo que reencuadra el pedido: Incredible 0.2.36 no tiene una sola "mano". Tiene tres superficies con reglas distintas (seccion 4): AppleScript de un paso para apps con diccionario (Notas, Spotify, Calendar), una superficie AX en segundo plano para los workflows guardados, y una superficie "Experimental Compute Use" opt-in con teclado por PID, acordes, clics por coordenadas y arrastre. "Replicar exactamente" exige elegir cual de las tres, o cuales.

Decisiones grises (una por bloque; cada una tiene opciones en la seccion 5):

### D1. Por que camino escribe Companion en una app
- A: solo Accesibilidad (atributo de seleccion, `AXValue`, foco por AX) como hoy.
- B: Apple Events por app con diccionario (Notas, Mail, Calendar...), en proceso, como `AppleEventSheets`; nuevo permiso de Automatizacion por app.
- C: ambos, con AX como default y Apple Events solo para apps listadas.
- [NEEDS CLARIFICATION: ¿Companion puede pedir el permiso de Automatizacion para Notas (y otras apps) igual que ya lo pide para Excel/Numbers, o las manos deben quedarse solo en Accesibilidad?]

### D2. Atajos con modificadores (Cmd+N, Cmd+Shift+P...)
- Hoy `press_key` acepta 8 teclas sin modificadores. Incredible experimental acepta acordes; Peekaboo los acepta pero redirige Cmd+W/Q/H/M a comandos semanticos.
- [NEEDS CLARIFICATION: ¿se abren los acordes? Si si: ¿lista negra de acordes destructivos que van a la hoja (y por tanto a Touch ID), o lista blanca corta (Cmd+N, Cmd+F, Cmd+L, Cmd+T...) y todo lo demas rechazado?]

### D3. Primer plano o segundo plano
- Incredible estable trabaja "deliberadamente" en segundo plano y no puede traer ventanas al frente; la experimental puede activar con `activate(intent)`.
- Companion hoy activa la app al abrirla (`NSWorkspace` por defecto activa) y `focus_window` llama `activate()`.
- [NEEDS CLARIFICATION: ¿Companion puede robar el foco (activar la app) para terminar una tarea, o debe preferir siempre el segundo plano y avisar cuando no pueda?]

### D4. Abrir una app y esperar a que este lista
- Hoy `open_app` vuelve en cuanto LaunchServices acepta el lanzamiento, sin esperar ventana ni foco. Incredible espera la ventana (hasta 30 s) y devuelve el PID.
- Decision tecnica (sin pregunta a Karen): la spec M2 la fija; solo falta el plazo maximo.

### D5. Verificar despues de cada accion
- Incredible observa la app tras cada accion (espera minima, AX quieto, presupuesto) y devuelve un resumen del cambio (titulo, dialogo nuevo, ventana nueva, "nada cambio").
- Companion devuelve "look again" y deja la verificacion al modelo.
- Decision tecnica: spec M4. Pregunta para Karen solo sobre latencia: [NEEDS CLARIFICATION: ¿se acepta aproximadamente 1 s extra por accion de mano a cambio de que cada resultado diga que cambio?]

### D6. Lo que la usuaria ve mientras actuan las manos
- Hoy el aura de pantalla solo se enciende con las manos prestadas al puente (agente externo), no con las manos de la propia voz.
- [NEEDS CLARIFICATION: ¿el aura/glow sobre la ventana objetivo debe encenderse tambien cuando la voz de Companion actua (abrir, clicar, escribir), y debe nombrar la accion (chip "Escribiendo en Notas")?]

### D7. Clic por coordenadas y arrastre
- Incredible experimental lo permite sobre una captura de la ventana exacta y mueve el puntero fisico.
- [NEEDS CLARIFICATION: ¿Companion debe poder mover el puntero de la usuaria (clic por coordenadas, arrastrar), o queda fuera hasta que haya un caso real?]

### D8. Aprobaciones para las capacidades nuevas
- Reglas firmadas que mandan: 20c D1 (el si hablado solo resuelve bajo riesgo), Touch ID en cada aprobacion critica (manos en la hoja = critico), y `open_url` a un host no dicho nunca por voz (sumidero de exfiltracion).
- Lo que falta decidir es solo que acciones nuevas suben a la hoja: acordes destructivos, crear una nota por Apple Events, clic por coordenadas.
- [NEEDS CLARIFICATION: ¿crear contenido nuevo en una app (una nota, un borrador) corre sin hoja como hoy corre `type_text` fuera de una terminal, o pide hoja?]

### D9. Juez LLM
- Incredible pone un juez LLM (`judge_actions`) delante de lotes de escrituras. No se recomienda copiarlo como compuerta (seccion 6 y 7); queda como decision explicita.
- [NEEDS CLARIFICATION: ¿se descarta el juez LLM como compuerta de las manos, dejando las compuertas deterministas actuales (HandsGate, ActionBand, tickets)?]

## 2. Estado actual

Contextos: app instalada (/Applications/Companion.app con TCC concedido), voz realtime, voz clasica, chat escrito (Companion delante), puente MCP (agente externo con las manos prestadas), swift test (fakes de los puertos, sin TCC), CI macOS (sin TCC).

### 2.1 Las tools de manos que existen hoy
- Las manos son tools del "padre" (la voz o el chat), no del especialista: `open_app`, `open_url`, `open_file`, `list_apps`, `read_skill`, `type_text`, `press_key`, `focus_window`, `read_focused`, `look`, `click`, `scroll`, `menu`, `see` [repo:Sources/CompanionCore/Tools/ParentTools.swift:52]
- Las de Accesibilidad solo se ofrecen con Accesibilidad concedida y Companion no delante [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:63]
- El navegador tiene tools propias por extension: `browser_tabs`, `browser_read`, `browser_click`, `browser_type`, `browser_navigate`, `browser_open`, `browser_take`, `browser_release` [repo:Sources/CompanionCore/Browser/BrowserTool.swift:7]
- `find_places` busca lugares reales y se ofrece solo si hay buscador detras [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:80]
- La voz realtime recibe las mismas specs del runner en el `session.update` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:235]
- La voz clasica arma su lista de tools por turno desde el mismo runner [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:347]
- El prompt del sistema enseña las manos solo si sus tools estan declaradas [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:54]
- La regla de manos del prompt: escribir en el campo enfocado, pulsar una tecla, levantar ventana, leer el campo, y verificar con `read_focused` antes de decir "escrito" [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:239]
- La regla de vista del prompt: `look` antes de `click`, volver a mirar despues de pulsar, `see` solo para imagenes o diseño [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:266]
- El prompt declara que lo que devuelve una tool es dato, no orden, y prohibe abrir o escribir algo que solo aparece ahi [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:214]

### 2.2 Ver
- `look` recorre la ventana enfocada (o la principal, o la primera) y numera controles, con presupuesto de 600 ms, 2500 nodos visitados y 400 recogidos [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:14]
- `look` tambien recorre los dialogos y hojas de la app como grupos aparte [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:73]
- Antes del primer recorrido "prima" la app con `AXManualAccessibility` y, en navegadores Chromium, `AXEnhancedUserInterface` [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:210]
- Cada app que pasa al frente se prima en segundo plano [repo:Sources/CompanionApp/CompanionMainSensing.swift:103]
- `see` captura con ScreenCaptureKit (`SCScreenshotManager`) y lo describe un modelo de vision [repo:Sources/CompanionServices/Perception/ScreenCapture.swift:71]
- Hay OCR local con Vision para regiones [repo:Sources/CompanionServices/Perception/RegionGrabber.swift:113]
- El texto visible de la ventana se cosecha por AX con su propio presupuesto de 450 ms [repo:Sources/CompanionServices/Accessibility/AXScreenText.swift:21]
- Los ids de `look` caducan con el siguiente `look`; un id viejo devuelve `stale_id` [repo:Sources/CompanionServices/Tools/ParentToolRunner+Sight.swift:166]

### 2.3 Actuar
- `click` prueba en orden: `AXPress`, foco por `AXFocused` si es editable, y por ultimo un clic de raton enviado al proceso en el centro del elemento [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:241]
- El clic de raton usa una fuente de eventos privada y `postToPid`, y no mueve el puntero de la usuaria [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:258]
- Antes de pulsar, `click` relee la etiqueta viva y rechaza si cambio desde el `look` [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:237]
- `scroll` solo va arriba o abajo por pagina (`AXScrollDownByPage`) o moviendo la barra un 25 % [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:276]
- `menu` resuelve la ruta en la barra de menus por coincidencia parcial y pulsa con `AXPress` el item final [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:326]
- `menu` vuelve a resolver al pulsar y exige el mismo titulo que se aprobo [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:319]
- `type_text` escribe primero por `kAXSelectedTextAttribute` y, si la app lo ignora, por portapapeles mas un Cmd+V enviado al proceso [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:59]
- El portapapeles se guarda con todos sus tipos y se restaura solo si nadie lo cambio mientras tanto [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:145]
- `press_key` acepta solo Return, Tab, Escape, Backspace y las cuatro flechas, sin modificadores [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:103]
- `press_key` limpia los flags del evento a proposito para que un modificador sostenido (el FN) no convierta Return en atajo [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:65]
- La descripcion de `press_key` le dice al modelo "sin modificadores" [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:32]
- `focus_window` busca por titulo entre las ventanas de la app objetivo, hace `AXRaise` y activa la app [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:86]
- `open_app` resuelve el nombre contra apps instaladas y abiertas y llama `NSWorkspace.openApplication` con la configuracion por defecto [repo:Sources/CompanionServices/Tools/NSWorkspaceOpener.swift:27]
- `open_app` devuelve "opened" sin esperar a que la app tenga ventana ni este delante [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:206]
- Tras un `open_*` exitoso, el objetivo del turno se libera y la siguiente mano "re-fija" el PID que observe [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:138]
- El PID objetivo es la ultima app delante que no es Companion, actualizado por la notificacion de activacion [repo:Sources/CompanionServices/Perception/ContextSensors.swift:229]
- No hay drag, ni clic derecho, ni doble clic, ni scroll horizontal, ni "scroll hasta que se vea" [repo:Sources/CompanionCore/Tools/ParentTools.swift:68]

### 2.4 Verificar y recuperarse
- `type_text` lee el campo antes de escribir y la copia del resultado dice "intente" hasta que una lectura lo pruebe [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:270]
- Los errores son un contrato con codigo estable para que el modelo se recupere (`no_focused_field`, `target_changed`, `stale_id`, `menu_not_found`...) [repo:Sources/CompanionCore/Tools/ParentTools.swift:3]
- `no_focused_field` sale cuando el elemento enfocado no tiene rol editable ni `AXValue` escribible [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:18]
- Los roles editables son solo `AXTextField`, `AXTextArea` y `AXComboBox` [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:14]
- El mensaje que recibe el modelo es "no focused text field in the app in front", sin decir que tiene el foco ni como conseguir un campo [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:303]
- Si la usuaria cambio de app mientras el modelo pensaba, la mano falla con `target_changed` en vez de actuar en otra ventana [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:245]
- Cada llamada AX tiene un tope de 0,25 s para que una app colgada no congele la voz [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:24]

### 2.5 Seguridad y aprobaciones
- `HandsGate`: un clic pide hoja si su boton borra, paga o envia y la usuaria no uso una palabra de esa familia; un boton sin etiqueta siempre pide hoja [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:131]
- `HandsGate`: en una app de comandos (terminal) teclear y Return piden hoja salvo una sola linea que la usuaria dijo [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:100]
- `HandsGate`: un item de menu se juzga por el titulo que de verdad se pulsaria, no por el parcial del modelo [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:149]
- Las acciones aprobadas gastan un ticket de un solo uso, ligado a PID, nodo y generacion del `look`, que caduca a los 60 s [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:99]
- `ParentToolGuard` es el punto unico por el que pasa toda hoja de las manos [repo:Sources/CompanionServices/Tools/ParentToolGuard.swift:110]
- La hoja se niega sola a los 60 s [repo:Sources/CompanionCore/Approvals/ApprovalPorts.swift:7]
- `open_url` a un host que la usuaria no dijo pide hoja [repo:Sources/CompanionCore/Tools/ParentToolPolicy.swift:186]
- `ApprovalRisk` es una lista blanca de lo que un si hablado puede resolver: solo lecturas y `find_places` [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:13]
- `open_url` esta fuera de esa lista a proposito: un si hablado abriria un host no dicho, el sumidero de exfiltracion [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:14]
- La regla firmada 20c D1: `resolve_approval` (voz o modelo) solo resuelve bajo riesgo; nunca click destructivo, `type_text` en terminal ni `menu` destructivo [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:27]
- La spec firmada de Touch ID clasifica toda mano en la hoja (`click`, `type_text`, `menu`...) como critica [repo:docs/specs/touch-id-aprobaciones-criticas.md:29]
- Karen pidio Touch ID en cada aprobacion critica [KAREN:docs/specs/touch-id-aprobaciones-criticas.md 2026-10-01]
- La spec de Touch ID esta aprobada pero en `main` no existe aun `atSheet` ni `verifyOwner` en el codigo [repo:Sources/CompanionCore/Tools/ActionBand.swift:57]
- `ActionBand` deja las manos en `.act` salvo objetivo destructivo o terminal, que suben a `.critical` [repo:Sources/CompanionCore/Tools/ActionBand.swift:61]
- El freno total deniega todas las aprobaciones pendientes y cancela el trabajo [repo:Sources/CompanionCore/Session/SessionMachine+Brakes.swift:53]
- Limites del puente: 30 acciones y 60 lecturas por minuto, 3 negativas en 10 min enfrian, 20 hojas por ventana de 10 min [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:85]
- Las manos de la voz propia no tienen limite de ritmo; solo el puente lo tiene [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:115]

### 2.6 Lo que ve la usuaria y los permisos
- El aura de pantalla se enciende con `handsWorking` solo si las manos estan prestadas al puente (`handsLentTo`) [repo:Sources/CompanionCore/Session/SessionMachine.swift:286]
- El aura dura 4 s despues de la ultima llamada del puente [repo:Sources/CompanionCore/Session/SessionMachine.swift:15]
- El panel del overlay es transparente a clics y no sale en las capturas de Companion [repo:Sources/CompanionUI/Overlay/ScreenOverlay.swift:20]
- El rastro de tinta y el orbe que sigue al cursor existen, medidos de Incredible, pero ligados al hold de FN [repo:Sources/CompanionUI/Overlay/PointerTrail.swift:3]
- Accesibilidad se pide con `AXIsProcessTrustedWithOptions` y el prompt del sistema [repo:Sources/CompanionServices/Permissions/AccessibilityPermission.swift:22]
- Grabacion de pantalla se comprueba con `CGPreflightScreenCaptureAccess` [repo:Sources/CompanionServices/Permissions/ScreenRecordingPermission.swift:12]
- Companion ya manda Apple Events desde su propio proceso para Excel y Numbers, y reconoce el -1743 de permiso denegado [repo:Sources/CompanionServices/Deliverables/AppleEventSheets.swift:10]
- El texto de `NSAppleEventsUsageDescription` solo menciona hojas de calculo [repo:scripts/bundle.sh:91]
- Una spec anterior ya vio el caso "abre una nota en blanco" y lo dejo fuera porque necesita Cmd+N [repo:docs/specs/wave-15c-tubo-rapido.md:109]

### 2.7 El caso "abre Notas y escribe hola": por que fallo
- Paso 1: `open_app("Notes")` lanza o activa Notas y vuelve enseguida, sin esperar ventana ni foco [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:206]
- Paso 2: el objetivo del turno se libera y la siguiente mano fija el PID que vea en ese momento [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:80]
- Paso 3: `type_text("hola")` pide el elemento enfocado de esa app y exige un rol editable [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:302]
- Paso 4: si el foco de Notas esta en la lista de notas o en la barra lateral (no en el cuerpo), no hay campo y sale `no_focused_field` [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:19]
- Paso 5: el modelo recibe "no focused text field" sin pista de recuperacion y lo dice como "No hay un campo activo para escribir" [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:298]
- Habia una ruta con las tools de hoy: `menu("Archivo > Nueva nota")` y luego `type_text`; el prompt no enseña a buscar o crear el campo cuando falta [repo:Sources/CompanionCore/Chat/ChatPrompt.swift:239]
- Otra ruta disponible: `look` y luego `click` sobre el area de texto, que la enfoca por `AXFocused` [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:244]
- Lo que no habia: Cmd+N, porque `press_key` no lleva modificadores [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:40]

### 2.8 Tabla de capacidades, brecha por brecha

| Capacidad | Incredible 0.2.36 | Companion hoy | Brecha | Evidencia |
|---|---|---|---|---|
| Arbol AX numerado | escaneo con presupuesto, ids que caducan, aviso de parcial | igual (`look`) | ninguna de fondo | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:19] [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:14] |
| Buscar por rol/nombre/texto | `find_by_role`, `find_by_text`, `find_all`, ambiguedad como error | solo lista numerada | falta busqueda dirigida y error `Ambiguous` | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:73] [repo:Sources/CompanionCore/Tools/ParentTool+Sight.swift:10] |
| Captura de ventana exacta + OCR local | SCK por ventana, OCR Vision con tope de 2 s, vision remota de respaldo | captura + vision remota; OCR solo de region | falta captura por ventana con OCR local primero | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:45] [repo:Sources/CompanionServices/Perception/ScreenCapture.swift:71] |
| Clic semantico | `AXPress`, luego foco | `AXPress`, foco, clic al proceso | ninguna | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:20] [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:241] |
| Clic por coordenadas, derecho, doble, arrastre | sobre captura de la ventana exacta, mueve el puntero fisico, ventana delante | no existe | falta (decision D7) | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:85] [repo:Sources/CompanionCore/Tools/ParentTools.swift:68] |
| Escribir texto | `type_text` por PID sin portapapeles, `fill`, `set_value`, `select_text` | atributo de seleccion, o portapapeles + Cmd+V | falta `set_value`/`fill` y seleccion precisa | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:84] [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:59] |
| Atajos con modificadores | `press_key("Cmd+n")`, acordes, F1-F24 | 8 teclas sin modificadores | falta (decision D2) | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:82] [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:103] |
| Menus | ruta con `AXPress`, item deshabilitado detectado, lee atajos de cada item | ruta con `AXPress` | falta detectar deshabilitado y listar menus con sus atajos | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:17] [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:316] |
| Abrir app | sin activar, espera ventana hasta 30 s, devuelve PID | activa, no espera | falta esperar y fijar el PID devuelto | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:76] [repo:Sources/CompanionServices/Tools/NSWorkspaceOpener.swift:27] |
| Apps con diccionario (Notas) | AppleScript de un paso permitido; -1743 = pedir Automatizacion | Apple Events solo para Excel/Numbers | falta (decision D1) | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:60] [repo:Sources/CompanionServices/Deliverables/AppleEventSheets.swift:5] |
| Desplazar | arriba/abajo/izquierda/derecha y `scroll_into_view` | arriba/abajo por pagina | falta horizontal y "hasta que se vea" | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:25] [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:272] |
| Cambiar de ventana | ventanas por id exacto, `activate(intent)` puede cambiar de Space | `focus_window` por titulo dentro de la app objetivo | falta listar ventanas de todas las apps y el caso otro Space | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:77] [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:72] |
| Leer que cambio | AXObserver, espera minima 1 s + 500 ms quieto, resumen "nada cambio / dialogo / ventana nueva" | "look again" en el texto del resultado | falta (decision D5) | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:80] [repo:Sources/CompanionServices/Tools/ParentToolRunner+Sight.swift:164] |
| Guardas antes de teclear | foco y caret iguales al escaneo, tecla sostenida, pantalla bloqueada | app objetivo igual a la del turno | faltan foco/caret, tecla sostenida y bloqueo | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:38] [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:298] |
| Errores tipados | NotFound, Ambiguous, Stale, Disabled, ForegroundRequired, InputBusy, OutcomeUnknown... | codigos de contrato | faltan `ambiguous`, `disabled`, `input_busy`, `outcome_unknown` | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:87] [repo:Sources/CompanionCore/Tools/ParentTools.swift:6] |
| Visual de las manos | panel indicador con glow sobre la ventana objetivo, transparente a clics | aura solo con el puente | falta para la voz propia (decision D6) | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:44] [repo:Sources/CompanionCore/Session/SessionMachine.swift:286] |
| Aprobacion | lecturas en silencio, juez LLM para lotes, tarjeta para enviar/borrar | compuertas deterministas, hoja, tickets, Touch ID firmado | Companion es mas estricto; no copiar el juez | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:52] [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:96] |
| Ritmo | no se encontro limite de acciones de escritorio en las cadenas | limites solo en el puente | igual de abierto en la voz propia | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:103] [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:85] |
| Permisos | Accesibilidad, Grabacion, Automatizacion (entitlement apple-events) | Accesibilidad, Grabacion; Automatizacion solo hojas | Automatizacion por app nueva si D1 = B o C | [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:9] [repo:scripts/bundle.sh:90] |

## 3. Fuentes primarias

- `AXUIElementPerformAction` pide a un objeto AX que ejecute una accion; puede devolver `kAXErrorCannotComplete` aunque la accion haya ocurrido, porque la app tarda en su callback [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462091-axuielementperformaction.json@macOS26-sdk-docs]
- `AXUIElementCopyAttributeValue` devuelve `kAXErrorNoValue` cuando el atributo no tiene valor (por ejemplo, ningun elemento enfocado) [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462085-axuielementcopyattributevalue.json@macOS26-sdk-docs]
- `AXUIElementSetAttributeValue` escribe un atributo (por ejemplo `AXFocused` o `AXValue`) y falla con `kAXErrorAttributeUnsupported` si el elemento no lo admite [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1460434-axuielementsetattributevalue.json@macOS26-sdk-docs]
- `kAXShowMenuAction` simula abrir el menu contextual de un elemento [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxshowmenuaction.json@macOS26-sdk-docs]
- `kAXFocusedUIElementAttribute` existe desde macOS 10.2 y su pagina no documenta semantica adicional [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/kaxfocuseduielementattribute.json@macOS26-sdk-docs]
- `AXObserverCreate` crea un observador de notificaciones AX de un PID; se registran notificaciones con `AXObserverAddNotification` [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1460133-axobservercreate.json@macOS26-sdk-docs]
- `AXIsProcessTrustedWithOptions` dice si el proceso es cliente de Accesibilidad confiable; con `kAXTrustedCheckOptionPrompt` el aviso es asincrono y no cambia el valor devuelto [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1459186-axisprocesstrustedwithoptions.json@macOS26-sdk-docs]
- Un evento de teclado sintetico necesita todas sus teclas, incluidos los modificadores como eventos propios (Shift abajo, z abajo, z arriba, Shift arriba) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:).json@macOS26-sdk-docs]
- `CGEventFlags` incluye `maskCommand`, `maskShift`, `maskControl`, `maskAlternate` y `maskSecondaryFn` [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventflags.json@macOS26-sdk-docs]
- `keyboardSetUnicodeString` fija el texto de un evento, pero los frameworks de la app pueden ignorarlo y traducir por el codigo de tecla [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:).json@macOS26-sdk-docs]
- `postToPid` entrega un evento a un proceso por PID; disponible desde macOS 10.11 [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/posttopid(_:).json@macOS26-sdk-docs]
- `CGEventSource(stateID:)`: fuentes que comparten estado se afectan; `privateState` usa una tabla de estado propia [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventsource/init(stateid:).json@macOS26-sdk-docs]
- `CGEventSourceStateID.privateState` es la tabla privada; `hidSystemState` refleja el hardware [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventsourcestateid/privatestate.json@macOS26-sdk-docs]
- `CGPreflightPostEventAccess` comprueba el permiso para publicar eventos (macOS 10.15+) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgpreflightposteventaccess().json@macOS26-sdk-docs]
- `SCScreenshotManager` captura un fotograma o una captura con filtro de contenido (ventana o pantalla), macOS 14+ [doc:https://developer.apple.com/tutorials/data/documentation/screencapturekit/scscreenshotmanager.json@macOS26-sdk-docs]
- `CGPreflightScreenCaptureAccess` comprueba Grabacion de pantalla sin mostrar UI (macOS 10.15+) [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgpreflightscreencaptureaccess().json@macOS26-sdk-docs]
- `VNRecognizeTextRequest` reconoce texto en una imagen en el dispositivo (macOS 10.15+) [doc:https://developer.apple.com/tutorials/data/documentation/vision/vnrecognizetextrequest.json@macOS26-sdk-docs]
- `NSWorkspace.OpenConfiguration.activates` vale `true` por defecto: abrir una app la trae al frente [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/openconfiguration/activates.json@macOS26-sdk-docs]
- `didActivateApplicationNotification` llega por el centro de notificaciones del workspace cuando una app se activa; es asincrona respecto del lanzamiento [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/didactivateapplicationnotification.json@macOS26-sdk-docs]
- El entitlement `com.apple.security.automation.apple-events` permite pedir a la usuaria mandar Apple Events a otras apps (con Hardened Runtime) [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events.json@macOS26-sdk-docs]
- `NSAppleEventsUsageDescription` es obligatorio si la app manda Apple Events, porque automatizar otra app puede dar acceso indirecto a datos sensibles [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.json@macOS26-sdk-docs]
- Accesibilidad deja a una app "acceder y controlar tu Mac"; se gestiona en Ajustes > Privacidad y seguridad > Accesibilidad [doc:https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac@2026-10-02]
- Automatizacion: una app que controla otra pide permiso con un dialogo la primera vez y se gestiona en Privacidad y seguridad > Automatizacion [doc:https://support.apple.com/guide/mac-help/allow-apps-to-automate-and-control-other-apps-mchl108e1718/mac@2026-10-02]
- Grabacion de pantalla y audio del sistema se concede por app en Privacidad y seguridad [doc:https://support.apple.com/guide/mac-help/control-access-screen-system-audio-recording-mchld6aa7d23/mac@2026-10-02]
- Privacidad separa Accesibilidad, Grabacion, Automatizacion y Monitorizacion de entrada como permisos distintos [doc:https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac@2026-10-02]

## 4. Implementaciones de referencia

### 4.1 Incredible 0.2.36 (referencia de comportamiento; codigo propietario, no se copia)
Por que es referencia: es el producto que Karen pidio igualar; la evidencia es estatica (cadenas y recursos de texto plano), con hash del binario. [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:2]
- Tres superficies de manos, no una: AppleScript de un paso, superficie AX de workflows en segundo plano, y "Experimental Compute Use" opt-in [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:59]
- El agente de fondo por defecto solo tiene captura de pantalla en `desktop`, no manos sobre apps nativas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:64]
- La superficie completa de computer use es una skill opt-in ligada al ajuste `experimental_compute_use` [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:68]
- El orquestador de voz no actua: su `open_app` solo lanza y todo lo que sigue es trabajo de un agente [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:67]
- El agente recibe las palabras de la usuaria literales junto a los objetivos [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:66]
- El helper nativo (Swift) usa AX, CGEvent, NSWorkspace, ScreenCaptureKit y Vision; nada privado aparece en `otool -L` [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:8]

#### Percibir
- Escaneo AX con presupuesto de tiempo y nodos, y aviso explicito de resultado parcial [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:19]
- Primado de apps Chromium/Electron antes de escanear (Chrome, Slack, VSCode, Cursor...) [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:13]
- Cada vista trae `input_focus` y la seleccion de texto, para saber donde caeria una tecla [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:81]
- La captura de computer use es de la ventana exacta y no recurre al escritorio [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:114]
- El comando `screenshot` del helper daemon, en cambio, usa `CGWindowListCreateImage` [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:27]
- OCR local primero (Vision, tope 2 s) y modelo de vision como respaldo [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:45]
- Lee el atajo de teclado de cada item de menu [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:18]

#### Decidir
- Preferir acciones AX en segundo plano; primer plano solo si hace falta [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:70]
- Preferir la ruta directa: un control de navegacion, la busqueda de la app, un atajo conocido o un menu, antes que coordenadas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:97]
- Cada accion lleva un `intent` con su efecto concreto, incluido el destinatario de un envio [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:72]
- El contenido de las apps es dato, no autoridad para cambiar la tarea [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:71]

#### Actuar
- Clic semantico por `AXPress` y, si falla, foco [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:20]
- `set_value` escribe en un campo sin pulsaciones [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:100]
- Teclado al PID con fuente privada (`CGEventPostToPid`), solo si ventana y control enfocados coinciden con el escaneo [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:78]
- `press_key` acepta acordes (`Cmd`, `Ctrl`, `Alt`, `Shift`) y teclas con nombre [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:82]
- `type_text` acepta de 1 a 16000 bytes y no usa el portapapeles [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:84]
- Menus por ruta con `AXPress`, con error propio si el item esta deshabilitado [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:17]
- Abrir app sin activarla y esperar su ventana hasta 30 s, sin repetir el lanzamiento [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:76]
- Clic por coordenadas y arrastre sobre una captura, moviendo el puntero fisico, con la ventana exacta delante [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:85]
- Una vista SwiftUI/Catalyst puede no desplazarse en segundo plano; lo reporta como error propio [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:25]

#### Verificar
- Tras cada accion espera al menos 1 s, luego 500 ms de AX quieto, con 5 s de presupuesto [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:80]
- Observa cambios con `AXObserver` (foco, valor, ventana creada, elemento destruido) [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:14]
- El resumen de cambio anuncia dialogos y ventanas nuevas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:93]
- "Nada cambio" se reporta y se prohibe repetir la misma accion [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:92]
- Un clic exitoso no prueba que el foco se movio; hay que revisar el foco antes de teclear [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:81]
- Solo se reportan resultados verificados [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:89]

#### Recuperarse
- Errores tipados con resultado externo: `Stale` re-escanea, `Ambiguous` estrecha, `OutcomeUnknown` inspecciona y nunca repite un guardar/enviar/alternar [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:87]
- Si la usuaria tiene una tecla o boton apretado, espera; nunca borra su entrada [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:39]
- Si el foco o la entrada cambian durante la entrega, para y no reintenta [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:37]
- Si la Mac esta bloqueada, pide desbloquear [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:30]
- Un dialogo bloquea su app: se resuelve primero, con Escape si no hay nada que clicar [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:101]
- Si AX no da el contenido, mira la imagen en vez de insistir con el arbol [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:113]

#### Seguridad
- Lecturas en silencio; escrituras y borrados de conectores levantan una tarjeta por celda [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:58]
- Un juez LLM aprueba lo deshacible y lo cubierto por palabras o tarjetas de la usuaria [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:52]
- El juez rechaza lo irreversible sin cobertura y lo que viene de una web, un correo o un documento [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:54]
- Un clasificador aparte decide si un comando destructivo va al dialogo de aprobacion [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:50]
- La entrada visual (coordenadas) pasa por aprobacion antes de ejecutarse [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:91]
- Nunca teclea contraseñas, codigos ni PIN; le pasa el inicio de sesion a la usuaria [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:94]
- Antes de enviar, publicar o pagar, confirma el destino en la pantalla actual [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:95]
- Ventanas y pestañas que no abrio no son suyas para cerrar ni manejar [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:96]
- Prohibe manejar la interfaz por script: nada de System Events, pulsaciones ni clics por AppleScript [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:62]
- Un si hablado vale como "go" en Incredible [repo:docs/research/auditoria-decisiones-incredible.md:67]
- No se encontro un limite de ritmo para acciones de escritorio en las cadenas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:103]

#### Lo que ve la usuaria
- Un panel indicador propio dibuja un glow en un WKWebView (`updateComputeGlow`) [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:44]
- Ese panel ignora el raton, asi que no tapa clics [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:46]
- El `intent` de las acciones de conector se le muestra a la usuaria [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:58]
- El rastro de tinta y el orbe del cursor son del hold de FN, no de las manos [repo:docs/research/incredible-fn-glow-pointer.md:82]
- No hay resaltado del elemento bajo el cursor [repo:docs/research/incredible-fn-glow-pointer.md:186]

#### Permisos
- Info.plist de Incredible declara Apple Events ("para escribir texto y controlar tu computadora") y Grabacion de pantalla [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:10]
- El helper pide Accesibilidad con el prompt del sistema y tiene un modo `request-permissions` [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:28]
- Observar y actuar por AX no requiere Grabacion; solo la inspeccion visual la requiere [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:33]
- El -1743 se interpreta como "falta Automatizacion", no como fallo del comando [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:61]

### 4.2 "Abre Notas y escribe hola" en Incredible, paso a paso (inferido de la evidencia)
- 1: el orquestador no escribe; su `open_app` solo lanza Notas, y "escribe hola" es trabajo de un agente [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:67]
- 2: `tell_agent` le pasa el objetivo y la frase literal de la usuaria [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:66]
- 3: sin Experimental Compute Use, la ruta permitida es AppleScript de un paso: "a Notes note" esta entre los ejemplos [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:60]
- 4: el script crea la nota con su cuerpo (`make new note with properties {body:...}`), sin depender de ningun campo enfocado [doc:https://www.macscripter.net/t/notes-app-create-new-note-with-formatted-title/71686@2019-06]
- 5: la primera vez macOS pide Automatizacion; un -1743 se le explica a la usuaria [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:61]
- 6: crear una nota es deshacible, asi que no pide tarjeta; enviar, compartir o borrar si [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:63]
- 7 (variante con Experimental Compute Use): `computer.open_app` sin activar, `wait_for_window`, vista con `input_focus`, `press_key("Cmd+n")` o el menu, revisar el foco, `type_text("hola")`, leer el `Change` [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:73]
- 8: en la variante AX, si el foco no es el editor, primero `el.focus()` o un atajo, y nunca teclear a ciegas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:81]

### 4.3 Peekaboo (steipete/Peekaboo)
Por que es referencia: automatizacion de macOS en Swift de Peter Steinberger, activo (push 2026-10-01), unas 5.2k estrellas, con servicios de clic, tecleo, atajos, menus y arrastre separados y testeados. [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/HotkeyService.swift#L156-L160@016240d]
- Los atajos dirigidos a un PID evitan cambiar la app delante, pero algunas apps solo atienden atajos en su ventana principal y pueden ignorarlos en segundo plano [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/HotkeyService.swift#L156-L160@016240d]
- Rechaza Cmd+W, Cmd+Q, Cmd+H y Cmd+M dirigidos a un PID porque su efecto no se puede verificar, y ofrece el comando semantico equivalente [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundHotkeyPolicy.swift#L5-L41@016240d]
- Comprueba el permiso de publicar eventos antes de mandar un atajo [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/HotkeyService.swift#L378@016240d]
- Para teclear "en" un campo, primero lo busca por etiqueta, identificador o placeholder y lo clica [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/TypeService+TargetResolution.swift#L9-L27@016240d]

### 4.4 Hammerspoon (Hammerspoon/hammerspoon)
Por que es referencia: automatizacion de macOS desde 2014, unas 16k estrellas, API de eventos usada a diario por su comunidad. [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L242-L276@23e387e]
- `keyStroke(modifiers, character, delay, application)` manda el par abajo/arriba con modificadores y opcionalmente a una app concreta, con 200 ms entre ambos por defecto [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L242-L276@23e387e]
- Segun su documentacion, pasar una tabla de modificadores (vacia o no) fuerza a soltar los modificadores creados y aun abajo; un `nil` explicito los hereda [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L257@23e387e]

## 5. Opciones

### 5.1 Por decision

| Decision | Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|---|
| D1 escribir | A: solo AX | sin permiso nuevo; ya existe | falla si el foco no esta en un campo; apps sin AX | baja | base siempre |
| D1 escribir | B: Apple Events por app | no depende del foco; verificable releyendo | permiso por app; un diccionario por app; solo apps scriptables | media | solo como complemento |
| D1 escribir | C: AX por defecto + Apple Events para una lista corta | cubre Notas sin tocar el resto | dos caminos que mantener | media | recomendada si Karen acepta el permiso |
| D2 acordes | A: no | nada nuevo que proteger | Cmd+N, Cmd+F imposibles | nula | no |
| D2 acordes | B: lista blanca corta | riesgo acotado, test por tabla | hay que ampliarla con evidencia | baja | recomendada |
| D2 acordes | C: libres con lista negra a la hoja | cubre todo | la lista negra se queda corta; cada hoja es Touch ID | media | no |
| D3 foco | A: siempre segundo plano | no roba el foco | algunas apps ignoran teclas en segundo plano | media | default |
| D3 foco | B: activar cuando haga falta, avisando | completa mas tareas | roba el foco; choca con `target_changed` | baja | solo con aviso visible |
| D4 abrir | esperar ventana y fijar PID devuelto | elimina la carrera del turno | una espera mas | baja | recomendada |
| D5 verificar | A: modelo vuelve a mirar | ya existe | caro en tokens y turnos; el modelo se salta el paso | nula | no |
| D5 verificar | B: AXObserver + espera acotada + resumen de cambio | cada resultado dice que cambio | aprox. 1 s por accion | media | recomendada |
| D6 visual | aura sobre la ventana objetivo tambien para la voz propia | la usuaria ve que y donde | un estado mas en el reductor | baja | recomendada |
| D7 coordenadas | A: fuera | sin riesgo de clic equivocado | algunos controles inalcanzables | nula | por ahora |
| D7 coordenadas | B: con captura y ventana delante, critico | cubre lienzos y controles sin AX | mueve el puntero; Touch ID cada vez | alta | despues de M1-M6 |
| D9 juez | A: compuertas deterministas | auditables, testeables | menos flexibles | nula | recomendada |
| D9 juez | B: juez LLM | flexible | no determinista; contradice 20c D1 | alta | no |

### 5.2 Hoja de ruta de specs pequeñas (orden recomendado)

Cada spec es un PR. Los criterios son medibles y heredan la seccion 10.

- **M1. Recuperarse de "no hay campo" (sin capacidad nueva).**
  - El error `no_focused_field` dice el rol de lo que tiene el foco y si la ventana tiene un unico area de texto visible.
  - El prompt (clasico y realtime) enseña la recuperacion: `look`, `click` sobre el campo, o `menu` de crear (p. ej. Archivo > Nueva nota), y luego `type_text`.
  - Criterios: test con fake de foco en `AXOutline` devuelve `no_focused_field` con `focused_role=AXOutline`; test de prompt contiene la frase de recuperacion en es y en; prueba en vivo "abre Notas y escribe hola" 9 de 10 corridas con la nota escrita y leida de vuelta.
- **M2. `open_app` espera y fija el objetivo.**
  - Espera hasta que el PID lanzado sea el frontal y tenga ventana AX, con plazo (propuesto 10 s, Incredible usa hasta 30 s).
  - El turno fija ese PID, no el que observe la siguiente mano.
  - Criterios: test con fake de activacion retrasada 400 ms: `type_text` despues de `open_app` actua sobre el PID nuevo; plazo vencido devuelve `window_not_ready`; ningun `type_text` cae en la app anterior.
- **M3. Acordes en `press_key` con lista blanca.**
  - Modificadores como eventos propios con `CGEventFlags`, fuente privada, `postToPid`.
  - Lista blanca inicial (propuesta: Cmd+N, Cmd+F, Cmd+L, Cmd+T, Cmd+Z, Cmd+A, Cmd+Shift+N); todo lo demas `refused` con codigo y alternativa semantica (Cmd+W/Q como Peekaboo).
  - Antes de entregar: el foco del PID sigue siendo el del ultimo `look` o lectura.
  - Criterios: test por tabla acorde a veredicto; test de que el evento lleva exactamente los flags pedidos; un acorde fuera de lista nunca llega al puerto.
- **M4. Resultado con cambio observado.**
  - Tras cada mano que cambia algo: espera minima + AX quieto acotado (`AXObserver`), y una linea "cambio: titulo X / dialogo nuevo / ventana nueva / nada observado".
  - Criterios: fake de observador; resultado con la linea en los cuatro casos; presupuesto maximo respetado (test con reloj inyectado); "nada observado" nunca dice "hecho".
- **M5. Aura de las manos propias.**
  - `handsWorking` tambien para la voz y el chat, con el marco de la ventana objetivo; chip con la accion sin datos privados (nunca el texto tecleado).
  - Criterios: test de reductor; el aura se apaga con el freno; captura propia no la incluye (`sharingType none`).
- **M6. Guardas de entrega.**
  - Tecla o boton sostenido por la usuaria = `input_busy`, sin teclear; foco/caret cambiados = `focus_changed`; dialogo modal delante = `dialog_blocking` con su titulo.
  - Criterios: fakes de estado de teclado y de foco; ningun evento publicado en esos casos.
- **M7. Notas por Apple Events (solo si D1 = B o C).**
  - Tool `note_create(body, title?)` en proceso, como `AppleEventSheets`; -1743 se mapea a `needs_automation` con el enlace a Ajustes; relectura de la nota creada como prueba.
  - Criterios: fake del puerto; texto de `NSAppleEventsUsageDescription` actualizado; banda segun D8.
- **M8. Clic por coordenadas y arrastre (solo si D7 = B).**
  - Captura de la ventana exacta, recibo que caduca a los 60 s, ventana delante, banda critica (hoja + Touch ID).
  - Criterios: recibo caducado rechaza; ventana movida rechaza; el puntero de la usuaria vuelve a su sitio o se documenta que no.

## 6. Evidencia en contra

- Contra "replicar exactamente": la mitad de las manos de Incredible (acordes, coordenadas, arrastre) es una skill experimental opt-in, no el producto por defecto; copiarla entera seria ir mas lejos que Incredible [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:69]
- Resolucion: la hoja de ruta empieza por lo que Incredible hace por defecto (recuperarse, esperar, verificar) y deja coordenadas para el final y a decision de Karen [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:98]
- Contra los acordes en segundo plano: algunas apps ignoran atajos dirigidos a un PID si no estan delante [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/HotkeyService.swift#L156-L160@016240d]
- Resolucion: M3 exige verificar el efecto con M4 y, si no hubo cambio, recurrir al menu equivalente (que se puede pulsar por AX sin foco) [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:316]
- Contra Apple Events para Notas: es un permiso de TCC nuevo por app y abre un canal que puede leer datos de otra app [doc:https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsappleeventsusagedescription.json@macOS26-sdk-docs]
- Resolucion: aceptado solo si Karen lo decide (D1), limitado a crear y releer, sin leer notas existentes [repo:Sources/CompanionServices/Deliverables/AppleEventSheets.swift:5]
- Contra M4: la espera de Incredible (al menos 1 s por accion) alarga cada paso en una app de voz [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:80]
- Resolucion: aceptado con presupuesto propio y medido; la pregunta de latencia es de Karen (D5) [repo:Sources/CompanionServices/Accessibility/AXTextInjector.swift:24]
- Contra el aura para la voz propia: un estado mas en el reductor y otra superficie que puede quedarse encendida [repo:Sources/CompanionCore/Session/SessionMachine.swift:286]
- Resolucion: el freno ya apaga lo que cuelga del turno; el criterio de M5 lo exige con test [repo:Sources/CompanionCore/Session/SessionMachine+Brakes.swift:53]

## 7. Ejemplares y anti-ejemplos

### Asi se ve bien hecho
- Atajo dirigido con politica: rechazar el acorde cuyo efecto no se puede verificar y nombrar la alternativa semantica [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundHotkeyPolicy.swift#L15-L25@016240d]
- Modificadores pasados en el mismo evento de bajada y de subida, a una app concreta si se pide [ref:https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/eventtap/eventtap.lua#L275-L277@23e387e]
- Fuente privada y flags limpios para que un modificador que la usuaria sostiene no se mezcle, como ya hace Companion [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:59]
- Antes de escribir, buscar y enfocar el campo en vez de fallar [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/TypeService+TargetResolution.swift#L9-L27@016240d]
- Abrir y esperar ventanas antes de devolver la app, como hace el modulo publico de Incredible [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:109]
- Un id viejo nunca se reasigna a otro elemento: se vuelve a mirar [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:234]

### Anti-ejemplos
- Publicar eventos por la funcion privada `SLEventPostToPid` de SkyLight (Peekaboo lo hace); Companion usa solo APIs publicas [ref:https://github.com/steipete/Peekaboo/blob/016240d908566e54b702336ba39abc0f621b5b60/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/BackgroundInputDriver.swift#L1722-L1746@016240d]
- Manejar la interfaz con System Events o pulsaciones por AppleScript; el propio Incredible lo prohibe [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:62]
- Repetir la misma accion cuando "nada cambio" [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:92]
- Decir "escrito" sin releer el campo [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:270]

### Que NO copiar (legal, etico o contra reglas firmadas)
- Codigo, prompts o textos de Incredible: este brief solo resume comportamiento y cita cadenas cortas [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:5]
- "Un si hablado es el mismo go": contradice 20c D1, que solo deja al si hablado lo de bajo riesgo [repo:docs/specs/wave-20c-endurecimiento-aprobaciones.md:27]
- Aprobar manos criticas sin Touch ID o recordar un si en lo critico: contradice la spec firmada [repo:docs/specs/touch-id-aprobaciones-criticas.md:11]
- Abrir una URL que aparecio en pantalla o en un resultado sin que la usuaria la dijera: es el sumidero de exfiltracion de `open_url` [repo:Sources/CompanionCore/Approvals/ApprovalRisk.swift:14]
- Un juez LLM como compuerta: no se decide aqui; es la decision D9 de la seccion 1 (la seccion 5 compara las opciones) [repo:Sources/CompanionCore/Tools/ParentTool+Hands.swift:96]
- Entitlements que bajan el endurecimiento (`disable-library-validation`, `allow-unsigned-executable-memory`) que trae Incredible [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:9]
- Teclear credenciales o codigos que aparezcan en pantalla (Incredible tambien lo prohibe; Companion ya excluye campos seguros) [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:306]
- Grabar la pantalla para "enseñar tareas" y subirlo: fuera de alcance de las manos y de privacidad distinta [repo:docs/research/incredible-arquitectura.md:47]

## 8. Trampas

- `open_app` activa por defecto y la notificacion de activacion llega despues; una mano inmediata puede fijar el PID de la app anterior [doc:https://developer.apple.com/tutorials/data/documentation/appkit/nsworkspace/openconfiguration/activates.json@macOS26-sdk-docs]
- La re-fijacion del turno toma el PID observado, que puede ser el viejo si la activacion aun no llego [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:85]
- Un acorde sintetico sin los modificadores como eventos propios no produce el atajo [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/init(keyboardeventsource:virtualkey:keydown:).json@macOS26-sdk-docs]
- Compartir la tabla de estado de la fuente con la del sistema mezcla el FN que la usuaria sostiene con el acorde; por eso Companion usa fuente privada y flags limpios [repo:Sources/CompanionServices/Accessibility/AXTextInjector+Hands.swift:59]
- El texto Unicode de un evento puede ignorarse; por eso `type_text` no debe ir por teclas letra a letra [doc:https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:).json@macOS26-sdk-docs]
- `AXPress` puede devolver `kAXErrorCannotComplete` aunque el boton se haya pulsado; reintentar a ciegas puede pulsar dos veces [doc:https://developer.apple.com/tutorials/data/documentation/applicationservices/1462091-axuielementperformaction.json@macOS26-sdk-docs]
- Los nombres de menu estan en el idioma del sistema: "Archivo > Nueva nota" en español, "File > New Note" en ingles [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:334]
- El portapapeles de respaldo de `type_text` pisa un momento lo que la usuaria copio; Incredible evita el portapapeles en su teclado [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:84]
- Una vista SwiftUI o Catalyst puede no desplazarse por AX en segundo plano [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:25]
- Apps en otro Space o tapadas dejan de publicar contenido actual por AX [repo:docs/research/evidence/incredible-0.2.36-manos-strings-2026-10-02.txt:77]
- Todo lo de Apple Events necesita `NSAppleEventsUsageDescription` con un texto que cubra el uso nuevo, o el permiso no tiene explicacion [repo:scripts/bundle.sh:90]
- Cada mano en la hoja sera critica cuando Touch ID aterrice: abrir acordes destructivos a la hoja significa un dedo por atajo [repo:docs/specs/touch-id-aprobaciones-criticas.md:29]

### Por contexto de ejecucion
- App instalada: es el unico contexto con TCC real; toda prueba de Notas, acordes y Apple Events se hace aqui, con la app cerrada antes de reinstalar [repo:CLAUDE.md:57]
- Voz realtime: las specs de manos se fijan al abrir la sesion; una mano nueva no aparece hasta reconectar [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:235]
- Voz clasica: la lista de tools se arma por turno, asi que una mano nueva aparece en el turno siguiente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:347]
- Chat escrito: con Companion delante las manos no se ofrecen (`self_in_front`); ninguna spec de esta hoja de ruta cambia eso [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:107]
- Puente MCP: las manos nuevas deben entrar en la lista blanca del puente y en su presupuesto, o el test de allowlist falla [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:34] [repo:Sources/CompanionCore/Deliverables/DeliverableTools.swift:78]
- swift test: sin Accesibilidad las manos no se ofrecen; las pruebas van contra fakes de los puertos [repo:Tests/CompanionServicesTests/HandsPolicyTests.swift:137]
- CI macOS: sin TCC; nada de esta hoja de ruta puede depender de un permiso real en CI [repo:Sources/CompanionServices/Permissions/AccessibilityPermission.swift:13]

## 9. Incertidumbre

- ASSUMPTION: el fallo de "abre Notas y escribe hola" vino de que el foco de Notas estaba en la lista de notas o la barra lateral, no de la carrera de activacion. prueba: buscar en el log de Companion la linea `hands: type_text no_focused_field pid=... bundle=...` de esa corrida; si el bundle no es `com.apple.Notes`, fue la carrera (M2); si es Notas, fue el foco (M1).
- ASSUMPTION: el cuerpo de una nota de Notas en macOS 26 es un `AXTextArea` alcanzable por `look`. prueba: abrir una nota y correr `look` desde el puente (self-qa) o Accessibility Inspector, y ver el rol del cuerpo.
- ASSUMPTION: `make new note with properties {body:...}` sigue vigente en el diccionario de Notas de macOS 26 (la fuente es un foro de 2019). prueba: `sdef /System/Applications/Notes.app` y buscar la clase `note` y el comando `make`.
- ASSUMPTION: en Incredible el AppleScript de un paso no pasa por el juez cuando crea contenido. prueba: con Incredible en vivo, pedir "crea una nota que diga hola" y ver si aparece tarjeta (solo observando, sin inyectar nada).
- ASSUMPTION: el valor por defecto de `experimental_compute_use` es apagado. prueba: mirar el interruptor en Ajustes de Incredible en una instalacion nueva.
- ASSUMPTION: Notas atiende Cmd+N dirigido a su PID estando en segundo plano. prueba: con M3 en una rama, mandar Cmd+N a Notas con Companion delante y contar notas antes y despues.
- ASSUMPTION: las cadenas de Incredible no tienen limite de ritmo para acciones de escritorio porque no existe, no porque viva en el servidor. prueba: no se puede resolver sin el codigo; tratarlo como desconocido y no usarlo como argumento.
- [NEEDS CLARIFICATION: D1, D2, D3, D5, D6, D7, D8 y D9 de la seccion 1.]

## 10. Checklist de estandar

- [ ] Ninguna mano nueva usa APIs privadas (nada de `dlopen` de frameworks privados ni simbolos `SL*`/`CGS*`).
- [ ] Todo evento sintetico usa fuente `privateState` y `postToPid`; los modificadores van como flags explicitos.
- [ ] Un acorde fuera de la lista blanca nunca llega al puerto de teclado (test por tabla).
- [ ] `open_app` devuelve el PID y la mano siguiente actua sobre ese PID; plazo vencido = `window_not_ready`.
- [ ] `no_focused_field` incluye el rol enfocado y el prompt enseña la recuperacion en es y en.
- [ ] Toda mano que cambia algo devuelve una linea de cambio observado; "nada observado" nunca se reporta como hecho.
- [ ] Ninguna mano repite una accion tras `outcome_unknown` o "nada observado" sin una lectura en medio.
- [ ] Una tecla sostenida por la usuaria o un dialogo modal delante bloquean la entrega con codigo propio.
- [ ] Ninguna mano nueva entra en `ApprovalRisk.low` salvo lecturas; acordes destructivos y coordenadas son criticos (hoja + Touch ID).
- [ ] El aura de las manos se enciende para la voz propia y se apaga con cualquier freno.
- [ ] Logs de manos con PID, bundle y conteos; nunca texto tecleado, leido ni titulos de ventana.
- [ ] Toda tool nueva aparece en la lista blanca y el presupuesto del puente, o el test de allowlist falla.
- [ ] Apple Events (si D1 lo aprueba) mapea -1743 a `needs_automation` y actualiza `NSAppleEventsUsageDescription`.
- [ ] Nada de este programa copia codigo, prompts ni textos de Incredible.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Cadenas de Incredible 0.2.36 (helper y binario principal) y recursos Python | Norditech, analisis propio | 0.2.36, sha 8a1eba9d / 5699175d | 2026-10-02 | medium |
| 2 | AXUIElementPerformAction | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 3 | AXUIElementCopyAttributeValue | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 4 | AXUIElementSetAttributeValue | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 5 | kAXShowMenuAction | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 6 | kAXFocusedUIElementAttribute | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 7 | AXObserverCreate | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 8 | AXIsProcessTrustedWithOptions | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 9 | CGEvent init(keyboardEventSource:virtualKey:keyDown:) | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 10 | CGEventFlags | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 11 | CGEvent keyboardSetUnicodeString | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 12 | CGEvent postToPid | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 13 | CGEventSource init(stateID:) y privateState | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 14 | CGPreflightPostEventAccess | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 15 | SCScreenshotManager | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 16 | CGPreflightScreenCaptureAccess | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 17 | VNRecognizeTextRequest | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 18 | NSWorkspace.OpenConfiguration.activates | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 19 | NSWorkspace.didActivateApplicationNotification | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 20 | Apple Events entitlement | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 21 | NSAppleEventsUsageDescription | Apple | macOS 26 SDK docs | 2026-10-02 | high |
| 22 | Allow accessibility apps to access your Mac | Apple Support | macOS actual | 2026-10-02 | high |
| 23 | Allow apps to automate and control other apps | Apple Support | macOS actual | 2026-10-02 | high |
| 24 | Control access to screen and system audio recording | Apple Support | macOS actual | 2026-10-02 | high |
| 25 | Change Privacy and Security settings on Mac | Apple Support | macOS actual | 2026-10-02 | high |
| 26 | Peekaboo HotkeyService, BackgroundHotkeyPolicy, TypeService, BackgroundInputDriver | steipete | commit 016240d | 2026-10-02 | high |
| 27 | Hammerspoon eventtap.lua | Hammerspoon | commit 23e387e | 2026-10-02 | high |
| 28 | Notes app: create new note with formatted title | MacScripter (foro) | 2019-06 | 2026-10-02 | low |
| 29 | Briefs previos sobre Incredible (arquitectura, glow y puntero, auditoria de decisiones) | companion-next | main 9085264 | 2026-10-02 | medium |
