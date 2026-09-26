# Wave 10b — El padre actúa

**Estado: ENTREGADA (2026-09-05).** Aprobada el mismo día por Karen («10b aprobado»). Gates verdes, 217 tests. Desviaciones respecto a este texto en la sección 9. Sale del mapa horizontal
(`AI_Research/AIResearch/COMPANION-MAP.md`, F4 y 4-D1). Segunda pieza de la
Wave 10. Se beneficia de 10a (el modelo sabe qué app hay enfrente antes de
abrir otra) pero no la requiere.

---

## 1. El defecto, en una línea

El turno conversacional no puede hacer nada por sí mismo: su única tool es
`delegate`, así que hasta "abre Safari" es un encargo.

### Lo que eso provoca, medido

| Camino | Tools del turno padre | Dónde |
|---|---|---|
| Chat | `[delegate]` | `ChatViewModel.swift` `consume`: `tools: [.delegate(config.language)]` |
| Voz realtime | `[delegate, resolve_approval, stop_job]` | `RealtimeRuntime.swift` `prepareSessionUpdate` |
| Voz clásica | `[]` | `ClassicRuntime.swift` `submit`: `tools: []` |

"Abre Safari" hoy: `delegate` → `JobRunner` → `JobQueue` (espera si hay otro
encargo) → `ExecutorProvider` (¿claude o nativo?) → `NativeExecutor` → 1-10
rondas de modelo → `run_shell "open -a Safari"` → `Approvals.request` → hoja
de permiso → 120 s o clic → `ProcessGroupRunner` → resultado → tarjeta →
línea de registro → acuse por voz. Para una acción de 30 ms, y **pidiendo
permiso** para algo que el usuario acaba de pedir en voz alta.

Y el prompt lo refuerza: `ChatPrompt.delegateRule` dice literalmente *"Never
say you cannot see the disk — delegate"*. El modelo aprende que no puede, y
delega hasta lo trivial. En clásico ni eso: cero tools, así que voz sin clave
es un chat sin manos.

El corpus tiene el ratio invertido: ~25 tools directas en el padre
(`open_app`, `open_url`, `open_file`, `list_apps`, `look_at`…) y
`start_large_task` solo para lo largo (spec 24 §5). PRODUCT-DECISIONS §7:
"fan-out es para leer/recolectar; escribir/actuar queda en el padre".

---

## 2. Lo que dice el corpus, y lo que ya tenemos

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| Corpus spec 24 §5, tabla de dispatch | `open_*` · `list_apps` → host; `read_file` · `write_file` · `run_*` → kernel/workspace; `start_large_task` → sub-agente | La partición: **abrir y mirar** es del padre; **leer, escribir y correr** es del especialista |
| Corpus MODULE-MAP `tools-desktop` | `list_apps`, `open_app`, `open_file`, `open_url` como crate propio, sin gate | El set mínimo |
| Corpus LAYERING §3 | Contrato = schema + validador + `ContractError` con `code` estable para que el modelo se recupere (`denied_path` → pide otra ruta) | El código de error viaja en el resultado de la tool |
| Relay `apps/desktop/src-tauri/src/contracts/mod.rs` | `http_url`, `app_name`, `resolve_home_file_in` **con tests table-driven**, incluido el escape por `..` a un hermano fuera de home | Se portan validadores y tests a Swift; más dos casos que la review de Relay encontró: symlink a directorio oculto, y `HOME` sin canonicalizar |
| ADR 001, nota de la séptima tool | Cada tool nueva exige un fallo observado y la prueba de que ninguna existente lo cubre | El fallo observado es este spec, sección 1. Ninguna tool existente abre una app sin `run_shell` + permiso |
| `EndpointPolicy` (Services) | http solo a localhost | **No aplica** aquí: gobierna *nuestras* peticiones. `open_url` abre el navegador *del usuario*; http a cualquier host es legítimo ("abre http://mi-router") |
| `NativeToolRunner.availableTools` | Una tool sin respaldo no se anuncia | Igual: `list_apps` siempre; `find_places` solo si `PlacesSearching` existe |

