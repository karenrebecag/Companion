# Wave 12e — Dictar en el campo enfocado: la misma tecla, otro destino

**Estado: ENTREGADA (2026-09-06).** Gates verdes (238 pruebas); revisiones
cerradas test-first (§10); desviaciones en §9. Falta la prueba manual de
Karen: exige conceder Monitoreo de entrada y Accesibilidad (§6).

**Original:** Cubierta por la aprobación de Karen del
2026-09-06 ("vamos. aplica y loopea para continuar con toda la spec de
cambios que sean visibles") y por su pedido original de la Wave 12
("asignar la tecla fn de mi mac para poner en on mi microfono es mucho
mejor", con Wispr Flow como ejemplo). Tras 12a-12d, es la pieza visible
que queda de la spec de producto: `relay-hud-spec/05` §4 ("Dictation:
same hold, **no** `run_turn` — paste into the focused field"), `02` §4,
`03` §5, y el corpus spec 11. Cierra la fila 10 del mapa (`COMPANION-MAP.md`
§5, "Dictado en campo enfocado", 0 %). Depende de 12b (hold) y 12c
(parciales, `turnText()` al soltar).

Sin commit: Karen commitea.

---

## 1. El defecto, medido

**A. Mantener FN siempre habla con Companion.** Soltar la tecla envía
`turnText()` a la conversación (`VoiceSession.commitTurnFromNative` →
`realtime.commitWithText`). Con el cursor en un mensaje de Slack, una
celda de Numbers o el campo de Safari, lo que dices no aparece ahí: se lo
lleva Companion. La spec de producto lo pone al revés: el mismo hold, y el
texto cae en el campo enfocado sin `run_turn` (`05` §4).

**B. No hay inyector.** Cero `AXSetValue`, cero `kAXFocusedUIElement`,
cero `CGEvent` de teclado en `Sources/` (grep 2026-09-06). La lectura por
Accesibilidad existe (`OpenDocumentsSensor`, 10a) y el permiso también
(`AccessibilityPermission`, fila en Ajustes › App › CONTEXTO); nadie
escribe.

**C. No hay modo.** `VoiceSettings` no sabe de `voice_mode`
(`relay-hud-spec/05` §5: "Agent vs dictation vs dynamic").

---

## 2. Lo que dice la spec de producto, el corpus y la industria

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| `relay-hud-spec/05` §4 | Dictado: el mismo hold, sin `run_turn`, pegar en el campo enfocado | Un destino más al soltar; el reductor no gana un kind |
| `relay-hud-spec/03` §5 | "Not a session kind": la island pinta parciales, final, y vuelve al pebble; sin card de respuesta, sin TTS | `SessionProjection.dictation` (nombre de la app) + línea `.dictating(app)` y `.dictated(app)`; luego Completed → Idle |
| `relay-hud-spec/02` §4 | keyup ForceEndpoint → vocabulario → pulido opcional → `text-injector` (AX / teclas / portapapeles) → historial; vacío → Idle sin pegar | AX primero, portapapeles + ⌘V después; vacío = `heardNothing` (12b). Sin vocabulario ni pulido en v1 (§7) |
| `relay-hud-spec/05` §5 | `voice_mode`: agent / dictation / dynamic | `VoiceSettings.mode: VoiceMode { agent, dictation, automatic }`, por defecto `automatic` |
| Corpus spec 11 (Observed) | Misma tecla que el agente; modo desde ajustes, no un segundo atajo; no inyectar en `AXSecureTextField`; no inyectar en otro Space; nunca loguear el texto pegado | Las cuatro, como contratos con test |
| Corpus spec 11, `dynamic` (Inferred, abierto) | Elegir por la app enfocada o un modificador; "still unproven" | Nuestra regla, explícita: **automático = si el elemento enfocado de la app que está delante es un campo de texto editable y no seguro, dicta; si no, habla con Companion**. Con Companion delante, siempre agente |
| Corpus spec 11, injector | 1) `AXSetValue` en el campo enfocado; 2) `CGEvent`; 3) portapapeles + ⌘V | 1) `kAXSelectedTextAttribute = texto` sobre el elemento enfocado (inserta en el cursor, respeta la selección); 2) portapapeles + ⌘V por `CGEvent` (restaurando el portapapeles). Sin teclas sintéticas letra a letra: pierden acentos y lentas |
| Wispr Flow / Superwhisper | Mantener, hablar, soltar: el texto aparece donde estaba el cursor; sin ventana | Igual, con la island mostrando "Dictando en Slack" y el parcial (12c) |
| macOS | Escribir por AX y postear ⌘V exigen Accesibilidad (ya pedida en 10a); `AXSecureTextField` es el rol de las contraseñas | Sin confianza AX: automático nunca dicta; en modo dictado, aviso con enlace |

