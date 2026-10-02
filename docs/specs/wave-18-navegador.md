# Wave 18 — El navegador: extensión MV3 y native messaging, como Incredible

**Estado: APROBADO (2026-09-28).** Firmado por Karen con las recomendaciones de D1–D7 («dales firma y mergea de una»). No arranca antes de la prueba en vivo de 17 (`wave-17-puente-mcp.md` §7).

## 1. El fallo (ADR 001)

Hoy el navegador se toca por Accesibilidad (`look`/`click`/`scroll` de 16a) y se lee por `web_fetch`; `browser-use/SKILL.md` lo dice: "Companion has no hand inside the browser". Lo que Accesibilidad no cubre a priori: pestañas que no están delante, iframes y shadow DOM, listas virtualizadas, escribir sin traer la app al frente (17, R2). **El fallo concreto está por verificar**: si §7 de 17 llega al picklist de Salesforce en Comet solo con `look`, esta wave no tiene fallo y se archiva (D1).

## 2. Cómo lo hace Incredible (análisis estático, 2026-09-28)

- Un manifiesto de mensajería nativa en la carpeta de Chrome con 3 ids de extensión permitidos y un host que entrega un secreto guardado en un archivo de su carpeta de datos (rutas y nombres en la referencia local). La extensión pide el secreto al host y después habla con la app por un canal local.
- Se reportó un puerto TCP fijo, pero **no se encontró en la app**: no verificado.
- Tools: `navigate`, `click`, `read` (selector `>>>` que atraviesa frames), `read_pdf`, pestañas de varios perfiles Chromium, `watch`/PiP. Filtra campos sensibles dentro de la extensión. Soporta Chrome, Edge, Arc y Brave.
- **Se toma**: extensión MV3 + native messaging, el filtrado dentro del navegador, `>>>` y ids de elemento que caducan con cada `read`.
- **No se toma**: el secreto en un archivo que dura para siempre, ni el puerto TCP.

## 3. Alternativas

| Vía | A favor | En contra |
|---|---|---|
| Solo Accesibilidad (ya existe) | Cero instalación; vale para Safari; ya tiene hojas y pin | Solo la pestaña delante; `type_text` exige el foco; frames y shadow DOM irregulares |
| AppleScript/JXA `execute javascript` | Sin extensión | "Allow JavaScript from Apple Events" por navegador + permiso de Automatización; JS arbitrario con la sesión de la usuaria; ningún filtro antes de que el dato salga; `osascript` está en la lista negra (`ClaudeCodeExecutor.swift`); Arc/Comet por verificar |
| Extensión MV3 + native host | Todas las pestañas; DOM real; filtrado dentro del navegador; no roba el foco | Instalar extensión y manifiesto; mantener JS |

**Recomendación**: extensión para Chromium. Accesibilidad sigue como respaldo y como vía de Safari. JXA se rechaza.

## 4. Decisiones (firma Karen)

- **D1** 18-0 arranca solo con un fallo de §1 observado en la prueba de 17.
- **D2** El host es el propio binario `Companion.app/Contents/MacOS/Companion --native-host`: bifurcación en `CompanionMain.swift` antes de `NSApplication`, relé stdio ↔ socket, sin UI. Se descartan un `.sh` con `nc -U` (no maneja el prefijo de longitud de 4 bytes) y un target nuevo (toca `Package.swift`, config raíz).
- **D3** Socket Unix aparte, `Companion/bridge/browser.sock` con su `browser.token`; se reusa `BridgeListener` parametrizado por nombre de archivo (hoy `bridge.sock`/`bridge.token` están escritos a fuego en `start()`). Ningún puerto TCP.
- **D4** Sin secreto de larga vida (§5).
- **D5** Navegadores en 18: Chrome y Comet (la sesión de Salesforce vive en Comet). Edge, Brave y Arc después. Rutas de `NativeMessagingHosts` de Comet y Arc por verificar.
- **D6** Extensión sin empaquetar (modo desarrollador) con `host_permissions: ["<all_urls>"]`. Chrome Web Store y permisos opcionales por origen quedan como decisión aparte de Karen.
- **D7** Escribir el manifiesto en la carpeta de Chrome es escribir config ajena: excepción explícita a ADR 004 (ADR 007). Solo con el botón *Conectar navegador* de Ajustes; *Quitar* lo borra; sin pulsar el botón no se escribe nada.

## 5. Arquitectura

