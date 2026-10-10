---
paths:
  - "Sources/WalkieTalkie/DictationSource.swift"
  - "Sources/WalkieTalkie/WisprFlowSource.swift"
  - "Sources/WalkieTalkie/LocalWhisperSource.swift"
  - "Sources/WalkieTalkie/ElevenLabsSource.swift"
  - "Sources/WalkieTalkie/ShotMarker.swift"
  - "Sources/WalkieTalkie/VoiceAffect.swift"
  - "Sources/WalkieTalkie/WisprHistory.swift"
  - "Sources/WalkieTalkie/WisprNotes.swift"
  - "Sources/WalkieTalkie/WisprSink.swift"
  - "Sources/WalkieTalkie/WisprState.swift"
  - "Sources/WalkieTalkie/WisprWatch.swift"
  - "tools/wispr-*"
  - "tools/eleven-test.sh"
---
# The dictation source

Rules for the recognisers and everything that catches Wispr Flow's words. History and reasoning:
`docs/journal.md` (*Wispr Flow everywhere*, *The firewall*, *ElevenLabs is the engine…*); the later
dated note always wins. Speechmatics and Gemini were removed whole on 2026-09-20 (sources, tools,
`DictationVocabulary`, menu rows, corpus tags, env switches); `git show` on that commit brings them back.

## One interface, nothing downstream looks behind it

- **`AppDelegate` holds a `DictationSource` and never names an implementation.** Chip, halo, settle,
  corpus and routing read the protocol only. Concrete classes appear only in `wireDictationSource()`,
  `engine(named:)` and the `/test/wispr*` routes. Payoff measured 2026-09-18: ElevenLabs cost one new
  file plus a case, a menu row, a line in `/engine` and a corpus tag.
- **Engines:** ElevenLabs Scribe (**default since 2026-09-19**, for its word timings), the local
  model, and Wispr Flow (third row, behind the firewall since 2026-09-22 evening; out of the list only
  that morning). `WisprFlowSource` is wired **whichever engine is picked** — the raw 🔽 → chord, the
  meter, `hearingChanged`, the ⚡ ring and the back button's stop hang off `wisprSource`.
- **`☁️ ElevenLabs + Live` (`eleven-live`, 2026-09-25) is a second `ElevenLabsSource(live: true)`**,
  not a flag: same WAV, same batch transcript **delivered**, plus `ElevenLabsLive` streaming the
  buffers (`MicRecorder.onBuffer`, set/cleared on `audioQueue`) to `scribe_v2_realtime` over a
  websocket (`commit_strategy=vad`) for the chip's `💬` caption only. Every stream failure is a
  log line, never a `DictationEnd`. Costs both: batch + $0.39/h. Probe measured 2026-09-25: first
  partial ~1 s after speech, then ~1/s, revising the last word's punctuation.
  **One socket per sentence, opened at `start()`, closed at `stop()`** (Q11, 2026-09-26 batch 6 —
  batch 5's warm `spare`, the 5 s empty keep-alive chunks, the 15-min `WT_ELEVEN_LIVE_WARM` window,
  the idle retry ladder and `DictationSource.release()` are gone: *"rece … waste de resurse"*). The
  socket has **its own `URLSession`** (`LiveSocketSession`: ephemeral, `waitsForConnectivity` off,
  own pool, invalidated at `shut()`) — hypothesis for the in-app handshake variance (0.3–4 s vs
  0.30–0.45 s from a script): `URLSession.shared` busy with the batch/correction uploads. The log
  measures it: `upgraded N s after connecting`, `session open, handshake N s, K chunk(s) caught up`;
  `state.live.handshake`. Unverified until the morning's B1 runs.
  **A dropped socket is one line and one reconnect** (TL29, was ~9 `send failed`/s): stale tasks'
  failures are ignored, the audio waits (≤ 64 buffers, ~5 s — also the cap for a socket not up yet,
  TL30), a second drop stops the caption for that sentence. **The band opens on the session, not
  the gesture** (`didOpenLive` / `liveOpen`; TL30): no key, or a socket that never opens, no band.
- **A cloud engine that fails keeps the sentence: the local model transcribes the same WAV**
  (2026-09-25, `AppDelegate.fallBackToLocal` → `transcribeLocally`). Any `.failed` carrying audio
  from a source with `recordsOwnAudio` (both ElevenLabs rows) is intercepted at the top of
  `dictationEnded` before anything is torn down, so `deliver` sends it where the sentence was
  going; the result says `via: local-fallback` and warns *X was unavailable*. Only if the local
  model fails too (90 s to come up, or no words) does the old path run (WAV staged for *Recover*).
  A helper found dead by the fallback's own request (nil answer, `ready` false after it) is brought
  back up and asked once more (2026-09-26, TR10: it used to give up in 35 ms).
  **No key records anyway** (the start gate is `isReady || recordsOwnAudio`), and **neither do the
  local model's weights** (2026-09-26 — `recordsOwnAudio` is true for it too; the WAV waits for the
  model at the stop, see `whisper-and-corpus.md`). The settle waits for as long as `fallingBack`
  (no ceiling since 2026-09-26 — the fallback is bounded by the model's 90 s and 300 s). ElevenLabs' `requestTimeout` is 20 s (was 45)
  and a timeout is not retried. Measured: cold model + 3.5 s clip = 6.0 s
  (`POST /test/local-fallback {"wav"}`, which answers the result and delivers nothing).
- **⌘⌃X hands the take to the local model on demand** (2026-09-28, `DictationSource.handToLocal()`):
  the same `fallBackToLocal` path, entered with `why == DictationEnd.localForced` — `via:
  local-forced`, no warning, `lastFailure` untouched. ElevenLabs: recording → no upload
  (`forcedTakes`); uploading → `Upload.abandonedAt`, the call finishes and is only logged. Wispr:
  recording → ⌃Escape + `endWithRecording(forced:)`; settling → `discardOnArrival` without the
  dismiss. The local engine answers false. → `mouse-gestures.md`, *⌘⌃X*
- **Backup Local Pre-Transcribe (p95) — decoded ahead, counted down to, inserted at zero**
  (2026-10-06; *Auto fallback to local (p98)* on 09-28, *offered, never inserted* 09-29 → 10-05).
  Victor, 2026-10-06: *"put a countdown timer … when the timer expires, the local dictation is
  automatically injected"* — that morning he pressed ⌘⌃X 11 s and 18 s past a 3.4 s budget while
  Wispr sat on rows that never finished. **His patience is a few seconds** (09-28). Default ON
  (`AutoLocal.isOn`, defaults key `autoLocalFallback`), Engine submenu `Backup Local Pre-Transcribe`.
  At every close of a relay sentence on a cloud engine (`armAutoLocal`, only when
  `DecodeRate.activeEngine` is the source's own key — a Wispr sentence his own chord opened is never
  armed): **`DecodeRate.budget`** = the engine's p95 for that length (Theil–Sen over its newest 100
  warm samples × the 0.95 quantile of the residual ratios, bounds 1…6; under 20 samples the prior × 3),
  clamped to **[1.5 s, 0.3 × audio + 1 s]**; **`localEta`** = `DecodeRate.typical(local)` + 0.3 s; the
  local model runs on the relay's own closed WAV (`DictationSource.closedTakeAudio(take:)`: ElevenLabs'
  upload in flight, Wispr's kept meter take) from **`max(0, budget − localEta)`** (`AutoLocal.shouldStart`,
  the 0.1 s tick in `syncLocalNow`). Under the 1.5 s voiced floor nothing runs. From
  `localNowRowDelay` (1 s) into the wait the chip counts down — `💻 local in 3s / ⌘⌃X ...`
  (`AutoLocal.row` / `rowText`, whole seconds up, `now` at zero, **no engine name**). **At zero the
  local words go in** (`AutoLocal.shouldHandOver`: expired + `.ready`, once → `handOverAtBudget` →
  `transcribeLocallyNow`, `via: local-auto`, log `⏱ <engine> over budget … they go in now`); a decode
  still running is waited for; one that gave nothing (failed/skipped/discarded) takes the row down
  and leaves the sentence to the engine. ⌘⌃X sooner → `via: local-forced`; the engine's words first →
  local ones discarded (`wasted`). **Never two local decodes of one take**: `transcribeLocally` takes the
  ready words, waits for a running decode, or starts a planned one. OFF: no decode ahead, nothing on
  a clock, `Local now` after 1 s.
  **Q14 stays automatic** (engine error, no Wispr row, Wispr gone) and reuses the
  words decoded ahead. Every armed sentence writes one `📊 fallback: engine= audio= budget=(p95,n=)
  localEta= specStart= localReady= engineAnswer= budgetExpired= outcome= wasted= toWords=` line at its
  outcome (seconds from the close; outcome `engine｜local-auto｜local-forced｜local-fallback｜…`) and the
  same JSON to `~/.walkie-talkie/fallback.jsonl` (`test: true` for a desk run); `evals/fallback-report.py`
  reads it back, `--budgets` replays the budgets.
  `eleven-live` files under `elevenlabs`. **The fake Scribe's answers file under `elevenlabs-test`**
  (any `WT_ELEVEN_BATCH_URL`), **a fake `History`'s rows under `wispr-flow-test`** (`WT_WISPR_DB`),
  so desk runs never teach the real lines. While ON and the engine is not local, the local weights are
  kept up (`keepLocalWarm`: launch +2 s, every engine pick, the checkbox). → journal: *Prepare local
  transcript (p95)*, *The countdown to the local words (2026-10-06)*
