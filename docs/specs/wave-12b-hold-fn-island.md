# Wave 12b — Mantener FN y hablar: la tecla global y la island

**Estado: ENTREGADA (2026-09-06).** Gates verdes con 233 tests; la island
vista en vivo bajo la banda del notch; desviaciones en §9, revisiones en
§10. Cubierta por la aprobación de Karen del
2026-09-06 ("vamos. aplica y loopea para continuar con toda la spec de
cambios que sean visibles") sobre el orden de la Wave 12 aprobado antes
("vamos, me parece perfecto": FN en hold, el atajo actual como manos libres).
Segunda pieza del HUD (`~/Desktop/relay-hud-spec/`, fuera del repo). Cubre
las metas **G1** (el hold funciona sin abrir la ventana), **G3** (ver
Listening / thinking / speaking / fila del hijo) y **G4** (Stop es Idle) de
`relay-hud-spec/00`, y el hueco **D3** del mapa (`COMPANION-MAP.md` §4).
Depende de 12a (el reductor de sesión).

Sin commit: Karen commitea.

---

## 1. El defecto, medido

**A. Activar el micrófono es un toggle dentro de la ventana.** El orb
(`ControlBar.swift:87`, `VoiceTapAction.forState`), el atajo
`Cmd+Opt+Space` (`KeyboardMonitor.swift`: `addLocalMonitorForEvents(matching:
.keyDown)`, sin `keyUp`, y **local**: solo con Companion delante) y el menú
(`MenuRouting.toggleVoice`) hacen lo mismo: `start()` o `hangUp()`. Hablar
con el Mac exige traer Companion al frente. La spec de producto lo dice al
revés: "Start a turn with hold or type without opening main"
(`relay-hud-spec/02` §10.1).

**B. No hay hold.** `TurnEvent` (`TurnTypes.swift:64`) no tiene
press/release; el turno lo cierra el servidor (VAD) o el endpointer nativo
(`TranscriptEndpointer`). No existe "suelto la tecla y ya" (ForceEndpoint,
spec 01 del corpus).

**C. No hay superficie fuera de la ventana.** Cero `NSPanel`, cero
`CGEvent`, cero `addGlobalMonitor` en `Sources/` (grep 2026-09-06). Cerrar
la ventana mata la app (`CompanionMain.swift`:
`applicationShouldTerminateAfterLastWindowClosed → true`).

**D. Un micro que oye todo el rato.** En realtime, el micro está abierto
desde `start()` hasta `hangUp()`. El silencio entre frases lo interpreta el
VAD del servidor. El producto es un hold: el micro oye **mientras** la tecla
está pulsada.

---

## 2. Lo que dice la spec de producto y la industria

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| `relay-hud-spec/02` §2.3–2.4 | Keydown → `Listening` + `StartMicCapture` + `ShowOverlay`; conectar el socket **al pulsar**; keyup → `Processing{Pending}` + `StopMicCapture` + ForceEndpoint; vacío → `CouldntHear` → Idle | `.pressed` / `.released` en el reductor de sesión; efectos `startListening` / `stopListening`; la voz obedece |
| `relay-hud-spec/02` §2.3 | Tap = press+release fusionados | `.tapped` lo decide la capa de tecla por duración; el reductor lo pinta como hint del hold, no como turno vacío (un FN accidental no puede sembrar cards "no te oí") |
| `relay-hud-spec/02` §2.7 | Barge-in: hold durante Speaking → Listening + StopTts | `.pressed` en speaking → `startListening` (la voz cancela su salida y abre el micro) |
| `relay-hud-spec/02` §9, §10 | Stop desde cualquier no-Idle → Idle; el hijo muere | `.stop` gana `cancelVoiceOutput` cuando la voz piensa o habla |
| `relay-hud-spec/01` §2.1–2.4, §4 | La island es la **misma** ventana que el pebble; anclada arriba, banda del notch; crece hacia abajo, nunca hacia los extras del menú; nunca se convierte en main | Un `NSPanel` non-activating, siempre encima, en todos los Spaces; pebble en Idle, crece por kind |
| `relay-hud-spec/03` §2 | Qué se ve por kind: pebble, nudge en hover, medidor en Listening, fase en Processing, fila del hijo, card de permiso **en la island** | `IslandView` pinta la proyección; la hoja de permiso se hospeda en la island |
| `relay-hud-spec/05` §5, §7, §9 | `idle_pebble_hidden`; copy propia: "Hold to talk", "Nothing to send", "Stop" | Preferencia `IslandPreference.pebbleHidden`; copy nuestra en `en/es.lproj` |
| Corpus spec 28 §10.1 (Observed) | FN es la tecla de activación por defecto en el original | FN por defecto |
| Industria: Wispr Flow (hold Fn por defecto), Superwhisper (modificador solo, hold o toggle) | Un modificador en hold es el estándar de dictado en Mac | FN en hold; el atajo actual como manos libres |
| macOS | FN llega como `flagsChanged` con `keyCode 63` y `.function`; escucharla fuera de la app exige un event tap **listen-only** y el permiso **Monitoreo de entrada** (`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`), ligado a la identidad de firma; "Pulsar la tecla 🌐 para" tiene que estar en "No hacer nada" | `HoldKeyTap` en Services; fila de permiso en Ajustes con enlace `Privacy_ListenEvent`; aviso del ajuste 🌐 en la misma fila |

---

## 3. Decisión

### 3.0 Qué viene de dónde

| Decisión | Fuente |
|---|---|
| FN en hold; `Cmd+Opt+Space` sigue como manos libres | Karen 2026-09-06; industria |
| El reductor de sesión recibe press/release/tap; la voz obedece efectos | `relay-hud-spec/02` §1 ("el hop, no invertir"); 12a §7 |
| La voz sigue caliente entre holds con el micro cerrado | `relay-hud-spec/02` §2.3 (conectar al pulsar), 12c hará el prewarm en boot |
| Island = `NSPanel` propio, no una segunda ventana normal | `relay-hud-spec/01` §2.2–2.3 |
| Copy nuestra; sin px de ellos | `relay-hud-spec/README` (white-label); geometría en tokens propios |
| Cerrar main no cierra la app | `relay-hud-spec/01` §7 ("If main is closed, the HUD can still work") |

### 3.1 El reductor de sesión (Core)

`SessionEvent` gana:

```swift
case pressed          // la tecla bajó (o el hold empezó en la island)
case released         // la tecla subió tras un hold
case tapped           // subió antes del umbral: no hubo hold
```

`SessionEffect` gana:

```swift
case startListening                 // abre la sesión si hace falta, abre el micro
case stopListening(commit: Bool)    // cierra el micro; true = ForceEndpoint
case cancelVoiceOutput              // corta lo que la voz piensa o dice
```

`SessionCard` gana `.holdHint`. `SessionProjection` gana `targets: [String]`
(lo que el padre está abriendo, para "Abriendo Safari…" en la island) y
`holding: Bool`.

Reglas nuevas:

| Evento | Desde | A | Efectos |
|---|---|---|---|
| `.pressed` | idle / hover / completed | `.listening`, `holding = true`, `interruption = nil` | `.startListening` |
| `.pressed` | processing(.speaking / .thinking) | `.listening`, `holding = true` | `.cancelVoiceOutput`, `.startListening` |
| `.pressed` | listening (ya escuchando por manos libres) | `holding = true` | `.startListening` (idempotente) |
| `.released` | listening con `holding` | `.processing(.pending)`, `holding = false` | `.stopListening(commit: true)` |
| `.released` | sin `holding` | nada | — |
| `.tapped` | listening con `holding` | vuelve al reposo (`rest()`), card `.holdHint` | `.stopListening(commit: false)` |
| `.tapped` | otro | card `.holdHint` | — |
| `.voice(listening, muted)` | processing(.pending) | se queda en pending (la voz cerró el micro y espera el texto) | — |
| `.voice(listening, muted)` | otro | reposo: `rest()` (Completed + timer si venía de processing, si no Idle); `voice = .muted` | — |
| `.voice(listening, !muted)` | cualquiera | `.listening` | — |
| `.voice(thinking)` desde pending | `.processing(.thinking)` | — |
| `.voice(error(notHeard))` desde pending | `.idle` + `.couldntHear` (ya en 12a) | — |
| `.stop` | listening / processing con voz viva | además de 12a: `.cancelVoiceOutput` si la voz piensa o habla; `holding = false` | — |
| `.parentActing(targets)` | | `targets = targets` | — |
| `.parentActed` | | `targets = []` | — |

Cambio sobre 12a: **listening con el micro cerrado ya no es Listening**. Es
la voz caliente esperando el próximo hold; el chrome está en reposo. La
prueba 3 de `SessionMachineTests` cambia en consecuencia.

### 3.2 La máquina de voz (Core, `TurnMachine`)

Tres eventos nuevos, sin tocar los existentes:

```swift
case holdPressed(preferRealtime: Bool)
case holdReleased(hasSpeech: Bool)
case interrupt
```

| Evento | Estado | Resultado |
|---|---|---|
| `holdPressed` | idle / error | = `startVoice(preferRealtime)` con `holdArmed = true` |
| `holdPressed` | connecting | `holdArmed = true` (al llegar `realtimeSessionReady` el micro se abre porque `muted = false` de fábrica) |
| `holdPressed` | listening, realtime, muted | `muted = false`, `speechOpen = false` → `[.setMicEnabled(true), .clearInputAudio]` |
| `holdPressed` | listening, !muted | nada |
| `holdPressed` | speaking / thinking, realtime | `state = .listening`, `muted = false` → `[.cancelAgentOutput, .setMicEnabled(true), .clearInputAudio]` |
| `holdPressed` | speaking, classic | = `advance` (barge-in clásico) |
| `holdReleased` | listening, realtime, !muted | `muted = true`, `speechOpen = false` → `[.setMicEnabled(false), .commitWithText]` |
| `holdReleased` | listening, classic | = `advance(hasSpeech)` (el turno empieza si hubo voz, si no cuelga) |
| `holdReleased` | connecting | `holdArmed = false`; al llegar `realtimeSessionReady`, el micro queda cerrado (`muted = true`) y **no** se envía nada: no hubo turno |
| `holdReleased` | otro | nada |
| `interrupt` | speaking / thinking, realtime | `state = .listening` → `[.cancelAgentOutput]` (el micro se queda como estaba) |
| `interrupt` | speaking, classic | = `advance` |
| `interrupt` | otro | nada |

`TurnSnapshot` gana `holdArmed: Bool` (solo para la carrera connecting →
ready). `hangUp` lo limpia.

**Por qué no `toggleMute` para soltar:** `toggleMute` solo envía el turno si
`speechOpen` (el VAD del servidor vio voz). Soltar la tecla es un
ForceEndpoint: se envía lo que el oído nativo oyó, sin preguntarle al
servidor. `.commitWithText` ya existe (9i) y ya degrada a "nada que enviar"
cuando el texto está vacío.

### 3.3 La sesión de voz (Services, `VoiceSession`)

`VoiceControlling` gana `hold()`, `release()`, `interrupt()`:

- `hold()` → `apply(.holdPressed(preferRealtime: openAIKey() != nil))`.
- `release()` → `apply(.holdReleased(hasSpeech: await mic.receivedBuffer))`.
  Con realtime, `.commitWithText` lee `audit.turnText()`; si está vacío no
  envía nada y la máquina no cambia de estado → la sesión proyecta
  `listening + muted` → el reductor vuelve al reposo. Para que se vea la card
  "no te oí" cuando **sí** hubo hold y no hubo texto, `commitTurnFromNative`
  aplica `.utteranceEmpty` en ese caso solo cuando el commit vino de un hold
  (`fromHold: true`): en conversación continua el vacío es normal y no se
  reporta.
- `interrupt()` → `apply(.interrupt)`.

### 3.4 La tecla (Services, `HoldKeyTap`)

```swift
public enum HoldKeyEvent: Sendable, Equatable { case pressed, released, tapped }

public struct HoldKeyClassifier: Sendable {      // puro, testeable
    public var tapThreshold: TimeInterval = 0.25
    public mutating func down(at: TimeInterval) -> HoldKeyEvent?   // .pressed
    public mutating func up(at: TimeInterval) -> HoldKeyEvent?     // .tapped | .released
}

public final class HoldKeyTap: @unchecked Sendable {
    public init(keyCode: Int64 = 63)                  // FN
    public var events: AsyncStream<HoldKeyEvent>
    public func start() -> Bool                       // false si no hay permiso
    public func stop()
}

public struct InputMonitoringPermission: InputMonitoringChecking {   // Services
    func isGranted() -> Bool     // CGPreflightListenEventAccess
    func request() -> Bool       // CGRequestListenEventAccess (prompt una vez)
}
```

`HoldKeyClassifier` vive en Core (puro): `down` emite `.pressed` de
inmediato (la latencia manda: la sesión se abre al bajar, no al confirmar
el hold); `up` emite `.tapped` si pasó menos del umbral, `.released` si no.
Un `up` sin `down` no emite nada. `HoldKeyTap` (Services, CoreGraphics) es
un `CGEvent.tapCreate` en `.cgSessionEventTap`, `.listenOnly`, sobre
`flagsChanged`; FN es `keyCode 63` y el bit `.maskSecondaryFn`. Corre en
su propio `RunLoop`; publica por `AsyncStream`. Sin permiso, `start()`
devuelve `false` y no instala nada. Si macOS deshabilita el tap (timeout),
se re-habilita en el callback (`CGEvent.tapEnable`).

HACK conocidos, con disparador: FN+otra tecla (FN+flecha = Inicio/Fin)
sigue contando como hold hasta que alguien lo reporte; la tecla no es
configurable (FN fija) hasta que un usuario sin FN lo pida (teclados
externos sin FN).

### 3.5 La island (UI, `NSPanel`)

`IslandPanel` (UI, AppKit): `NSPanel` con `[.nonactivatingPanel, .borderless,
.fullSizeContentView]`, `level = .statusBar`, `collectionBehavior =
[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, fondo
transparente, `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded = true`,
`isMovableByWindowBackground = false`, `acceptsMouseMovedEvents = true`.
Anclada en `IslandChrome.dock(on: screen, size:)`: centrada en X, pegada al
borde superior de `NSScreen.main`, bajo el notch si lo hay
(`safeAreaInsets.top`), sin px de nadie: tamaños en `IslandChrome` (tokens
propios, uno por kind: pebble, hover, listening, processing, card).

`IslandView` (SwiftUI) lee `chat.session.projection` y `voice.levels`:

| Kind | Pinta | No pinta |
|---|---|---|
| Idle | Pebble: cápsula con punto de acento. Oculto si `IslandPreference.pebbleHidden`. Card `.couldntHear` / `.permission` / `.holdHint` mientras dure `interruption` o hasta el siguiente evento | Transcripción, campo de texto |
| Hover | Nudge (más grande) + "Mantén FN para hablar" | — |
| Listening | Island crecida, medidor del micro (`levels.mic`), "Escuchando…" | Historial |
| Pending | "…" sin medidor | Medidor vivo |
| Thinking | "Pensando…" con shimmer | Ventana nueva |
| ToolExecuting | "Abriendo Safari…" (`targets`) | JSON |
| Speaking | Nivel del agente (`levels.agent`) | Reproductor |
| SubAgentRunning | Fila: objetivo, último paso, `n pasos`, botón Stop | El informe entero |
| Completed | Marca breve; el timer devuelve al pebble | Un quinto estado |
| Cualquiera con `approval` | `ApprovalSheet` hospedada en la island (la island crece); Aprobar / Denegar responden por `chat.answerApproval` | Traer main al frente |

Botón Stop visible en cualquier Processing y en Listening manos libres:
`chat.cancelJob()` si hay encargo; si no, `session.send(.stop)`. Esc en
main sigue igual. Click en el pebble → muestra main (`MenuRouting.showMain`).
Hover en el panel → `.hoverEntered / .hoverLeft`. Mantener el pebble con
el ratón → `.pressed` / `.released` (el mismo camino que la tecla, para
quien no tiene FN).

`IslandState.from(projection, levels, pebbleHidden)` es una función pura
(struct `IslandState`: `size`, `title`, `meter`, `showsStop`, `hidden`) para
que lo que la island decide se pruebe sin instanciar vistas.

### 3.6 Ajustes (App tab)

El bloque "ATAJO" pasa a "HABLAR":

- Fila "Mantén FN para hablar" (fija) + subtítulo con el aviso del ajuste
  del sistema "Pulsar la tecla 🌐 para: No hacer nada".
- `PermissionRow(kind: .inputMonitoring)` con estado y botón: primero
  `request()` (el prompt del sistema, una vez), después el enlace
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`.
- Fila del atajo de manos libres (la de siempre, `Cmd+Opt+Space`), con
  subtítulo "Manos libres: abre y cuelga la voz".
- Toggle "Mostrar el punto en reposo" (`IslandPreference.pebbleHidden`).

### 3.7 La app (`CompanionMain`)

- Crea `IslandPanel` con `IslandView(chat:voice:)` y lo muestra al arrancar.
- `HoldKeyTap` + `HoldKeyClassifier`: si el permiso está concedido, `start()`
  y bombea `events` → `sessionModel.send(.pressed / .released / .tapped)`.
  Si no, el log lo dice una vez y la fila de Ajustes lo muestra; al
  concederse (la fila pregunta al volver a primer plano), se arranca.
- `SessionModel(voice:)`: el puerto de voz para los efectos nuevos.
- `applicationShouldTerminateAfterLastWindowClosed → false`;
  `applicationShouldHandleReopen` vuelve a mostrar main; menú "Ventana ›
  Mostrar Companion".
- El tap corre solo cuando FN es el modo activo; no hay más monitores
  globales.

### 3.8 Archivos que toca

| Capa | Archivo | Qué |
|---|---|---|
| Core | `SessionTypes.swift`, `SessionMachine.swift` | §3.1 |
| Core | `TurnTypes.swift`, `TurnMachine.swift` | §3.2 |
| Core | `VoicePorts.swift` | `hold()` / `release()` / `interrupt()` |
| Core | `HoldKey.swift` (nuevo) | `HoldKeyEvent`, `HoldKeyClassifier` |
| Core | `Permissions.swift` | `InputMonitoringChecking`, `PermissionSettingsLink.inputMonitoring` |
| Core | `IslandState.swift` (nuevo) | la función pura de §3.5 |
| Services | `VoiceSession.swift` | §3.3; `commitTurnFromNative(fromHold:)` |
| Services | `HoldKeyTap.swift` (nuevo), `InputMonitoringPermission.swift` (nuevo) | §3.4 |
| UI | `SessionModel.swift` | puerto `voice`, tres efectos |
| UI | `IslandPanel.swift`, `IslandView.swift`, `IslandChrome.swift` (nuevos) | §3.5 |
| UI | `VoiceViewModel.swift` | `hold()` / `release()` (para el pebble con ratón) |
| UI | `PermissionRow.swift`, `SettingsAppPane.swift`, `ContextSettings.swift` o `HoldSettings.swift` (nuevo) | §3.6 |
| UI | `MenuPlan.swift`, `Shortcuts.swift` | `showMain` |
| UI | `en.lproj/es.lproj/Localizable.strings` | copy de la island y de Ajustes |
| App | `CompanionMain.swift` | §3.7 |
| Tests | `SessionMachineTests` (+pressed/released/tapped/muted), `TurnMachineTests` (+hold), `HoldKeyTests` (nuevo), `IslandStateTests` (nuevo), `SessionModelTests` (+efectos al puerto de voz), `VoiceSessionTests` (+hold/release en realtime y clásico), `catalogParityTests` | §5 |

---

## 4. Restricciones

- Sin código de Incredible, sin sus px, sin sus strings, sin su esquema de
  URL. Geometría en `IslandChrome` con tokens nuestros.
- Core sin AppKit ni CoreGraphics. `HoldKeyTap` en Services. `IslandPanel`
  en UI (AppKit está permitido en UI).
- Ningún monitor global además del tap de FN. El tap es listen-only: no
  consume ni modifica eventos.
- La island nunca se activa (`nonactivatingPanel`); el foco se queda donde
  estaba.
- Las reglas de conformidad (`session-kind-write`, tokens, copy en catálogo)
  aplican a las vistas nuevas. Sin `try?` en Core/Services.
- `applicationShouldTerminateAfterLastWindowClosed` pasa a `false`: Cmd+Q y
  el menú siguen cerrando.

---

## 5. TDD (tests antes que código)

| # | Test | Espera |
|---|---|---|
| 1 | `HoldKeyClassifier`: down → `.pressed`; up a 0.1 s → `.tapped`; up a 0.6 s → `.released`; up sin down → nil; down repetido (auto-repeat) → nil | puro |
| 2 | `SessionMachine.pressed` desde idle | `.listening`, `holding`, efecto `.startListening` |
| 3 | `.pressed` desde speaking | `.listening`, efectos `.cancelVoiceOutput` + `.startListening` |
| 4 | `.released` con holding | `.processing(.pending)`, `.stopListening(commit: true)` |
| 5 | `.released` sin holding | sin efectos ni cambio |
| 6 | `.tapped` con holding desde idle | reposo (idle), card `.holdHint`, `.stopListening(commit: false)` |
| 7 | `.voice(listening, muted)` en pending | sigue pending |
| 8 | `.voice(listening, muted)` desde processing(.speaking) | completed + timer; desde idle → idle; `voice = .muted` |
| 9 | `.voice(listening, !muted)` | `.listening` (la 3 de 12a, reescrita) |
| 10 | pending → `.voice(thinking)` → `.voice(speaking)` → `.voice(listening, muted)` | thinking → speaking → completed + timer → idle |
| 11 | pending → `.voice(error(notHeard))` | idle + `.couldntHear` |
| 12 | `.stop` en speaking | idle + `.cancelVoiceOutput`; `holding = false` |
| 13 | `.parentActing(["Safari"])` / `.parentActed` | `targets` se llena y se vacía |
| 14 | `TurnMachine.holdPressed` desde idle realtime | `[.openRealtimeSession]`, connecting, `holdArmed` |
| 15 | `holdPressed` en listening muted | `[.setMicEnabled(true), .clearInputAudio]`, `!muted` |
| 16 | `holdPressed` en speaking realtime | `[.cancelAgentOutput, .setMicEnabled(true), .clearInputAudio]`, listening |
| 17 | `holdReleased` en listening realtime | `[.setMicEnabled(false), .commitWithText]`, `muted` |
| 18 | `holdReleased` en connecting → `realtimeSessionReady` | listening con `muted`, sin commit |
| 19 | `holdReleased(hasSpeech:)` en clásico | true → `[.submitUtterance]`; false → cuelga |
| 20 | `interrupt` en thinking realtime | `[.cancelAgentOutput]`, listening; en idle → nada |
| 21 | `SessionModel`: `.pressed` llama a `voice.hold()` (fake); `.released` a `release()`; `.stop` en speaking a `interrupt()` | puertos |
| 22 | `VoiceSession.hold()` + `release()` en realtime con texto nativo "abre Safari" | se envía `conversation.item.create` con el texto y `response.create`; el micro queda cerrado (`micEnabled == false`) |
| 23 | `hold()` + `release()` sin texto | no se envía nada; el snapshot proyecta `listening + muted`; `.utteranceEmpty` llega (notHeard) |
| 24 | `hold()` mientras el agente habla | `response.cancel` + micro abierto |
| 25 | `hold()` / `release()` en clásico (sin clave) | escucha, y al soltar con voz empieza el turno |
| 26 | `IslandState.from`: idle → pebble; idle + pebbleHidden → hidden; hover → nudge + hint; listening → meter; processing(.subAgentRunning) con job → fila + stop; approval → card grande; completed → marca | puro |
| 27 | `PermissionRowModel(kind: .inputMonitoring)` tiene título, cuerpo y enlace `Privacy_ListenEvent` | catálogo |
| 28 | Paridad en/es de las claves nuevas | `catalogParityTests` |

---

## 6. Prueba manual (solo Karen)

1. Ajustes › Sistema: "Pulsar la tecla 🌐 para" en "No hacer nada".
   Companion › Ajustes › App › HABLAR: conceder Monitoreo de entrada (el
   prompt del sistema, o el enlace).
2. Con Companion **detrás** (Safari delante): mantener FN, decir "qué hora
   es", soltar. La island baja del notch al pulsar, muestra el medidor,
   "…" al soltar, "Pensando…", y la respuesta suena. Safari sigue con el
   foco.
3. Tap FN (corto): la island muestra "Mantén FN para hablar" y vuelve al
   pebble. Nada se envía.
4. Mantener FN mientras Companion habla: se calla y escucha.
5. Mantener FN y no decir nada: "No te oí" y vuelve al pebble.
6. Delegar por voz ("crea un archivo en el escritorio"): la island muestra
   la fila del encargo con Stop; pulsar Stop la cierra y el registro queda
   en el hilo.
7. Un `open_url` que no dijiste: la hoja aparece **en la island**; Aprobar
   / Denegar funcionan sin traer main.
8. Cerrar la ventana principal: la app sigue; el pebble sigue; FN sigue.
   Click en el pebble → vuelve main. Cmd+Q cierra.
9. Sin permiso: la fila de Ajustes lo dice y ofrece el enlace; FN no hace
   nada; el orb y `Cmd+Opt+Space` siguen funcionando.

---

## 7. Fuera de alcance

- Prewarm en boot y métricas (`stt_*_at_ms`): **12c**.
- Transcripción parcial en la island mientras se mantiene: **12c** (exige
  un stream de parciales de `VoiceAudit`).
- Dictado en el campo enfocado (spec 11 del corpus): otra wave.
- Glow / outline (G5), confirmación de spawn (G6), desktop-mini, chat-input
  como ventana aparte: no.
- Los cuatro closures hacia dentro de `VoiceSession.init` (`onDelegate`,
  `onStopJob`, `onResolveApproval`, `onMCPApproval`): siguen. Pasarlos a
  efectos exige que el especialista viva en el reductor (fila del hijo con
  spawn), que es 12c o después.
- Tecla configurable para el hold; FN+combos: HACK anotados en §3.4.
- Arrastrar la island / posición guardada (`session_bar_position`): no.

---

## 8. Fuentes

- `~/Desktop/relay-hud-spec/00-goals-and-auditors.md` (G1, G3, G4),
  `01-hud-anatomy.md` (§2.1–2.4, §4, §7), `02-interaction.md` (§1, §2.3–2.8,
  §9, §10), `03-screens-and-states.md` (§2), `05-replication-checklist.md`
  (§4, §5, §7, §9, §12).
- `AI_Research/AIResearch/specs/01` (hold timeline, ForceEndpoint), `16`
  (`UserPressedActivation` / `Released` / `Tapped`), `19`, `25`, `28` §10.1;
  `COMPANION-MAP.md` §4 D3 y §5 fila 7.
- companion: `TurnMachine.swift`, `VoiceSession.swift`, `KeyboardMonitor.swift`,
  `ControlBar.swift`, `WindowChrome.swift`, `CompanionMain.swift`,
  `PermissionRow.swift`, `SettingsAppPane.swift`.
- Apple: `CGEvent.tapCreate`, `CGPreflightListenEventAccess`,
  `CGRequestListenEventAccess`, `NSPanel.StyleMask.nonactivatingPanel`,
  `NSScreen.safeAreaInsets`.

---

## 9. Desviaciones respecto a esta spec (al entregar)

| # | La spec decía | Lo que hay | Por qué |
|---|---|---|---|
| 1 | `.pressed` en speaking → `.cancelVoiceOutput` + `.startListening` | Solo `.startListening`; `TurnMachine.holdPressed` corta al agente por su cuenta al abrir el micro | Un efecto, una responsabilidad: la voz sabe cortar cuando le abren el micro mientras habla. `.cancelVoiceOutput` queda para `.stop` |
| 2 | Card `.holdHint` / `.couldntHear` de un paso | `SessionProjection.notice`: la card que el reposo conserva hasta que algo nuevo empieza (`pressed`, `typedSubmitted`, `started`, `parentActing`, escuchar de verdad) | La snapshot de la voz que sigue a un tap o a una suelta vacía borraba la card en milisegundos |
| 3 | `stopListening(commit: false)` sin evento en la voz | `TurnEvent.holdDiscarded` + `VoiceControlling.discard()` | Un tap cierra el micro y limpia el buffer sin enviar; ni `toggleMute` ni `holdReleased` hacían eso |
| 4 | `VoiceViewModel.hold()` / `release()` para el pebble con ratón | No existen; el pebble manda `.pressed` / `.released` / `.tapped` al `SessionModel` con el mismo `HoldKeyClassifier` que la tecla | Un solo camino para el hold, venga de donde venga |
| 5 | Island "bajo el notch si lo hay (`safeAreaInsets.top`)" | Anclada en `visibleFrame.maxY`: justo debajo de la banda del menú / notch, centrada | El notch es un recorte físico: dibujar debajo de él es invisible. Visto en vivo: la cápsula asoma bajo la banda, encima de las ventanas |
| 6 | Menú "Ventana › Mostrar Companion" | No | Clic en el Dock (`applicationShouldHandleReopen`) y tap en el pebble ya traen main; el instalador del menú no está en UI |
| 7 | — | `SessionEvent.pendingTimedOut` + `SessionEffect.schedulePendingExpiry` (12 s) | Un turno enviado al que el servidor no responde no puede dejar la island en "Enviando…" para siempre |
| 8 | — | `SessionEvent.heardNothing`, emitido por `VoiceSession` cuando una suelta no tiene texto | `.utteranceEmpty` en la máquina de voz cae al clásico (`recover`) si hay conversación; el hold vacío no es un fallo de la voz, es "nada que enviar" |
| 9 | La sesión "sigue caliente entre holds con el micro cerrado" | Así es, y con el VAD del servidor activo (`voice.turnDetection`) una pausa larga dentro de un hold envía antes de soltar | HACK: se apaga el VAD del servidor cuando la sesión la abre un hold, cuando alguien lo reporte. Hoy degrada a conversación continua, no rompe |
| 10 | `IslandChrome.dock(on:size:)` con tokens "uno por kind" | `IslandChrome` con anchos por rol (`pebbleWidth` 64, `nudgeWidth` 160, `barWidth` 320, `cardWidth` 480, `meterSide` 32) y alto según el contenido | La retícula prohíbe aritmética sobre `Space`; el alto lo mide la vista y lo devuelve al panel |
| 11 | Hover por SwiftUI | `NSTrackingArea` (`.activeAlways`) en la vista huésped del panel | El panel nunca es key; el hover de SwiftUI no cuenta ahí |
| 12 | Test 22-25 en `VoiceSessionTests` | `HoldVoiceTests.swift` aparte | `VoiceSessionTests` ya pasa de mil líneas |
| 13 | `SessionModel(voice:)` recibe la sesión | `VoicePortBox` en la app: el reductor nace antes que la sesión que le obedece | Orden de construcción en `CompanionMain`; la caja se rellena una vez |
| 14 | — | `SessionMachine.voiceIdleTimeout` (20 s): una sesión abierta por un hold que reposa con el micro cerrado cuelga sola; `SessionEvent.voiceIdleExpired`, `SessionEffect.scheduleVoiceIdleExpiry` / `.hangUpVoice` | Security review: la puerta del micro es software; el hardware seguía tomado con la ventana cerrada. El siguiente hold dentro del plazo la encuentra caliente; pasado, reconecta (12c precalienta sin micro) |
| 15 | — | El pebble no se oculta mientras `projection.voice != .off` | Es la única marca nuestra de que el micro está tomado |
| 16 | — | `IslandState.from(_:pebbleHidden:mainInFront:)`: con main key la island no hospeda la hoja | Dos hojas para la misma petición confundían |
| 17 | — | `ApprovalClickGuard` (0,6 s): la hoja de la island ignora el clic que ya iba en camino | Aparece bajo el puntero, sobre cualquier app |

---

## 10. Revisiones (2026-09-06)

### 10.1 Seguridad (security-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | Entre holds, `setMicEnabled(false)` cierra la puerta por software; el `AVAudioEngine` sigue tomando el micro físico, sin ventana ni marca propia (el pebble podía estar oculto) | Test primero: `testAWarmHoldSessionIdlesOut` (SessionMachineTests 33), `testTheWarmSessionHangsUpThroughThePort` (SessionModelTests 33b), `testPebbleShowsWhileTheMicIsEngaged` (HoldKeyTests 26c). Plazo de 20 s en reposo → `hangUp` (socket, reproductor y micro); el pebble no se oculta con la voz viva. La manos libres silenciada desde la ventana no cuelga sola: su botón muestra el estado. Con AEC el reproductor comparte el motor del micro: parar solo el micro entre holds mataría la respuesta, por eso se cuelga entero |
| 2 | Media | La hoja de la island aparece bajo el puntero sobre cualquier app y un clic la responde sin reposo | Test primero: `testApprovalClickGuard` (HoldKeyTests 26d). `ApprovalClickGuard.dwell` 0,6 s; la respuesta antes de eso se ignora. «Recordar» sigue en falso por defecto; la island nunca es key, así que Enter/Esc no llegan |
| 3 | Baja | Un clic simple en el pebble abre el micro < 250 ms antes de resolverse como tap | Aceptado: mismo clasificador que la tecla (la latencia manda); con el cierre 1 el micro se suelta al vencer el plazo |
| — | Verificado | Tap listen-only solo sobre `flagsChanged` (no puede ver teclas imprimibles); sin datos de tecla ni transcripción en el log de este diff; permiso solo por las APIs de Apple; `audit.consume()` no reenvía texto ya enviado | — |
| P | Previo | `VoiceAudit.logTurn()` escribe la transcripción literal en `~/Library/Logs`; el hold desde cualquier app la dispara más | Fuera del diff de 12b. Ticket en ROADMAP (deuda): decidir si el log de turnos guarda longitud y latencias en vez del texto |

### 10.2 Código (code-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | `VoiceSession.release()` leía la snapshot, suspendía en `mic.receivedBuffer` y aplicaba después: una pulsación en el hueco reabría el micro y la suelta vieja lo cerraba | Test primero: `testAPressDuringAReleaseWins` (HoldVoiceTests 23c, falla sin la guarda). `holdGeneration` sube en cada `hold()`; la suelta lee el micro, compara y, si hubo pulsación, se descarta |
| 2 | Alta | Pulsar, soltar y volver a pulsar antes de `realtimeSessionReady` dejaba `muted` y la sesión llegaba con el micro cerrado y la tecla apretada | Test primero: `testTurnMachineRePressWhileConnecting` (TurnMachineTests 18b). `holdPressed` en connecting pone `muted = false` |
| 3 | Alta | La misma petición se pintaba en la hoja de main y en la card de la island | Test primero: `testIslandYieldsTheSheetToMain` (HoldKeyTests 26b). `mainInFront` desde `NSWindow.didBecomeKey/didResignKey` → `HoldSettingsModel.mainInFront` → `IslandState.from(..., mainInFront:)` |
| 4 | Media | `HoldKeyTap.port` se leía en el hilo del tap y se escribía en `stop()` sin el lock | Sin test (carrera de hilos sin harness): `port` y `runLoop` bajo el mismo `NSLock`; el hilo del tap comprueba `self.port === port` |
| 5 | Media | `stop()` antes de que el hilo fijara `runLoop` dejaba un `CFRunLoopRun` sin nadie que lo parase | Sin test (mismo motivo): el hilo sale si el puerto ya no es el suyo y corre el loop en tramos de 1 s mientras lo sea; `stop()` invalida bajo el lock |
| 6 | Baja | `stop()` no se llamaba nunca | `applicationWillTerminate` lo llama |
| 7 | Baja | `onSize` durante `IslandPanel.init` cae en `island == nil`; la siembra manual lo cubre | Aceptado, comentado aquí: la siembra en `CompanionMain` es la que pinta el primer frame |
