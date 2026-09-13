# The dictation source

Rules for `DictationSource`, `WisprFlowSource`, `LocalWhisperSource` and `tools/wispr-test.sh`.
Full history and reasoning: `docs/journal.md` — *Wispr Flow everywhere (2026-09-12)*.

## One interface, and nothing downstream may look behind it

- **`AppDelegate` holds a `DictationSource` and never names an implementation.** The chip, the
  halo, the settle, the corpus and the destination routing read the protocol only. The one place
  either concrete class appears is `wireDictationSource()` and the `/test/wispr*` routes, which are
  named after Wispr on purpose. → journal: *One interface, because a second branch is how the first
  one rots*
- **Every callback lands on the main queue.** The two sources produce their edges on three
  different threads between them (CoreAudio's listener queue, a transcription callback, the event
  tap), and what the callbacks drive is AppKit. One rule at the boundary, not a hop per call site.
- **`phase` is the source's answer to *how far along*, and it is source-agnostic**
  (`DictationPhase`, 2026-09-13): `idle` · `warming` · `listening` · `transcribing(status)` ·
  `done(status)`. `isRecording` only ever answered the middle one, so a cold Electron's warm-up
  and Wispr's formatting pass both reached the relay as the same undivided *not recording* — and
  a settle written against that cannot tell *the words are late* from *the words are lost*. The
  status string is the recogniser's own vocabulary and nothing outside the source may branch on
  it. → journal: *Three witnesses instead of one (2026-09-13, evening)*
- **`isRecording` is the source's; `listening` is the relay's.** The first answers *is a microphone
  open*, the second *does this app have a sentence in flight*. They are not the same instant and
  every gate in `AppDelegate` means the second.

## Three witnesses, and none of them alone (2026-09-13)

- **`WisprWatch`'s CoreAudio notification is not a witness on its own.** Measured: **0–6 s late,
  and in five successful Loopback runs it produced no edge at all** — Wispr is pinned to
  `🎓 TO Wispr`, whose physical source keeps the stream warm, so `IsRunningInput` never changes
  and a notification that only fires on a change never fires. A dictation shorter than its own lag
  has neither an open nor a close edge. It is kept as a *second* source and never the only one.
- **`WisprState` joins four inputs and says what each proved**: the chord (a dictation was asked
  for — it is the clock), a **100 ms poll** of `kAudioProcessPropertyIsRunningInput`
  (`WisprWatch.sampleIsRunningInput`, over cached object ids, running only between the chord and
  the words), the notification, and the `History` row at 150 ms (Wispr *has* the sentence). Every
  `listening` transition logs **both lags** — `poll saw it 412 ms after the chord, notification
  never` — and they stay two inputs on purpose: the gap between pull and push is the measurement
  the replay buffer will need.
- **The machine owns nothing** — no timers, no CoreAudio, no SQLite, no AppKit — which is what
  makes `POST /test/wispr-state/simulate` a unit test: a fresh machine with a fake clock, a
  scripted sequence, its transitions back. It is a route and not an XCTest target because the
  package is one `executableTarget` with a `main.swift` in it.
- **The relay's own stop closes the listening phase**, not the edge: `stop()`, `cancel()`,
  `⌃Escape`, the second hands-free chord and `POST /test/wispr-handsfree` all call
  `closeListening`. The edge confirms and logs `⚡ the mic edge closed N ms after the relay had
  already stopped`.
- **`beginCapture` is armed at the start chord.** The swallow window, the pasteboard watch and the
  row poll cover the whole sentence; only the 30 s deadline starts at the close. A missing edge
  then costs nothing, which is the whole of the Word failure.
- **`speculativeGrace` may only retract a ring for a chord that left no row.** Wispr creates the
  row at the gesture, so its absence is the honest test for *Wispr ignored the chord*; a row that
  exists confirms the dictation exactly as the microphone used to. Two messages, because they call
  for two different fixes: `Wispr never created a row within 12 s of the chord` against
  `Wispr's own row (the relay saw no microphone) confirms the ring`.
- **This app's own `fn ⌃ Space` is stamped out of its own tap.** The chord became a toggle on the
  far side — one seen while a dictation is open is Victor ending it — so without the
  `backButtonStamp` check `postWisprHandsFree` would hand the source its own start back as a stop.

## The ring is *microphone open*; the chip carries the wait (2026-09-13)

- **The ring goes down at the microphone's close, not at the words' landing.** Victor's reading:
  the ⚡ ring is the relay's own knowledge that a microphone is open, and the tooltip is where the
  words go. A ring standing twelve seconds over a sentence already pasted into Word is
  indistinguishable from one still hearing him. `caretHalo.setActive(listening || speculative)` —
  `settling` is deliberately no longer in it.