**Veredicto:** el padre necesita cuatro tools de acción, sin permiso, con
validadores que ya están escritos y probados en Relay, y un loop de una o dos
rondas en los tres caminos.

---

## 3. Decisión

### 3.1 `ParentTool` en Core: cuatro tools, y una compartida

```swift
public enum ParentTool: String, CaseIterable, Sendable {
    case openApp    = "open_app"     // { name }
    case openURL    = "open_url"     // { url }
    case openFile   = "open_file"    // { path }   bajo $HOME, abre en la app por defecto
    case listApps   = "list_apps"    // {}         corriendo + instaladas, tope 100
    public var spec: ToolSpec        // descripciones es/en, como NativeTool
}
```

`find_places` (ya `.safe`, ya sin disco) se ofrece **también** al padre: un
lugar no necesita especialista. `list_directory`, `read_file`, `web_fetch` y
todo lo que lee contenido se queda en el especialista con su sandbox.

**Por qué sin aprobación.** `open_*` ejecuta lo que el usuario pidió en la
misma frase; el riesgo es una URL o ruta inventada por el modelo, y eso lo
atrapa el validador, no una hoja. El corpus tampoco gatea `open_*`. Lo que sí
queda prohibido para siempre en el padre: `run_shell`. Si "abrir" necesita un
comando, es un encargo.

### 3.2 `ParentToolPolicy` en Core: validadores con código estable

```swift
public struct ContractError: Error, Sendable, Equatable {
    public var code: String      // denied_url · denied_path · invalid_args · not_found
    public var message: String
}
public enum ParentToolPolicy {
    public static func appName(_ raw: String) throws(ContractError) -> String
    public static func httpURL(_ raw: String) throws(ContractError) -> URL
    public static func homePath(_ raw: String, home: URL) throws(ContractError) -> URL
}
```

`homePath`, portado de Relay con las dos correcciones de su review:

1. `~` y `~/…` expanden; absoluta fuera de home → `denied_path`; relativa se
   resuelve contra home.
2. Componentes ocultos rechazados **antes y después** de resolver symlinks:
   `~/dotfiles/x` con `dotfiles → ~/.config` se niega.
3. `home` se canonicaliza una vez (`resolvingSymlinksInPath`) para que un home
   en volumen de red no niegue todo.
4. Resuelto debe seguir bajo home; si no existe, se valida el padre existente
   más cercano y se devuelve `not_found`, no `denied_path` — el modelo puede
   pedir otra ruta en vez de creer que no tiene permiso.
5. **Solo documentos y carpetas** (añadido tras el security review del
   2026-09-05): `NSWorkspace.open` *ejecuta* un `.command`/`.tool`/`.terminal`,
   lanza un `.app`, corre un `.workflow`/`.scpt`/`.applescript` y sigue la URL
   guardada dentro de un `.webloc`/`.inetloc` — una segunda puerta a `file://`
   o `javascript:` que `httpURL` nunca ve. Cualquier componente con esa
   extensión → `denied_path`; abrir una app tiene su propia tool. Entradas
   > 4096 bytes → `invalid_args` antes de tocar el disco.

El **código** viaja en el resultado de la tool:
`"denied_path: hidden path components are not allowed"`. Es lo que LAYERING §3
llama "el error como contrato": el modelo se recupera por el código, el humano
lee el mensaje.

### 3.3 `ParentToolRunner` en Services, sobre un puerto

Sin `Process`, sin `open -a`, sin PATH: todo por `NSWorkspace`. Detrás de un
puerto para que el runner sea testeable sin abrir nada:

```swift
public protocol WorkspaceOpening: Sendable {           // Core
    func openApplication(named name: String) async throws(ContractError)
    func open(_ url: URL) async throws(ContractError)   // http(s) o file://
    func runningApplications() -> [String]
    func installedApplications() -> [String]            // /Applications · /System/Applications · ~/Applications
}
```

`NSWorkspaceOpener` (Services) lo implementa: la app por nombre se busca en
los tres directorios y entre las que corren (`localizedName`); si hay varias
coincidencias exactas gana la instalada; sin coincidencia → `not_found` con
las tres más parecidas en el mensaje, para que el modelo corrija ("Safari" no
"Safari Technology Preview").

