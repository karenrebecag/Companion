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

rm -rf "$APP"
mkdir -p "$BIN" "$APP/Contents/Resources"
cp "$BUILT" "$BIN/Companion"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Companion</string>
    <key>CFBundleDisplayName</key><string>Companion</string>
    <key>CFBundleIdentifier</key><string>com.karen.companion</string>
    <key>CFBundleExecutable</key><string>Companion</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
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

# A stable identity keeps TCC grants across rebuilds; ad-hoc re-prompts every
# time. Create one with Keychain Access > Certificate Assistant (Wave 5).
SIGN="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Companion Dev"; then
    SIGN="Companion Dev"
fi
codesign --force --sign "$SIGN" "$APP" >/dev/null 2>&1 || true

echo "built $APP (signed: $SIGN)"
echo "run: open $APP    logs: ~/Library/Logs/Companion.log"