- **The chip shows `Transcribing...` for the whole settle** (`setTranscribing`, raised in
  `dictationStoppedListening`, lowered in `endSettling`) — the same claim the ring used to make by
  standing, without the lie.
- **`endSettling` logs `✍️ the words landed`, not `⚡ ring down`**, and notes into
  `RingDown.lastSettled`; the ring's own note is written at the close. `/test/state` answers both
  (`lastRingDown`, `lastSettled`), because *why did the ring go* and *why did the wait end* are two
  questions with two different fixes.
- **The settle's 8 s steps aside for a recogniser that is still answering.** `armSettleGiveUp`
  re-arms while `source.phase.isWaitingForWords`, bounded by 30 s. Eight seconds is right for
  *nothing came back* and wrong for a row that says `processing`; Wispr's tail runs to 22.8 s.
- **A 🔼 click while the words are in flight is a stop, or nothing — never a new dictation.**
  `onPasteToggle` asks `listening || isRecording` first, then `settling ||
  phase.isWaitingForWords` and does nothing; `startDictation` carries `!settling` in its guard;
  and `retireCaptureIfSettled` replaces the unconditional `endCapture` in `gestureSeen` — a
  capture whose row is not terminal belongs to a sentence still in flight.

## The gesture opens the dictation, the microphone confirms it

- **`didBegin` fires on the chord, not on the CoreAudio edge.** Measured 2026-09-12: 324, 478, 528,
  634, 674 ms warm — and **5.0 s and 6.0 s** cold. Everything a dictation opens with (the ring, the
  chip, the context shot, the ⌘C probe, the music pause) fires there, or he watches them arrive in
  two instalments. → journal: *The ring shrank away and came back*
- **The microphone edge must never re-open.** It cancels the retraction, logs `⚡ mic edge confirms
  the ring N ms after the gesture`, and returns. A second `didBegin` takes the halo down and puts it
  back, which is the flicker this whole section exists to remove.
- **`speculativeGrace` is 12 s** — the worst measured open × 2, never under three. A retraction is
  for a chord Wispr *ignored*; that is rare enough to be worth the patience, and a beacon that
  flickers is worse than one briefly wrong.
- **Push-to-talk is the one gesture that only raises the beacon.** Two held modifiers (right ⌘ +
  right ⌥) also fire on a ⌘⌥ meant for something else, and a false `didBegin` costs a screenshot
  and a ⌘C probe posted into whatever he is working in.

## Catching Wispr's transcript

- **Its delivery is a synthetic ⌘V — measured, not assumed** (2026-09-12): keycode 9, flags
  `0x20100000`, from pid 4904 `Wispr Flow`, 1.6 s and 5.9 s after the microphone closed on the two
  sentences that proved it. The `probe:` line in `relay.log` is that measurement and it is armed on
  every dictation, so the day it stops being a ⌘V the log says so. → journal: *The probe*
- **The swallow is narrow: V + ⌘, from a process whose name says Wispr, inside the capture
  window.** Victor's own ⌘V carries pid 0 and can never match; this app's own carries
  `backButtonStamp`.
- **Swallow the `keyUp` with the `keyDown`, and leave the ⌘ alone.** Passing a release whose press
  was swallowed hands the app underneath an orphan; the modifier goes out and comes back balanced.
- **`captureTimeout` is 30 s and is not the ring's timeout.** Wispr's round trip: avg 2.6 s, max
  22.8 s. Six seconds lost an 81-second dictation on the evening the wrap shipped. The capture costs
  one flag and can afford to wait; the ring is on screen and stops at `settleTimeout` (8 s, Wispr's
  p99) — and both are only the net, since 2026-09-12 (late): the settle normally ends on Wispr's own
  `History` row.
- **Wispr's `History` row is the completion signal** (`WisprHistory`, read-only, 2026-09-12): one row
  per dictation, created at the gesture with `status = ''`, filled at the end — `formatted` (+
  `pastedText`, the exact text inserted), `dismissed`, `empty`, `no_audio`, `error`; `e2eLatency` p50
  2.2 s / p90 3.5 s / p99 7.1 s / max 13.7 s over 30 days. `beginCapture` takes the newest row **only
  if its `startedAt` is this dictation's** (a chord Wispr ignored leaves the previous finished row on
  top) and polls it every 150 ms. `formatted` gives the ⌘V `pasteGrace` (1 s) — the ordinary paths
  deliver and close the capture underneath — then delivers `pastedText` as `.insertedElsewhere`: at
  the caret that was the destination; at a terminal the words go on to it and the copy at the focus
  is a stray the log names. Why: two dictations on 2026-09-12 were inserted with **no ⌘V and no
  pasteboard change** (an Accessibility insertion), and every other signal is dead — Wispr's unified
  log is silent, its pill's frame and AX tree never change, `config.json` has no insertion-method
  setting. → journal: *Wispr's own row says when it is done (2026-09-12)*