`ParentToolRunner.execute(tool:arguments:) async -> ToolResult` — misma forma
que `NativeToolRunner`, mismo `ToolResult`, sin `approved:`.

### 3.4 El loop del padre, en los tres caminos

- **Chat** — `ChatViewModel.consume` pasa de "un stream" a **hasta 3 rondas**:
  1. `stream(history, tools: parentSpecs + [delegate])`.
  2. `.toolCalls` con alguna `ParentTool` → se ejecutan en orden → por cada una
     una **línea de estado** en el hilo ("Abrí Safari" / "No encontré esa app:
     …") con `Recall` de tool (mismo mecanismo que 9d: `assistant` con
     `toolCalls` + `.tool` con el mismo id) → vuelve a stream.
  3. `.handoff` → `runJob` como hoy. Si en la misma ronda vienen tools del
     padre y `delegate`, primero las del padre, luego el encargo.
  4. Tercera ronda sin texto → se cierra con lo acumulado. El tope es un
     seguro, no un objetivo; en uso normal son una o dos.
- **Voz realtime** — `RealtimeRuntime.handle(.functionCall)`: antes del
  fallthrough a `delegate`, `ParentTool(rawValue: name)` → `onParentTool?` →
  `functionOutput(callId, output)` → `requestResponse()`. El server ya hace el
  loop; el cliente solo responde. `prepareSessionUpdate` declara las tools del
  padre junto a las tres actuales.
- **Voz clásica** — `ClassicRuntime.submit`: `tools: parentSpecs (+ delegate
  si jobs != nil)`. Loop de hasta 3 rondas como el chat; el texto de cada ronda
  va al `SentenceSplitter` como hoy (la frase previa a la acción se dice, luego
  se dice el resultado).

### 3.5 El prompt deja de decir "no puedes"

`ChatPrompt.delegateRule` se parte en dos, es/en:

- **`actRule`** (siempre que haya tools del padre): "You can open apps, URLs
  and files on this Mac and list what is installed, directly — do it, in one
  sentence. Say what you opened."
- **`delegateRule`** (si hay especialista): lo de hoy **menos** la frase "Never
  say you cannot see the disk — delegate", que pasa a "For anything that reads
  or changes files, runs commands or searches the web, call delegate."

Es un cambio de comportamiento del modelo. Se prueba a mano (sección 6); el
test automático solo garantiza que el prompt contiene lo uno y no lo otro.

### 3.6 Archivos que toca

| Capa | Archivo | Cambio |
|---|---|---|
| Core | `ParentTools.swift` (nuevo) | `ParentTool` + specs es/en + `WorkspaceOpening` |
| Core | `ParentToolPolicy.swift` (nuevo) | `ContractError` + 3 validadores |
| Core | `ChatPrompt.swift` | `actRule` / `delegateRule` |
| Core | `ChatPorts.swift` | `ChatDelta.toolCalls([ToolCallRef])` — **compartido con 10c**; si 10c va antes, ya está |
| Services | `NSWorkspaceOpener.swift` (nuevo) | adapter |
| Services | `ParentToolRunner.swift` (nuevo) | dispatch + `ToolResult` |
| Services | `RealtimeRuntime.swift` | dispatch de `functionCall` + tools en `sessionUpdate` |
| Services | `ClassicRuntime.swift` | loop ≤ 3 |
| Services | `VoiceSession.swift` | inyectar runner; `onParentTool` |
| UI | `ChatViewModel.swift` | loop ≤ 3, líneas de estado con `Recall` |
| UI | `ChatCopy.swift` + catálogos | "Abrí X" / "No encontré X" |
| App | `CompanionMain.swift` | construir `NSWorkspaceOpener` + runner, inyectar |
| Tests | `ParentToolPolicyTests.swift` · `ParentToolRunnerTests.swift` (nuevos); `ChatViewModelTests` · `ChatPromptTests` · `VoiceSessionTests` (ampliar) | abajo |

