# Notices

Companion ships with **Inter** (SIL Open Font License 1.1) in
`Sources/CompanionUI/Fonts/`. Gadey, Hypodermic and TBJ Interval are not
in this repository; they load from disk if present, otherwise Inter then
the system font.

## Design references (no code copied)

- **hermes-agent** (Nous Research, MIT) — tool schemas and agent-loop
  semantics informed the native executor's tool set. No code was taken; the
  project is Python, this one is Swift. See ADR 001 in `docs/DECISIONS.md`
  for why Companion does not depend on it.
- **Companion prototype** (this author) — the ledger in `docs/REFERENCE.md`
  carries the hard-won audio and protocol behaviour that this rebuild ports.

## Services

The app talks to the OpenAI API (chat, realtime voice, speech synthesis) with
the key the user provides. It can also talk to any OpenAI-compatible endpoint,
including a local one.
