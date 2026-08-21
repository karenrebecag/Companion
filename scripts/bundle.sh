#!/bin/bash
# Wraps the SPM binary in a .app bundle. TCC refuses to prompt for mic or
# speech without usage descriptions in an Info.plist, so voice cannot be
# tested from `swift run` alone. Signing/notarization is Wave 5.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/Companion.app"
BIN="$APP/Contents/MacOS"

cd "$ROOT"
swift build -c "$CONFIG"
BUILT="$(swift build -c "$CONFIG" --show-bin-path)/companion"

# Single source of truth: the version ships in the binary, so the bundle
# reads it from Build.swift instead of keeping a copy that drifts.
VERSION="$(grep -o 'version = "[^"]*"' "$ROOT/Sources/CompanionCore/Build.swift" | cut -d'"' -f2)"
[ -n "$VERSION" ] || { echo "no pude leer Build.version" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$BIN" "$APP/Contents/Resources"
cp "$BUILT" "$BIN/Companion"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Companion Next</string>
    <key>CFBundleDisplayName</key><string>Companion Next</string>
    <!-- Distinct from the prototype's com.karen.companion: sharing the id
         makes LaunchServices open whichever app it resolved first. Settle the
         final id when the prototype is retired (Wave 5). -->
    <key>CFBundleIdentifier</key><string>com.karen.companion.next</string>
    <key>CFBundleExecutable</key><string>Companion</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Companion listens when you start a voice turn.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Companion transcribes your voice on this Mac to understand you.</string>
</dict>
</plist>
PLIST

# A stable identity keeps TCC grants across rebuilds; ad-hoc makes macOS treat
# every build as a new app and silently drop the microphone grant, which shows
# up as "mic input format is 0 Hz". Create it with scripts/make-signing-cert.sh.
SIGN="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Companion Dev"; then
    SIGN="Companion Dev"
fi
if ! codesign --force --sign "$SIGN" "$APP" 2>/tmp/companion-codesign.err; then
    echo "codesign falló con '$SIGN':" >&2
    cat /tmp/companion-codesign.err >&2
    exit 1
fi
if [ "$SIGN" = "-" ]; then
    echo "aviso: firma ad-hoc — los permisos de micrófono se pierden en cada" >&2
    echo "       rebuild. Corre scripts/make-signing-cert.sh una vez." >&2
fi

echo "built $APP (signed: $SIGN)"
echo "run: open $APP    logs: ~/Library/Logs/CompanionNext.log"
