# Notices

## Fonts

Companion ships with **Inter** (SIL Open Font License 1.1) in
`Sources/CompanionUI/Fonts/`. Gadey, Hypodermic and TBJ Interval are not
in this repository; they load from disk if present, otherwise Inter then
the system font.

## Vendored binary

| Path | Project | Version | License |
|---|---|---|---|
| `vendor/RiveRuntime.xcframework` | [rive-ios](https://github.com/rive-app/rive-ios) | 6.23.1 (macOS arm64 + x86_64, dSYMs stripped) | MIT |

This is the project's **only** third-party dependency and the only binary
nobody can audit by reading this repository. ADR 003 in `docs/DECISIONS.md`
makes that trade explicit and measured; adding a second one takes another
ADR. Pinning is by content, not by a version string: replacing the
framework must update this checksum in the same commit.

```
shasum -a 256 vendor/RiveRuntime.xcframework/macos-arm64_x86_64/RiveRuntime.framework/Versions/A/RiveRuntime
44da8a76d19e292b04cc7e1768dfc8b2613a7a27b018bc95d230043bf58d3c86
```

The mascot (`Sources/CompanionUI/Mascot/hello.riv`) comes from the public
example at [novra.design/ollama](https://www.novra.design/ollama).

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
