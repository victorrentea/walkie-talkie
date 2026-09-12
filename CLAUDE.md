# Walkie Talkie — rules

A macOS overlay that relays Victor's dictation — his own microphone, a local Whisper — into a
bound terminal, a Claude Code session it spawns, or the caret. `README.md` says what it is and
how it works.

This file holds only what every session needs. Everything else moved on 2026-09-11:

- **`docs/journal.md`** — the full engineering journal: every decision, measurement and
  reversal, in the original order, with a contents list and a *superseded* list at the top.
  Read it before re-deriving anything; the later dated section always wins.
- **`.claude/rules/*.md`** — the paid-for traps per area of the code. Each loads by itself when
  a matching file is touched:

  | rule file | loads for |
  |---|---|
  | `terminal-binding.md` | `TerminalBinding`, `IDEBridge`, `BindFlight`, `RebindHistory`, `RebindPanel`, `SessionSearch`, `helpers/session_search.py`, `UnbindPop`, `relay-restart.sh` |
  | `destinations-and-outbox.md` | `AppDelegate`, `Outbox`, `SessionLabel` |
  | `overlay-chip.md` | `RelayWindow`, `OverlayStates`, `Glyphs`, `docs/states/`, the shoot script |
  | `chip-wipe.md` | `ChipWipe` |
  | `mouse-gestures.md` | `HotkeyTap` |
  | `area-crop.md` | `HotkeyTap`, `ScreenCapture`, `Package.swift` |
  | `screenshots-and-selection.md` | `ScreenCapture`, `CaptureFlash`, `CursorMarker`, `WindowContext`, `SelectionCapture`, `evals/` |
  | `chrome-extension.md` | `chrome-extension/`, `ElementPicker`, `MusicBridge` |
  | `whisper-and-corpus.md` | `Transcriber`, `MicRecorder`, `DecodeRate`, `InputDevice`, `VoiceCorpus`, `helpers/`, `evals/` |
  | `replace-wispr-and-halo.md` | `CaretHalo`, `DropArrow`, the halo asset |
  | `spawn.md` | `SpawnTerminal`, `SpawnFolderMenu`, `ProjectList`, `helpers/recent_projects.py` |
  | `menu-bar.md` | `StatusItem`, `MenuBarMirror`, `MessageLog`, `AboutPage` |
  | `build-and-launch.md` | `build-app.sh`, `main.swift`, `SingleInstance`, `assets/` |

## UI language: English only

- **Every string the app renders is English** — title, rows, flashes, banners, every menu row,
  the Chrome extension's label, its one error string and its toolbar title. Log lines, comments
  and commit messages are unaffected. The overlay is on a projector in front of international
  rooms; a Romanian label is noise to the room at best.
- Where the strings live: `RelayWindow.swift` (`shotHint`, `recordText`, `engineText`,
  `hqBadge`, `elapsedText`, `pickHint`, `pickText`, `titleText`), the `flash(_:)` /
  `flashTitle(_:)` call sites in `AppDelegate.swift`, `StatusItem.swift` (the longest list),
  `chrome-extension/inspect.js` and `relay.js`. Rows hidden behind `showsGestureHints` still
  count — they must be English when the flag comes back.

## Build, install, restart

- **Build and install:** `./build-app.sh` — renders the icon from `assets/walkie-bound.png`,
  writes the plist, `touch`es the bundle, resets the Dock icon cache only when the `.icns`
  checksum changed. Never commit an `.icns`.
- **Restart the installed app:** `./relay-restart.sh`. It reads `~/.walkie-talkie/bound-tty`
  first, waits for a dictation in flight to finish *and deliver* (six seconds after the row stops
  saying `listening`), stands the app down through `SingleInstance`, relaunches, and re-binds the
  same tty through `POST /bind {"tty": …}` (no toggle, no flight, no flash). **Never restart
  while a dictation is running** — *"niciodată să nu mai dai restart la Walkie Talkie … în
  dictare — oprești și aștepți să se termine dictarea, să se livreze, abia apoi faci restart"*.
  A `.keystroke` target has no tty and cannot be restored; the script says so.
- **Never launch the installed app by its executable path.** `open "/Applications/Walkie
  Talkie.app"`, never `…/Contents/MacOS/Walkie Talkie`. macOS keys TCC grants to the bundle id
  only for processes it launched itself; a path launch is filed as a *second* app with the same
  name and its own Screen Recording / Automation rows. `main.swift` re-execs through
  LaunchServices when the parent is not launchd (`WT_ALLOW_DIRECT=1` overrides); `swift build`
  binaries in `.build/` are unaffected.
