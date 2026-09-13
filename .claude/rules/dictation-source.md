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

## The wrap, end to end (2026-09-14)

**Wrap Wispr Flow** is a menu tick, default **on**, and it chooses between three *relationships
with another app*. `/engine` and `GET /test/state` answer `wrapMode` **and `wrapWhy`**, because a
wrap that quietly fell back to the emergency path is exactly what nobody notices.

| mode | Wispr is told | the words come from | what it costs |
|---|---|---|---|
| **`scratchpad`** (default) | *Open Scratchpad*, **held** for the sentence | the `History` row at `formatted`, `via: "wispr-history"`; the note is a cross-check | nothing — Wispr inserts nowhere |
| `sink` (emergency) | the hands-free chord | the relay's own key window, taken at the **stop**, `via: "wispr-sink"` | his keyboard, for a moment, every dictation |
| `off` (tick down) | the hands-free chord | nobody — Wispr inserts where the focus is | the wrap |

`WT_WRAP_MODE=sink` for one run; `POST /test/wrap-mode {"mode": …}` for the loop (`auto` hands the
decision back). It falls back to `sink` **automatically** when Wispr has no `open_scratchpad`
shortcut, and when the Scratchpad window will not close — both said out loud in `wrapWhy`.

### Scratchpad mode, in order

1. **Start from CLOSED.** A held chord writes a note **only while the Scratchpad window is
   closed** — four runs. With it open Wispr transcribes normally (`History` says `formatted`) and
   writes **no note at all**; the sentence is lost and closing the window afterwards does not
   commit it. Wispr opens that window during the dictation, so the thing that breaks a sentence is
   the **previous** one. `holdScratchpad` checks and closes before it holds.
2. **Hold the chord** — `open_scratchpad`, read from `prefs.user.shortcuts` by **action name** at
   call time, fallback `79` (F18), `WISPR_SCRATCHPAD_KEYS` overrides. A single key on purpose: a
   chord held for a whole sentence must not be one that hijacks every key he presses.
3. **Park it on sight.** A 25 ms watcher from the **chord** (the window appears at the *start* of
   the hold and lives for the whole sentence). Parked to the smallest size Wispr allows, at the
   bottom-right of the second display when one is attached, all but an 8 pt sliver past the edge.
4. **Release at the stop**, and ask the close **exactly once** — see *Never reintroduce*.
5. **Deliver from the row at `formatted`**, with an **addressed ⌘V**.
6. **Cross-check the note** 3.5 s later, and log only a material disagreement.

### The numbers behind it (all measured, 2026-09-13/14)

| | |
|---|---|
| Wispr's own round trip (`e2e`) | 320–420 ms |
| row `formatted`, after the microphone closed | **~400–530 ms** |
| words landed (addressed paste, no longer gated on the close) | **~410–490 ms** |
| the note readable | 2627 ms — **why the note is not the delivery** |
| the Scratchpad visible on the main display | **17–40 ms** (the poll's own latency) |
| the Scratchpad closed, after the close was asked | **417–445 ms** |
| its window level / subrole / minimum size | **layer 3** / `AXStandardWindow` / **300×300** |
| does Wispr remember the parked frame | **no** — it reopens at its own origin, so it is parked on every open |

### The delivery is the row; the note is the second opinion

- **The note is where Wispr *pastes*; the row is where Wispr writes *what it heard*.** Waiting for
  the note made the mode 2.8 s slower for a copy of the same sentence.
  `WT_SCRATCHPAD_DELIVER=note` goes back to waiting, because the day the two disagree somebody
  will want the other one.
- **`formattedText` first in this mode**, where every other path prefers `pastedText`: an append
  into Wispr's own note arrives lowercased and run on (`commit and push the fix.` against
  `Commit and push the fix.`).
- **The cross-check normalises case and punctuation away** and compares only the **new portion** of
  the note — Wispr does not reliably start a new note, it appends with `source = typed` whose
  content is the whole accumulated notepad. Only a disagreement about the *words* is worth a line.
- **The ⌘V is swallowed in every mode.** It was let through in Scratchpad mode for one build, on
  the reasoning that Wispr's paste belongs to Wispr's own note — true while the note was the
  delivery, false once the window is closed at the release: the paste then arrives with nowhere of
  its own to go and lands in **his document**, lowercased, beside the relay's proper copy.

### The addressed paste

- **`DictationResult.focusPid`** carries the pid of the app he was looking at **at the chord** —
  the last unambiguous moment, because the window that takes the keyboard never becomes frontmost.
  `pasteText(_:to:)` → `TerminalBinding.pressPaste(to:)` posts the ⌘V with **`postToPid`**,
  straight into that application's event queue, bypassing the session and therefore whoever holds
  the key focus. Who holds it is a **log line, not a gate**.