---

## 3. Decisiones

### 3.1 El destino se decide al pulsar, no al soltar

`DictationRouter.destination(mode:, field:, trusted:) -> Destination`
(Core, pura):

| mode | field (sonda AX) | trusted | destino |
|---|---|---|---|
| `.agent` | — | — | `.agent` |
| `.dictation` | editable, no seguro | sí | `.dictation(field)` |
| `.dictation` | ninguno / seguro | sí | `.agent` (`.noField`: solo al log, sin aviso en pantalla) |
| `.dictation` | — | no | `.agent` con aviso `.needsAccessibility` |
| `.automatic` | editable, no seguro | sí | `.dictation(field)` |
| `.automatic` | ninguno / seguro / sin confianza | — | `.agent` |

Se decide en `VoiceSession.hold()` con `FocusedFieldProbing.focusedField()`
(Services, AX): la app que está delante **no es Companion**
(`NSWorkspace.frontmostApplication.bundleIdentifier != nuestro`), su
`kAXFocusedUIElementAttribute` tiene rol `AXTextField` / `AXTextArea` /
`AXComboBox` (o `kAXEditableAttribute`), y no es `AXSecureTextField`. La
sonda devuelve `FocusedField { app, pid, role, secure }` o `nil`. Con el
destino `.dictation`, la sesión emite `SessionEvent.dictating(app:)`.

### 3.2 Soltar pega, no envía

En `commitTurnFromNative`, con `dictationTarget != nil`:

1. `text = audit.turnText()`; vacío → `heardNothing` (como hoy).
2. `injector.inject(text, into: field)` → `.injected(chars)` o
   `.failed(reason)`.
3. `.injected` → `SessionEvent.dictated(app:)`; el modelo no ve nada, el
   historial no gana nada; `audit.consume()` como siempre.
4. Cualquier `.failed` manda el texto al agente (`commitWithText`): nada de
   lo que dijiste se pierde. Solo `.needsAccessibility` (también el
   decidido al pulsar en modo Dictar) emite
   `SessionEvent.dictationFailed(.needsAccessibility)`, un aviso sin
   transición; `.fieldGone` (cambiaste de app durante el hold) y
   `.refused` solo se loguean (§9.2). Nunca se pega en una app distinta de
   la sondeada al pulsar: la inyección comprueba el `pid` y el rol otra
   vez.

La máquina de voz no cambia: `holdReleased` sigue siendo
`closeMic + commitWithText`; el destino lo decide la sesión.

### 3.3 El inyector (Services, `AXTextInjector`)

- **AX:** `AXUIElementCreateApplication(pid)` → focused element → confirmar
  rol y no seguro → `AXUIElementSetAttributeValue(kAXSelectedTextAttribute,
  text)`. Inserta en el cursor y reemplaza la selección, como escribir.
- **Portapapeles + ⌘V:** si AX devuelve error (Chromium y Electron mienten
  a veces): guardar el contenido de texto del portapapeles, escribir el
  texto, postear ⌘V (`CGEvent` keyDown/keyUp con `.maskCommand`, `keyCode
  9`), restaurar el portapapeles tras 0,3 s. `CGEvent.post` exige
  Accesibilidad: la sonda ya lo comprobó.
- Nunca teclas letra a letra. Nunca en `AXSecureTextField`. Nunca si el
  `pid` enfocado ahora no es el sondeado. Nunca se loguea el texto: el log
  dice `dictation: pasted N chars into <app> via ax|paste` o el fallo.

### 3.4 El reductor y la island

- `SessionProjection.dictation: String?` (la app). `SessionEvent.dictating(app:)`
  lo escribe en Listening; `.dictated(app:)` pasa a `.processing(.completed)`
  con `notice = .dictated(app)` y su timer; `.dictationFailed(reason)` →
  `notice` `.permission(.accessibilityDenied)` o `.failure`, y
  `restingKind()`. `begin()` lo borra. `.stop` lo borra.
- `IslandState.Line`: `.dictating(app)` (Listening, con medidor y parcial),
  `.dictated(app)` (Completed). Copy: "Dictando en Slack", "Pegado en
  Slack". `TurnFailure.accessibilityDenied` con copy y enlace
  (`PermissionSettingsLink.accessibility`).
