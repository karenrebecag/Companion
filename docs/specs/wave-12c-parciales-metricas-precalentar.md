# Wave 12c — Ver lo que oye: parciales en la island, un hold es un turno, métricas y precalentado

**Estado: ENTREGADA (2026-09-06).** Gates verdes (234 grupos en `swift test`, 13 funciones de test nuevas); la
línea `prewarm:` vista en vivo en el arranque; desviaciones en §9,
revisiones en §10. Cubierta por la aprobación de Karen del
2026-09-06 ("vamos. aplica y loopea para continuar con toda la spec de
cambios que sean visibles") sobre el orden aprobado de la Wave 12 (12a
reductor → 12b hold + island → 12c precalentar + métricas + parciales →
12d contratos). Tercera pieza del HUD (`~/Desktop/relay-hud-spec/`, fuera
del repo). Cubre la fila Listening de `relay-hud-spec/01` §2.1 ("Meter +
partial transcript region"), `relay-hud-spec/03` §2.3 (partial transcript
on the island) y §2.4 (Pending: "waiting for the last words"), y el hueco
**D8** del mapa (`COMPANION-MAP.md` §4, "Sin prewarm"). Depende de 12b.

Sin commit: Karen commitea.

---

## 1. El defecto, medido

**A. Mientras mantienes FN no ves nada de lo que se oye.** La island pinta
"Escuchando…" y el medidor (`IslandState.Line.listening`); el texto que el
oído va reconociendo solo existe dentro de `VoiceAudit` (`turnText()`), y el
stream `Transcriber.partials` no lo consume nadie en `Sources/`
(grep 2026-09-06: el único lector está en `VoicePortsTests`). La spec de
producto pone el parcial en la island en Listening y lo deja en Pending
("waiting for the last words").

**B. Las primeras palabras de un hold se pierden.** `openRealtimeSession`
arranca el oído (`audit.begin`) solo **después** de `waitForReady()`
(`VoiceSession.swift:440`), y `startPumps()` solo después de
`transport.open`. Con un hold, el usuario habla desde el keydown; hasta que
el socket está listo (~1 s) los frames llegan al pump con el oído apagado
(`VoiceAudit.hear`: `guard enabled`) y se descartan. El corpus lo dice al
revés: "send PCM immediately (do not wait for silence)" y conectar **bajo**
la frase, no antes de ella (spec 01, "Hold-to-talk timeline").

**C. Un hold no es un turno.** Con el VAD del servidor activo
(`voice.turnDetection`, por defecto), una pausa dentro de un hold produce
`EarTurnEvent.finished` → `earSegment` → `.serverSpeechStopped` →
`.commitWithText` (`VoiceSessionPumps.swift:63`): el turno viaja **antes**
de soltar. Quedó anotado como HACK en 12b §9.9. El producto es
"keyup = ForceEndpoint": lo que se dice mientras se mantiene es un turno.

**D. Nada mide el hold.** No hay una sola línea en el log con
press → listo, press → primer parcial, soltar → envío, envío → primer
audio. El corpus optimiza con esas etiquetas (`press-time`, `stt/connect`,
`stt/final`, `tts_first_audible_ms`); sin ellas la decisión de precalentar
el socket (D8) es opinión.

**E. Boot no precalienta nada.** `MicCapture` se construye pero no prepara
el motor; la clave se lee del llavero en la primera pulsación; el primer
hold paga VPIO + llavero + socket + oído en serie (`COMPANION-MAP.md` D8).

**F. La pista del hold no aprende.** El nudge de hover dice "Mantén FN para
hablar" siempre; la spec la muestra solo hasta el primer hold completado
(`completed_hold_to_talk`, `relay-hud-spec/02` §2.2).

---

