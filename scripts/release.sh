#!/bin/bash
# Builds a distributable app. Signs with a Developer ID and notarizes when
# credentials exist; otherwise produces an ad-hoc build and says so, because
# an unsigned app is still useful to contributors who build from source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Companion.app"
DMG="$ROOT/build/Companion.dmg"

"$ROOT/scripts/bundle.sh" release

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
