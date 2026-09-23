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
# **The identity macOS keys every privacy grant to.** The old name, on purpose —
# see the comment beside `CFBundleIdentifier` in the Info.plist below. It lives in
# a variable because three places have to agree about it: the plist, the
# `--identifier` codesign is given, and the check that refuses to install a bundle
# where they do not.
BUNDLE_ID="ro.victorrentea.wispr-relay"
FINAL_APP="/Applications/$APP_NAME.app"

# **Two builds must not assemble into /Applications at the same time.** On
# 2026-09-21 two of them did — three worktrees of this repo exist and each has this
# script — and what was left in /Applications was a bundle with **no Info.plist**:
# files from both runs, a signature made halfway through the other's copying. An
# app with no Info.plist has no bundle identifier, so TCC stopped recognising it as
# `ro.victorrentea.wispr-relay` and attributed it to its **executable path**
# instead, as a second unrelated application with none of the grants. The symptom
# was the whole app going dead — `accessibility trusted=false eventTap=false`, no
# hotkey, no gesture — with the Accessibility checkbox still ticked next to a row
# called "Walkie Talkie".
#
# Two things stop it now, and the second is the one that matters:
#
#  1. a lock, so the second run says so and leaves rather than interleaving;
#  2. **the bundle is assembled somewhere else and swapped in whole at the end**,
#     so /Applications never holds a half-built app for the two minutes assembly
#     takes. Last writer still wins if the lock is somehow bypassed — but what it
#     wins with is a complete, signed, verified bundle.
#
# `shlock` writes the pid and rejects a lock whose process is gone, so a build
# killed mid-flight does not wedge the next one.
LOCK="${TMPDIR:-/tmp}/walkie-talkie-build.lock"
if ! /usr/bin/shlock -f "$LOCK" -p $$; then
    echo "⛔ another build-app.sh is running (pid $(cat "$LOCK" 2>/dev/null | tr -d ' ')) — not touching $FINAL_APP" >&2
    echo "   wait for it to finish, or remove $LOCK if that pid is gone." >&2
    exit 1
fi

# Staged **inside /Applications** so the swap at the end is a rename on the same
# filesystem rather than a copy: hidden, prefixed, and removed by the trap however
# this script leaves.
STAGE="/Applications/.$APP_NAME.app.build-$$"
APP_DIR="$STAGE"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
# `$STAGE` and not `$APP_DIR`: the swap at the end repoints `APP_DIR` at the
# installed app, and a trap reading it then would delete the very thing this
# script just installed. `$STAGE` is emptied by the swap instead.
cleanup() { [ -n "$STAGE" ] && rm -rf "$STAGE"; rm -f "$LOCK"; return 0; }
trap cleanup EXIT

echo "Building WalkieTalkie (release)…"
cd "$DIR"
swift build -c release

BIN="$DIR/.build/release/WalkieTalkie"
[ -x "$BIN" ] || { echo "❌ build produced no binary at $BIN"; exit 1; }

echo "Assembling $APP_NAME.app…"
# Remembered across the wipe so the icon caches are only kicked when the picture
# actually changed — see the note beside `dock.iconcache` at the end of the file.
OLD_ICON_SUM="$(shasum -a 256 "$FINAL_APP/Contents/Resources/AppIcon.icns" 2>/dev/null | cut -d' ' -f1 || true)"
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
# The search field on `Rebind to…` runs this one, on a pause in his typing, over
# Claude Code's session journals. Same two-place lookup as the two above.
cp "$DIR/helpers/session_search.py" "$CONTENTS/Resources/session_search.py"

# The menu bar item's two faces: the device alone at rest, the full icon with its
# ring once the relay is pointed at a terminal. Copied rather than declared as SPM
# resources because this target has none — the bundle is assembled here.
cp "$DIR/assets/walkie-idle.png" "$CONTENTS/Resources/walkie-idle.png"
cp "$DIR/assets/walkie-bound.png" "$CONTENTS/Resources/walkie-bound.png"

