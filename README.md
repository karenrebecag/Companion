# Companion

Native macOS voice companion. Talk — or type — and the model you pick works
the turn: realtime voice over OpenAI Realtime, heavy work optionally
delegated to a specialist agent with your files and terminal.

Ground-up rebuild of a working prototype, built spec-first. Requires only
macOS 14+ and an OpenAI API key; specialist executors (Claude Code, Hermes)
are optional capabilities detected at runtime.

## Build

```bash
swift build          # Command Line Tools are enough — no Xcode project
swift run CompanionTests   # tests (see docs/ARCHITECTURE.md, Testing)
scripts/gates.sh     # full compliance suite
```

## Documents

- `docs/ARCHITECTURE.md` — layers, pattern, concurrency rules
- `docs/PROGRAM.md` — rebuild program (waves)
- `docs/REFERENCE.md` — behavior ledger from the reference prototype

Status: Wave 2. `swift run companion` — paste an OpenAI API key and chat.
Voice is Wave 3.
