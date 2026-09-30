#!/bin/bash
# Builds a distributable app. Signs with a Developer ID and notarizes when
# credentials exist; otherwise produces an ad-hoc build and says so, because
# an unsigned app is still useful to contributors who build from source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Companion.app"  # release: DISPLAY_NAME = Companion
DMG="$ROOT/build/Companion.dmg"

# 21c D7: a DMG must map back to a commit, so a dirty tree is refused. Rule of
# spec §3.1, tightened: tracked changes anywhere; untracked OR ignored files
# where they reach the build (SwiftPM `.copy` ships an ignored file too); no
# git, or a git whose toplevel is a parent repo judging files it does not
# track as ours (unknown is never clean). Measured before building.
# HACK: duplicates the rule S2 puts in bundle.sh, and is stricter than §3.1's
# wording (--ignored, toplevel); share one helper and amend §3.1 when S2 lands.
dirty=0
top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$(cd "$ROOT" && pwd -P)" ]; then
    dirty=1
elif ! git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    dirty=1
elif ! git -C "$ROOT" diff --quiet HEAD; then
    dirty=1
elif [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all --ignored -- Package.swift Sources Extensions assets scripts)" ]; then
    dirty=1
fi
if [ "$dirty" = "1" ]; then
    if [ "${COMPANION_ALLOW_DIRTY:-}" = "1" ]; then
        echo "aviso: arbol sucio (o sin git) y COMPANION_ALLOW_DIRTY=1 — el DMG no corresponde a un commit" >&2
    else
        echo "el arbol esta sucio (o sin git): un DMG asi no se puede llevar a un commit." >&2
        echo "Commitea los cambios, o corre con COMPANION_ALLOW_DIRTY=1 si es a proposito." >&2
        exit 1
    fi
fi

# D6: building a DMG must never replace the app installed in /Applications.
COMPANION_NO_INSTALL=1 "$ROOT/scripts/bundle.sh" release

IDENTITY="${COMPANION_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)"/\1/' || true)"
fi

if [ -n "$IDENTITY" ]; then
    echo "signing with: $IDENTITY"
    # Hardened runtime is required for notarization; the entitlements let the
    # app keep using the microphone and speech recognition under it.
    codesign --force --deep --options runtime \
        --entitlements "$ROOT/scripts/companion.entitlements" \
        --sign "$IDENTITY" "$APP"
else
    echo "aviso: sin identidad Developer ID — build sin notarizar" >&2
fi

# The re-sign above (hardened runtime) produced a different artifact from the
# one bundle.sh smoked; what goes into the DMG must be what passed the probe.
# Unconditional so no branch can skip it; without a re-sign it costs a rerun.
"$ROOT/scripts/package-smoke.sh" "$APP"

rm -f "$DMG"
hdiutil create -volname "Companion" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo "built $DMG"

# Notarization needs an Apple Developer account; store credentials once with:
#   xcrun notarytool store-credentials companion --apple-id ... --team-id ...
if [ -n "$IDENTITY" ] && xcrun notarytool history --keychain-profile companion >/dev/null 2>&1; then
    echo "notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile companion --wait
    xcrun stapler staple "$DMG"
    echo "notarized and stapled"
else
    echo "aviso: sin credenciales de notarizacion; quien lo abra vera el aviso" >&2
    echo "       de Gatekeeper. Ver docs/DISTRIBUTION.md" >&2
fi