- **When a fix "did not take", read the bundle, not the repo:** `find "/Applications/Walkie
  Talkie.app" -type f`. Source mtimes lie (`cp`). The About row, `Victor's Walkie Talkie (<build>)`, carries the
  executable's mtime — the one place that says which build is running.
- The app is `.regular` (Dock tile — Force Quit is the escape hatch when it hangs — and a minimal
  main menu); nothing in it ever calls `NSApp.activate`.
- **Dependencies:** `mlx_whisper` (`pip install mlx-whisper`) and `ffmpeg`; the model is
  `mlx-community/whisper-large-v3-turbo` (`RELAY_WHISPER_MODEL` overrides). The Chrome
  extension is loaded unpacked by hand (`chrome://extensions` → Developer mode → Load unpacked);
  after any `manifest.json` permission change it needs a **Reload** there or the feature silently
  does nothing.

## Identity

- **The bundle id is `ro.victorrentea.wispr-relay` and stays so.** macOS keys Accessibility,
  Screen Recording and the microphone to it plus the signing identity; changing it costs three
  grants re-ticked by hand on an app whose job is to be running before Victor starts talking.
  The Caches path and the dispatch-queue labels follow it. Everything else — folder, repo, Swift
  target, `.app`, home folder — says `walkie-talkie` (renamed from `wispr-relay` on 2026-08-26).
  `build-app.sh` says so beside the line; do not tidy it.
- The app icon is generated at build time from `assets/walkie-bound.png` (the device in its
  orange ring), inset to 790/1024; the same PNG is the 19 pt menu bar icon, uninset.

## Where the data lives

- **`~/.walkie-talkie/`** — `outbox.jsonl` (the log of everything dictated; a line is written at
  *delivery*, never before), `voice-corpus/<day>/` + `corpus.jsonl` (every recording beside its
  transcript, forever — never compress lossily, nothing prunes it), `decode-rate.jsonl`,
  `bound-tty` (`ttysNNN` or `ttysNNN listening`; absent when unbound; cleared at launch and quit),
  `rebind-history.json`, `pinned-projects.json`, `ide/` (the VS Code / IntelliJ extensions'
  loopback listeners), `relay.log`. `--home` moves the outbox and the corpus.
- **`~/Library/Caches/ro.victorrentea.wispr-relay/`** — `shots/<session-stamp>/` (a staging
  area, never an archive: capped at 300 frames across sessions, purgeable), `cancelled/` (one
  WAV, five minutes), `message-log.html`. `--home` does not move these.
- `~/.wispr-relay` is **merged** (not renamed) into `~/.walkie-talkie` on first launch
  (`Outbox.adoptLegacyHome`); it holds the corpus, the one thing here that cannot be regenerated.

## Path dependency

- `Package.swift` declares `.package(path: "../victor-mac-kit")` — `CropGeometry`,
  `CropSelectionOverlay`, `CropCapture`, shared with `victor-macos-addons`. A fresh clone needs
  that sibling checkout beside it. Both apps are only ever built on this Mac, from local; that is
  the trade for editing the shared gesture and rebuilding in one step.

## The overlay's states are photographed

- **No change to the overlay is finished until `./docs/shoot-overlay-states.sh` has been run.**
  It shoots all 40 states through `RelayWindow.snapshot` (always 2×) and regenerates
  `docs/overlay-states.html`. A new state is a new `Shot` in `OverlayStates.swift`; a state that
  goes away is a deleted one. **Never edit `docs/overlay-states.html` by hand.** The script
  stands the installed app down and puts it back.
- Nothing that rides the pointer can be screenshot (`sharingType = .none`; `RELAY_CAPTURABLE=1`
  no longer works on macOS 15). Review with: the states page; `kill -USR1 <pid>` →
  `<home>/snapshot.png`; `WT_SHOOT_MENU`, `WT_SHOOT_WIPE`, `WT_SHOOT_HALO` (+ `…-arrow.png`),
  all `=<path> ./.build/debug/WalkieTalkie`; `WT_HALO_DEMO=<seconds>` (the one capturable run);
  `CGWindowListCopyWindowInfo` for geometry. `RELAY_SHOOT` runs skip every transition.

## Testing at a desk — the loopback control surface

`ElementPicker` listens on the first free port of 8917–8919 (the Chrome extension posts to all
three; `MusicBridge` is a WebSocket on 8920).

