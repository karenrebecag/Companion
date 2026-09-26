# Landing a decision-model layer (jev-voice pattern) in companion-next

Read-only investigation. Repo root:
`/Users/karenrebecaog/Desktop/SoftwareDevProjects/companion-next`. No files
were modified.

---

## 1. THE PATH OF A VOICE COMMAND TODAY

There are **three** turn-submission points, all converging on the same
free-form tool-call model. There is **no code anywhere in this repo that
enumerates a closed candidate set and asks a cheap model to select one with a
probability distribution.** Every "decision" the app makes about which app to
open, which URL to visit, or which tool to call is made by the primary LLM
generating free-form JSON arguments. The one true exception — the hold-FN
dictation branch — makes its decision with **zero model calls at all**, via a
pure Core function. That is the closest existing precedent, and it is
instructive precisely because it proves the pattern (closed-criteria, no LLM)
is already native to this codebase's architecture.

### 1.1 Realtime path (OpenAI Realtime, hold-FN warm path today)

- Session declares tools flat (`ToolSpec.encodeRealtime()`,
  `Sources/CompanionCore/ToolSpec.swift:135-137`) in `sessionUpdate`
  (`Sources/CompanionServices/RealtimeRuntime.swift:131`,
  `parentToolsEnabled: parentTools != nil`).
- The model (`gpt-realtime`) emits a `function_call` event over the
  WebSocket. `RealtimeRuntime.handle(.functionCall(name, arguments, callId))`
  (`Sources/CompanionServices/RealtimeRuntime.swift:290`) dispatches:
  1. `resolve_approval` / `stop_job` — control tools, handled inline
     (`RealtimeRuntime.swift:291-297`).
  2. A `ParentTool` the runner backs
     (`parentTools.handles(name)`, `RealtimeRuntime.swift:302-320`): the
     call's target is derived (`ParentTool.target(of:)`,
     `Sources/CompanionCore/ParentTools.swift:60-65`), the `open_url` gate is
     checked (`ParentToolGate.approval`, see §2), the tool executes
     (`ParentToolRunner.execute`, §1.4 below), a status line is appended to
     the thread, and `functionOutput` is sent back — **the model decided
     which app/URL/file, in free text; nothing offered it a closed menu.**
  3. Otherwise, `delegate` → `Handoff.parse` → `onDelegate(handoff)` →
     `JobRunner` (specialist path), or, if `onDelegate` is nil,
     `Self.functionRefusal` (`RealtimeRuntime.swift:325-338`).
- **Who decides:** the primary model, every time. `ParentToolPolicy`
  validates the *arguments* after the fact (is this a real app? is this URL
  http/https? is this path under `$HOME` and not hidden?) — it never
  constrains what the model is allowed to *propose*.
- **Bad argument:** `ToolArguments.parse` (`Sources/CompanionCore/
  ToolArguments.swift:9-12`) tries `JSONSerialization` first, then a
  syntax-only `repair()` (fence stripping, Python literals, unquoted keys,
  trailing/missing commas, unterminated strings/brackets — the exact list
  `json_repair` documents, no more). Unparseable → `nil` →
  `ContractError.invalidArgs("could not parse arguments: <raw>")`
  (`ParentToolRunner.swift:52-54`) — the model sees its own bad output and
  can retry. **Never** silently `[:]` (that was the pre-Wave-10c bug).
- **Tool not available:** filtered out of `specs()` before the model ever
  sees it (`ParentToolRunner.specs`, `Sources/CompanionServices/
  ParentToolRunner.swift:33-38` — `read_skill` only if a `SkillReading` store
  exists, `find_places` only if `PlacesSearching` exists). This is the fix
  for the documented "captura la intención y luego se muere" bug (§5).

### 1.2 Classic / hybrid path (Apple STT → chat/completions → TTS, Wave 9i)

**Important nuance found in `docs/specs/wave-14-baseline.md` (PROPUESTA,
unapproved, 2026-09-07):** the hold-FN "hot path" **today is still
Realtime**, not classic. Wave 9i's own spec is flagged as "Mentira respecto a
lo shipped" (`docs/specs/wave-14-baseline.md:118`) — the hold calls
`response.create` on `gpt-realtime` as the "brain" even in the shipped code.
Classic/`ClassicRuntime` is the **cold path**: no OpenAI key, or Realtime
unreachable.

- `ClassicRuntime.submit(config:...)` (`Sources/CompanionServices/
  ClassicRuntime.swift:78`) runs a loop of up to `maxParentRounds = 3`
  (`ClassicRuntime.swift:27`, loop at `ClassicRuntime.swift:120`,
  cap-reached check at `:180`), calling `chat.stream(history, tools:)`
  (`ChatProvider`, chat/completions SSE) each round.
