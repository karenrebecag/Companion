# Architecture

Native macOS voice companion. Swift 6 (strict concurrency), SPM, no Xcode
project required — Command Line Tools are enough to build, test and run.

## Layers = SPM targets

```
CompanionApp        composition root: builds adapters, injects, launches
  ├─ CompanionUI    SwiftUI views, design tokens, cards  (MainActor default)
  ├─ CompanionServices  adapters: network, audio, subprocesses, Keychain
  └─ CompanionCore  pure domain: state machine, codecs, parsing  (no Apple
                    frameworks beyond Foundation)
```

Dependencies only point downward. The compiler enforces this: a forbidden
import is a build error, not a review comment. `scripts/gates.sh` adds the
framework-level rules SPM can't express.

## Folders inside a target

Each target groups its files by domain (`Voice/`, `Chat/`, `Browser/`,
`Bridge/`, `Tools/`, `Deliverables/`...), and a domain keeps the same name in
every target it spans: `CompanionCore/Browser` holds the ports and policy,
`CompanionServices/Browser` the adapters, `CompanionUI/Settings` the view.
The pairing is what would let a domain become its own module later
(interface + live implementation) without renaming anything.

A file that only extends a type is named `Type+Concern.swift`
(`VoiceSession+Pumps.swift`), so the type it belongs to reads from the
name. `Skills`, `Diagram`, `Fonts` and `Mascot` are copied resources in
`Package.swift`: no source folder may take those names.

## Pattern: ports & adapters around a pure core

- **Core defines ports** — protocols like `VoiceTransport`, `ChatProvider`,
  `Executor`, `Transcriber`, `SpeechSynthesizer`, `SecretStore`. Core never
  knows which implementation exists or whether one is installed.
- **Services implement adapters** — `RealtimeWebSocketTransport`,
  `OpenAIChatProvider`, `ClaudeCodeExecutor`… Optional capabilities (Claude
  Code, Hermes) are *detected at runtime*, never assumed. The product must be
  fully usable with nothing but an OpenAI API key.
- **The composition root wires it** — `CompanionApp` is the only place that
  names concrete adapters.
- **Adapters that must know each other expose a wiring init** — when two
  adapters share a framework object the app layer should never hold (the
  audio player joining the mic's `AVAudioEngine`), Services offers an init
  taking the concrete peer, e.g. `RealtimePlayer(sharedWith: MicCapture)`.
  Depending on the concrete type is deliberate: it keeps non-Sendable
  framework types inside Services instead of leaking into the root.

## State: reducer, not scattered mutation

The turn lifecycle (idle → connecting → listening → thinking → speaking) is a
value-type state machine: `handle(event) -> [Effect]`. Pure, exhaustively
tested, no I/O. A runtime in Services executes effects and feeds results back
as events. (If you come from the web: it's a Redux reducer with an effect
interpreter.)

Since Wave 12a there are two reducers, one projection: `TurnMachine` owns
how the voice captures and plays; `SessionMachine` (Core) observes its
snapshots and owns what the chrome shows — Idle / Hover / Listening /
Processing(phase) — plus typed turns, the parent's hands, the specialist's
job and the approval queue. `SessionModel` (UI) is the only writer of the
projection; views read it, view models send events. A failure or a stop is
an `InterruptReason` on the way back to Idle, never a kind of its own.

## Concurrency rules

- Swift 6 language mode everywhere; data races are compile errors.
- UI targets default to `@MainActor` (set in Package.swift).
- Long-lived sessions (voice, jobs) are `actor`s in Services.
- Events flow as `AsyncStream`, not stored callback closures.
- Cancellation is structured (`Task.cancel()`), not generation counters.
- `DispatchSemaphore` never blocks an async context.

## Observation

View models use `@Observable` (Observation framework), split by concern
(chat, voice, settings) — not one god object. Views re-render only on the
properties they actually read.

## Errors and logging

No silently swallowed errors: `try?` is banned in Core and Services (gate).
Every failure path either recovers deliberately or logs through `Log` with
context. Unknown protocol events are logged, never dropped silently.

## Configuration boundary

One `Config` type owns every external fact: API keys (Keychain), model names,
endpoints, detected executors. Nothing else reads the environment, home
directory or dotfiles. This is what keeps the app distributable.

## Testing

Target: Swift Testing (`@Test` / `#expect`). Today the machine builds with
bare Command Line Tools, which ship neither the Testing module nor XCTest, so
tests run through `CompanionTests` — an executable target with a tiny harness
whose API mirrors Swift Testing on purpose (`expect` -> `#expect`). Upgrade
trigger: once Xcode is installed, migrate mechanically to a real
`.testTarget`. Core targets ~complete coverage; the reference project's test
suite is ported as a characterization contract. `scripts/gates.sh` runs
build + static checks + architecture checks + tests; it must be green before
any merge. Two contracts are data, not prose: `conformance/ui-contract.json`
(grid and projection rules over `Sources/CompanionUI`, a ratchet on old debt)
and `conformance/hud-gates.json` (the HUD's auditor gates, each citing the
tests that prove it; the runner fails when a cited test disappears).
