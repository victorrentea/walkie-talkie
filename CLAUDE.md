# Walkie Talkie — rules

A macOS overlay that relays Victor's dictation — **Wispr Flow's microphone since 2026-09-12**,
a local Whisper behind it — into a bound terminal, a Claude Code session it spawns, or the caret.
`README.md` says what it is and how it works.

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
  | `dictation-source.md` | `DictationSource`, `WisprFlowSource`, `LocalWhisperSource`, `tools/wispr-test.sh` |
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
- **Dependencies:** **Wispr Flow** (the default source — the relay drives it by posting its own
  shortcuts and reads its delivery; it does not launch it). For the retired local source,
  `mlx_whisper` (`pip install mlx-whisper`) and `ffmpeg`; the model is
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
| `GET /engine` | which **source** is live, whether it is ready, whether the wrap is on **and in which mode** (`wrapMode` · `wrapWhy` · `scratchpadChord`), and the local model's state |
| `POST /test/dictation` `{"text": …}` | a fabricated transcript, entering exactly where a real one does (pastes `caretLine` in Replace Wispr) |
| `POST /test/selection` `{"text": …}` | file a highlight as though he had made one — it enters at `fileSelection`, so the offset, the window reading and the frozen-slot rule all run; 409 outside a dictation. The one attachment otherwise unreachable from a desk |
| `POST /test/dictation/start` | open a dictation without talking, so shot offsets have a zero (a caret one in Replace Wispr) |
| `POST /test/spawn` · `/test/spawn-folders` | a spawn from a desk; the folder menu on its own |
| `POST /test/replace-wispr` `{"on": true}` | the mode behind the forward button |
| `POST /test/wispr` `{"on": true}` | pretend Wispr Flow opened (or closed) the microphone — the ⚡ ring, the chevrons and the ✕'s cancel, without dictating into another app |
| `POST /test/wispr` `{"hotkey": true}` | pretend Wispr's *start gesture* was pressed — the whole dictation opens here, and the microphone edge only confirms it |
| `POST /test/wispr-handsfree` | post the **real** chord (fn ⌃ Space) — a real Wispr dictation starts, and the relay's own state machine is driven with it (this app's posts are stamped out of its own tap since 2026-09-13, so the chord no longer comes back as Victor's). A second call is the toggle's stop. Installed build only: `.build/debug` has no Accessibility grant and `CGEventPost` fails silently |
| `POST /test/key-trace` `{"on": true}` | log every keyboard event and its verdict (`passed` / `SWALLOWED by <branch>`), with keycode and posting pid only — the answer to *who is eating his keystrokes*. Same as `WT_KEY_TRACE=1` |
| `POST /test/scratchpad/park` | move Wispr's Scratchpad window to its corner now — smallest size Wispr allows, bottom-right of the second display (the main one's when there is one), all but an 8 pt sliver off the edge; answers the frame it ended up at |
| `POST /test/wrap-mode` `{"mode": "scratchpad"｜"sink"｜"off"｜"auto"}` | pick how the relay takes Wispr's words for this run; `auto` hands the decision back to the tick and to Wispr's own configuration. The menu tick follows |
| `POST /test/wispr` `{"historyRoute": true}` | make Wispr's `History` row the **delivery** rather than the late fallback: `formatted` delivers at once with no `pasteGrace`, the text comes from `pastedText` **or `formattedText`**, always as `.route`. Default off; `WT_WISPR_HISTORY_ROUTE=1` |
| `POST /test/wispr-state/simulate` `{"steps": […]}` | **the state machine's unit test** — a fresh `WisprState` with a fake clock, driven by a scripted sequence (`{"input": "chord"｜"stop"｜"poll"｜"notify"｜"row"｜"timeout"｜"reset", "on": …, "status": …, "atMs": …}`), answering with its transitions, the final phase and the two lags. Touches nothing in the running relay |
| `GET /test/wispr-notes` · `POST /test/wispr-notes` `{"since": <unix s>}` | Wispr Flow's **Scratchpad**, read-only (`WisprNotes`, `Notes` + `NoteVersions`): the GET is the baseline before the chord, the POST the delivery read after it (`{"note": null}` when nothing was written since). Wired to no gesture — the reading half of the candidate wrap |
| `POST /test/wispr-scratchpad` `{"down": true}` · `{"up": true}` · `{"tap": true}` | Wispr's *Open Scratchpad* chord — **held** between two calls (per Wispr's docs: tap opens/closes the window, hold is push-to-talk **into the Scratchpad**, double-tap is hands-free into it). Read from `prefs.user.shortcuts` by action name at call time; fallback **`79` (F18)** — a single key, because a held ⌘⌥ would hijack every key Victor presses for the length of a sentence — `WISPR_SCRATCHPAD_KEYS` overrides (the same variable `helpers/wispr_loopback.py` reads); modifiers carry their device-dependent right-hand bits; a **120 s dead-man's switch** releases a hold nobody came back for |
| `POST /test/input` `{"name": "…"}` | point the **system's** default input at a device (substring match) and say what it was; with no name it only reports. For `tools/wispr-test.sh` |
| `POST /test/cancel` | the ✕'s cancel: kill the dictation in flight, whichever app is holding the microphone |
| `POST /test/recover` | recover the cancelled dictation |
| `POST /test/gesture` `{"name": "forward-left"}` | post the ⌃⌥⌘F-key chord Options+ makes for **one mouse gesture**, so `HotkeyTap`'s gesture branch runs as for his hand. `forward-click/-right/-left/-up/-down`, `back-click/-right/-left/-up/-down`; 400 lists them. The F7 **bind** sub-case needs a real held left button (`leftIsHeld` asks the window server) and is not fakeable — `forward-click` is always the caret dictation |
| `GET /test/state` | everything an assertion needs, read-only: `listening` · `settling` · `speculative` · `capturing` (the swallow window) · `isRecording` (the source's microphone) · `phase` / `phaseStatus` (source-agnostic, `DictationPhase`) · `wispr` (`{state, since, status, row, lags:{pollMs, notifyMs}, transitions}`) · `wrapMode` / `wrapWhy` · `relayStarted` / `startedMode` / `intercepting` · `scratchpadWindowOpen` · `scratchpad` (`{windowOpen, frame, parkedFrame, minimumSize, everBecameKey, lastKeyAt, opens, reopenedElsewhere, screens}`) · `historyRoute` · `ringUp` · `chip` (the rows as strings) · `pasteMode` / `atCaret` / `spawnPending` / `awaitingBind` / `bound` · `historyRow` · `source` · `wrapWispr` · `sinkOpen` · `scratchpadHeld` · `sessionFlags` (the modifiers the window server believes are held) · `keyTrace` · `keyRedirect` (`{armed, pid, keys, passed}`, per dictation) · `lastRingDown` (why the **ring** went) · `lastSettled` (why the **wait** ended) · `lastDelivery`. ISO-8601 with ms |
| `POST /test/sink` `{"on": true}` · `GET /test/sink` · `POST /test/sink/clear` | **the relay's own window, as the key window** — `WisprSink`: 40×20, borderless, bottom-left corner, an instrumented `NSTextView` inside. The GET answers *did anything land in it, and by which route*: `paste` (⌘V), `ax:…` (an Accessibility write, with the setter's name), `typed`, `keyDown`, plus `key` and `previousApp` |
| `POST /test/sink` `{"key": true}` · `{"restore": true}` | take the keyboard (remembering whose it was) / hand it back, window left open. The two calls answered the question they were built for (2026-09-13, 3/3): **Wispr picks its insertion target at the END** — taking key 1–5 ms after the stop chord is enough, and the row's `app` column named the relay although TextEdit was in front the whole dictation |
| `POST /test/rebind-panel` `{"query": …}` | put the *Rebind to…* panel up mid-screen, field filled in (again to close) |
| `POST /test/resume-session` `{"session": …, "directory": …}` | ⏎ on a closed session's row — `claude --resume` in a spawned window |
| `GET /ping` · `POST /pick` | the Chrome extension's mailbox; 503 outside a dictation |

