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

- **Build + install:** `./relay-restart.sh --build` (stages, waits for the gate, quits, swaps, relaunches).
  A bare `./build-app.sh` swaps the bundle at once — only with the app not running: a bundle
  replaced under the running app breaks its AppleEvents (every bind fails). Never commit an `.icns`.
- **Restart ONLY through `./relay-restart.sh [--build]`** — never `pkill`/`kill`/`open` by hand.
  2026-09-28, Victor: *"restart is only possible after 5 secs of inactivity after the last insert
  of text"*, then at 21:20 *"there should only be 5 seconds since the last ended dictation for the
  walkie deploy to be authorized"* — **5 s since the last ended dictation, never while any engine
  is dictating or transcribing; his typing does not hold it.** The gate waits for
  `GET /test/state.busy` false (every engine, Wispr's own mic and History row included) and 5 s
  after the last insert/dictation edge; an app that does not answer is refused (exit 4), never
  restarted blind.
  `--dry-run` checks the gate; `--force` is a human's only. If it refuses, WAIT — never override.
- **An edit to `chrome-extension/` is deployed with `./relay-restart.sh --extension`** (any restart also reloads it when it changed) — committing it reaches no browser.
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

- **Keys:** ⌘⌃B bind (again = unbind), ⌘⌃D dictate, **⌘⌃X = the local model now** (recording or
  waiting on the cloud: this Mac transcribes the take, `via: local-forced`; 2026-09-28). All three
  swallowed. ⌘⌃⌥D and ⌘⌃L belong to Victor Addons, ⌘⌃W to Wispr Flow.
  Right ⌘⌥ held = Walkie's clean dictation (`54+61`); right ⌥⇧ held = **Wispr's own** ptt (`61+60`,
  Q23), left alone.
- **The clipboard always holds the finished sentence** (Q17, 2026-09-28): the envelope for a prompt,
  the clean words for a plain one, whatever the engine or destination; never restored. ⌘V re-pastes.
- **Side buttons** (Options+ → ⌃⌥⌘F3…F12, duplicated in `HotkeyTap`, must not drift;
  `evals/test_gesture_spec.py` is the spec): 🔼 = prompt at the caret (full envelope); 🔼 → at the
  bound terminal (mid-sentence: flips bound ⇄ caret, 2026-10-05 — 🔼 ends it); 🔼 ← cancel (**at rest: a ⚡ quick question** — Opus via a pre-started `claude -p`, answer in the reply pop-up, 2026-10-09; then 🔎 web check + 🧐 adversarial review, ✕ stops them, 2026-10-10); 🔼 ↑ new session; 🔼 ↓ kamikaze; ◀️-held + 🔼 bind; **🔽 and 🔽 →
  = plain dictation** (start/stop; words only, follows the Engine; **every stop inserts, then
  Return** — 2026-10-05: the bare 🔽 at rest is no longer Return); 🔽 is the shutter while a prompt
  records; **🔽 ↓ while a prompt records = the typing box** (`[typed: "…"]` inline, 2026-10-07 —
  `mouse-gestures.md`). A prompt with a `?` asks the agent for `walkie-reply`, shown beside the
  pointer (`destinations-and-outbox.md`).
- **Unbound, everything still works:** the sentence is held 5 min for the next bind.
- **The recipient is latched when the microphone closes — which terminal, not only *not the caret*.**
  A deliberate bind mid-sentence redirects; the 10 s poll never may; a bind or unbind after the close
  changes nothing (Q2, 2026-09-26).

## Never reintroduce

- **Pause** — Disconnect is the hand-back; `holdsForBind` is never a menu tick.
- **⌘⇧P re-paste** (or any re-paste key) — the clipboard holds the sentence instead (Q17, 2026-09-28).
- **Wispr's DB as a recogniser**, **`copy_last_text` by default**, **focus-stealing as the Wispr
  wrap**, **revoking Wispr's Accessibility**, **`open -a "Wispr Flow"`** — why: `dictation-source.md`.
- **Bracketed paste for terminal delivery** — Claude Code wraps it in `<pasted_content>` and the
  model treats it as data. Delivery stays a raw `do script` chunk + Return, plus up to four more
  Returns (watched 4 s, ~1/s — 2026-09-29) while the tab reads back the sentence still under `❯` or `review and press Enter to send`
  *after* the sentence's own echo (2026-09-28: Claude Code folds a Return within ~150 ms of a large
  chunk into the paste — `terminal-binding.md`).
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
