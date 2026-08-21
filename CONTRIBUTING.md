# Contributing

## Ground rules

The project is built spec-first, in waves. Before writing code for anything
larger than a fix, there is a spec in `docs/specs/` that says what the wave
delivers and what it deliberately leaves out.

Two documents are not optional reading:

- `docs/ARCHITECTURE.md` — the layers and why the compiler enforces them.
- `docs/REFERENCE.md` — the ledger: behaviour learned the hard way, mostly
  around macOS audio. **Read the relevant section before touching audio,
  permissions or the realtime protocol.** Most of it is invisible to tests.

## Before you open a PR

```bash
swift build
swift test
scripts/gates.sh     # build + static checks + layer rules + tests
```

`scripts/gates.sh` must be green. It checks things a reviewer should not have
to: no secrets, no debug printing, no swallowed errors in Core or Services,
no file over 800 lines, and no import that breaks the layering.

## What reviewers look for

- **Wiring, not just code.** The most common defect in this repo's history is
  a correct, tested type that nothing ever calls. If you add a capability,
  show what invokes it.
- **Tests that prove the effect.** For anything with side effects, assert the
  effect (the file was not written), not the message.
- **Comments say why.** What the code does is already in the code.
- No emojis, in code or in UI text.

## Commits

`type(scope): description`, one change per commit, message explains the why.

## Manual testing

Some layers cannot be covered by tests: microphone permissions, CoreAudio,
code signing. Those are verified by hand on a real Mac before a wave closes,
and what they teach goes into the ledger.