`/bind`, `/unbind` and `/target` are not gated on `dictating`. `/test/dictation` enters below the
recogniser and says nothing about it; `/test/dictation/start` opens no microphone, so the halo
sits at rest there.

- **`WisprSink` is the one deliberate exception to *nothing in it ever calls `NSApp.activate`*** (2026-09-13).
  It has to *be* the key window — the question it answers is what an ordinary key window would have
  received — so opening it activates the app and takes the keyboard, remembering the frontmost app and
  the focused element so `restoreFocus()` can put both back. It is not bindable (it is not a terminal)
  and never appears in `docs/states/` (`snapshot` photographs `root`, it does not enumerate the app's
  windows).
- **The sink is NOT the wrap and never will be** (Victor, 2026-09-13 evening). Measured 3/3: Wispr
  picks its insertion target at the **end**, and a window that takes the keyboard 1–5 ms after the stop
  chord receives the text — so it works, and he rejected it anyway, because stealing focus during every
  dictation is not something to do to a man who may be clicking or typing at that instant. Revoking
  Wispr's Accessibility grant was rejected for its own reason: Wispr has to go on working standalone.
  The sink stays a **test instrument** and the emergency mode, and **may not take the key window
  while a Scratchpad dictation is in flight** — `POST /test/sink {"key": true}` is refused with a
  409, because Wispr appears to choose its target from the key window and the sentence is lost.
  The wrap that shipped is Wispr's own **Scratchpad** (`POST /test/wispr-scratchpad`, held) — see
  *The dictation source* for how it runs, and the journal's *The night the wrap found its shape*
  for the three things the first measurement of it got wrong.
  The `History` row's `app` column is **not** a witness to the destination — it names the front
  app, which for every other kind of dictation is accidentally the same thing.
