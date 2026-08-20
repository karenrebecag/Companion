# Wave 1 — Core de dominio

**Estado: CERRADO** — 2026-08-20. Karen: "vamos con todas las waves".
Kickoff planner + architect. Gates verdes (640 tests).

## Objetivo

`CompanionCore` completo: logica pura (Foundation), cobertura de
caracterizacion del original. Las waves 2-4 solo traducen I/O hacia estos
tipos.

## Desviaciones vs BORRADOR (kickoff)

1. **Cero puertos en Wave 1.** `SecretStore`, `CapabilityProbe`,
   `ChatProvider`, `VoiceTransport`, `Executor` se definen en la wave que
   los implementa. Config es un snapshot de valores.
2. **Archivos extra:** `Conversation.swift` (Turn + attachments),
   `ToolSpec.swift`, `CompanionBlocks.swift` (parte de Markdown, tope 400).
3. **Codecs no exponen `[String: Any]`.** Encode -> `String`/`Data`
   Sendable; los tests decodifican JSON.
4. **Mute/echo/typed no son estados.** Seis fases; flags en `TurnSnapshot`.
5. **Dos echo guards:** overlap de palabras en `Endpointing`; 350 ms
   `echoGuardUntil` en el snapshot.
6. **Prompts parametrizan `workdir`/`desktop`.** Nada de `NSHomeDirectory`.
7. **Harness propio** (`expect`/`expectEq`), no Swift Testing (deuda ROADMAP).
8. **`JobSteps` es Wave 4.** Aqui solo `stepLabel` + `toolDetail`.
9. **Tools Realtime se inyectan** (`[ToolSpec]`), no un booleano
   `delegateTo`.

## Archivos (`Sources/CompanionCore/`)

| Archivo | Contenido | Contrato original |
|---|---|---|
| `Conversation.swift` | `Turn`, `TurnRole`, `AttachmentRef`, `Turn.numbered` | `Attachments.swift:279` |
| `ToolSpec.swift` | `delegate` / `resolve_approval`; encode plano vs anidado | Realtime vs chat |
| `TurnMachine.swift` | `TurnSnapshot` + `handle(event, at) -> [TurnEffect]` | `main.swift` / VoiceState |
| `RealtimeCodec.swift` | parse + encode session.update / seed / systemItem | `RealtimeProtocol`, Phase 4/6 |
| `SSECodec.swift` | delta, toolDelta, `ToolCallBuilder` | `TalkClient.swift:163-239` |
| `AgentStreamCodec.swift` | NDJSON claude -p, approvals, stepLabel, thought | `ClaudeStreamProtocol` |
| `SentenceSplitter.swift` | takeSentence + splitFirstSentence + sentences | TalkClient / Speech |
| `Endpointing.swift` | EchoGuard, SpeechCues, TranscriptEndpointer, Endpointer | `Endpointer.swift` |
| `Escalation.swift` | `Handoff.parse` + prompts parametrizados | `Escalation.swift` |
| `Markdown.swift` | split, reportCut, plainText, extractSources | `MarkdownSplitter` |
| `CompanionBlocks.swift` | `companion:locations` / `gallery` + locatorJSON | `CompanionBlocks` |
| `Config.swift` | providers, voces, turn detection, snapshot | correccion vs original |
| `Executors.swift` | catalogo `[native] + detectados`; sin enum Brain | ADR 001 |

## API congelada (resumen)

- Core: value types `public` `Sendable`. Cero actors. Cero Apple fuera de
  Foundation. `CGFloat` -> `Double`. Sin `try?`: parse falla -> `.ignored`
  / `nil` con `do/catch`.
- `TurnMachine.handle(_ event: TurnEvent, at now: TimeInterval) -> [TurnEffect]`.
  Reloj inyectado. Echo-guard 350 ms como timestamp, no timer.
  Mute con `speechOpen` -> `commitAndRespond`; mute sin habla pendiente
  solo apaga mic (un commit vacio lo rechaza el server).
- `RealtimeCodec.parse` / `encode`. Tools planos. Voz se omite si `nil`
  (no cambia tras el primer audio); speed siempre viaja. Seed: 6 turnos,
  200 chars, `Usuario:` / `Companion:`.
- `ProviderDescriptor.route(preferred:)`: OpenAI -> Groq -> Ollama;
  preferido conocido encabeza; desconocido no rompe.
- `Handoff.parse`: solo `delegate` + goal no vacio; JSON truncado no
  delega.

Detalle de firmas: salida del architect del kickoff 2026-08-20 (esta
sesion). Si una firma choca con un test de caracterizacion, gana el test.

## Tests (caracterizacion)

Portar mismos casos / misma semantica, nombres de funcion identicos,
llamando a los tipos nuevos:

- Phase 2: endpointer, cues, takeSentence, sentences, splitFirst,
  EchoGuard. **No** AgentChoice.
- Phase 3: route, tool stream, handoff. **No** dotenv.
- Phase 4: parse / sessionUpdate / seed.
- Phase 5: userTurn, parse NDJSON, systemItem, jobPrompt parametrizado.
- Phase 6: control_request, control_response, approvalTool.
- Phase 7: markdown, tables, companion blocks, locatorJSON, reportCut,
  plainText, extractSources (sin `JobSteps.files`), toolUse, stepLabel,
  thought. **No** shortcuts / JobSteps summary / workExecutor / updates.
- Nuevos: catalogo nativo siempre presente; transiciones del reducer
  (start, barge-in, mute, hang-up, error).

Registro en `Tests/CompanionTests/main.swift` (el orquestador lo escribe):

```
scaffoldTests()
endpointingTests()
sentenceSplitterTests()
markdownTests()
escalationTests()
agentStreamCodecTests()
executorsTests()
configTests()
sseCodecTests()
realtimeCodecTests()
turnMachineTests()
finishTests()
```

## Construccion (lotes)

- **A (paralelo):** Endpointing+Splitter | Conversation+Markdown+Blocks |
  Escalation+AgentStream.
- **B (tras A):** Executors+Config | SSE+Realtime (`ToolSpec` aqui o en A).
- **C (tras B):** TurnMachine.
- `main.swift` y `Build.version` los toca el orquestador. Version
  `0.1.0-wave1` solo al cierre.

## Restricciones

- <=400 lineas tipico, 800 tope. Gates verdes. Sin red/audio/UI.
- No copiar el original: reescribir al patron (async no aplica en Core;
  value types, sin callbacks).

## Definicion de done

Gates verdes. Caracterizacion del original en verde para esta capa.
Changelog + roadmap. Spec CERRADO.

## Riesgos

- Reducer sobre-disenado: solo flujos que el original ya exhibe.
- Divergencia Realtime: validar contra PROTOCOL-REALTIME.md y Phase 4.

## Hallazgos del review de cierre (resueltos 2026-08-20)

Review con code-reviewer (APPROVE sin hallazgos) + security-reviewer
(1 critico, 2 altos, 1 medio accionables aqui; detalle en CHANGELOG). Todos
corregidos via tdd-guide con test en rojo primero. El hallazgo de inyeccion
de prompt en Escalation se resuelve estructuralmente en Wave 4 (requisito
anadido a su spec). Pendiente fuera de esta wave: migrar el harness a Swift
Testing (Xcode ya activo) — coordinar con la sesion de Wave 2.
