# Ledger de referencia — companion original

El valor del repo original (`../companion`) no esta en su estructura sino en
las cicatrices: comportamientos ganados a base de bugs reales. Antes de portar
cualquier feature, buscarla aqui. Las referencias archivo:linea apuntan al
repo original.

## Audio / AEC (las mas caras de redescubrir)

- Voice Processing de Apple a veces no entrega NINGUN buffer del microfono.
  Watchdog de 1.5 s: si no llego ni un buffer, apagar Voice Processing y
  reintentar una vez (`RealtimeWiring.swift:306-318`). Sin backoff en el
  original; el rebuild debe limitar reintentos.
- **El reintento sin VPIO debe ESPERAR al HAL** (`Hermes.swift
  retryWithoutVP`, la parte que este ledger omitio y costo tres iteraciones
  en Wave 3): VPIO desarma su dispositivo agregado de forma ASINCRONA; el
  HAL reporta 0 Hz mientras tanto, y un engine que vio 0 Hz se queda con el
  para siempre. Sondear con un engine FRESCO por intento, hasta ~2 s, antes
  de rendirse. Reintentar de inmediato = fallo garantizado.
- VPIO no arranca con cualquier entrada (multicanal/agregada:
  kAUInitialize -10875) y el fallo deja el engine zombi. El original ademas
  PERSISTIA el veto entre corridas (`VoiceSettings.aecVetoed`): reintentar
  VPIO en cada arranque "solo envenena el HAL". El rebuild usa veto
  in-process; si el 0 Hz reaparece entre lanzamientos, portar la
  persistencia.
- Dos instancias con VPIO compiten por el dispositivo: el prototipo se
  instala como item de login (`install.sh`) y revive al iniciar sesion —
  cerrar el viejo antes de probar el nuevo.
- Echo guard: ~350 ms tras audio del agente donde una "interrupcion" se trata
  como eco, no como barge-in (`RealtimeVoice.swift`, `echoGuardUntil`).
- Con AEC del engine compartido, el player de Realtime se cuelga del engine
  del microfono en vez de crear el suyo (`RealtimeAudio.swift`, `ownsEngine`).
- PCM 24 kHz mono int16 little-endian en ambos sentidos; el encoder reserva
  +16 frames de slack para el resampling (`RealtimeAudio.swift:24`).
- Firma estable ("Companion Dev" cert) o TCC revoca microfono/voz en cada
  build (`build.sh` del original, `docs/make-signing-cert.sh`).

## OpenAI Realtime (contratos no obvios)

- Mute NO es dejar de mandar audio: el server espera oir silencio. Hay que
  mandar commit + response.create a mano al mutear
  (`RealtimeVoice.swift:347-370`).
- La voz NO puede cambiar despues del primer audio de la sesion; la velocidad
  si (contrato session.update, `docs/PROTOCOL-REALTIME.md`).
- El schema de tools en Realtime es PLANO, no anidado como en chat/completions
  (`RealtimeProtocol.sessionUpdate`).
- turn_detection: server_vad (silence_duration_ms, default 700) vs
  semantic_vad (eagerness low/auto/high = 8s/4s/2s).
- No hay resume de sesion: al caerse, sesion nueva sembrada con los ultimos
  6 turnos recortados a 200 chars; las imagenes no sobreviven
  (`RealtimeVoice.swift:170-177`).
- WebRTC: el audio viaja por tracks, no por deltas (`carriesAudio`); fases
  llegan por output_audio_buffer.started/stopped; mute = track.enabled=false.
- Cadena de fallback: WebRTC (timeout 12 s) -> WebSocket (6 s) -> pipeline
  clasico (mic + STT local + TTS). Cada caida se loguea.

## Chat / TalkClient

- Cadena de proveedores OpenAI -> Groq -> Ollama; si ya se HABLARON frases de
  una respuesta parcial, no se reintenta con el siguiente proveedor
  (`spokePartial`, `TalkClient.swift:278-283`).
- Corte de frases para TTS: terminador (.!?) SEGUIDO de espacio/salto (no
  parte "3.14"), minimo 25 caracteres (`TalkClient.swift:135-161`).
