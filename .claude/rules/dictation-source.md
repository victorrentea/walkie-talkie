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

## The wrap is Wispr's Scratchpad, and the sink is the emergency path (2026-09-13)

- **Three modes, one tick, and `/engine` + `/test/state` say which and why** (`wrapMode`,
  `wrapWhy`): `scratchpad` (default — hold Wispr's `open_scratchpad` chord for the sentence, read
  the note, `via: "wispr-notes"`), `sink` (the hands-free chord, the swallow, and the sink taking
  the key at the **relay's own stop**, `via: "wispr-sink"`), `off` (the tick down — Wispr inserts
  where the focus is, ring only). `WT_WRAP_MODE` / `POST /test/wrap-mode`, `auto` to hand it back.
- **The Scratchpad wrap has exactly one precondition: the Scratchpad window must be CLOSED.**
  Measured over four runs. Closed: a held chord writes a note, 3/3 — new `Notes` + `NoteVersions`
  row, victim document untouched, focus unchanged, window opens in the background afterwards.
  Open: Wispr transcribes normally (`History` = `formatted`) and writes **no note at all**; the
  sentence is lost and closing the window afterwards does not commit it.
- **So the close is part of the wrap, not tidying after it.** Wispr opens that window at the end
  of *every* dictation, which means the thing that swallows a sentence is the **previous** one —
  the failure shows up one sentence after its cause, which is why it is checked twice: before the
  hold (`holdScratchpad`) and after the capture (`closeScratchpadAfterwards`, from `endCapture`,
  so it runs on every way out). Both verify by polling the window list; the second is mandatory
  and logs loudly when it fails.
- **A window that will not close stands the mode down to `sink`, out loud** (`scratchpadBroken`).
  It is cleared by a later `start()` that finds the window closed, or by
  `POST /test/wrap-mode {"mode": "auto"}`. Holding a chord that writes nothing is the one failure
  this mode must never have quietly.
- **250 ms, not 60.** A 60 ms press/release does not toggle the Scratchpad window; 250 ms does,
  inside 1.5 s. Wispr is telling a tap from a hold by duration.