```
extensión (service worker) ⇄ chrome.runtime.connectNative ⇄ Companion --native-host
   [uint32 + JSON, stdio]                     ⇄ browser.sock [JSONL] ⇄ BrowserChannel (actor)
```

Autenticación con tres cerraduras, sin Keychain:
1. `allowed_origins` del manifiesto fija el id de la extensión; el host comprueba además `argv[1] == chrome-extension://<id>/`.
2. El host lee `browser.token` (0600, carpeta 0700), regenerado en cada lanzamiento (patrón de 17).
3. `BridgeListener` rechaza cualquier par cuyo `getpeereid` no sea el uid de la app.

La extensión nunca guarda un secreto. **Trade-off frente al Keychain**: un proceso del mismo usuario puede leer el token. Es el mismo modelo de amenaza que ya aceptó 17, y un malware con ese uid también podría hablar con Accesibilidad. El Keychain no añade frontera: el host no lo lee sin diálogos (`KeychainSecretStore` usa el llavero legacy y con el certificado autofirmado cada rebuild vuelve a pedir la contraseña). Upgrade trigger: cuenta de Apple Developer (llavero con data protection atado a la identidad del binario).

**Dirección de las llamadas**: la extensión abre la conexión y manda `hello` (`extension`, `browser`, `version`, `protocol:1`). Después Companion llama y la extensión responde (al revés que 17). Si el service worker de MV3 muere, `connectNative` vuelve a abrir. Que el puerto nativo mantenga vivo al worker está por verificar.

**Tools** (solo con una extensión conectada: tool sin respaldo no se ofrece): `browser_tabs` (lectura), `browser_read(tab, selector?)` (lectura: texto más elementos numerados, ids que caducan en cada lectura), `browser_click(id)`, `browser_type(id, text)`, `browser_navigate(tab, url)` (escrituras). Salen por `ParentToolRunner.specs`, así que el puente de 17 las publica solo.

**Puertas** (se reusan, no se copian): `browser_click` → `HandsGate.clickVerdict(label:context:said:)` + ticket de `ApprovalTickets`; `browser_type` → `HandsGate.verdict` con la regla de direcciones; `browser_navigate` a otro origen → lógica de `ParentToolGate.saidIt`; las tres escrituras entran en `BridgePolicy.writeTools` (30/min).

**Campos sensibles, doble filtro**: la extensión descarta los valores de `type=password`, `autocomplete=cc-*`, `one-time-code` y `hidden`; `BrowserPolicy` (Core) vuelve a filtrar; `browser_type` sobre uno de ellos responde `secure_field` (código existente).

## 6. Protocolo (Core, `BrowserProtocol.swift`)

```
→ {"id":1,"method":"hello","params":{"extension":"<id>","browser":"comet","protocol":1}}
← {"id":7,"method":"call","params":{"name":"browser_read","arguments":{"tab":12}}}
→ {"id":7,"result":{"ok":true,"output":"[1] botón \"Guardar\" …","origin":"https://…"}}
```

Códigos: `bad_token`, `not_connected`, `stale_id`, `secure_field`, `invalid_args`, `timeout`, `frame_too_large`. Frame nativo con tope de 1 MB; línea del socket 64 KB, como 17. El resultado se recorta con aviso.

## 7. Entregas

| # | Qué | Archivos |
|---|---|---|
| 18-0 | Core: codec (JSONL + prefijo uint32), `BrowserPolicy` (escrituras, filtro sensible, cambio de origen, caducidad de ids), `BrowserCopy` es/en | `CompanionCore/BrowserProtocol.swift`, `BrowserPolicy.swift`, `BrowserCopy.swift`, 2 tests |
| 18-1 | Extensión con arnés `node --test` sin dependencias sobre funciones puras (clasificador de campos, parser de `>>>`, serializador) | `Extensions/browser/manifest.json`, `background.js`, `content.js`, `lib/page.js`, `test/page.test.js` |
| 18-2 | Canal: `BridgeListener` parametrizado, `BrowserHostRelay` (stdio ↔ socket), `BrowserChannel` (actor, pendientes por id, timeout), bifurcación `--native-host` | `BridgeListener.swift`, `BrowserHostRelay.swift`, `BrowserChannel.swift`, `CompanionMain.swift`, tests |
| 18-3 | Tools y puertas: casos nuevos en `ParentTool`, ejecución en el runner, `BridgePolicy.writeTools`, `browser-use/SKILL.md` | `ParentTools.swift`, `ParentToolRunner.swift`, `BridgePolicy.swift`, `SKILL.md`, tests |
| 18-4 | Ajustes › Navegador: *Conectar navegador* / *Quitar* (escribe y borra el manifiesto por navegador detectado), estado; ADR 007; CHANGELOG | `NativeHostInstaller.swift`, `SettingsInventory` (+1), `DECISIONS.md`, `CHANGELOG.md`, tests |