- **The sink cross-check only ever sees what leaks.** With the swallow armed at the **start** chord
  (2026-09-13), a correct run leaves the sink empty; it disagreed with the row 5/5 that evening only
  because Wispr's ⌘V arrived before the relay knew the microphone had shut and escaped into it.
- **`evals/test_stale_modifier.py` guards the stale-⌘ rule** (2026-09-14, its fourth occurrence):
  it parses `Sources/` and fails any function that posts a key with non-empty flags and neither
  posts a `flagsChanged` nor uses `postToPid`. `--self-test` proves it rejects the pre-`fc74df6`
  `SelectionCapture.swift`. `GET /test/state.sessionFlags` says what the window server believes is
  held right now, so a *flags are clear* check reads the truth rather than inferring it from the
  damage. The rule and its four occurrences are in `.claude/rules/area-crop.md`.
- **A dictation's `delivery` is written down now** (2026-09-13), in the outbox line and in
  `/test/state.lastDelivery`: `{"via": "wispr-cmdv" | "wispr-history" | "wispr-notes" | "pasteboard" | "local-whisper" |
  "test", "kind": "route" | "alreadyInserted" | "insertedElsewhere", "to": "terminal:ttysNNN" | "caret" |
  "spawn:<folder>" | "held", "at": ISO}`. It records and never decides — the caret, the held sentence and
  the two *somebody else inserted it* cases write no outbox line at all, and this is the only trace they
  leave.
- **`tools/wispr-loop.sh <scenario>` closes the loop on these routes** — one real Wispr
  dictation from a WAV through the virtual microphone, asserted end to end, with the
  scenarios, the preconditions and the timing table in `docs/loopback.md`.

## Gestures, current

- **Keys:** ⌘⌃B binds the terminal in front (again on the same target: unbinds), ⌘⌃D starts /
  ends a dictation, ⌘⌃P pastes the last envelope. All swallowed, autorepeat included. ⌘⌃⌥D is
  Victor Addons' dark-mode toggle.
- **Mouse:** *Use Logi Gestures* is ticked by default (2026-09-09) — the side buttons arrive
  from Options+ as ⌃⌥⌘F3…F12 and every mouse button is passed through; the wheel is untouched
  except a **drag** while dictating, which crops a screen area (2026-09-10). The chords are
  duplicated in Options+ and in `HotkeyTap`'s `VK_F3…VK_F12` and must not drift. Unticked, the
  wheel carries the whole vocabulary — `.claude/rules/mouse-gestures.md`.
- **The forward button's vocabulary (2026-09-12), in both engines:** 🔼 click = dictate **at the caret**,
  whatever is bound; 🔼 → = dictate at the **bound** terminal; 🔼 ← = cancel either; 🔼 ↑ = a new
  session. The relay starts every one of them (`startDictation`); no gesture posts Wispr's chord
  raw except 🔽 →.
- **Unbound, the app does everything it does bound** (2026-09-11, `holdsForBind`): the sentence
  is held five minutes for the bind that follows; the chip says `⏳ bind to send — ⌘⌃B`.
- **The recipient is whoever the relay is pointed at when the microphone closes.** A deliberate
  bind mid-sentence redirects the words; the 10 s poll never may.

## The dictation source (2026-09-12)