- **The chord goes out on a serial queue and only onto a bare wire.** `postScratchpad` posted
  immediately at first, and the first real dictation went out as `⌃⌥⌘F18` a millisecond after
  `/test/gesture`'s `⌃⌥⌘F7` — Wispr does not have that bound, so it ran an ordinary dictation and
  pasted. It now waits `settleForOptionsPlus` and then for the modifiers, exactly as
  `postWisprHandsFree`, `postWisprCancel`, `postWisprCopyLast` and `postReturn` all have since
  2026-09-09; the **bookkeeping** (`scratchpadHeld`, the dead-man's switch) stays at the call site
  because `stop()` reads it milliseconds later. A serial queue rather than `.global()`, because a
  press and a release that can overtake each other are a key stuck down.
- **`POST /test/gesture` now clears its own flags.** It posted `⌃⌥⌘F-key` down and up and nothing
  else, so `CGEventSource` went on reporting three held modifiers until the next real keystroke —
  the stale-⌘ bug of `area-crop.md` for a third time, and the reason every *wait for a bare wire*
  loop behind it ran out. A real Options+ gesture posts its own trailing flags-cleared event
  12–22 ms later; this route now posts one too.
- **`startedMode` and `intercepting` are two different questions.** The first says *how the chord
  was posted*, so it says what `stop()` must undo — a dictation opened by holding a key is ended
  by releasing that key, whatever the menu says by then. The second says *does the relay deliver
  these words*. They come apart on `POST /test/wispr-handsfree`, which posts Wispr's own chord
  (`startedMode == .off`: nothing held, no sink) while the wrap is on and the ⌘V is still the
  relay's to swallow. Folding them into one flag broke that route the first time it was tried.
- **A dictation Victor starts himself is Wispr's** (`relayStarted == false`): his own keyboard
  chord, or 🔽→ which posts Wispr's chord raw. Ring only — no swallow, no Scratchpad, no
  pasteboard watch, nothing delivered. It ends on Wispr's row with `.silent("")`, which is
  *nothing worth a banner*. `deliver` carries the same guard, because the cost of one call site
  ever missing it is a sentence he spoke into another app arriving in an agent's terminal.
- **Every path out releases the chord.** `closeListening` releases as a belt, and so does the
  `speculativeGrace` drop — the one exit that does not go through it. Behind both,
  `HotkeyTap`'s 120 s dead-man's switch.
- **The `History` row's `app` column is the front app, never the destination.** It said TextEdit
  for a sentence that went into Wispr's own note. In Scratchpad mode the row is the *clock* —
  `formatted` says Wispr is done, `dismissed` / `empty` / `no_audio` end the capture — and the
  **note** is the delivery; delivering from the row would race the note it is announcing.

## The two alternatives that work and were rejected (2026-09-13)

- **The sink as the primary wrap.** Measured 3/3: Wispr picks its insertion target at the *end*,
  so a window taking the keyboard 1–5 ms after the stop chord receives the text. Victor rejected
  it because it takes the focus off a man who may be clicking or typing at that instant. It stays
  as the emergency path and as the test instrument, and **must not become the default again**.
- **Revoking Wispr's Accessibility grant.** With no grant it can neither write through AX nor post
  a synthetic ⌘V, so the row is the only delivery left. Rejected: Wispr has to go on being usable
  on its own, and an app this one has quietly disarmed is not.
- **Dismissing before the paste.** Not an alternative at all, and the number says why: the window
  between the row saying `formatted` and the ⌘V is **57 ms**, and a ⌃Escape posted *after*
  `formatted` does not stop the paste. There is no *cancel the insertion* — only *do not ask for
  one*, which is exactly what the Scratchpad is.

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
- **The third candidate is Wispr's own Scratchpad, and it is the one that shipped** (2026-09-13):
  the chord held for the sentence puts the text in `Notes`, and `WisprNotes` reads it back
  (`via: "wispr-notes"`). Verified end to end on the installed build at 23:31 — see the four
  corrections below, every one of them paid for by a run that looked like it worked.
- **Wispr DOES post a ⌘V in Scratchpad mode, and it is aimed at its own window.** The earlier
  reading of *no ⌘V at all* was taken with no tap armed. The swallow must be **off** in this mode
  (`armInjectionCapture(swallow: startedMode != .scratchpad)`, probe still armed): taking that key
  is this app reaching into another app's conversation with itself, and it showed — one run's
  sentence was appended to the previous run's note as ` commit and push the fix `, doubled.
- **The caret paste is ADDRESSED, so the delivery no longer waits for the window** (2026-09-14).
  `DictationResult.focusPid` carries the pid of the app he was looking at *at the chord* — the last
  unambiguous moment, since the thief never becomes frontmost — and `pasteText(_:to:)` →
  `TerminalBinding.pressPaste(to:)` posts the ⌘V with **`postToPid`**, straight into that
  application's event queue, bypassing the session and therefore whoever holds the key focus. Who
  holds it is a **log line now, not a gate**. It was both, and it cost 488 ms on a good close and
  3337 ms on one that needed a retry, for a round trip the row had finished at 400 ms.
- **`focusPid` is nil for every other delivery, and that is the point.** The fabricated
  `/test/dictation`, the recovered cancelled sentence (minutes later, where *now* is the right
  target) and ⌘⌃P all mean *whatever has the caret*. Bound-terminal and spawn deliveries never
  went through the focus at all. One field, one caller, no second branch.
- **No modifier cleanup on the addressed paste.** The stale-⌘ bug `tap(key:command:)` is written
  around is about `CGEventSource.flagsState`, which is *session* state; events posted to a pid
  never enter it. The `flagsChanged` pair still goes to the same pid, because a Cocoa app builds
  ⌘V out of a modifier it believes is down.
- **The delivery is the ROW, not the note** (2026-09-13, after the first working run). Measured:
  the row said `formatted` **531 ms** after the microphone closed; the note was not readable until
  **2627 ms**, because Wispr writes it when it opens its window; closing that window cost another
  **663 ms**. Waiting for the note made the mode 2.8 s slower than the ⌘V it replaces, for a copy
  of the same sentence. The note is where Wispr *pastes*; the row is where it writes what it
  heard. `WT_SCRATCHPAD_DELIVER=note` goes back to the note.
- **The note is the cross-check, and case and punctuation are normalised away before comparing.**
  Wispr's paste arrives lowercased and without the final stop (` commit and push the fix ` against
  `Commit and push the fix.`), so only a **material** disagreement is worth a line — a
  disagreement about the *words* is the wrap delivering something other than what Wispr heard,
  which is the failure this mode exists to avoid.
