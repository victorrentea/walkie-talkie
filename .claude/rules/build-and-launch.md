---
paths:
  - "build-app.sh"
  - "Sources/WalkieTalkie/main.swift"
  - "Sources/WalkieTalkie/SingleInstance.swift"
  - "assets/**"
---

# Build, install and launch

Rules for `build-app.sh`, the icon it generates from `assets/`, what `main.swift` does before
`NSApplication.shared`, the single-instance and restart discipline, and the two places the old
name `wispr-relay` survives.
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## Diagnosing a stale bundle

- **Read the bundle, not the repo, when a fix "did not take":
  `find "/Applications/Walkie Talkie.app" -type f`.** On 2026-08-28 three faults were reported
  separately — ⌘⌃D no longer bound a terminal (macOS's "look up in dictionary" took it), Local
  Whisper refused with `cannot import mlx_whisper`, the menu bar showed an old glyph — and had one
  cause: the installed app predated three commits (`e635128`, `584ecd2`, the icon assets) while the
  working tree was clean at HEAD. The ⌘⌃D one looks exactly like an OS shortcut winning a fight; it
  isn't — **nobody was claiming the key**. A Resources folder without `walkie-idle.png` dates the
  build older than the icons.
  → journal: *A stale bundle in /Applications is three bugs at once*
- **Source mtimes lie.** `build-app.sh` copies with `cp`, so every file in the bundle carries the
  *install* time whatever its contents. The build stamp in the menu exists because "am I running
  what I just built?" had no answer anywhere in the app.
  → journal: *A stale bundle in /Applications is three bugs at once*

## Never launch the installed app by its executable path

- **`open "/Applications/Walkie Talkie.app"` — never
  `"/Applications/Walkie Talkie.app/Contents/MacOS/Walkie Talkie"`**, however much easier the
  second makes reading the log on stdout. macOS keys a privacy grant to a bundle identifier only
  for a process it launched itself; one started by its own path is attributed to the **path**, as a
  second, unrelated application. Found 2026-09-08 with two already on this Mac:

  ```
  kTCCServiceScreenCapture | ro.victorrentea.wispr-relay                              | 0 | 2026-08-15
  kTCCServiceScreenCapture | /Applications/Walkie Talkie.app/Contents/MacOS/Walkie…   | 1 | 2026-09-08
  kTCCServiceAppleEvents   | ro.victorrentea.wispr-relay            → com.apple.Terminal | 0 | 2026-08-15
  kTCCServiceAppleEvents   | /Applications/Walkie Talkie.app/Contents/MacOS/Walkie…  → com.apple.Terminal | 1 | 2026-08-28
  ```

  `client_type` is the whole story: `0` is a bundle id, `1` is a path. System Settings showed
  **two rows both called "Walkie Talkie"**, one with the app's icon and one with the generic
  `exec` icon, each holding Screen Recording of its own — and each revocable independently, so the
  app can lose Screen Recording while a checkbox next to its name is still ticked.
  → journal: *Never launch the installed app by its executable path*
- **The rows are indistinguishable in the UI; the query is the diagnostic.**
  `/Library/Application Support/com.apple.TCC/TCC.db` for Screen Recording and Accessibility,
  `~/Library/Application Support/com.apple.TCC/TCC.db` for Automation and the microphone — readable
  with `sqlite3` from a terminal with Full Disk Access, **neither writable** without root, and
  `tccutil reset` takes a bundle identifier so it cannot name a path row. **Removing one is a click
  in System Settings** (select the row, press `−`), the only route there is.
  → journal: *Never launch the installed app by its executable path*
- **`main.swift` makes it structurally impossible: `relaunchThroughLaunchServicesIfNeeded()`
  runs before `NSApplication.shared` is so much as touched.** If the parent is not launchd (pid 1)
  **and** the executable sits inside a `.app`, it re-execs the bundle through `open -n -a … --args`
  and exits, having asked macOS for nothing. `WT_ALLOW_DIRECT=1` overrides it.
  → journal: *Never launch the installed app by its executable path*
- **Development runs are untouched** — that is why the test is the bundle, not the parent alone:
  `swift build` puts the binary in `.build`, which is not a `.app` and has no bundle identity to be
  mistaken for. `RELAY_SHOOT` and `docs/shoot-overlay-states.sh` run exactly as before.
  → journal: *Never launch the installed app by its executable path*

## The app icon and the build stamp

- **The icon is generated at build time from `assets/walkie-bound.png` (the device in its orange
  ring) by `assets/make-appicon.swift` + `iconutil` — never a committed `.icns`.** The PNG stays
  the single source of truth; the ring is what makes the icon findable at 32 px in a folder of a
  hundred (*"iconul app sa fie cu cercul portocaliu in jur, ca originalul"*, 2026-08-28). The
  bundle is `touch`ed afterwards or Finder and the Dock keep serving the cached old picture.
  → journal: *The app icon and the build stamp*
- **Touching the bundle is not enough for the Dock: delete `com.apple.dock.iconcache` (darwin
  user cache dir) and restart the Dock — only when the `.icns` checksum changed.** Measured the
  day the grid inset landed: the installed `.icns` and `NSWorkspace.iconForFile:` were new while
  the Dock went on painting the old tile across a `killall Dock`; that file survives a Dock
  restart. A Dock restart is a visible flicker and the script runs on every build, hence the
  `shasum` compare. Verified by capturing the Dock: 72 px against a neighbour's 76.
  → journal: *The app icon and the build stamp*
- **The tiles are inset to Apple's icon grid: 790/1024.** `sips -Z` scales to *fill* and the PNG
  fills its canvas corner to corner, so until 2026-09-07 the ring was drawn at the full Dock slot
  and read visibly fatter than its neighbours (spotted in the Dock and ⌘-Tab). Measured on this
  Mac, not taken from the HIG: Finder's and Chrome's bodies are **824** across on a 1024 canvas
  (80.5 %; the 83.6 % an alpha bounding box reports is drop shadow), and a **circle** gets the
  smaller slot, **790** (77.1 %), because at equal width a disc reads as the larger object. Victor
  Addons, circular, sits at 77.0–78.1 %.
  → journal: *The app icon and the build stamp*
- **The padding cannot live in the artwork.** `walkie-bound.png` is *also* the 19 pt menu bar
  icon, which has no grid and must not be inset. One source of truth, two framings.
  → journal: *The app icon and the build stamp*
- **Swift, not a `sips` loop and not Python.** `sips` cannot pad with transparency (`--padColor`
  takes an opaque RGB triple); CoreGraphics from Python needs PyObjC, which `/usr/bin/python3` does
  not have; the Swift toolchain is already a hard dependency of `build-app.sh`.
  → journal: *The app icon and the build stamp*
- **The build stamp is the executable's own mtime, not a constant stamped into the source.**
  Addons seds a `BUILD_TIME` literal into a tracked Swift file on every build, which dirties the
  tree and lands in commits as noise; the file date says the same thing for free, cannot go stale,
  and works for a plain `swift build`. Read once a session, on the About row.
  → journal: *The app icon and the build stamp*

## Activation policy and the Dock tile

- **The app is `.regular` since 2026-09-07 — `setActivationPolicy(.regular)` in `main.swift`, no
  `LSUIElement` in the plist `build-app.sh` writes.** The Dock tile is the escape hatch: ⌥-click →
  **Force Quit** is the gesture his hands know, and an `.accessory` app's only ways out of a hang
  were Activity Monitor or a `pkill` in a terminal — possibly the very terminal the relay was
  typing into (2026-09-07, the deadlock).
  → journal: *The Dock tile is the escape hatch*
- **Nothing calls `NSApp.activate`.** The overlay is a `.nonactivatingPanel`, the About row and
  the Prompt Log open pages in the browser rather than modals. The one change is that a click on
  the tile makes the app frontmost — so `main.swift` installs a minimal main menu (About, Hide,
  Quit ⌘Q); a `.regular` app with no `mainMenu` shows an empty menu bar, which reads as a broken
  app.
  → journal: *The Dock tile is the escape hatch*
- **The "never becomes key" comments (`SpawnFolderMenu`, `RelayWindow`, `AboutPage`) are still
  right in spirit.** Each is about a mouse monitor or a click-through: the app is never frontmost
  *by its own doing*, so every click still arrives at a background app and counts as a first click.
  Clicking the Dock tile is the deliberate exception, ending in Force Quit or ⌘Q.
  → journal: *The Dock tile is the escape hatch*

## The bundle id and the legacy home

- **The bundle id stays `ro.victorrentea.wispr-relay`** — and with it the Caches path and the
  dispatch-queue labels. macOS keys Accessibility, Screen Recording and the microphone to that
  string plus the signing identity; changing it costs three grants re-ticked by hand on an app
  whose job is to be running before Victor starts talking. `build-app.sh` says so beside the line,
  because it is exactly the inconsistency a later reader would tidy up.
  → journal: *The rename, and the two places the old name survives*
- **`~/.wispr-relay` is merged into `~/.walkie-talkie` on first launch (`Outbox.adoptLegacyHome`)
  — a merge, not a rename.** It holds the voice corpus, 300 MB of Victor's speech paired with
  transcripts, the one thing that cannot be regenerated. The VS Code extension and the skill's
  `install.sh` create `~/.walkie-talkie/` before the first renamed relay runs, so a rename-if-absent
  would have skipped itself forever. Each entry moves only when the destination lacks one of that
  name; directories present on both sides are merged one level down; nothing is overwritten.
  → journal: *The rename, and the two places the old name survives*
- **A `--home` override skips the merge, checked rather than assumed.** Without the guard a test
  instance would drag the real corpus into a scratch directory.
  → journal: *The rename, and the two places the old name survives*
- **`IDEBridge` reads both registries** — an extension host keeps the code loaded when its window
  opened, and an unreloaded window would otherwise fall back to a blind paste.
  → journal: *The rename, and the two places the old name survives*

## Restarting the installed app

- **There is never more than one overlay: `SingleInstance.enforce()` terminates every other copy
  (by bundle id, or by executable path for a copy out of `.build`) and waits for it to go.** Two
  would tap the same shortcuts, open the microphone on the same gesture and relay into different
  outboxes. The newest launch wins.
  → journal: *The overlay's states are photographed, and the page is part of the change*
- **`./relay-restart.sh` and `docs/shoot-overlay-states.sh` stand the installed app down through
  `SingleInstance` and put it back — and both obey Victor's rule:** *"niciodată să nu mai dai
  restart la Walkie Talkie … în dictare — oprești și aștepți să se termine dictarea, să se
  livreze, abia apoi faci restart"*, then *"legat dar nu în dictare poți să-l restartezi totuși,
  ideal ar fi să-l re-legi la același terminal automat"*. A dictation in flight is a stop; a
  binding is a thing to put back. It cost one on 2026-09-09, when the shoot script restarted the
  app while he was bound.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **Both facts come from `~/.walkie-talkie/bound-tty`, read before anything stands the app down**
  (launch clears it): absent unbound, `ttysNNN` bound, `ttysNNN listening` while the microphone is
  open. One `cat`, written from the two switches that own those facts.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **Wait six seconds after the row stops saying `listening`.** The microphone closing is not the
  end of the sentence: the decode and the held panel deliver the words.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **The restore addresses a tty (`POST /bind {"tty"}`), never the front window, never a toggle,
  no flight, no flash.** At the end of a build the frontmost window is whatever the build was
  watched in.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **The retry waits ten seconds for an answer (`curl -m 10`), not one.** A bind is one to two
  `osascript` round trips and the route answers only when finished; `-m 1` timed out on a bind that
  had **succeeded**, the loop bound again and again — seven re-binds over 70 seconds after one
  restart, one stealing a binding Victor had made by hand, another redirecting a caret dictation.
  The retry is for a port not open yet, which fails in milliseconds; it must never fire against a
  bind still running.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*
- **A `.keystroke` target has no tty and cannot be restored**; the script says so and the app runs
  either way.
  → journal: *Restarting keeps the binding, and never interrupts a sentence (2026-09-09)*

## Do not

- Do not launch `/Applications/Walkie Talkie.app` by its executable path, and do not remove
  `relaunchThroughLaunchServicesIfNeeded()` from in front of `NSApplication.shared`.
- Do not commit an `.icns`, put grid padding into `walkie-bound.png`, or replace the Swift icon
  script with `sips`.
- Do not sed a build time into a tracked source file.
- Do not change the bundle id `ro.victorrentea.wispr-relay`.
- Do not turn `adoptLegacyHome` into a rename-if-absent, and do not let it run under `--home`.
- Do not restart the installed app while `bound-tty` says `listening`, and do not restore a
  binding with a one-second curl timeout.