- **Nil for every other delivery**, which means *whatever has the caret*: the fabricated
  `/test/dictation`, the five-minute recovery of a cancelled sentence, ⌘⌃P. Bound-terminal and
  spawn deliveries never went through the focus at all.
- **No modifier cleanup on the addressed paste.** The stale-⌘ bug `tap(key:command:)` is written
  around is about `CGEventSource.flagsState`, which is *session* state; events posted to a pid
  never enter it. The `flagsChanged` pair still goes to the same pid, because a Cocoa app builds
  ⌘V out of a modifier it believes is down.

### The keyboard, while Wispr's window is up

- **The Scratchpad becomes KEY without its app becoming frontmost.** Measured: a `z` typed 1.5 s
  after the stop went into the note and was delivered *inside the sentence*, with
  `frontmostApplication` reading TextEdit throughout. **Never test key focus with
  `frontmostApplication`** — use the system-wide focused element's owner
  (`AXUIElementCreateSystemWide` + `kAXFocusedUIElementAttribute` + `AXUIElementGetPid`).
- **Real keys are re-posted to the app he was looking at**, decided **per key**:
  anything carrying **⌘ or ⌃ passes** (⌘Tab and ⌘Space stay the system's), the focus owner is
  checked at the keystroke, and only a key whose owner is Wispr is handed on. Armed at the chord,
  disarmed when the window is confirmed gone, **10 s ceiling from the release**, below the app's
  own chords so ⌘⌃B and ⌘⌃D keep working, logged **by keycode only**.
  `WT_SCRATCHPAD_REDIRECT_KEYS=0` turns it off.
- **`keyRedirect`'s counters are this dictation's, zeroed at the chord** whether or not the guard
  then arms — the loop read `keys = 5` on runs where nothing had been redirected at all, because
  only a successful arm reset them and a run that never armed inherited the previous one's numbers
  wholesale. A failure to arm now says so in the log instead of leaving stale evidence behind.
- **The focus-owner check does not use the system-wide element.** Measured 2026-09-14:
  `AXUIElementCreateSystemWide` + `kAXFocusedUIElementAttribute` returns **`kAXErrorCannotComplete`**
  on this Mac, so a check written on it silently answers *no* for ever. It is still asked first —
  where it works it is the most direct reading there is — and a failure is logged once, after which
  the question goes to **Wispr's own application**: is the Scratchpad the window it considers
  focused, and does that window say it is.
- **`WT_KEY_TRACE=1` / `POST /test/key-trace {"on": true}`** logs every keyboard event the tap sees
  and the verdict it reached — `passed`, or `SWALLOWED by <branch>` — with the **keycode and the
  posting pid only, never a character**. An event that reached the end of `handle` untouched says
  `passed` explicitly, so a missing verdict means a branch that has not been instrumented rather
  than a key that vanished.
- **Its limit, and it is a hard one: it cannot manufacture a key window.** An application that is
  frontmost with **no key window has no first responder**, and a character posted to it is dropped.
  `wrap-caret` lands 7/7 because TextEdit keeps its key window; `wrap-bound` lands 0/7 with the
  same pid, because a bound Terminal holds it instead. ⌘V survives the same trip either way
  (`performKeyEquivalent` needs no first responder), which is why the delivery works and the
  letters do not.
- **The theft cannot be undone.** Re-activating the victim does nothing (`activate` says *be
  frontmost* and it already is); `AXMain` / `AXFocused` on the window he was typing in logs
  `the focus owner is still Wispr`.

### The sink, and everything the wrap is not

- **The sink is the emergency mode and a test instrument, never the default.** It works — 3/3,
  Wispr picks its insertion target at the **end**, so a window taking the keyboard 1–5 ms after the
  stop chord receives the text — and Victor rejected it as the primary path because it takes the
  focus off a man who may be clicking or typing.
- **It may not take the key window during a Scratchpad dictation.** `POST /test/sink {"key": true}`
  is **refused with a 409** while one is in flight: the `bound` scenario did it and the row never
  went terminal for the whole 30 s capture. Wispr appears to choose its target from the key window.
- **A dictation Victor starts himself is Wispr's** — his own keyboard chord, or 🔽→ which posts
  Wispr's chord raw. Ring only: no swallow, no Scratchpad, no pasteboard watch, nothing delivered;
  it ends on Wispr's row with `.silent("")`. `relayStarted` is that distinction and `deliver`
  carries the guard as well as its callers.
- **`startedMode` and `intercepting` are two different questions.** The first says *how the chord
  was posted*, so it says what `stop()` must undo — a dictation opened by holding a key is ended by
  releasing that key. The second says *does the relay deliver these words*. They come apart on
  `POST /test/wispr-handsfree`, which posts Wispr's own chord (nothing held, no sink) while the
  wrap is on and the ⌘V is still the relay's to swallow.

## Three witnesses, and none of them alone (2026-09-13)

`WisprState` is five phases — `idle` · `warming` · `listening` · `transcribing(status)` ·
`done(status)` — joined from four inputs, none authoritative alone. Measured on one real dictation:

| witness | what it proves | when it spoke |
|---|---|---|
| the chord this app posts | a dictation was **asked for** | it is the clock |
| Wispr's `History` row appearing | Wispr **took the chord** | **357 ms** |
| the **100 ms poll** of `kAudioProcessPropertyIsRunningInput` | a microphone **is** open | **607 ms** |
| `WisprWatch`'s CoreAudio notification | the same fact, pushed | **5590 ms** |

- **The notification is 0–6 s late and sometimes silent altogether.** It publishes only when the
  value it re-reads *differs*, so a dictation shorter than its own lag has neither edge — and with
  Wispr pinned to `🎓 TO Wispr`, whose physical source keeps the stream warm, it produced **no edge
  at all** in five successful runs. It is a *second* source and never the only one.
- **Both lags are logged on the `listening` transition**, and they stay two inputs on purpose: the
  gap between pull and push is the measurement the replay buffer will need.
- **A witness that never saw the microphone open cannot report it closing.** A close belonging to
  the previous sentence arrived six seconds later, 600 ms into the next one, and ended it. Both the
  notification and the poll now need `notifyMs` / `pollMs` for *this* dictation.
- **The machine owns nothing** — no timers, no CoreAudio, no SQLite, no AppKit — which is what
  makes `POST /test/wispr-state/simulate` a unit test: a fresh machine with a fake clock, a
  scripted sequence, its transitions back, in under a millisecond. It is a route and not an XCTest
  target because the package is one `executableTarget` with a `main.swift` in it. It earned its
  keep in its first minute by finding `chordAt > 0` standing in for *a chord has been seen*, which
  a clock starting at zero makes two different questions.
- **The relay's own stop closes the listening phase**, not the edge: `stop()`, `cancel()`, ⌃Escape,
  the second hands-free chord and `POST /test/wispr-handsfree` all call `closeListening`, which is
  also the one place the machine is told and the one place a held chord is released.
- **`speculativeGrace` may only retract a ring for a chord that left no row.** Wispr creates the row
  at the gesture, so its absence is the honest test for *Wispr ignored the chord*.

## The ring is *microphone open*; the chip carries the wait (2026-09-13)

- **The ring goes down at the microphone's close**, not at the words' landing —
  `caretHalo.setActive(listening || speculative)`, with `settling` deliberately not in it. A ring
  standing twelve seconds over a sentence already pasted into Word is indistinguishable from one
  still hearing him.
- **The chip shows `Transcribing...` for the whole settle** — the same claim the ring used to make
  by standing, without the lie.
- **`endSettling` logs `✍️ the words landed`, not `⚡ ring down`**, and notes into
  `RingDown.lastSettled`; the ring's own note is written at the close. `/test/state` answers both.
- **The settle's 8 s steps aside for a recogniser that is still answering** (`armSettleGiveUp`
  re-arms while `phase.isWaitingForWords`, bounded by 30 s). Eight seconds is right for *nothing
  came back* and wrong for a row that says `processing`.
