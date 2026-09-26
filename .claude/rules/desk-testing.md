---
paths:
  - "Sources/WalkieTalkie/ElementPicker.swift"
  - "tools/**"
  - "evals/**"
  - "docs/loopback.md"
---
# Testing at a desk — the loopback control surface

`ElementPicker` listens on the first free port of 8917–8919 (the Chrome extension posts to all three;
`MusicBridge` is a WebSocket on 8920). `/bind`, `/unbind`, `/target` are not gated on `dictating`.
Real Wispr dictations end to end: `tools/wispr-loop.sh <scenario>` (scenarios, preconditions and
timings in `docs/loopback.md`; it takes `~/.walkie-talkie/wispr-loop.lock` — never run two).

| route | what |
|---|---|
| `POST /bind` | bind the frontmost terminal; 409 if nothing bindable; on the bound target it **unbinds** |
| `POST /bind {"tty": "ttys004"}` | bind that session — no toggle, flight or flash (the restart's restore) |
| `POST /unbind` · `GET /target` | let go · current binding (`guarded`: does the shell guard apply) |
| `GET /engine` | live source, readiness, `wrapMode`·`wrapWhy`·`scratchpadChord`, local model state, `mic` |
| `POST /test/dictation {"text", "words"?}` | fabricated transcript entering where a real one does; with `words` (`{text,start,end,type}`) `ShotMarker.place` runs for real |
| `POST /test/dictation/start {"clock"?}` | open a dictation without talking; `clock` installs a wall-clock marker clock (no mic ⇒ no offsets otherwise) |
| `POST /test/selection {"text"}` | file a highlight via `fileSelection`; 409 outside a dictation |
| `POST /test/area {x,y,w,h, "to"?}` | the wheel drag without the wheel (global Cocoa points; `to` = the ⇧-drag's move); only the crop overlay is skipped |
| `POST /test/spawn` · `/test/spawn-folders` | a spawn; the folder menu alone |
| `POST /test/replace-wispr {"on"}` | the mode behind the forward button |
| `POST /test/wispr {"on"}` · `{"hotkey": true}` · `{"historyRoute"}` | fake Wispr's mic edge · fake its start gesture · row as the delivery |
| `POST /test/wispr-handsfree` · `{"hand": true}` | post the **real** chord (fn ⌃ Space). Plain: `relay: true`, ⌘V swallowed, words delivered. `hand`: as if Victor pressed it. **Installed build only** (`.build/debug` has no Accessibility, `CGEventPost` fails silently) |
| `POST /test/firewall` | run the tap canary; `{"on": false}` lets Wispr's ⌘V through; answers `alive`, `tap` (`alive｜open｜dead` — `open` = failing open on purpose while main is frozen), `failingOpen`, `canaryMs` |
| `POST /test/key-trace {"on"}` | log every key event + verdict (`passed` / `SWALLOWED by …`), keycode and pid only |
| `POST /test/stall {"seconds"}` | freeze main (≤ 20 s) — proves the tap's fail-open (`🧊`, sample in `hangs/`) |
| `POST /test/wrap-mode {"mode"}` | `scratchpad｜sink｜off｜auto` |
| `POST /test/scratchpad/park` · `/test/wispr-scratchpad {"down"｜"up"｜"tap"}` · `GET/POST /test/wispr-notes` | park Wispr's Scratchpad · drive its chord (120 s dead-man) · read its note |
| `POST /test/shot-marker` | the marker unit test: `{text, available, selections}` rewrite; `{words, cues}` placement; `{play, kind}` into Loopback |
| `POST /test/wispr-state/simulate {"steps"}` | `WisprState` unit test with a fake clock |
| `POST /test/mic {"id"}` | pick the microphone (`auto｜xlr｜mac｜rx｜bose`); answers `chosen`/`resolved`/`available`/`mark` |
| `POST /test/mic {"device": "<name substring>"｜null}` | **process-local input override** (2026-09-26, G1): the recorder opens that CoreAudio device (e.g. `"TO Wispr"`, a Loopback), not written to `mic/choice`, gone at relaunch; `/engine.mic.override` shows it. Play a corpus WAV into the Loopback with `sounddevice` (48 kHz, 2 ch) — no speaker |
| `POST /test/eleven {"fail": "429｜429x2｜500｜401｜422｜timeout｜transport｜unreadable｜empty", "delayMs"?, "once"? (true), "scope"? ("final"｜"correction"｜"any"), "lang": {"code","p"}?, "live": "drop｜never-open｜error:<type>"?}` · `{"clear": true}` | **the ElevenLabs fault switch** (G3): the fake answers the next upload of that scope (`final` = the delivery, `correction` = the caption's rolling batch); `xN` spends N attempts (`429x2` = the call and its retry); `live` hits the socket once; `/engine.elevenlabs.fault` and `state.elevenFault` show what is armed |
| `POST /test/whisper {"kill"｜"stop"｜"cont"｜"restart": true}` | **the local helper on demand** (G4): SIGKILL/SIGSTOP/SIGCONT to `whisper_helper.py`, or stop + bring up; answers `describe()` (`ready`, `alive`, `pid`). A dead helper now fails the next request instead of killing the app (SIGPIPE ignored; `ready` cleared on EOF/EPIPE) |
| `POST /test/input {"name"}` | point the **system** default input at a device (for `tools/wispr-test.sh`) |
| `POST /test/paste-hint` | show the `📋 Re-paste ⌘⇧P` row once |
| `POST /test/cancel` · `/test/recover` | the ✕'s cancel · recover the cancelled dictation |
| `POST /test/prompt {"do": "send"｜"cancel"｜"edit", "text"?}` | **the held prompt panel** (2026-09-26, G5): ⏎ · the ✕'s cancel · `edit` with `text` replaces the words and restarts the clock (an edit that ended), without it opens the field; 409 `no prompt on the panel` otherwise. Answers `prompt` |
| `POST /test/gesture {"name"}` | post Options+'s ⌃⌥⌘F-key chord for a gesture: `forward-`/`back-` + `click｜right｜left｜up｜down`; the F7 bind sub-case (held left button) is not fakeable |
| `POST /test/sink {"on"｜"key"｜"restore"}` · `GET /test/sink` · `/test/sink/clear` | `WisprSink`, the instrumented key window: what landed, by which route |
| `POST /test/rebind-panel {"query"}` · `/test/resume-session` | the *Rebind to…* panel · ⏎ on a closed session's row |
| `GET /ping` · `POST /pick` | the Chrome extension's mailbox; 503 outside a dictation |

**`GET /test/state`** answers everything an assertion needs, read-only, ISO-8601 with ms:
`listening` · `settling` · `speculative` · `capturing` · `isRecording` · `phase`/`phaseStatus` ·
`wispr` (`state, since, status, row, lags, transitions`) · `wisprHearing` · `wrapMode`/`wrapWhy` ·
`relayStarted`/`startedMode`/`intercepting` · `scratchpad…` · `historyRoute` · `ringUp` · `arrowsUp` ·
`pasteHint` · `halo` · `chip` (rows as strings) · `pasteMode`/`atCaret`/`spawnPending`/`awaitingBind`/
`bound` · `historyRow` · `source` · `sinkOpen` · `sessionFlags` (modifiers the window server thinks
are held — read this, never infer) · `keyTrace` · `keyRedirect` · `lastRingDown` · `lastSettled` ·
`lastDelivery` · `backStopsWispr` · `busy`/`busyWhy`/`quitPending`/`pid`/`dictationStartedAt` · since 2026-09-26 (G7):
`liveCaption` (the band's ticker) · `fallingBack` · `autosend` · `lastFailure {why, engine, at}` · `recoverable {path,
duration, expiresAt}` · `live` (the socket: `socket`, `chunksSent`, `pending`, `seconds`, `cutSeconds`, `segments`,
`correctedSegments`, `corrections`, `correcting`, `committedChars`, `partialChars`, `keyterms`) · `elevenFault` ·
`elevenCost {total, label, lines}` · `micOpened {device, rate, channels, at}` (what the recorder really opened) · `whisper` ·
since batch 4: `prompt {held, verb, deadline (s left, null while paused/edited), text, buttons, editing, paused}` · `tapFailingOpen`.

- **`delivery`** (outbox line and `lastDelivery`): `{via: wispr-cmdv｜wispr-history｜wispr-notes｜
  pasteboard｜local-whisper｜test, kind: route｜alreadyInserted｜insertedElsewhere, to: terminal:ttysNNN｜
  caret｜spawn:<folder>｜held, at}`. It records, never decides; caret/held/elsewhere write no outbox line.
- **`WisprSink` is the one exception to *never `NSApp.activate`*** — it must be the key window to
  answer what one receives. Never bindable, never in `docs/states/`. With the swallow armed at the
  start chord a correct run leaves it empty.
- **`evals/test_stale_modifier.py`** fails any function that posts a key with flags and neither posts
  `flagsChanged` nor uses `postToPid` (rule and history in `area-crop.md`).
- `/test/dictation` enters below the recogniser; `/test/dictation/start` opens no mic, so the halo rests.
