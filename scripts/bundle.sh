#!/bin/bash
# Wraps the SPM binary in a .app bundle. TCC refuses to prompt for mic or
# speech without usage descriptions in an Info.plist, so voice cannot be
# tested from `swift run` alone. Signing/notarization is Wave 5.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
cd "$ROOT"
swift build -c "$CONFIG"
BUILT="$(swift build -c "$CONFIG" --show-bin-path)/companion"

# Single source of truth: the version ships in the binary, so the bundle
# reads it from Build.swift instead of keeping a copy that drifts.
VERSION="$(grep -o 'version = "[^"]*"' "$ROOT/Sources/CompanionCore/Build.swift" | cut -d'"' -f2)"
[ -n "$VERSION" ] || { echo "no pude leer Build.version" >&2; exit 1; }

# Identity per configuration. The source of truth is ProductIdentity.swift and
# a test compares the two: a plist written here that drifts installs an app
# whose own code does not recognise it. Two builds may sit on one Mac, so they
# never share a bundle id — same id means LaunchServices opens whichever it
# resolved first (the scar that named this app "Next" in the first place).
if [ "$CONFIG" = "release" ]; then
    BUNDLE_ID="com.karen.companion"
    DISPLAY_NAME="Companion"
    LOG_NAME="Companion.log"
else
    BUNDLE_ID="com.karen.companion.next"
    DISPLAY_NAME="Companion Next"
    LOG_NAME="CompanionNext.log"
fi

# The prototype owns com.karen.companion and a LaunchAgent revives it at
# login. Shipping a release next to it is the collision this whole scheme
# exists to avoid, so it stops here instead of producing a broken install.
if [ "$CONFIG" = "release" ] && [ -d "$HOME/Applications/companion.app" ]; then
    echo "el prototipo sigue instalado en ~/Applications/companion.app y" >&2
    echo "reclama $BUNDLE_ID. Corre su uninstall.sh antes de empaquetar" >&2
    echo "el release, o las dos apps se pisan en LaunchServices." >&2
    exit 1
fi

APP="$ROOT/build/$DISPLAY_NAME.app"
BIN="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$BIN" "$APP/Contents/Resources"
cp "$BUILT" "$BIN/Companion"


BINPATH="$(swift build -c "$CONFIG" --show-bin-path)"
for bundle in "$BINPATH"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

if [ -d "$ROOT/Sources/CompanionUI/Fonts" ]; then
    mkdir -p "$APP/Contents/Resources/Fonts"
    cp "$ROOT/Sources/CompanionUI/Fonts/"*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
    cp "$ROOT/Sources/CompanionUI/Fonts/"*.ttf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
    [ -f "$ROOT/Sources/CompanionUI/Fonts/OFL.txt" ] \
        && cp "$ROOT/Sources/CompanionUI/Fonts/OFL.txt" "$APP/Contents/Resources/Fonts/"
fi

# Loaded unpacked from here, so the path Settings shows survives a rebuild.
if [ -d "$ROOT/Extensions/browser" ]; then
    mkdir -p "$APP/Contents/Resources/BrowserExtension"
    cp -R "$ROOT/Extensions/browser/." "$APP/Contents/Resources/BrowserExtension/"
    rm -rf "$APP/Contents/Resources/BrowserExtension/test"
fi

[ -f "$ROOT/assets/AppIcon.icns" ] \
    && cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
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
    <key>NSAppleEventsUsageDescription</key>
    <string>Companion reads and writes the spreadsheet you have open in Excel or Numbers when you ask it to. Every write asks first and keeps a copy of the workbook.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Your city goes with each request while the city switch in Settings is on. macOS only asks for your location when you search for something nearby and Settings has no city. Companion keeps the city, never your coordinates.</string>
    <key>NSLocationUsageDescription</key>
    <string>Your city goes with each request while the city switch in Settings is on. macOS only asks for your location when you search for something nearby and Settings has no city. Companion keeps the city, never your coordinates.</string>
    <key>NSContactsUsageDescription</key>
    <string>Companion looks up a contact by name when you type @ in the island, so you can mention them. It reads names as you type and an email or phone only if you choose one, and never uploads your address book.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Companion captures the screen when you hold FN so it can see what you are looking at. One snapshot per hold, never a recording, never stored.</string>
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

# Install to /Applications: testing always opens THE app, never a stray
# build. Same path + same bundle id + same identity = TCC grants survive.
INSTALL="/Applications/$DISPLAY_NAME.app"
if rm -rf "$INSTALL" 2>/dev/null && ditto "$APP" "$INSTALL" 2>/dev/null; then
    echo "built and installed $INSTALL (signed: $SIGN)"
    echo "run: open \"$INSTALL\"    logs: ~/Library/Logs/$LOG_NAME"
else
    echo "built $APP (signed: $SIGN) — no pude instalar en /Applications"
    echo "run: open \"$APP\"    logs: ~/Library/Logs/$LOG_NAME"
fi
