# Puente de QA: `companion_ask` y control total de Companion desde Claude Code

**Estado: BORRADOR** (Fable, 2026-10-15; la firma es de Karen).
**Decisiones de Karen 2026-10-15:** "vamos con la recomendacion, las acciones criticas exigen
touch id, as_user_words, sin hojas de aprobacion solo touch id en critic actions". Es decir:
Q1 modo QA volátil (muere con el proceso); Q2 la banda crítica exige Touch ID siempre, también
en QA, y Touch ID entra en el alcance de esta spec porque no está implementado; Q3 el turno del
agente lleva `as_user_words`; Q4 y regla general: en modo QA **no hay hojas de aprobación**: lo
no crítico actúa directo y lo crítico pide Touch ID. Con eso `companion_resolve_approval`
desaparece. La hoja de sesión del puente (`bridge_session`) se queda (ver Q1 de §9).

Base: `docs/specs/self-qa-inspeccion.md` (APROBADO), `docs/research/self-qa-puente.md` (R1-R7),
`docs/research/self-qa-inspeccion-datos.md` (D1-D7), ADR 009, `docs/specs/wave-17-puente-mcp.md`
§3, `docs/specs/wave-20d-modos-autorizacion.md` (bandas), `docs/specs/touch-id-aprobaciones-criticas.md`
(APROBADO; aquí "spec TID": su puerto, adaptador, dobles y plan de tests se reutilizan tal cual).
Formato: `self-qa-inspeccion.md`. Líneas citadas contra `origin/main` `52419444` (companion-next)
y `e678b1a` (companion-mcp).

Esta spec **relaja a propósito**, solo dentro del modo QA, reglas firmadas: R2 (texto del
agente como palabras de la usuaria, por `as_user_words`), R3 y R8 (escrituras de ajustes por
tool), D7 de inspección-datos (texto de vuelta) y, la mayor, la hoja por acción: en QA la hoja
desaparece y la prueba de dueña (Touch ID) la sustituye en lo crítico. Lo que no se relaja: R1
para la hoja de **sesión** (`bridge_session` la contesta solo Karen), R5 (allowlist con test),
R6 (logs sin argumentos ni output), R7 (nace apagado; una hoja de sesión por conexión), y la
regla 20c/20d "el modelo nunca contesta su propia pregunta de permiso": en QA no hay pregunta
que contestar, hay un dedo que poner.

## 1. Objetivo

Que Claude Code, conectado por el shim `companion-mcp`, corra un QA de uso completo de
Companion sin tomar el mouse de Karen:

1. mandarle un turno escrito, esperar a que termine y leer un resultado verificable (fases,
   tools que llamó el modelo con sus resultados, tarjetas, documentos, errores y texto de la
   respuesta): `companion_ask` + `companion_wait_turn`;
2. que ese turno, y las manos que el agente mueva directo por el puente, no se detengan en
   hojas: lo no crítico actúa; lo crítico pide Touch ID a Karen y sigue;
3. empezar en limpio: `companion_new_conversation`;
4. ver lo que Companion pinta sin Accesibilidad: `companion_screen` (tiene puerto, no tool),
   `companion_controls`, `companion_capture`;
5. cambiar ajustes estructurados: `companion_set_setting`;
6. leer la historia de turnos aunque el log rote: `companion_turns`;
7. tener las manos (`look`/`click`/`type_text`/`see`) listadas siempre que estén instaladas,
   con el motivo por llamada cuando no están listas (hoy desaparecen de la sesión, §2.1);
8. como prerrequisito: el puerto de prueba de dueña (`OwnerVerifying`) y su adaptador
   LocalAuthentication, para que nunca exista un estado "sin hoja y sin Touch ID".

### Fuera de alcance

- Varias conexiones a la vez (sigue una; `busy`).
- Eventos push del puente al shim: una línea en vuelo por conexión
  (`BridgeSession.swift:123-132`) y MCP no tiene un canal que Claude Code consuma como evento.
  La espera con continuación de D4 es el sustituto; v2 del protocolo queda anotada en §8.
- Pulsar controles de Companion por AX (ADR 009: se inspecciona, no se maneja).
- El árbol de Accesibilidad de la ventana (D4 de `self-qa-puente`, brief propio).
- El lado "hoja + Touch ID" de la spec TID (clic de Karen en Permitir sobre lo crítico,
  reductor `.verifyOwner`, isla "Verificar"): sigue su propio plan de PRs. Esta spec solo toma
  de ella el puerto, el adaptador y los dobles (su PR-3), y define el camino **sin hoja** de QA.
- Las hojas de jobs de voz y del especialista (`VoiceSession+Approvals`, `JobRunner`) siguen
  como hoy también en QA; la voz entra en §5.7 (PR-7) y ahí se cablea el mismo gate.
- Inyectar audio en el pipeline de voz: diseñado en §5.7, última entrega.

## 2. Estado actual (verificado)

### 2.1 Por qué no aparecieron las manos en la sesión

- `hello` publica `tools.specs(language())` filtrado por la allowlist **en el instante del
  hello** (`BridgeSession.swift:279-285`).
- `ParentToolRunner.specs` solo agrega manos y vista si `readyHands != nil`
  (`ParentToolRunner.swift:82-92`); `readyHands` exige `hands.trusted()` **y**
  `!hands.selfInFront()` (`:67-70`).
- `selfInFront` es `FrontmostAppSensor.ownInFront`: true mientras Companion es la app activa
  (`ContextSensors.swift:265-276`).
- El shim hace **un** `hello` al arrancar (`index.ts:24` → `attachBridge`, `server.ts:108-118`)
  y la lista registrada en MCP solo cambia cuando `client.tools` cambia, y eso solo pasa en un
  `hello` nuevo (`client.ts:357-358`; `server.ts:139-163`), es decir cuando el socket cae
  (`client.ts:293-294`): idle de 10 min (`BridgeSession.swift:143-152`, `BridgePolicy.swift:105`),
  "Detener manos" o reinicio.