## 2. Lo que dice la spec de producto, el corpus y la industria

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| `relay-hud-spec/03` §2.3 | Listening: medidor + **partial transcript** en la island (`SttPartialTranscript` → snapshot) | `SessionEvent.partialTranscript(String)` → `SessionProjection.partial` → `IslandState.partial` |
| `relay-hud-spec/03` §2.4 | Pending: "waiting for the last words"; el medidor se para; luego thinking o Idle | El parcial sigue en Pending; se borra cuando la fase cambia |
| `relay-hud-spec/04` §reducer | `(Listening, SttPartialTranscript) => (Listening, [EmitUiProjection])`: el parcial no cambia el kind | El reductor solo escribe `partial`; el kind no se mueve |
| `relay-hud-spec/02` §2.3 | Conectar el socket **al pulsar** y mandar PCM **ya**, sin esperar silencio | El oído arranca al pulsar, en paralelo con el socket; el pump de frames arranca con el micro |
| `relay-hud-spec/02` §2.2 | `HoldToTalkHint` solo si no han completado un hold (`completed_hold_to_talk`) | `HoldSettingsModel.holdLearned` (UserDefaults); el nudge de hover deja de decirlo |
| Corpus spec 01, "Hold-to-talk timeline" | `press-time`, `stt/connect`, `stt/final`, `stt/zero-samples`, `tts_first_audible_ms`; precalentar el token en boot y medirlo (`prewarm_ms`) | `TurnTimeline` (Core, pura) con una línea por hold; `prewarm:` medido en boot. Los nombres son nuestros |
| Corpus spec 01, "Why keydown, not keyup" | Un socket frío al soltar añade 200-800 ms de aire muerto; el prewarm + conectar al pulsar lo esconde bajo la frase | El socket sigue abriéndose al pulsar (se reutiliza caliente 20 s, 12b §9.14); lo que se precalienta en boot es lo que no caduca: motor del micro, clave, alcance de red |
| Corpus spec 01, `stt/zero-samples` | Una suelta sin audio no es un turno | Ya: `heardNothing` (12b) |
| Wispr Flow / Superwhisper | El texto aparece mientras mantienes; soltar lo pega | Parcial visible en la island, tail visible (`truncationMode(.head)`) |
| OpenAI Realtime | Sesiones con vida máxima y cierre por inactividad; un socket abierto en boot puede estar muerto a la primera pulsación | No se precalienta el socket en boot; se mide `press→ready` y se decide después con datos (§7) |

---

## 3. Decisiones

### 3.1 El parcial es un campo de la proyección, no un kind

- `SessionEvent.partialTranscript(String)`: solo en `.listening` escribe
  `projection.partial`; en cualquier otro kind se ignora.
- `SessionProjection.partial: String?` se borra en `begin()` (algo nuevo
  empieza), en `.tapped`, `.heardNothing`, `.stop`, y cuando el kind deja de
  ser `.listening` o `.processing(.pending)`.
- `IslandState.partial: String?` viaja con las líneas `.listening` y
  `.pending`; la island lo pinta debajo de la línea, dos renglones como
  máximo, con la cola visible.
- Origen: `VoiceAudit.partials: AsyncStream<String>` publica `turnText()`
  cada vez que el oído nativo cambia su hipótesis (dedupe por igualdad).
  `VoiceSession.pumpPartials()` lo reenvía como `SessionEvent` mientras el
  micro está abierto por un hold (`holdArmed && !muted`) y en Pending. La
  manos libres no publica parciales (su ventana ya tiene el hilo).

### 3.2 El oído arranca al pulsar

`openRealtimeSession()` cambia de orden:

1. `mic.requestAccess()`, `mic.start()`, `player.start()` (como hoy).
2. **Nuevo:** el pump de frames arranca aquí (`startFramePump()`), y
   `audit.begin(locale:)` arranca **en paralelo** con `transport.open` +
   `waitForReady` (`async let`).
3. Si el socket falla, `closeRealtime()` ya apaga el oído (`audit.end()`).