- **A clean sentence on Wispr waits ≥ 5 s for Wispr's formatted words** (2026-10-10, Victor: *"in
  dictare curata cu wispr ca motor, ia te rog varianta redactata"*): two plain sentences that evening
  went in as the local model's words — Wispr's row came at 2.4 s, the budget was the 1.5 s floor.
  `AutoLocal.wisprCleanFloor` raises the budget (`budgetSeconds`) for 🔽 / 🔽 → / right ⌘⌥ on Wispr
  only; the decode ahead and the hand-over past it are unchanged. Log `⏱ a clean sentence on Wispr
  Flow — budget … raised to 5.0 s`.
- **A 🔽 → plain sentence hands its WAV to the countdown too** (2026-10-06, 11:14). `closedTakeAudio`
  answered only `relayStarted`, which the raw chord never sets, so the plain sentence was armed and
  counted down but the decode ahead stayed `planned` (`⏱ … the local decode has not started (no WAV
  yet)`), nothing went in at zero, and Wispr's `error` came 33 s later. It reads `walkieOwned`
  (`relay || walkiePosted`) now; his own Wispr chord (Q9) still has none.
- **A Wispr still finishing the take the relay gave up on cannot take the next one** (2026-10-06).
  Measured 10:25:11: a start chord posted 6 s after ⌘⌃X left row 18414 `processing` was ignored; the
  sentence learnt so 12 s in (`holdOwnTake`) and went local by the back door — Victor read it as the
  new-session gesture picking another engine. `WisprFlowSource.stillFinishingAbandonedRow` (the row
  `watchLateRow` owns, read live, nil once terminal/dead) → `startDictation` borrows the local model
  **at the start**, flash `💻 Local — the last take is still being transcribed`. With the clock
  handing over at the budget this is the common case after a slow row, not a rarity.
