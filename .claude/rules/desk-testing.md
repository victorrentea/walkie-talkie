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
The whole suite runs **inside the Tart guest, on demand only** (2026-09-29, Victor: *"I will only
run it on demand and send you out to run this test and fix findings when I experience some issues"*;
the 02:00 LaunchAgent is unloaded — external APIs must not be hit by a scheduler): `WT_NIGHT_FORCE=1
tools/wt-night.sh start`, or a driver session on `wt-lab` — `docs/vm-lab.md`, *Nightly*; desk runs
prefer the local engine.

| route | what |
|---|---|
| `POST /bind` | bind the frontmost terminal; 409 if nothing bindable; on the bound target it **unbinds** |
| `POST /bind {"tty": "ttys004"}` | bind that session — no toggle, flight or flash (the restart's restore) |
| `POST /unbind` · `GET /target` | let go · current binding (`guarded`: does the shell guard apply) |
| `GET /engine` | live source, readiness, `wrapMode`·`wrapWhy`·`scratchpadChord`, local model state, `mic`; `wisprShortcuts` (Wispr's `config.json` action → chord, e.g. `ptt: "61+60"`), `wisprStandalone`, `wisprPttCoherent` (standalone ⇒ Wispr's ptt is off 54+61; W-C7) |
| `POST /test/dictation {"text", "words"?}` | fabricated transcript entering where a real one does; with `words` (`{text,start,end,type}`) `ShotMarker.place` runs for real |
| `POST /test/dictation/start {"clock"?}` | open a dictation without talking; `clock` installs a wall-clock marker clock (no mic ⇒ no offsets otherwise) |
| `POST /test/selection {"text"}` | file a highlight via `fileSelection`; 409 outside a dictation |
| `POST /test/area {x,y,w,h, "to"?}` | the wheel drag without the wheel (global Cocoa points; `to` = the ⇧-drag's move); only the crop overlay is skipped |
| `POST /test/spawn` · `/test/spawn-folders` | a spawn; the folder menu alone |
| `POST /test/replace-wispr {"on"}` | the mode behind the forward button |
| `POST /test/wispr {"on"}` · `{"hotkey": true}` · `{"historyRoute"}` | fake Wispr's mic edge · fake its start gesture · row as the delivery |
| `POST /test/wispr-handsfree` · `{"hand": true}` | post the **real** chord (fn ⌃ Space). Plain: `relay: true`, ⌘V swallowed, words delivered. `hand`: as if Victor pressed it. **Installed build only** (`.build/debug` has no Accessibility, `CGEventPost` fails silently) |
| `WT_WISPR_DB=<path>` (env, or a line in `elevenlabs.env`, re-read ≤ 1 s) | **a fake `flow.sqlite`** (2026-09-28, H1): `WisprHistory`/`WisprNotes` read it instead of Wispr's; reopened on a path or inode change. `evals/plan/fake_wispr_db.py` writes a schema-identical copy and its rows (`insert`/`update`/`finish`: `status`, `asrText`/`formattedText`/`pastedText`, `timestamp`, `speechDuration`, `e2eLatency`, `duration`); `state.wisprLive.db` names the file in force. Rollback journal by default; `create(wal=True)` / `desk(wal=True)` = Wispr's WAL mode, a holder connection keeping `-wal` alive until `close()` (batch 3: the only way a desk reaches the relay's WAL watch) |
| `POST /test/wispr-paste {"dryClaim"?}` | a Wispr ⌘V through the firewall's decision, no key on the wire (B, HK4): answers `verdict` `passed｜dropped` + `why`; dropped → `injected` as the tap does. `dryClaim` (batch 3): for 10 s the Q19 claim decides and logs (`🧪 dry claim`) but pastes nothing; `wisprLive.lastForeignClaim {row, source, chars}` |
| `POST /test/wispr-proc {"stop"｜"cont"｜"kill"｜"relaunch": true, "afterMs"?, "forMs"?, "pid"?}` | **Wispr's main process** (H2): SIGSTOP (auto-SIGCONT after `forMs`, default 10 s, ≤ 60 s) · SIGCONT · SIGKILL · kill + `open "/Applications/Wispr Flow.app"` by path; `afterMs` delays it. A `pid` that is not the anchored main executable's → 409; not running → 409. **`{"fakeExit": true}`** (batch 4): the sentence's Wispr reads as exited, no signal sent — the quit at a desk |
| `POST /test/wispr-chord {"post": "on"｜"off"｜"cancel"｜"none", "state": "start"｜"stop"｜"cancel"｜"none"}` · `{"mute": bool, "seconds"?}` | **the chord and the relay's belief, decoupled** (H4): `post` puts fn ⌃ Space (`cancel`: ⌃Esc) on the wire without touching state; `state` moves `WisprFlowSource` without posting (`start` = the relay's own gesture). `mute` (≤ 600 s default, self-expiring): every Wispr chord the app posts goes out as its stamped trailing `flagsChanged []` only — desk runs over the fake DB never reach his real Wispr. Answers `wisprLive` |
| `POST /test/modifiers {"keys": [54, 61], "holdMs": n (≤ 10 000), "stamped"?}` | **a modifier pair held as if by hand** (C, H6): unstamped `flagsChanged` with the device bits (right ⌘ 54, right ⌥ 61, right ⇧ 60, right ⌃ 62…), released in reverse to `[]`; `keys: []` + `stamped: true` = one stamped `flagsChanged []` (GW6, the tail of this app's own chords). Non-modifier keycodes → 400. Synthetic input: under `hands-off` |
| `POST /test/firewall` | run the tap canary; `{"on": false}` lets Wispr's ⌘V through; answers `alive`, `tap` (`alive｜open｜blind｜dead` — `open` = failing open on purpose while main is frozen; `blind` = Secure Input / lock screen hides keys from every tap, `hidden` names the holder), `failingOpen`, `canaryMs`, `healing`. A dead answer starts the self-heal |
| `POST /test/tap {"kill": true｜"unschedule"｜"invalidate"｜"disable"｜"secure", "seconds"}` | break the tap (source off the run loop · mach port invalidated · `tapEnable(false)` · Secure Input held N s) and run the canary → heal; poll `/test/firewall`. **Keys are blind while anything holds Secure Input** — `/test/gesture` answers `hidden` + `warning` then |
| `POST /test/key-trace {"on"}` | log every key event + verdict (`passed` / `SWALLOWED by …`), keycode and pid only |
| `POST /test/stall {"seconds"}` | freeze main (≤ 20 s) — proves the tap's fail-open (`🧊`, sample in `hangs/`) |
| `POST /test/wrap-mode {"mode"}` | `scratchpad｜sink｜off｜auto` |
| `POST /test/scratchpad/park` · `/test/wispr-scratchpad {"down"｜"up"｜"tap"}` · `GET/POST /test/wispr-notes` | park Wispr's Scratchpad · drive its chord (120 s dead-man) · read its note |
| `POST /test/shot-marker` | the marker unit test: `{text, available, selections}` rewrite; `{words, cues}` placement; `{play, kind}` into Loopback |
| `POST /test/affect` | `VoiceAffect` on fabricated timings, pure: `{words:[{text,start,end,type?}], voiced?: s \| [{t,rms,voiced}], language?, gestures?, thresholds?, tense?}` → `{hesitant, tense, tag, text (with [?]), marks, affect, thresholds}` (2026-09-27) |
| `POST /test/wispr-state/simulate {"steps"}` | `WisprState` unit test with a fake clock |
| `POST /test/mic {"id"}` | pick the microphone (`auto｜xlr｜mac｜rx｜bose`); answers `chosen`/`resolved`/`available`/`mark` |
| `POST /test/mic {"device": "<name substring>"｜null}` | **process-local input override** (2026-09-26, G1): the recorder opens that CoreAudio device (e.g. `"TO Wispr"`, a Loopback), not written to `mic/choice`, gone at relaunch; `/engine.mic.override` shows it. Play a corpus WAV into the Loopback with `sounddevice` (48 kHz, 2 ch) — no speaker |
| `POST /test/eleven {"fail": "429｜429x2｜500｜401｜422｜timeout｜transport｜unreadable｜empty｜delay", "delayMs"?, "once"? (true), "scope"? ("final"｜"correction"｜"any"), "lang": {"code","p"}?, "live": "drop｜never-open｜error:<type>"?}` · `{"clear": true}` | **the ElevenLabs fault switch** (G3): the fake answers the next upload of that scope (`final` = the delivery, `correction` = the caption's rolling batch); `xN` spends N attempts (`429x2` = the call and its retry); `live` hits the socket once; `/engine.elevenlabs.fault` and `state.elevenFault` show what is armed |
| `POST /test/whisper {"kill"｜"stop"｜"cont"｜"restart": true}` | **the local helper on demand** (G4): SIGKILL/SIGSTOP/SIGCONT to `whisper_helper.py`, or stop + bring up; `{"model": "<repo id｜folder>"}` = the Engine list's model pick (2026-10-03, applied at idle; `GET /engine.whisperModels`); answers `describe()` (`ready`, `alive`, `pid`). A dead helper now fails the next request instead of killing the app (SIGPIPE ignored; `ready` cleared on EOF/EPIPE) |
| `POST /test/local-fallback {"wav", "words"?}` | the local model on a file, delivers nothing; `words: true` forces the word timings (otherwise asked only with a cue pending) and answers `words[{text,start,end}]` — `evals/test_local_marker_place.py` (2026-10-04) |
| `POST /test/input {"name"}` | point the **system** default input at a device (for `tools/wispr-test.sh`) |
| `POST /test/paste-hint` | show the `📋 Re-paste ⌘V` row once (was `Re-paste ⌘⇧P` until 2026-09-28, `On the clipboard ⌘V` for a few hours, `Re-paste ⌘V` since) |
| `POST /test/engine-menu {"appearance": "light"｜"dark", "seconds"? (3), "x"?, "y"?}` | pop a copy of the **Engine** list (with the 🧾 quota row) in a forced theme at global point x,y (default: top right of the menu-bar screen); closes itself — a submenu cannot be opened from code. `"menu": "main"` pops the whole top-level menu instead (2026-09-28) |
| `POST /test/cancel` · `/test/recover` | the ✕'s cancel · recover the cancelled dictation |
| `POST /test/local-now` | **⌘⌃X's action** (2026-09-28): the take recording or in flight goes to the local model (`via: local-forced`); at rest a flash. `state.localNow {available, why, loading, row}` says whether it would (TN1–TN3, `evals/plan/cases_localnow.py`) |
| `POST /test/local-auto {"on"?, "budget"?, "localEta"?, "wisprDown"?, "fakeLaunch"?, "wisprAge"?}` | **Prepare local transcript (p95)** (2026-09-28 as the auto fallback; 2026-09-29): `on` is the Engine submenu's checkbox (**written to the defaults** — the harness restores it after every case); `budget` / `localEta` (s｜null, 2026-09-29) force the next closes' budget and local ETA, so a case can place the decode ahead against a fake engine's delay (its traces are `test`); `wisprDown` makes a start read Wispr Flow as not running; `fakeLaunch` logs Wispr's background launch instead of running it; `wisprAge` (batch 4, s｜null) reads Wispr's process as that old. Answers `localAuto` (TA2, TA4–TA11, `evals/plan/cases_localauto.py`) |
| `POST /test/autosend {"on": bool}` | **Autosend for this run** (2026-09-26 batch 6, G6): the menu row's toggle, **not** written to the defaults — a relaunch restores his setting; `state.autosend` |
| `POST /test/prompt {"do": "send"｜"cancel"｜"edit", "text"?}` | **the held prompt panel** (2026-09-26, G5): ⏎ · the ✕'s cancel · `edit` with `text` replaces the words and restarts the clock (an edit that ended), without it opens the field; 409 `no prompt on the panel` otherwise. Answers `prompt` |
| `POST /test/gesture {"name"}` | post Options+'s ⌃⌥⌘F-key chord for a gesture: `forward-`/`back-` + `click｜right｜left｜up｜down`; the F7 bind sub-case (held left button) is not fakeable. **`"direct": true`** (batch 4): `forward-right`｜`forward-click`｜`forward-down` call the handler (`toggleDictation`｜`forwardClickToggle`｜`onGestureKamikaze`), no chord — works with the screen locked |
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
`elevenCost {total, label, lines}` · `elevenQuota {used, total, remaining, reset, source (subscription｜character-stats), subscriptionStatus, missingUserRead, pace (green｜orange｜red, the row's colour = the burn trend), burnRate, title, error, fetchedAt}` (null before the first fetch; the Engine list's 🧾 row, 2026-09-28) · `micOpened {device, rate, channels, at}` (what the recorder really opened) · `whisper` ·
since batch 4: `prompt {held, verb, deadline (s left, null while paused/edited), text, buttons, editing, paused}` · `tapFailingOpen` · since batch 6: `sentences` (Q12: `[{id, state, target, startedAt, take, waiting}]`, oldest first) ·
`sentenceQueue` · `wisprStandalone` (Q9) · `live.handshake` (Q11) · `localNow {available, why, loading, row}` (⌘⌃X,
2026-09-28) · `localAuto {on, budget, p95, quantile, cap, samples, engine, audio, since, left, expired, settled,
fired (always false — the hand-over is `spec.consumed` + the trace's `outcome=local-auto` since 2026-10-06), spec {startAt, startedAt, readyAt, phase planned｜running｜ready｜failed｜skipped｜discarded,
wasted, consumed, chars, wav}, trace (the 📊 line's JSON), forced {budget, localEta}, localReady, wispr {down, fakeLaunch,
launches, launchedAgo}}` (prepare local transcript, 2026-09-29 — kept after the words land until the next close; seconds in
`spec` are from the close) · since 2026-09-28 (Wispr as engine):
`wisprLive {micOpen (the poll's CoreAudio sample), newestRowId, newestRowStatus, newestRowText (chars), captureOpen,
captureRow, speculative, isRecording, discarding, meterRecording, sawCmdV (this capture's firewall caught Wispr's ⌘V),
lastCmdVAt, relayOwned, relayOwnedUntil, wisprPid, pidAtChord, chordsMuted, db, historyWake {watching, subscribers, events, ticks, passes, queries, cacheHits}, rowSeen {rowid, status, at, epoch}, lastForeignRow, lastForeignClaim}` (the last four: batch 3, 2026-09-28 — `rowSeen` is when the capture's reader saw its row change, the desk's WAL-watch latency) · `pasteboard {changeCount, events:
[{changeCount, at, writer: walkie｜other, why?, front, skipped?}]}` (never the text; the 20 Hz sampler starts at the
first `/test/state`). **`{"fail": "delay", "delayMs": n}`** is the real
upload made n ms late (Q12's order cases); `delayx2` delays the next two.

- **Wispr as the engine at a desk: `evals/plan/cases_wispr.py`** (TW1–TW21, 2026-09-28, the reviews in
  `evals/plan/wispr/`). A desk case switches in a fresh fake DB (`# fake-wispr:` marks in `elevenlabs.env`,
  removed after every case through the harness's `CLEANUPS`), mutes Wispr's chords, points the relay's
  recorder at the Loopback and drives rows by hand — his real Wispr hears nothing. `lab_only` cases SKIP
  off the Tart guest (`WT_LAB=1`, set by `run-phase.sh`, or `kern.hv_vmm_present`); every case SKIPs
  when Wispr is not running. `WT_ALLOW_WISPR_KILL=1` lets TW7(c)/TW15 kill and relaunch his Wispr.
- **`delivery`** (outbox line and `lastDelivery`): `{via: wispr-cmdv｜wispr-history｜wispr-notes｜
  pasteboard｜local-whisper｜elevenlabs-scribe｜local-fallback｜local-forced (⌘⌃X)｜local-auto (the budget ran out —
  2026-09-28 22:25 → 09-29 07:40, and again since 2026-10-06)｜test, kind: route｜alreadyInserted｜insertedElsewhere, to: terminal:ttysNNN｜
  caret｜spawn:<folder>｜held, at}`. It records, never decides; caret/held/elsewhere write no outbox line.
- **`WisprSink` is the one exception to *never `NSApp.activate`*** — it must be the key window to
  answer what one receives. Never bindable, never in `docs/states/`. With the swallow armed at the
  start chord a correct run leaves it empty.
- **`evals/test_stale_modifier.py`** fails any function that posts a key with flags and neither posts
  `flagsChanged` nor uses `postToPid` (rule and history in `area-crop.md`).
- `/test/dictation` enters below the recogniser; `/test/dictation/start` opens no mic, so the halo rests.
- **Harness timing and skipping** (2026-09-29, `evals/plan/README.md`, `evals/plan/timing-audit.md`):
  a condition wait's timeout is `tmo(path)` = measured p99 × 1.5 + 1 s × `WT_HARNESS_SLOW` (1.0 desk,
  1.5 guest) — never a new round number in a case. Settle waits read `relay_busy()`, never
  `state()["busy"]`: a cancelled take's *audio staged for Recover* holds `busy` five minutes and cost
  wave 5 ~750 of its 2 762 s. `harness.py --changed-since <sha>` SKIPs cases whose `covers=(…)` did not
  change (`--list` to preview, no app needed); `WT_SOAK_N` sets the soak loop lengths.
- **Local tests prefer the local engine; ElevenLabs is capped** (2026-09-27, Victor: *"pune plafon +
  regula ca testele locale sa prefere intotdeauna motor local"* · *"poti emula daca vrei apiul lor de
  streaming pt testele de live subtitles"*; on 26 Sep the suite alone burned 4 561 of the month's
  10 000 credits). `evals/plan/harness.py` sets `POST /engine {"id":"whisper"}` at start and puts his
  engine back at exit; only the cases in `ELEVEN_ENGINE` (tags `eleven`, `live`) switch to
  `eleven`｜`eleven-live`, for their duration. They run against **`evals/plan/fake_scribe.py`**
  (stdlib RFC 6455 + batch, `--selftest` needs no app) through `WT_ELEVEN_LIVE_URL` /
  `WT_ELEVEN_BATCH_URL` lines the harness writes into `elevenlabs.env` (between two
  `# fake-scribe:` marks, removed at exit and at the next start) — the app re-reads that file at
  every engine pick, so no relaunch. `WT_FAKE_SCRIBE=0` = the real service. A case that would spend
  real credits (not `FAULT_ONLY`; always for `VENDOR_ONLY` = TL25) is `SKIP credit cap (N left)`
  when `WT_ELEVEN_QUOTA` (10000) − this month's `GET /v1/usage/character-stats` < `WT_ELEVEN_MIN_CREDITS`
  (3000) or the usage is unreadable; the report header and footer carry credits before/after.
  The run also wakes the display (`caffeinate`): the band's display link stops with the screen.