- Tool call `delegate` {goal, context}: un call malformado o truncado NO
  delega — se habla el texto que haya (`TalkClient.swift:374-385`).
- Timeout por proveedor: 15 s de INACTIVIDAD, no total; 60 s tope del turno.
- Ventana de historial: 20 turnos; adjuntos inline (imagen -> image_url,
  texto legible -> bloque de texto, binario -> no viaja).

## Delegacion (claude -p / Hermes)

- `claude -p` con stream-json bidireccional NDJSON por stdin/stdout; el
  proceso PERSISTE entre encargos si el workdir no cambio
  (`ClaudeStream.swift`, `JobRunner.swift:110-115`).
- Approvals: `control_request` subtype `can_use_tool` -> dialogo o voz;
  auto-deny a los 120 s con mensaje "sin respuesta" para que el especialista
  busque otra ruta (`JobRunner.swift:142-150`).
- `--allowedTools WebSearch,WebFetch` pre-aprobados para no pedir permiso por
  cada lectura web (`ClaudeStream.swift:183`).
- Rol del ejecutor se inyecta UNA vez por sesion (`Escalation.executorRole`).
- Cola serial: un job a la vez, presupuesto 15 min, fallback a Hermes batch
  si el proceso de claude murio (`JobRunner.swift:69,167-179`).
- Timeline de pasos: tool_use -> JobStepInfo -> resumen "2 busquedas · 1
  archivo" (`JobSteps.swift`).

## Endpointing (pipeline clasico)

- Dos umbrales sobre transcript estable: 0.6 s frase completa / 2.6 s frase
  colgante (heuristica de ultima palabra, `SpeechCues`); voiceFloor 0.06;
  tope absoluto de utterance 45 s (`Endpointer.swift:72-74`).
- Endpointer RMS de respaldo cuando no hay permiso de Speech: calibracion
  0.4 s, margen 0.045 sobre el piso, 0.25 s de habla antes de speechStarted.

## TTS clasico

- Frases <=80 chars se cachean en disco por hash fnv1a (avisos repetidos).
- OpenAI `gpt-4o-mini-tts` primero, Hermes/Python fallback con kill a 30 s.

## UI / contratos de cards

- Fences `companion:locations` y `companion:gallery` en el markdown del
  agente se renderizan como cards nativas; JSON invalido degrada a bloque de
  codigo (`CompanionBlocks`, `ChatMarkdown.swift:59-66`).
- `reportCut`: primer bloque = resumen visible, resto plegado, fuentes
  extraidas de la seccion "Sources/Fuentes" (`MarkdownSplitter.swift:34-48`).

## Anti-patrones del original que NO se portan

- Semaforo bloqueando `Task.detached` (`TalkClient.swift:345-372`).
- Contador `generation` manual para cancelar turnos (usar Task cancellation).
- 10+ callbacks cableados a mano (`RealtimeWiring.swift:13-177`) -> AsyncStream.
- AppDelegate god-object con ~20 vars de estado (`main.swift:10-44`).
- `try?` silencioso en I/O (EnvKeyStore, ClaudeStream.submit).
- Paths hardcodeados a `~/.hermes/*` — en el rebuild todo pasa por Config.
- Dos sistemas de color (Palette vs Tokens) y dos de timing (Motion vs
  MotionTime): aqui hay UNO de cada uno.

## Cicatrices propias del rebuild (no venian del prototipo)

Descubiertas en prueba manual de Wave 3; ningun test las vio.

- **AVAudioEngine vacio mata el proceso.** `prepare()`/`start()` sobre un
  engine recien creado, antes de conectar nodos, hace que AVFoundation arme
  su grafo de I/O por defecto y toque el microfono que el engine del mic ya
  tiene abierto: lanza una NSException que Swift NO puede capturar y el
  proceso aborta. Reglas: conectar el grafo ANTES de arrancar, y nunca
  `prepare()` — `start()` reporta el fallo como error de Swift, del que si se
  puede degradar (`RealtimePlayer.start`).
- **Un bundle sin usage descriptions no puede pedir microfono.** `swift run`
  produce un binario suelto; macOS jamas muestra el prompt. Ver
  `scripts/bundle.sh` y el gate que lo vigila.