- **A 🔼 click while the words are in flight is a stop, or nothing — never a new dictation.**
  `onPasteToggle` asks `listening || isRecording` first, then `settling || phase.isWaitingForWords`
  and does nothing; `startDictation` carries `!settling`; and `retireCaptureIfSettled` replaces the
  unconditional `endCapture` in `gestureSeen` — a capture whose row is not terminal belongs to a
  sentence still in flight.

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

- **The loopback is the whole control surface**, and every route is in CLAUDE.md's *Testing at a
  desk* table. `POST /test/gesture {"name": …}` posts the ⌃⌥⌘F-key chord Options+ makes for a mouse
  gesture, so the tap's gesture branch runs as it does for his hand (the F7 *bind* sub-case needs a
  real held left button and is not fakeable). `GET /test/state` answers everything an assertion
  needs in one read. `DictationResult.via` names the delivery route and lands in `outbox.jsonl`'s
  `delivery` field.
- **`POST /test/gesture` clears its own modifier flags.** It posted `⌃⌥⌘F-key` down and up and
  nothing else, so `CGEventSource` went on reporting three held modifiers until the next real
  keystroke — and every *wait for a bare wire* loop behind it ran to its ceiling, which is how the
  Scratchpad chord went out as `⌃⌥⌘F18` and Wispr ran an ordinary dictation instead. A real
  Options+ gesture posts its own trailing flags-cleared event 12–22 ms later; so does this route
  now. It is the stale-⌘ bug of `area-crop.md` for the third time in this repo.