`gates.sh` corre además `node --test Extensions/browser/test` si existe `node` (por verificar que quepa en `gates.sh` sin tocar su contrato).

## 8. Criterios de aceptación

1. El codec redondea `hello`/`call`/`result`/`error`; frame > 1 MB → `frame_too_large`; prefijo truncado → error, nunca cuelgue.
2. `BrowserPolicy` elimina valores de password, `cc-number` y `one-time-code` aunque la extensión los mande.
3. `browser_click` sobre "Eliminar" no dicho → hoja; denegada → la extensión no recibe ningún `call`.
4. `browser_navigate` a un origen no dicho → hoja; mismo origen → sin hoja.
5. 31 escrituras del navegador en 60 s por el puente → la 31.ª es `rate_limited`.
6. Sin extensión conectada, `specs` no incluye ninguna `browser_*`.
7. Host con `argv[1]` distinto del id fijado sale ≠ 0 sin tocar el socket; token malo → `bad_token` y cierre.
8. Tests JS: el clasificador marca los 4 tipos sensibles; `a >>> b` produce dos segmentos.
9. *Quitar* borra el manifiesto; `connectNative` falla y Companion lo muestra "desconectado".
10. En vivo (Karen): en Comet, `browser_read` de una pestaña de fondo devuelve el picklist de Salesforce sin cambiar la pestaña activa.

## 9. Seguridad

Ningún puerto TCP; socket 0600 en carpeta 0700 con `getpeereid` y token por lanzamiento. Una sola extensión conectada (la segunda recibe `busy`). Lo que devuelve el navegador son datos, nunca instrucciones (M3 de 15g), declarado en cada tool. Logs: tool, código, origen y `chars=N`, nunca texto ni valores. Se hereda la idempotencia pendiente de 17 (§9-6). `security-reviewer` obligatorio en 18-2 y 18-3.

## 10. Riesgos

- **R1** El ciclo de vida del service worker MV3 corta el puerto → reconexión y `not_connected` estable.
- **R2** Rutas de manifiesto de Comet/Arc desconocidas → D5 limita a lo verificado.
- **R3** `<all_urls>` es amplio → solo sin empaquetar (D6).
- **R4** Casos nuevos en `ParentTool` rompen `switch` exhaustivos (`isHands`, `isSight`) → el compilador los señala en 18-3.
- **R5** Lanzar el binario de la app como host podría inicializar AppKit → bifurcar antes de `NSApplication` + test del modo host.

## 11. Desviaciones del kickoff (planner + architect, 2026-09-29, contra `c316a33`)

**D1 cumplido.** La sesión de QA del 2026-09-29 sobre Salesforce en Comet mostró el fallo de §1: `type_text` en campos Lightning → `no_focused_field`; Enter en la barra de direcciones no navega (hubo que usar `open_url`); `see` inventa datos que `look` no tiene.

Se registran sin re-aprobar (la intención de cada decisión se conserva):