- **Bundle id compartido con el prototipo.** Con el mismo
  `com.karen.companion`, LaunchServices abria la app vieja al pedir la nueva.
  El rebuild usa `com.karen.companion.next` y su propio archivo de log.

- **"Sin red" y "el servidor no contesta" no son el mismo fallo.** Caer al
  pipeline clasico es correcto cuando el WS no responde pero hay internet;
  sin internet solo cambia un error legible por un microfono escuchando en
  silencio (el clasico tambien necesita chat y TTS remotos). La sesion
  consulta `ReachabilityProbing` (NWPathMonitor) antes de decidir.
- **Sin AEC no hay barge-in por voz.** Con Voice Processing apagado no se
  mandan frames en `.speaking`, asi que el VAD del servidor nunca oye a la
  usuaria interrumpir. Por eso el default cambio a AEC on (desviacion 8 del
  spec de Wave 3 queda revocada); el watchdog cubre el riesgo de VPIO.

- **VPIO no levanta con dispositivos dispares** (`kAUInitialize -10875`).
  Limitacion conocida del framework (foros de Apple 772006 / 810129): el
  agregado que arma VPIO falla si entrada y salida no casan en canales — un
  dispositivo virtual (Teams) en la cadena basta. La tecnica documentada de
  Apple es fijar AMBOS buses del unit con
  `kAudioOutputUnitProperty_CurrentDevice` antes de inicializar; en esta Mac
  ni asi levanta. Los stacks de voz en produccion (LiveKit) tratan VPIO como
  opcional y caen a AEC por software.
- **Tras un VPIO fallido, el engine simple hereda el agregado roto**: la
  entrada reporta 3 canales en vez del micrófono integrado (1 ch) y el grafo
  arranca sin entregar un solo buffer. Fijar la entrada del engine plano al
  dispositivo integrado (`AudioDevicePin.pinInput`), no confiar en el default
  del proceso.
- **Salida sin eco = AEC innecesario.** Con audifonos o bluetooth no hay
  realimentacion acustica, asi que se pueden mandar frames mientras el agente
  habla y el barge-in por voz funciona sin VPIO. Detectar por transport type
  y data source del dispositivo de salida.
- **Keys importadas desde la terminal piden contrasena en cada arranque.**
  Un item creado por `security` solo confia en esa herramienta; hay que
  declarar la app con `-T <ruta al binario>` (con firma estable, la confianza
  sobrevive a los rebuilds). Cuando la usuaria pega la key en el onboarding
  esto no ocurre: la app es duena del item.

- **Una app GUI no hereda el PATH del shell.** `which claude` en subproceso
  dice "no instalado" con claude instalado, y cualquier ruta hardcodeada
  apunta a donde no es (`~/.local/bin` es donde instala el instalador
  oficial). La unica verdad es el sistema de archivos: `CLIBinaryLocator`.
- **`-m` no es un flag de `claude`; es `--model` con alias corto** (opus/
  sonnet/haiku). El prototipo lo hacia bien (`Model.swift:147`); el rebuild
  lo invento y el proceso moria en argparse.
- **Un pipe entrega bloques, no lineas.** `readData(ofLength:)` parte o pega
  el NDJSON; sin buffer de lineas el parser recibe basura silenciosa.
  `LineBuffer` en Core + regresion con lineas de 20 KB.
- **`hermes chat -Q` toma el prompt como argumento `-q`**, no por stdin
  (`Hermes.swift:308-313`); mandarlo por stdin lo deja esperando el EOF.
- **JSONSerialization escapa `/` como `\/`.** Un assert `contains("/ruta")`
  sobre JSON serializado falla aunque la ruta viaje bien.
- **Helpers @MainActor + runAsync se abrazan.** El `runAsync` del TestKit
  bloquea el main thread con un semaforo; un helper @MainActor llamado
  dentro de su closure detached espera un actor que no va a soltarse:
  timeout de 5 s disfrazado de CancellationError. Los helpers que se usen
  dentro de runAsync van nonisolated.

## Percepcion del sistema (Wave 10a)

