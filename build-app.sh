#!/bin/bash
# Build Walkie Talkie and wrap it in a signed .app.
#
# The .app is not cosmetic: macOS keys Accessibility / Screen Recording (TCC)
# grants to a code-signing identity. A bare SwiftPM binary is ad-hoc signed and
# gets a NEW identity on every rebuild, so Victor would have to re-tick the
# Accessibility checkbox after each change. Signing the bundle with the stable
# local identity makes the grant stick.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Walkie Talkie"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building WalkieTalkie (release)…"
cd "$DIR"
swift build -c release

BIN="$DIR/.build/release/WalkieTalkie"
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

# The menu bar item's two faces: the device alone at rest, the full icon with its
# ring once the relay is pointed at a terminal. Copied rather than declared as SPM
# resources because this target has none — the bundle is assembled here.
cp "$DIR/assets/walkie-idle.png" "$CONTENTS/Resources/walkie-idle.png"
cp "$DIR/assets/walkie-bound.png" "$CONTENTS/Resources/walkie-bound.png"

# The Finder / Spotlight / Get Info icon, built here from the *bound* picture —
# the device inside its orange ring. It was the idle one for two days, on the
# argument that the ring means "bound to a terminal right now" and an app icon
# cannot make a claim about a live state. Victor reversed it on 2026-08-28
# ("iconul app sa fie cu cercul portocaliu in jur, ca originalul"), and the
# argument does not survive the reversal: in the menu bar the two pictures sit
# side by side and the ring is a *state*, but nothing shows the app icon beside
# its own alternative — there it is only the app's identity, and the ring is what
# makes it recognisable at 32px among a hundred other icons. Generated rather
# than committed as an .icns so the one source of truth stays the PNG: change
# that file and the app icon follows on the next build.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $spec
    sips -s format png -Z "$1" "$DIR/assets/walkie-bound.png" \
        --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <!-- **The old name, on purpose.** The app is Walkie Talkie; its identity to
         macOS is not. TCC keys Accessibility, Screen Recording and the microphone
         to this string plus the signing identity, so changing it costs three
         grants re-ticked by hand in System Settings — and it is invisible
         everywhere Victor looks. The Caches folder follows it for the same
         reason. Do not "fix" this to match the name. -->
    <key>CFBundleIdentifier</key>
    <string>ro.victorrentea.wispr-relay</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Walkie Talkie needs Accessibility to read the selected text and to listen for its global shortcuts.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Walkie Talkie records your dictation itself when the Local Whisper engine is selected, so that Wispr Flow is not in the loop at all.</string>
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

# Finder and the Dock cache an app's icon by bundle path; touching the bundle is
# what tells them the cache is stale, or the old picture survives the rebuild.
touch "$APP_DIR"

echo "✅ Installed $APP_DIR (built $(date '+%b %-d, %H:%M'))"