- **X1 (D2)** Un manifiesto de `NativeMessagingHosts` no lleva argumentos: Chrome lanza `path chrome-extension://<id>/`. El modo host se entra solo con el origen fijado en `argv[1]`; un `--native-host` suelto se rechaza y los tests llaman a `BrowserHostRelay.run` directamente. Mismo binario, bifurcación antes de `NSApplication`, sin escribir en stdout nada que no sea un frame, y `exit` antes de tocar `Config`, Keychain o AppKit.
- **X2 (§6)** El token lo inyecta el relé en el `hello` del primer frame; la extensión nunca lo ve. `hello` lleva `token`.
- **X3 (§6)** El resultado viaja estructurado (`BrowserPage` con elementos: rol, etiqueta, contexto, tipo, autocomplete, valor, frame, `generation`) y Core renderiza el texto. Con un texto ya hecho, Core no podría volver a filtrar (criterio 2) ni gatear clics por etiqueta.
- **X4 (§5, R4)** Nada de casos nuevos en `ParentTool`: `BrowserTool` en Core y `BrowserToolRunner: ParentToolExecuting` en Services, compuestos con `CompositeParentTools`. La conversación usa `[parentTools, appTools, browserTools]`; el puente `[parentTools, browserTools]` (no hereda el Slack de Karen). `ParentTool.ownsRequest` y `SessionMachine.isJobRequest` reconocen `BrowserTool`.
- **X5 (§5)** El puente no publica solo: `BridgeScope.bridgeTools` es lista explícita (20c D6) y `BridgePolicy.readTools` también; ambas suman las `browser_*`. `DeliverableTools.swift` entra en 18-3.
- **X6 (§5)** `HandsGate.verdict` cae en `default: .act` para nombres ajenos a `ParentTool`: la regla de direcciones se extrae como `HandsGate.typeVerdict(text:said:)`. La puerta de navegación vive en `BrowserPolicy` (mismo módulo que `ParentToolGate.saidIt`). `approval(for:said:)` es síncrono: las puertas leen la última `BrowserPage` filtrada en caché por pestaña; los tickets se atan a (tab, generation, element, label). El runner tiene su propia instancia de `ApprovalTickets`.
- **X7 (§6)** 64 KB de punta a punta: la extensión recorta a ~56 KB UTF-8 (`TextEncoder`); el relé aplica el tope nativo de 1 MB y rechaza con `frame_too_large` (con el id del frame) todo lo que re-codificado pase de 64 KB, porque `BridgeListener` cierra la conexión en una línea larga.
- **X8 (D6)** El manifiesto de la extensión lleva `key` (id estable aunque se mueva la carpeta) y `externally_connectable: {"ids": []}`; sin `onMessageExternal` ni listener de `window.message`. Permisos: `nativeMessaging`, `scripting`, `alarms` y `<all_urls>`; sin `tabs` ni `debugger`. La clave privada no se commitea.
- **X9 (18-1)** Lectura con `chrome.scripting.executeScript` a demanda (`allFrames`, mundo aislado) en vez de `content_scripts` declarados: sin listener en cada página y funciona en pestañas de fondo. `>>>` atraviesa shadow roots abiertos y frames del mismo origen; los frames de otro origen se cubren con `browser_read` sin selector (ids etiquetados por frame). Escritura: `execCommand('insertText')` con respaldo del setter nativo + `input`/`change`. Clic: secuencia pointer/mouse completa con `composed: true`.
- **X10 (§5)** Filtro sensible ampliado: `current-password`/`new-password`; los `hidden` no se listan.
- **X11 (seguridad)** `SO_NOSIGPIPE` en los fds aceptados por `BridgeListener` (arregla también 17: escribir a un relé que Chrome mató tumbaba la app) y `SIGPIPE` ignorado en el relé. La cerradura 1 (`argv[1]`) es defensa en profundidad: las reales son token + `getpeereid` (se dice en ADR 007).
- **X12 (18-4)** No existe pestaña «Navegador»: es un `Panel` en la pestaña de privacidad. El listener del navegador arranca al lanzar la app solo si hay un manifiesto instalado, independiente de prestar las manos. ADR 007 es el siguiente libre.
- **X13 (D5)** Rutas verificadas en esta Mac: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` y `~/Library/Application Support/Comet/NativeMessagingHosts/`. El puerto 37423 de Incredible sí existe (WebSocket local tras el intercambio de secreto), no se copia.
- **X14 (gates)** `gates.sh` corre `node --test` sobre la extensión si hay `node`; sin `node`, aviso, no fallo.

**Abierto para Karen (no bloquea construir):** criterio 5 publica las `browser_*` por el puente de 17, y `browser_read` de cualquier pestaña de fondo va más allá de `look`. Se construye como dice el criterio (detrás de *Prestar las manos* y de *Conectar navegador*); si prefiere solo escrituras o un interruptor aparte, es un cambio de una línea en `BridgeScope`. **D8 (CDP/`debugger`)** sigue fuera: los sitios que exigen `isTrusted` caen al `type_text` de Accesibilidad.

**Riesgos nuevos:** el renderizado en pestañas de fondo se pausa (un picklist puede no pintarse tras un clic); la sesión realtime y Claude Code fijan su lista de tools al abrir, así que si arrancaron antes que la extensión no ven las `browser_*`.

## 12. Fuera de alcance

`read_pdf`, `watch`/PiP, varios perfiles a la vez, Safari por extensión, Chrome Web Store, JXA, escribir sin hoja, cualquier backend o telemetría.
