# Distribution

How a build reaches someone else's Mac.

## Two identities, one Mac

| | Bundle id | In the Finder | Log |
|---|---|---|---|
| Release (`bundle.sh release`) | `com.karen.companion` | Companion.app | `~/Library/Logs/Companion.log` |
| Development (`bundle.sh`) | `com.karen.companion.next` | Companion Next.app | `~/Library/Logs/CompanionNext.log` |

The strings live in `Sources/CompanionCore/ProductIdentity.swift`; a test
compares them against this script, because a plist written by bash that
drifts installs an app whose own code does not recognise it.

They never share an id on purpose: two apps claiming one bundle id make
LaunchServices open whichever it resolved first, which is how a "fixed" build
kept launching the old one. For the same reason the author's earlier
prototype — installed at `~/Applications/companion.app` with a LaunchAgent
that revives it at login — must be uninstalled before packaging a release,
since it claims `com.karen.companion` too. `bundle.sh release` refuses to run
while it is there and says so.

## Build a release

```bash
scripts/release.sh      # bundle + sign + DMG (+ notarize when configured)
```

The script degrades on purpose: with no Developer ID it still produces a DMG
and says the build is unsigned, because that build is useful to anyone who
compiles from source.

## Where this project actually is

Releases ship **ad-hoc signed**, because there is no Apple Developer account
behind the project. That is not a temporary state waiting on a script: it is
a decision with a price, and the price is paid by whoever downloads.

| Level | What the user sees | What it needs |
|---|---|---|
| **Ad-hoc — what ships today** | Gatekeeper blocks the first open; the user has to allow it by hand, and the steps differ on macOS 14 vs 15+ | Nothing |
| Developer ID signed | Same warning, but it names the developer | Apple Developer Program (99 USD/year) |
| Signed + notarized | Opens like any other app | Program + `notarytool` credentials |

The README carries both unblock routes, because right-click → Open stopped
working in macOS 15 and half the people who download would be stuck without
the second one. `scripts/release.sh` already signs and notarizes the day
credentials exist; nothing here has to be rewritten for that.

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

There is no update framework and that is deliberate: the only binary this
project ships that it did not build is RiveRuntime (ADR 003, attributed and
pinned by checksum in `NOTICE.md`), and adding a second one takes another
ADR. Releases are published on GitHub and the app compares its version
against the latest release (ADR 002).

The check is silent by design: no network, a 404, a hostile payload — all of
them produce nothing on screen. An update check must never hand the user an
error to deal with.