`FakeWorkspaceOpener` en `ChatFakes.swift`: registra qué se pidió abrir y no
abre nada.

---

## 4. Restricciones

- **Ninguna tool del padre pide permiso.** Si algún día una lo necesita, no es
  del padre.
- **`run_shell` nunca en el padre.** Ni con permiso.
- **Tope de 3 rondas** por turno del padre. Se registra si se alcanza.
- **El resultado de cada tool queda en el hilo como línea de estado** y en la
  memoria con `Recall` de tool. Es el registro de qué hizo la app sola, igual
  que el encargo deja el suyo (9-0).
- **Sin subprocesos** para abrir. `NSWorkspace` o nada.
- **Los códigos de error son contrato**: `denied_url`, `denied_path`,
  `invalid_args`, `not_found`. Cambiar uno es cambiar la API del modelo.
- **`open_file` bajo `$HOME`**, no bajo el workdir: el padre abre lo que el
  usuario nombra; el especialista edita dentro de una carpeta. Son alcances
  distintos a propósito.

---

## 5. TDD

Validadores (portados de Relay + dos casos nuevos):

1. `appName`: acepta "Safari", "Visual Studio Code", "Notes.app"; rechaza
   vacío, > 64, `/`, `\`, `;`.
2. `httpURL`: acepta `https://x`, `http://localhost`, `http://192.168.1.1`;
   rechaza `file:///etc/passwd`, `javascript:alert(1)`, `https://a b`,
   `HTTP://X` se normaliza.
3. `homePath` acepta `~/ok.txt` y devuelve la ruta canónica.
4. `homePath` rechaza `/etc/passwd` con `denied_path`.
5. `homePath` rechaza `~/.ssh/id_rsa` con `denied_path` y mensaje "hidden".
6. `homePath` rechaza el escape `<home>/nested/../<hermano-fuera>/secret.txt`
   (la ruta existe; se atrapa **después** de resolver).
7. `homePath` rechaza `~/link/x` cuando `link → ~/.config` (symlink a oculto).
8. `homePath` con `home` = ruta con symlink en el medio acepta `~/ok.txt`
   (canonicaliza home; el test de Relay pasaba y producción habría fallado).
9. `homePath` de un archivo que no existe bajo un padre válido → `not_found`,
   no `denied_path`.

Runner, con `FakeWorkspaceOpener`:

10. `open_app "Safari"` llama `openApplication(named:)` y devuelve `ok` con
    "opened Safari".
11. `open_app "Safar"` → `not_found` y el mensaje lista candidatos.
12. `open_url` con `file://` → `denied_url`, y el opener **no** fue llamado
    (se afirma el efecto, no el mensaje).
13. `open_file "~/.zshrc"` → `denied_path`, opener no llamado.
14. `list_apps` con 250 instaladas devuelve 100 y dice cuántas quedaron fuera.

Loop:

15. Chat: fake `ChatProvider` que emite `toolCalls([open_app])` y luego texto
    → el opener fue llamado una vez, el hilo tiene una línea de estado, y
    `historyForTests()` contiene `assistant(toolCalls:[id])` + `tool(id)`.
16. Chat: tres rondas seguidas de tool calls → se cierra en la tercera y se
    loguea el tope.
17. Chat: `toolCalls([open_app]) + handoff` en la misma ronda → primero se
    abre, luego `runJob`.
18. Realtime: `functionCall(name: "open_url")` → `functionOutput` con el
    resultado, `requestResponse` llamado, `onDelegate` **no** llamado.
19. Clásico: tool call → segunda ronda → el sintetizador recibió la frase de la
    segunda ronda.
20. `ChatPrompt.system` con tools del padre contiene `actRule` y **no** contiene
    "cannot see the disk" en ningún idioma.
21. `availableParentTools` sin `PlacesSearching` no incluye `find_places`.

---

## 6. Prueba manual (solo Karen)

- Voz: "abre Safari" → Safari al frente, **sin** hoja, **sin** tarjeta de
  encargo, una línea "Abrí Safari" en el hilo. Latencia perceptible: la del
  modelo, no la del queue.
