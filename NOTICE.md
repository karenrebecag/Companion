# Notices

Companion ships with **no third-party code**: it clones and builds with the
Swift toolchain alone. This file records the work that informed the design.

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