- **The Scratchpad window takes the keyboard when it opens, so the caret paste must not race it.**
  Measured: the relay's own 70 characters were appended to the Scratchpad and the TextEdit
  document Victor was looking at stayed empty. At `formatted` the window is normally not open yet,
  so the ordinary path pastes straight away; if it *is* open it is closed first and the words
  follow. Everything else about the window — the close, the verify, the cross-check — happens
  **after** the delivery, on its own time.
- **The window is parked** (`WisprScratchpad.park`): smallest size Wispr allows (measured by
  asking for 1×1 through AX and reading back what it settled on), bottom-right of the **second**
  display when one is attached, all but an 8 pt sliver past the edge. AX coordinates run from the
  top left of the main screen with y **down**, where AppKit runs from the bottom left with y up;
  getting that backwards puts the window off the top of the world rather than off the bottom.
  Parked on the first open and on any open that comes back elsewhere; the log says whether Wispr
  remembered. `POST /test/scratchpad/park` does it on demand.
- **THE SCRATCHPAD BECOMES KEY WITHOUT ITS APP BECOMING FRONTMOST**, and that is the finding
  everything below is written against (loop, 2026-09-13, `wrap-bound`). A `z` typed 1.5 s after
  the stop gesture went into Wispr's note, was picked up as part of the newly added portion, and
  was delivered to the bound agent **inside the sentence** — while
  `NSWorkspace.frontmostApplication` read `TextEdit` for the whole run and the victim document
  stayed empty. So: **do not test for key focus with `frontmostApplication`.** The test is the
  **system-wide focused element's owner** (`AXUIElementCreateSystemWide` +
  `kAXFocusedUIElementAttribute` + `AXUIElementGetPid`), with the window's own `AXFocused` as the
  second reading.
- **The window opens at the START of the hold and lives for the whole sentence** — not at the end,
  which is what the first build assumed. So the 25 ms watcher is armed at the **chord**, the window
  is **parked on first sight** (measured: on screen for **19–33 ms**, which is the poll's own
  latency), and the close is asked at the release. `lastOpenMs` is the whole life, `closeMs` the
  part after the close was asked — **440 ms** when the first tap takes, up to ~3.3 s when it needs
  a second.
- **One tap is not reliably enough, so it is asked up to three times.** Measured both ways inside a
  minute: a tap toggled a *parked* window closed, and another tap a minute later did nothing. The
  cost of a failure is not this dictation but the **next** one, which is transcribed and written
  nowhere — so `closeWindow` retries, and every attempt logs **which one worked and whether the
  window was parked at the time**. Nothing is un-parked to find out whether that helps: un-parking
  would put the window back over his work, which is the thing being avoided, so the log accumulates
  the evidence and the decision comes after enough of it.
- **Measured, once, and worth keeping:** the Scratchpad is `AXStandardWindow` at **window layer 3**
  — it genuinely floats over everything, which is Victor's objection in a number — and its minimum
  size is **300×300**. Parked at the bottom-right of the only display it ends up at `1720,1089` on
  a `1728×1079` screen, clamped from the `1720,1109` asked for. **Wispr does not remember the
  frame**: it reopens at `1428,817` every time, so parking is done on every open, not once.