| route | what |
|---|---|
| `POST /bind` | bind the frontmost terminal; 409 if nothing bindable; on the target already bound it **unbinds** (`{"unbound": true}`) |
| `POST /bind` `{"tty": "ttys004"}` | bind that session — no toggle, no flight, no flash (the restart's restore) |
| `POST /unbind` | let the binding go |
| `GET /target` | the current binding; `guarded` says whether the shell guard applies |
| `GET /engine` | which model is loaded and whether it is ready |
| `POST /test/dictation` `{"text": …}` | a fabricated transcript, entering exactly where a real one does (pastes `caretLine` in Replace Wispr) |
| `POST /test/dictation/start` | open a dictation without talking, so shot offsets have a zero (a caret one in Replace Wispr) |
| `POST /test/spawn` · `/test/spawn-folders` | a spawn from a desk; the folder menu on its own |
| `POST /test/replace-wispr` `{"on": true}` | the mode behind the forward button |
| `POST /test/wispr` `{"on": true}` | pretend Wispr Flow opened (or closed) the microphone — the ⚡ ring, the chevrons and the ✕'s cancel, without dictating into another app |
| `POST /test/cancel` | the ✕'s cancel: kill the dictation in flight, whichever app is holding the microphone |
| `POST /test/recover` | recover the cancelled dictation |
| `POST /test/rebind-panel` `{"query": …}` | put the *Rebind to…* panel up mid-screen, field filled in (again to close) |
| `POST /test/resume-session` `{"session": …, "directory": …}` | ⏎ on a closed session's row — `claude --resume` in a spawned window |
| `GET /ping` · `POST /pick` | the Chrome extension's mailbox; 503 outside a dictation |

`/bind`, `/unbind` and `/target` are not gated on `dictating`. `/test/dictation` enters below the
recogniser and says nothing about it; `/test/dictation/start` opens no microphone, so the halo
sits at rest there.

## Gestures, current

- **Keys:** ⌘⌃B binds the terminal in front (again on the same target: unbinds), ⌘⌃D starts /
  ends a dictation, ⌘⌃P pastes the last envelope. All swallowed, autorepeat included. ⌘⌃⌥D is
  Victor Addons' dark-mode toggle.
- **Mouse:** *Use Logi Gestures* is ticked by default (2026-09-09) — the side buttons arrive
  from Options+ as ⌃⌥⌘F3…F12 and every mouse button is passed through; the wheel is untouched
  except a **drag** while dictating, which crops a screen area (2026-09-10). The chords are
  duplicated in Options+ and in `HotkeyTap`'s `VK_F3…VK_F12` and must not drift. Unticked, the
  wheel carries the whole vocabulary — `.claude/rules/mouse-gestures.md`.
- **Unbound, the app does everything it does bound** (2026-09-11, `holdsForBind`): the sentence
  is held five minutes for the bind that follows; the chip says `⏳ bind to send — ⌘⌃B`.
- **The recipient is whoever the relay is pointed at when the microphone closes.** A deliberate
  bind mid-sentence redirects the words; the 10 s poll never may.

## Never reintroduce

- **Pause** (gone 2026-09-01) — Disconnect is the "hand the mouse back" gesture; `holdsForBind`
  must never become a menu tick.
- **Wispr Flow's database** as a recogniser or fallback (gone 2026-08-29). A fallback is a second
  *local* model.
- **A typing affordance on the overlay's own surface.** The panel becomes key only while the
  transcript is being edited (`RelayPanel.wantsKey`).
- **A leash, smoothing filter or spring** on the chip's cursor-following; **a ✕ beside the
  pointer** in any state; **a border, blur or shadow** on anything that rides the pointer.
- **The denominator in a shot's name**; **the cursor mark burned into the JPEG**; **F3** as the
  shutter; the **1000 px** handover (800 is one rung above what the evals allow).
- **The corner / bottom-edge beacon** (`RecordingBeacon`, deleted 2026-09-11) — the halo round
  the pointer is the beacon now.
- **An emoji where the mouse has to be shown** — draw his mouse (`Glyphs.mouse`).

## Conventions

- Dates in headings, `(2026-MM-DD)`, mark a behaviour change. When two notes disagree, the later
  date wins; the journal's *superseded* list names the known reversals.
- A rule with a measured number behind it keeps the number. A feature that cannot be
  screenshot keeps a `WT_SHOOT_*` route, or it cannot be reviewed.
