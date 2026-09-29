# Notices

## Fonts

Companion ships with **Inter** (SIL Open Font License 1.1) in
`Sources/CompanionUI/Fonts/`. Gadey, Hypodermic and TBJ Interval are not
in this repository; they load from disk if present, otherwise Inter then
the system font.

## Vendored binary

None. RiveRuntime (rive-ios 6.23.1, MIT) shipped for the animated mascot until
2026-09-29, when the orb replaced the mascot as the app's identity and the
binary left with it (ADR 003, retired). Adding a binary again takes an ADR
and an entry here pinned by checksum.

## Design references (no code copied)

- **Orb** by Siddhant Mehta ([metasidd/Orb](https://github.com/metasidd/Orb)),
  MIT (copyright 2024 Siddhant Mehta; same terms as the project LICENSE).
  The orb's layered look — wavy blob, rotating glow, particles, soft shadow
  — follows it, rewritten in this repository's patterns; particles use
  SpriteKit like the upstream port.
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