- `ChatDelta.toolCalls([ToolCallRef])` — **all** calls of a round together
  (`Sources/CompanionCore/ChatPorts.swift:3-10`, comment: "the provider
  rejects a history where a call is missing its answer"). `.handoff` is
  split out separately if `delegate` is among them (Wave 10c 3A.3).
- Each round's parent-tool calls run via `act(...)`
  (`ClassicRuntime.swift:239`) against `ParentToolRunner`, same validators
  as Realtime. Text fragments go to `SentenceSplitter` → TTS
  per round (so the sentence before an action is spoken, then the result).
- **Same model-decides-everything shape as Realtime**, just chat/completions
  instead of the Realtime socket, and the loop is client-managed instead of
  server-managed.

### 1.3 Typed chat path

`ChatViewModel.consume(history:conversationId:said:)`
(`Sources/CompanionUI/ChatViewModel.swift:367`) is structurally identical to
`ClassicRuntime.submit`: loop `for round in 1...Self.maxParentRounds`
(`ChatViewModel.swift:374`, `maxParentRounds = 3` at `:144`), same
`ParentToolExecuting` dispatch, same round-cap copy
(`ParentToolCopy.roundCap`).

### 1.4 The hold-FN / dictation path (12b / 12e) — the one branch with NO model call

This is the closest thing in the repo to jev-voice's push-to-talk / closed
decision:

- `HoldKeyClassifier` (Core, pure) decides tap vs hold by duration —
  a small closed-state decision, no LLM (`docs/REFERENCE.md`, "Mantener FN y
  la island (Wave 12b)").
- `DictationRouter.destination(mode:field:trusted:)`
  (`Sources/CompanionCore/Dictation.swift:44-59`) is a **pure, total
  function** over three closed inputs — `VoiceMode` (`agent` / `dictation` /
  `automatic`), an optional `FocusedField` (from AX, secure-field excluded),
  and an `AXIsProcessTrusted()` bool — returning a `DictationDestination`
  (`.agent(notice)` or `.dictation(field)`). **No model is consulted.** If
  `.dictation`, the words never reach any LLM at all: `AXTextInjector`
  (Services) injects them into the focused field of the app in front via AX
  or clipboard+Cmd+V (`docs/REFERENCE.md`, "Dictar en el campo enfocado
  (Wave 12e)").
- This is architecturally exactly the jev-voice shape: enumerate closed
  criteria (mode × field-presence × permission), decide in code, act without
  a model. It just doesn't generalize past "talk to Companion vs. type into
  the field under the cursor" today.

---

## 2. THE PARENT TOOL VOCABULARY

### 2.1 `ParentTool` (Core) — acts without approval, closed set of 5

`Sources/CompanionCore/ParentTools.swift:48-56`:

| Tool | Arg shape | Approval | Notes |
|---|---|---|---|
| `open_app` | `{name: String}` | never | resolved against `WorkspaceOpening.runningApplications() + installedApplications()` |
| `open_url` | `{url: String}` | **conditional** (§2.3) | http/https only |
| `open_file` | `{path: String}` | never | under `$HOME`, launchers refused |
| `list_apps` | `{}` | never | capped at 100 (`ParentToolRunner.maxAppListing`, `Sources/CompanionServices/ParentToolRunner.swift:9`) |
| `read_skill` | `{name: String}` | never | by catalog name only, not path (Wave 11a) |

Also offered to the parent when backed: `find_places` (`NativeTool`, `.safe`)
— "a place needs no specialist" (`docs/specs/wave-10b-manos-del-padre.md`
§3.1).

### 2.2 `NativeTool` (Core) — the specialist's set, 8 tools, risk-tiered

`Sources/CompanionCore/NativeTools.swift:8-25`:

| Tool | Risk |
|---|---|
| `find_places`, `list_directory`, `read_file`, `web_fetch`, `web_search` | `.safe` |
| `write_file`, `edit_file`, `run_shell` | `.requiresApproval` |

`run_shell` is **permanently forbidden to the parent** — "Si 'abrir' necesita
un comando, es un encargo" (`docs/specs/wave-10b-manos-del-padre.md` §3.1).

### 2.3 `ParentToolPolicy` (Core) — the validators (post-hoc, not pre-hoc)

`Sources/CompanionCore/ParentToolPolicy.swift`. Three pure validators:

- `appName(_:)` (`:22-34`) — length ≤64, no `/`, `\`, `;`, no control chars.
- `httpURL(_:)` (`:38-58`) — scheme must be http/https, host required, no
  whitespace, length ≤4096.
- `homePath(_:home:)` (`:62-90`) — expands `~`, two-barrier canonicalization
  (lexical `..`-collapse, then `realpath(3)` resolution of symlinks), rejects
  hidden components **before and after** symlink resolution, rejects
  "launcher" extensions (`.app`, `.command`, `.webloc`, etc. —
  `launcherExtensions`, `:17-20`) at every path component, distinguishes
  `not_found` (valid parent, missing leaf — model can retry a different
  name) from `denied_path` (outside home / hidden / launcher).
- `resolveApp(_:among:)` (`:95-106`) — **this is the existing precedent
  closest to a candidate-selection mechanism**: takes the model's free-text
  app name, matches case-insensitively against the known set
  (`WorkspaceOpening.runningApplications() + installedApplications()`), and
  on a miss returns up to 3 near-candidates by substring/common-prefix so the
  model can self-correct. It is deterministic string matching, not a scored
  probability distribution, and it runs **after** the model already
  committed to a name — but structurally it is "enumerate the candidate set,
  pick the closest."

`ContractError` (`ParentTools.swift:6-41`) — the stable error-code contract:
`denied_url`, `denied_path`, `invalid_args`, `not_found`, `denied_by_user`.
"El código viaja en el resultado de la tool... el modelo se recupera por el
código" (`docs/specs/wave-10b-manos-del-padre.md` §3.2).

### 2.4 The `open_url` gate — the one approval in the parent (Wave 10c §3D)

`ParentToolGate.approval(for:said:)`
(`Sources/CompanionCore/ParentToolPolicy.swift:186-201`) — a **pure**
function: parses the URL, extracts host, and checks `saidIt(url:host:said:)`
(`:209-228`) against the user's own turn text (whole URL, bare host, or — for
two-label or `brand.co.tld` hosts only — the brand word, guarded against
negation and subdomain-hijack per the 2026-09-05 security review). If the
host wasn't in the user's own words, an `ApprovalRequest` is raised through
the same sheet/actor as job approvals. This is the **only** place in the
parent-tool vocabulary where a heuristic (not the model) gates an action —
and it exists purely to close a prompt-injection hole (context-sourced URL →
silent exfiltration), not to reduce LLM latency/cost.

### 2.5 "Nada se pierde" (Wave 10c) — what happens to a call that can't run

Four concrete fixes, all evidenced in `docs/specs/wave-10c-nada-se-pierde.md`:

1. **Multiple tool calls in one round were fused.** `SSECodec.toolDelta`
   read only `tool_calls[0]` of each SSE chunk; two parallel calls in one
   response produced `name = "read_filewrite_file"`. Fixed by assembling
   `RawToolCallDelta` **by `index`** (the one required field per OpenAI's
   streaming contract) into a `[ToolCallRef]` list
   (`ChatDelta.toolCalls`, `ChatPorts.swift:9`).
2. **Malformed JSON args → `[:]` silently.** Now `ToolArguments.parse`
   (§1.1) either repairs or returns `nil` → the raw text is surfaced to the
   model in the error.
3. **Approvals polled with `Task.sleep(10ms)` in an actor**, no memory, and
   a denial read to the model as `"Tool requires approval: run_shell"` — a
   config error, not a "no." Fixed with `CheckedContinuation`-based
   `Approvals`, an `ApprovalMemory` (Core, pure, `ApprovalKey` =
   `Tool(pattern)` — same grammar as Claude Code permissions, session
   lifetime only), and a denial that now reads
   `denied_by_user: the user refused this action. Do not retry it or work
   around it...` (`ContractError.deniedByUser`,
   `EscalationCopy`-backed message).
4. **Deduplication within a round**: identical `(name, canonicalized args)`
   executes once; both `.tool` turns get the same output under their own
   `tool_call_id`, because the API rejects a call missing its answer.

---

## 3. ESCALATION AS IT EXISTS

**`Escalation.swift` / `EscalationCopy.swift` do NOT mean "escalate to a
stronger model."** They mean the `delegate` handoff from the conversational
(parent) turn to the specialist executor (NativeExecutor / ClaudeCodeExecutor
/ Hermes). Read carefully, so the wave spec doesn't reuse the name for
something it isn't:

- `Handoff` (`Sources/CompanionCore/Escalation.swift:6-34`) — `{goal,
  context}`, parsed from a `delegate` tool call. **"A malformed or truncated
  `delegate` call must not escalate — the speaker keeps talking whatever
  text it already has"** (`Escalation.swift:4-5`) — i.e. escalation here
  fails *closed to the parent*, never silently to a bigger model.
- `Escalation.jobPrompt` / `executorPrompt`
  (`Escalation.swift:40-91`) — builds the prompt the specialist receives
  (goal, context, workdir, desktop, attachments, skills catalog).
- `EscalationCopy.executorRole` (`EscalationCopy.swift:13-46`) — injected
  **once per specialist session**: tells the specialist it has the tools,
  the user is speaking not reading, markdown rendering rules, card
  vocabulary, sources format.
- `EscalationCopy.queuedNotice` / `resultSummary` — voice-facing copy for
  what happens while/after a job runs.

**How "parent handles it" vs "delegate to specialist" is actually decided
today: it is not decided by code at all.** It is decided by the primary
model's own tool choice, steered only by two prompt fragments
(`ChatPrompt.system`, `Sources/CompanionCore/ChatPrompt.swift:30-78`):

- `actRule` (`ChatPrompt.swift:133-153`, emitted when
  `parentToolsEnabled`): "You have hands... do it, in one sentence."
- `delegateRule` (`ChatPrompt.swift:159+`, emitted when `delegateEnabled`):
  "For anything that reads or changes files, runs commands, or searches the
  web, call delegate."

There is **no classifier, no heuristic, no closed decision** between these
two rules — the model reads both and picks. This is exactly the surface
jev-voice's decision model would replace for the enumerable subset (open
app/URL/file), while leaving `delegate` itself (inherently open-ended: "make
me a script that...") to the strong model.

Once `delegate` fires, `WorkRouting` (`Sources/CompanionCore/Executors.swift`)
decides **which** executor (native / Claude Code / Hermes) gets the job —
by capability ranking, "por tipo, como el prototipo, con el vendor fuera"
(`docs/ROADMAP.md`, "El carril del trabajo"). This is a second, separate
decision — also currently rule-based, not model-based — but it decides
*which specialist*, never *whether to delegate at all*.

---

## 4. LOCAL MODEL PATH (9b)

- **Runtime supported today: Ollama only** (Apple Foundation Models is ADR
  006 point 7, described but not yet an implemented `ChatProvider` — "no es
  una fila del catálogo" as of this reading; `StartupProbing`/`LocalCatalog`
  currently only ever returns `.ollama` paths,
  `Sources/CompanionServices/OllamaModelScan.swift:145-152`).
- **Port/adapter:** `OllamaModelScan` (`Sources/CompanionServices/
  OllamaModelScan.swift`) — read-only `GET http://localhost:11434/api/tags`
  (`:71-72`), decodes `{models: [{name, size}]}`. Chat itself goes through
  the *same* `ChatProvider`/`ChatSSEAttempt` machinery as OpenAI/Groq, via
  `ProviderDescriptor.ollama` (`Sources/CompanionCore/Config.swift:79-85`):
  `baseURL = http://localhost:11434/v1`, i.e. **OpenAI-compatible
  `/chat/completions`**, `secretKey: nil`.
- **`logprobs`: absent from the entire codebase.** `grep -rn "logprob"
  Sources/ Tests/` returns zero hits. `ChatSSEAttempt`/`ChatParameters` never
  request `logprobs` or `top_logprobs`, and no code path parses per-token
  probabilities from a stream. **A "real distribution" is not obtainable
  today without new adapter work** — but the shape to add it into already
  exists: `ProviderDescriptor.supportsStrictTools` is exactly the pattern
  ("HACK: decided by id... upgrade trigger: read the provider's 400 body",
  `Config.swift:39-43`) a `supportsLogprobs: Bool` flag would follow, and
  `ChatSSEAttempt`'s request-body builder (`makeBody`) is the single choke
  point that would need the field added.
- **Reachability, factually:** Ollama's OpenAI-compatible endpoint is known
  (external fact, not verified in this repo) to accept `logprobs`/
  `top_logprobs` on `/v1/chat/completions` for many models; llama.cpp's
  server does too. OpenAI's Chat Completions API supports `logprobs` /
  `top_logprobs` as well. So the **transport is OpenAI-shaped everywhere in
  this repo already**, which is the good news: a `DecisionProvider` adapter
  that wants `top_logprobs` for a constrained one-token-choice completion can
  extend the existing `ChatProvider`/`ChatSSEAttempt` request path rather
  than inventing a new transport.
- **Apple Foundation Models** (`SystemLanguageModel`, ADR 006 point 7) is an
  **in-process Swift API, not HTTP** — no logprobs surface is discussed
  anywhere in this repo, and its 4096-token joint input/output budget is
  called out as a hard constraint ("obliga a un presupuesto de historia
  propio... si no da para una conversación útil, el adapter no se escribe").
  If FM ever becomes a `ChatProvider`, it is a structurally different kind of
  adapter (no URLSession, no SSE) and would need its own investigation for
  whether the SDK exposes token probabilities at all — out of scope of what
  this repo currently shows.

---

## 5. THE DOCUMENTED FAILURES A DECISION MODEL WOULD ADDRESS

Direct quotes, with sources:

1. **"Captura la intención y luego se muere."** `web_search` was always
   offered to the model (`NativeTool.allCases` unfiltered) and always
   returned "not available: requires configured search provider API key."
   The model reported it *couldn't* search instead of finding another way.
   Fixed by filtering unbacked tools out of `availableTools`
   (`docs/ROADMAP.md`, "El carril del trabajo", 2026-08-24). **This is
   exactly the failure mode jev-voice targets structurally**: an LLM given a
   tool it can't reliably use produces worse behavior than not offering the
   tool at all — the same argument for not letting the LLM free-form-generate
   an app name when a closed enumeration exists.

2. **The parent used to have only `delegate`.** Before Wave 10b:
   `"abre Safari"` today (pre-10b) went `delegate → JobRunner → JobQueue
   (waits if another job) → ExecutorProvider → NativeExecutor → 1-10 model
   rounds → run_shell "open -a Safari" → Approvals.request → permission
   sheet → 120s or click → ProcessGroupRunner → result → card → log line →
   voice ack. For a 30ms action, and asking permission for something the
   user just said out loud.` (`docs/specs/wave-10b-manos-del-padre.md` §1,
   paraphrased/quoted structure). And: *"El corpus tiene el ratio invertido:
   ~25 tools directas en el padre... y `start_large_task` solo para lo
   largo."* This is the exact "90% of commands don't need a powerful agent"
   observation, arrived at independently and already partially fixed by
   giving the parent 5 direct tools — but the *selection* within those tools
   (which app, which URL) is still 100% free-form LLM generation.

3. **ADR 005 — "el modelo se cree autor."** A job's result used to enter the
   thread twice: once as the specialist's text, once paraphrased by the
   voice model reading it back — "el que sonaba era el resumen del que
   estaba escrito" (`docs/DECISIONS.md`, ADR 005). Fixed: the result returns
   once; the voice only acknowledges. Wave 9d's milestone in the roadmap is
   literally titled **"El modelo deja de creerse autor del informe del
   especialista."** This is a *different* escalation problem (double
   narration) than jev-voice's, but the same underlying lesson: don't let a
   generative model re-decide/re-express something a deterministic step
   already produced.

4. **Wave 10c "nada se pierde"** — see §2.5. The tool-call round trip had
   four distinct correctness bugs (call fusion, arg loss, approval polling,
   denial misread as error) before it was reliable even for a *single*
   free-form tool call. A decision layer that removes the round trip
   entirely for the enumerable 90% sidesteps this whole class of bug for
   those commands.

5. **Wave 12e dictation lesson** — *"Cualquier fallo del inyector (fieldGone,
   refused, needsAccessibility) manda las palabras a Companion: nada se
   pierde y nada se pega en otra app"* (`docs/REFERENCE.md`, "Dictar en el
   campo enfocado"). This is the *fail-safe* pattern a decision model's
   "not sure" branch should copy: a low-confidence decision must degrade to
   the existing free-form path, never to silence or a wrong guess.

6. **Wave 13a vision** — the screenshot is **never** sent to the realtime
   model; only a capped SUMMARY (≤400 chars) + up to 12 SNIPPETS (≤80 chars
   each) are (`docs/specs/wave-13a-ver-la-pantalla.md` §3.3). This is the
   repo's existing philosophy for "on-screen elements as candidates": never
   hand the model raw pixels/DOM, hand it a small enumerated, capped,
   labeled set — precisely the shape jev-voice wants for "indexed on-screen
   elements."

7. **Wrong app names (measured, not hypothetical).** The first live manual
   test of Wave 10b found: *`"abre safari, puedes?"` → `not_found: no app
   named Safari"` because on macOS 26 `/Applications/Safari.app` is a
   symlink into a cryptex, and `contentsOfDirectory(at:...,
   options:[.skipsHiddenFiles])` doesn't see it* — fixed by enumerating with
   `readdir`-equivalent path APIs (`docs/specs/wave-10b-manos-del-padre.md`
   §9, "Primera prueba manual"). Also noted in the same section: *"el modelo
   llamó 'navegadores' a ChatGPT y Slack — `list_apps` sin categoría deja al
   modelo adivinar."* Both are exactly the class of error a candidate-set
   selection (rather than free generation) removes by construction.

8. **Latency of the tool-call round trip — the only hard numbers in the
   repo are from the *competitor* trace, not Companion's own production
   metrics** (`docs/specs/wave-14-baseline.md`, PROPUESTA/unapproved,
   §1): Incredible's measured hold timeline —
   `FN up → +300ms commit queue → +1500ms primary-STT deadline → Groq batch
   STT final at t=7417ms → orchestrator text at t=7903ms → LLM first token
   at t=8858ms (TTFT 955ms) → TTS first audible at t=9706ms (+848ms after
   token) → release→audible = 5073ms total.` Companion's own instrumentation
   for this exists (`TurnTimeline`, `Sources/CompanionCore/
   TurnTimeline.swift:39-50`, emits a `"voice timeline: press→mic ... ·
   press→ear ... · press→ready ... · press→partial ... · release→commit ...
   · commit→audio ..."` line per hold) but **no absolute numbers for
   Companion's own tool-call latency are recorded anywhere in docs** — this
   would need to be measured before/after a decision layer to make the
   latency case quantitatively, not just structurally.

---

## 6. WHERE A DECISION LAYER WOULD SIT

### 6.1 A Core port: `DecisionProvider` (or `ChoiceOracle`)

Following the exact shape of `ChatProvider` (`ChatPorts.swift:35-39`) and
`ContextSensing` (`TurnContext.swift:146-150`) — a protocol in Core, pure
request/response types, no I/O in Core itself:

```swift
// Core, pure. Mirrors ChatProvider's shape but returns a closed choice,
// never free text.
public struct DecisionQuestion: Sendable, Equatable {
    public var kind: DecisionKind          // .choice(candidates) / .yesNo
    public var utterance: String           // what the user said (or a span of it)
    public var candidates: [String]        // the enumerated menu, IDs not prose
}

public struct DecisionAnswer: Sendable, Equatable {
    public var choice: String?             // nil == "not sure" / below threshold
    public var distribution: [String: Double]  // candidate -> probability
    public var confidence: Double          // min over the judgements used
}

public protocol DecisionProvider: Sendable {
    func decide(_ question: DecisionQuestion) async throws -> DecisionAnswer
}
```

This is a **new port**, not a repurposing of `ChatProvider`, because its
contract is fundamentally different: `ChatProvider.stream` returns free text
+ tool calls; `DecisionProvider.decide` returns a closed choice + a
distribution. Keeping them separate also keeps `ChatSSEAttempt`'s existing
780-line-adjacent complexity untouched (gates.sh's 800-line hard cap,
`scripts/gates.sh` Gate 2, would otherwise be at risk).

### 6.2 A pure candidate producer + `Plan` composer (Core)

The candidate *lists* mostly already exist, just not exposed as a Core-safe,
DecisionProvider-facing type:

- **Installed/running apps**: `WorkspaceOpening.runningApplications() /
  installedApplications()` (`ParentTools.swift:184-190`) already returns
  `[String]`. It's a Core *protocol*; the enumeration itself correctly lives
  in Services (`NSWorkspaceOpener.swift:58-84`) because Core cannot import
  AppKit (gates.sh Gate 3). A candidate producer for "which app" is
  therefore: **reuse `WorkspaceOpening` directly**, do not duplicate it.
- **Known sites / URL allowlist**: does **not exist today**. `httpURL`
  validates shape, not membership; there is no bookmarks/history/allowlist
  candidate source. This would be new — and per ADR 006's Config-boundary
  rule ("nada lee el entorno fuera de Config"), it would have to come from
  either browser history (new, invasive, likely out of scope) or a
  user-curated list in `Config`/`UserPreferences` (safer, smaller, matches
  the `providerOrder`/`ContextPreference` precedent).
- **Shortcuts**: no `Shortcuts`/Apple Shortcuts integration exists in this
  repo at all (`grep -rn "Shortcuts" Sources/` — no non-comment hits). New
  surface entirely.
- **Spans cut from the transcript**: the raw turn text is already fully
  available at every call site (`heard` in Classic, `commitWithText`'s
  argument in Realtime, `text` in typed) — no extraction utility exists, but
  the substring-matching machinery in `ParentToolGate.saidIt`
  (`ParentToolPolicy.swift:209-228`) is the closest existing precedent for
  "does a candidate appear in what the user said," and its negation-aware,
  word-boundary-aware regex approach is directly reusable for span
  extraction.
- **Indexed on-screen elements**: explicitly **out of scope everywhere it's
  mentioned**. `docs/specs/wave-10b-manos-del-padre.md` §7: *"`look_at` /
  click / type sobre la UI enfrente (AX) — Wave 12+."* `docs/specs/
  wave-13a-ver-la-pantalla.md` §3.5: *"Clic/type por visión (sigue
  diferido)."* What *does* exist and is reusable as a text-only candidate
  source is `ContextBlock`'s screen snippets (`Sources/CompanionCore/
  TurnContext.swift`, `ContextBlock.swift` — SUMMARY + up to 12 SNIPPETS,
  each ≤80 chars, labeled by app) and `ScreenBriefParser.swift`. These are
  candidate *text*, not clickable elements — a decision model choosing among
  them would be choosing "which visible label does the user mean," not
  clicking anything (clicking stays out of scope per the same specs).

A pure `Plan` composer belongs in Core, next to `TurnContext`/`ContextBlock`:

```swift
// Core, pure. min-confidence aggregation across however many DecisionAnswers
// a plan needed (one per slot: "which app" + "which action", etc.)
public struct Plan: Sendable, Equatable {
    public var steps: [PlanStep]
    public var confidence: Double   // min(over steps' DecisionAnswer.confidence)
}
public enum PlanOutcome: Sendable, Equatable {
    case act(Plan)
    case notSure(reason: String)     // below threshold -> falls back to the LLM path
}
public enum PlanThreshold {
    public static func evaluate(_ plan: Plan, minConfidence: Double) -> PlanOutcome
}
```

This mirrors `LocalModelChoice.choose` (`Sources/CompanionCore/
LocalModels.swift:78-101`) — same shape: pure static function, ordered rule
list, deterministic tie-break, and `DictationRouter.destination`
(`Dictation.swift:44-59`) — same shape: total function over closed enum
inputs returning a decision + an escape hatch.

### 6.3 Does it REPLACE the LLM tool-call, or sit in FRONT as a fast path?

**Recommendation: sit in FRONT, as a fast path, with the current LLM path as
fallback — never a silent replacement.** Reasoning, grounded in what's
already in the repo:

- `ParentTool` is *already* a closed, small, enumerable set (5 tools). It is
  the natural target. `NativeTool` is **not**: `read_file`/`write_file`/
  `run_shell` take arbitrary paths/commands that cannot be pre-enumerated —
  a decision model has nothing to select *over* there. So this layer applies
  to the parent-tool surface, not the specialist's.
- The fallback-on-uncertainty pattern is already the house style: Ollama
  absent → base tier falls back cleanly (`StartupState`, `LocalModels.swift:
  164-179`); dictation injector failure → words go to Companion, nothing
  lost (§5.5); low screen-vision confidence → `<screen_summary pending=
  "true"/>` rather than blocking (`wave-13a` §3.2). A decision layer that
  can't clear its threshold should degrade to exactly the current flow
  (model emits the tool call itself), not to silence, and definitely not to
  "not sure" spoken back with no path forward for the trivial 90% case —
  that would be a worse UX regression than today's "always ask the model."
- Doing it as a **pre-filter in front of `ParentToolRunner.execute`** (not
  inside it) keeps every existing validator (`ParentToolPolicy`,
  `ParentToolGate`) exactly where it is and exactly as strict — the decision
  layer would pick a candidate, but the candidate still has to pass
  `ParentToolPolicy.homePath`/`httpURL`/`resolveApp` before anything opens.
  This is the same "layer 1 (strict) then layer 2 (repair), never invent"
  discipline `ToolArguments`/`ToolSpec.strict` already established for
  argument correctness (Wave 10c 3A.4) — the decision layer is a *third*
  layer ahead of both, not a replacement for either.
- Concretely: on hearing an utterance, before (or in parallel with) sending
  it to the primary model, run it through `DecisionProvider` against the
  `ParentTool` candidate set (app names from `WorkspaceOpening`, etc.). If
  `PlanOutcome.act(plan)` clears the threshold, execute directly through
  `ParentToolRunner`/`ParentToolPolicy` and skip the round trip. If
  `.notSure`, fall through to today's path unchanged (model sees `actRule` +
  `delegateRule` as now). This is invisible to the LLM either way — no
  prompt changes needed for the fallback case.

### 6.4 TurnMachine / SessionMachine wiring — existing events to reuse

No new `SessionEvent`/`SessionEffect` cases are strictly required for the
happy path — the vocabulary already fits:

- **`.parentActing(targets: [String])` / `.parentActed`**
  (`Sources/CompanionCore/SessionMachine.swift:46-51`) — already means "the
  app is doing something on its own, no job, no sheet." A fast-path decision
  executing `open_app` would emit exactly these two events, unchanged, the
  same as the LLM-driven path does today (`RealtimeRuntime.swift:305,313`).
  The UI (`IslandState`, `.processing(.toolExecuting)`) needs no new state.
- **A new notice/card would be needed for "not sure"** — nothing in
  `SessionEvent` today represents "I heard you but I'm not confident which
  X you meant." The closest existing shape is `.heardNothing` →
  `projection.notice = .couldntHear` (`SessionMachine.swift:~115-119`) and
  `.dictationFailed(failure)` → a notice without a transition
  (`SessionMachine.swift:~128-133`, "A notice, not a transition: the words
  are already on their way to Companion and its turn owns the kind"). A
  `.decisionUnsure` case would follow that exact pattern: a `Notice` card,
  no `projection.kind` change, and the turn continues into the normal
  model-driven path as if the fast path had never been tried.
- **`TurnTimeline`** (`Sources/CompanionCore/TurnTimeline.swift`) is the
  right place to add a `decisionMade`/`decisionSkipped` mark if the latency
  win needs to be measured, following the existing
  `"voice timeline: ..."` line format (§5.8).

### 6.5 Config

Following `ContextPreference`/`ContextChannels` (Wave 10a) and
`ProviderDescriptor`/`providerOrder` (Wave 9b) precedent:

- `Config.decisionConfidenceThreshold: Double` — a tunable minimum, read
  through `Config` like everything else ("Toda lectura del entorno pasa por
  Config", `CLAUDE.md`).
- A `ProviderDescriptor`-shaped entry for the judge model itself — it can
  legitimately be **the same Ollama/OpenAI descriptor already in the
  catalog**, just called with a different (smaller, cheaper, possibly
  `logprobs`-requesting) request shape. No new `SecretKey` case is needed if
  it reuses an existing provider's key; a new one only if a dedicated
  judge-only provider (e.g. a specific Groq model) is chosen.
- A toggle in `UserPreferences`/`SettingsAppPane`, same pattern as
  `ContextPreference` (`docs/specs/wave-10a-contexto-del-turno.md` §3.3) —
  on by default only once measured to be safe, given the security history in
  §2.5.

### 6.6 Tests to write first (repo's reducer-testing style)

Match the existing convention exactly (`Tests/CompanionTests/
ParentToolPolicyTests.swift`, `SessionMachineTests.swift`): **one `@Test
@MainActor` entry function per file that calls many small, named,
single-assertion sub-functions**, using `expect`/`expectEq` from
`TestKit.swift`, and fixtures/fakes added to `ChatFakes.swift`
(`FakeWorkspaceOpener` already exists there per Wave 10b §3.6 — a
`FakeDecisionProvider` returning a scripted `DecisionAnswer` is the natural
next fake).

Suggested first tests, Core-pure, no network:

1. `PlanThreshold.evaluate` with a single step above threshold → `.act`.
2. `PlanThreshold.evaluate` with `confidence == threshold` exactly →
   (decide and pin the boundary behavior; the codebase's own comparable
   pick, `LocalModelChoice.choose`, is inclusive `<=` at its boundary,
   `LocalModels.swift:88`).
3. `PlanThreshold.evaluate` with **any** step below threshold → `.notSure`
   (min-over-judgements, per the task's own spec).
4. `Plan` composed of zero steps → `.notSure` (never act on nothing).
5. A `DecisionQuestion` with a candidate list built from
   `WorkspaceOpening.installedApplications()` fed through a
   `FakeDecisionProvider` → `ParentToolRunner.execute` receives the resolved
   exact app name, never the raw utterance.
6. `FakeDecisionProvider` returning `.notSure` → the existing model-driven
   path runs unchanged (assert `ChatProvider.stream` was still called with
   `actRule` present) — this is the regression test that proves the fast
   path is additive, not a fork.
7. A `.decisionUnsure` (or equivalent) event → `SessionMachine` emits a
   notice card, **no** `projection.kind` change (mirrors
   `testAPermissionFailureIsACardNotAKind`,
   `Tests/CompanionTests/SessionMachineTests.swift:12`).
8. End-to-end-ish: candidate set changes between the decision and execution
   (an app quit mid-decision) → `ParentToolPolicy.resolveApp` still runs and
   can still fail `not_found` — the decision layer's confidence does not
   bypass validation (ties into §7's risk about not weakening the security
   reviews already done in Wave 10b/10c).

---

## 7. CONSTRAINTS & RISKS

- **Swift 6 strict concurrency.** Every new Core type must be `Sendable`;
  `CompanionUI` defaults to `@MainActor`
  (`Package.swift:37-41`, `.defaultIsolation(MainActor.self)`); a
  `DecisionProvider` adapter in Services, if it holds mutable scan state
  like `LocalCatalog` (`OllamaModelScan.swift:117-176`, `NSLock`-guarded,
  `@unchecked Sendable`), should follow that exact lock pattern rather than
  inventing a new concurrency primitive — `DispatchSemaphore` is explicitly
  banned in async contexts (`docs/ARCHITECTURE.md`, "Concurrency rules").
- **ADR 003 — no new binary/external deps without a fresh ADR.** A decision
  layer needs none: it's a request-shape change (`logprobs`/
  `top_logprobs`) on an **already-OpenAI-compatible** endpoint
  (`ProviderDescriptor`, §4). This is good news for approval — it does not
  touch the one axis (`ADR 003`) that has historically been contentious in
  this repo.
- **`scripts/gates.sh` static checks that would bite:**
  - Gate 2's 800-line hard cap (`gates.sh`, "Regla de la casa: 200-400
    lineas tipico, 800 tope duro") — `ChatSSEAttempt.swift` and
    `RealtimeRuntime.swift` (415 lines) are already large; new
    decision-layer wiring inside them should be its own new file
    (`DecisionGate.swift` or similar), not grown in place.
  - `try?` banned in Core/Services (Gate 2) — a `DecisionProvider` adapter
    doing HTTP must propagate/handle errors exactly like
    `OllamaModelScan.scan` does (`do { ... } catch { return silent() }`,
    never `try?`).
  - No `print`/`NSLog`/`debugPrint` — use `Log` (Services) as everywhere
    else.
  - Architecture import gate (Gate 3): **Core cannot import
    AppKit/AVFoundation/SwiftUI/WebKit/Combine.** This is why "installed
    apps" enumeration cannot move into Core even for the candidate producer
    — it must stay behind the `WorkspaceOpening` port exactly as it is
    today (`ParentTools.swift:184-190`, implemented in
    `NSWorkspaceOpener.swift`, Services). The decision layer's Core code can
    only ever see `[String]` candidate lists handed to it, never enumerate
    them itself.
- **The spec process is not optional here.** `docs/CLAUDE.md`/
  `docs/ORCHESTRATION.md`: `BORRADOR → APROBADO → EN CURSO → CERRADO`, and
  *"Sin spec APROBADO por Karen no se escribe código."* `wave-14-baseline.md`
  — the spec that most overlaps this idea (per-role BYOK models: brain /
  mouth / ear) — is itself still **PROPUESTA, sin implementar, espera
  aprobación** as of 2026-09-07. A decision-model wave would sit adjacent to
  or inside that unresolved wave, not ahead of it; the two should probably
  be reconciled in the same spec pass (a "judge" role is a natural sibling
  of wave-14's brain/mouth/ear roles) rather than drafted independently.
- **ADR 001's tool-addition discipline still applies in spirit.** *"Cada
  tool nueva exige un fallo observado, y la prueba de que ninguna de las que
  ya existen lo cubre"* (`docs/DECISIONS.md`, ADR 001 notes on the 7th/8th
  tool). A decision layer isn't a new tool, but the same rigor — an observed
  failure, not a wish — should gate it: the qualifying evidence already
  exists (§5: the Safari-symlink miss, the "navegadores" mislabeling, the
  pre-10b permission-for-a-30ms-action absurdity) and should be cited
  verbatim in the wave spec rather than re-derived.
- **Security risk — do not let confidence bypass validation.** Wave 10b/10c
  spent two full security-review passes hardening `ParentToolPolicy`/
  `ParentToolGate` (compound shell commands in remembered approvals,
  subdomain hijack in `saidIt`, launcher-extension escape via `open_file`,
  TOCTOU in `NSWorkspaceOpener.open`). A decision layer must feed its chosen
  candidate through those **same** validators unchanged — a high-confidence
  wrong answer (model or judge) is still just a wrong answer, and the
  validators are what catches it, not the confidence score. This is worth
  stating explicitly in the wave spec's Restricciones section, mirroring
  Wave 10b §4's *"Ninguna tool del padre pide permiso... run_shell nunca en
  el padre"* pattern of hard, named restrictions.
- **`open_url`'s approval gate must not be weakened by a fast path.** If a
  decision layer picks a URL candidate for the parent to open, it still has
  to pass `ParentToolGate.approval(for:said:)` — the candidate being
  "confidently chosen" doesn't mean the *user said it*, which is the actual
  criterion Wave 10c 3D gates on. These are orthogonal checks and both must
  run.
- **No conflicting ADR found.** Nothing in `docs/DECISIONS.md` forbids or
  contradicts this direction; ADR 004/006's "detect, never assume" and
  "read-only adapter, product behaves identically when absent" principles
  (`HermesProviderScan`/`OllamaModelScan` precedent) are directly compatible
  with — and should be the template for — a `DecisionProvider` adapter that
  degrades to `.notSure` when its judge model is unreachable.

---

## Summary (10 lines)

Best insertion point: a new Core port `DecisionProvider` (mirrors
`ChatProvider`/`ContextSensing`) feeding a pure `Plan`/`PlanThreshold`
composer, sitting **in front of** `ParentToolRunner.execute` as a fast path
for the 5-tool `ParentTool` set only — never touching `NativeTool` (whose
args are inherently open-ended) or `delegate` itself. It replaces the
free-form model round trip for the enumerable 90% (`open_app`, `open_url`,
`open_file`, `list_apps`, `read_skill`), reusing `WorkspaceOpening` as the
app-candidate source and `ParentToolPolicy`/`ParentToolGate` unchanged as
the validation layer every chosen candidate must still pass — confidence
never bypasses validation. On `.notSure` it falls through to today's
`actRule`/`delegateRule` prompt path untouched, so the LLM path is always
the safety net, matching every existing degrade-on-uncertainty pattern in
this repo (dictation-injection failure, screen-vision timeout, Ollama
absence). It must not touch `run_shell`, the specialist's file tools, the
`delegate`/`Escalation` handoff machinery, or weaken the `open_url`
same-words gate — and it needs its own APROBADO spec (likely reconciled
with the still-unapproved Wave 14 brain/mouth/ear role split) before any
code is written.