- **Intermediate statuses are progress, not silence** (2026-09-13). The vocabulary lives in one
  place: `WisprState.intermediateStatuses` = `""`, `recording`, `raw_transcript`, `processing`;
  `terminalStatuses` = `formatted`, `extension_paste`, `extension_other`, `dismissed`, `empty`,
  `no_audio`, `error`. An unknown status is treated as terminal — today's behaviour, kept — but
  `Log.error`s, because reading an unknown as progress would turn one new Wispr status into every
  sentence waiting out thirty seconds.
- **Wispr restores the clipboard after its own ⌘V, and that cost three sentences** (2026-09-13).
  With the baseline `changeCount` taken at the microphone's close — after Wispr's write — the only
  move the relay saw was the restore, and `the pasteboard moved but no ⌘V was seen` delivered it:
  163 characters of a Word rental contract filed in `corpus.jsonl` three times beside audio of
  *"Commit and push the fix"*. Arming at the start chord fixes the ordering; `deliver` also
  **refuses a pasteboard identical to the pre-dictation one** (keeping the capture, because the
  row usually answers a beat later) and reads the string at the instant the change is seen rather
  than 250 ms afterwards, because the restore lands inside that gap.
- **`historyIsTheRoute` makes the row the delivery rather than the late fallback** (2026-09-13,
  `WT_WISPR_HISTORY_ROUTE=1` / `POST /test/wispr {"historyRoute": true}`, default off).
  `formatted` then delivers immediately with no `pasteGrace`, the text comes from `pastedText`
  **or `formattedText`** (a Wispr that inserted nothing fills the second), and the delivery is
  always `.route` — nobody but the relay is going to put that sentence anywhere. The ⌘V swallow
  stays armed behind it as the safety net.
- **A new dictation closes a capture still standing** *only if its row is terminal* — see
  `retireCaptureIfSettled` above. Left armed on a terminal row it would take the next sentence's
  ⌘V as this one's answer; disarmed on a live one it throws away the sentence in flight, which is
  the 09-13 phantom-dictation failure.

## Testing

- **The loopback has a closed feedback loop since 2026-09-13**, and the four routes are in CLAUDE.md's
  *Testing at a desk* table. `POST /test/gesture {"name": …}` posts the ⌃⌥⌘F-key chord Options+ makes
  for a mouse gesture, so the tap's gesture branch runs as it does for his hand (the F7 *bind* sub-case
  needs a real held left button and is not fakeable). `GET /test/state` answers `listening`, `settling`,
  `speculative`, `capturing`, `isRecording`, `ringUp`, the chip's rows and the latched destination in one
  read. `POST /test/sink` opens `WisprSink` — 40×20, borderless, in a corner — as the key window, and
  `GET /test/sink` says what landed in it and by which route. `DictationResult.via` names the delivery
  route and lands in `outbox.jsonl`'s `delivery` field.
- **`WisprSink` is NOT the wrap and never will be** (Victor, 2026-09-13 evening). It is measured and
  it works — 3/3, Wispr picks its insertion target at the **end**, and a window taking the keyboard
  1–5 ms after the stop chord receives the text — and he rejected it anyway: stealing focus during
  every dictation is not something to do to a man who may be clicking or typing at that instant.
  Revoking Wispr's Accessibility grant was rejected for its own reason — Wispr has to go on working
  standalone. It stays a **test instrument**, opened by `POST /test/sink` and by nothing else.
- **The sink cross-check only ever sees what leaks.** It disagreed with the row 5/5 on 2026-09-13
  because the swallow was armed too late and Wispr's ⌘V escaped into it — 24 characters against the
  row's 23, a match. With the swallow armed at the start chord, a **correct** run leaves the sink
  empty, so a runner assertion of *sink text equals row text* now fails on every good run and has to
  be inverted.
- **The third candidate is Wispr's own Scratchpad, and it is the one that works** (2026-09-13,
  measured): F18 held 20 s put the text in `Notes` (a new note per dictation, with a
  `NoteVersions` row beside it), left the victim TextEdit document untouched, **never moved the
  focus**, posted **no ⌘V**, wrote and then restored the pasteboard, and came back in **432 ms**.
  The Scratchpad window opened in the background. `WisprNotes` is the read half
  (`GET`/`POST /test/wispr-notes`, `via: "wispr-notes"`), wired to no gesture yet.