- **One engine for every gesture** (2026-10-06, Victor: *"the model that is used for transcribing
  should be the same for all four, always. Make sure in the code that this never drifts"*): bound,
  caret, new session and clean all open the microphone through `startDictation`, the only caller of
  `source.start()`; a sentence runs elsewhere only through `borrowEngine`, for the hard failures
  listed in `evals/test_one_engine.py` (Q21 without Wispr's F19 shortcut, Wispr not up, Wispr still
  finishing). A new borrow must be added there with its reason, or that test fails.
- **A Wispr sentence never waits for Wispr Flow to start** (2026-09-28 evening — *"10 s startup time is
  killing"*; not gated on the checkbox since 2026-09-29 — a hard failure, like Q14): a `startDictation` on Engine = Wispr while Wispr is not running,
  or was launched by the relay under `AutoLocal.wisprStartupGrace` (12 s) ago — **or whose process is
  younger than that, whoever launched it** (batch 4, item 4: `ProcessClock.age`, TX9) — borrows the local
  model for that one sentence (Q21's `borrowEngine`: the relay's own microphone, decoded at the
  close, `via: local-whisper`), flashes `💻 Local — Wispr Flow is starting`, and launches Wispr in
  the background (`NSWorkspace.openApplication` on the bundle path, `activates = false`, at most
  once per 30 s). `POST /test/local-auto {"wisprDown", "fakeLaunch", "wisprAge"}` fakes them (`AutoLocal.wisprNotUp` is the pure half).
- **`engine(named:)` is one table read by the launch pick and the menu pick; anything unrecognised is
  the default**, never a named engine, so a typo cannot pick a recogniser.
- **`setEngine`** nils the old source's callbacks, assigns `source`, writes `dictationSource`, re-runs
  `wireDictationSource()`; **refuses while a sentence is in flight**. `WT_SOURCE` wins for a run.
- **Every callback lands on the main queue** — one rule at the boundary, not a hop per call site.
- **`phase` (`DictationPhase`: `idle`·`warming`·`listening`·`transcribing(status)`·`done(status)`)
  is source-agnostic**; the status string is the recogniser's and nothing outside may branch on it.
  `isRecording` = *a microphone is open* (source); `listening` = *a sentence is in flight* (relay);
  every gate in `AppDelegate` means the second.
- **Never open or close a microphone on the main thread.** `MicRecorder.start/stop` are synchronous
  CoreAudio binds; a wedged audio stack froze the app solid twice (2026-09-19, `sample` →
  `BindToDeviceInternal → mach_msg`). Wispr: `meterQueue`; ElevenLabs and local: `audioQueue` (open,
  stop, cancel — local since a 🔼← froze it 2026-09-24). Meter readers take only `MicRecorder.lock`,
  never held across an engine call.
- **`hearingChanged` arrives whether or not Wispr is the engine** (wired once at launch, not in
  `wireDictationSource`) and claims only *a microphone is open* — pause the music, raise the ring.
  Deliberately not a sixth `DictationSource` event: a dictation Victor starts himself stays Wispr's.
- **A chord this app posts must announce itself** — `HotkeyTap.onWisprRawChord` →
  `noteRawChord(closing:)`. The keyboard branch filters our own posts (`backButtonStamp`), so without
  this 🔽 → reached `WisprState` through no witness at all: no row poll, no ring.
- **Right ⌘⌥ is never Wispr's push-to-talk any more** (Q9 step 2, 2026-09-28): `onWisprPushToTalkReleased`,
  `WisprStart.pushToTalk`, `startedByHeldPair`, `heldPairIsTheEngines` are deleted; the pair is
  `onCleanHold` whatever the Engine (on Engine = Wispr it posts Wispr's F19 shortcut — below). Wispr's
  own ptt is **right ⌥⇧ `61+60`** (Q23), watched only to start the bridge's feed, never taken.
- **A Wispr sentence names Wispr's microphone** — `History.micDevice` → `InputDevice.glyph(wisprName:)`,
  read from Wispr, never written; `🎓 TO Wispr` maps to the relay's own device.

## The Wispr firewall (2026-09-22, evening)

Victor: *"vreau wisprflow să NU mai fie lăsat să insereze text el … îi luăm transcrierea din DB, cât
Walkie e pornit."* Case: app1 in front, relay bound to terminal 2 → nothing in app1, words in terminal 2.
He rules out **any focus move and the Scratchpad**. Plan: `docs/wispr-injection-attack-plan.md` ①+③.

- **Three parts:** `HotkeyTap` drops Wispr's ⌘V **statelessly** (posting pid is Wispr — no arm, no
  window); every Wispr sentence is the relay's (`intercepting` whoever pressed the chord) and is
  delivered from the `History` row at `formatted` (`historyIsTheRoute` default; pasteboard never
  read); `wisprSource` wired whichever engine is picked. There is no AX dictation path in Wispr —
  every dictation ends in a plain session-visible ⌘V. `wrapMode` answers `.off` while it is up.
- **Measured (`tools/wispr-loop.sh`):** row `formatted` 458–540 ms after mic close, ⌘V dropped
  407–506 ms after, words landed 5–10 ms after the row; hand-started-bound 195 chars in the tty, 0 in front.
- **Identity is signed:** `isWispr` answers from the process name (fail closed), demotes off the tap
  thread unless signed by Team ID `C9VQZ78H85`; cache keyed on `(pid, start time)`.
- **The canary is not optional** — a re-signed tap can report enabled and be inert, and
  `build-app.sh` re-signs every build. `HotkeyTap.proveAlive` posts a stamped bare V key-up at launch
  and after wake (0.9–3.8 ms); a miss flashes for 20 s. `POST /test/firewall` runs one.
- **A missed canary is *blind* before it is *dead*** (2026-09-28): while **any** process holds Secure
  Event Input — the lock screen (raised at display dim), any focused password field, suspected also
  Terminal with a tab in `icanon -echo` (a witness running `stty -echo; cat`) — macOS shows keys to no
  tap (the session's `kCGSSessionSecureInputPID` names the frontmost app, not the caller): the canary,
  every ⌃⌥⌘F gesture and Wispr's ⌘V go unseen, `enabled=true`. That was the 07:06 → 07:14 "dead tap"
  of 09-26 and 09-28 (unlocked 07:13:54, alive 07:14:02). `HotkeyTap.keyboardHidden()` names it;
  the heal waits (2 s poll, no event), re-checks at unlock / screens wake / session active; only a
  miss with keys visible rebuilds the tap (`rebuildTap`: invalidate + new `tapCreate`, at once then
  2/5/10/30 s). `tap: "blind"` + `hidden` on `/test/firewall`; `POST /test/tap {"kill"}` breaks it.
- **A frozen app swallows nothing** (`MainStallGate`, 2026-09-24, after a 32-min deadlock ate a
  61-word sentence): main thread beats every **0.1 s** (0.5 until 2026-09-26); silent 3 s → the tap
  passes every event until it beats and no mouse button is down, and samples into
  `~/.walkie-talkie/hangs/`. Known cost: a stall clearing after Wispr pasted may deliver twice.
  **Since 2026-09-26 (batch 4):** the clock is **uptime** (`HotkeyTap.uptime`, `CLOCK_UPTIME_RAW` =
  `mach_absolute_time`, which does not advance in sleep — `mach_continuous_time` does; the false
  `🧊 195 s` of 09-25 was a closed lid); a 10 Hz watchdog on the tap's run loop opens the gate within
  0.1 s of the threshold and closes it within 0.1 s of the thaw, event or not (TR4: `silent for 3.1 s`,
  was 3.7); `back after N s` is the stall itself, last beat before to first beat after (a 6 s stall
  read `16.4 s`, now `6.1 s`); no trace line per event, a count at the close; the tap's own chords
  are dropped rather than handed through (`mouse-gestures.md`). **The canary is seen while failing
  open** (its own lock, never `stateLock`): `POST /test/firewall` answers `alive: true, tap: "open"`,
  not `alive: false` (TG26). **Not fixed:** a session button stuck down keeps the gate open for as long
  as it is stuck (R24, the 7 h middle button) — the close waits for no button down, by design.
- **Ask Wispr before toggling it** (W6, 2026-09-28): `WisprFlowSource.start()` refuses (*one engine
  at a time*) while Wispr's microphone is open and the relay has none; `stop()` posts no chord for a
  sentence Wispr never took (no row, no microphone, > 1 s after the gesture) — a second toggle there
  would start a ghost recording. `AppDelegate.startDictation`'s *Wispr Flow is listening* refusal now
  asks on Engine = Wispr too (his right ⌥⇧ sentence never sets `isRecording`).
- **No unclaimed-paste rescue** (Q9 step 2, 2026-09-28): `rescueFromRow` is deleted — it had no
  freshness check (W17). `WT_WISPR_FIREWALL=0` for one run.
- **Q9: Wispr's own sentences are Wispr's alone — always** (batch 6 built it behind
  `WT_WISPR_STANDALONE`; **step 2, 2026-09-28, deleted the flag and the old adoption path**;
  `state.wisprStandalone` still answers `true` for the scripts that read it). A Wispr sentence the
  relay did not start: `gestureSeen(relay: false)` and a mic edge nobody asked for return early (no
  ring, no capture, no delivery), his chord never closes the relay's own sentence, and the tap lets
  Wispr's ⌘V through unless the relay owns a Wispr sentence (`setWisprRelayOwned`: from the relay's
  gesture to its machine's idle + 10 s, ceiling 11 min) or a capture is armed. **The 10 s tail is
  row-aware (B, 2026-09-28 wave 3 — it ate 8/8 of his sentences in the lab):** at idle
  `startTailWatch` reads the newest row every 0.2 s; one newer than the relay's floor (its adopted
  row, or the row on top at its chord; with no adopted row also started after the relay's close),
  once the relay's own ⌘V was seen or 1.5 s passed (`WisprOwnership.rowIsHis`), goes to
  `HotkeyTap.noteForeignWisprRow` and his ⌘V **passes** (`⌘V from Wispr Flow passed — row N is
  newer than the relay's…`). A ⌘V still dropped with no capture open asks the rows
  (`claimForeignPaste(floor:)`): his row → pasted at the caret (Q19), the relay's → *the relay's own
  late ⌘V*, logged — never *nothing delivered* in silence. Pure half + tests: `WisprOwnership`. Wispr's ptt is
  `61+60` (right ⌥⇧, Q23); `GET /engine.wisprPttCoherent` is false if it is ever `54+61` again.

## Catching Wispr's words

- **Delivery is a synthetic ⌘V**: keycode 9, flags `0x20100000`, Wispr's pid. The `probe:` log line
  measures it on every dictation. Swallow the `keyUp` with the `keyDown`; leave ⌘ alone.
- **`History` row = completion signal** (`WisprHistory`, `flow.sqlite`, read-only, `mode=ro`, one
  query). One row per dictation, created at the gesture (357 ms) with `status = ''`. `beginCapture`
  takes the newest row **only if its `startedAt` is this dictation's**. Text: `pastedText` or
  `formattedText`. `e2eLatency` p50 2.2 s / p99 7.1 s / max 13.7 s.
- **The readers wake on Wispr's commits, not a timer** (batch 3, 2026-09-28): `WisprHistoryWatch`
  = kqueue on `flow.sqlite-wal` + the main file (re-armed on delete/rename, path or inode change),
  second looks 5/15/40 ms after each event (WAL frames land before the `-shm` index), passes ≥ 4 ms
  apart, a 1 s safety tick; `pollHistory`, the retired-discard and discard-close watches subscribe.
  `WisprHistory.read` runs its query only when `PRAGMA data_version` moved (cache per handle
  generation). Clocked rules ask `wake(after:)`. Measured: 0.6 ms from commit to read (unit test).
  `wisprLive.historyWake` / `rowSeen`.
- **Statuses live in one place:** `WisprState.intermediateStatuses` (`""`, `recording`,
  `processing`) / `terminalStatuses` (`formatted`, `extension_paste`, `extension_other`, `dismissed`,
  `empty`, `no_audio`, `error`, and since batch 3 `raw_transcript`, `fallback`,
  `verification_failed`, `timeout`) / `pasteableStatuses` (Wispr's own: `formatted`,
  `raw_transcript`, `verification_failed`, `extension_paste`, `fallback` + `extension_other`).
  Unknown → terminal + `Log.error`.
- **`raw_transcript` is final** (batch 3, 2026-09-28, from Wispr's code: written only by the final
  update — formatter unfinished or the OpenAI fallback). With words → delivered at once
  (`rawTextSettled` and its 0.8 s grace are deleted); **a pasteable status with no words** →
  `endWithRecording` at once (Q14), not the 8 s `silenceCeiling` (deleted).
- **A Wispr failure falls back on the relay's own recording (Q14, 2026-09-28).** The meter records
  from the **gesture** (`startMeter` in `gestureSeen`), not from Wispr's confirmation. Every failure —
  `error`/unknown status, `empty`/`no_audio`, a pasteable final row with no words, a dead row, a NULL
  row with **no microphone ever seen** 3 s after the close (`nullNoMicCeiling`, W2), no row at all by
  `speculativeGrace`, the capture timeout, Wispr quitting — goes through `endWithRecording`: ≥ 1.5 s
  voiced (`ElevenLabsSource.fallbackVoicedFloor`) → `.failed(audio:)` → `AppDelegate.fallBackToLocal`
  (Wispr allowed since that day) → delivered to the latched destination, `via: local-fallback`; some
  speech under the floor → Recover (`heardNothing`); **< 0.3 s voiced → Recover too since A
  (2026-09-28 wave 3)** — Wispr failed as well, and the meter's *no speech* was wrong 4× in the lab;
  a take the recorder got **no audio** for (`MicRecorder.Health.deaf`: 0 buffers or digital zeros)
  ends `DictationEnd.recorderDeaf`, Recover, never the local model. Every take logs
  `wispr meter: N s voiced — <device>: buffers, peak, tap restarts`; `WT_KEEP_TAKES=1` copies each
  WAV to `~/.walkie-talkie/kept-takes/`. `MicRecorder` restarts its tap on
  `AVAudioEngineConfigurationChange` and after 1 s with no buffer (`🔁 mic:` lines). The row given up on is watched (`watchLateRow`, ≤ 5 min) and held owned
  (`HotkeyTap.holdWisprOwned`): its late ⌘V is dropped and the row only logged — never a second copy.
  **A dead row is let go at once** (batch 3): it produces no ⌘V, and a 5-min hold made every Wispr
  ⌘V the relay's.
- **A prompt carries `asrText`, a plain sentence `formattedText`** (2026-10-06, Victor: *"it keeps
  reframing my words and sometimes confuses the receiving agent … only when prompting"*). Wispr's
  formatter rewrites, the recogniser does not (and already punctuates). `deliver` puts the row's
  `asrText` on `DictationResult.unformatted` every time; `AppDelegate.deliver` swaps it in for an
  envelope (bound terminal, spawn, 🔼 caret prompt), never for 🔽 / right ⌘⌥ clean words or a legacy
  caret sentence. Empty `asrText` → the formatted words. The corpus keeps the formatted text. Log
  `🎙️ prompt carries Wispr's asrText`. `WT_WISPR_RAW_PROMPTS=0` off.
- **The capture reads its own row after adoption** (W4, 2026-09-28): `pollHistory` takes
  `WisprHistory.entry(rowid: historyRow)`, never `newest()` — his own newer row hid the relay's.
- **Q19 (Victor's Q7 = A): his own right ⌥⇧ sentence ending while the relay's row is in flight is
  pasted at the caret by the relay.** The firewall drops the ⌘V (it cannot tell whose it is);
  `claimForeignPaste` finds a newest row **newer than the relay's**, terminal with words, < 120 s old,
  and hands it to `foreignSentence` → `AppDelegate.pasteText` (clipboard + ⌘V at the caret, Q17).
  **Only a row that existed at the drop** (wave 3): a row made after it is a later sentence whose own
  ⌘V may still pass the tap — claiming it would paste it twice. `lastForeignRow` (also set when the
  tap passes a row) keeps any row from being pasted by both. **The pasteboard, once, as the last
  resort** (batch 3): the row is read first; with no words in it at the drop, `pasteboardString()` is
  read then (off main — Wispr's delayed-render item, gone at its restore 500 ms later), refused while
  the clipboard is still the relay's own last write (`PasteboardTimeline.lastOwnCount`), and pasted
  only if the row's words do not come within the claim's 5 s. `POST /test/wispr-paste {"dryClaim"}`.
- **Q15: a Wispr sentence waits behind a held / paused / edited prompt panel** — its answer goes
  through `runAnswer` like every engine's (it used to force-send the panel, W10).
- **Q16: a start while Wispr is still formatting is refused visibly** — flash *⏳ Wispr Flow takes one
  sentence at a time* (`startDictation`, `onCleanHold`); Wispr does not queue.
- **A cancelled Wispr sentence keeps the relay's recording for Recover** (W3): `closeListening`
  keeps the meter WAV even on a cancel, and every `.cancelled` from this source carries it
  (`endCancelledWithRecording`) — it was deleted (*nothing had been recorded yet*) or orphaned.
- **Q2/Q24, bounded by a dead-row verdict** (batch 3, 2026-09-28 — the blind *wait while
  `processing`, ≤ 300 s* is gone): `WisprState.deadRow` (pure, `WisprRowLifeTests`) ends the
  sentence on the commit that shows it — NULL/`processing` with a **newer rowid** (superseded; Wispr
  never finalizes it), **another Wispr pid** than at adoption, still open **1 s after the relay's own
  ⌃Escape** (`relayDismissedAt`: the cancel during the settle; ⌘⌃X while recording), **NULL with no
  `duration` 3 s after the close** and Wispr's mic shut (the stop path never ran). What is left
  `processing` may still finish: `captureTimeout` 30 s, then waits on to `workingCeiling` **40 s**
  from the close (Wispr's e2e p99 4.4 s, max 36 s). A NULL row with no microphone gives up at 3 s (W2).
- **`Opening Wispr Flow...` until Wispr's microphone opens** (Q20): `micOpened` (poll or edge, once
  per sentence, `micSeen`) → `RelayWindow.setOpening(false)`; shot `listening-opening`. The ring is
  not yet told (it still breathes on the relay's own meter) — open item.
- **Timeouts:** `captureTimeout` 30 s (an 81 s dictation was lost at 6 s); `settleTimeout` 8 s; both
  only nets behind the row. The settle steps aside while `phase.isWaitingForWords` — **with no
  ceiling since 2026-09-26** (it gave up at 30 s and a new sentence could start under a late reply:
  TL8, TL15, TR11, TL25); every recogniser bounds itself (Scribe 20 s + one retry, Wispr's 30 s
  capture, the local model's 90 s / 300 s). **Every start refuses while the words are in flight**
  (`startDictation` checks `phase.isWaitingForWords` too, as the side buttons did) and says which
  flag refused and how old it is; a `listening` with no recorder behind it for > 30 s is put down by
  the gesture that meets it (TR18). → journal: *Fixes to the test plan's findings, batch 3*
- **The pasteboard is an answer only when the relay asked it one** (`askedForCopy`) — otherwise it
  delivered whatever Victor had last copied. Wispr restores the clipboard after its ⌘V: arm at the
  start chord, refuse a pasteboard identical to the pre-dictation one, read the string the instant it
  changes (three sentences became a Word rental contract, 2026-09-13).
- **A Wispr that quits mid-sentence is not his stop** (batch 4, item 3 — TQ2/TW20 cut the take at
  the kill): a Wispr-side close of a relay sentence (poll, CoreAudio edge) asks `ProcessClock.isAlive`
  on `wisprPidAtChord` (kernel table, zombie = dead), again 0.3 s later (`quitCloseGrace`); gone →
  `abandonForDeadWispr` → `holdOwnTake("Wispr Flow quit")`, alive → `closeListening` as before. Desk:
  `POST /test/wispr-proc {"fakeExit": true}` (no signal), TW42.
- **Wispr's exit is watched, not polled** (batch 4, item 5 — TW20's quit took 1.48 s once the WAL
  watch replaced the 150 ms poll the check rode on): `ProcessExitWatch` (`NOTE_EXIT`) on the pid at
  every capture → `abandonForDeadWispr` at once. `wisprLive.exitWatchPid` / `exited`.
- **A Wispr that quit is not slow:** `pollHistory` checks the main process by the anchored path
  `/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow` (two absences, 300 ms) **and** compares
  the pid read at the chord (`wisprPidAtChord`) — the harness relaunches Wispr in 200 ms.
- **Wispr out of the sentence is not his stop — the relay's own recording carries it** (batch 4,
  2026-09-29, F1: TW4's Q14 answer went to the caret the previous sentence had latched, because
  the 12 s `speculativeGrace` ended the sentence under him with no close on this side).
  `holdOwnTake(why)`: a relay sentence with no row and no microphone at 12 s is **not** ended — the
  capture is let go, the meter keeps recording, `isRecording` stays, `phase` answers `.listening`
  (`ownTakeOnly`, `wisprLive.ownTake`), Wispr's mic edges are not this sentence's, the E watch may
  still dismiss a late ghost; chip `💻 <why> — this Mac keeps recording; stop as usual`. **His stop**
  (`stop()` posts no chord, `closeListening`) latches the recipient like any close, then
  `endWithRecording` → Q14. Cancel and ⌘⌃X work on it (no ⌃Escape posted). Belts in `AppDelegate`:
  `dictationBegan` clears `latchedAtCaret`/`latch`; a fallback for a sentence never closed on this
  side latches then (`latchIfNeverClosed`), and the next stop gesture within 30 s while its words are
  out is taken as its stop — nothing re-routed, nothing opened (`closedForHimAt`).
- **E, the ghost microphone** (lab wave 3; E-FP fixed batch 4): after a relay chord Wispr never
  answered, a 25 s watch dismisses (⌃Escape) a Wispr microphone opening with no sentence behind it
  (`WisprOwnership.ghostMic`). **Disarmed by the next relay chord**, and never while a relay capture
  is in flight (a microphone still open after the relay's stop while Wispr finishes its row — TW8a in
  wave 4 was dismissed that way, its row declared dead).
- **A stop chord Wispr did not take is posted again, then dismissed** (2026-10-01,
  `WisprState.stopWasLost`, `verifyStopTook`): 1.2 s after the relay's stop, row still NULL with no
  `duration` **and** Wispr's microphone open → one more toggle; still so 1.2 s later → the sentence
  ends on the relay's recording (Q14, local model) and **then** ⌃Escape (a `dismissed` row reaching a
  live capture reads as his cancel). ⌘⌃X in flight dismisses such a Wispr too. Measured: 527/536
  stops left NULL in ≤ 453 ms; on 17:31:00 a clean chord left row 18156 listening 435 s.
- **A new dictation retires a standing capture only if its row is terminal**
  (`retireCaptureIfSettled`); otherwise it throws away the sentence in flight.

## Witnesses and phases (`WisprState`, 2026-09-13)

| witness | proves | measured |
|---|---|---|
| the chord this app posts | a dictation was asked for | the clock |
| `History` row appears | Wispr took the chord | 357 ms |
| 100 ms poll of `IsRunningInput` | a mic is open | 607 ms |
| `WisprWatch` notification | same, pushed | 5590 ms — 0–6 s late, often silent |

- **Arm the capture at the start chord, never from the CoreAudio edge** (a 2.5 s dictation went into
  Word with the relay blind). A witness that never saw the mic open may not report it closing.
- **The gesture opens the dictation; the mic edge only confirms, never re-opens** (warm 324–674 ms,
  cold 5–6 s). `speculativeGrace` 12 s, and may only retract a ring for a chord that left **no row**.
- **The relay's own stop closes listening** (`closeListening` — also releases any held chord).
- **A late OPEN edge belongs to the last sentence** (`lateOpenEdge()`, asked before `state.notify`):
  our stop is the latest event (≤ 12 s) and either its capture is open or no newer row exists.
- **The machine owns nothing** (no timers, CoreAudio, SQLite, AppKit) — hence
  `POST /test/wispr-state/simulate` as its unit test.
- **A 🔼 click while words are in flight is a stop or nothing**, never a new dictation.
- **A dictation Victor starts himself** (his chord, or 🔽 →) is ring-only in the pre-firewall model:
  `relayStarted` false. Under the firewall the words are still the relay's to deliver.

## Cancel during the settle

- **A cancel after the microphone closed disowns the transcript in flight** (2026-09-26, R2).
  ElevenLabs cancels its upload (`ElevenLabsSource.Upload`, task + retry), the local source marks
  its decode (`LocalWhisperSource.Decode`), both end `.cancelled(audio:)` so the WAV goes to
  Recover; `AppDelegate.transcriptDisowned` makes `deliver` drop anything that still arrives and
  `fallbackToken` drops a fallback's late answer. Before, `🗑️ Cancelled` was followed by the words
  (TL10, TL11, TG8, TG9). → journal: *Fixes to the test plan's findings, batch 1*

- **Never disarm while Wispr may still paste.** A cancel sets `discardOnArrival`: whatever arrives
  (⌘V, row, note, or nothing by `captureTimeout`) is swallowed and dropped. `cancel()` calls
  `state.reset`; `pollHistory` does not feed `sawRow` while discarding.
- **…but it may not block the next gesture:** `retireDiscardedCapture` releases everything except the
  swallow, keyed by `retiredDiscardRow` (`WisprHistory.entry(rowid:)`), let go at terminal +
  `pasteGrace`, on its ⌘V, or at 5 s. `injected(from:)` checks the retired row before `capturing`.

## The Scratchpad wrap — dormant, kept

Superseded as the delivery by the firewall; the code stands (`wrapMode` · `wrapWhy`, `POST
/test/wrap-mode`). Modes: `scratchpad` (hold *Open Scratchpad*, deliver from the row), `sink`
(emergency, takes the key window at the stop), `off`. Falls back to `sink` when Wispr has no
`open_scratchpad` shortcut or the window will not close. Order: **start from CLOSED** (open window →
no note, sentence lost) → hold the chord (`open_scratchpad` by action name, fallback `79`/F18,
`WISPR_SCRATCHPAD_KEYS`) → park on sight (25 ms watcher; smallest size, bottom-right of the second
display, 8 pt sliver; re-park every open) → release, ask the close **exactly once** → deliver from
the row → cross-check the note 3.5 s later (new portion only, case/punctuation normalised).
Numbers: row 400–530 ms, words 410–490 ms, note readable 2627 ms, close 417–445 ms, window layer 3,
min 300×300. Traps, all paid for:

- **The close is a toggle.** Only `WisprScratchpad.ensureClosed(reason:)` closes it; it re-checks
  existence at post time (`tapWisprScratchpad(if:)`) and 0.6 s after (`the close opened it —
  toggled back`). A queued **hold** carries `dictationEpoch` and is dropped if stale; a release is
  never dropped for a stale epoch. Chord presses are **250 ms** (60 ms does not toggle), on a serial
  queue, onto a bare wire, 120 s dead-man's switch.
- **Idle orphan sweep** (`startIdleSweep`): any window standing > 1 s while idle is closed.
- **Never minimize or hide the Scratchpad mid-dictation** — the sentence never comes back.
- **The Scratchpad becomes KEY without its app becoming frontmost** — never test focus with
  `frontmostApplication`; no AX focus reading is true either way; the system-wide focused element
  returns `kAXErrorCannotComplete` here. The gate is the window's **existence**.
- **Keys while it is up are redirected** (`armKeyRedirect`, ⌘/⌃ pass, per-key target resolved and
  `kill(pid,0)`-checked at the keystroke, 10 s ceiling): printables via **`AXSelectedText`** on
  `HotkeyTap.axQueue` (200 ms/char; a frontmost app with no key window drops posted characters),
  non-printables by `postToPid`. 7/7 letters measured — **only under the loop's lock**; two harness
  instances once contaminated a night of readings. Counters `seen`/`redirectedAX`/`redirectedKey`/
  `passed`, zeroed at the chord.
- **Never call a TIS function from the tap** — `TISGetInputSourceProperty` asserts main and traps;
  `refreshKeyboardLayout` caches a `Data`.
- **Wispr's close activates Wispr** → `putTheFrontBack` via `AXFrontmost` (plain `activate` is
  declined for a background app), only when Wispr is frontmost, never during the sentence. The rig's
  `frontmost_app()` (System Events) cannot see a stolen front; read `NSWorkspace`.
- **The addressed paste:** `DictationResult.focusPid` (the app at the chord) → `pressPaste(to:)` via
  `postToPid`; nil for every other delivery.
- **The sink** (`WisprSink`) is a test instrument / emergency mode; refused (409) as key window during
  a Scratchpad dictation. Victor rejected focus-stealing as the primary path. A correct run leaves it empty.

## Stale ⌘ (the bug of `area-crop.md`, occurrences 3–7)

Any post of a key with modifier flags must be followed by a `flagsChanged`: `POST /test/gesture`
clears its own flags; `SelectionCapture.read()`'s ⌘C posts the trailing `flagsChanged` and is stamped;
Wispr's own let-through ⌘V leaves ⌘ down, so the tap posts the clearing event;
`clearStaleModifiersAtLaunch()` (after `SingleInstance.enforce`) heals one left before launch,
per modifier, against `keyState` on both keycodes. `evals/test_stale_modifier.py` guards the source.

## ElevenLabs Scribe (2026-09-18)

- **`LocalWhisperSource`'s shape with an HTTPS `POST`** to `api.elevenlabs.io/v1/speech-to-text`
  (multipart, `xi-api-key`) of one 16 kHz mono WAV the relay recorded. No wrap; corpus audio = the
  transcribed audio. 3.0% WER Romanian (FLEURS); `scribe_v1` $0.40/h, `scribe_v2` $0.22/h —
  price in `ElevenLabsSource.rate`, keyed by model.
- **Key:** `~/.walkie-talkie/elevenlabs.env` (`ELEVENLABS_API_KEY=`), env first, **follows `--home`**
  (a test relay cannot bill), re-read on every menu open. A file: launchd gives no shell; Keychain prompts.
- **Language is not pinned** on the batch transcript — his Romanian carries English terms. `WT_ELEVEN_LANG=ro` for comparisons.
- **The live socket also sends 50 `keyterms`** (first column of `~/.walkie-talkie/vocab.txt`, re-read per session) and `vad_silence_threshold_secs=1.5`; **after 3 s without new words it uploads the audio since the last cut to the batch model and replaces the live segments** (`ElevenLabsLive.correctIfPaused`, `gentle` corrections on the band). `ElevenLabsCost` keeps the running bill (`/test/state.elevenCost`; off the menu rows since 2026-09-28). (2026-09-26)
- **The live caption IS pinned to `ro` + `secondary_languages=en`** (2026-09-26, a caption came back Turkish): `ElevenLabsLive.languages`, `WT_ELEVEN_LIVE_LANGS=ro,en` overrides (first = `language_code`, rest = `secondary_languages`, repeated query keys; probed 2026-09-26 on a corpus WAV, English transcribed fine under it). `WT_ELEVEN_LANG` set wins for both.
- **`DictationEnd.failed`** ≠ `.silent` (drops audio) ≠ `.cancelled` (keeps it quietly): 12 s banner
  + WAV staged for *Recover Dictation*. One retry, only for transport/429/5xx; `requestTimeout` 20 s.
- **An empty transcript is `.failed(why: DictationEnd.heardNothing, audio:)`, never `.silent`**
  (2026-09-26, §3.8 — the WAV used to be deleted; 60 s of speech lost 09-19 and 09-20). Scribe `""`
  and a local answer with no words both; `.silent("")` is only a take under 0.35 s. **No local
  fallback for `heardNothing`**: Whisper on 3 s of silence answered `www.clu.com.br` and it was
  delivered (TL16, first try). → journal: *Fixes to the test plan's findings, batch 1*
- **Except with real speech (Q8, 2026-09-26 batch 6):** a Scribe `""` on a take with **≥ 1.5 s voiced**
  (2.0 until Q13, 2026-09-27; `MicRecorder.voicedSeconds`, read at the close in `ElevenLabsSource.stop`,
  `fallbackVoicedFloor`) is an ordinary `.failed` → the local model stands in. Under it stays
  `heardNothing` (WAV kept, banner, nothing delivered).
- **The same floor on every Scribe failure (2026-09-27, batch 7):** 401/quota, 429, 5xx, timeout,
  transport, a key gone mid-sentence — `ElevenLabsSource.finishWithFailure` ends a take under the
  floor as `heardNothing` (the cause stays in the log line), so it never reaches `fallBackToLocal`.
  With the quota out (27 Sep) every silent take became a local decode otherwise. **Short real
  sentences fell under 2 s:** the 3.5 s `CLIP_EN` measured 1.1–1.9 s voiced because 1365-frame
  buffers each dropped a tail the meter never saw — hence Q13 (floor 1.5 s, the meter carries the
  tail, `whisper-and-corpus.md`). Fallback cases still play `CLIP_SPEECH` (12 s). TL16.
- **Unmeasured:** `languageFloor = 0.5`, `scribe_v1` vs `v2`. `tools/eleven-test.sh [wav | --corpus n]`.

## Markers: where a picture was taken

- **Timestamp markers (2026-09-19, current, `ShotMarker.place`, `WT_MARKER_TIMESTAMPS=0` off).**
  Scribe's `words[]` carry `start`/`end` on the WAV this app recorded; a press measured on the same
  ruler (`MicRecorder.offset(of:)` — frames written, answered backwards, ≤ 85 ms buffer correction)
  lands between words. Only for a source with `audioOffset(of:)`; Wispr answers nil and frames keep
  their `mm:ss` rows under the words.
- **The local engine places them too since 2026-10-04.** Until then `LocalWhisperSource` had **no**
  `audioOffset(of:)` (the protocol default nil — this file claimed otherwise) and the helper sent no
  timings: outbox 135 local dictations, 224 shots, **0 inline**. Now `whisper_helper.py` decodes with
  `word_timestamps=True` (OpenAI's six turbo alignment heads, `RELAY_WHISPER_ALIGNMENT`), answers
  `words[{text,start,end}]` (Whisper's leading spaces kept, so they join into `text` — else
  `LocalWhisper.Result.timedWords` drops them), the source answers `meter.offset(of:)`, and both
  `didTranscribe` and the local fallback hand `words` to `resolvingMarkers`. Precision, cost:
  `evals/local-word-timing/`; desk proof `evals/test_local_marker_place.py`.
- **Reserved at the gesture, keyed by path** (`shotMarkerNumbers`, before `screencapture` runs); the
  safety net is a **set** of real pictures, not a count. `ShotMarker.render` is the one vocabulary.
  Selection numbers are reserved under `fileSelection`'s lock (`reserveMarkerLocked`) and spoken after.
- **Cues without `words[]` place nothing and never fall back on `resolve`** — every match would be his
  own words rewritten. The corpus copy is his words untouched (`resolvingMarkers(inline: false)`).
- **`evals/test_marker_place.py`** — ten seam cases via `POST /test/shot-marker`; safe mid-workshop.
- **Spoken markers — RETIRED 2026-09-18 for every engine** (`WT_SHOT_MARKERS=1` revives; back on Wispr, below): a clip played into
  `🎓 TO Wispr` said `screenshot one`; Scribe heard `Pict element one` and the phrase stayed in the
  sentence. Fails per engine/language/accent. Mechanism notes (gap gate `quietSeconds ≥ 0.12 s`,
  1.5 s ceiling; masking is not a level problem) are in the journal.
- **Spoken markers are back on Wispr only (2026-09-30, `ShotMarker.wisprSpoken`, `WT_WISPR_MARKERS=0`
  off)**, measured in `evals/wispr-markers/`. His recorded `screenshot N` came back in `asrText` 37/40
  in place; `say` got 11/20, because Wispr's recogniser drops a second speaker.
  - `WisprFlowSource.mark` queues the clip and splices it into the bridge's stream at his **next
    pause** (`markerPause` 0.3 s of `quietSeconds`, no ceiling); a marker still waiting at the stop
    goes straight to the bridge.
  - `AudioBridge.noteMarker`: the marker is never dropped as a pause and plays at 1.0; the pacer
    then catches up on the voice queued behind it (`🔀 caught up after the marker in N s`).
  - `ShotMarker.resolveStrict` reads the numbers from the row's `asrText` (`DictationResult.asr`,
    `said`). It places every marker, aligned into the formatted words, or places none (the footer
    with clocks), and strips the phrases either way.
  - With nothing said, nothing in a Wispr transcript is rewritten.
  - The dry run is `evals/wispr-markers/dryrun.py`.
- **Four of his recorded clips are mis-cut** (`screenshot-3`, `selected-text-6`, `selected-text-8`,
  `picked-element-6` also carry the next marker's words). The strict check falls back on the
  phantom number.
- **No live captions:** Scribe realtime gives timings only on committed text from a smaller model.

## Voice affect: what the transcript loses (2026-09-27, `VoiceAffect`)

Victor's rules (spec `~/workspace/voice-distill/docs/voice-affect.md`, *Design propus*): **two
global tags, `[voice: hesitant]` / `[voice: tense]`, otherwise nothing**; the tag says only what
transcription lost — no numbers, nothing concluded from the words; **more important: `[?]` WHERE
he hesitated**; what the agent does about it lives in CLAUDE.md, not in the tag. → journal:
*Voice affect* (2026-09-27)

- **Per sentence, on its own words and take** (Q12 keeps two in flight): `MicRecorder.meterHops`
  (64 ms hops, `t` on the WAV's ruler, ≤ 12 000, own lock) is read at the close on `audioQueue`
  and rides `DictationResult.voiceHops`. Only ElevenLabs has `words[]`; local and Wispr get nothing.
- **`[?]` goes in as a token before `ShotMarker.place`**, before the word after a gap ≥ `longPause`
  (≥ `boundaryPause` after `.?!`; `…` is not a boundary). A gap holding a shutter/selection press
  (`markerCues` ± 0.3 s) is the gesture's — never marked, so a `[?]` never sits inside a marker.
  Text rebuilt from the marked tokens only if the words spell the transcript; the corpus copy uses
  the unmarked words.
- **`[voice: hesitant]` is one line right after `[Dictated in RO or EN]`** (`terminalLine`), only on
  a positive verdict; outbox `affect: {pauses, fillers, restarts, rate, verdict, why, …}`; corpus
  nothing. Applies to a bound terminal, a spawn, the forward click's caret prompt — never the back
  click's plain words or a legacy caret sentence.
- **Thresholds** (`VoiceAffect.Thresholds` defaults = `voice-affect.json`'s top-level `thresholds`,
  from his 2,369-clip distributions, journal *Voice affect*): `[?]` at a gap **≥ 2.5 s** (≥ 3 s
  after `.?!`; a file `gaps.p97` never sets it lower — `longPauseFloor`). **Hesitant = 2 of 6
  signals**: pause ratio ≥ 0.35 · ≥ 4 gaps over 1 s · rate < 1.4 **words**/s · lead > 3 s ·
  ≥ 2 restarts · ≥ 2 fillers and ≥ 8 % (Scribe keeps fillers; Whisper does not). Gesture gaps count
  for none of it.
- **Tense = the energy-spread half only**, behind `WT_VOICE_TENSE=1`; pitch/arousal is not
  measured. Never infer either tag from the words.
- **`POST /test/affect`** — verdict + marked text from fabricated timings; `VoiceAffectTests`.

## Every switch the dictation source reads

| variable | effect |
|---|---|
| `WT_SOURCE=whisper｜eleven｜wispr` | engine for one run (the menu writes `dictationSource`) |
| `WT_WISPR_ENGINE=0｜1` | overrides `StatusItem.wisprEngineDefault` (`true`: Wispr Flow is the last row of the Engine list): env → `elevenlabs.env`, re-read at every menu build; `GET /engine.wisprRowShown` says whether the row is there. `POST /engine {"id":"wispr"}` picks it either way |
| `WT_WISPR_FIREWALL=0` | let Wispr's ⌘V through (`POST /test/firewall {"on": false}`) |
| `ELEVENLABS_API_KEY` · `WT_ELEVEN_MODEL=scribe_v2` · `WT_ELEVEN_LANG=ro` · `WT_ELEVEN_LIVE_LANGS=ro,en` | key; model (default `scribe_v1`); pinned language (off); the live caption's language set (default `ro,en`) |
| `WT_WRAP_WISPR=0` · `WT_WRAP_MODE=scratchpad｜sink｜off` | wrap off / forced mode (`POST /test/wrap-mode`) |
| `WT_SCRATCHPAD_DELIVER=note` | deliver from the note (2.8 s slower) |
| `WT_SCRATCHPAD_REDIRECT_KEYS=0` · `WT_SCRATCHPAD_AX_INSERT=0` | key redirect off / redirect by `postToPid` |
| `WT_SCRATCHPAD_NOTE_MAY_DELIVER=1` | let the note be delivered as text |
| `WISPR_SCRATCHPAD_KEYS=79` | *Open Scratchpad* chord override |
| `WT_WISPR_HISTORY_ROUTE=0` | wait `pasteGrace` for a ⌘V before the row |
| `WT_KEY_TRACE=1` | log every key event + verdict, keycode/pid only (`POST /test/key-trace`) |
| `WT_MARKER_TIMESTAMPS=0` · `WT_SHOT_MARKERS=1` · `WT_MARKER_DEVICE` | timestamp markers off / spoken on / device |
| `WT_VOICE_AFFECT=0` · `WT_VOICE_TENSE=1` | `[?]` marks + `[voice: hesitant]` off (default on) / the energy half of `[voice: tense]` on (default off); env → `elevenlabs.env` → `voiceAffect` / `voiceTense` defaults |
| `WT_WISPR_RAW_PROMPTS=0` | prompts carry Wispr's `formattedText` again instead of `asrText` (2026-10-06) |
| `WT_WISPR_COPY_FALLBACK=1` | re-enable `copy_last_text` — see below |
| `WT_WISPR_DB=<path>` | a fake `flow.sqlite` instead of Wispr's (test-only, 2026-09-28): env → `elevenlabs.env`, re-read ≤ 1 s; `evals/plan/fake_wispr_db.py` (`desk-testing.md`) |
| `WT_ELEVEN_LIVE_URL` · `WT_ELEVEN_BATCH_URL` | the realtime socket / batch upload somewhere else (2026-09-27): env → `elevenlabs.env`, read at every engine pick; the harness points them at `evals/plan/fake_scribe.py` (`desk-testing.md`). Default `wss://api.elevenlabs.io/v1/speech-to-text/realtime` · `https://api.elevenlabs.io/v1/speech-to-text` |

## Do not

- **Read Wispr's DB as a recogniser or transcript fallback.** `flow.sqlite` is read only by
  `WisprHistory`, for a row's status and its words; nothing of Wispr's ever transcribes.
- **Turn `copy_last_text` (⌘⌃C) back on by default** — after a failed sentence it hands back the previous one.
- **Cancel an insertion Wispr has decided on** — 57 ms between `formatted` and the ⌘V; ⌃Escape after it does nothing.
- **Revoke Wispr's Accessibility grant** — Wispr must keep working standalone.
- **`open -a "Wispr Flow"`** — resolves to the nested helper, which quits; `pgrep -x` matches it too.
  `open "/Applications/Wispr Flow.app"` and match the anchored executable path.
- **Delete `LocalWhisperSource`** — offline fallback and the evals' baseline.
- **Give the corpus tag a default branch** — `local` · `wispr` · `11l`, unknown keeps its own id;
  a mislabelled sample in the corpus is worthless forever.
- **Pin `language_code`** for the cloud engine.

## The "From Walkie" microphone follows the relay's life (2026-09-29)

`FromWalkieDevice` turns the BlackHole-built device **"From Walkie"** (`../from-walkie`, box UID
`FromWalkie_UID`) on at launch and off in `applicationWillTerminate` — **not** when a restart is
replacing the instance (the newcomer turns it on; an off/on blip bounces Wispr to its next mic and
back). A crash is covered by Victor Addons' watchdog (5 s poll, device off when the relay is gone).
The switch is `kAudioBoxPropertyAcquired` — no GUI, no sudo. The device reports **USB**, because
Wispr's microphone list hides every Virtual device.

## The bridge feeds From Walkie — every Wispr sentence (2026-09-29)

Victor: *"not miss the first half a second or a full second of speech"* and *"a single source to
select the input microphone … not have Wispr Flow pick a different device than I picked in
walkie-talkie"*; then *"fed with a bit of an offset … a speed up of the voice to 1.1x … after a few
seconds there should be no lag"*. Wispr's microphone is From Walkie (it still lists it under its old
name `Wispr Feed`); his microphone is `InputDevice.resolve()`, for Wispr too.

- **`AudioBridge` is on by default** (`WT_BRIDGE=0` off, `WT_BRIDGE_DEVICE` overrides the needle
  `From Walkie`). **Held until Wispr's input runs**: From Walkie is BlackHole, what is written before a
  reader opens is gone. `start(holding: true)` at the gesture; `release()` when
  `WisprWatch.sampleIsRunningInput()` turns true (the 25 ms feed watch, `feedWatchTick`).
- **Back to live, `BridgePacer`** (pure, `BridgePacerTests`): the silence ahead of the first word is
  cut at the release (0.3 s pad kept), pauses are shortened to 0.25 s while lagging, and the player
  runs faster through `AVAudioUnitTimePitch` while more than **0.2 s** is queued — live is ~one 85 ms
  buffer, a faster queue would starve mid-word. **1.1× just behind, rising with the lag to `maxRate`
  at 3 s behind** (2026-09-30; `WT_BRIDGE_RATE`, `WT_BRIDGE_MAX_RATE`). `maxRate` is **the fastest
  Wispr still transcribes** — Victor: *"accelerarea asta trebuie să aibă un anumit plafon … îmi asum
  această procesare întârziată"* — **1.25**, measured on 12 of his clips (`evals/wispr-catchup/`,
  *Wispr's ceiling*): clean at 1.25×, his fastest Romanian breaks at 1.35× (WER 0.06 → 0.51). Flat 1.1×
  took a median 7.9 s to catch up from 5 s late. Log: `🔀 bridge released (…) N ms after the gesture
  — held, cut, behind live`, `🔀 bridge caught up … live X s after`.
- **The relay's stop waits for the whole queue** (`bridgeDrainSeconds`) — **no ceiling since
  2026-09-30** (was 8 s, 3 before that): what the capped speed could not absorb is his sentence, and
  he accepts the wait. Only a queue that has not shrunk for **2 s** (`drainStall`, a stuck player)
  ends it early; the teardown after the recorder waits the same way. And **for Wispr's input** when
  the bridge is still holding (≤ 2.5 s, `stopWaitsForInput`; past it the chord goes and Q14 carries
  the take).
- **His own Wispr sentences get a feed too** (`Feed.own`): Wispr listens to From Walkie, so without
  one it hears silence. Started by right ⌥⇧ (`HotkeyTap.onWisprPushToTalk`, watched never taken), his
  fn ⌃ Space (`gestureSeen`, relay: false), or Wispr's input seen running with no feed (200 ms idle
  sample, for his Wispr-window starts). Metering only — nothing written, Q9 unchanged; ends 0.3 s
  after Wispr's input closes, or 3 s with no input. Its tail is Wispr's to cut: a released
  push-to-talk stops Wispr with whatever catch-up is still queued unheard. A relay gesture takes the
  microphone over from it (`startMeter`).
- **The right ⌘⌥ hold is Wispr's again on Engine = Wispr** (2026-09-29, Victor: *"it should use the
  same engine for transcription everywhere"* — Q21's local borrow reversed). fn ⌃ Space under the held
  pair reaches Wispr as ⌘⌥fn⌃Space and is ignored (measured twice). So Wispr has a **second hands-free
  shortcut, right ⌘ + right ⌥ + F19 (`54+61+80: popo`)**, registered through its Shortcuts window, and
  the hold posts only F19 under his fingers (`HotkeyTap.postWisprHandsFreeUnderHeldPair`, stamped, no
  bare-wire wait); the release stops with the usual fn ⌃ Space. Measured: row + microphone within ~1 s.
  `heldPairChordIsConfigured` reads Wispr's config; without that shortcut the hold borrows the local
  model as Q21 did. **The start chord waits up to 1.5 s for a bare wire and logs it** (`⌨️ fn ⌃ Space
  posted N ms after the ask`); it was 200 ms and silent.
- **No `AVAudioEngine` call in the bridge may raise into Swift** (2026-09-30, after two guest `SIGABRT`s in
  `-[AVAudioPlayerNode play]` from `AudioBridge.start`, `evals/wispr-catchup/`): every one goes through
  `WTTry` (`Sources/ObjCTry`, an `@try` shim — Swift cannot catch an `NSException`). `start` is
  `engine.start()` + `isRunning` + `play()`, one retry, else `false` (the *no device* path → Q14). An
  `AVAudioEngineConfigurationChange` mid-take re-aims and restarts it (≤ 3 a take, `🔀 audio bridge back
  after a device change`); past that, or with From Walkie gone, `die()` takes it down with the counts at
  zero so the stop chord does not wait for audio nobody will play. `ObjCTryTests` pins the guard. The
  guest's crash reports kept no exception text, so the exact condition is still a guess.
- `GET /test/state` → `wisprLive.bridge` {`feed`, `holding`, `held`, `queued`, `pending`}.

## A Wispr whose microphone does not open is out of the sentence at 3 s (2026-10-08)

Victor: *"dictation hangs with «opening wispr flow». why? + that should autofall back to local model
not hang"*. 14:33:54: Wispr (up 29 h) made row 18613 and never opened its microphone; the chip said
`Opening Wispr Flow...` for 12 s, the stop waited 2.5 s for an input that never ran, and Q14 refused
the take at 1.2 s voiced (under 1.5 s) — Recover later decoded 40 chars from it. 14:34:34: no row, no
microphone; he cancelled at 2.8 s.

- **`WisprFlowSource.micOpenGrace` 3 s** (`armMicOpenWatch`, armed beside the chord probe on every
  relay start): no microphone seen by then, row or not → `holdOwnTake` (`💻 Wispr Flow's microphone did
  not open in 3 s` / `did not answer the chord in 3 s`) — the chip drops `Opening`, his stop posts no
  chord, the local model transcribes the relay's take; Wispr's open row is dismissed (⌃Escape) and
  `armGhostWatch` dismisses a late microphone. F1's 12 s `speculativeGrace` is now only the net.
- **A take Wispr never heard falls back at 0.3 s voiced, not 1.5 s** (`endWithRecording`: floor =
  `micSeen ? fallbackVoicedFloor : 0.3`). The 1.5 s floor guards a sentence Wispr heard and mangled.

## Diagnostics for a Wispr that will not start (2026-09-29)

Three log lines, no behaviour behind them (journal: *Wispr as the engine, 29 Sep*):
`📮 Wispr has not answered the start chord 1.5 s after it` (how the chord left — or that it never
did — Wispr's pid/age/input, the row on top, session + HID flags, Secure Input, the front app);
`🎙️ Wispr's input reopened N s after the relay took its close as the end of row R` (a poll close that
was a blip); `wispr history: row R recorded X s, the relay closed its take at Y s`. Grep these first.

- **A relay stop over a start Wispr never took** (no row, no microphone, > 1 s) posts no chord and
  goes to the local model at once (`ownTakeOnly`) — W6's `!isRecording` never held for a relay start.
- **The raw toggle's stop asks W6 too** (2026-10-02, `HotkeyTap.onWisprRawStop` →
  `WisprFlowSource.rawStop`): 🔽 →, F5 and the back click used to post the stop straight from the tap,
  past `stop()`. At 11:07:00 F5's start was lost and the stop chord *started* Wispr (row 18220, written
  at the stop, left listening). Now the tap hands the stop to the source on main, which posts no chord
  for a lost start. Net under it: W2 (NULL row, no microphone seen, 3 s after the close) dismisses
  (⌃Escape) a Wispr found listening on that row, if it is still the newest.
- **A Wispr-side close whose row is still NULL with no `duration` is not Wispr's end** (`nullRowHold`):
  up to 4 s from the input going off; the input back → the sentence goes on, the row moving → ended
  as before, the ceiling → `holdOwnTake`. A blip under the F19 hold cut the take at 2.8 s of 10.