# The caret halo's film: 25 frames of the ring, packed five across, keyed off
# black. Same reason as above — no SPM resources on this target, so the bundle is
# assembled by hand. `CaretHalo` also finds it in `assets/` when the binary is
# run straight out of `.build`, which is how the contact sheet and the demo run.
cp "$DIR/assets/caret-halo-5x5.png" "$CONTENTS/Resources/caret-halo-5x5.png"
# The halo preview's voice: one clip of his own, copied out of the corpus (see
# `ClipVoice`). Never played aloud.
cp "$DIR/assets/halo-voice.wav" "$CONTENTS/Resources/halo-voice.wav"
# The voice-halo page, which the halo runs whole in a web view (`HaloPage`):
# vendored from a pinned tag of the sibling repo by `tools/vendor-voice-halo.sh`
# (a no-op without the sibling — the committed copy is what ships), then copied
# beside the MilkDrop engine and its preset packs (`assets/milkdrop`, where
# `butterchurn.min.js` is dropped in by hand). Bundled so the halo works on a
# plane; `HaloPage` finds the folder here or in `assets/` from a `.build` binary.
"$DIR/tools/vendor-voice-halo.sh"
rm -rf "$CONTENTS/Resources/voice-halo" "$CONTENTS/Resources/milkdrop" "$CONTENTS/Resources/projectm"
cp -R "$DIR/assets/voice-halo" "$CONTENTS/Resources/voice-halo"
cp -R "$DIR/assets/milkdrop" "$CONTENTS/Resources/milkdrop"
# The native engine's presets (`ProjectMHalo`, the `projectm` branch); the engine
# itself is linked statically, so nothing else has to travel with the app.
cp -R "$DIR/assets/projectm" "$CONTENTS/Resources/projectm"

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
    <string>$BUNDLE_ID</string>
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

# **Nothing is installed until the bundle answers for itself.** Each of these was
# false of what sat in /Applications on 2026-09-21, and each is invisible from the
# outside — the app launched, showed its icon and its menu, and silently had no
# identity for macOS to hang a privacy grant on. A build that cannot pass them
# leaves the working app where it is and says which line failed.
#
# The plist is checked *before* signing and not only after: codesign's own verdict
# on a bundle without one is "bundle format unrecognized, invalid, or unsuitable",
# which names neither the file nor the reason.
fail() { echo "❌ $1" >&2; echo "   $FINAL_APP left untouched." >&2; exit 1; }

[ -f "$CONTENTS/Info.plist" ] || fail "the assembled bundle has no Contents/Info.plist"

PLIST_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist" 2>/dev/null || true)"
[ "$PLIST_ID" = "$BUNDLE_ID" ] || fail "Info.plist says CFBundleIdentifier=$PLIST_ID, expected $BUNDLE_ID"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    if security find-identity -v -p codesigning | grep -Fq "Victor Addons Local Code Signing"; then
        SIGNING_IDENTITY="Victor Addons Local Code Signing"
    fi
fi

# **`--identifier` is passed rather than inferred.** Left to itself codesign reads
# the identifier out of `Contents/Info.plist` and falls back to the executable's
# **file name** when it cannot — which is how the broken bundle of 2026-09-21 came
# to be signed as `Identifier=Walkie Talkie`. Saying it out loud means a plist that
# went missing can no longer be signed over in silence; the check below then
# refuses the install outright.
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --identifier "$BUNDLE_ID" --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "   signed with: $SIGNING_IDENTITY"
else
    echo "⚠️  No stable identity; ad-hoc signing (Accessibility will re-prompt after rebuilds)."
    codesign --force --identifier "$BUNDLE_ID" --sign - "$APP_DIR"
fi

# And what the signature actually came out as:
codesign --verify --deep --strict "$APP_DIR" 2>/dev/null \
    || fail "the signature does not verify (a resource was added or changed after signing)"

SIG="$(codesign -dv "$APP_DIR" 2>&1)"
echo "$SIG" | grep -Fq "Identifier=$BUNDLE_ID" \
    || fail "signed as $(echo "$SIG" | grep '^Identifier=' || echo '(no identifier)'), expected Identifier=$BUNDLE_ID"
# `Info.plist=not bound` is codesign's way of saying the plist is not sealed into
# the signature — the exact state in which TCC stops trusting the bundle id and
# falls back to attributing the app to its executable path.
if echo "$SIG" | grep -Fq "Info.plist=not bound"; then
    fail "the Info.plist is not bound into the signature"
fi

echo "   verified: $BUNDLE_ID, signature intact, Info.plist sealed"

# **The swap.** Everything above happened beside /Applications; this is the only
# moment the installed app changes, and it changes in one rename. The old bundle is
# moved aside first rather than deleted, so a failure here leaves something to put
# back instead of a hole where the app was.
OLD_ASIDE="/Applications/.$APP_NAME.app.replaced-$$"
if [ -e "$FINAL_APP" ]; then
    mv "$FINAL_APP" "$OLD_ASIDE"
fi
if ! mv "$APP_DIR" "$FINAL_APP"; then
    if [ -e "$OLD_ASIDE" ]; then mv "$OLD_ASIDE" "$FINAL_APP"; fi
    fail "could not move the new bundle into place"
fi
rm -rf "$OLD_ASIDE"
STAGE=""                      # installed now — the trap has nothing left to remove
APP_DIR="$FINAL_APP"
CONTENTS="$APP_DIR/Contents"

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