- **`WisprSink` is a test instrument and nothing else.** `POST /test/sink` opens it — 40×20,
  borderless, in a corner — and `GET /test/sink` says what landed in it and by which route. It is
  **refused with a 409** if asked to take the key window during a Scratchpad dictation.
- **The sink cross-check only ever sees what leaks.** It disagreed with the row 5/5 on 2026-09-13
  because the swallow was armed too late and Wispr's ⌘V escaped into it — 24 characters against the
  row's 23, a match. With the swallow armed at the start chord, a **correct** run leaves the sink
  empty, so an assertion of *sink text equals row text* fails on every good run.
- **`POST /test/wispr-state/simulate` is the state machine's unit test** — a fresh `WisprState`
  with a fake clock, a scripted sequence of inputs, its transitions and both lags back, touching
  nothing in the running relay.
- **`POST /test/wispr-scratchpad {"down"|"up"|"tap"}`** drives Wispr's Scratchpad chord by hand;
  `GET`/`POST /test/wispr-notes` reads its note; `POST /test/scratchpad/park` parks its window;
  `POST /test/wrap-mode` picks the mode. `POST /test/wispr-handsfree` keeps its old behaviour — it
  posts Wispr's own chord, so nothing is held and no sink is taken, while the wrap stays on and the
  ⌘V is still the relay's to swallow.
- **250 ms, not 60.** A 60 ms press/release does not toggle the Scratchpad window; 250 ms does.
  Wispr is telling a tap from a hold by duration.
- **The chord goes out on a serial queue and only onto a bare wire** — `settleForOptionsPlus` then
  a wait for the modifiers, exactly as `postWisprHandsFree`, `postWisprCancel`, `postWisprCopyLast`
  and `postReturn` have since 2026-09-09. The bookkeeping (`scratchpadHeld`, the dead-man's switch)
  stays at the call site because `stop()` reads it milliseconds later; a serial queue rather than
  `.global()`, because a press and a release that can overtake each other are a key stuck down.
  **120 s dead-man's switch** behind all of it, and every exit path releases the chord —
  `closeListening` and the `speculativeGrace` drop separately, because that one does not go through
  it.
- **The two failures all of this exists for** (2026-09-13): a 2.5 s caret dictation into Word
  produced no CoreAudio edge at all, so `beginCapture` never armed and Wispr's ⌘V went straight
  into Word; and a second 🔼 click landed inside the settle, where `onPasteToggle` asked only about
  `listening`, and started a phantom dictation whose `gestureSeen` disarmed the first sentence's
  swallow window. Both are invisible from outside the process, which is what `/test/state` is for.

## Do not — the ones paid for on the night of 2026-09-13/14

- **Do not make focus-stealing the primary wrap.** The sink works (3/3) and is the **emergency**
  mode: a dictation helper whose ordinary behaviour is to interrupt a man who may be clicking or
  typing is one he cannot leave running.
- **Do not revoke Wispr's Accessibility grant** to stop it inserting. It works, and it breaks Wispr
  as a standalone tool, which it has to go on being.
- **Do not try to cancel an insertion Wispr has decided on.** The window between the row saying
  `formatted` and the ⌘V is **57 ms**, and a ⌃Escape posted *after* `formatted` does not stop the
  paste at all. There is no *cancel the insertion* — only *do not ask for one*.
- **Do not minimize or hide the Scratchpad mid-dictation.** `AXMinimized = true` the moment the
  window appears and the dictation **never comes back**: no `formatted`, no delivery, no ring down.
  Wispr needs that window live. The precondition is *closed at the start*, not *absent during*.
- **Do not ask the Scratchpad close twice.** It is a **toggle**: a second tap behind the first
  closes the window and opens it straight back up. `wrap-cancel` left `['Status', 'Scratchpad']`
  behind for exactly that reason. `armCloseOnSight` is idempotent and claims
  `scratchpadWindowHandled`; every other path checks it.
- **Do not arm a capture from the CoreAudio edge.** It is 0–6 s late and sometimes silent, and
  everything armed from `edge(false)` — the swallow, the row poll, the settle — simply never ran.
  Arm at the **start chord**.
- **Do not test key focus with `frontmostApplication`.** The Scratchpad becomes key without its app
  becoming frontmost; use the system-wide focused element's owner.
- **Do not `open -a "Wispr Flow"`.** LaunchServices resolves the name to the nested Accessibility
  helper at `…/Contents/Resources/swift-helper-app-dist/Wispr Flow.app`, which quits itself when it
  has no parent — and `pgrep -x "Wispr Flow"` matches it too, so a preflight can report Wispr
  running when only the helper is. `open "/Applications/Wispr Flow.app"`, and match the anchored
  executable path.

## Do not — the standing ones

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
