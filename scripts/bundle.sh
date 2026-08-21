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

# SPM does not know the framework will live in the bundle: without this rpath
# dyld looks everywhere except Contents/Frameworks and the app dies at launch.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$BIN/Companion" 2>/dev/null || true

BINPATH="$(swift build -c "$CONFIG" --show-bin-path)"
for bundle in "$BINPATH"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done
# Rive resolves fileName against the main bundle, not the SPM module bundle.
if [ -d "$ROOT/Sources/CompanionUI/Mascot" ]; then
    cp "$ROOT/Sources/CompanionUI/Mascot/"*.riv "$APP/Contents/Resources/" 2>/dev/null || true
fi

if [ -d "$ROOT/Sources/CompanionUI/Fonts" ]; then
    mkdir -p "$APP/Contents/Resources/Fonts"
    cp "$ROOT/Sources/CompanionUI/Fonts/"*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
    cp "$ROOT/Sources/CompanionUI/Fonts/"*.ttf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
    [ -f "$ROOT/Sources/CompanionUI/Fonts/OFL.txt" ] \
        && cp "$ROOT/Sources/CompanionUI/Fonts/OFL.txt" "$APP/Contents/Resources/Fonts/"
fi

[ -f "$ROOT/assets/AppIcon.icns" ] \
    && cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
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

# Rive ships as a framework: it must travel inside the bundle and be signed
# with the same identity, or the app will not launch.
RIVE_FW="$ROOT/vendor/RiveRuntime.xcframework/macos-arm64_x86_64/RiveRuntime.framework"
if [ -d "$RIVE_FW" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$RIVE_FW" "$APP/Contents/Frameworks/"
fi

# A stable identity keeps TCC grants across rebuilds; ad-hoc makes macOS treat
# every build as a new app and silently drop the microphone grant, which shows
# up as "mic input format is 0 Hz". Create it with scripts/make-signing-cert.sh.
SIGN="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Companion Dev"; then
    SIGN="Companion Dev"
fi
if [ -d "$APP/Contents/Frameworks/RiveRuntime.framework" ]; then
    codesign --force --sign "$SIGN" \
        "$APP/Contents/Frameworks/RiveRuntime.framework" >/dev/null 2>&1 || true
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

# Install to /Applications: testing always opens THE app, never a stray
# build. Same path + same bundle id + same identity = TCC grants survive.
INSTALL="/Applications/Companion.app"
if rm -rf "$INSTALL" 2>/dev/null && ditto "$APP" "$INSTALL" 2>/dev/null; then
    echo "built and installed $INSTALL (signed: $SIGN)"
    echo "run: open $INSTALL    logs: ~/Library/Logs/CompanionNext.log"
else
    echo "built $APP (signed: $SIGN) — no pude instalar en /Applications"
    echo "run: open $APP    logs: ~/Library/Logs/CompanionNext.log"
fi