- **Accesibilidad va atada a la firma, como el mic.** El grant se concede a
  mano en System Settings › Privacidad › Accesibilidad y queda ligado a la
  identidad de firma: un rebuild con otro cert lo borra en silencio y
  `OpenDocumentsSensor` vuelve a `[]` sin error. Por eso `isTrusted()` se
  relee en cada `sense` y la fila de Ajustes lo muestra; sin `scripts/
  make-signing-cert.sh` estable, cada build pide el permiso otra vez.
- **El prompt de Accesibilidad sale UNA vez** por app + firma
  (`AXIsProcessTrustedWithOptions` con `AXTrustedCheckOptionPrompt`); tras
  negarlo, devuelve `false` sin UI. El deep link
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
  es la unica salida que no se agota.
- **`frontmostApplication` somos nosotros** cuando la usuaria le habla a la
  ventana: el sensor reporta la ultima app activada que no es Companion
  (`didActivateApplicationNotification`). Sin eso `<focused_app>` diria
  siempre "Companion".
- **`kAXDocumentAttribute` no existe en Electron**; VS Code y Chrome dan
  titulos de ventana, y Chrome es una ventana AX por ventana, no por pestaña.
  Lo que hay es titulo o nada (spec 09: resumenes, no volcado de AX).
- **`NSPasteboard` en macOS 15.4+ puede avisar por cada lectura**
  (`accessBehavior`). El canal nace apagado y solo lee si `changeCount` se
  movio.
- **La espera con presupuesto no puede ser un `TaskGroup`** con el hijo que
  bloquea dentro: el grupo espera a todos sus hijos al salir. Los sensores
  corren `Task.detached` y `sense` compite una continuation contra un sleep;
  lo que llego tarde se descarta.
- **El constante `kAXTrustedCheckOptionPrompt`** es un global no
  concurrency-safe bajo Swift 6; se usa su valor documentado como string.

## Tool calls y permisos (Wave 10c)

- **Dos calls en una respuesta llegan intercaladas por `index`** (0,1,0,1).
  Leer `tool_calls.first` las funde. `index` es el único campo required del
  fragmento; `id` y `name` llegan en el primero. Ollama y algunos
  compatibles no mandan `id`: se inventa uno estable por ronda.
- **`strict: true` solo en OpenAI.** Exige `additionalProperties: false` y
  todo en `required` (lo opcional como `["string","null"]`). Los
  compatibles contestan 400 al campo; `supportsStrictTools` decide por id
  hasta leer el 400 real.
- **Reparación de argumentos** (`ToolArguments`): solo si
  `JSONSerialization` falló; la lista de json_repair; lo super roto es
  `nil` → `invalid_args: could not parse arguments: <crudo>`.
- **Permisos**: `Approvals` es un actor con continuations; auto-deny a los
  120 s con `Task.sleep` cancelable. La memoria (`ApprovalKey`,
  `Tool(patrón *)`) vive en el actor y muere con el proceso. Deny gana.
  Negar devuelve `denied_by_user: …` (`Escalation.deniedByUser`).
- **`open_url` con puerta** cuando el host no aparece en las palabras de la
  usuaria (URL entera, host sin `www.`, o etiqueta registrable ≥ 3 letras
  no seguida de punto). Chat, clásico y realtime pasan por el mismo actor y
  la misma hoja. En clásico el turno de voz espera a la hoja (o al
  auto-deny); en realtime el texto de referencia es el último
  `commitWithText`.

## Skills y knowledge (Wave 11a)

- **Formato Agent Skills, literal**: `name` 1-64, `[a-z0-9]` y guiones
  simples, igual a la carpeta, sin `anthropic`/`claude`; `description` 1-1024
  sin tags XML. El parser (`SkillFrontmatter`) es `clave: valor` plano,
  `>`/`|` pliega líneas, `metadata:` y lo desconocido se ignoran. Sin
  librería YAML.
- **El cuerpo nunca va al prompt.** Solo la línea de catálogo (nombre —
  descripción — ruta), escapada y con topes en scalars (`SkillCatalog.Caps`:
  240 / 32 / 6 000). Cabe quitando custom desde el final; una del sistema
  nunca cae.
- **Raíces con modo** (`PathValidator.Root`): workdir rw, `skills/default`
  ro, `skills/custom` rw, `knowledge` rw, `memory` rw. Un relativo sin
  workdir no resuelve. Escribir en ro devuelve `denied_path: …` (contrato),
  no "outside". `write_file` crea la carpeta padre.
