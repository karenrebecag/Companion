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

## Ported code

- **Space UI** ([usespaceui/ui](https://github.com/usespaceui/ui)), MIT. The
  thinking orb in `Sources/CompanionUI/Orb/Thinking/` is a Swift port of its
  `orb/thinking` renderers (scenes, presets, math), drawn with Canvas. The
  upstream licence follows.

```
MIT License

Copyright (c) 2026 Space UI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Services

The app talks to the OpenAI API (chat, realtime voice, speech synthesis) with
the key the user provides. It can also talk to any OpenAI-compatible endpoint,
including a local one.
