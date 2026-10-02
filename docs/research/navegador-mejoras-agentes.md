# Reference Brief: mejoras del control del navegador (extension MV3 + lado host) contra Incredible y agentes de navegador profesionales

Slug: navegador-mejoras-agentes | Nivel: deep | Fecha: 2026-10-02 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Pregunta: como mejorar el control del navegador de Companion (extension MV3 en `Extensions/browser/` y el lado Swift: `BrowserToolRunner`, `BrowserHost`, `BrowserSanitize`, `BrowserToolRunner+Gates.swift`, `page.js`, `wire.js`) para cerrar los 8 hallazgos HIGH, los 9 MEDIUM y los 8 LOW de la auditoria del 2026-10-02, con dos varas: Incredible como piso minimo (directiva relayada por el orquestador, no palabra citada de Karen) y los agentes de navegador open source profesionales.

Entrada: `~/Desktop/incredible-ref/audits/auditoria-extension-navegador-2026-10-02.md` (sha256 que empieza en 9d429828792f). La auditoria se hizo sobre otro checkout (`296c330`); cada linea citada abajo se releyo en este worktree.

Fuera de alcance, ya en curso en otras ramas (no se duplican):
- `browser-read-menu-abierto` (rama `fix/browser-read-open-menu`, ESCALADO): la lectura CON selector de un `[role=menu]`/`[role=listbox]` abierto, y por que canal llega la "siguiente accion" de un error (su D2/D3). Este brief adopta su canal (codigo en la allowlist de Core + copia bilingue) y solo agrega la lista completa de codigos que los HIGH necesitan.
- `bridge-companion-cerrado`: el puente con la app cerrada. Toca M-9 y L-6 (relanzado del host con la app apagada); aqui solo se nombran.

Comparaciones con Incredible que NO se pueden hacer: su extension de navegador no esta instalada en esta Mac. No se puede observar como redacta los errores del navegador, como representa menus, `aria-expanded`, scroll o foco dentro del DOM, ni su reconexion. Lo unico disponible de Incredible es (a) las cadenas legibles de su helper de accesibilidad de escritorio (no el de navegador), (b) la lista de modulos del binario principal, que muestra un subsistema de navegador con contrato propio, politica de privacidad, paso de consentimiento y vista con referencias de elementos, sin su comportamiento, y (c) el resumen de su extension 1.17.3 escrito en la spec 18b. Toda paridad de abajo es "por analogia con el helper de escritorio", nunca "Incredible lo hace asi en el navegador".

Decisiones grises (una investigacion por bloque; opciones en la seccion 5, decisiones de Karen en la seccion 9):

- G1. Codigos de error que llegan al modelo (H-2, H-3, M-1, M-2, M-3). Toca el contrato extension-Core.
- G2. Identidad del elemento entre leer y actuar (H-1, H-8). Toca el trust boundary (que se pulsa vs. que se aprobo).
- G3. Que ve el modelo en un read sin selector: visibilidad, estado ARIA, orden y truncado (H-4). Agregar campos a `BrowserElement` toca el contrato.
- G4. Saltos de linea al escribir (H-5). Toca el gate: un Enter real envia formularios.
- G5. Esperar la carga en open/navigate y exponer el estado (H-6).
- G6. Manos nuevas: elegir opcion de `select`, tecla, scroll (H-7). Tools nuevas por el puente y por el chat: contrato, gate y permisos.
- G7. Higiene de prompt injection del texto de pagina (M-6, M-7, L-4, L-8). Trust boundary.
- G8. El permiso `debugger` sin ADR (M-8). Permisos.
- G9. Pestana recuperada por la usuaria y tomar en el chat sin hoja (M-4, M-5). M-5 reabre una decision firmada (18b D1).

## 2. Estado actual

Contextos: app instalada (/Applications/Companion.app, que tambien es el host nativo: Chrome o Comet lanzan el mismo binario y bifurca antes de AppKit), service worker MV3 de la extension en Chrome y Comet (minimo 116, scripts en mundo ISOLATED, CDP via chrome.debugger), swift test (CompanionCoreTests y CompanionServicesTests contra el canal falso BrowserCommanding), node --test de Extensions/browser/test (chrome y DOM falsos: sin render, sin CDP, sin elementFromPoint real), el puente MCP (bridgeRunner con las mismas browser_* y su propio caller), CI via scripts/gates.sh (node --test solo si hay node; sin node es aviso)

### Contexto de ejecucion y pruebas

- El binario de la app bifurca al modo host nativo antes de AppKit, Config o Keychain cuando Chrome lo lanza [repo:Sources/CompanionApp/CompanionMain.swift:14]
- `scripts/gates.sh` corre `node --test` sobre cada `*.test.js` de la extension solo si existe `node` [repo:scripts/gates.sh:309]
- El runner habla con la extension por el protocolo `BrowserCommanding`, la costura que usan los tests Swift con un canal falso [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:7]
- El arnes de `background.test.js` es un `chrome` falso que registra cada llamada; no hay navegador real [repo:Extensions/browser/test/background.test.js:9]
- Las pruebas de `page.js` usan nodos falsos; la de visibilidad solo prueba `display:none` en el propio nodo [repo:Extensions/browser/test/page.test.js:269]
- El manifiesto pide Chrome 116 como minimo [repo:Extensions/browser/manifest.json:7]
- Permisos declarados: `nativeMessaging`, `scripting`, `alarms`, `tabGroups`, `storage` y `debugger`; sin `tabs` [repo:Extensions/browser/manifest.json:8]

### G1, codigos de error