- **Línea de sync** solo sobre `<raíz>/<name>/SKILL.md` o `KNOWLEDGE.md`
  (`SkillsLocation.classify`, un nivel). El archivo se escribe aunque el
  frontmatter falle; el `failed — por qué` es para que el modelo reescriba.
- **`read_skill`** solo por nombre del catálogo; una ruta no es un nombre
  válido → `not_found` sin mirar el disco. Se anuncia solo si hay store.
- **`default/` se regenera desde el bundle** en cada arranque cuando difiere
  (también lo editado a mano). El bundle de Services requiere
  `resources: [.copy("Skills")]` en `Package.swift`; `bundle.sh` copia
  los `.bundle` de SPM a `Contents/Resources`, y se leen por
  `ServicesResourceBundle`, no por `Bundle.module` (cicatriz de abajo).
- **Cicatriz (21c): `Bundle.module` hace trap en la app empaquetada.** El
  accessor que genera `swift build` nativo (Swift 6.3.3) busca el bundle en
  la RAÍZ de la `.app` y en la ruta absoluta del `.build` del checkout, y si
  no, `Swift.fatalError`: nunca mira `Contents/Resources`, que es donde lo
  deja `bundle.sh`, y ningún `do/catch` lo atrapa. La app instalada
  funcionaba solo porque el `.build` existía en esta Mac; un DMG en otra
  Mac moría en `Fonts.register()`. Ahora cada módulo con recursos pasa por
  su resolver (`UIResourceBundle`, `ServicesResourceBundle`, orden en
  `ResourceBundleLocator`): `Contents/Resources` → junto al ejecutable →
  `Bundle.module` solo si su bundle de build existe → `nil`, y el recurso
  degrada. Un test de escaneo falla si `.module` aparece fuera de los
  resolvers. Fuente: `docs/research/recursos-empaquetados-bundle-module.md`
  §2, §7, §8.
- **Cicatriz**: la memoria nunca llegaba al chat tecleado (`makeRequest` no
  la reenviaba a `makeBody`). Cualquier cosa nueva que entre al system
  prompt por `ChatSSEAttempt` necesita el test de request, no solo el de
  `ChatPrompt`.

## El reductor de sesión (Wave 12a)

- **Dos máquinas, una proyección.** `TurnMachine` sigue mandando en la
  captura (idle → connecting → listening → thinking → speaking → error).
  `SessionMachine` la observa por `.voice(TurnSnapshot)` y decide el chrome:
  Idle / Hover / Listening / Processing(fase). `error` es de la voz; la
  sesión lo proyecta como `interruption = .failure` + card, y vuelve a Idle.
- **Quién escribe qué.** Solo `SessionModel.send` muta `projection`
  (`private(set)` + regla `session-kind-write` en `conformance/ui-contract.json`,
  que desde 12d cubre los once campos).
  `ChatViewModel` manda eventos (`typedSubmitted` / `typedReplyStreaming` /
  `typedReplyFinished`, `parentActing` / `parentActed`, `job(e)`,
  `approvalAnswered`, `stop`) y lee `session.projection`. `VoiceViewModel`
  reenvía cada snapshot. Las vistas leen `chat.session.projection`.
- **Un stream hacia fuera.** `VoiceSession.events` lleva `.job(e)` (encargo
  por voz, cards del padre, peticiones de `open_url`), `.parentActing /
  .parentActed` y `.approvalSettled` (el "sí" hablado). `CompanionMain` lo
  bombea a `ChatViewModel.receive`, que escribe el hilo y reenvía al
  reductor. Los closures que quedan en `VoiceSession.init` son órdenes del
  modelo (`onDelegate`, `onStopJob`, `onResolveApproval`, `onMCPApproval`):
  pasan a efectos en 12b.
- **Efectos y puertos.** `cancelJob` → `JobSubmitter.cancel`;
  `resolveApproval(id, ok, remember)` → `ApprovalsProvider` si hay actor,
  si no el submitter; `scheduleCompletedExpiry` → `sleep` inyectable (el
  siguiente evento que saque el kind de Completed lo cancela);
  `logTransition` → `log` inyectado (`Log.app` en la app).
