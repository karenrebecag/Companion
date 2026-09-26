# Wave 12a — El reductor de sesión: cuatro kinds, una proyección

**Estado: ENTREGADA (2026-09-06).** Aprobada por Karen el 2026-09-06 ("vamos.
aplica y loopea"); gates verdes con 231 tests; desviaciones en §9; revisiones en §10. Dirección
aprobada el 2026-09-06 ("vamos, me parece perfecto"): Wave 12 "El HUD" en el orden de la spec de
producto `~/Desktop/relay-hud-spec/` (fuera del repo, a propósito):
12a reductor y proyección → 12b hold global con FN e island → 12c
precalentamiento → 12d contratos y validadores (independiente). Esta es la
primera pieza. Cubre las metas **G2** (el overlay escucha; el core posee el
estado) y **G4** (cancelar es Idle) de `relay-hud-spec/00`, y cierra el hueco
**D4** del mapa (`AI_Research/AIResearch/COMPANION-MAP.md` §4).

Sin commit: Karen commitea.

---

## 1. El defecto, en dos líneas

**A.** No hay un estado de sesión. Hay tres: el de la voz (`TurnMachine`,
seis estados con `error` como uno de ellos), el del encargo (`JobTimeline` +
`approvalQueue` dentro de `ChatViewModel`) y el de las manos del padre (líneas
de estado sueltas). La UI los combina a mano en cada vista.

**B.** Lo que sale de la sesión de voz sale por seis closures, y lo que el
encargo produce llega a la UI por otro camino. Una island (12b) que quiera
pintar "ejecutando tool" o "hijo trabajando" no tiene de dónde leerlo.

### A, medido

| Dónde | Qué guarda | Quién lo lee |
|---|---|---|
| `TurnMachine.snapshot` (`TurnTypes.swift:5`) | `idle, connecting, listening, thinking, speaking, error` + 11 flags | `VoiceViewModel.snapshot` → `StatusLine`, `ControlBar`, `Orb`, `CompanionRootView` (Esc) |
| `ChatViewModel.job` (`ChatViewModel.swift:75`) | `JobTimeline` (goal, steps, startedAt) | `ThreadView` → `JobCardView` |
| `ChatViewModel.approvalQueue` (`:123`), `jobHasApprovedAction` (`:83`) | `[ApprovalRequest]` | `StatusLine`, `CompanionRootView` → `ApprovalSheet`, Esc |
| `VoiceSession.pendingApproval` / `pendingMCPApproval` | la misma petición, otra vez | `answerPendingApproval` (el "sí" hablado) |
| `voice.statusText` | copy derivada del estado de voz | `StatusLine` |

`error` es un estado de la máquina (`TurnMachine.fail`): un permiso de
micrófono denegado deja la voz **en un modo**, y la copia con el enlace a
Ajustes vive en `VoiceCopy.settingsLink(for: failure)`. La spec de producto lo
dice al revés: cancelar y fallar vuelven a Idle; lo que se muestra es una
card (`relay-hud-spec/03` §2.9, `00` G4).

### B, medido

`VoiceSession.init` (`VoiceSession.swift:70-197`) cablea: `onJobEvent`
(parámetro), `realtime.onStopJob`, `realtime.onDelegate` (→ `VoiceJobBridge`
con `onEvent` + `announce`), `realtime.onResolveApproval`,
`realtime.onMCPApproval`, `onCard` en los dos runtimes, y
`ParentToolGuard(onRequest:onRemembered:)`. El mapa lo llama "la misma forma
que los 10+ callbacks a mano del prototipo". Son dos familias distintas:

| Familia | Closures | Dirección |
|---|---|---|
| **Hacia fuera** (proyección) | `onJobEvent`, `onCard` ×2, `parentGuard.onRequest`, `parentGuard.onRemembered`, `VoiceJobBridge.onEvent` | la sesión cuenta lo que pasa |
| **Hacia dentro** (órdenes del modelo) | `onDelegate`, `onStopJob`, `onResolveApproval`, `onMCPApproval` | el modelo pide algo por function call |

Las de fuera son la proyección y **se van en esta wave**: un solo stream.
Las de dentro son la superficie de function calls del realtime; se quedan
hasta 12b, cuando el hold entre por el reductor y la sesión de voz pase a ser
un puerto que obedece efectos (§7).

---

## 2. Lo que dice la spec de producto y el corpus

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| `relay-hud-spec/00` G2 | El reductor es el único dueño de `State.kind` / `Processing.phase`; el overlay escucha y pinta; "paint lags reduce, never leads"; sin transición local | Un reductor puro en Core; la UI lee una proyección `private(set)`; regla de conformidad que prohíbe escribir el kind desde UI |
| `relay-hud-spec/00` G4, `03` §2.9 | Cancelar = `InterruptReason` + Idle, nunca un quinto kind; Stop mata a los hijos; el fallo es una card | `InterruptReason`; `error` deja de ser kind de sesión; el fallo de voz se proyecta como card con enlace |
| `relay-hud-spec/03` §1 | "Dos máquinas, una island": el reductor de sesión manda en el chrome; la máquina de captura de voz obedece y solo aporta medidor y parciales | `TurnMachine` **se queda** como máquina de voz; el reductor de sesión la observa y la traduce |
| `relay-hud-spec/03` §2, `05` §4 | Cuatro kinds: Idle, Hover, Listening, Processing. Fases: Pending, Thinking, Speaking, ToolExecuting, SubAgentRunning, Completed. Completed → timer → Idle | Los enums, con nuestros nombres |
| `relay-hud-spec/02` §5 | Los permisos **se quedan** en Processing; negar → recordar la interrupción, no re-proponer | La petición pendiente es un campo de la proyección, no un estado |
| `relay-hud-spec/03` §3 | Kinds de overlay = lo que la island pinta, no React ni estado | `SessionCard` con nombres de intención nuestros |
| Corpus spec 16 | Un reductor, eventos y comandos del **mismo** reductor para approvals, sub-agentes y cards | `SessionEvent` / `SessionEffect` |
| `COMPANION-MAP` §4 D4 | Doce símbolos públicos sin llamadores; la lógica correcta se pierde entre capas | Se borran los que esta wave deja huérfanos; el resto se lista en §7 |
| companion `ARCHITECTURE.md` "State: reducer not scattered mutation" | La regla ya existe para la voz | Se extiende a la sesión |

---

## 3. Decisión

### 3.0 Qué viene de dónde

| Decisión | Fuente |
|---|---|
| Reductor puro en Core, proyección observada por UI | G2; ARCHITECTURE |
| `TurnMachine` intacta; el reductor de sesión la traduce | `relay-hud-spec/03` §1 (dos máquinas) |
| Fallo de voz → Idle + card con enlace | G4; `03` §2.9 |
| Cuatro kinds + seis fases, nombres nuestros | `05` §4 |
| Un stream de eventos hacia fuera; las órdenes del modelo siguen como puertos | Nuestra (§1 B); el corte honesto de D4 |
| Regla de conformidad "la UI no escribe el kind" | G2 "no-local-transition", como test de auditor |

### 3.1 Tipos (Core, `SessionTypes.swift`)

```swift
public enum SessionKind: Sendable, Equatable {
    case idle, hover, listening
    case processing(SessionPhase)
}
public enum SessionPhase: Sendable, Equatable {
    case pending, thinking, speaking, toolExecuting, subAgentRunning, completed
}
/// Why the session left Processing without finishing (G4). Never a kind.
public enum InterruptReason: Sendable, Equatable {
    case userStopped, userSteered, failure(TurnFailure)
}
/// What the chrome can paint besides the kind: intent names, ours.
public enum SessionCard: Sendable, Equatable {
    case couldntHear
    case permission(TurnFailure)        // mic / speech denied: link to Settings
    case failure(TurnFailure)           // the rest of TurnFailure, one line
    case approval(ApprovalRequest)      // the sheet's source of truth
    case approvalAnswered(tool: String, approved: Bool, remembered: Bool)
    case answer(Card)                   // the existing Card channel (map, gallery, sources)
}
/// The voice port's own status, distinct from the session kind: a session
/// can be Idle while the socket is still opening.
public enum VoiceStatus: Sendable, Equatable { case off, connecting, live, muted }

public struct SessionProjection: Sendable, Equatable {
    public var kind: SessionKind = .idle
    public var voice: VoiceStatus = .off
    public var pipeline: VoicePipeline? = nil
    public var partialTranscript: String? = nil
    public var job: JobTimeline? = nil          // moved from CompanionUI to Core
    public var approval: ApprovalRequest? { … } // first of the queue
    public var approvalQueue: [ApprovalRequest] = []
    public var cards: [SessionCard] = []        // transient, replaced per projection
    public var interruption: InterruptReason? = nil
    public var echoFreeOutput: Bool = false
}

public enum SessionEvent: Sendable, Equatable {
    case voice(TurnSnapshot)                    // the voice machine moved
    case partialTranscript(String?)
    case typedSubmitted
    case typedReplyStreaming
    case typedReplyFinished
    case parentActing(targets: [String])        // the parent's hands, one round
    case parentActed
    case job(JobEvent)                          // started / step / approval / card / denied / remembered
    case jobFinished(ok: Bool)
    case approvalAnswered(requestId: String, approved: Bool, remember: Bool)
    case hoverEntered, hoverLeft                // the island (12b) emits them; the reducer already knows them
    case completedTimerExpired
    case stop                                   // the user: Esc, button, "stop"
}

public enum SessionEffect: Sendable, Equatable {
    case cancelJob
    case resolveApproval(requestId: String, approved: Bool, remember: Bool)
    case scheduleCompletedExpiry(TimeInterval)
    case logTransition(from: SessionKind, to: SessionKind)
}
```

`JobTimeline` y `JobStepInfo` se mueven de `ChatViewModelJobs.swift` a Core
(`JobTimeline.swift`): la proyección los lleva y Core no puede importar UI.

### 3.2 El reductor (Core, `SessionMachine.swift`)

`handle(_ event: SessionEvent, at now: TimeInterval) -> [SessionEffect]`,
puro, `Equatable`. Reglas:

| Evento | Desde | A | Efectos |
|---|---|---|---|
| `.voice(s)` con `s.state == .connecting` | cualquiera | kind sin cambio; `voice = .connecting` | — |
| `.voice(.listening)` | idle / hover / processing | `.listening`; `voice = .live` o `.muted` | — |
| `.voice(.thinking)` | listening | `.processing(.thinking)` o `.processing(.subAgentRunning)` si `job != nil` | — |
| `.voice(.speaking)` | processing | `.processing(.speaking)` | — |
| `.voice(.idle)` | cualquiera | `.idle` si no hay job; `.processing(.subAgentRunning)` si lo hay | — |
| `.voice(.error(f))` | cualquiera | `.idle` + `interruption = .failure(f)` + card `.permission(f)` (micDenied / speechDenied) o `.couldntHear` (notHeard / micSilent) o `.failure(f)` | — |
| `.typedSubmitted` | idle | `.processing(.thinking)` | — |
| `.typedReplyStreaming` | processing(.thinking) | `.processing(.speaking)` (en chat, "speaking" = tokens en pantalla) | — |
| `.typedReplyFinished` | processing | `.processing(.completed)` si voz off; kind de voz si voz live | `.scheduleCompletedExpiry(1.5)` cuando queda en completed |
| `.parentActing` | idle / processing | `.processing(.toolExecuting)` | — |
| `.parentActed` | toolExecuting | vuelve a lo que dicte la voz, o `.processing(.completed)` | idem |
| `.job(.started)` | cualquiera | `.processing(.subAgentRunning)`; `job = JobTimeline(goal)` | — |
| `.job(.stepStarted / .thought)` | processing | fase sin cambio; `job.steps += 1` | — |
| `.job(.approvalRequested(r))` | processing | fase sin cambio; `approvalQueue += r`; card `.approval(r)` | — |
| `.job(.card(c))` | cualquiera | kind sin cambio; card `.answer(c)` | — |
| `.job(.approvalDenied / .approvalRemembered)` | processing | card `.approvalAnswered(…)` | — |
| `.jobFinished` | processing | `job = nil`; `.processing(.completed)` si voz off, si no el kind de la voz | `.scheduleCompletedExpiry` cuando queda en completed |
| `.approvalAnswered(id, ok, remember)` | processing | quita `id` de la cola | `.resolveApproval(id, ok, remember)`; si `!ok` y era la primera acción del job → además `.cancelJob` (la regla de 10c) |
| `.completedTimerExpired` | processing(.completed) | `.idle`; `cards = []` | — |
| `.hoverEntered` / `.hoverLeft` | idle ↔ hover | | — |
| `.stop` | cualquier no-idle | `.idle`; `interruption = .userStopped`; `job = nil`; cola vacía | `.cancelJob` si había job; `.resolveApproval(…, approved: false)` por cada pendiente |

Todo cambio de kind emite `.logTransition` (hoy `VoiceSession.apply` loguea
"voice: a -> b"; la sesión loguea "session: a -> b" y la voz sigue con el
suyo). `cards` es transitorio: cada proyección lleva las cards de **este**
paso; la UI que quiera conservar una (la sheet, el card de mapa en el hilo)
la copia a su propio modelo, como hoy hace `ChatViewModel` con `Card`.

### 3.3 Dónde corre (UI, `SessionModel.swift`)

`@Observable @MainActor public final class SessionModel` con
`public private(set) var projection: SessionProjection`, `func send(_:)` y
los puertos que los efectos necesitan: `jobs: (any JobSubmitter)?`,
`approvals: (any ApprovalsProvider)?`, un reloj inyectable para el timer de
Completed. Es el **único** objeto que muta la proyección. Sustituye a:

- `VoiceViewModel.snapshot` como fuente para `StatusLine`, `ControlBar`,
  `Orb` y el Esc de `CompanionRootView` (siguen leyendo `levels` y
  `interruptCapability` del `VoiceViewModel`, que se queda como el mando de la
  voz: start, advance, hangUp, mute, push).
- `ChatViewModel.job`, `approvalQueue`, `pendingApproval`,
  `jobHasApprovedAction`: se borran; `ChatViewModel` recibe el `SessionModel`
  y le manda eventos (`receiveJobEvent` → `send(.job(e))`; `answerApproval` →
  `send(.approvalAnswered)`; `runJob` → `.jobFinished`; el turno tecleado →
  `.typedSubmitted / .typedReplyStreaming / .typedReplyFinished`; las manos
  del padre → `.parentActing / .parentActed`).
- `VoiceSession.pendingApproval` / `pendingMCPApproval` como copia: la voz
  sigue necesitando saber qué contestar al "sí" hablado; lee de la misma cola
  que llega por el stream (§3.4), no de una copia propia.

### 3.4 El stream (Services, `VoiceSession`)

`public nonisolated let events: AsyncStream<SessionEvent>`, al lado de
`snapshots` y `levels`. Por él salen: `.job(e)` (lo que hoy va por
`onJobEvent` y `VoiceJobBridge.onEvent`), `.job(.card(c))` (hoy `onCard`),
`.job(.approvalRequested(r))` (hoy `parentGuard.onRequest`),
`.job(.approvalRemembered)` (hoy `parentGuard.onRemembered`),
`.parentActing / .parentActed` (nuevo: hoy la línea de estado se escribe en
el hilo y nadie más se entera), `.partialTranscript`, `.jobFinished`. El
parámetro `onJobEvent` de `VoiceSession.init` **desaparece**;
`CompanionMain` conecta `session.events` → `SessionModel.send`.

`VoiceViewModel` reenvía cada `TurnSnapshot` como `.voice(s)` al
`SessionModel` (además de guardarlo para el mando). Es un reenvío, no una
segunda fuente: el `SessionModel` no lee `voice.snapshot` nunca.

### 3.5 Lo que la UI deja de decidir

- `StatusLine`: la línea de "esperando permiso", el enlace a Ajustes por
  permiso y el estado de voz salen de `projection.cards` y `projection.kind`.
  `VoiceCopy.settingsLink(for:)` recibe la card, no el failure.
- `CompanionRootView`: la sheet se abre con `projection.approval`; el Esc
  manda `.stop` (hoy decide entre sheet, dropdown, ajustes y colgar: la
  escalera de Esc se queda, pero el último peldaño es `session.send(.stop)`,
  que a su vez cuelga la voz por efecto… **no**: colgar la voz sigue siendo
  `voice.hangUp()` desde el mando, y `.stop` llega al reductor por el
  `.voice(.idle)` que produce. `.stop` explícito es para el botón Stop del
  job y para 12b).
- `ThreadView`: `JobCardView(job: projection.job)`.
- `ControlBar` / `Orb`: `projection.kind` y `projection.voice` deciden
  orb / mute / colgar; los niveles siguen del `VoiceViewModel`.

### 3.6 La regla de conformidad (G2 como test de auditor)

`conformance/ui-contract.json` gana una regla:

```json
"session-kind-write": {
  "pattern": "projection\\.(kind|job|approvalQueue|cards)\\s*(=|\\.append|\\.remove)",
  "why": "La UI pinta la proyección; solo SessionMachine la muta. Una vista que escribe el kind es la transición local que G2 prohíbe."
}
```

Y `SessionProjection` es `private(set)` en `SessionModel`: el compilador
cubre lo que el regex no.

### 3.7 Archivos que toca

| Capa | Archivo | Qué |
|---|---|---|
| Core | `SessionTypes.swift` (nuevo) | §3.1 |
| Core | `SessionMachine.swift` (nuevo) | §3.2 |
| Core | `JobTimeline.swift` (nuevo, movido desde UI) | `JobTimeline`, `JobStepInfo` sigue en `JobSteps.swift` |
| Core | `TurnTypes.swift` | sin cambios de forma; comentario: `TurnState.error` es de la voz, la sesión lo proyecta como card |
| Services | `VoiceSession.swift` | `events` stream; fuera `onJobEvent`; `pendingApproval` se alimenta de la cola proyectada; `VoiceJobBridge` emite al stream |
| Services | `VoiceJobBridge.swift` | `onEvent` → sink de `SessionEvent`; emite `.jobFinished` |
| Services | `ClassicRuntime.swift`, `RealtimeRuntime.swift` | `onCard` y la línea de estado de las manos → eventos por el mismo sink (`.parentActing / .parentActed`) |
| UI | `SessionModel.swift` (nuevo) | §3.3 |
| UI | `ChatViewModel.swift`, `ChatViewModelJobs.swift` | fuera `job`, `approvalQueue`, `jobHasApprovedAction`; eventos al `SessionModel` |
| UI | `VoiceViewModel.swift` | reenvía `.voice(s)`; `isActive` se queda (mando) |
| UI | `StatusLine.swift`, `CompanionRootView.swift`, `ThreadView.swift`, `ControlBar.swift`, `VoiceCopy.swift` | leen la proyección |
| App | `CompanionMain.swift` | `SessionModel(jobs:approvals:)`; `session.events` → `send`; `VoiceSession` sin `onJobEvent` |
| Conformance | `conformance/ui-contract.json` | regla `session-kind-write` |
| Tests | `SessionMachineTests.swift`, `SessionModelTests.swift` (nuevos); `ChatViewModelTests`, `VoiceSessionTests` (harness `events`), `JobCancelTests`, `VoiceApprovalTests`, `JobNarrationTests`, `DelegateRoundTripTests`, `ConformanceTests` | §5 |

Unos veinte archivos. Es un refactor mediano-grande, sin cambio visible para
la usuaria salvo uno: un fallo de voz se ve como card con enlace y la voz
vuelve a reposo, en vez de quedarse en un modo "error".

---

## 4. Restricciones

- `SessionMachine` no importa nada de Services ni de UI; sin I/O; `Equatable`.
- `TurnMachine` no cambia de forma. Sus 419 líneas de tests siguen verdes sin
  tocarlas.
- La proyección se muta en **un** sitio. Regla de conformidad + `private(set)`.
- Ningún closure nuevo. Lo que sale de la sesión sale por `events`.
- Sin `try?` en Core/Services. Sin emojis. Comentarios solo el porqué.
- Los símbolos huérfanos del mapa que esta wave deja sin uso se borran en la
  misma wave (`approvalToolJSON`, `needsHeardNotice` si
  siguen sin llamadores tras el cambio); el resto se lista en §7 con su dueño.

---

## 5. TDD (tests antes que código)

| # | Test | Espera |
|---|---|---|
| 1 | `SessionMachine` arranca en `.idle`, `voice = .off`, sin job, sin cola | proyección `.init()` |
| 2 | `.voice(connecting)` | kind no cambia; `voice = .connecting` |
| 3 | `.voice(listening)` desde idle | `.listening`, `voice = .live`; con `muted` → `.muted` |
| 4 | `.voice(thinking)` / `.voice(speaking)` | `.processing(.thinking)` / `.processing(.speaking)` |
| 5 | `.voice(thinking)` con job vivo | `.processing(.subAgentRunning)`, no `.thinking` |
| 6 | `.voice(error(micDenied))` | `.idle`, `interruption = .failure(micDenied)`, `cards == [.permission(micDenied)]` |
| 7 | `.voice(error(notHeard))` | `.idle`, `cards == [.couldntHear]` |
| 8 | `.voice(idle)` con job vivo | sigue `.processing(.subAgentRunning)` |
| 9 | Turno tecleado: submitted → streaming → finished con voz off | thinking → speaking → completed + `.scheduleCompletedExpiry`; `completedTimerExpired` → idle |
| 10 | Turno tecleado con voz live | finished vuelve al kind de la voz, sin timer |
| 11 | `.parentActing(["Safari"])` / `.parentActed` | `.processing(.toolExecuting)` y vuelta |
| 12 | `.job(.started(goal))` desde idle | `.processing(.subAgentRunning)`, `job.goal == goal` |
| 13 | `.job(.stepStarted)` ×3 | `job.steps.count == 3`, fase sin cambio |
| 14 | `.job(.approvalRequested(r))` | sigue processing; `approval == r`; card `.approval(r)` |
| 15 | Dos peticiones, se contesta la primera | la segunda pasa a `approval`; efecto `.resolveApproval` con el id correcto y `remember` |
| 16 | Negar la **primera** acción del job | efectos `.resolveApproval(false)` + `.cancelJob`; negar una posterior → solo resolve (regla 10c) |
| 17 | `.job(.card(c))` en idle | kind sigue idle; card `.answer(c)` |
| 18 | `.jobFinished` con voz off | completed + timer; con voz live → kind de voz |
| 19 | `.stop` en processing con job y dos peticiones | idle, `interruption = .userStopped`, `job == nil`, cola vacía, efectos `.cancelJob` + dos `.resolveApproval(false)` |
| 20 | `.stop` en idle | no-op, sin efectos |
| 21 | `hoverEntered` / `hoverLeft` | idle ↔ hover; en listening `hoverEntered` es no-op |
| 22 | `cards` es transitorio | tras cualquier evento siguiente la card anterior no está |
| 23 | Toda transición de kind emite `.logTransition(from:to:)` | y un evento sin cambio no lo emite |
| 24 | `SessionModel.send(.approvalAnswered)` | llama a `approvals.resolve` (fake) con id, approved y remember; sin actor, al `jobSubmitter` |
| 25 | `SessionModel` con reloj falso: completed → avanza 1.5 s → idle | el timer es cancelable: un evento antes lo anula |
| 26 | `ChatViewModel.runJob` publica `.job(.started)` … `.jobFinished` en el `SessionModel` y **no** guarda job propio | `chat.job` ya no existe; `session.projection.job` sí |
| 27 | `VoiceSession.events` lleva `.job(.approvalRequested)` cuando el especialista pide, y `.parentActing` cuando el padre abre Safari | harness de `VoiceSessionTests` con el stream en vez de `onJobEvent` |
| 28 | El "sí" hablado resuelve la petición que la proyección tiene primera | `VoiceApprovalTests` |
| 29 | Conformidad: `session-kind-write` falla ante `session.projection.kind = .idle` en un archivo de UI de prueba | mutación en ambos sentidos, como las otras reglas |
| 30 | Catálogo: nuevas claves de copy en en/es con paridad | `catalogParityTests` |

---

## 6. Prueba manual (solo Karen)

1. Voz con clave: hablar, delegar "crea un archivo", ver el card del encargo,
   la hoja de permiso, aceptar; el resultado llega y la voz lo anuncia. Igual
   que hoy.
2. Negar el micrófono en Ajustes del Sistema y pulsar el orb: la voz vuelve a
   reposo (el orb, no un modo "error") y aparece la card "Micrófono sin
   permiso" con "Abrir Ajustes del Sistema".
3. Chat tecleado: "abre Safari" pinta "Abriendo Safari…" mientras dura y la
   línea se cierra; delegar y pulsar Stop cierra el card y deja el registro.
4. Esc con la hoja abierta la niega; Esc sin nada cuelga la voz. Sin cambios.
5. En el log: líneas `session: idle -> listening`, `session: listening ->
   processing(thinking)`, junto a las `voice:` de siempre.

---

## 7. Fuera de alcance

- Los cuatro closures **hacia dentro** (`onDelegate`, `onStopJob`,
  `onResolveApproval`, `onMCPApproval`): son la superficie de function calls
  del realtime. Pasan a efectos en **12b**, cuando `pressed/released` entren
  por el reductor y `VoiceSession` obedezca `SessionEffect`.
- `.pressed / .released / .tapped`, `.showOverlay / .hideOverlay`, el
  `NSPanel`: **12b**.
- Confirmación de spawn (G6), glow (G5): después de la acción por
  Accesibilidad.
- Huérfanos del mapa que no son de esta wave: `disableVoiceProcessing`
  (puerto de mic, 9c), `executorPrompt` / `stepLabel` / `spokenSoFar` /
  `commitAudio` (voz clásica), `storedLabel` / `thumbnailData` / `passesAA`
  (UI). Se revisan en 12d con el resto de contratos.

---

## 8. Fuentes

- `~/Desktop/relay-hud-spec/00-goals-and-auditors.md` (G2, G4, §4 checklist),
  `02-interaction.md` (§1 el salto, §5 approvals, §9 gestos),
  `03-screens-and-states.md` (§1 dos máquinas, §2 chrome por fase),
  `05-replication-checklist.md` (§4 nuestro reductor, §12 orden).
- `AI_Research/AIResearch/specs/16-state-machine.md`, `COMPANION-MAP.md` §4
  D4 y §5 fila 6.
- companion: `TurnTypes.swift`, `TurnMachine.swift`, `VoiceSession.swift`,
  `VoiceJobBridge.swift`, `ChatViewModelJobs.swift`, `VoiceViewModel.swift`,
  `StatusLine.swift`, `CompanionRootView.swift`, `docs/ARCHITECTURE.md`.

---

## 9. Desviaciones respecto a esta spec (al entregar)

| # | La spec decía | Lo que hay | Por qué |
|---|---|---|---|
| 1 | `VoiceSession.pendingApproval` lee "de la misma cola que llega por el stream" | Sigue siendo el buzón propio de la voz para el "sí" hablado; al resolver emite `.approvalSettled(id)` y la cola proyectada se cierra | Services no ve la UI. El buzón se alimenta de los mismos eventos que emite; lo que faltaba era cerrar la hoja, y eso lo hace el evento nuevo (antes la hoja quedaba abierta tras un "sí" hablado) |
| 2 | `ControlBar` / `Orb` deciden por `projection.kind` y `projection.voice` | Siguen sobre `VoiceViewModel.snapshot` | Son el mando y el medidor de la voz (`relay-hud-spec/03` §1: la máquina de captura aporta medidor y parciales). `StatusLine`, `CompanionRootView` y `ThreadView` sí leen la proyección |
| 3 | `VoiceCopy.settingsLink(for:)` recibe la card | `settingsLink(after: projection.interruption)`; la de `TurnFailure?` se queda | Las cards son de un paso; el enlace a Ajustes tiene que sobrevivir hasta que la voz vuelva a escuchar. `interruption` dura hasta salir de Idle |
| 4 | `SessionEvent.partialTranscript` | No está | Nadie lo emite hasta 12b (island). Un evento sin emisor es código muerto |
| 5 | `.voice(.error(f))` → `.idle` | `.idle` si no hay encargo; `.processing(.subAgentRunning)` si lo hay | Un fallo de voz no mata al hijo; la fila del hijo manda |
| 6 | — | Eventos `.approvalSettled(id)` y `.approvalDropped(id)` | La cola tiene que cerrarse cuando el actor contesta por otra vía (voz, memoria) o cuando el turno muere al cambiar de conversación, sin que el reductor lo lea como "negaste el primer paso" y pare el encargo |
| 7 | `.approvalAnswered` negando el primer paso → `.resolveApproval` + `.cancelJob` | Además aplica la semántica de `.stop`: niega las demás peticiones en cola | Antes quedaban para el auto-deny de 120 s. Un encargo parado no tiene peticiones que esperar |
| 8 | Los `onCard` de los runtimes siguen | Borrados; los runtimes emiten por `events: AudioStreamBox<SessionEvent>` (cards y manos) | Un closure menos. `ParentToolGuard.onRequest/onRemembered` se quedan (existían; no son nuevos) |
| 9 | `JobStepInfo` sigue en `JobSteps.swift`; la etiqueta la hacía `ChatCopy.step` | `JobTimeline.step(tool, summary)` en Core construye "Tool: resumen" | La proyección se arma en Core y `JobSteps.summary` lee la ruta tras los dos puntos; `ChatCopy.step` queda para el hilo |
| 10 | Borrar `approvalToolJSON` y `needsHeardNotice` si siguen sin llamadores | No se tocan | Tienen tests que los llaman y no son de esta wave; van con la limpieza de contratos en 12d |
| 11 | Test 30: claves de copy nuevas | No hay claves nuevas | Las cards reutilizan `VoiceCopy.failure` y `status.approvalWaiting` |
| 12 | El log de transiciones | `SessionModel(log:)` es un puerto inyectado; `CompanionMain` pasa `Log.app` | UI no importa Services |
| 13 | `.stop` desde `cancelJob` | `ChatViewModel.cancelJob` manda `.stop` y escribe el registro solo si el reductor devolvió `.cancelJob` | El hilo sigue siendo del view model; la decisión, del reductor |
| 14 | 12 tests de `VoiceSessionTests` adaptados al stream | El harness conserva el parámetro `onJobEvent` y lo alimenta bombeando `session.events` | Doce llamadas sin tocar; la forma del harness no era el objetivo |
| 15 | El "sí" hablado resuelve en `VoiceSession` contra su buzón | `VoiceSession` emite `.approvalSpoken(approved:)`; el reductor resuelve **la primera de la cola** (lo que la hoja muestra) con las mismas reglas que la hoja (negar el primer paso para el encargo) | Security review 2026-09-06: dos nociones de "pendiente" dejaban que un "sí" concediera una petición que nadie miraba. `approvalSettled` se queda para la puerta del chat (auto-deny del actor) |
| 16 | — | `SessionProjection.targets` (lo que el padre abre) | Lo necesita la island de 12b y ya viajaba en `parentActing` |

---

## 10. Revisiones (2026-09-06)

### Security review

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Crítico | Aprobar una petición del padre (`open_url`) mientras corre un encargo ponía `jobApprovedOnce` y desarmaba "negar el primer paso para el encargo"; negarla paraba el encargo | `SessionMachine.isJobRequest`: solo las peticiones que no son de `ParentTool` cuentan para el encargo. Test `testAParentsApprovalDoesNotCountForTheJob` (falló primero) |
| 2 | Crítico | El "sí" hablado resolvía el último `pendingApproval` de `VoiceSession` (un slot que se sobreescribe) mientras la hoja mostraba el primero de la cola | `.approvalSpoken`: la voz no resuelve; el reductor contesta la primera de la cola. Test `testTheSpokenAnswerGoesToTheSheetsFirst`; `VoiceApprovalTests` 3 y 4 pasan por `SessionModel` |
| 3 | Alto | Negar por voz el primer paso no paraba el encargo (preexistente) | Mismo cierre que 2: el camino es uno |
| 4 | Medio | `jobApprovedOnce` no contaba las aprobaciones por voz → sobre-cancelación | Mismo cierre que 2 |
| 5 | Medio (plausible) | Una petición tardía tras Stop reabría la cola | Con `interruption == .userStopped` y sin encargo, la petición se niega sin entrar. Test `testALateRequestAfterStopIsDenied` |

### Code review

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alto | `stop()` no limpiaba `typedBusy`: la voz al volver a reposo se quedaba pintando la última fase | `stop()` limpia `typedBusy`. Test `testStopClosesTheTypedTurn` |
| 2 | Alto | Cambiar de conversación, abrir otra o cambiar la clave con un turno tecleado en vuelo no avisaba a la sesión (los guards de `isCurrent` saltan `endTurn`) | `ChatViewModel.abandonTurn()` en los tres caminos. Test `testSwitchingConversationClosesTheTypedTurn` |
| 3 | Alto | La cola mezcla peticiones del encargo y del padre para la regla del primer paso | = security 1 |
| 4 | Medio | `changeKey()` no soltaba las peticiones del padre | Ahora llama a `dropParentApprovals()` |
| 5 | Medio | Un `.started` repetido reiniciaba `jobApprovedOnce` | Solo se reinicia al crear el encargo. Test `testRenamingARunningJobKeepsItsApprovals` |
| 6 | Bajo | El stream de eventos es un `AsyncStream` sin tope | `HACK` anotado en `VoiceSession.init` con el disparador (segundo consumidor o consumidor lento) |
| 7 | Bajo | Los efectos `cancelJob` / `resolveApproval` corren en `Task` sin manejo | Los puertos no lanzan; no hay error que manejar. Sin cambio |
