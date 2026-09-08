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
# Remembered across the wipe so the icon caches are only kicked when the picture
# actually changed — see the note beside `dock.iconcache` at the end of the file.
OLD_ICON_SUM="$(shasum -a 256 "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null | cut -d' ' -f1 || true)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$BIN" "$MACOS/$APP_NAME"

# The local-Whisper engine shells out to this. It goes in Resources so an
# installed app is self-contained; LocalWhisper.helperPath looks here first and
# falls back to <repo>/helpers for a `swift build` run, so both work unswitched.
mkdir -p "$CONTENTS/Resources"
cp "$DIR/helpers/whisper_helper.py" "$CONTENTS/Resources/whisper_helper.py"
# The spawn menu's recent-projects half is measured by this one, run in the
# background at most once a day. `RecentProjects.helperPath` looks here first and
# falls back to <repo>/helpers, exactly as the whisper helper does.
cp "$DIR/helpers/recent_projects.py" "$CONTENTS/Resources/recent_projects.py"

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
#
# The tiles are **inset to Apple's icon grid** — 790 across a 1024 canvas for a
# circular icon — rather than scaled to fill, which is what a plain `sips -Z`
# loop did until 2026-09-07 and is why the Dock tile was visibly fatter than
# every icon beside it. `assets/make-appicon.swift` carries the measurements and
# the reason the padding cannot live in the artwork.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "$DIR/assets/make-appicon.swift" "$DIR/assets/walkie-bound.png" "$ICONSET"
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
    <!-- No LSUIElement here on purpose. The app is a regular app since
         2026-09-07 so it has a Dock tile with a running dot, which is the only
         option-click -> Force Quit there is when it hangs. The reasoning is in
         main.swift. (No backticks in this heredoc: it is unquoted, so the shell
         would run them.) -->
    <key>NSAccessibilityUsageDescription</key>
    <string>Walkie Talkie needs Accessibility to read the selected text and to listen for its global shortcuts.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Walkie Talkie records your dictation so it can transcribe it locally and relay it to your coding agent.</string>
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

# **And touching it is not enough for the Dock.** Measured on 2026-09-07, when
# the icon was inset to Apple's grid: the installed `.icns` was the new one and
# `NSWorkspace.iconForFile:` served the new one, while the Dock went on painting
# the old picture across a `killall Dock` — because the tile it draws comes from
# `com.apple.dock.iconcache` in the darwin user cache dir, which **survives a
# Dock restart**. Deleting that file and restarting is what actually repaints it,
# verified by capturing the Dock and measuring the tile (72px against a
# neighbour's 76, i.e. the circle slot, where before it was the full tile).
#
# Only when the picture changed: a Dock restart is a visible flicker and this
# script runs on every build. The old checksum was taken before the wipe above.
NEW_ICON_SUM="$(shasum -a 256 "$CONTENTS/Resources/AppIcon.icns" | cut -d' ' -f1)"
if [ "$OLD_ICON_SUM" != "$NEW_ICON_SUM" ]; then
    rm -f "$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache"
    killall Dock 2>/dev/null || true
    echo "   icon changed — cleared the Dock icon cache and restarted it"
fi

echo "✅ Installed $APP_DIR (built $(date '+%b %-d, %H:%M'))"
