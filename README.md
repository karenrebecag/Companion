```
 ╔══════════════════════════════════════════════════════════════════════════════╗
╔╝                                                                              ╚╗
║   ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ███╗   ██╗██╗ ██████╗ ███╗   ██╗  ║
║  ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗████╗  ██║██║██╔═══██╗████╗  ██║  ║
║  ██║     ██║   ██║██╔████╔██║██████╔╝███████║██╔██╗ ██║██║██║   ██║██╔██╗ ██║  ║
║  ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██║╚██╗██║██║██║   ██║██║╚██╗██║  ║
║  ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║ ╚████║██║╚██████╔╝██║ ╚████║  ║
║   ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝  ║
╚╗                                                                              ╔╝
 ╚══════════════════════════════════════════════════════════════════════════════╝
```

# Companion

Native macOS voice companion. Talk or type; the model you choose works the turn. Heavy work can be handed to a specialist that reads and writes files, runs commands, and searches the web — inside a folder you choose, and only after asking permission for anything destructive.

Built for one real need: **natural conversation with the computer**, with access to the local AI tools already on the machine, less friction than Siri, and more agency than a chat window.

This is a personal project and a portfolio piece. It is not a commercial product. It exists to solve a daily problem and to practice product judgment under real constraints (hardware scars, permissions, trust, scope).

Spec-driven end to end. The owner wrote the specs, the architecture rules, the ADRs, and the wave program; the implementation was produced by orchestrated agents under those contracts. Zero lines of application code were written by hand.

Requires macOS 14+ and an OpenAI API key. Optional specialist executors (Claude Code, Hermes) are detected at runtime — the app is fully usable without them.

---

## The problem it actually tries to solve

Most “AI on the desktop” experiences are either:

- a chat panel that cannot touch the rest of the machine, or
- a powerful agent that is slow, opaque, or requires a heavy external stack.

Companion aims at the middle that is useful every day: **speak or type, stay in one thread, and occasionally let a specialist act on files and the terminal under explicit permission**. Voice and text share the same conversation. The specialist is optional, sandboxed, and interruptible.

The project started as a working prototype and was rebuilt from zero with a strict process (specs → TDD → gates → close). The rebuild was not a rewrite for its own sake; it was a way to keep the behaviour that only shows up on real hardware while replacing a structure that had become hard to reason about.

---

## What works today

- **One thread for voice and text.** OpenAI Realtime for live voice with barge-in (tap anytime; by voice when output is echo-free, e.g. headphones). Classic pipeline (mic → system speech recognition → chat → TTS) as fallback.
- **Delegation to a specialist.** The chat model can hand off a job. A built-in `NativeExecutor` runs a tool loop over any OpenAI-compatible endpoint with a small, deliberate set of tools (read / write / edit files, shell, web). Claude Code and Hermes appear as options only if they are installed.
- **Approvals, answerable by voice.** Destructive actions require explicit permission. The request appears in a sheet — a job is assistive UI and does not interrupt to ask — and can be answered out loud while hands are busy. Unanswered requests time out to deny.
- **Keys stay on the machine.** Stored in the Keychain. Nothing reads environment files or `~/.hermes` as a requirement.
- **Degrades on purpose.** No optional CLI → the app still works. No network → clear failure instead of a silent mic. Missing permissions → the rest of the product remains usable.

---

## Architecture (why it is shaped this way)

Four SPM targets, dependencies only downward. The compiler enforces the boundaries; `scripts/gates.sh` adds the rules SPM cannot express.

```
CompanionApp          composition root
  ├── CompanionUI     SwiftUI, design tokens, cards   (MainActor by default)
  ├── CompanionServices  network, audio, processes, Keychain
  └── CompanionCore   pure domain: state machine, codecs, parsing
```

**Ports & adapters.** Core defines protocols (`VoiceTransport`, `ChatProvider`, `Executor`, `SecretStore`, …). Services implements them. Optional capabilities are discovered at runtime, never assumed.

**Turn lifecycle as a pure reducer.** `TurnMachine` is a value-type state machine: `handle(event) → [Effect]`. No I/O. A runtime in Services executes effects and feeds results back as events. Exhaustively tested. This is the single source of truth for idle → connecting → listening → thinking → speaking and for barge-in, mute, fallback, and delegation hand-off.

**Swift 6 strict concurrency** everywhere. Long-lived sessions are actors. UI defaults to MainActor. Events move as `AsyncStream`. Cancellation is structured.

**Configuration boundary.** One `Config` type owns external facts (keys, models, endpoints, detected executors, language). Nothing else reads the environment or home directory. That is what keeps the app distributable and reviewable.

Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Decisions that matter

These are the product and engineering choices that define the project more than any feature list.

