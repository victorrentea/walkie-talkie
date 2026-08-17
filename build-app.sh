#!/bin/bash
# Build Wispr Relay and wrap it in a signed .app.
#
# The .app is not cosmetic: macOS keys Accessibility / Screen Recording (TCC)
# grants to a code-signing identity. A bare SwiftPM binary is ad-hoc signed and
# gets a NEW identity on every rebuild, so Victor would have to re-tick the
# Accessibility checkbox after each change. Signing the bundle with the stable
# local identity makes the grant stick.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Wispr Relay"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building WisprRelay (release)…"
cd "$DIR"
swift build -c release

BIN="$DIR/.build/release/WisprRelay"
[ -x "$BIN" ] || { echo "❌ build produced no binary at $BIN"; exit 1; }

echo "Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$BIN" "$MACOS/$APP_NAME"

# The local-Whisper engine shells out to this. It goes in Resources so an
# installed app is self-contained; LocalWhisper.helperPath looks here first and
# falls back to <repo>/helpers for a `swift build` run, so both work unswitched.
mkdir -p "$CONTENTS/Resources"
cp "$DIR/helpers/whisper_helper.py" "$CONTENTS/Resources/whisper_helper.py"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>ro.victorrentea.wispr-relay</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Wispr Relay needs Accessibility to read the selected text and to listen for its global shortcuts.</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    if security find-identity -v -p codesigning | grep -Fq "Victor Addons Local Code Signing"; then
        SIGNING_IDENTITY="Victor Addons Local Code Signing"
    fi
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "   signed with: $SIGNING_IDENTITY"
else
    echo "⚠️  No stable identity; ad-hoc signing (Accessibility will re-prompt after rebuilds)."
    codesign --force --sign - "$APP_DIR"
fi

echo "✅ Installed $APP_DIR"