- Pending muestra "Pegando…" (`.pending` con `dictation != nil`).

### 3.5 Ajustes

Bloque HABLAR (12b): fila "Al mantener FN" con tres opciones: **Automático**
(por defecto: "si el cursor está en un campo de otra app, dicta; si no,
habla con Companion"), **Hablar con Companion**, **Dictar**. Si el modo no es
Agente y Accesibilidad no está concedida, la fila de permiso de
Accesibilidad (la de CONTEXTO) aparece también aquí con su botón y enlace.
`VoiceSettings.mode` persiste con el resto (`VoiceProfile.settings`).

### 3.6 Manos libres y clásico

- La manos libres (`Cmd+Opt+Space`) sigue siendo agente: no hay hold, no
  hay campo que sondear.
- Sin clave de OpenAI (pipeline clásico) el hold sigue siendo agente (§7).

### 3.7 API

Core:

- `VoiceMode { agent, dictation, automatic }`; `VoiceSettings.mode`.
- `Dictation.swift`: `FocusedField`, `Destination`, `DictationNotice`,
  `DictationRouter`, puertos `FocusedFieldProbing` y `TextInjecting`,
  `InjectionResult`.
- `SessionEvent.dictating(app:)`, `.dictated(app:)`, `.dictationFailed(DictationFailure)`;
  `SessionProjection.dictation`; `SessionCard.dictated(app)`.
- `TurnFailure.accessibilityDenied`.
- `IslandState.Line.dictating(String)`, `.dictated(String)`.

Services:

- `AXTextInjector: FocusedFieldProbing, TextInjecting`.
- `VoiceSession(probe:, injector:)`; `dictationTarget`; la rama en
  `commitTurnFromNative`.

UI: `HoldSettingsBlock` (modo), `IslandCopy`, `VoiceCopy.failure` /
`settingsLink`, strings en/es.

App: `CompanionMain` cablea `AXTextInjector(selfBundleID:)`.

### 3.8 Archivos

| Capa | Archivo | Cambio |
|---|---|---|
| Core | `Config.swift` | `VoiceMode`, `VoiceSettings.mode` |
| Core | `Dictation.swift` | nuevo |
| Core | `SessionTypes.swift`, `SessionMachine.swift`, `IslandState.swift`, `TurnTypes.swift` | eventos, campo, líneas, fallo |
| Services | `AXTextInjector.swift` | nuevo |
| Services | `VoiceSession.swift` | sonda al pulsar, rama al soltar |
| UI | `HoldSettings.swift`, `IslandView.swift`, `VoiceCopy.swift`, `en/es.lproj` | modo, líneas, copy |
| App | `CompanionMain.swift` | cableado |
| Tests | `DictationTests` (nuevo), `SessionMachineTests`, `HoldKeyTests`, `HoldVoiceTests`, `VoiceSessionTests` (fakes) | §5 |

---

## 4. Restricciones

- El texto dictado **nunca** va al log ni al `ConversationStore` ni al
  modelo (contrato con test: `hud-gates.json` gana la puerta
  `dictation-never-logged`).
- Nunca en `AXSecureTextField`; nunca en una app distinta de la sondeada;
  nunca sin Accesibilidad; nunca con Companion delante.
- Sin `Info.plist` nuevo: Accesibilidad no lleva usage description.
- Core puro; sin `try?` en Core/Services; retícula; copy en catálogo.
- El reductor sigue siendo el único escritor de la proyección.

---

## 5. TDD (RED → GREEN)

| # | Test | Archivo |
|---|---|---|
| 1 | `DictationRouter`: la tabla de §3.1 completa | DictationTests |
| 2 | `.dictating(app)` en Listening escribe `dictation`; `.dictated` → Completed + `notice`; `.dictationFailed(.needsAccessibility)` → aviso de permiso; `begin()` y `.stop` lo borran | SessionMachineTests |
| 3 | Island: `.dictating` con medidor y parcial; Pending con `dictation` es "Pegando…"; `.dictated` en Completed; `.accessibilityDenied` con enlace | HoldKeyTests |
| 4 | Hold con sonda que devuelve un campo (modo automático): al soltar el inyector recibe el texto, el transport **no** recibe `conversation.item.create`, `events` lleva `.dictating` y `.dictated` | HoldVoiceTests |
| 5 | Hold sin campo (automático): agente como hoy | HoldVoiceTests |
| 6 | Modo dictado sin confianza AX: no se pega, `dictationFailed(.needsAccessibility)`, el texto cae al agente | HoldVoiceTests |
| 7 | El campo desapareció al soltar (`.fieldGone`): no se pega en otra app; cae al agente | HoldVoiceTests |
| 8 | Vacío en dictado: `heardNothing`, nada pegado | HoldVoiceTests |
| 9 | El texto dictado no aparece en el log (`Log.configure` a fichero temporal) ni en `events` salvo como parcial | HoldVoiceTests |
| 10 | `VoiceSettings.mode` persiste y por defecto es `.automatic` | ConfigTests |
| 11 | Puerta `dictation-never-logged` en `hud-gates.json` cita el test 9 | hudGatesTests |

---

## 6. Prueba manual (Karen)

1. Ajustes › App › HABLAR: "Al mantener FN" en Automático (por defecto).
   Accesibilidad concedida (fila de CONTEXTO o la de aquí).
2. Cursor en un mensaje de Slack o Notas; mantener FN, decir "hola qué
   tal", soltar: el texto aparece en el campo; la island dijo "Dictando en
   Slack" con el parcial y luego "Pegado en Slack".
3. Cursor en ningún campo (Finder): mantener FN, "abre Safari": Companion
   lo abre (agente).
4. Cursor en un campo de contraseña de Safari: mantener FN: agente, no
   dictado.
5. Cambiar a "Dictar" sin Accesibilidad: al soltar, aviso con enlace; el
   texto llega a Companion.
6. `~/Library/Logs/CompanionNext.log`: `dictation: pasted N chars into
   Slack via ax`; nunca el texto.

---

## 7. Fuera de alcance

- Vocabulario / reemplazos y pulido con modelo (spec 11 L2/L0): otra wave;
  primero medir cuánto corrige el oído nativo.
- Historial de dictado (`dictation-history.json`): no (privacidad; el
  texto ya está donde el usuario lo puso).
- Popup de resultado: no; la island ya lo dice.
- Dictado en el pipeline clásico (sin clave): otra wave si hace falta.
- Dictado en el campo de Companion (`chat_input_dictation_*`): el hilo ya
  lo permite con la manos libres.
- Teclas sintéticas letra a letra.

---

## 8. Fuentes

- `~/Desktop/relay-hud-spec/02-interaction.md` §4, `03-screens-and-states.md`
  §4.3, §5, `05-replication-checklist.md` §4, §5.
- `AI_Research/AIResearch/specs/11-dictation.md`; `COMPANION-MAP.md` §5 fila 10.
- companion: `docs/specs/wave-12b-hold-fn-island.md`,
  `wave-12c-parciales-metricas-precalentar.md` §3.3, `ContextSensors.swift`
  (lectura AX, 10a), `AccessibilityPermission.swift`.

---

## 9. Desviaciones respecto a §3

| # | Spec | Entregado | Por qué |
|---|---|---|---|
| 1 | La sonda corre dentro de `hold()`, antes de abrir el micro | Corre en su propia tarea (`dictationTask`); el micro abre sin esperarla y el soltar la espera | Revisión de código: `AXUIElementCopyAttributeValue` es un viaje a la app de delante; una colgada bloqueaba el actor de voz entero (frames, watchdog, island). Además cada llamada AX lleva `AXUIElementSetMessagingTimeout` de 0,25 s |
| 2 | `.noField` y `.fieldGone` avisan en pantalla | Solo `.needsAccessibility` avisa; los otros dos van al log | v1: `.noField` es lo normal en modo Automático (no es un fallo) y `.fieldGone` ya se resuelve solo mandando el texto al agente. `DictationNotice.fieldGone` se borró: el router nunca lo producía |
| 3 | Restaurar el portapapeles tras 300 ms | Solo si nadie más lo tocó (`changeCount`) | Revisión de seguridad: restaurar a ciegas se comía lo que la usuaria hubiera copiado en esos 300 ms |
| 4 | `AXTextInjector(selfBundleID:)` | Inicializador que puede fallar: sin identificador propio no se construye | Revisión de seguridad: con `""` la comparación `app.bundleIdentifier != ""` era cierta y Companion dejaba de excluirse a sí misma |
| 5 | — | La island dice "FN está apagada. Clic para permitirla" cuando falta Monitoreo de entrada | En vivo: el nudge enseñaba "Mantén FN para hablar" con la tecla muerta; Karen tuvo que abrir la voz con un clic |
| 6 | — | El oído deja de escribir las frases en el log (`ear: hearing/segment (N chars)`) | En vivo apareció `ear: segment «Hola, ¿estás ahí?»`: la deuda abierta en 12b rompía la puerta `dictation-never-logged` |
| 7 | — | Una pulsación que rebota conserva el destino ya decidido | Revisión de código: repetía la llamada AX y el anuncio |

---

## 10. Revisiones (2026-09-06)

### 10.1 Seguridad (security-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | Ningún test tocaba `AXTextInjector`: todas las pruebas corrían contra los dobles | Test primero: `AXTextInjectorTests` (nuevo) sobre lo comprobable sin otra app delante: ida y vuelta del portapapeles con todos los tipos, colisión, vacío, identidad propia obligatoria |
| 2 | Media | Restaurar el portapapeles sin mirar `changeCount` borraba lo que alguien copiara en esos 300 ms | Test primero: `testAConcurrentCopyWins`. `restore(_:to:ifUnchangedFrom:)` y una línea de log cuando no restaura |
| 3 | Media | `selfBundleID` vacío hacía que Companion dejara de excluirse | Test primero: `testTheOwnBundleIDIsRequired`; `init?` |
| 4 | Media | El defecto `.automatic` puede mandar una frase a una persona (Slack) en vez de a Companion | Se mantiene: es lo que pide la spec de producto (`voice_mode: dynamic`) y la island dice "Dictando en Slack" con el parcial durante todo el hold. Anotado para Karen; cambiarlo es un ajuste, no código |
| 5 | Baja | Sin tope de longitud en lo que se inyecta | Aceptado en v1: el hold lo acota (la tecla se suelta). Anotado |
| 6 | Baja | `DictationNotice.fieldGone` era código muerto | Borrado (§9.2) |
| — | Verificado | Lo dictado no llega al log, ni al `ConversationStore`, ni al socket, ni al flujo salvo como parcial; el VAD del servidor no puede saltarse el destino; el campo seguro se comprueba al sondear y al inyectar; el `pid` se revalida; `AXIsProcessTrusted` nunca pide permiso desde el hold; una sola pulsación sintética de Cmd+V, nunca letra a letra | — |

### 10.2 Código (code-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | La sonda AX corría dentro del actor de voz antes de abrir el micro: una app colgada congelaba la sesión entera | Test primero: `testTheProbeNeverDelaysTheMic` (la sonda detenida y el micro abre igual). `dictationTask` + `AXUIElementSetMessagingTimeout` |
| 2 | Media | `.noField` y `.fieldGone` nunca llegaban a la usuaria pese a la tabla de §3.1 | La spec se alinea con lo entregado (§9.2) y el caso muerto se borra |
| 3 | Baja | Un rebote de la pulsación volvía a sondear y a anunciar | Test primero: `testABouncedPressKeepsTheTarget` |
| 4 | Baja | `Log` es un sumidero global compartido entre tests concurrentes | Aceptado hoy (los tests que lo configuran son rápidos); anotado para cuando haya más |
| — | Verificado | `DictationRouter` puro y cubierto 1:1; las reglas del reductor; sin carrera entre `.dictating` y la transición a Listening; el destino se consume una vez por hold; copy en catálogo en los dos idiomas; sin `try?`; ningún archivo pasa de 800 líneas | — |

---

## 11. Lo que enseñó la prueba en vivo (2026-09-06)

- **FN nunca se oyó.** La base de TCC no tenía fila de `kTCCServiceListenEvent`
  para `com.karen.companion.next`: el permiso no estaba denegado, es que
  nunca se pidió. `CGPreflightListenEventAccess()` devuelve falso y el tap
  no se instala. La app reintenta al volver al frente
  (`applicationDidBecomeActive`), así que conceder y hacer clic en
  Companion basta; no hace falta relanzar.
- **Accesibilidad estaba denegada** (`kTCCServiceAccessibility` con valor 0,
  creada al leer el contexto): por eso Companion sabe qué app está delante
  (`NSWorkspace`, sin permiso) pero no ve títulos ni documentos. Con la
  fila ya creada, la app aparece en Ajustes del Sistema y basta con
  encender el interruptor: el diálogo no vuelve a salir.
- **La island mentía.** Enseñaba "Mantén FN para hablar" con la tecla
  muerta. Ahora dice que FN está apagada y el clic abre la ventana.