- Conclusión: si al lanzar Claude Code Companion estaba al frente (Karen en su ventana o en
  Ajustes, lo normal al preparar un QA) o Accesibilidad no estaba confiada para ese binario,
  las nueve tools de manos y vista **no entraron en el hello y no vuelven en toda la sesión**.
  `unavailability(for:)` ya sabe decir `self_in_front` / `needs_accessibility` por llamada
  (`ParentToolRunner.swift:105-113`, 20b D4), pero no se alcanza porque el shim no tiene la
  tool registrada. La wave 17 lo diseñó pensando en el permiso ("sin Accesibilidad no hay
  manos", `wave-17-puente-mcp.md:56`), no en el foco; con el foco la condición cambia cada
  segundo y la lista se congela.
- Igual para el navegador: `BrowserToolRunner.specs` (`BrowserToolRunner.swift:77`) depende de
  la extensión conectada en ese instante (verificar al implementar PR-3).

### 2.2 El camino de una llamada y la aprobación

- Allowlist → `handles`/`unavailability` → validación de argumentos → `policy.admit`
  (`BridgeSession+Calls.swift:56-85`).
- Primera llamada de una conexión: hoja de sesión `bridge_session`, nunca recordada
  (`BridgeSession+Calls.swift:87-158`; `BridgePolicy.swift:32`, `165-180`, `198-207`).
- Hoja por llamada con `said: ""` (`BridgeSession+Calls.swift:160-178`), por
  `ParentToolGuard.verdict` → `answer` (`ParentToolGuard.swift:57-126`).
- En el chat, la hoja la pide `ChatViewModel.gate` (`ChatViewModel+Turn.swift:250-280`):
  `tools.approval(for:said:)` → `bound` → `actsWithoutSheet` → `remembered` →
  `approvals.request`. Las dos rutas (puente y chat) terminan en `Approvals.request`
  (`Approvals.swift:32-62`), auto-deny a 60 s (`:92-96`).
- La banda de una acción la decide `ActionBand.classify(toolName:arguments:facts:)`
  (`ActionBand.swift:63`), con hechos (`hostSaid`, `destructiveTarget`, `inTerminal`...); la
  spec TID añade `ActionBand.atSheet(_:)` con hechos "sin verificar" (todo sube de banda).

### 2.3 Presupuestos, idle, pausa

- 30 escrituras y 60 lecturas por minuto, por proceso (`BridgePolicy.swift:93-100`, `198-230`).
- 3 negativas en 10 min → `cooling_down`; 20 hojas en 10 min → sesión apagada
  (`BridgePolicy.swift:113-124`, `311-329`).
- Idle 10 min, chequeo cada 15 s; una llamada esperando no es idle (`inFlight`,
  `BridgeSession.swift:50-56`, `143-170`, `195-196`). `idleTimeout` se fija en `init` (`:57-70`).
- **Pausa**: `BridgeHost` pausa en todo `SessionKind.isUsersTurn` (`BridgeHost.swift:86-95`);
  `.typedSubmitted` pone `kind = .processing(.thinking)` (`SessionMachine.swift:105-109`), que
  es turno de la usuaria (`SessionTypes.swift:18-23`). Un turno escrito disparado por el puente
  **pausaría al propio puente** y toda llamada siguiente recibiría `paused` (D2 lo resuelve).

### 2.4 Privacidad: por qué el texto vuelve como longitudes

- D1-D7 de `self-qa-inspeccion-datos.md:9-25`: metadatos, oráculo de igualdad, rasgos
  derivados dentro del proceso; D7 "sin modo de contenido completo por ahora, se reabre si
  aparece una prueba cuyo oráculo no se pueda expresar como igualdad, rasgo derivado o
  metadato". `ThreadMessageInput` no es `Encodable` y se imprime como longitud
  (`SelfInspection.swift:116-144`). Salidas de lista cerrada (`SelfInspection+Projection.swift`).
- Razón (ADR 009, `DECISIONS.md:464-492`): el texto de la usuaria saldría a un tercero sin
  consentimiento propio. Esta spec reabre D7 con el disparador que la propia decisión fija.

### 2.5 El turno escrito hoy

- `ChatViewModel.send()` → `dispatch` → `startTurn` (`ChatViewModel.swift:227-262`;
  `ChatViewModel+Turn.swift:9-44`). `said = text` salvo origen `.choice` (`:16`).
  `newConversation()` existe (`ChatViewModel.swift:264-277`).
- El turno ya produce lo que el resultado necesita, pero lo tira: `streamRound` devuelve
  `calls` (`:146-180`); `act` ejecuta y guarda cada outcome como `Recall(role: .tool)`
  (`:186-245`); tarjetas a `messages` con `card`; recibos a `session.send(.receipt)`; fin en
  `endTurn()` (`:131-135`); fallos en `errorText` + mensaje `isFailure` (`:116-128`).
- `MessageOrigin` es `typed | choice` (`ChatMessage.swift`); el puente lo espeja en
  `ThreadMessageOrigin` (`SelfInspection.swift:110-112`).

### 2.6 Lo que falta en el puente para QA

- `SelfInspecting.screen()` existe (`SelfInspection.swift:92`; `SelfInspectionSource.swift:100`)
  pero `CompanionTool` no tiene caso `screen` (`SelfInspection.swift:9-16`).
- Log principal: 1 MB con una generación `.1` (`Log.swift:14`, `157-171`); `companion_log`
  lee solo el actual (`:43-49`). Nada registra qué tools usó un turno del chat
  (`Log.bridge` es del puente, `BridgeSession+Calls.swift:203-205`).
- `BridgeCallResult` es `ok/output/target/tool`, `output` ≤ 24 000 bytes
  (`BridgeProtocol.swift:129-153`); un resultado estructurado viaja como JSON en `output`
  (precedente `SelfInspectionRunner.encoded`, `:147-158`).
- Shim: tool nueva = acción (130 s, `client.ts:55`, `tool-kinds.ts:49-51`); lecturas 30 s;
  una llamada en vuelo (`client.ts:186-236`); cancelación por `signal`.

### 2.7 Touch ID

- `grep LAContext|deviceOwnerAuthentication Sources` vacío: la spec TID está aprobada y no
  implementada. Define `OwnerVerifying` / `OwnerCheck` (Core), `LocalAuthOwnerCheck`
  (Services), `FakeOwnerCheck` (soporte) y el mapeo `LAError.Code → OwnerCheck` (spec TID §3).
  Esta spec los toma sin cambiar una firma.

## 3. Decisiones

Las D1-D11 siguen la numeración de la versión anterior; D3, D5 y D10 cambian por Karen.

- **D1 Alcance "QA" explícito y volátil (firmado).** Segundo interruptor en Ajustes ›
  Privacidad, bajo "Prestar las manos": *"Modo QA: el agente escribe en la conversación, lee
  las respuestas y actúa sin hojas; lo crítico pide Touch ID"*. Nace apagado, vive en memoria
  (muere al cerrar Companion), exige "Prestar las manos" y exige que el puerto de dueña esté
  disponible (`OwnerVerifying.canVerify()`; sin Touch ID ni contraseña el interruptor no
  enciende y lo dice). Al cambiar, el puente cierra la sesión viva (`BridgeSession.stop()`)
  para que el shim rehaga el `hello`. La hoja de sesión dice el alcance: "quiere usar tu Mac y
  conducir la conversación (modo QA)".
- **D2 El turno del puente no pausa al puente.** Turno con origen `.agent`; `BridgeHost` no
  pausa mientras `projection.agentTurn` es true. Un hold o un envío de Karen siguen pausando y
  cortan el turno del agente como cualquier `abandonTurn`.
- **D3 `as_user_words` (firmado).** El texto de `companion_ask` entra con `said = text`, igual
  que si Karen lo hubiera tecleado (`ChatViewModel+Turn.swift:16`). Efecto: las aperturas y
  acciones "dichas" actúan sin confirmar (host de `open_url` nombrado → `hostSaid`;
  `type_text` del texto dicho → `HandsGate` lo deja pasar; una familia destructiva que ella
  nombró baja de banda como con sus palabras). Lo que no cambia: lo que la clasificación deja
  en **crítico** con palabras y todo (terminal, borrar sin nombrarlo, `run_shell`,
  `create_document`/`sheet_write` sobre existente...) sigue pidiendo Touch ID. El flag es
  entrada de la tool, `true` por defecto en QA; `false` reproduce el turno sin palabras (D3 de
  la versión anterior) para probar las hojas que Karen vería sin decir nada.
- **D4 Esperar sin sondeo**: continuación del lado de Companion (`TurnWaiter`, patrón
  `Approvals`), despertada por el fin del turno, por una prueba de dueña pendiente o por el
  tope de espera. Como la conexión atiende una línea a la vez, la espera **devuelve en cuanto
  hay Touch ID pendiente** (para que el agente le diga a Karen que ponga el dedo) y nunca pasa
  de 100 s (bajo los 130 s del shim).
- **D5 En modo QA no hay hojas (firmado).** Un único `QAGate` decide por cada acción con hoja
  pendiente de pedir, en las dos rutas (chat: `ChatViewModel.gate`; puente:
  `ParentToolGuard.verdict`), antes de `approvals.request`:
  - banda `.act` o `.confirm` (`ActionBand.classify` con los hechos reales del gate y `said`)
    → actúa, sin hoja, con tarjeta/recibo como en 20d (`onAct`, `UndoReceipt`);
  - banda `.critical` → `OwnerVerifying.verify(reason:)` (Touch ID o contraseña del sistema);
    `confirmed` → `granted` y actúa; `refused` → la acción se niega (`owner_refused`) y cuenta
    como negativa de Karen para el cool-down; `unavailable` → se niega (`owner_unavailable`),
    no cuenta, y el modo QA se apaga solo (ya no cumple D1).
  - **Nunca `bridge_session`**: la hoja de sesión se mantiene con clic de Karen (R1, R7).
  - Fail-closed: si el `QAGate` no tiene puerto, lo crítico se niega; nunca actúa.
  - `companion_resolve_approval` desaparece.
- **D6 Texto en el alcance QA, cerrado por tipo.** Con QA salen: texto de la respuesta,
  `output` de cada tool (capado y enmarcado como datos), `arguments`, tarjetas como JSON, rutas
  de archivos producidos, y `companion_thread` acepta `include_text`. Sin QA, el mismo JSON con
  `text` ausente y `length` presente. Nunca: claves, log de transcripciones, campos seguros,
  memoria.
- **D7 Las manos se listan por instalación.** El puente publica `handsSpecs` cuando
  `installedHands != nil`; cada llamada responde `self_in_front` / `needs_accessibility` /
  `screen_recording_required` como ya hace `unavailability`. Chat y voz siguen con
  `readyHands`. `companion_status` gana `refresh: true` (bye + hello).
- **D8 Idle en QA**: 60 min.
- **D9 Registro de turnos aparte del log**: anillo de 50 `TurnRecord` en memoria + JSONL de
  metadatos `~/Library/Logs/<identidad>/turns.jsonl`, rotado por conteo (500), 0600.
- **D10 Captura propia sin hoja (firmado Q4)**: `NSView.cacheDisplay` en proceso, PNG en
  `~/Library/Application Support/Companion/qa/captures/` (0700), devuelta como ruta. Incluye la
  isla aunque muestre la hoja de sesión (es copy de la app; el `summary` ya pasa por
  `plainPreview`). Nunca va al modelo de visión de la nube. Solo en QA.
- **D11 Ajustes por tool, lista cerrada**: `language`, `appearance`, `voice_mode`, `decision`,
  `interface_sounds`, `thinking_sound`. Nunca `lend_hands`, el modo QA, claves, grants ni
  destinos de confianza. Solo en QA.
- **D12 Prueba de dueña: puerto y adaptador de la spec TID, sin cambios de firma.**
  `OwnerVerifying.verify(reason:) async -> OwnerCheck` (`confirmed | refused | unavailable`);
  `LocalAuthOwnerCheck` crea un `LAContext` por llamada, `canEvaluatePolicy` falso →
  `unavailable`, `evaluatePolicy(.deviceOwnerAuthentication)` dentro de
  `withTaskCancellationHandler` con `invalidate()` al cancelar; mapeo puro
  `check(for: LAError.Code)`: `userCancel`, `systemCancel`, `appCancel`,
  `authenticationFailed`, `userFallback` → `refused`; el resto → `unavailable`. Se añade
  `canVerify() async -> Bool` (para D1) y la razón fija
  `ApprovalCopy.ownerReason(language)` es la misma frase que la spec TID (Q2 de esa spec:
  sin datos del payload). Un segundo `verify` mientras uno está en curso no abre un segundo
  diálogo: `QAGate` serializa (actor) y responde `owner_busy` al segundo.

## 4. API de cada tool

Todas: `target` vacío; JSON con sorted keys dentro de `output` y terminado con
`BridgeCopy.toolDataSuffix`. Errores con `BridgeCode` más los nuevos de §4.7.

### 4.1 `companion_ask` (escritura; solo QA)

```json
{ "text": "string, 1..16000 bytes UTF-8, sin NUL",
  "conversation": "current | new   (opcional; default current)",
  "as_user_words": "bool (opcional; default true)",
  "wait_seconds": "entero 0..100 (opcional; default 60)" }
```
Si `conversation == "new"` llama `newConversation()` antes. Dispara
`startTurn(text, origin: .agent, asUserWords:)`; si hay un turno en vuelo responde `busy_turn`
con su `turn_id` (no encola: la cola de `dispatch` es de Karen). Espera según D4 y devuelve:

```json
{ "turn_id": "uuid", "conversation_id": "uuid",
  "status": "running | awaiting_owner | completed | failed | cancelled",
  "elapsed_ms": 0,
  "phases": [ { "phase": "started|streaming|acting|owner_check|completed|failed|cancelled", "at_ms": 0 } ],
  "tool_calls": [ { "index": 0, "name": "open_app", "arguments": "{...}", "ok": true,
                    "target": "Safari", "output": "opened Safari", "output_length": 12,
                    "verified": false, "band": "act|confirm|critical",
                    "owner_check": "confirmed|refused|unavailable|none" } ],
  "cards": [ { "kind": "stats", "title": "…", "json": "{…}" } ],
  "receipts": [ { "kind": "created|appended|undone", "subject": "…" } ],
  "files": [ "/Users/…/documento.pdf" ],
  "handoff": { "executor": "claude-code", "goal_length": 0 },
  "pending_owner_check": { "tool": "type_text", "band": "critical", "reason": "…" },
  "reply": { "text": "…", "length": 0, "language": "es", "confidence": 0.9, "is_failure": false },
  "status_lines": [ "…" ],
  "error": { "code": "…", "message": "…" } }
```
`awaiting_owner` significa: el diálogo del sistema está en pantalla; el agente le pide a Karen
el dedo y vuelve con `companion_wait_turn`. Sin QA la tool no se lista (`unknown_tool`).
`arguments`, `output`, `cards[].json`, `reply.text`, `status_lines` solo con QA; `output`
individual ≤ 4 000 bytes y el total al tope de `BridgeCallResult` con la nota de truncado.

### 4.2 `companion_wait_turn` (lectura; solo QA)

`{ "turn_id": "uuid", "wait_seconds": "entero 0..100 (default 60)" }` → mismo resultado. Un
turno terminado responde al instante desde el anillo. Desconocido → `not_found`. Cortado por
un hold de Karen → `status: cancelled`, `error.code: interrupted`.

### 4.3 `companion_new_conversation` (escritura; solo QA)

`{}` → `{ "conversation_id", "previous_conversation_id", "archived_messages": 12 }`.

### 4.4 `companion_turns` (lectura; con y sin QA)

`{ "limit": "1..50 (default 10)", "turn_id": "opcional" }` → lista de `TurnRecord`:
metadatos siempre (`turn_id`, `origin` `typed|choice|agent|voice`, `started_at`, `ended_at`,
`status`, `tool_calls[].{name, ok, band, owner_check, target_length}`, `cards[].kind`,
`reply.length/language`, `error.code`); con QA, además los textos de §4.1.

### 4.5 `companion_screen`, `companion_controls` (lectura; con y sin QA)

`companion_screen {}` → `InspectedScreen` (`page`, `settingsOpen`, `settingsTab`).
`companion_controls {}` → `[ { "id": "settings.privacy.lendHands", "kind":
"switch|button|dropdown|field|secureField", "value": "on|off|<opción>|<longitud>",
"enabled": true, "visible": true } ]`, escrito por las vistas en el `InspectionMirror` con
`.inspectable(id:)` (patrón `ScreenReport`, `SelfInspectionSource.swift:51-68`). `secureField`
nunca lleva valor. Ids = claves del catálogo de copy, estables y sin idioma.

### 4.6 `companion_set_setting` (escritura; solo QA), `companion_capture` (lectura; solo QA)

`{ "key": "language|appearance|voice_mode|decision|interface_sounds|thinking_sound",
"value": "string" }` → `{ "key", "previous", "current" }`. `language` publica
`companionLanguageDidChange` (`SettingsView.swift:190`). Fuera del enum → `invalid_args`.

`companion_capture { "target": "window|island" }` → `{ "path", "width", "height", "bytes" }`.
`not_available` si la superficie no está en pantalla. Se borran al cerrar Companion.

### 4.7 Códigos nuevos (`BridgeCode`)

`qa_scope_off`, `busy_turn`, `not_found`, `interrupted` (expone `ContractError.interrupted`),
`owner_refused`, `owner_unavailable`, `owner_busy`. Entran en `CODE_PATTERN` del shim sin
cambio (`client.ts:112`). Las manos directas por el puente en QA devuelven `owner_refused` /
`owner_unavailable` en lugar de `denied_by_user` cuando la banda es crítica.

## 5. Diseño y archivos a tocar

### 5.1 companion-next · Core (puro)

- `Sources/CompanionCore/Approvals/ApprovalPorts.swift` (nuevo, = spec TID): `OwnerCheck`,
  `OwnerVerifying` (+ `canVerify()`).
- `Sources/CompanionCore/Approvals/QAApprovalPolicy.swift` (nuevo): pura.
  `decide(band: ActionBand, tool: String) -> .act | .ownerCheck | .sheet` donde `.sheet` solo
  para `bridge_session`; `outcome(for: OwnerCheck) -> .granted | .refused(code) | .unavailable(code)`.
- `Sources/CompanionCore/Approvals/ApprovalCopy.swift`: `ownerReason(_:)` (= spec TID).
- `Sources/CompanionCore/Bridge/QATools.swift` (nuevo): `enum QATool` con specs es/en
  (patrón `CompanionTool`), `QAScope`.
- `Sources/CompanionCore/Bridge/TurnRecord.swift` (nuevo): `TurnRecord`, `TurnStatus`,
  `TurnPhase`, `TurnToolCall`, `TurnResult` (`includeText: Bool` deja `text` nil), `TurnRing`
  inmutable (`appending` devuelve copia; 50).
- `BridgeProtocol.swift`: códigos §4.7. `DeliverableTools.swift`: allowlist (R5).
  `BridgePolicy.swift`: buckets (§7), `idleTimeoutQA`. `BridgeCopy.swift`: título de hoja QA.
- `SelfInspection.swift`: `CompanionTool.screen`; `ThreadMessageOrigin.agent/.voice`; puerto
  `QADriving`; `SelfInspecting.controls()`.
- `MessageOrigin.agent` (hoy en `CompanionUI/Chat/ChatMessage.swift:32-35`).
- `SessionTypes.swift` / `SessionMachine.swift`: evento `.agentSubmitted` → `agentTurn = true`
  y `kind = .processing(.thinking)`; `SessionProjection.agentTurn`; fase `ownerCheck` para la
  isla (una línea "Pon el dedo" con `catalogText`, sin contenido). Revisar la lista exhaustiva
  `SessionMachine+Resting.swift:218-224`.

### 5.2 companion-next · Services

- `Sources/CompanionServices/Approvals/LocalAuthOwnerCheck.swift` (nuevo, = spec TID §3).
- `Sources/CompanionServices/Approvals/QAGate.swift` (nuevo, `actor`): `enabled:
  @Sendable () -> Bool`, `owner: (any OwnerVerifying)?`, `classify` por `ActionBand.classify`
  con los hechos que el gate ya tiene (`said`, `inTerminal`, `destructiveTarget`...).
  `decide(_ request: ApprovalRequest, call: ToolCallRef, said: String) async -> QAVerdict`
  (`.notInQA | .act | .granted | .refused(code) | .unavailable(code)`); serializa `verify`
  (D12); registra en el log `tool`, `band` y resultado, nunca argumentos (R6); al
  `.unavailable` apaga el modo (D5) por un closure `disableQA`.
- `Sources/CompanionServices/Tools/ParentToolGuard.swift`: `verdict` consulta `qaGate` antes
  de `answer` (`:57-87`); mantiene `onSettled` para que el puente cuente negativas.
- `Sources/CompanionServices/Bridge/QARunner.swift` (nuevo, `ParentToolExecuting`): sirve
  `companion_ask`, `companion_wait_turn`, `companion_new_conversation`, `companion_turns`,
  `companion_set_setting`, `companion_capture`. `specs` según el alcance, leído por llamada.
- `Sources/CompanionServices/Bridge/TurnWaiter.swift` (nuevo, `actor`): continuación + tope
  inyectado; `signal(turnId:event:)`; sin reloj propio.
- `Sources/CompanionServices/Bridge/TurnJournal.swift` (nuevo): JSONL, rotación por conteo, 0600.
- `BridgeSession.swift`: `idleTimeout` pasa a closure (`:50`, `:143-146`).
- `SelfInspectionRunner.swift`: `.screen`; `companion_thread include_text`.
- `ParentToolRunner.swift`: `bridgeSpecs(_:)` con `installedHands` (D7);
  `BrowserToolRunner.swift` mismo criterio.
- `Sources/CompanionServices/Perception/WindowCapture.swift` (nuevo): `cacheDisplay` → PNG.

### 5.3 companion-next · UI y App

- `SelfInspectionSource.swift`: implementa `QADriving` (`ask(text:newConversation:asUserWords:)
  -> turnId`, `newConversation()`, `setSetting`, `controls()`), `@MainActor`.
- `ChatViewModel+Turn.swift`: `startTurn(origin: .agent, asUserWords:)` → `said = asUserWords
  ? text : ""`; `gate` consulta `qaGate` (puerto Core `QAGating`) antes de `approvals.request`
  (`:272-274`): `.act` → nil; `.granted` → `tools.granted` y nil; `.refused/.unavailable` →
  outcome `failed` con el código; `.notInQA` → camino de hoy. Publica `onTurnEvent` (fases,
  llamadas con banda y resultado de dueña, fin).
- `SettingsAppPane.swift`, `UserPreferences.swift`: `QAScopePreference` (memoria, no
  `UserDefaults`; `.companionQAScopeDidChange`); deshabilitado sin `lendHands` o sin
  `canVerify()`; strings es/en (paridad `LocalizedTests`).
- `InspectionMirror`: `controls` + `.inspectable(id:kind:value:)` en `SettingsSwitch`,
  `AppButton`, `Dropdown`, campos (no `SecureField`).
- `IslandView` / `IslandCopy`: línea `ownerCheck` ("Pon el dedo para continuar").
- `BridgeHost.swift:86-95`: no pausar con `agentTurn`; `idleTimeout` closure.
- `CompanionMain.swift:155-171`: construir `LocalAuthOwnerCheck`, `QAGate`, `QARunner`,
  `TurnWaiter`, journal, captura; pasar `qaGate` a `ParentToolGuard` del puente y a
  `ChatViewModel`; observar `.companionQAScopeDidChange` → `bridgeHost.stopHands()`.
- `docs/DECISIONS.md`: ADR 012 "Modo QA: Companion se deja conducir por el puente sin hojas;
  lo crítico lo protege la prueba de dueña" (revisa ADR 009 sin reemplazarlo; cita la spec TID).
  `changelog.d/<rama>.added.md` por PR.

### 5.4 companion-mcp (shim)

- `tool-kinds.ts`: `companion_ask`, `companion_new_conversation`, `companion_set_setting` en
  `WRITE_TOOLS`; `companion_turns`, `companion_screen`, `companion_controls`,
  `companion_capture` en `READ_TOOLS`; bucket nuevo `LONG_TOOLS` (130 s, `readOnlyHint:
  true`) para `companion_wait_turn`; el test `never lists a tool as both a read and an action`
  (`server-tools.test.ts:401`) pasa a tres conjuntos disjuntos.
- `server.ts`: `companion_status { refresh?: boolean }` → `close()` + `connect()` + sync (D7).
- `tool-result.ts` / `screen-text.ts`: el JSON de `TurnResult` también pasa por el fence.
- `README.md`: "Modo QA" con el riesgo de §6 en una frase; corregir "Permitir 1 h" (retirado
  en §9-5 de la wave 17).

### 5.5 Flujo de `companion_ask`

1. Shim → `call companion_ask`. `BridgeSession` admite (QA on, allowlist, presupuesto).
2. `QARunner.execute` → `QADriving.ask` (`@MainActor`) → `newConversation()` si toca →
   `startTurn(text, origin: .agent, asUserWords: true)` → `session.send(.agentSubmitted)`.
3. `QARunner` → `TurnWaiter.wait(turnId, until: min(wait_seconds, 100))`.
4. El turno corre. Por cada tool que necesitaría hoja, `gate` → `QAGate.decide`:
   - `.act`/`.granted` sin diálogo → sigue; el record anota `band` y `owner_check: none`;
   - crítica → `verify` abre el diálogo del sistema; la fase `owner_check` despierta la espera:
     el agente recibe `awaiting_owner` y se lo dice a Karen; Karen pone el dedo (o cancela);
     `confirmed` → actúa; `refused` → la tool devuelve `owner_refused` al modelo, que sigue
     su turno con ese resultado; `unavailable` → `owner_unavailable` y el modo QA se apaga.
5. `endTurn` / fallo / `abandonTurn` → `completed|failed|cancelled`; el record al journal;
   `QARunner` devuelve `TurnResult(includeText: qaEnabled())`.

### 5.6 Interacción con lo existente

- Hold de Karen durante un turno del agente: pausa (`.listening` es de ella), `abandonTurn`
  corta el turno, el waiter recibe `cancelled`. Si había un diálogo Touch ID abierto, la tarea
  del gate se cancela y `invalidate()` lo cierra (= A9 de la spec TID).
- "Detener manos": cierra la sesión; el turno del agente no se corta solo; la siguiente
  conexión lo ve en `companion_turns`.
- Cool-down: `refused` del dueño cuenta como negativa; tres seguidas apagan la sesión como hoy.
- Presupuesto: `companion_ask` cuesta 1 escritura; las tools que el modelo llame dentro no
  pasan por el puente (R4 de §6).
- Manos directas por el puente (`click`, `type_text`...) en QA: mismo `QAGate` desde
  `ParentToolGuard.verdict`; sin hoja; crítico → Touch ID; la respuesta de la llamada espera
  al dedo (el shim ya da 130 s a las acciones).
- Spec TID (lado hoja): cuando aterrice, el clic de Karen en "Permitir" sobre `bridge_session`
  también pedirá Touch ID (su A11). No choca con esta spec: aquí la hoja de sesión se mantiene
  y el `QAGate` no la toca.

### 5.7 Voz sin micrófono (última entrega)

- `companion_hold { "action": "start|stop", "audio_path": "WAV PCM16 24 kHz bajo ~" }`:
  `start` instala un `FileMic: MicCapturing` (`VoicePorts.swift:31-45`; emite `MicFrame` a
  ritmo real y luego silencio) y manda `session.send(.pressed)`; `stop` manda `.released` y
  restaura el mic. Solo QA; ruta por `ParentToolPolicy.homePath`. Cubre Apple y realtime.
- `VoiceSession+Approvals` consulta el mismo `QAGate`: en QA el turno de voz tampoco ve hojas y
  lo crítico pide Touch ID.
- El turno de voz entra al `TurnRing` con `origin: voice` (closure gemelo de `onTurnEvent`).
- Riesgo propio: el swap del mic reutiliza `MicRestart` (`VoiceSession+MicRestart.swift`); si
  no admite un reemplazo arbitrario, PR-7 lo extiende con test.

## 6. Seguridad y privacidad

**Riesgo escrito del modo QA (texto del interruptor y ADR 012).** Con "Prestar las manos" +
"Modo QA" encendidos y la hoja de sesión aprobada por Karen, cualquier proceso del mismo
usuario que lea `bridge.token` (0600) puede, **sin ninguna hoja más**: escribirle a Companion
lo que quiera y que el modelo lo tome como palabras de Karen (`as_user_words`); ejecutar
directo toda acción de banda *hacer* y *confirmar* (abrir apps y URLs, teclear y pulsar lo no
destructivo, crear documentos nuevos, escribir hojas que solo agregan, llamar MCP de confianza
de banda confirmar); y leer el texto de las respuestas, los outputs de las tools y las
tarjetas. Lo que **no** puede: nada de banda *crítica* (terminal, `run_shell`, borrar, pagar,
sobrescribir archivo o celda, `type_text` en terminal, todo `isMCP`, toda tool sin clasificar)
sin que Karen ponga el dedo o la contraseña en ese momento; ni abrir la sesión sin su clic en la
hoja. Mitigaciones en pie:

1. R7: hoja de sesión por conexión, nunca recordada (`BridgeSession+Calls.swift:93-99`), y
   con QA su título lo dice.
2. D1: el alcance muere con el proceso; no se enciende sin prueba de dueña disponible.
3. D5/D12: lo crítico exige `OwnerCheck.confirmed` de un `LAContext` nuevo por acción; sin
   puerto o sin sensor y sin contraseña se niega (fail-closed) y el modo se apaga.
4. R6: `Log.bridge` y el journal sin argumentos ni output; el `QAGate` registra tool, banda y
   resultado de dueña.
5. Cool-down y tope de hojas siguen contando; un `refused` del dueño es una negativa.
6. 30 escrituras/min sobre `companion_ask` y las manos directas.
7. El clasificador falla hacia arriba (20d: "en la duda, sube"): una tool nueva sin banda es
   crítica y pide Touch ID.

**Residuo (D7 de `self-qa-clic-fuera-de-banda`, aceptado allí):** un proceso que además conozca
la contraseña, o que tenga a Karen tocando Touch ID por otra razón en ese instante, puede
aprobar lo crítico. En QA el residuo pesa más porque hay más diálogos de Touch ID seguidos:
mitigación de copy, la razón fija del diálogo nombra la tool y la banda
(`ApprovalCopy.ownerReason` + sujeto ≤ 80 caracteres, como permite Q2 de la spec TID).

**Privacidad (D6).** Reabre D7 de `self-qa-inspeccion-datos` solo bajo QA. Lo que sale pasa
por `BridgeScreenText.strip` y el cap de 24 000 bytes (`BridgeProtocol.swift:146-153`) y por el
fence del shim. Lista cerrada de campos con texto: `reply.text`, `tool_calls[].arguments`,
`tool_calls[].output`, `cards[].json`, `status_lines`, `companion_thread[].text`. Test con
centinela (A7 de `self-qa-inspeccion.md`) dos veces: sin QA no aparece en ninguna salida; con
QA solo en esos campos.

**Validación de entrada.** `text` por `BridgeArguments.violation` con `maxBytes: 16_000`;
`as_user_words` booleano; `key`/`value` por enum (`allowed`), así el shim los rechaza antes
(`tool-args.ts:33-39`).

**Riesgos**

- R1 Diálogo de Touch ID que nadie atiende: `LAContext` no tiene plazo propio documentado;
  el `QAGate` corre `verify` con un tope de 60 s (`ApprovalTiming.autoDeny`) y cancela
  (`invalidate()`) → `refused`. Sin aserción de reloj en el test: el tope es un `Task`
  inyectado.
- R2 Continuación huérfana en `TurnWaiter` si la conexión cae: `onSessionBoundary` cancela.
- R3 Mezcla de turnos: Karen teclea durante un turno del agente → `dispatch` encola
  (`ChatViewModel.swift:256-262`); el `TurnResult` se filtra por `turn_id`.
- R4 Las tools que el modelo llama dentro del turno no gastan presupuesto del puente; hasta
  `maxRounds` rondas por `companion_ask`. Aceptado: es el chat.
- R5 `companion_controls` depende de que cada control sea `inspectable`; test que escanea
  `SettingsAppPane`/`SettingsView`.
- R6 Un estado "sin hoja y sin Touch ID" nunca existe: PR-1 trae puerto, adaptador y `QAGate`
  sin cablear; PR-2 enciende el salto de hojas ya con el gate cableado y fail-closed.
- R7 Fricción: en una prueba de banda crítica cada acción pide el dedo. Es lo que Karen pidió;
  si molesta en vivo, se reabre con evidencia (igual que la spec TID §6).

## 7. Buckets y allowlist (R5)

| Tool | `BridgeScope` | Bucket | Solo QA |
|---|---|---|---|
| companion_ask | sí | write | sí |
| companion_wait_turn | sí | read (shim: LONG) | sí |
| companion_new_conversation | sí | write | sí |
| companion_turns | sí | read | no (texto solo con QA) |
| companion_screen, companion_controls | sí | read | no |
| companion_set_setting | sí | write | sí |
| companion_capture | sí | read | sí |
| companion_hold (PR-7) | sí | write | sí |

`BridgePolicy.unbucketed(BridgeScope.bridgeTools)` sigue vacío.

## 8. Mejoras evaluadas (prioridad por valor para QA)

| # | Mejora | Valor | Entrega |
|---|---|---|---|
| 1 | Puerto de dueña + `LocalAuthOwnerCheck` + `QAGate` (D5, D12) | prerrequisito de todo lo demás | PR-1 |
| 2 | `companion_ask` / `wait_turn` sin hojas (D2-D5) | el pedido | PR-2 |
| 3 | Manos/navegador por instalación + `companion_status refresh` (D7) | sin esto no hay QA de manos | PR-3 |
| 4 | `companion_new_conversation` | cada caso en limpio | PR-4 |
| 5 | Journal de turnos (D9) + `companion_turns` | historia aunque rote el log | PR-4 |
| 6 | Idle 60 min en QA (D8) | sesiones largas | PR-2 |
| 7 | `companion_screen` + `companion_controls` | QA de Ajustes sin AX | PR-5 |
| 8 | `companion_set_setting` (D11) | idioma y modos | PR-5 |
| 9 | `companion_capture` (D10) | evidencia visual | PR-6 |
| 10 | Voz sin micrófono + gate en voz (§5.7) | prueba de voz e2e | PR-7 |
| 11 | Push en vez de sondeo | MCP no lo consume; la espera con continuación cubre | fuera |

## 9. Preguntas abiertas para Karen

- **Q1** La hoja de sesión `bridge_session` se queda con clic (esta spec). Cuando la spec TID
  aterrice, ese clic pedirá Touch ID además. ¿Quieres que en modo QA la hoja de sesión se
  reemplace por Touch ID solo (sin clic), o que siga clic + Touch ID? No se decide aquí.
- **Q2** Razón del diálogo de Touch ID en QA: frase fija (spec TID) o frase fija + tool y
  banda (propuesto en §6, residuo).

## 10. Plan de tests (uno por comportamiento; sin aserciones de reloj; `now`/topes inyectados)

### Core (`Tests/CompanionCoreTests`)
- `QAApprovalPolicyTests`: `.act` y `.confirm` → actúa; `.critical` → `ownerCheck`;
  `bridge_session` → `sheet` aunque sea crítica; `confirmed` → `granted`; `refused` →
  `owner_refused`; `unavailable` → `owner_unavailable`.
- `QAToolsTests`: cada `QATool` en `BridgeScope.bridgeTools` y en un bucket; `unbucketed`
  vacío; los specs solo-QA no se listan con el alcance apagado.
- `TurnRecordTests`: `includeText: false` sin campos de texto y con longitudes; `true` con
  exactamente los seis campos de §6 (centinela).
- `TurnRingTests`: 51 → 50, el más viejo fuera; `appending` no muta.
- `BridgePolicyTests`: `idleTimeoutQA` sustituye al normal cuando el closure lo dice.
- `SessionMachineTests`: `.agentSubmitted` pone `agentTurn` y `kind = .processing`; la fase
  `ownerCheck` pinta la línea de catálogo sin contenido.

### Services (`Tests/CompanionServicesTests`)
- `LocalAuthOwnerCheckTests` (= spec TID): `cancelCodesMapToRefused`,
  `unavailableCodesMapToUnavailable`, `everyKnownCodeMapsToNonConfirmed`.
- `QAGateTests` (con `FakeOwnerCheck` de la spec TID): fuera de QA → `.notInQA` y la hoja de
  siempre; banda hacer sin llamar al puerto; crítica llama una vez y actúa con `confirmed`;
  `refused` niega y `onSettled` cuenta negativa; `unavailable` niega sin contar y llama
  `disableQA`; sin puerto lo crítico se niega; dos críticas a la vez → la segunda `owner_busy`;
  cancelar la tarea del gate registra cancelación en el fake; `as_user_words` baja la banda de
  un `open_url` con host dicho.
- `ParentToolGuardQATests`: `verdict` con QA y manos críticas pasa por el gate y nunca por
  `approvals.request` (`ScriptedApprovals` sin peticiones).
- `QARunnerAskTests`: sin QA → `unknown_tool`; turno en vuelo → `busy_turn` con id;
  `conversation: new` llama `newConversation` antes (fake `QADriving` graba el orden);
  `as_user_words: false` llega como `said: ""`.
- `TurnWaiterTests`: resuelve `completed` al `signal`; `awaiting_owner` al abrir Touch ID;
  `running` al tope (tope como `Task` cancelable); huérfana cancelada en `onSessionBoundary`.
- `TurnJournalTests`: una línea JSON por turno sin texto; rota a 500; 0600.
- `BridgeHandsListingTests`: `bridgeSpecs` lista `look`/`click`/`type_text`/`see` con
  `selfInFront == true` y la llamada responde `self_in_front`; `trusted == false` →
  `needs_accessibility`; `specs` (chat) sigue ocultándolas (`HandsPolicyTests:134` intacto).
- `SelfInspectionRunnerTests`: `companion_screen` devuelve el espejo; `include_text` ignorado
  sin QA y honrado con QA.
- `BridgeSessionTests`: título de la hoja de sesión con QA; cambiar el alcance cierra la
  conexión; una llamada crítica directa en QA devuelve `owner_refused` con `FakeOwnerCheck`
  en `refused`.
- `WindowCaptureTests`: ruta bajo el directorio 0700 y PNG con las dimensiones de la vista
  fake; `not_available` sin ventana.

### UI (`Tests/CompanionUITests`)
- `ChatViewModelAgentTurnTests`: `startTurn(origin: .agent, asUserWords: true)` manda
  `said == text` al runner (`FakeParentTools.saidSeen`) y `false` manda `""`; fases
  `started → acting → completed`; registra cada `ToolCallRef` con outcome, banda y resultado
  de dueña; `abandonTurn` emite `cancelled`; con `qaGate` en `.granted` no llama
  `approvals.request`.
- `QAScopePreferenceTests`: nace apagado; no escribe `UserDefaults` (escaneo de fuentes como
  A2 de `self-qa-inspeccion`); notifica solo en cambio real; no enciende sin `lendHands` ni
  sin `canVerify()`.
- `InspectionControlsTests`: cada `SettingsSwitch`/`Dropdown` de Ajustes con su id de
  catálogo; `SecureField` nunca con valor.
- `BridgeHostPauseTests` (App o UI según el observador): no pausa con `agentTurn`; pausa con
  `.listening`.

### Integration (`Tests/CompanionIntegrationTests`)
- `QAWiringTests`: la raíz de composición inyecta `LocalAuthOwnerCheck` en `QAGate` y el
  mismo gate en `ParentToolGuard` del puente y en `ChatViewModel` (lee el código fuente, como
  `compositionRootWiresLocalAuthOwnerCheck` de la spec TID); ningún camino de Sources produce
  `.granted` sin `OwnerCheck.confirmed` salvo las bandas no críticas del `QAApprovalPolicy`.

### Shim (`companion-mcp`, vitest)
- `tool-kinds`: tres conjuntos disjuntos; `companion_wait_turn` con timeout largo y
  `readOnlyHint: true`.
- `server-tools`: `companion_status { refresh: true }` manda `bye`, reconecta y registra la
  lista nueva; sin `refresh` no reconecta si ya está listo.
- `tool-result`: `TurnResult` enmarcado y sin invisibles; `owner_refused` se conserva.

### En vivo (Karen, release instalado)
- QA encendido, Companion al frente: `companion_ask("di hola")` → `completed`, `reply.text`.
- `companion_ask("abre Notes y escribe hola")` → `completed` sin hoja ni Touch ID (banda hacer
  con palabras dichas), `type_text` ok.
- `companion_ask("abre Terminal y escribe ls")` → `awaiting_owner`; Karen pone el dedo →
  `companion_wait_turn` → `completed`; cancela el diálogo → `owner_refused` en la tool y el
  turno sigue.
- `osascript` con `AXPress` sobre nada: no hay hoja que pulsar; el diálogo del sistema no
  responde a AX.
- QA apagado: las tools no se listan; `companion_turns` solo longitudes.
- Sin cerrar la sesión: el shim lista `look`/`click` aunque Companion esté al frente.

## 11. Entregas (PRs pequeños, en orden, `changelog.d` en cada uno)

| PR | Repo | Contenido | Archivos principales |
|---|---|---|---|
| **PR-1** `feat/owner-check-port` | companion-next | Prueba de dueña sin cablear: `OwnerVerifying`/`OwnerCheck`, `LocalAuthOwnerCheck`, `FakeOwnerCheck`, `ApprovalCopy.ownerReason`, `QAApprovalPolicy` (Core) y `QAGate` (Services) con tests. Sin cambio de comportamiento. Es el PR-3 de la spec TID más el gate | `ApprovalPorts.swift`, `LocalAuthOwnerCheck.swift`, `OwnerCheckFakes.swift`, `QAApprovalPolicy.swift`, `QAGate.swift`, `ApprovalCopy.swift` |
| **PR-2** `feat/qa-ask` | companion-next | D1 modo QA volátil (exige `canVerify`) + hello con alcance + título de hoja; D2 sin pausa; D3 `origin: .agent` + `as_user_words`; D4 `TurnWaiter`; **D5 gate cableado en `ChatViewModel.gate` y `ParentToolGuard.verdict`**; `companion_ask` y `companion_wait_turn`; D8 idle; línea de isla `ownerCheck`; ADR 012 | `QATools.swift`, `TurnRecord.swift`, `QARunner.swift`, `TurnWaiter.swift`, `ChatViewModel+Turn.swift`, `ParentToolGuard.swift`, `SelfInspectionSource.swift`, `SessionTypes/SessionMachine`, `BridgeHost.swift`, `BridgeSession.swift`, `SettingsAppPane.swift`, `UserPreferences.swift`, `DeliverableTools.swift`, `BridgePolicy.swift`, `CompanionMain.swift`, `IslandCopy`, `Localizable.strings` ×2, `DECISIONS.md` |
| **PR-2b** | companion-mcp | bucket `LONG_TOOLS`, kinds de las dos tools, fence del JSON, README "Modo QA" | `tool-kinds.ts`, `server.ts`, `tool-result.ts`, `README.md` |
| **PR-3** `fix/bridge-hands-listed` | ambos | D7 manos y navegador por instalación; `companion_status refresh` | `ParentToolRunner.swift`, `BrowserToolRunner.swift`, `CompanionMain.swift`, `server.ts`, `client.ts` |
| **PR-4** `feat/qa-turns` | companion-next (+ kinds) | `companion_new_conversation`; D9 journal + `companion_turns`; `companion_thread include_text` | `TurnJournal.swift`, `QARunner.swift`, `SelfInspectionRunner.swift` |
| **PR-5** `feat/qa-screen` | companion-next (+ kinds) | `companion_screen`, `companion_controls` (espejo + `.inspectable`), D11 `companion_set_setting` | `SelfInspection.swift`, `InspectionMirror`, `SettingsAppPane.swift`, `SettingsView.swift`, `Dropdown.swift`, `IncredibleControls.swift` |
| **PR-6** `feat/qa-capture` | companion-next (+ kinds) | D10 `companion_capture` | `WindowCapture.swift`, `CompanionMainWindow.swift`, `QARunner.swift` |
| **PR-7** `feat/qa-voice` | companion-next (+ kinds) | §5.7 `companion_hold` + `FileMic`; `QAGate` en `VoiceSession+Approvals` | `FileMic.swift`, `VoiceSession+MicRestart.swift`, `VoiceSession+Approvals.swift`, `QARunner.swift` |

PR-2 depende de PR-1 (R6 de §6: nunca main sin hoja y sin Touch ID). PR-1 es compatible con
el plan de la spec TID: su PR-3 queda hecho y los demás siguen igual. PR-2 supera los ~5
archivos: lleva cinco líneas de plan en el chat antes de empezar, según las reglas de Karen.
Revisión: `security-reviewer` en PR-1, PR-2 y PR-5 (frontera de confianza: Touch ID, `said`,
ajustes); `code-reviewer` opcional en el resto. Merge de Karen después de leer, con la bitácora
del PR. Cada PR pasa `scripts/gates.sh` y, en el shim, `pnpm verify`.