- Chat: "abre la carpeta Descargas" → Finder en `~/Downloads`.
- Chat: "abre mi .zshrc" → responde que no abre archivos ocultos, y **no**
  delega para rodearlo (si delega, el prompt de 3.5 necesita otra vuelta).
- Voz: "busca cines cerca de Reforma" → mapa sin encargo (`find_places` en el
  padre).
- Voz: "crea un archivo prueba.md en el escritorio" → **sigue** siendo un
  encargo con permiso. La partición se respeta.

---

## 7. Fuera de alcance

- `look_at` / click / type sobre la UI enfrente (AX) — Wave 12+.
- `list_directory` / `read_file` en el padre. Leer contenido es del
  especialista y su sandbox.
- Recordar "abre X" como hábito o atajo.
- `reveal_file` (mostrar en Finder sin abrir). Cabe en `open_file` con un
  argumento el día que haga falta; hoy no hay fallo observado.

---

## 8. Fuentes

- Corpus: `specs/24-logic-trace.md` §5 (tabla de dispatch), `MODULE-MAP.md`
  (`tools-desktop`), `PRODUCT-DECISIONS.md` §7, `LAYERING.md` §3,
  `COMPANION-MAP.md` F4 y D1.
- Relay: `apps/desktop/src-tauri/src/contracts/mod.rs` (validadores + tests);
  review de 2026-09-05 (findings 4 y 5: home sin canonicalizar, symlink a
  oculto).
- Apple — `NSWorkspace.openApplication(at:configuration:)`,
  `NSWorkspace.open(_:)`, `runningApplications`.
- ADR 001 y sus dos notas (criterio para una tool nueva).
- Código del rebuild: `ChatViewModel.consume`, `RealtimeRuntime.handle`,
  `ClassicRuntime.submit`, `ChatPrompt.delegateRule`, `NativeToolRunner`
  (forma de `ToolResult` y de `availableTools`).

---

## 9. Desviaciones al implementar (2026-09-05)

| Sección | Decía | Se hizo | Por qué |
|---|---|---|---|
| 3.3 | `ParentToolRunner.execute(tool:arguments:) -> ToolResult`, "mismo `ToolResult`" | `ParentToolExecuting.execute(name:argumentsJSON:) -> ParentToolOutcome` (Core); el runner conforma al protocolo | `ToolResult` vive en Services y `CompanionUI` solo importa Core (gate de capas). El outcome lleva además `target` para la línea de estado |
| 3.3 | `WorkspaceOpening` "en Core" | Igual, en `ParentTools.swift` | — |
| 3.4 / 3.6 | `ChatDelta.toolCalls([ToolCallRef])` compartido con 10c | Se conserva el `.toolCall` singular actual: **una** tool del padre por ronda | Cambiar la forma del delta es el diseño de 10c (ensamblar por `index`); adelantarlo aquí lo habría hecho dos veces. Con el loop de 3 rondas el efecto práctico es el mismo salvo latencia |
| 3.4 voz clásica | `tools: parentSpecs (+ delegate si jobs != nil)` | Solo `parentSpecs` | Clásico nunca ha manejado `.handoff` (no tiene `onDelegate`); anunciar `delegate` sin ejecutarlo sería la misma promesa vacía que 9f cerró. Queda para cuando clásico tenga especialista |
| 3.6 | `ChatCopy` + catálogos ("Abrí X") | `ParentToolCopy` en Core, es/en por `switch` | Services también escribe estas líneas (`thread.appendStatus` en realtime y clásico) y no alcanza el catálogo; es el mismo patrón que `Escalation` |
| 3.4 chat | "Tercera ronda sin texto → se cierra" | La tercera ronda **ejecuta** sus tools y luego cierra, con línea de estado `ParentToolCopy.roundCap` | Tirar la tercera llamada sin ejecutarla dejaría al modelo creyendo que la hizo |
| 5.16 | "se loguea el tope" | Línea de estado en el hilo (chat) · `Log.app` (clásico) | `CompanionUI` no tiene logger; el hilo ES el registro |
| 3.2 | `homePath` canonicaliza con `resolvingSymlinksInPath` | `realpath(3)` para home y para la ruta | Foundation quita `/private`, realpath lo conserva: un home bajo `/var` no coincidía consigo mismo. Lo encontró el primer test en rojo |