- **On a Scratchpad dictation the `History` row is not the witness.** Its `app` column named the
  **front app** (TextEdit) for a sentence that went into Wispr's own note: `app` answers *what was
  in front*, which for every other kind of dictation is accidentally the same thing as *where the
  words went*. The note is the only place the destination is written.
- **A modified note counts as much as a new one.** The run measured a new note per dictation, but
  the Scratchpad is a notepad and nothing promises it will not append — so `WisprNotes.newest` tests
  `max(createdAt, modifiedAt) >= since` and delivers the newest `NoteVersions` **content** rather
  than the accumulated note.
- **One read-only handle for both readers** (`WisprFlowDB`): `mode=ro` in the URI on top of the
  flag, 50 ms busy timeout, dropped on any error. Two connections opened independently against a
  3.5 GB WAL file another process is writing is not a thing to do twice.
- **Historical — the Scratchpad as an untested hypothesis** (2026-09-13, midday): per Wispr's docs its
  *Open Scratchpad* shortcut taps to open/close, **holds to dictate into the Scratchpad**, and
  double-taps for hands-free into it. `POST /test/wispr-scratchpad {"down"|"up"|"tap": true}` posts
  it, reading the chord from `prefs.user.shortcuts` by **action name** at call time (fallback
  **`79` = F18**; `WISPR_SCRATCHPAD_KEYS` overrides, and is the variable `helpers/wispr_loopback.py`
  reads — the rig posts the same chord and the two must not disagree). A **single** key, because
  this one is held for the length of a sentence and a held ⌘⌥ hijacks every key he presses. The hold is the only poster in this app that leaves the
  keyboard down between two calls, so it carries a **120 s dead-man's switch**, every release is
  idempotent, the chord that is down is remembered against a rebind mid-sentence, and the modifiers
  go out with their **device-dependent bits** — Wispr's own push-to-talk reader distinguishes the
  right ⌘ from the left.
- **Historical — the sink as the wrap.** Victor's design (2026-09-13, midday), superseded that
  evening: only Wispr's transcription engine, Walkie feeding it its inputs and taking its outputs
  synthetically, Wispr never inserting into the real app — **only for dictations this app started**
  (`backButtonStamp`) and **only while *Wrap Wispr Flow* is on**. `becomeKey()` / `restoreFocus()` are
  separate calls (`POST /test/sink {"key"|"restore": true}`) because it is not yet known whether Wispr
  picks its target app at the chord or at insertion time, and the two answers give opposite
  instructions. Do not wire it in before the loop has measured that.
- **The two failures these exist for** (2026-09-13): a 2.5 s caret dictation into Word produced no
  CoreAudio edge at all — `WisprWatch` is 0–6 s late and only publishes an edge when the value it
  re-reads has changed — so `beginCapture` never armed and Wispr's ⌘V went straight into Word; and a
  second 🔼 click landed inside the settle, where `onPasteToggle` asks only about `listening`, and
  started a phantom dictation whose `gestureSeen` disarmed the first sentence's swallow window. Both are
  invisible from outside the process, which is what `/test/state` is for.

## Do not

- **Do not read Wispr Flow's database as a recogniser or a transcript fallback.** The 2026-08-29
  rule stands for what it was about: the words come from the pasteboard the ⌘V announces. What
  `WisprHistory` reads (2026-09-12, Victor: *"ok. build"*) is the **row's status** — is Wispr done —
  and `pastedText` only for a sentence Wispr has already inserted by a route no tap sees, where the
  alternative is waiting a timeout for a key that is never coming. Read-only, `mode=ro`, one query;
  nothing here transcribes, and nothing here may ever start a dictation or replace the pasteboard
  path while the ⌘V is still possible (`pasteGrace`).
- **Do not turn `copy_last_text` (⌘⌃C) back on by default.** It hands back *the last text Wispr
  produced* — after a failed sentence, the previous one — and delivering a five-minute-old
  paragraph as though he had just said it is worse than losing the sentence. Measured once: the
  chord went out and `changeCount` never moved. `WT_WISPR_COPY_FALLBACK=1`.
- **Do not delete `LocalWhisperSource`.** It is the fallback for the day a Wispr update changes how
  it delivers, the only recogniser that works with no network, and the baseline `evals/` scores the
  corpus against.
- **Do not let the corpus stop growing.** The halo's meter writes its WAV so a Wispr dictation has
  audio to file; `engine` distinguishes `wispr-flow` (through Wispr's formatting pass) from
  `whisper-local` (raw).