- **Reglas que el reductor absorbió.** Negar el PRIMER paso para el encargo
  (10c 3B.4) y no recuerda; negar uno posterior solo lo niega. Stop niega
  la cola entera. Un paso huérfano abre la tarjeta sin nombre; `.started`
  la nombra después. `jobFinished` sin encargo no hace nada.
- **Cards son de un paso.** `projection.cards` se vacía en cada evento; lo
  que deba durar (el enlace a Ajustes) sale de `interruption`, que dura
  hasta que la sesión sale de Idle.
- **Cicatriz**: la hoja no se cerraba tras un "sí" hablado porque la voz y
  la UI tenían dos nociones de "pendiente". Todo lo que resuelva un permiso
  fuera de la hoja tiene que emitir `approvalSettled`.

## Dictar en el campo enfocado (Wave 12e)

- **Una bifurcación del hold, no un kind.** `DictationRouter.destination`
  (Core, pura) decide **al pulsar** con el modo (`VoiceSettings.mode`:
  `agent`, `dictation`, `automatic`), el campo enfocado de la app de
  delante (`FocusedFieldProbing`) y la confianza AX. `VoiceSession.hold()`
  guarda `dictationTarget` y emite `.dictating(app:)`; al soltar,
  `commitTurnFromNative` llama a `TextInjecting.inject` y emite
  `.dictated(app:)` en vez de `commitWithText`. Cualquier fallo del
  inyector (`fieldGone`, `refused`, `needsAccessibility`) manda las
  palabras a Companion: nada se pierde y nada se pega en otra app.
- **El reductor** solo gana `projection.dictation` (la app): se escribe en
  Listening, sobrevive Pending y Completed (`.dictated` → Completed con su
  temporizador), y se borra al salir de esas fases, en `begin()` y en Stop.
  `.dictationFailed(.needsAccessibility)` es un aviso
  (`.permission(.accessibilityDenied)`) sin transición: el turno del
  agente es dueño del kind y el aviso se ve al reposar.
- **La sonda no está en el camino de la pulsación.** `routeHold` lanza una
  `Task.detached` y `commitTurnFromNative` espera su resultado al soltar;
  cada llamada AX lleva `AXUIElementSetMessagingTimeout` de 0,25 s. Una app
  colgada delante retrasaba el micro y congelaba el actor de voz entero
  (revisión 12e). Un rebote de la pulsación conserva el destino decidido.
- **`AXTextInjector`** (Services): sonda `kAXFocusedUIElementAttribute` de
  la app de delante (nunca Companion), rol `AXTextField`/`AXTextArea`/
  `AXComboBox` o `AXValue` settable; `AXSecureTextField` es un campo
  seguro y nunca objetivo. Inyecta con `kAXSelectedTextAttribute` (inserta
  en el cursor, respeta la selección) y, si la app lo ignora, portapapeles
  + Cmd+V por `CGEvent`, restaurando a los 300 ms **todos** los tipos que
  había, y solo si `changeCount` dice que nadie más escribió en el
  portapapeles mientras tanto. Vuelve a comprobar el `pid` y el rol al
  soltar. El inicializador falla sin bundle id propio: sin él Companion no
  podría excluirse a sí misma de los destinos. La constante del
  rol seguro no existe en el framework: es el literal `"AXSecureTextField"`.
- **Lo dictado no se loguea.** `audit.logTurn()` se salta en el camino del
  dictado; el log dice `dictation: pasted N chars into <app> via ax|paste`.
  Puerta `dictation-never-logged` en `conformance/hud-gates.json`.
- **La manos libres y el clásico** (sin clave) siempre hablan con
  Companion: `routeHold` solo corre con realtime.

## El libro de puertas del HUD (Wave 12d)