### Security review (2026-09-05)

| Severidad | Hallazgo | Estado |
|---|---|---|
| CRÍTICO | `open_file` no filtraba tipo: `.command`, `.app`, `.webloc`/`.inetloc` bajo home se ejecutaban/lanzaban por `NSWorkspace.open`, rodeando `run_shell` y el filtro de esquemas | **Cerrado** con test en rojo primero (`testHomePathRefusesLaunchers`, `testOpenFileRefusesLaunchers`): lista de extensiones lanzadoras → `denied_path`, en todos los componentes de la ruta |
| MEDIO | TOCTOU entre `realpath` y `NSWorkspace.open` (symlink cambiado en medio) | Residual, marcado con `HACK:` en `NSWorkspaceOpener.open`; no hay API por fd/bookmark. Requiere ejecución local previa como el mismo usuario |
| MEDIO | `open_app` resuelve el nombre en un barrido y el adapter vuelve a barrer el disco | Abierto, mismo requisito que el anterior. Fix futuro: el puerto devuelve la URL del bundle resuelto |
| BAJO | Sin tope de longitud en `httpURL`/`homePath` | **Cerrado**: 4096 bytes → `invalid_args` |

### Code review (2026-09-05)

| Severidad | Hallazgo | Estado |
|---|---|---|
| ALTO | `actRule` nunca llegaba al modelo: `ChatSSEAttempt.makeBody` y `RealtimeRuntime.instructions` no pasaban `parentToolsEnabled`; los tests probaban `ChatPrompt.system` aislado | **Cerrado**. `ParentToolPromptWiringTests` lee el cuerpo real de la petición y las instrucciones reales de la sesión; `makeBody` deriva la bandera de las tools declaradas (como `delegate`) |
| ALTO | La tarjeta de `find_places` se perdía en voz (`ConversationPresenting` solo habla texto) | **Cerrado**. `onCard` en ambos runtimes → `onJobEvent(.card)`, el mismo seam que pinta el mapa de un encargo. Test `testRealtimeParentToolCardReachesTheThread` |
| MEDIO | Clásico pegaba el fragmento sin punto de una ronda con la primera palabra de la siguiente | **Cerrado**: el fragmento se dice antes de la ronda siguiente. Test `testClassicFlushesFragmentBeforeNextRound` |
| MEDIO | Sin chequeo de cancelación entre llamadas de una misma ronda (chat) | **Cerrado**: `Task.isCancelled` por llamada |
| MEDIO | Una tarjeta entre dos respuestas `tool` del mismo turno assistant rompe el historial en algunos proveedores | **Cerrado**: respuestas primero, tarjetas después. Test `testParentToolCardsComeAfterAllToolAnswers` |
| BAJO | `ClassicRuntime.submit` > 50 líneas | Extraído `act(_:said:using:language:)` |
| BAJO | Clásico no anuncia `delegate` | Desviación documentada arriba, intencional |

### Primera prueba manual (Karen, 2026-09-05)

Chat «abre safari, puedes?» → `not_found: no app named Safari` → el modelo
llamó `list_apps` solo y se recuperó (el contrato de error funcionó) — pero
Safari no estaba en la lista. Causa: en macOS 26 `/Applications/Safari.app`
es un symlink a `/System/Cryptexes/App/System/Applications/Safari.app` y
`contentsOfDirectory(at:…, options: [.skipsHiddenFiles])` no lo devuelve;
`contentsOfDirectory(atPath:)` sí. **Cerrado** con test que falla primero
(`testRealOpenerFindsSafari`, depende de la máquina a propósito) y
enumeración por ruta + raíz del cryptex. Observación de producto: el modelo
llamó "navegadores" a ChatGPT y Slack — `list_apps` sin categoría deja al
modelo adivinar; candidato para 10c o para una descripción de tool mejor.

Resto de la prueba manual (sección 6) pendiente.
