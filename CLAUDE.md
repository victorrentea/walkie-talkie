# Walkie Talkie — rules

A macOS overlay that relays Victor's dictation into a bound terminal, a Claude Code session it
spawns, or the caret. Recognisers: **ElevenLabs Scribe** (default since 2026-09-19), a local
Whisper, and **Wispr Flow behind a firewall** (since 2026-09-22 evening: `HotkeyTap` drops its ⌘V,
the words come from its `History` row, the relay delivers them). `README.md` says how it works.

This file holds only what every session needs. The rest is disclosed on demand:

- **`docs/journal.md`** — every decision, measurement and reversal (contents + *superseded* list at
  the top). Read the relevant section before re-deriving anything; the later date always wins.
- **`.claude/rules/*.md`** — the paid-for traps per area; each loads when a matching file is read.
  **Read the one for your area first** when starting from a task rather than a file:

  | rule file | area |
  |---|---|
  | `dictation-source.md` | recognisers, the Wispr firewall, `History` row, Scratchpad wrap, markers, env switches |
  | `desk-testing.md` | the loopback routes (`/test/*`, `GET /test/state`) — **read before driving the app from a desk** |
  | `build-and-launch.md` | `build-app.sh`, restart gate, `QuitGate`, Dock-tile restart, bundle identity |
  | `terminal-binding.md` | `TerminalBinding`, `IDEBridge`, rebind panel, session search, `relay-restart.sh` |
  | `destinations-and-outbox.md` | `AppDelegate` routing, `Outbox`, `SessionLabel` |
  | `overlay-chip.md` | `RelayWindow`, `OverlayStates`, `Glyphs`, the states page |
  | `mouse-gestures.md` | `HotkeyTap` keys and side buttons (the full gesture table) |
  | `area-crop.md` | wheel-drag crop, **the stale-⌘ rule** |
  | `screenshots-and-selection.md` | `ScreenCapture`, `SelectionCapture`, `WindowContext`, evals |
  | `chrome-extension.md` | `chrome-extension/`, `ElementPicker`, `MusicBridge` |
  | `whisper-and-corpus.md` | `Transcriber`, `MicRecorder`, `InputDevice`, `VoiceCorpus`, `helpers/` |
  | `replace-wispr-and-halo.md` | `CaretHalo`, `DropArrow`, `PasteHint` |
  | `spawn.md` | `SpawnTerminal`, folder menu, `ProjectList` |
  | `menu-bar.md` | `StatusItem`, `MessageLog`, About |

## UI language: English only

Every string the app renders is English (projector, international rooms) — chip rows, flashes,
menus, About, the Chrome extension. Logs, comments and commits are unaffected. Strings live in
`RelayWindow.swift`, `flash(_:)` / `flashTitle(_:)` in `AppDelegate.swift`, `StatusItem.swift`,
`AboutWindow.swift`, `chrome-extension/inspect.js` and `relay.js`. Hidden rows count too.

## Build, install, restart

- **Build + install:** `./build-app.sh`. Never commit an `.icns`.
- **Restart ONLY through `./relay-restart.sh [--build]`** — never `pkill`/`kill`/`open` by hand.
  It waits until `GET /test/state.busy` is false **and** 10 s quiet after the last delivery, then
  restarts and re-binds the tty. Victor: never restart mid-dictation. `--dry-run` checks the gate.
- **Never launch by the executable path** — `open "/Applications/Walkie Talkie.app"`; a path launch
  is a second app to TCC.
- **A fix "did not take"? Read the bundle, not the repo** (`find "/Applications/Walkie Talkie.app"
  -type f`); the About row's build stamp is the executable's mtime.
- **Nothing calls `NSApp.activate`** (only the `WisprSink` test instrument).
- **Deps:** `mlx_whisper` + `ffmpeg` for the local model; the Chrome extension is loaded unpacked
  and needs **Reload** after any `manifest.json` permission change; `Package.swift` needs the sibling
  checkout `../victor-mac-kit`.

## Identity and data

- **Bundle id `ro.victorrentea.wispr-relay` stays** — Accessibility, Screen Recording and mic grants
  are keyed to it. Everything else says `walkie-talkie`. Do not tidy it.
- **`~/.walkie-talkie/`**: `outbox.jsonl` (written at delivery), `voice-corpus/` + `corpus.jsonl`
  (forever — never lossy, never pruned), `bound-tty`, `relay.log`, `elevenlabs.env`, `hangs/`.
  `--home` moves outbox, corpus and key. **`~/Library/Caches/ro.victorrentea.wispr-relay/`**: shots
  staging (≤ 300 frames), `cancelled/`, message log.

## The overlay is photographed

**No overlay change is finished until `./docs/shoot-overlay-states.sh` has run** (regenerates
`docs/overlay-states.html` — never edit it by hand). Pointer-riding windows cannot be screenshot;
use the states page, `kill -USR1 <pid>` → `<home>/snapshot.png`, or the `WT_SHOOT_*` / `WT_HALO_DEMO`
hooks (`overlay-chip.md`, `replace-wispr-and-halo.md`).

## Gestures, in one screen

- **Keys:** ⌘⌃B bind (again = unbind), ⌘⌃D dictate, ⌘⇧P re-paste the last envelope (falls back to
  the outbox after a restart). All swallowed. ⌘⌃⌥D belongs to Victor Addons.
- **Side buttons** (Options+ → ⌃⌥⌘F3…F12, duplicated in `HotkeyTap`, must not drift;
  `evals/test_gesture_spec.py` is the spec): 🔼 = prompt at the caret (full envelope); 🔼 → at the
  bound terminal; 🔼 ← cancel; 🔼 ↑ new session; 🔼 ↓ kamikaze; ◀️-held + 🔼 bind; 🔽 = plain
  dictation (words only, follows the Engine); 🔽 → Return (mid plain dictation: stop, insert, Return).
- **Unbound, everything still works:** the sentence is held 5 min for the next bind.
- **The recipient is latched when the microphone closes — which terminal, not only *not the caret*.**
  A deliberate bind mid-sentence redirects; the 10 s poll never may; a bind or unbind after the close
  changes nothing (Q2, 2026-09-26).

## Never reintroduce

- **Pause** — Disconnect is the hand-back; `holdsForBind` is never a menu tick.
- **Wispr's DB as a recogniser**, **`copy_last_text` by default**, **focus-stealing as the Wispr
  wrap**, **revoking Wispr's Accessibility**, **`open -a "Wispr Flow"`** — why: `dictation-source.md`.
- **Bracketed paste for terminal delivery** — Claude Code wraps it in `<pasted_content>` and the
  model treats it as data. Delivery stays a raw `do script` chunk + Return, plus a third Return only
  when the tab reads back `review and press Enter to send` *after* the sentence's own echo.
- **A typing affordance on the overlay** (`RelayPanel.wantsKey` only while editing).
- **A leash/smoothing/spring** on cursor-following; **a ✕ by the pointer**; **border, blur or
  shadow** on anything that rides the pointer; **an emoji where the mouse should be drawn**
  (`Glyphs.mouse`); **the corner beacon** (the halo is the beacon).
- **A denominator in a shot's name**, **the cursor burned into the JPEG**, **F3 as the shutter**,
  the **1000 px** handover (800 is the ceiling the evals allow).

## Conventions

- `(2026-MM-DD)` in a heading marks a behaviour change; later date wins.
- A rule with a measured number keeps the number. A feature that cannot be screenshot keeps a
  `WT_SHOOT_*` route, or it cannot be reviewed.
- New detail goes into the matching `.claude/rules/` file (or the journal), not here.