- **`conformance/hud-gates.json`**: las puertas del auditor
  (`relay-hud-spec/05` §10, `00` §3) como data: id, fuente, afirmación,
  tests que la prueban y reglas del contrato que la vigilan.
  `hudGatesTests` (en `ConformanceTests.swift`) comprueba que cada test
  citado corre (`Conformance.testRuns`: `func <nombre>(` en las líneas
  lógicas de `Tests/`, con `@Test` o invocado desde otra
  línea) y cada regla existe; no ejecuta nada, `swift test` ya lo hace.
  `testTheLedgerKeepsItsTenGates` fija los diez ids (`HUDGates.expected`).
  Una puerta nueva se añade con su test y en esa lista; un test que se
  borra o deja de llamarse rompe la puerta que lo citaba.
- **`main-activation`**: `Sources/CompanionUI` nunca activa la app
  (`NSApp.activate`, `NSApplication.*.activate`, `activate(options:)`,
  `makeKeyAndOrderFront`, `.makeKey()`, `.orderFront(`); traer main lo
  decide `CompanionMain` por `onShowMain`. `orderFrontRegardless` y
  `orderOut` en la island no roban el foco y no cuentan.
- **`HUDContractTests.swift`**: cuatro kinds por `switch` exhaustivo (un
  quinto no compila), Stop desde cada kind alcanzable, la puerta del padre
  cerrada sin actor (Services y UI), el cuerpo de `read_skill` fuera del
  `ConversationStore` (vive en `Recall`, la memoria del turno).
- **`ContractError.deniedByUser`**: la única denegación del padre;
  `Escalation.deniedByUser` es su `wire` (mismo texto). El mensaje sin
  código está en `Escalation.deniedByUserMessage`.

## Ver lo que oye: parciales, un turno por hold, tiempos (Wave 12c)

- **El parcial es un campo, no un kind.** `SessionEvent.partialTranscript`
  solo escribe `projection.partial` en Listening; sobrevive a Pending y se
  borra al salir de esas dos fases y en `begin()`. `IslandState.partial`
  lo lleva en `.listening` y `.pending`; la island lo pinta con la cola
  visible (`truncationMode(.head)`).
- **De dónde sale.** `VoiceAudit.partials` es el stream del oído nativo;
  `VoiceSession.pumpPartials()` lee `turnText()` **en el actor** (así ve
  un `committed` estable) y lo emite solo con `holdOpen` (`holdArmed &&
  listening && !muted`). La manos libres no emite parciales.
- **El oído arranca al pulsar.** `openRealtimeSession` arranca el pump de
  frames y `beginEar` (una `Task` sobre el actor, no `async let`: el
  audit vive en el actor) antes de `transport.open`; el camino de ready
  la espera. Si la sesión muere mientras, `beginEar` apaga el oído.
- **Un hold es un turno.** En una sesión con `holdArmed`, `pumpEarTurns`
  ignora `.speechStarted` y `.finished` (también tras soltar o tras un
  tap: lo tardío no es un turno). Al soltar viaja `turnText()`, y cada
  pulsación hace `audit.consume()` para que lo tardío del hold anterior
  no se cuele. Cierra el HACK de 12b §9.9. La versión con `heldSegments`
  perdía el segmento en vuelo y enviaba segundos turnos (revisiones).
- **`TurnTimeline`** (Core, pura): la primera marca gana; `line()` es
  `nil` sin `pressed`; huecos como «—». `VoiceSession.flushTimeline()` la
  escribe al primer audio del agente, al colgar o al pulsar de nuevo;
  `lastTimeline` la guarda para tests. Nunca texto, solo milisegundos.
- **`prewarm()`** en boot (`CompanionMain`, `Task.detached`: una tarea
  `.utility` heredada por el main actor nunca corrió ahí):
  `mic.prewarm()` (solo con el micro ya autorizado: `prepareEngine` +
  sin `engine.prepare()`, que sin tap lanza una excepción y mata la app)
  y alcance de red. Una línea
  `prewarm:`. Ni permisos, ni sockets, **ni llavero**: leer la clave en
  boot abrió el diálogo del llavero en la build de desarrollo (la ACL del
  item no lista esa firma) y bloqueó la tarea. El socket realtime no se
  precalienta: vida máxima y cierre por inactividad lo dejarían muerto al
  pulsar.
- **`holdLearned`** (`IslandPreference.holdLearned`): lo escribe la island
  al ver `.processing(.pending)`; el hover deja de enseñar el hold, el tap
  lo pide siempre.

## Mantener FN y la island (Wave 12b)