- Core deja pasar solo una allowlist de codigos; `debugger_revoked` y `debugger_unavailable` no estan en ella [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:13]
- Un codigo fuera de la lista se convierte en `browser_error` [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:20]
- El codec aplica la allowlist al decodificar el error de la extension [repo:Sources/CompanionCore/Browser/BrowserCodec.swift:40]
- `failed` reemplaza el mensaje de la extension por la copia de Core elegida por codigo [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:238]
- La copia de `invalid_args` es generica y no nombra accion siguiente [repo:Sources/CompanionCore/Browser/BrowserCopy.swift:97]
- Un codigo desconocido cae en "The browser failed: code" [repo:Sources/CompanionCore/Browser/BrowserCopy.swift:99]
- La extension emite `debugger_revoked` cuando la usuaria pulso Cancelar en el banner [repo:Extensions/browser/background.js:332]
- La extension emite `debugger_unavailable` con el mensaje crudo de Chrome cortado a 200 [repo:Extensions/browser/background.js:335]
- Un read de una pestana inexistente responde `invalid_args`, no `stale_id` [repo:Extensions/browser/background.js:245]
- Una pagina no inyectable (chrome://, visor PDF) responde `invalid_args` [repo:Extensions/browser/background.js:255]
- Cualquier excepcion de `dispatch` sale como `invalid_args` [repo:Extensions/browser/background.js:106]
- El read solo libera la lease ante `stale_id`, asi que "no such tab" bajo `invalid_args` no la libera [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:151]
- `take` traga el error de `ensureAttached` y responde `taken` igual [repo:Extensions/browser/background.js:175]
- El host concede la lease ante cualquier exito de `take` [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Lease.swift:171]
- El timeout de la extension responde `timeout` aunque la accion en la pestana no se pueda cancelar [repo:Extensions/browser/background.js:98]
- Un clic no confirmado solo deja un `console.warn` y se informa como hecho [repo:Extensions/browser/background.js:361]
- Los tests Swift fijan que un codigo desconocido es `browser_error` [repo:Tests/CompanionCoreTests/BrowserSanitizeTests.swift:42]
- El test de endurecimiento del canal fija lo mismo de punta a punta [repo:Tests/CompanionServicesTests/BrowserChannelHardeningTests.swift:20]
- `BridgeCode` ya define `target_changed`, que las manos de escritorio usan [repo:Sources/CompanionCore/Bridge/BridgeProtocol.swift:175]
- Las manos de escritorio devuelven `target_changed` cuando la app del frente cambio [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:248]

### G2, identidad del elemento

- `lookup` solo comprueba la generacion y `isConnected` [repo:Extensions/browser/lib/page.js:215]
- `locate` devuelve `label` y `role` del momento del clic [repo:Extensions/browser/lib/page.js:336]
- `pressElement` usa `spot.label` solo para el cursor y no lo compara con nada [repo:Extensions/browser/background.js:355]
- Justo antes de pulsar se repite la prueba de cobertura (`hitsAt`), no la de identidad [repo:Extensions/browser/background.js:356]
- El ticket de Core queda atado a la etiqueta del read [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:199]
- El veredicto del clic se calcula sobre la etiqueta y el `href` cacheados [repo:Sources/CompanionCore/Browser/BrowserPolicy+Verdicts.swift:7]
- El `menu` de escritorio vuelve a resolver al pulsar y exige el mismo titulo aprobado [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:316]
- En un iframe el clic va directo al camino sintetico, sin `hitsAt` ni `landing` [repo:Extensions/browser/background.js:371]
- Tras `offscreen` el respaldo es un clic sintetico sobre el nodo [repo:Extensions/browser/background.js:384]

### G3, lo que ve el modelo

- `INTERACTIVE` lista etiquetas y roles accionables [repo:Extensions/browser/lib/page.js:13]
- `isVisible` mira `hidden`, `display` y `visibility` del propio elemento, no de sus ancestros [repo:Extensions/browser/lib/page.js:272]
- `serializeElement` no emite `aria-expanded`, `aria-checked`, `aria-selected`, `aria-pressed`, `disabled` ni `aria-haspopup` [repo:Extensions/browser/lib/page.js:194]
- `BrowserElement` en Core no tiene campos de estado [repo:Sources/CompanionCore/Browser/BrowserProtocol.swift:100]
- `trimPage` conserva los primeros N elementos en orden de DOM con el 60% del presupuesto [repo:Extensions/browser/lib/wire.js:80]
- El texto es `body.innerText`, donde un portal al final de `body` queda al final [repo:Extensions/browser/lib/page.js:298]
- Core vuelve a cortar la lectura a 48000 bytes [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:20]
- El render de una linea de elemento muestra rol, etiqueta, frame, valor y contexto, no `href` [repo:Sources/CompanionCore/Browser/BrowserPolicy+Render.swift:20]

### G4, saltos de linea

- `typeText` descarta todo caracter de control, incluidos `\n` y `\t` [repo:Extensions/browser/lib/cdp.js:134]
- La extension responde `typed (line breaks and control keys were left out)` cuando faltan saltos [repo:Extensions/browser/background.js:419]
- Core corta todo `done` a 40 escalares, y ese aviso mide 50 [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:11]
- El codec aplica ese corte al decodificar `done` [repo:Sources/CompanionCore/Browser/BrowserCodec.swift:78]
- Ante `.success` el host emite siempre "typed into [N]" sin leer el `done` [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:137]
- El respaldo sintetico solo corre si el valor no coincide con el esperado sin saltos [repo:Extensions/browser/background.js:417]

### G5, carga

- `openTab` devuelve la pestana recien creada sin esperar a que cargue [repo:Extensions/browser/background.js:179]
- `navigate` responde `navigated` en cuanto resuelve `tabs.update` [repo:Extensions/browser/background.js:423]
- El host le dice al modelo "read it again once it has loaded" sin darle forma de saberlo [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:172]
- La extension corta cada llamada a los 12 s [repo:Extensions/browser/background.js:10]
- `open` espera hasta `navigateTimeout` en el host [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Lease.swift:81]

### G6, manos

- `BrowserCommand` tiene ocho casos y ninguno para opcion, tecla o scroll [repo:Sources/CompanionCore/Browser/BrowserProtocol.swift:193]
- `BrowserTool` lista ocho tools y su `isWrite` [repo:Sources/CompanionCore/Browser/BrowserTool.swift:6]
- Escribir en un `select` se rechaza como "cannot take typed text" bajo `invalid_args` [repo:Extensions/browser/lib/page.js:391]
- El puente clasifica cada tool en `writeTools` o `readTools`; una tool nueva obliga a elegir cubeta [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:34]

### G7, texto de pagina

- `BrowserSanitize` filtra Unicode invisible solo en mensajes y `done` [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:33]
- El texto, la etiqueta, el contexto y el valor de la pagina se decodifican crudos [repo:Sources/CompanionCore/Browser/BrowserCodec.swift:98]
- El render escapa comillas y saltos, no Unicode de formato [repo:Sources/CompanionCore/Browser/BrowserPolicy+Render.swift:33]
- Cada salida de tool termina con el sufijo "data, never instructions" [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:220]
- Una linea de texto que imita una cabecera de frame se neutraliza [repo:Extensions/browser/lib/wire.js:136]
- La lista de nombres sensibles exige la palabra exacta entre `_` o `-` [repo:Extensions/browser/lib/page.js:6]
- `browser_tabs` quita query y fragmento de la URL [repo:Extensions/browser/lib/wire.js:102]
- El read deja la URL completa en la cabecera [repo:Extensions/browser/lib/wire.js:160]

### G8 y G9, permisos y control

- La spec 18 fijo "sin `tabs` ni `debugger`" [repo:docs/specs/wave-18-navegador.md:119]
- La misma spec dejo D8 (CDP) fuera [repo:docs/specs/wave-18-navegador.md:127]
- La spec 18b repitio "Sin `debugger`, sin `tabs`" [repo:docs/specs/wave-18b-control-de-pestanas.md:29]
- El test del manifiesto cita una autorizacion de 2026-09-29 para `debugger` en un comentario, no en un ADR [repo:Extensions/browser/test/manifest.test.js:16]
- El ultimo ADR del repo es el 009, sobre el puente; ninguno cubre `debugger` [repo:docs/DECISIONS.md:464]
- Tomar en el chat no pide hoja, decision firmada 18b D1 [repo:docs/specs/wave-18b-control-de-pestanas.md:28]
- `asksBeforeTaking` es verdadero solo fuera del chat [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Lease.swift:11]
- No hay listener de `tabs.onUpdated` ni de grupos; solo `onRemoved` y `onCreated` [repo:Extensions/browser/background.js:433]
- La revocacion por Cancelar se guarda en `storage.session` y dura lo que la pestana [repo:Extensions/browser/lib/cdp.js:145]
- Tras un reinicio del worker, `attach` responde `busy` si la conexion vieja sigue abierta [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:65]

## 3. Fuentes primarias

- `chrome.debugger` define `DetachReason` con `target_closed` y `canceled_by_user` [doc:https://developer.chrome.com/docs/extensions/reference/api/debugger@2026-09-11]
- `chrome.debugger` expone a extensiones dominios como Accessibility, DOM, DOMSnapshot, Input, Page y Network [doc:https://developer.chrome.com/docs/extensions/reference/api/debugger@2026-09-11]
- `DebuggerSession` (sesiones hijas, p. ej. iframes de otro proceso) existe desde Chrome 125 [doc:https://developer.chrome.com/docs/extensions/reference/api/debugger@2026-09-11]
- El permiso `debugger` muestra las advertencias "Access the page debugger backend" y "Read and change all your data on all websites" [doc:https://developer.chrome.com/docs/extensions/reference/permissions-list@2026-09-09]
- El permiso `tabs` y el permiso `webNavigation` muestran "Read your browsing history"; `offscreen` no muestra advertencia [doc:https://developer.chrome.com/docs/extensions/reference/permissions-list@2026-09-09]
- `TabStatus` vale `unloaded`, `loading` o `complete`, y `onUpdated` trae `status` en `changeInfo` [doc:https://developer.chrome.com/docs/extensions/reference/api/tabs@2026-09-24]
- `url`, `pendingUrl`, `title` y `favIconUrl` de una pestana exigen el permiso `tabs` o permisos de host [doc:https://developer.chrome.com/docs/extensions/reference/api/tabs@2026-09-24]
- Un service worker de extension termina tras 30 s sin eventos ni llamadas a APIs de extension [doc:https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle@2023-05-02]
- Desde Chrome 105 `connectNative` mantiene vivo el service worker [doc:https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle@2023-05-02]
- Desde Chrome 118 una sesion activa de `chrome.debugger` mantiene vivo el service worker [doc:https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle@2023-05-02]
- `checkVisibility()` devuelve false si el elemento no tiene caja (`display:none` propio o de un ancestro) o un ancestro tiene `content-visibility: hidden`, y opcionalmente por opacidad o `visibility` [doc:https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility@2026-06-18]
- `Element.checkVisibility` existe en Chrome desde la 105, por debajo del minimo 116 del manifiesto [doc:https://github.com/mdn/browser-compat-data/blob/f2dd714f4923299ce2c56b7379252f78eed74417/api/Element.json#L3586@f2dd714]
- WAI-ARIA 1.2 define `aria-expanded` (abierto o cerrado), `aria-haspopup`, `aria-disabled`, `aria-checked`, `aria-selected` y `aria-pressed` como estado del control [doc:https://www.w3.org/TR/wai-aria-1.2/@REC-2023-06-06]
- CDP `Input.insertText` inserta texto que no viene de una tecla y es experimental [doc:https://github.com/ChromeDevTools/devtools-protocol/blob/3e46e43d9611a3ef508dea0024e5fe6b87d1d578/pdl/domains/Input.pdl#L141-L146@3e46e43]
- CDP `Input.dispatchKeyEvent` acepta `keyDown`, `keyUp`, `rawKeyDown` y `char` [doc:https://github.com/ChromeDevTools/devtools-protocol/blob/3e46e43d9611a3ef508dea0024e5fe6b87d1d578/pdl/domains/Input.pdl#L96-L104@3e46e43]
- CDP `DOM.getContentQuads` devuelve la posicion del nodo relativa al viewport y es experimental [doc:https://github.com/ChromeDevTools/devtools-protocol/blob/3e46e43d9611a3ef508dea0024e5fe6b87d1d578/pdl/domains/DOM.pdl#L372-L384@3e46e43]
- El dominio CDP `Accessibility` es experimental [doc:https://github.com/ChromeDevTools/devtools-protocol/blob/3e46e43d9611a3ef508dea0024e5fe6b87d1d578/pdl/domains/Accessibility.pdl#L7@3e46e43]
- Playwright define visible como caja no vacia sin `visibility:hidden`, y antes de un clic exige visible, estable, que reciba el evento y habilitado [doc:https://playwright.dev/docs/actionability@consultado-2026-10-02]
- OWASP LLM01:2025 clasifica el contenido de sitios web como inyeccion indirecta y pide separar y marcar el contenido externo, minimo privilegio y aprobacion humana para acciones de alto riesgo [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]

## 4. Implementaciones de referencia

### Por que cada una es referencia

- Playwright (Microsoft, unas 97k estrellas, push del 2026-10-02): el codigo de las tools MCP de `playwright-mcp` vive en `playwright-core/src/tools` [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/snapshot.ts#L23-L33@a47fcf5]
- chrome-devtools-mcp (equipo de Chrome DevTools en Google, unas 53k estrellas, push del 2026-10-02) [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/McpPage.ts#L815-L844@b2f522c]
- browser-use (unas 117k estrellas, MIT, push del 2026-10-02): serializa el DOM via CDP y numera elementos interactivos [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/service.py#L252-L285@62a0f71]
- Stagehand (Browserbase, unas 25k estrellas, push del 2026-10-02): ahora trae un runtime de extension MV3 con `debugger`, `tabs` y `<all_urls>` [ref:https://github.com/browserbase/stagehand/blob/a237c771fc188569bc95c1b2ed3c789950335d3a/packages/extension/manifest.json#L5-L6@a237c77]
- nanobrowser (unas 14k estrellas, Apache-2.0, push del 2026-10-02): agente dentro de una extension MV3 que maneja la pestana con puppeteer-core sobre `chrome.debugger` [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/browser/page.ts#L97-L115@ad47282]
- mcp-chrome (hangwin, unas 12k estrellas, ultimo push 2026-01-06, menos activo): servidor MCP que vive en una extension MV3 con host nativo, como Companion [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/wxt.config.ts#L40-L59@f48e715]
- Incredible: helper de accesibilidad de escritorio (no el de navegador), leido como cadenas locales; describe comportamiento, no se copia [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]
- Politica de la carpeta de referencia: replicar comportamiento con APIs publicas, sin copiar codigo ni texto propietario [ref:incredible-ref/README.md@47d55c41b5ec]

### G1, errores que nombran la accion siguiente

- Playwright: una referencia que ya no esta en el ultimo snapshot falla con un texto que pide capturar un snapshot nuevo [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L559-L582@a47fcf5]
- chrome-devtools-mcp: un uid sin snapshot pide `take_snapshot`; un nodo desaparecido dice que ya no existe [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/McpPage.ts#L815-L844@b2f522c]
- browser-use: un indice que ya no existe responde que la pagina pudo cambiar y pide refrescar el estado [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/tools/service.py#L1683-L1694@62a0f71]
- Incredible (escritorio): cada error nombra la accion siguiente; elemento caducado pide reescanear, fallo de accion pide inspeccionar el resultado antes de reintentar, y un bloqueo a mitad declara el resultado desconocido [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]
- Las tres referencias open source pasan texto libre escrito por su propio codigo, no por la pagina; Companion ya decidio que el texto de la extension no llega al modelo, asi que el patron se adopta como codigo estable + copia [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L577@a47fcf5]

### G2, identidad entre leer y actuar

- Playwright: el motor `aria-ref` devuelve el elemento del ultimo snapshot solo si sigue conectado; no compara rol ni nombre al actuar [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/injected/src/injectedScript.ts#L762-L768@a47fcf5]
- Playwright: al tomar el snapshot, una ref se reemite si el rol o el nombre del elemento cambiaron [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/injected/src/ariaSnapshot.ts#L220-L232@a47fcf5]
- Playwright: el campo `element` es una descripcion humana "para obtener permiso", que el modelo escribe y nadie verifica contra el DOM [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/snapshot.ts#L26@a47fcf5]
- chrome-devtools-mcp: resuelve el uid al nodo del snapshot y falla si se desprendio; tampoco compara rol ni nombre [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/McpPage.ts#L828-L844@b2f522c]
- Incredible (escritorio): rechaza actuar si el control cambio de rol, titulo, descripcion o identificador desde el escaneo y pide releer y encontrar el control otra vez [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]
- browser-use: entre acciones encadenadas compara URL y foco antes y despues y corta la cola si cambiaron [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/agent/service.py#L2730-L2828@62a0f71]
- nanobrowser: corta las acciones encadenadas si aparecieron elementos nuevos desde el estado leido [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/agent/agents/navigator.ts#L308-L322@ad47282]
- Playwright: refs con prefijo de frame (`f1e2`) para elementos dentro de iframes [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L562@a47fcf5]
- browser-use: la visibilidad de un nodo en iframe se calcula desplazando su caja por el offset de cada frame padre [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/service.py#L296-L346@62a0f71]

### G3, visibilidad, estado y truncado

- browser-use: sin caja de layout el nodo no es visible, y descarta `display:none`, `visibility:hidden` y opacidad 0 [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/service.py#L264-L285@62a0f71]
- mcp-chrome: visible exige `offsetWidth` y `offsetHeight` mayores que cero, que valen 0 dentro de un ancestro `display:none` [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/inject-scripts/accessibility-tree-helper.js#L135-L140@f48e715]
- Playwright: el snapshot ARIA agrega `checked`, `disabled`, `expanded`, `pressed` y `selected` segun el rol [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/injected/src/ariaSnapshot.ts#L277-L298@a47fcf5]
- browser-use: los atributos por defecto incluyen `aria-expanded`, `aria-checked`, `checked`, `selected`, `expanded`, `pressed`, `disabled` y `haspopup` [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/views.py#L18-L75@62a0f71]
- chrome-devtools-mcp: el formateador del snapshot publica los booleanos de accesibilidad (deshabilitado, expandido, enfocado, seleccionado) [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/formatters/SnapshotFormatter.ts#L183-L187@b2f522c]
- mcp-chrome: marca `disabled` en la linea del elemento [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/inject-scripts/accessibility-tree-helper.js#L566-L569@f48e715]
- browser-use: marca como nuevo (prefijo `*`) todo elemento interactivo que no estaba en el estado anterior [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/serializer/serializer.py#L750-L766@62a0f71]
- nanobrowser: marca `isNew` por hash de los elementos cliqueables del estado anterior en la misma URL [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/browser/page.ts#L341-L369@ad47282]
- Incredible (escritorio): un escaneo truncado se declara parcial y pide acotar a una ventana o un subarbol [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]

### G4, saltos de linea

- Puppeteer mapea `\n` y `\r` a la tecla Enter con texto `\r`, es decir, un Enter real que en un `input` envia el formulario [ref:https://github.com/puppeteer/puppeteer/blob/2e45a3af43231cd658285e4da5e7f53e40f24edf/packages/puppeteer-core/src/common/USKeyboardLayout.ts#L319-L321@2e45a3a]
- Playwright separa "escribir tecla a tecla" de "escribir en un editable" como tools distintas [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/keyboard.ts#L26-L89@a47fcf5]
- chrome-devtools-mcp separa `fill` (valor de campo o opcion de `select`) de `type_text` (teclado sobre el foco) [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/tools/input.ts#L386-L428@b2f522c]
- Incredible (escritorio): limita el texto por bytes, verifica el foco antes de teclear y si el foco o la entrada de la usuaria cambian a mitad no reintenta y pide inspeccionar [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]

### G5, carga

- Playwright: `navigate` espera `domcontentloaded` y luego `load` con tope de 5 s [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L353-L383@a47fcf5]
- Playwright: tras cada accion espera un asentamiento y, si hubo navegacion, el `load` con tope [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/utils.ts#L20-L57@a47fcf5]
- chrome-devtools-mcp: tras cada accion espera una navegacion posible y un DOM estable, con topes [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/utils/WaitForHelper.ts#L31-L44@b2f522c]
- nanobrowser: navegar y leer esperan red estable mas un minimo configurable [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/browser/page.ts#L1561-L1591@ad47282]

### G6, manos nuevas

- Playwright tiene `browser_select_option`, `browser_hover`, `browser_check` y `browser_uncheck` [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/snapshot.ts#L151-L171@a47fcf5]
- Playwright tiene `browser_press_key` [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/keyboard.ts#L26-L28@a47fcf5]
- chrome-devtools-mcp elige la opcion de un `select` nativo por su valor y rechaza `select` multiple o deshabilitado [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/tools/input.ts#L62-L98@b2f522c]
- chrome-devtools-mcp tiene `press_key` para atajos y teclas de navegacion [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/tools/input.ts#L605-L607@b2f522c]
- browser-use tiene `dropdown_options` y `select_dropdown` para `select` nativo y menus ARIA [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/tools/service.py#L1683-L1720@62a0f71]
- browser-use tiene `scroll` por paginas, tambien sobre un contenedor (desplegables) [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/tools/service.py#L1380-L1383@62a0f71]
- browser-use tiene `send_keys` [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/tools/service.py#L1488@62a0f71]
- nanobrowser tiene `send_keys`, `get_dropdown_options` y `select_dropdown_option` [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/agent/actions/builder.ts#L569-L683@ad47282]
- Incredible (escritorio): scroll por pagina y desplazar hasta hacer visible, estado expandido y marcado como booleanos explicitos, item de menu deshabilitado con error propio, teclas con verificacion de foco [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]

### G8, permiso `debugger` en extensiones de agente

- Stagehand declara `debugger`, `offscreen`, `scripting`, `tabs` y `<all_urls>` [ref:https://github.com/browserbase/stagehand/blob/a237c771fc188569bc95c1b2ed3c789950335d3a/packages/extension/manifest.json#L5-L6@a237c77]
- mcp-chrome declara `debugger`, `tabs`, `webNavigation`, `history`, `bookmarks`, `offscreen` y `<all_urls>`, entre otros [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/wxt.config.ts#L40-L59@f48e715]
- nanobrowser conecta puppeteer-core a la pestana con `ExtensionTransport.connectTab`, que va sobre `chrome.debugger` [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/browser/page.ts#L97-L115@ad47282]
- Stagehand mantiene vivo su worker con un documento `offscreen` y un puerto de latido [ref:https://github.com/browserbase/stagehand/blob/a237c771fc188569bc95c1b2ed3c789950335d3a/packages/extension/service-worker-lifecycle/heartbeat-manager.ts#L41-L70@a237c77]

## 5. Opciones

### G1. Codigos de error

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Ampliar la allowlist con codigos estables y copia bilingue por codigo: `debugger_revoked`, `debugger_unavailable`, `unreadable_page`, `not_typable`, `outcome_unknown` (timeout de una escritura ya empezada), `not_confirmed` (clic sin `landing`); "no such tab" pasa a `stale_id` | Mantiene la regla "el texto de la extension no llega al modelo"; mismo patron que el brief del menu; el modelo sabe que hacer | Cambia el contrato extension-Core y los tests que fijan `browser_error`; hay que sincronizar JS, Swift y copia | media | Recomendada |
| B. Dejar pasar el mensaje saneado de la extension (una linea, 300 escalares) | Cero codigos nuevos | `debugger_unavailable` y "cannot be read" llevan texto de Chrome que puede incluir URL o titulo; rompe la regla firmada | baja | No |
| C. Solo copia mejor para `invalid_args` | Minimo | No separa "pagina ilegible" de "argumentos malos"; el modelo sigue reintentando | baja | No |

### G2. Identidad del elemento

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. La extension guarda rol, etiqueta y `href` de cada id al leer y los recalcula en `locate`, en `hitsAt` (justo antes de pulsar), en `prepareType` y en el camino sintetico; si difieren responde `target_changed` (ya existe en `BridgeCode`) o `stale_id` | No agrega argumentos al cable; cubre tambien iframes y respaldo sintetico; mismo criterio que el `menu` de escritorio y que Incredible | Falsos `target_changed` si la etiqueta cambia legitimamente (contadores, "Seguir" a "Siguiendo"): una lectura mas | baja | Recomendada |
| B. Core manda `expectedLabel`, `role` y `href` en `click`/`type` y la extension compara | Core decide con su propia copia de lo aprobado | Cambia el comando del cable; la comparacion depende de que Core y JS normalicen igual la etiqueta | media | Solo si se quiere defensa contra un worker que mienta, que no es el modelo de amenaza |
| C. Self-heal: si cambio, releer y reubicar por descripcion | Menos idas y vueltas | Pulsa algo distinto de lo aprobado: rompe el gate | media | No |

Frames (H-8): A1 = en el frame, prueba de cobertura dentro de su propio documento (`elementFromPoint` del frame en el centro del elemento) y la misma prueba de identidad; A2 = camino confiable por CDP sumando offsets de frames del mismo origen; A3 = sesiones CDP hijas para iframes de otro proceso (Chrome 125, exige subir el minimo de 116). Recomendada A1 ahora; A2 cuando un caso real lo pida; A3 es decision de Karen por la version minima.

### G3. Lo que ve el modelo

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Visibilidad con `checkVisibility()` (y `getClientRects().length` como respaldo) | Cubre ancestros `display:none`, `details` cerrado y `content-visibility`; API nativa desde Chrome 105 | El arnes falso de node no la tiene: hay que darle una implementacion fiel en el fake | baja | Recomendada (sin cambio de contrato) |
| B. Estado ARIA: `expanded`, `checked`, `selected`, `pressed`, `disabled`, `haspopup` en el elemento y en la linea renderizada | Paridad con las 4 referencias; el gatillo abierto y cerrado se distinguen | Cambia `BrowserElement`, codec y render; mas bytes por elemento | media | Recomendada, como decision de contrato |
| C. Orden de prioridad antes de truncar: primero elementos dentro de `dialog`/`aria-modal`, menu o listbox visible, popover abierto y los nuevos desde la ultima lectura; despues el resto en orden de DOM | Lo recien abierto nunca se corta | Cambia el orden de ids que el modelo ve; hay que explicar el orden en la copia | media | Recomendada |
| D. Marca de "nuevo desde la ultima lectura" por elemento | browser-use y nanobrowser lo hacen; ayuda a ver lo que abrio un clic | Requiere identidad estable entre lecturas (WeakMap por nodo en la pagina) | media | Recomendada junto con C |
| E. Paginacion u `offset` en el read | Nada se pierde | Mas llamadas; el read con selector del brief del menu ya cubre el caso de "leer solo el menu" | media | Despues de C, si C no basta |
| F. Leer el arbol de accesibilidad por CDP (`Accessibility.getFullAXTree`) | Estado y nombres calculados por Chrome | Dominio experimental; reescribe `page.js`; otro modelo de ids | alta | No ahora |

### G4. Saltos de linea

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Resultado estructurado: la extension devuelve `typed` y un indicador de saltos omitidos; Core lo convierte en copia ("se escribio sin los saltos de linea; avisale a la usuaria") y deja de ignorar `done` | Honesto ya; no cambia lo que se escribe | No resuelve el correo de tres parrafos | baja | Recomendada como primer paso |
| B. En `textarea` y `contenteditable`, escribir el texto con saltos por `Input.insertText` o por la insercion sintetica que ya existe en `typeIntoElement` | El texto llega entero sin teclas Enter, que en un `textarea` no envian nada | `insertText` es experimental; editores ricos (Gmail, Lightning) pueden tratar el texto insertado distinto que las teclas | media | Recomendada tras una prueba en vivo |
| C. Mandar `\n` como Enter real (como Puppeteer) | Lo que hacen las librerias | En un `input` envia el formulario: un envio que nadie aprobo | baja | No |

### G5. Carga

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `open` y `navigate` esperan `status=complete` via `tabs.onUpdated` con tope menor que los 12 s de la extension (p. ej. 8 s) y responden `loaded` o `still_loading` | Lo hacen Playwright, chrome-devtools-mcp y nanobrowser | Paginas con long-polling nunca llegan a `complete`: el tope lo resuelve | baja | Recomendada |
| B. El read incluye `status` de la pestana en la cabecera | El modelo sabe si leyo una pagina a medias | Campo nuevo en `BrowserPage` (contrato) | baja | Recomendada junto con A |
| C. Esperar DOM estable tras cada clic | Menos lecturas vacias | Mas latencia por accion; dificil de probar sin navegador | media | Despues |

### G6. Manos nuevas

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. `browser_select(tab, generation, element, option)` para `select` nativo, por texto visible de la opcion | Las 4 referencias lo tienen; el formulario de alta deja de estar bloqueado | Tool nueva: gate, copia, cubeta del puente, prompt | media | Recomendada |
| B. `browser_key(tab, key)` con lista cerrada: Escape, Tab, flechas, Enter; Enter pasa por el gate como un clic de enviar | Cierra menus, navega listas, confirma | Enter es un envio: necesita hoja salvo que la usuaria lo dijera | media | Recomendada con la lista cerrada |
| C. `browser_scroll(tab, direction, element?)` | Listas virtualizadas y menus largos | Sin efecto si la pagina no desplaza; hay que releer | baja | Recomendada |
| D. Hover y doble clic | Paridad con Playwright | Sin caso de uso nombrado hoy | baja | No ahora |

### G7. Texto de pagina

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Aplicar el filtro de escalares de `BrowserSanitize` (formato, uso privado, sin asignar) a texto, etiqueta, contexto, valor y titulo de pagina | Corta etiquetas Tag, cero-ancho y bidi; ya probado en mensajes | Puede romper scripts que usan ZWJ legitimo (emoji compuestos, algunas lenguas) | baja | Recomendada, decision de trust boundary |
| B. Ampliar los nombres sensibles (`cardnumber`, `ccnum`, `iban`, `cvv2`, `securitycode`, `token`, `secret`, `apikey`) por subcadena normalizada y mandar `masked` a Core | Menos campos de tarjeta escapan | Mas falsos positivos ("token" en campos inocuos) | baja | Recomendada |
| C. Quitar query y fragmento de la URL de la cabecera del read y mostrar el host del `href` en cada enlace | Menos tokens filtrados; el modelo sabe a donde lleva un enlace | Cambia lo que el modelo lee | baja | Recomendada, decision |
| D. Omitir texto fuera de pantalla u opaco | Menos instrucciones invisibles | Muchas paginas esconden texto accesible a proposito (lectores de pantalla) | media | No sin prueba |

### G8. Permiso `debugger`

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. ADR que ratifica `debugger` con limites: solo pestanas en lease, solo dominios Input, Emulation, Page (y DOM si G2-A2), nunca Network ni Runtime.evaluate desde CDP, test que fije la lista | Cierra la deriva de spec; limita lo que la capacidad permite | Un ADR mas que Karen firma | baja | Recomendada |
| B. Quitar `debugger` y volver a eventos sinteticos | Menos permisos | Vuelve el fallo de Lightning que lo motivo | media | No |

### G9. Control de la pestana

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Escuchar `tabs.onUpdated` (`groupId`) y avisar al host cuando la usuaria saca la pestana del grupo Companion; el host suelta la lease | Respeta la senal natural de "es mia" | Mensaje nuevo extension a Core (contrato) | media | Recomendada |
| B. Pedir hoja al tomar en el chat cuando el titulo o el host no aparecen en lo que dijo la usuaria (M-5) | Corta la cadena "una pagina pide tomar el banco" | Reabre 18b D1 firmada | baja | Decision de Karen |

## 6. Evidencia en contra

- La razon mas fuerte contra G2-A: Playwright, la referencia mas usada, no compara rol ni nombre al actuar, solo que el nodo siga conectado [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/injected/src/injectedScript.ts#L762-L768@a47fcf5]
- Se resuelve porque Playwright no tiene un gate atado a la etiqueta; Companion si, y su ticket ya liga la etiqueta del read, asi que pulsar otra etiqueta es saltarse lo aprobado [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:199]
- El costo aceptado de G2-A es una lectura extra cuando la etiqueta cambia sola; Incredible paga el mismo costo en escritorio [ref:incredible-ref/accessibility-helper.md@00d9f9efb8d2]
- Contra G1-A: los tests actuales fijan que todo codigo desconocido es `browser_error`, asi que el cambio rompe pruebas a proposito y hay que reescribirlas como lista explicita [repo:Tests/CompanionCoreTests/BrowserSanitizeTests.swift:42]
- Contra G3-A: Playwright cuenta como visible un elemento con opacidad 0, y `checkVisibility()` sin opciones tambien; no se filtra opacidad para no esconder controles que aparecen al pasar el cursor [doc:https://playwright.dev/docs/actionability@consultado-2026-10-02]
- Contra G3-B: cada campo de estado agrega bytes y Core corta a 48000; se mitiga emitiendo el estado solo cuando el atributo existe [repo:Sources/CompanionServices/Browser/BrowserToolRunner.swift:20]
- Contra G4-B: `Input.insertText` es experimental en CDP y puede cambiar sin aviso [doc:https://github.com/ChromeDevTools/devtools-protocol/blob/3e46e43d9611a3ef508dea0024e5fe6b87d1d578/pdl/domains/Input.pdl#L141-L146@3e46e43]
- Se acepta con respaldo: la insercion sintetica por `execCommand('insertText')` ya existe en `typeIntoElement` y no pasa por teclas [repo:Extensions/browser/lib/page.js:247]
- Contra G6: cada tool nueva agranda la superficie que una pagina hostil puede intentar disparar; OWASP pide minimo privilegio [doc:https://genai.owasp.org/llmrisk/llm01-prompt-injection/@2025]
- Se resuelve con lista cerrada de teclas, Enter tras el gate y `select` juzgado como un `type` (etiqueta, origen del frame) [repo:Sources/CompanionCore/Browser/BrowserPolicy+Verdicts.swift:18]
- Contra G5-A: una espera dentro de la extension compite con su propio corte de 12 s, y si lo pasa el host recibe `timeout` de una navegacion que si ocurrio [repo:Extensions/browser/background.js:10]
- Contra G8-A: las extensiones de agente de referencia piden aun mas (`tabs`, `webNavigation`, `history`), asi que limitar dominios es mas estricto que lo comun, no menos [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/wxt.config.ts#L40-L59@f48e715]

## 7. Ejemplares y anti-ejemplos

- Bien: error con accion siguiente y codigo estable; Playwright pide un snapshot nuevo cuando la ref no existe [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L577@a47fcf5]
- Bien: chrome-devtools-mcp dice que el nodo se desprendio y que tome un snapshot nuevo [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/McpPage.ts#L937@b2f522c]
- Bien: reverificar al pulsar contra lo aprobado; el `menu` de escritorio de Companion resuelve otra vez y exige el titulo aprobado [repo:Sources/CompanionServices/Accessibility/AXScreen.swift:316]
- Bien: visibilidad por caja, no por estilo propio; browser-use descarta nodos sin caja de layout [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/service.py#L282-L283@62a0f71]
- Bien: marcar lo nuevo; browser-use antepone `*` a los elementos que no estaban en el estado anterior [ref:https://github.com/browser-use/browser-use/blob/62a0f71ba5e4724e287fcb7f93be84465366441a/browser_use/dom/serializer/serializer.py#L1032@62a0f71]
- Bien: parar cuando la pagina cambio; nanobrowser corta la cola si aparecio algo nuevo [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/agent/agents/navigator.ts#L313-L322@ad47282]
- Bien: navegar con espera acotada; Playwright espera `load` con tope de 5 s porque la pagina ya es operable [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/playwright-core/src/tools/backend/tab.ts#L381-L382@a47fcf5]
- Bien: `select` con validacion; chrome-devtools-mcp rechaza un `select` multiple o deshabilitado antes de elegir [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/tools/input.ts#L62-L98@b2f522c]
- Anti-ejemplo: self-heal que reinfiere el elemento con el LLM tras un fallo y pulsa el nuevo selector; en Companion pulsaria algo que nadie aprobo [ref:https://github.com/browserbase/stagehand/blob/a237c771fc188569bc95c1b2ed3c789950335d3a/packages/extension/services/actService.ts#L361-L420@a237c77]
- Anti-ejemplo: reasignar en silencio el indice de una accion a "el mismo elemento" encontrado por historia; en Companion el ticket es por id y etiqueta y no debe moverse solo [ref:https://github.com/nanobrowser/nanobrowser/blob/ad47282a17ecdfb894745af093e0f7332fc1f71a/src/background/agent/agents/navigator.ts#L547-L590@ad47282]
- Anti-ejemplo: `\n` convertido en Enter real, que envia formularios [ref:https://github.com/puppeteer/puppeteer/blob/2e45a3af43231cd658285e4da5e7f53e40f24edf/packages/puppeteer-core/src/common/USKeyboardLayout.ts#L321@2e45a3a]
- Anti-ejemplo: visibilidad que solo mira el propio elemento; la de Companion lista items de un desplegable cerrado [repo:Extensions/browser/lib/page.js:272]
- Anti-ejemplo: comparar opacidad como la cadena exacta "0" deja pasar "0.0" u opacidad heredada [ref:https://github.com/hangwin/mcp-chrome/blob/f48e71751e00bc09725c7e173423cff4f2ccd12a/app/chrome-extension/inject-scripts/accessibility-tree-helper.js#L137@f48e715]
- Anti-ejemplo: el aviso util que se pierde dos veces, cortado a 40 escalares y luego ignorado por el host [repo:Sources/CompanionServices/Browser/BrowserToolRunner+Gates.swift:137]

## 8. Trampas

### Por contexto

- App instalada: los codigos nuevos solo llegan al modelo si estan a la vez en la allowlist y en `BrowserCopy`; uno sin copia cae en "The browser failed: code" [repo:Sources/CompanionCore/Browser/BrowserCopy.swift:99]
- App instalada: el host nativo es el mismo binario; un cambio de protocolo exige reinstalar la app y recargar la extension a la vez, o el `hello` con `protocol` viejo no se entiende [repo:Extensions/browser/background.js:9]
- Service worker MV3: `tabState` y `taken` viven en memoria; una identidad guardada en el worker se pierde al suspenderse, la guardada en la pagina (`__companionState`) no [repo:Extensions/browser/background.js:20]
- Service worker MV3: una sesion de `debugger` activa lo mantiene vivo desde Chrome 118, pero solo mientras hay una pestana adjunta [doc:https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle@2023-05-02]
- Service worker MV3: esperar la carga (G5) debe terminar antes de los 12 s de la propia extension [repo:Extensions/browser/background.js:97]
- Service worker MV3: `tabs.onUpdated` hay que registrarlo en el nivel superior del worker, igual que `onRemoved`, para que despierte al worker [repo:Extensions/browser/background.js:433]
- swift test: los tests que fijan `browser_error` para codigos desconocidos deben pasar a una lista explicita de codigos permitidos y otra de rechazados [repo:Tests/CompanionServicesTests/BrowserChannelHardeningTests.swift:20]
- swift test: una tool nueva sin cubeta en `BridgePolicy` rompe el test de cubetas del puente a proposito [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:34]
- node --test: el `fake` de `page.test.js` no tiene `checkVisibility`, `innerText` real ni herencia de `display`; un test de G3-A que solo use el fake no prueba el render [repo:Extensions/browser/test/page.test.js:269]
- node --test: nada ahi verifica `elementFromPoint`, CDP ni `insertText`; G2 en iframes, G4-B y G5 necesitan prueba en vivo en Chrome y Comet [repo:Extensions/browser/test/background.test.js:9]
- Puente MCP: las mismas tools corren con el caller del puente, que pide hoja para `take`; una tool nueva hereda la hoja solo si se agrega a `writeTools` [repo:Sources/CompanionCore/Bridge/BridgePolicy.swift:43]
- CI: sin `node`, `gates.sh` solo avisa; un cambio de extension puede llegar a main sin correr sus tests [repo:scripts/gates.sh:309]

### Generales

- `BrowserSanitize.done` corta a 40 escalares; cualquier resultado nuevo con texto largo se trunca, por eso G4-A va como indicador, no como frase [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:11]
- La copia de `stale_id` dice "read the tab again"; si G2 usa `stale_id` en vez de `target_changed`, el modelo no distingue "caduco" de "cambio" [repo:Sources/CompanionCore/Browser/BrowserCopy.swift:87]
- `target_changed` hoy significa "la app del frente cambio" en escritorio; reusarlo en el navegador exige copia propia del navegador [repo:Sources/CompanionServices/Tools/ParentToolRunnerHands.swift:248]
- El orden de prioridad de G3-C cambia que id tiene cada elemento; los ids siguen siendo locales a la generacion, asi que no rompe tickets [repo:Extensions/browser/lib/wire.js:150]
- Un `select` nativo abre un popup que CDP no controla: elegir debe ser asignar el valor y disparar `input` y `change`, no pulsar [ref:https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/b2f522c8ba0fd2e00a679159b4aa5243de5f1b78/src/tools/input.ts#L62-L98@b2f522c]
- `aria-hidden` no es visibilidad de pantalla: Playwright trata `display:none` y `aria-hidden=true` como ocultos solo para accesibilidad, en una funcion aparte de la visibilidad visual; mezclar ambos criterios en `isVisible` esconderia controles que si se ven [ref:https://github.com/microsoft/playwright/blob/a47fcf59c87a1b06a7439ce0c7ffe491d8cba513/packages/injected/src/roleUtils.ts#L337-L351@a47fcf5]
- El filtro de G7-A sobre ZWJ rompe emoji compuestos en etiquetas; aceptar o excluir ZWJ (U+200D) es parte de la decision [repo:Sources/CompanionCore/Browser/BrowserSanitize.swift:39]
- Sesiones CDP hijas para iframes de otro proceso existen desde Chrome 125, por encima del minimo 116 [doc:https://developer.chrome.com/docs/extensions/reference/api/debugger@2026-09-11]
- Tras un Cancelar del banner, `take` hoy responde `taken`; si G1 agrega `debugger_revoked` sin arreglar `take`, el grupo azul seguira mintiendo [repo:Extensions/browser/background.js:175]

## 9. Incertidumbre

Comparaciones imposibles (la extension de Incredible no esta instalada en esta Mac): como redacta los errores del navegador, como representa menus y estado ARIA en el DOM, si espera la carga, si tiene teclas o scroll en el navegador, y su reconexion. Las paridades de este brief vienen del helper de escritorio.

- ASSUMPTION: `chrome.debugger.sendCommand` acepta el comando experimental `Input.insertText` desde una extension. prueba: en una pestana tomada, llamar `Input.insertText` con "a\nb" sobre un `textarea` y leer su `value`.
- ASSUMPTION: `Input.insertText` con saltos de linea en un `contenteditable` de Gmail y en un campo de texto largo de Lightning crea parrafos y no envia nada. prueba: correo de prueba en borrador y caso de Salesforce en Comet, inspeccion del DOM despues.
- ASSUMPTION: la insercion sintetica `execCommand('insertText')` conserva los `\n` en un `textarea` y crea parrafos en un `contenteditable`. prueba: test en vivo con "a\nb" en ambos y lectura de `value` e `innerHTML`.
- ASSUMPTION: `tabs.onUpdated` entrega `changeInfo.status` sin el permiso `tabs` (la doc solo restringe url, title y favIconUrl, y la extension tiene permisos de host). prueba: test manual en Chrome 116 o superior con un listener que registre `status` de una pestana tomada.
- ASSUMPTION: el puerto nativo mantiene vivo el worker (Chrome 105 o superior), lo que haria raro el `busy` de M-9. prueba: abrir `chrome://serviceworker-internals`, dejar la extension conectada 5 min sin llamadas y ver si el worker se detiene.
- ASSUMPTION: `checkVisibility()` se comporta igual en Comet que en Chrome. prueba: pagina local con un `ul` dentro de un `div` con `display:none` y `browser_read` en ambos navegadores.
- ASSUMPTION: comparar rol y etiqueta (G2-A) no produce falsos `target_changed` frecuentes en Salesforce Lightning. prueba: 20 clics de QA en Lightning con el contador de `target_changed` en el log.
- ASSUMPTION: Incredible en el navegador hace las mismas reverificaciones que su helper de escritorio. prueba: imposible hoy; requiere instalar su extension en un perfil aparte y repetir H-1 y H-5 alli.

Decisiones para Karen:
- [NEEDS CLARIFICATION: K1 (G1, contrato extension-Core): se adoptan los codigos `debugger_revoked`, `debugger_unavailable`, `unreadable_page`, `not_typable`, `outcome_unknown` y `not_confirmed`, mas `target_changed` en `BrowserSanitize.allowedCodes` (hoy falta, lineas 13-17) con su copia, que G2 necesita (se decide junto con K2), con copia es/en que nombre la accion siguiente? Coordinar con el D3 del brief browser-read-menu-abierto para no definir dos veces el canal.]
- [NEEDS CLARIFICATION: K2 (G2, trust boundary): un elemento cuyo rol, etiqueta o href cambio entre leer y actuar responde `target_changed` con copia de navegador (recomendado) o `stale_id`?]
- [NEEDS CLARIFICATION: K3 (G4, gate): se permite escribir saltos de linea en `textarea` y `contenteditable` por insercion de texto (nunca Enter real), tras la prueba en vivo? Mientras tanto, solo el aviso honesto.]
- [NEEDS CLARIFICATION: K4 (G3 y G5, contrato): se agregan a `BrowserElement` los campos de estado ARIA y a `BrowserPage` el `status` de carga, y se cambia el orden del read para poner primero dialogos, menus abiertos y elementos nuevos?]
- [NEEDS CLARIFICATION: K5 (G6, contrato y permisos): que manos nuevas entran (`browser_select`, `browser_key` con lista cerrada, `browser_scroll`), Enter con hoja salvo que la usuaria lo dijera, y si van tambien por el puente (en `writeTools`)?]
- [NEEDS CLARIFICATION: K6 (G7, prompt injection): se filtra Unicode de formato en todo texto de pagina (y que hacer con ZWJ), se amplian los nombres sensibles, se quita query y fragmento de la URL del read y se muestra el host de cada enlace?]
- [NEEDS CLARIFICATION: K7 (G8, permisos): se escribe el ADR 010 que ratifica `debugger` (hoy solo hay un comentario en un test) con la lista cerrada de dominios CDP y un test que la fije?]
- [NEEDS CLARIFICATION: K8 (G9): sacar una pestana del grupo Companion suelta la lease? Y M-5: se reabre 18b D1 para pedir hoja al tomar en el chat una pestana que la usuaria no nombro?]
- [NEEDS CLARIFICATION: K9 (H-8): subir el minimo de Chrome a 125 para clics confiables en iframes de otro origen, o quedarse en el camino sintetico con prueba de cobertura dentro del frame?]

## 10. Checklist de estandar

Hoja de ruta: specs chicas, en orden de severidad. Cada una es un PR con test en rojo primero.

1. S1 (H-2, H-3, M-1) codigos con accion siguiente. Depende de K1.
   - `debugger_revoked` llega al modelo con copia que dice que la usuaria detuvo el control y que no reintente; test Swift de punta a punta.
   - `browser_read` de `chrome://settings` devuelve `unreadable_page`, no `invalid_args`.
   - "no such tab" en read devuelve `stale_id` y libera la lease.
   - `browser_take` tras un Cancelar devuelve `debugger_revoked` y el host no concede la lease.
   - Ningun codigo nuevo cae en `browser_error`; los tests de allowlist enumeran los permitidos.
2. S2 (H-1, H-8) identidad al actuar. Depende de K2.
   - Test node: read ve "Siguiente", la pagina cambia el texto a "Eliminar cuenta", click devuelve el codigo elegido y CDP no recibe `mousePressed`.
   - Mismo test para el camino de iframe y para el respaldo sintetico.
   - En iframe, un overlay sobre el elemento hace fallar el clic sintetico con `stale_id` (cobertura dentro del frame).
3. S3 (H-5) saltos de linea honestos. Primer paso sin K3.
   - Escribir "a\nb" en un `input` deja "ab" y la salida al modelo dice que se omitieron los saltos.
   - El indicador no depende del corte de 40 escalares de `done`.
   - Con K3 aprobada: en `textarea` el valor final es "a\nb" y ningun evento Enter se envia (verificado en vivo).
4. S4 (H-4b) visibilidad real. Sin cambio de contrato.
   - Un boton dentro de un ancestro `display:none` no se lista; uno dentro de `details` cerrado tampoco.
   - El fake de node implementa `checkVisibility` con herencia de ancestros, y un test lo cubre.
5. S5 (H-4a, H-4 estado) lo que ve el modelo. Depende de K4.
   - Un gatillo con `aria-expanded=true` se renderiza distinto de uno con `false`.
   - En una pagina de 1500 enlaces con un menu abierto al final del `body`, todos los `menuitem` visibles aparecen en el read truncado.
   - Los elementos nuevos desde la lectura anterior llevan marca.
6. S6 (H-6) carga. Depende de K4 para el campo `status`.
   - `browser_open` seguido de `browser_read` sobre una pagina con 3 s de retardo devuelve el contenido final, no about:blank.
   - Una pagina que nunca completa responde `still_loading` antes de 12 s.
7. S7 (H-7) manos nuevas. Depende de K5.
   - `browser_select` elige "Mexico" en un `select` nativo y la pagina recibe `input` y `change`.
   - `browser_key` con Escape cierra un menu abierto; con Enter pide hoja si la usuaria no lo dijo.
   - `browser_scroll` sobre un listbox largo trae opciones nuevas al siguiente read.
   - Cada tool nueva esta en una cubeta de `BridgePolicy` y tiene copia es/en.
8. S8 (M-2, M-3) resultado desconocido.
   - Un timeout de `click` o `type` ya empezado devuelve `outcome_unknown` con copia "inspecciona antes de reintentar".
   - Un clic sin `landing` devuelve `not_confirmed`, nunca `clicked`.
9. S9 (M-6, M-7, L-4, L-8) higiene. Depende de K6.
   - Una etiqueta con caracteres del bloque Tag llega al modelo sin ellos.
   - `cardnumber` y `iban` sin `autocomplete` se rechazan para escribir y su valor no viaja.
   - La URL del read no lleva query ni fragmento.
10. S10 (M-8) ADR del permiso `debugger`. Depende de K7.
    - ADR 010 firmado; un test falla si la extension llama un dominio CDP fuera de la lista.
11. S11 (M-4, M-5) control de pestanas. Depende de K8.
    - Sacar la pestana del grupo Companion suelta la lease y el siguiente clic responde `not_controlled`.
12. S12 (M-9, L-1, L-2, L-3, L-5, L-6, L-7) robustez de conexion y detalles. Coordinar con `bridge-companion-cerrado`.
    - Tras reiniciar el worker, las tools vuelven en menos de 5 s, no en el siguiente tick de 1 min.

Criterios que toda spec hereda:
- [ ] Ninguna escritura del navegador pulsa o escribe en un elemento cuyo rol, etiqueta o `href` difiere del que juzgo el gate.
- [ ] Todo error que llega al modelo tiene codigo estable de la allowlist y copia es/en que nombra la accion siguiente; ningun texto libre de la extension o de Chrome llega al modelo.
- [ ] Ningun elemento invisible por un ancestro aparece en el read.
- [ ] Ningun `\n` se convierte en un Enter real sin pasar por el gate.
- [ ] `open` y `navigate` no responden exito antes de `complete` o de un tope declarado, y el modelo puede saber cual fue.
- [ ] Cada tool nueva tiene veredicto de gate, cubeta en el puente, copia es/en y test Swift y node.
- [ ] Todo cambio de contrato extension-Core se versiona en `protocol` del `hello` y tiene test a ambos lados.
- [ ] Lo que solo se puede verificar en Chrome real (CDP, `elementFromPoint`, `insertText`, carga) se lista como prueba en vivo de Karen en la spec, no se da por probado con node.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | chrome.debugger API | Google (Chrome for Developers) | 2026-09-11 | 2026-10-02 | high |
| 2 | Permissions list | Google (Chrome for Developers) | 2026-09-09 | 2026-10-02 | high |
| 3 | chrome.tabs API | Google (Chrome for Developers) | 2026-09-24 | 2026-10-02 | high |
| 4 | Extension service worker lifecycle | Google (Chrome for Developers) | 2023-05-02 | 2026-10-02 | high |
| 5 | Element.checkVisibility | MDN | 2026-06-18 | 2026-10-02 | high |
| 6 | browser-compat-data Element.json | MDN | f2dd714 | 2026-10-02 | high |
| 7 | WAI-ARIA 1.2 | W3C | REC 2023-06-06 | 2026-10-02 | high |
| 8 | DevTools Protocol pdl (Input, DOM, Accessibility) | Google ChromeDevTools | 3e46e43 | 2026-10-02 | high |
| 9 | Playwright actionability | Microsoft | sin version en la pagina | 2026-10-02 | high |
| 10 | OWASP LLM01:2025 Prompt Injection | OWASP | 2025 | 2026-10-02 | high |
| 11 | microsoft/playwright (tools MCP, injected) | Microsoft | a47fcf5 | 2026-10-02 | high |
| 12 | ChromeDevTools/chrome-devtools-mcp | Google | b2f522c | 2026-10-02 | high |
| 13 | browser-use/browser-use | browser-use | 62a0f71 | 2026-10-02 | high |
| 14 | browserbase/stagehand (extension) | Browserbase | a237c77 | 2026-10-02 | medium |
| 15 | nanobrowser/nanobrowser | nanobrowser | ad47282 | 2026-10-02 | medium |
| 16 | hangwin/mcp-chrome | hangwin | f48e715 | 2026-10-02 | medium |
| 17 | puppeteer/puppeteer USKeyboardLayout | Google | 2e45a3a | 2026-10-02 | high |
| 18 | incredible-ref accessibility-helper.md (local, solo lectura) | extraccion local de Incredible 0.2.36 | sha256 00d9f9efb8d2 | 2026-10-02 | medium |
| 19 | incredible-ref README.md (local) | carpeta de referencia | sha256 47d55c41b5ec | 2026-10-02 | high |
| 20 | Auditoria extension navegador (local) | auditoria 2026-10-02 | sha256 9d429828792f | 2026-10-02 | high |

[KAREN:chat 2026-10-02] Se decide como lo resuelve la referencia local de Incredible y, donde no alcanza, con la recomendacion del brief. K1 si, los siete codigos con target_changed en la lista blanca y copia que nombra la accion siguiente, coordinado con browser-read-menu-abierto. K2 target_changed. K3 si, insercion de texto sin Enter real, solo despues de la prueba en vivo. K4 si. K5 si a browser_select, browser_key con lista cerrada y browser_scroll, Enter con hoja salvo que yo lo haya dicho, y tambien por el puente. K6 si a todo; el trato de ZWJ lo fija la prueba de la spec. K7 si, ADR 010 con la lista cerrada de dominios CDP y su test. K8 si, sacar la pestana del grupo suelta la lease, y se reabre 18b D1: hoja al tomar en el chat una pestana que no nombre. K9 subir el minimo a Chrome 125.
