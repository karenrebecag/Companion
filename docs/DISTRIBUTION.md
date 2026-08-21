# Distribution

How a build reaches someone else's Mac.

## Build a release

```bash
scripts/release.sh      # bundle + sign + DMG (+ notarize when configured)
```

The script degrades on purpose: with no Developer ID it still produces a DMG
and says the build is unsigned, because that build is useful to anyone who
compiles from source.

## The three levels of trust

| Level | What the user sees | What it needs |
|---|---|---|
| Ad-hoc (today) | Gatekeeper blocks it; user must right-click → Open once | Nothing |
| Developer ID signed | Same warning, but identifies the developer | Apple Developer Program |
| Signed + notarized | Opens like any app | Program + `notarytool` credentials |

## Setting up notarization (once)

1. Join the Apple Developer Program (99 USD/year).
2. Create a **Developer ID Application** certificate (Xcode → Settings →
   Accounts → Manage Certificates) and let it live in the login keychain.
3. Create an app-specific password at appleid.apple.com.
4. Store the credentials under the profile the script expects:

```bash
xcrun notarytool store-credentials companion \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
```

From then on `scripts/release.sh` signs, notarizes and staples on its own.

## Why the hardened runtime needs entitlements

Notarization requires the hardened runtime, which blocks microphone access
unless the app declares it. `scripts/companion.entitlements` asks for exactly
three things: audio input, outgoing network, and read-write access to files
the user picks. Nothing else.

## Local development builds

Use `scripts/bundle.sh` with the local "Companion Dev" identity
(`scripts/make-signing-cert.sh` creates it once). A stable identity is what
keeps macOS from dropping the microphone permission on every rebuild — see
the audio section of `docs/REFERENCE.md`.

## Updates

There is no update framework and that is deliberate: the project ships with
zero external dependencies. Releases are published on GitHub and the app can
compare its version against the latest release (see ADR 002 in
`docs/DECISIONS.md`).