| Decision | Why |
|----------|-----|
| **No required external agent runtime** (ADR 001) | Hermes was powerful and also a full ecosystem. Requiring it killed adoption for a personal tool. Capabilities were absorbed natively; Claude Code / Hermes remain optional adapters. |
| **No Sparkle** (ADR 002) | Updates check GitHub Releases with a small, testable client. Adding an update framework would be a second binary dependency on a project that treats supply chain as a first-class concern. |
| **No binary dependencies** (ADR 003 retired) | The one vendored binary (Rive, for the mascot) left when the orb became the identity. Any binary needs its own ADR. |
| **Ad-hoc signing for releases** | There is no Apple Developer account behind the project. Gatekeeper will block the first open; the README documents both macOS 14 and 15+ paths. Notarization is supported by the scripts the day credentials exist. |
| **Approvals for destructive tools** | The specialist is useful only if it is trusted. Write and shell always ask. Paths cannot leave the chosen workdir, including via symlinks. |
| **Spec-first waves, gates before merge** | Every non-trivial change starts as a written contract. `scripts/gates.sh` (build, static checks, layer rules, tests) is the same script run in CI and locally. |
| **Ledger of hardware scars** | Audio, permissions, and realtime behaviour that only appear on real Macs are written down in [`docs/REFERENCE.md`](docs/REFERENCE.md) so they are not rediscovered. |

What was deliberately left out is as important as what shipped: no mandatory Python stack, no silent update framework, no “computer use” of the whole UI, no unbounded tool surface in the native executor.

---

## Current status (honest)

The engineering and process are mature for a personal project of this scope. The product still has gaps that matter when the audience is no longer only the author:

- **Trust of the voice loop.** Mostly closed: the voice no longer reads a result back — the specialist's text is the message and the voice only acknowledges, and which of the two endings happened comes from the job, not from the model ([ADR 005](docs/DECISIONS.md)). What is still open is silence, not lying: the classic fallback has no model to produce that acknowledgment, so a job ends there without a word, and a permission nobody looks at times out to deny just as quietly.
- **First-run for a stranger.** Gatekeeper (ad-hoc build), microphone and speech prompts, and a required API key are real walls. The happy path for someone who has never seen the repo is still being hardened.
- **Discoverability of delegation.** The most differentiated capability is not self-explanatory. Users have to learn what they can actually ask for.
- **Continuity.** Conversations and per-folder job sessions persist. There is not yet a deliberate local knowledge layer that makes the companion feel like it accumulates context about *you* over time.

Wave program and measured gap vs the original prototype live in [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## Direction (not a commitment)

The next meaningful product step under consideration is **local knowledge under user control** — an explicit, inspectable store (notes, preferences, project context) that the model can query through tools, with the same approval and sandbox rules that already exist. The goal is continuity without turning the app into a second notes system or a silent profiler.

**Explicitly deferred:** vision models driving direct control of arbitrary system UI. It is attractive on a whiteboard and expensive in reliability, permissions, and scope. It does not strengthen the core thesis (natural conversation + deliberate local agency) enough to justify the cost right now.

---

## Install

Download `Companion.dmg` from the [latest release](https://github.com/karenrebecag/Companion/releases/latest), open it, and drag the app to Applications.

The build is **not notarized** (no Apple Developer account). macOS will refuse to open it the first time:

- **macOS 14 (Sonoma):** right-click the app → **Open** → **Open** again.
- **macOS 15 (Sequoia) and later:** double-click once and let it be blocked, then **System Settings → Privacy & Security** → **Open Anyway**. Right-click → Open no longer works there.

On first speech the system will ask for microphone and speech recognition. Refusing either leaves the rest of the app working. An OpenAI API key is requested on first run and stored in the Keychain.

---

## Build

```bash
swift build
swift test           # Swift Testing
scripts/gates.sh     # full compliance suite

scripts/bundle.sh          # debug .app (Companion Next) — required for voice
open "build/Companion Next.app"

scripts/bundle.sh release  # product identity, for packaging
```

Voice requires the bundle: macOS only shows microphone and speech prompts when usage descriptions are present in an Info.plist.

Run `scripts/make-signing-cert.sh` once. Without a stable signing identity every rebuild is a different app to macOS, so the microphone grant is dropped and the mic reports 0 Hz.

Debug and release use different bundle IDs on purpose so Launch Services never opens the wrong binary. See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

---

## Documents

| Document | What it is |
|----------|------------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layers, ports & adapters, concurrency rules |
| [`docs/PROGRAM.md`](docs/PROGRAM.md) | Rebuild method (waves, specs, TDD, gates) |
| [`docs/REFERENCE.md`](docs/REFERENCE.md) | Ledger of behaviour learned on real hardware |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | ADRs |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Wave status and measured gaps |
| [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) | Signing, Gatekeeper, updates |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How changes are expected to land |

---

## Stack

- Swift 6 (strict concurrency), SwiftPM only — no Xcode project required to build and test
- macOS 14+
- OpenAI Realtime (primary voice path) + system Speech / AVSpeech as fallbacks
- MIT license

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Read [`docs/REFERENCE.md`](docs/REFERENCE.md) before touching audio, permissions, or the realtime protocol — most of that behaviour is invisible to tests.

`scripts/gates.sh` must be green before a change is considered done.

---

Licensed under MIT.
