# Companion

Native macOS voice companion. Talk — or type — and the model you pick works
the turn: realtime voice over OpenAI Realtime, heavy work optionally
delegated to a specialist agent with your files and terminal.

Ground-up rebuild of a working prototype, built spec-first. Requires only
macOS 14+ and an OpenAI API key; specialist executors (Claude Code, Hermes)
are optional capabilities detected at runtime.

## Install

Download `Companion.dmg` from the [latest release](https://github.com/karenrebecag/Companion/releases/latest),
open it and drag the app to Applications.

The build is **not notarized** — there is no Apple Developer account behind
it — so macOS will refuse to open it the first time. Getting past that is a
one-time step, and it changed in macOS 15:

- **macOS 14 (Sonoma):** right-click the app → **Open** → **Open** again.
- **macOS 15 (Sequoia) and later:** double-click it once and let it be
  blocked, then go to **System Settings → Privacy & Security**, scroll to the
  message about Companion and press **Open Anyway**. Right-click → Open no
  longer works there.

Companion then asks for the microphone and for speech recognition the first
time you speak. Both prompts are the system's; the app has no way to skip
them, and refusing either leaves the rest of it working.

You also need an OpenAI API key, which the app asks for on first run and
stores in your keychain.

## Build

```bash
swift build
swift test           # Swift Testing
scripts/gates.sh     # full compliance suite

scripts/bundle.sh          # .app bundle — required for voice
open "build/Companion Next.app"

scripts/bundle.sh release  # the product itself, installed to /Applications
```

Voice needs the bundle: macOS only prompts for microphone and speech access
when the binary carries the matching usage descriptions in an Info.plist.

A debug bundle installs as **Companion Next** with its own bundle id, so it
never displaces a copy of the release you may have installed. Two apps that
share an id make macOS open whichever it resolved first — see
`docs/DISTRIBUTION.md`.

Run `scripts/make-signing-cert.sh` once. Without a stable signing identity
every rebuild is a different app to macOS, so it silently drops the
microphone grant and the mic starts reporting 0 Hz.

## Documents

- `docs/ARCHITECTURE.md` — layers, pattern, concurrency rules
- `docs/PROGRAM.md` — rebuild program (waves)
- `docs/REFERENCE.md` — behavior ledger from the reference prototype

## What works today

- **Voice and text share one thread.** Realtime voice with barge-in (tap
  anytime; by voice when output is echo-free, such as headphones).
- **Delegation.** The chat model can hand heavy work to a built-in specialist
  that reads and writes files, runs commands and searches the web — inside the
  folder you choose, and asking permission before anything destructive.
- **Your keys stay yours.** Stored in the Keychain, never in the repo or a
  dotfile.

## Contributing

See `CONTRIBUTING.md`, and read `docs/REFERENCE.md` before touching audio:
it holds the behaviour that only shows up on real hardware.

Licensed under MIT.