La razón original de esperar a ready ("armar el oído para un turno que
nunca abrió parecería el clásico sin red") se cubre con el log: el fallo
del socket sigue siendo `sessionDropped`/`networkUnavailable`, el oído se
apaga en el mismo `closeRealtime`.

### 3.3 Un hold es un solo turno

En una sesión abierta por un hold (`machine.snapshot.holdArmed`), la
tecla es dueña del turno y el VAD del servidor no lo es: en
`pumpEarTurns`, `.speechStarted` y `.finished` se ignoran mientras
`holdArmed` (esto es, también después de soltar y después de un tap: un
segmento que llega tarde no es un turno nuevo ni resucita lo descartado).
Al soltar, `commitTurnFromNative` envía `turnText()`: el texto corrido del
oído desde la última consumición, que incluye los segmentos cerrados
durante el hold **y** el que iba en vuelo al soltar. Cada pulsación
consume el oído (`audit.consume()`) para que lo que el oído entregue tarde
del hold anterior no se cuele en el siguiente. Cierra 12b §9.9.

(La primera versión acumulaba los segmentos en `heldSegments` y los
enviaba al soltar; las revisiones mostraron que perdía el segmento en
vuelo, que un `.finished` tardío tras soltar o descartar se enviaba como
segundo turno, y que uno tardío tras la pulsación siguiente se colaba en
ella. Ver §9 y §10.)

### 3.4 Métricas: una línea por hold

`TurnTimeline` (Core, pura, `Equatable`):

```swift
public struct TurnTimeline: Sendable, Equatable {
    public var pressed, micReady, earReady, sessionReady,
               firstPartial, released, committed, firstAudio: TimeInterval?
    public mutating func mark(_ point: Point, at: TimeInterval)   // primera vez gana
    public func line() -> String?   // nil sin `pressed`
}
```

La línea (ms enteros, "—" cuando falta):

```
voice timeline: press→mic 82 · press→ear 610 · press→ready 940 · press→partial 1420 · release→commit 260 · commit→audio 880
```

Quién marca (todo en el actor `VoiceSession`):

| Punto | Dónde |
|---|---|
| `pressed` | `hold()` |
| `micReady` | primer frame del pump con `pressed` marcado |
| `earReady` | `audit.begin` devuelve con el oído encendido |
| `sessionReady` | `apply(.realtimeSessionReady)` |
| `firstPartial` | primer parcial no vacío del hold |
| `released` | `release()` (tras la guarda de generación) |
| `committed` | `realtime.commitWithText` en `commitTurnFromNative` |
| `firstAudio` | `apply(.agentAudioStarted)` → se escribe la línea y se reinicia |

Una línea también al colgar o al pulsar de nuevo si el hold anterior no
llegó a `firstAudio` (con los puntos que tenga). Sin texto de la
transcripción en la línea.

### 3.5 Precalentar en boot, medido

`VoiceSession.prewarm()` (nuevo, llamado desde `CompanionMain` después de
construir la sesión, en una `Task` de baja prioridad):

1. `mic.prewarm()` (nuevo en `MicCapturing`, extensión por defecto no-op):
   `MicCapture` solo si el micro **ya está autorizado**
   (`AVCaptureDevice.authorizationStatus(for: .audio) == .authorized`,
   nunca pide el permiso en boot): `prepareEngine()` + `engine.prepare()`,
   sin arrancar. VPIO construye su dispositivo agregado aquí, no en la
   primera pulsación.
2. `reachability.isOnline` (calienta el probe).

Log: `prewarm: mic 412 ms · net 1 ms`. El socket y el oído no se
precalientan (§2, fila OpenAI Realtime). **El llavero tampoco**: la
primera versión leía la clave para calentar `CachingSecretStore`, y en la
build de desarrollo esa lectura abrió el diálogo del llavero en el
arranque (visto en vivo el 2026-09-06, `SecItemCopyMatching` bloqueado
en `sample`). Una lectura del llavero puede ser un diálogo; un diálogo
al arrancar no es precalentar. Test 9 lo exige (`secrets.reads == 0`).

### 3.6 La pista del hold aprende

`HoldSettingsModel.holdLearned` (UserDefaults `companion.island.holdLearned`),
se pone a `true` la primera vez que la proyección entra en
`.processing(.pending)` desde un hold (la island lo observa: es su pista).
`IslandState.from(_:pebbleHidden:mainInFront:holdLearned:)`: con
`holdLearned`, hover pinta el nudge sin línea (`.none`); `.tapped` sigue
enseñando el hold (un tap es pedir la pista).

### 3.5b Lo que enseñó el arranque en vivo

- `Task(priority: .utility)` heredada por el main actor en
  `applicationDidFinishLaunching` **nunca corrió** ("scheduled" en el log
  y nada después, 8 s); `Task.detached` sí. Queda como `Task.detached`
  con el porqué en el comentario.
- `engine.prepare()` sobre un grafo sin tap instalado lanza una excepción
  de Objective-C (`required condition is false: inputNode != nullptr ||
  outputNode != nullptr`) que mata el proceso sin informe de fallo. El
  prewarm del micro se queda en `prepareEngine()`; `start()` prepara
  cuando el tap existe.
- `pkill` a la app deja a macOS preguntando "¿reabrir ventanas?" en el
  arranque siguiente, un diálogo modal **antes** de
  `applicationDidFinishLaunching`: la app parece viva y muda. Para las
  pruebas: salir con `quit` o lanzar con `-ApplePersistenceIgnoreState YES`.

### 3.7 API

Core:

- `SessionEvent.partialTranscript(String)`; `SessionProjection.partial`.
- `IslandState.partial`; `IslandState.from(..., holdLearned: Bool = false)`.
- `TurnTimeline` (`Sources/CompanionCore/TurnTimeline.swift`).
- `MicCapturing.prewarm()` con extensión por defecto.

Services:

- `VoiceAudit.partials`; `VoiceSession.prewarm()`, `pumpPartials()`,
  `heldSegments`, `timeline`; `MicCapture.prewarm()`.

UI:

- `IslandView` pinta `partial`; escribe `holdLearned`.
- `HoldSettingsModel.holdLearned`.

App:

- `CompanionMain`: `Task(priority: .utility) { await session.prewarm() }`.

### 3.8 Archivos

| Capa | Archivo | Cambio |
|---|---|---|
| Core | `SessionTypes.swift` | evento + campo `partial` |
| Core | `SessionMachine.swift` | `partialTranscript`, borrado del parcial |
| Core | `IslandState.swift` | `partial`, `holdLearned` |
| Core | `TurnTimeline.swift` | nuevo |
| Core | `VoicePorts.swift` | `MicCapturing.prewarm()` |
| Services | `VoiceAudit.swift` | `partials` |
| Services | `VoiceSession.swift` | `prewarm()`, timeline, orden de arranque, `heldSegments` |
| Services | `VoiceSessionPumps.swift` | `pumpPartials`, `startFramePump`, hold en `pumpEarTurns` |
| Services | `MicCapture.swift` | `prewarm()` |
| UI | `IslandView.swift`, `HoldSettings.swift` | parcial, `holdLearned` |
| App | `CompanionMain.swift` | prewarm en boot |
| Tests | `SessionMachineTests`, `HoldKeyTests`, `HoldVoiceTests`, `TurnTimelineTests` (nuevo), `VoiceSessionTests` (fake) | §5 |

---

## 4. Restricciones

- Core puro; sin `try?` en Core/Services; retícula (`Space`/`Radius`),
  nada literal en UI; copy en catálogo en/es (sin claves nuevas: el parcial
  es texto del usuario).
- El parcial nunca va al log (ya lo hace `audit.logTurn`, deuda anotada en
  ROADMAP); la línea de métricas lleva solo milisegundos.
- `prewarm()` no pide permisos ni abre sockets; si algo falla, una línea
  de log y nada más.
- Sin cambios en `Package.swift` / `Info.plist`.
- El reductor sigue siendo el único escritor de la proyección
  (`session-kind-write`).

---

## 5. TDD (RED → GREEN)

| # | Test | Archivo |
|---|---|---|
| 1 | `partialTranscript` en Listening escribe `projection.partial`; en Idle se ignora | SessionMachineTests |
| 2 | El parcial sobrevive a `.released` (Pending) y se borra al pasar a thinking, en `.tapped`, `.heardNothing`, `.stop` y en `.pressed` | SessionMachineTests |
| 3 | `IslandState.from` lleva `partial` en `.listening` y `.pending`; en thinking no | HoldKeyTests |
| 4 | Con `holdLearned`, hover es nudge sin línea; sin él, `.holdHint`; `.tapped` enseña siempre | HoldKeyTests |
| 5 | `TurnTimeline.line()`: `nil` sin `pressed`; ms enteros; "—" en huecos; `mark` no pisa la primera marca | TurnTimelineTests |
| 6 | Hold: el oído está encendido **antes** de `sessionUpdated` (frames del hold llegan al transcriptor durante connecting) | HoldVoiceTests |
| 7 | Hold con oído segmentador: un `.finished` mid-hold no envía; al soltar viaja el texto acumulado | HoldVoiceTests |
| 8 | Hold: los parciales del oído salen por `events` como `.partialTranscript` mientras se mantiene; ninguno tras soltar y pensar | HoldVoiceTests |
| 9 | `prewarm()` llama a `mic.prewarm()`; no lee el llavero, no abre el transport, no arranca el micro ni pide permiso | HoldVoiceTests |
| 10 | Hold completo escribe una línea `voice timeline:` con press→ready y release→commit (log a fichero temporal, `Log.configure`) | HoldVoiceTests |

---

## 6. Prueba manual (Karen)

1. Arrancar la app: en `~/Library/Logs/CompanionNext.log` una línea
   `prewarm: key … · mic … · net …`.
2. Con Companion detrás, mantener FN y decir una frase larga con una pausa
   en medio: la island muestra el texto creciendo; la pausa **no** envía;
   al soltar viaja todo.
3. Hablar desde el mismo instante de pulsar: la primera palabra está en el
   turno (comparar con antes de 12c, que la perdía).
4. Tras soltar, la island sigue mostrando el texto en "Enviando…" y lo
   quita cuando empieza a pensar.
5. En el log, una línea `voice timeline:` por hold; anotar `press→ready`
   típico para decidir D8 (socket caliente en boot) con datos.
6. Pasar el ratón por el pebble tras el primer hold: crece sin la pista.

---

## 7. Fuera de alcance

- Socket realtime caliente en boot (D8 completo): se decide con los
  números de §3.4. Si `press→ready` típico > 800 ms, wave propia con un
  socket de vida acotada y reconexión al vuelo.
- Subtítulos del agente (`show_ai_subtitles`, `tts:caption-word`): no.
- Chips de adjuntos pendientes y sugerencia de idioma en la island: no.
- Dictado en el campo enfocado: otra wave.
- Apagar el VAD del servidor en sesiones de hold: §3.3 lo hace innecesario
  (los segmentos se acumulan).

---

## 8. Fuentes

- `~/Desktop/relay-hud-spec/01-hud-anatomy.md` §2.1 (fila Listening),
  `02-interaction.md` §2.2–2.4, `03-screens-and-states.md` §1, §2.3–2.5,
  `04-orchestration.md` (reducer, `SttPartialTranscript`).
- `AI_Research/AIResearch/specs/01-voice-session.md` (diagrama de estados,
  "Hold-to-talk timeline", "Metrics they already name"); `COMPANION-MAP.md`
  §4 D8 y §5 fila 8.
- companion: `docs/specs/wave-12b-hold-fn-island.md` §7, §9.9.

---

## 9. Desviaciones respecto a esta spec (al entregar)

| # | La spec decía | Lo que hay | Por qué |
|---|---|---|---|
| 1 | `audit.begin` en paralelo con `async let` | `earTask = Task { await self?.beginEar(locale:) }` sobre el actor, esperada en el camino de ready y en `closeRealtime` | `VoiceAudit` vive en el actor (`committed`, `enabled`); un `async let` la sacaría a un hilo hijo y `hear` la leería en carrera |
| 2 | `prewarm()` lee la clave para calentar `CachingSecretStore` | No toca el llavero | En la build de desarrollo la lectura abrió el diálogo del llavero al arrancar y bloqueó la tarea (visto con `sample`, 2026-09-06). Test 9 lo exige |
| 3 | El parcial se emite "y en Pending" | Solo con `holdOpen` (`holdArmed && listening && !muted`); en Pending el reductor conserva el último | Tras soltar el micro está cerrado: no hay hipótesis nuevas que valgan, y una tardía pintaría texto que no viaja |
| 4 | — | `eventBox` deja de ser `private` en `VoiceSession` | El pump de parciales vive en la extensión (`VoiceSessionPumps`) |
| 5 | Test "offline no arma el clásico" (`!transcriber.started`) | Ahora exige que el oído arrancado con la sesión se apague con ella (`stops >= 1`) y que el pipeline no sea clásico | El oído arranca al pulsar por diseño; lo que sigue valiendo es que muera con la sesión |
| 6 | Test 6 llama a `hold()` y comprueba | `hold()` corre en una `Task`: no vuelve hasta ready o timeout | En la app nadie espera a `hold()` (`SessionModel` lo lanza en una `Task`); el test lo imita |
| 7 | Test 10 "un hold entero" | Exige un frame y un parcial en el hold de prueba | Sin ellos `press→mic` y `press→partial` serían huecos legítimos, no fallos |
| 8 | `heldSegments` (§3.3 original) | No existe: bajo `holdArmed` los eventos del VAD se ignoran y al soltar viaja `turnText()`; cada pulsación consume el oído | Revisiones: perdía el segmento en vuelo, un `.finished` tardío era un segundo turno (también tras un tap), y uno tardío tras la pulsación siguiente se colaba en ella |
| 9 | `Task(priority: .utility)` en boot | `Task.detached` | La tarea con prioridad utility heredada por el main actor nunca corrió (§3.5b) |
| 10 | `prepareEngine()` + `engine.prepare()` | Solo `prepareEngine()` | `prepare()` sin tap lanza una excepción que mata la app (§3.5b) |
| 11 | `hold()` reinicia la línea de tiempos siempre | Solo si no hay pulsación o la anterior ya soltó | Una pulsación que rebota mientras conecta es el mismo hold; medía press→ready desde la segunda |

---

## 10. Revisiones (2026-09-06)

### 10.1 Seguridad (security-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Media | `heldSegments` sin guarda de generación: un `.finished` tardío del hold anterior, procesado tras la pulsación siguiente, se unía al hold nuevo (palabras de un turno en otro) | Test primero: `testLateWordsDoNotJoinTheNextHold` (HoldVoiceTests 12). `heldSegments` desaparece; bajo `holdArmed` el VAD se ignora y cada pulsación consume el oído (`audit.consume()`), así que lo tardío del hold anterior nunca entra en `turnText()` del siguiente |
| 2 | Baja/Media | `heldSegments` sin techo (tecla atascada) | Desaparece con el cierre 1 |
| 3 | Baja (previo) | `VoiceAudit.logTurn()` y `RealtimeRuntime` escriben el texto final del turno en el log | Fuera del diff; ticket ya abierto en ROADMAP (12b) |
| — | Verificado | El parcial no llega al log ni al `ConversationStore` (solo `projection.partial`); la línea de tiempos solo lleva ms; `prewarm()` no pide permisos, no arranca captura, no abre red; el oído que arranca al pulsar muere con la sesión; `holdLearned` es un `Bool` | — |
| N | Nota | `RealtimeRuntime.append(_:)` (PCM crudo al socket) no tiene llamadores en producción | Pendiente de un `refactor-cleaner`; anotado aquí |

### 10.2 Código (code-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | Tras soltar (o descartar) la máquina sigue en `listening + muted`, así que un `.finished` tardío pasaba `holdOpen == false` → `earSegment` → `.serverSpeechStopped` → **segundo** `commitTurnFromNative`: un turno que nadie pidió, incluso tras un tap | Test primero: `testALateSegmentAfterReleaseSendsNothing` (11) y `testALateSegmentAfterDiscardSendsNothing` (11b). Bajo `holdArmed` el VAD se ignora del todo |
| 2 | Media | Una pulsación que rebota mientras conecta reiniciaba la línea de tiempos y `press→ready` se medía desde la segunda; además una línea vacía en el log | Test primero: `testABouncedPressKeepsTheTimeline` (13). `hold()` solo reinicia si no hay pulsación o la anterior ya soltó |
| 3 | Baja | `hangUp()` concurrente con `waitForReady()` puede armar un watchdog sobre una sesión ya cerrada (no-op por su guarda) | Aceptado, previo a 12c |
| — | Verificado | Borrado del parcial en todos los caminos; doble `audit.end()` seguro; `MicCapture.prewarm` sin ventana de intercalado con `start()`; `holdLearned` se escribe solo en `.processing(.pending)`, que solo nace de `.released` | — |