- **Tres máquinas, un hold.** `HoldKeyClassifier` (Core, puro) decide tap
  vs hold por duración y emite `pressed` al bajar, no al confirmar.
  `SessionMachine` recibe `pressed / released / tapped` y emite
  `startListening / stopListening(commit:) / cancelVoiceOutput`.
  `TurnMachine` recibe `holdPressed / holdReleased / holdDiscarded /
  interrupt`. `VoiceSession.hold() / release() / discard() / interrupt()`
  son el puerto.
- **Soltar es ForceEndpoint.** `holdReleased` en realtime = `muted` +
  `.commitWithText`; no depende de `speechOpen` (el VAD del servidor).
  Vacío → `VoiceSession` emite `SessionEvent.heardNothing`, nunca
  `.utteranceEmpty` (ese cae al clásico).
- **Entre holds la sesión sigue abierta con el micro cerrado.** Para el
  reductor, `listening + muted` es reposo (Completed con timer si venía de
  processing, Idle si no), salvo en Pending. `realtimeSessionReady` ya no
  fuerza `muted = false`: una suelta antes de ready deja el micro cerrado.
- **La island no decide nada.** `IslandState.from(projection,
  pebbleHidden:)` es la única función que traduce la proyección a chrome
  (tamaño por rol, medidor, línea, Stop, hoja). `IslandPanel`:
  `.nonactivatingPanel`, `.statusBar`, todos los Spaces, `canBecomeKey =
  false`; hover por `NSTrackingArea .activeAlways`. El alto lo mide la
  vista (`PreferenceKey`) y el panel se re-ancla en `visibleFrame.maxY`.
- **El tap de FN.** `HoldKeyTap` (Services): `CGEvent.tapCreate` en
  `.cgSessionEventTap`, `.listenOnly`, máscara solo `flagsChanged`, keycode
  63, bit `.maskSecondaryFn`; run loop propio; se re-arma en
  `tapDisabledByTimeout`. `CGPreflightListenEventAccess` antes de instalar;
  `applicationDidBecomeActive` reintenta tras conceder el permiso. Sin
  clave de Info.plist: Monitoreo de entrada no tiene usage description.
- **Ajuste del sistema que rompe FN:** Teclado › "Pulsar la tecla globo
  para" tiene que estar en "No hacer nada"; la fila de Ajustes lo dice.
- **La voz caliente cuelga sola.** Una sesión que abrió un hold y reposa
  con el micro cerrado (`holdArmed && muted`, chrome en idle/hover/
  completed) arma `scheduleVoiceIdleExpiry` (20 s) y al vencer `hangUpVoice`.
  Es la única forma de soltar el micro físico: con AEC el reproductor
  comparte el motor del micro, así que no se para el micro a medias. La
  manos libres silenciada desde la ventana no entra: su botón lo muestra.
- **La hoja tiene un anfitrión.** `HoldSettingsModel.mainInFront` (key
  window) decide: main pinta la hoja, la island no la duplica. En la
  island, `ApprovalClickGuard` ignora respuestas en los primeros 0,6 s.
- **`notice` vs `cards`.** Las cards duran un paso; `notice` es lo que el
  reposo sigue mostrando (hint, "no te oí", permiso) hasta que algo nuevo
  empieza. Lo que deba verse tras la snapshot de la voz va en `notice`.
- **Cicatriz**: la retícula. Anchos de la island como tokens en
  `IslandChrome`, `Space.x0` para un spacing cero; nada de `Space.x8 * 2`.

## El patron de bug que se repite en este repo

Cuatro veces en Wave 3 aparecio lo mismo: **la logica correcta y testeada,
sin cablear al camino real.** El watchdog de VP existia y nadie lo llamaba;
`disableVoiceProcessing()` idem; el barge-in del reducer estaba probado pero
la vista llamaba `hangUp()`; `VoiceCopy.failure(...)` estaba escrito y nadie
lo mostraba; `.networkUnavailable` se agrego al enum sin que ningun camino lo
emitiera. Los tests verdes NO prueban que el cableado exista. Al revisar una
wave, buscar cada capacidad nueva con grep y confirmar que alguien la invoca
desde el flujo real.
