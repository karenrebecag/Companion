# Companion

Native macOS voice companion. Talk — or type — and the model you pick works
the turn: realtime voice over OpenAI Realtime, heavy work optionally
delegated to a specialist agent with your files and terminal.

Ground-up rebuild of a working prototype, built spec-first. Requires only
macOS 14+ and an OpenAI API key; specialist executors (Claude Code, Hermes)
are optional capabilities detected at runtime.

## Build

```bash
swift build
swift test           # Swift Testing
scripts/gates.sh     # full compliance suite

scripts/bundle.sh    # .app bundle — required for voice
open build/Companion.app
```

Voice needs the bundle: macOS only prompts for microphone and speech access
when the binary carries the matching usage descriptions in an Info.plist.

Run `scripts/make-signing-cert.sh` once. Without a stable signing identity
every rebuild is a different app to macOS, so it silently drops the
microphone grant and the mic starts reporting 0 Hz.

## Documents

- `docs/ARCHITECTURE.md` — layers, pattern, concurrency rules
- `docs/PROGRAM.md` — rebuild program (waves)
- `docs/REFERENCE.md` — behavior ledger from the reference prototype

Status: Wave 3. Paste an OpenAI API key, then talk or type — one thread,
either way. Delegation to specialists is Wave 4.
