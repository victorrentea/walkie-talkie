---
paths:
  - "Sources/WalkieTalkie/DictationSource.swift"
  - "Sources/WalkieTalkie/WisprFlowSource.swift"
  - "Sources/WalkieTalkie/LocalWhisperSource.swift"
  - "Sources/WalkieTalkie/ElevenLabsSource.swift"
  - "Sources/WalkieTalkie/ShotMarker.swift"
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
- **Push-to-talk ends when the ⌘⌥ pair goes up** — `onWisprPushToTalkReleased` → `closeListening`,
  gated on `startedByHeldPair` and `isRecording`. `onWisprMaybeStarting` carries a `WisprStart` so
  the release pairs with its own press. Once Wispr's row confirms a held-pair dictation it opens the
  sentence (`confirmSpeculative` → `didBegin`, caret mode: no picture, no probe).
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
- **A frozen app swallows nothing** (`MainStallGate`, 2026-09-24, after a 32-min deadlock ate a
  61-word sentence): main thread beats every 0.5 s; silent 3 s → the tap passes every event until it
  beats and no mouse button is down, and samples into `~/.walkie-talkie/hangs/`. Known cost: a
  stall clearing after Wispr pasted may deliver twice.
- **An unclaimed ⌘V is rescued from the row** (`rescueFromRow`). `WT_WISPR_FIREWALL=0` for one run.

## Catching Wispr's words

- **Delivery is a synthetic ⌘V**: keycode 9, flags `0x20100000`, Wispr's pid. The `probe:` log line
  measures it on every dictation. Swallow the `keyUp` with the `keyDown`; leave ⌘ alone.
- **`History` row = completion signal** (`WisprHistory`, `flow.sqlite`, read-only, `mode=ro`, one
  query). One row per dictation, created at the gesture (357 ms) with `status = ''`. `beginCapture`
  takes the newest row **only if its `startedAt` is this dictation's**; polls every 150 ms. Text:
  `pastedText` or `formattedText`. `e2eLatency` p50 2.2 s / p99 7.1 s / max 13.7 s.
- **Statuses live in one place:** `WisprState.intermediateStatuses` (`""`, `recording`,
  `raw_transcript`, `processing`) / `terminalStatuses` (`formatted`, `extension_paste`,
  `extension_other`, `dismissed`, `empty`, `no_audio`, `error`). Unknown → terminal + `Log.error`.
- **`raw_transcript` with words in it is finished** — Wispr never flips it (21 rows / 30 days).
  `rawTextSettled` reads it as `formatted` after `rawTextGrace` 0.8 s of stillness, for the switch
  only. Text columns normally appear in the same tick as the terminal status (`tools/wispr-row-watch.py`).
- **A row with nothing in it stops being progress after 8 s** (`silenceCeiling`) → *"No speech was
  heard"*; `asrText` exists to tell *thinking* from *heard nothing*.
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
- **A Wispr that quit is not slow:** `pollHistory` checks the main process by the anchored path
  `/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow` (two absences, 300 ms) **and** compares
  the pid read at the chord (`wisprPidAtChord`) — the harness relaunches Wispr in 200 ms.
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
- **The live socket also sends 50 `keyterms`** (first column of `~/.walkie-talkie/vocab.txt`, re-read per session) and `vad_silence_threshold_secs=1.5`; **after 3 s without new words it uploads the audio since the last cut to the batch model and replaces the live segments** (`ElevenLabsLive.correctIfPaused`, `gentle` corrections on the band). `ElevenLabsCost` keeps the running bill (menu rows). (2026-09-26)
- **The live caption IS pinned to `ro` + `secondary_languages=en`** (2026-09-26, a caption came back Turkish): `ElevenLabsLive.languages`, `WT_ELEVEN_LIVE_LANGS=ro,en` overrides (first = `language_code`, rest = `secondary_languages`, repeated query keys; probed 2026-09-26 on a corpus WAV, English transcribed fine under it). `WT_ELEVEN_LANG` set wins for both.
- **`DictationEnd.failed`** ≠ `.silent` (drops audio) ≠ `.cancelled` (keeps it quietly): 12 s banner
  + WAV staged for *Recover Cancelled Dictation*. One retry, only for transport/429/5xx; 45 s ceiling.
- **An empty transcript is `.failed(why: DictationEnd.heardNothing, audio:)`, never `.silent`**
  (2026-09-26, §3.8 — the WAV used to be deleted; 60 s of speech lost 09-19 and 09-20). Scribe `""`
  and a local answer with no words both; `.silent("")` is only a take under 0.35 s. **No local
  fallback for `heardNothing`**: Whisper on 3 s of silence answered `www.clu.com.br` and it was
  delivered (TL16, first try). → journal: *Fixes to the test plan's findings, batch 1*
- **Unmeasured:** `languageFloor = 0.5`, `scribe_v1` vs `v2`. `tools/eleven-test.sh [wav | --corpus n]`.

## Markers: where a picture was taken

- **Timestamp markers (2026-09-19, current, `ShotMarker.place`, `WT_MARKER_TIMESTAMPS=0` off).**
  Scribe's `words[]` carry `start`/`end` on the WAV this app recorded; a press measured on the same
  ruler (`MicRecorder.offset(of:)` — frames written, answered backwards, ≤ 85 ms buffer correction)
  lands between words. Only for a source with `audioOffset(of:)` (ElevenLabs, local); Wispr answers
  nil and frames keep their `mm:ss` rows under the words.
- **Reserved at the gesture, keyed by path** (`shotMarkerNumbers`, before `screencapture` runs); the
  safety net is a **set** of real pictures, not a count. `ShotMarker.render` is the one vocabulary.
  Selection numbers are reserved under `fileSelection`'s lock (`reserveMarkerLocked`) and spoken after.
- **Cues without `words[]` place nothing and never fall back on `resolve`** — every match would be his
  own words rewritten. The corpus copy is his words untouched (`resolvingMarkers(inline: false)`).
- **`evals/test_marker_place.py`** — ten seam cases via `POST /test/shot-marker`; safe mid-workshop.
- **Spoken markers — RETIRED 2026-09-18** (`WT_SHOT_MARKERS=1` revives): a clip played into
  `🎓 TO Wispr` said `screenshot one`; Scribe heard `Pict element one` and the phrase stayed in the
  sentence. Fails per engine/language/accent. Mechanism notes (gap gate `quietSeconds ≥ 0.12 s`,
  1.5 s ceiling; masking is not a level problem) are in the journal.
- **No live captions:** Scribe realtime gives timings only on committed text from a smaller model.

## Every switch the dictation source reads

| variable | effect |
|---|---|
| `WT_SOURCE=whisper｜eleven｜wispr` | engine for one run (the menu writes `dictationSource`) |
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
| `WT_WISPR_COPY_FALLBACK=1` | re-enable `copy_last_text` — see below |

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
