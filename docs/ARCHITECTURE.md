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

Cross-target API is `package`, not `public` (SE-0386): visible to every
target in this package and to nothing outside it. The package ships an
executable, not a library, so there is no external API to declare. A symbol
that another target does not need stays `internal`.

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
  The one exception, discarding late writes from work that cannot be
  stopped in time, is ADR 008 in `DECISIONS.md`.
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

Swift Testing (`@Test` / `#expect`), one test target per layer under
`Tests/<Target>/` (flat folders, so `#filePath` depth is the same everywhere):

| Test target | Depends on | Holds |
|---|---|---|
| `CompanionCoreTests` | Core | domain: codecs, state machines, policies |
| `CompanionServicesTests` | Core, Services | adapters: network, processes, bridge |
| `CompanionUITests` | Core, UI | views, view models, copy; no resources |
| `CompanionIntegrationTests` | Core, Services, UI | flows that cross layers |

Shared fakes live in four regular support targets (not test targets, never
`@testable`, API `package`): `CompanionTestKit` (harness, conformance, fixtures;
no Companion dependency), `CompanionCoreTestSupport` (Core + TestKit),
`CompanionServicesTestSupport` and `CompanionUITestSupport` (each: its layer +
CoreTestSupport + TestKit). A support target never carries `swiftSettings`, so
UI's `defaultIsolation` does not leak into the fakes. `scripts/check-test-layers.sh`
(run by Gate 3) enforces this: R1 no `@testable` outside `*Tests`; R2 import
direction between test and support targets; R3 (on `dump-package`) support
targets are regular, settings-free, depend only on what the table allows, no
production target depends on them, and UI test targets have no resources; R4 no
`@_exported import`. Imports of support modules are explicit in every file. The
voice harness reaches `SessionModel` only through the `SessionEventSink`
protocol, so `CompanionServicesTestSupport` never imports UI.
`scripts/gates.sh` runs build (debug and release) + static checks +
architecture checks + tests; it must be green before any merge. Two contracts
are data, not prose: `conformance/ui-contract.json`
(grid and projection rules over `Sources/CompanionUI`, a ratchet on old debt)
and `conformance/hud-gates.json` (the HUD's auditor gates, each citing the
tests that prove it; the runner fails when a cited test disappears).