- **One interface, two recognisers.** `DictationSource` — `start` / `stop` / `cancel`,
  `didMaybeBegin` / `didBegin` / `didStopListening` / `didTranscribe` / `didEnd`, plus a `meter`
  the halo breathes on. `WisprFlowSource` and `LocalWhisperSource` implement it and
  **nothing downstream may name either of them**: the chip, the halo, the settle, the corpus and
  the destination routing read the protocol only. The Wispr path spent a month with no transcript
  in it precisely because it was a second branch nobody exercised.
- **The session row says the terminal's title** (2026-09-12): `✳ walkie-talkie — Fix the tax
  rounding` over `walkie-talkie@main` whenever the target has one (`Target.title`, refreshed on the
  10 s poll); the folder row stands where there is no terminal to ask.
- **Wispr Flow is the default and every gesture goes through it** — ⌘⌃D, the wheel, the side
  buttons, *Start Dictation*, the spawn. `WT_SOURCE=whisper` (or the `dictationSource` default)
  picks the local model, which is **retired, not deleted**: no gesture starts it and the weights
  are no longer loaded at launch.
- **Wrap Wispr Flow** (menu tick, default **on**) picks between three *relationships with another
  app*, and `/engine` and `/test/state` say which is in force and why (`wrapMode` · `wrapWhy`):
  | mode | Wispr is told | the words come from | what it costs |
  |---|---|---|---|
  | **`scratchpad`** (default) | *Open Scratchpad*, **held** for the sentence | the `History` row at `formatted` (`via: "wispr-history"`); the note is the cross-check | nothing — no insertion, no focus moved |
  | `sink` (emergency) | the hands-free chord | the relay's own key window, taken at the **stop** (`via: "wispr-sink"`) | his keyboard, for a moment, every dictation |
  | `off` (tick off) | the hands-free chord | nobody — Wispr inserts where the focus is | the wrap |
  Automatic fallback to `sink` when Wispr has no `open_scratchpad` shortcut, and when the
  Scratchpad window will not close — both said out loud in `wrapWhy`.
- **Every switch the dictation source reads**, in one place:
  | variable | what it does |
  |---|---|
  | `WT_SOURCE=whisper` | the local model instead of Wispr Flow (also the `dictationSource` default) |
  | `WT_WRAP_WISPR=0` | the *Wrap Wispr Flow* tick off for one run |
  | `WT_WRAP_MODE=scratchpad｜sink｜off` | force the mode for one run (`POST /test/wrap-mode` at runtime, `auto` to hand it back) |
  | `WT_SCRATCHPAD_DELIVER=note` | wait for the Scratchpad note instead of delivering from the row — 2.8 s slower, kept for the day the two disagree |
  | `WT_SCRATCHPAD_REDIRECT_KEYS=0` | stop re-posting his keystrokes while Wispr's window is up |
  | `WISPR_SCRATCHPAD_KEYS=79` | override the *Open Scratchpad* chord (the same variable `helpers/wispr_loopback.py` reads) |
  | `WT_WISPR_HISTORY_ROUTE=1` | in `sink` / `off`, deliver from the `History` row rather than waiting `pasteGrace` for a ⌘V |
  | `WT_KEY_TRACE=1` | log every keyboard event the tap sees and the decision it made — keycode and posting process only, never a character. `POST /test/key-trace {"on": true}` is the same switch at runtime, because an installed app does not inherit a shell's environment |
  | `WT_WISPR_COPY_FALLBACK=1` | re-enable the `copy_last_text` (⌘⌃C) fallback — off by default, and see *Never reintroduce* |
- **Scratchpad mode, in order** (all measured 2026-09-13/14): **start from CLOSED** — a held chord
  writes a note only while the window is closed; with it open Wispr transcribes and writes **no
  note at all**, and the thing that breaks a sentence is therefore the *previous* one → **hold the
  chord** (`open_scratchpad`, read by action name, fallback `79` = F18, `WISPR_SCRATCHPAD_KEYS`
  overrides) → **park on sight** (25 ms watcher from the *chord*: the window appears at the start
  of the hold and lives for the whole sentence) → **release** and ask the close **exactly once** →
  **deliver from the row at `formatted`** → **cross-check the note** 3.5 s later.
- **The numbers:** Wispr's own round trip 320–420 ms; row `formatted` ~400–530 ms after the
  microphone closes; **words landed ~410–490 ms**; the note not readable until 2627 ms (which is
  why it is not the delivery); the window visible on the main display **17–40 ms**; closed **417–445
  ms** after the close is asked; window **layer 3**, `AXStandardWindow`, minimum **300×300**; and
  **Wispr does not remember the parked frame**, so it is parked on every open.
- **The delivery is the row, the note is the second opinion.** The note is where Wispr *pastes*;
  the row is where it writes what it heard. `WT_SCRATCHPAD_DELIVER=note` goes back to waiting for
  the note, which costs 2.8 s for a copy of the same sentence.
- **The caret paste is addressed** (2026-09-14): `DictationResult.focusPid` carries the pid of the
  app he was looking at at the chord, and `TerminalBinding.pressPaste(to:)` posts the ⌘V with
  `postToPid` straight into that application's queue — bypassing the session and therefore whoever
  holds the key focus. Nil for every other delivery, which means *whatever has the caret*;
  bound-terminal and spawn deliveries never used the focus at all.
- **The Scratchpad window is parked out of the way** (`WisprScratchpad.park`, `POST
  /test/scratchpad/park`): smallest size Wispr allows, bottom-right of the **second** display when
  one is attached, all but an 8 pt sliver past the edge. AX measures from the top left with y
  **down** where AppKit measures from the bottom left with y up.
- **The Scratchpad becomes KEY without its app becoming frontmost** (measured): a `z` typed 1.5 s
  after the stop went into Wispr's note and was delivered *inside the sentence*, with
  `frontmostApplication` reading TextEdit throughout. **Never test key focus with
  `frontmostApplication`** — use the system-wide focused element's owner. For as long as the window
  is up, every **real** keystroke is re-posted to the app he was looking at
  (`HotkeyTap.armKeyRedirect`, `postToPid`, per-key focus check, ⌘/⌃ always pass, logged by keycode
  only, 10 s ceiling from the release, `WT_SCRATCHPAD_REDIRECT_KEYS=0` to disable). **Its limit:
  it cannot manufacture a key window** — an app that is frontmost with no key window has no first
  responder and a character posted to it is dropped, which is why the same redirect lands 7/7 where
  the victim keeps its key window and 0/7 where another window holds it.
- **`WisprState` joins four witnesses**, measured on one real dictation: Wispr's `History` row
  appearing at **357 ms**, the 100 ms CoreAudio poll at **607 ms**, `WisprWatch`'s notification at
  **5590 ms** — and the chord itself as the clock. The notification is 0–6 s late and produced **no
  edge at all** in five successful runs; a witness that never saw the microphone open may not
  report it closing.
- **A dictation Victor starts himself is Wispr's** — his own keyboard chord, or 🔽→ which posts
  Wispr's chord raw. Ring only: never intercepted, never routed, no swallow and no Scratchpad.
  `relayStarted` in `/test/state` is that distinction; it ends on Wispr's row with `.silent("")`.
- **The menu's *Close Wispr Scratchpad*** does the 250 ms press by hand. Whether the relay should
  close Wispr's window for him beyond the wrap's own cycle is Victor's to decide.
- **The dictation opens on the gesture, not on the microphone.** Measured 2026-09-12: 324–674 ms
  from the chord to Wispr's microphone when warm, **5–6 s** cold. The ring, the chip, the context
  shot and the music pause all fire on `didBegin`, which the hands-free chord raises directly; the
  CoreAudio edge **confirms** and never re-opens. `speculativeGrace` is **12 s** (worst measured
  × 2). Push-to-talk (two held modifiers) is the one ambiguous gesture and raises the beacon only.
- **Three witnesses, since 2026-09-13** (`WisprState`, `DictationPhase` on the protocol): the chord,
  a **100 ms poll** of Wispr's `IsRunningInput`, `WisprWatch`'s notification, and the `History` row at
  150 ms. The notification alone is **0–6 s late and produced no edge at all in five successful
  Loopback runs**, which is where both failures of that day came from. The relay's own stop closes
  the listening phase; the edge only confirms. `beginCapture` is armed at the **start** chord, so a
  missing edge costs nothing, and `speculativeGrace` may only retract a ring for a chord that left
  **no row**.
- **The ⚡ ring is *microphone open*, and the chip carries the wait** (2026-09-13): it goes down on
  the relay's own stop gesture, the chip shows `Transcribing...` for the settle, `endSettling` logs
  `✍️ the words landed`, and a 🔼 click during the settle is a **stop or nothing**, never a new
  dictation.
- **The recipient is latched when the microphone closes**, and it is the caret when nothing is
  bound. **Wispr's own `History` row says when it is done** (`WisprHistory`, read-only, 2026-09-12
  late): the settle ends on `formatted` / `dismissed` / `empty`, and `pastedText` is delivered as
  `.insertedElsewhere` when Wispr inserted by a route the tap cannot see. `settleTimeout` 8 s
  (Wispr's p99) and `WisprFlowSource.captureTimeout` 30 s are the net behind it.
- **The corpus goes on growing.** The meter the halo breathes on writes its WAV now, and
  `VoiceCorpus.captureLocal(engine:)` files it beside Wispr's transcript as `wispr-flow`. Those
  labels have been through Wispr's formatting pass; `whisper-local` ones are raw.
- **`tools/wispr-test.sh <file.wav>`** drives one dictation end to end and prints the transcript
  and the ⚡ timings. It needs **Wispr → Settings → Microphone → Auto-detect** (Wispr's own device
  id is a salted Chromium hash and is not scriptable); it says so rather than failing silently.

## Never reintroduce

- **Pause** (gone 2026-09-01) — Disconnect is the "hand the mouse back" gesture; `holdsForBind`
  must never become a menu tick.
- **Wispr Flow's database as a recogniser or fallback** (gone 2026-08-29, restated 2026-09-12 when
  Wispr became the source). A fallback is a second *local* model. The wrap reads the **pasteboard**,
  which is where Wispr itself puts the sentence a millisecond before it presses ⌘V — public, and
  the same place `pasteText` puts its own. **The one file of Wispr's opened in `Sources/` is
  `flow.sqlite`, read-only, by `WisprHistory`** (2026-09-12, late, Victor's decision after the
  experiments): the row's `status` is the *is it done* signal, and `pastedText` is read only for a
  sentence Wispr has already inserted invisibly. Nothing else of Wispr's, and never as a recogniser.
- **`copy_last_text` (⌘⌃C) as a routine transcript path** — off by default since the hour it was
  written. It hands back *the last text Wispr produced*, which after a failed sentence is the
  **previous** one, and delivering a five-minute-old paragraph as though he had just said it is
  worse than losing the sentence. `WT_WISPR_COPY_FALLBACK=1` for whoever wants to work on it.
- **Taking Victor's focus as the *primary* wrap** (2026-09-13). The sink works — 3/3, Wispr picks
  its insertion target at the end and a window taking the keyboard 1–5 ms after the stop chord
  receives the text — and it is the **emergency** path, not the default: a dictation helper whose
  ordinary behaviour is to interrupt a man who may be clicking or typing is one he cannot leave
  running. For the same shape of reason, **never revoke Wispr's Accessibility grant** to stop it
  inserting: it works, and it breaks Wispr as a standalone tool, which it has to go on being.
- **Wispr's dismiss as a way to stop a paste already decided.** Measured 2026-09-13: the window
  between `formatted` and the ⌘V is **57 ms**, and a ⌃Escape posted after `formatted` does not
  stop the paste at all. There is no *cancel the insertion* — only *do not ask for one*, which is
  what the Scratchpad is.
- **Minimizing or hiding Wispr's Scratchpad mid-dictation** (2026-09-14). `AXMinimized = true` the
  moment the window appears and the dictation **never comes back** — no `formatted`, no delivery,
  no ring down. Wispr needs that window live; the precondition is *closed at the start*, not
  *absent during*. Hiding the application is the same move and is expected to do the same thing.
- **Asking the Scratchpad close twice.** It is a **toggle**: a second tap behind the first closes
  the window and opens it straight back up — `wrap-cancel` left `['Status', 'Scratchpad']` behind
  for exactly that reason. `armCloseOnSight` is idempotent and claims `scratchpadWindowHandled`.
- **Arming a capture from the CoreAudio edge** (2026-09-13). It is 0–6 s late and sometimes silent
  altogether, and everything armed from `edge(false)` — the swallow, the row poll, the settle —
  simply never ran; a 2.5 s dictation went straight into Word with the relay blind to it. Arm at
  the **start chord**.
- **`open -a "Wispr Flow"`** — LaunchServices resolves the name to the nested Accessibility helper
  at `…/Contents/Resources/swift-helper-app-dist/Wispr Flow.app`, which quits itself when it has no
  parent, and `pgrep -x "Wispr Flow"` matches it too. Use `open "/Applications/Wispr Flow.app"` and
  match the anchored executable path.
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