- **One owner per close.** The close is a *toggle*, so a second tap behind the first closes the
  window and opens it straight back up — `wrap-cancel` left `['Status', 'Scratchpad']` behind for
  exactly that reason (2026-09-14): `closeListening` armed the close and `endCapture` asked again
  three seconds later. `armCloseOnSight` is idempotent and claims `scratchpadWindowHandled`, and
  every other path checks it.
- **The sink may not take the key window during a Scratchpad dictation.** `POST /test/sink
  {"key": true}` is **refused with a 409** while one is in flight. The `bound` scenario did it and
  the dictation never came back — the row stayed non-terminal through the whole 30 s capture and
  the relay reported *No words came back*. Wispr appears to choose its target from the key window,
  so a test instrument holding it while the chord is down is a test measuring itself, and the
  failure it produces looks exactly like Wispr being broken.
- **The victim pid is remembered in EVERY mode**, at the gesture, and never the relay's own: a
  spawn dictation puts the relay's folder menu in front at exactly that moment, so the pid is taken
  from the frontmost application only when it is somebody else's, with the last non-relay frontmost
  app (kept by `NSWorkspace` subscription) as the fallback. It used to be filled inside
  `guardTheKeyboard` behind a guard that returned early on the relay, which is why `wrap-spawn`
  armed no protection at all. The destination of the sentence has nothing to do with whose
  keyboard it is.
- **Never minimize or hide Wispr while a Scratchpad dictation is running.** Measured 2026-09-14:
  `AXMinimized = true` on the window the moment it appears and the dictation **never comes back** —
  no `formatted`, no delivery, no ring down. Wispr needs that window live, the same way it needs
  the sink not to hold the key window. The precondition is *closed at the start*, not *absent
  during*.
- **The focus cannot be taken back from it either.** Re-activating the victim application does
  nothing (`activate` says *be frontmost*, and it already is); setting `AXMain` / `AXFocused` on
  the window he was typing in logs `the focus owner is still Wispr`. So the redirect is the only
  lever there is, and it works exactly where the app it is aimed at **has a key window** to receive
  the keys — `wrap-caret` 7/7, `wrap-bound` 0/7 with the same pid, the difference being a bound
  Terminal holding the key window in the second.
- **`windowIsOpen()` asks Accessibility, not the window server.** *Exists* and *is on screen* are
  two questions; the close, the retry and the precondition all want the first. `windowIsOnScreen()`
  is the second and is what `visibleMs` is measured from.
- **And for exactly that stretch, his keys are re-posted to the app he was looking at.**
  `HotkeyTap.armKeyRedirect(to:)` takes every **real** key (pid 0, unstamped) and hands it on with
  `postToPid` to the application that was frontmost at the **stop gesture** — the last moment that
  is unambiguous, since the thief never becomes frontmost. Wispr's own synthetic keys carry its
  pid and this app's carry `backButtonStamp`; neither is touched. Armed when the window is *seen*
  and disarmed when it is confirmed gone, with a **10 s ceiling** whatever anyone forgets, and
  below the app's own chords in the tap so ⌘⌃B and ⌘⌃D keep working. Logged **by keycode only** —
  a log that records what he typed is a log that must not exist.
  `WT_SCRATCHPAD_REDIRECT_KEYS=0` turns it off.
- **The note is never the delivered text once the row has delivered.** It is read
  `crossCheckDelay` (3.5 s) later and compared, nothing more — which is also what stops a stray
  keystroke in the note from being folded into the sentence, the other half of the same finding.
- **Wispr does not reliably start a new note** — it appended to a note from four minutes earlier
  with `source = typed`, and a `typed` version carries the **accumulated notepad**, not the
  increment. So the delivery is the new portion only: the note's content with the text captured at
  the gesture (`priorNoteText`) stripped off the front by longest common prefix. 70 characters for
  a four-word sentence is what the other reading costs, growing every time.
- **The close must wait for the window to appear** (`closeWhenItAppears`). A close fired at the
  delivery finds nothing open, reports success, and the window appears a second later and is still
  there at the start of the next dictation — which is the state that costs a sentence.
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
