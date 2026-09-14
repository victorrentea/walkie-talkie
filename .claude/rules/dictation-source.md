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
- **Which source is live is a menu row since 2026-09-14** — `Engine`, replacing `Replace
  WisprFlow`. `AppDelegate.setEngine` nils the old source's five callbacks, assigns `source`, writes
  `dictationSource` and re-runs `wireDictationSource()`; that is the whole switch, because nothing
  downstream knows there is more than one answer. It **refuses while a sentence is in flight** and
  tells the menu what is actually running either way. `WT_SOURCE=whisper` still wins for one run.
  → `.claude/rules/menu-bar.md`, *The Engine row*
- **`isRecording` is the source's; `listening` is the relay's.** The first answers *is a microphone
  open*, the second *does this app have a sentence in flight*. They are not the same instant and
  every gate in `AppDelegate` means the second.

## The wrap, end to end (2026-09-14)

**The wrap** (`wrapWispr`) is **on** and is no longer a menu row — *Wrap Wispr Flow* went on
2026-09-14 as redundant beside `Engine`, and its stored preference went with it; `off` is the
harness's control, through `WT_WRAP_WISPR=0` or `POST /test/wrap-mode`. It chooses between three
*relationships with another app*. `/engine` and `GET /test/state` answer `wrapMode` **and `wrapWhy`**, because a
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
- **The ⌘C selection probe must leave the modifier state clean, and until
  2026-09-14 it did not.** `KeySimulator.simulateKeyPress` stamped `.maskCommand` on the C
  `keyDown` **and `keyUp`** and posted nothing after — and `CGEventSource.flagsState` reports
  whatever the last event's flags said, so the session believed **⌘ was held** until Victor's next
  real key. It is the stale-⌘ bug of `area-crop.md` a fourth time, and it matters more here than it
  did in `TerminalBinding.tap`: the window server **merges live modifier state back into a posted
  key**, so a letter arriving afterwards is delivered as **⌘ + that letter**. The probe runs
  **only for a bound or spawned dictation** (`captureContext` → `stashSelection` →
  `SelectionCapture.read`, and only when Accessibility returned nothing) and **never for a caret
  one**, which is exactly the axis along which the loop's probe letters survive or vanish — and
  `q z j k w y v` against TextEdit are *quit*, *close the document*, *undo* and four edits.
  The trailing `flagsChanged` is now posted; the leading one deliberately is not, because asserting
  ⌘-down is the window being closed.
- **The probe is stamped.** `keyboardEventSource: nil` gave it pid 0 and no `userData`, so this
  app's own ⌘C reached its own tap looking exactly like a key Victor had pressed.
- **`WT_KEY_TRACE=1` / `POST /test/key-trace {"on": true}`** logs every keyboard event the tap sees
  and the verdict it reached — `passed`, or `SWALLOWED by <branch>` — with the **keycode and the
  posting pid only, never a character**. An event that reached the end of `handle` untouched says
  `passed` explicitly, so a missing verdict means a branch that has not been instrumented rather
  than a key that vanished.
- **A printable character goes in through Accessibility, not as a key** (2026-09-14). An
  application that is frontmost with **no key window has no first responder**, so a character
  delivered to it by any key route is dropped — measured twice, once with a dead target and once
  with a live one, and the letters vanished both times. ⌘V survives the same trip only because
  `performKeyEquivalent` needs no first responder. So the guard sets **`AXSelectedText`** on the
  victim's focused element, which needs no key window at all: at a caret the selection is empty, so
  setting it *is* typing. **Return, Tab, the arrows and Delete** have no text to insert and go by
  `postToPid`, logged as best effort.
- **The focused element is read fresh at the keystroke**, not remembered from the chord: he may
  have clicked into another field since, and inserting into the field he has left is worse than
  dropping the key.
- **The target pid is resolved at the keystroke too.** The remembered one can be **dead** — the
  loop force-quits its victim between scenarios, and the guard spent a whole run posting into a
  corpse — so `kill(pid, 0)` checks it and a dead target falls back to whoever is frontmost now,
  said out loud once. The tap never asks AppKit on its own thread; `HotkeyTap.noteFrontmost` is
  pushed in by the workspace observer.
- **The swallow gate is strict: `WisprScratchpad.scratchpadHasFocus()`, and nothing else.** Only
  while the window itself reports `AXFocused == true`. Anything short of a yes passes the key
  through, because the loop sampled TextEdit's `AXTextArea` as focused at every probe of a run in
  which the guard swallowed all seven letters — and a swallow while the victim holds the focus is
  pure loss.
- **`keyRedirect` counts four things**: `seen`, `redirectedAX`, `redirectedKey`, `passed`, and the
  last three add up to the first.

### The keyboard guard is ON, and it works (2026-09-14)

**`WT_SCRATCHPAD_REDIRECT_KEYS` and `WT_SCRATCHPAD_AX_INSERT` both default on.**
While Wispr's Scratchpad window is up, a real keystroke is taken by the tap and
inserted into the app he was looking at through `AXSelectedText`, on a serial
queue off the tap thread.

Measured by the suite run **alone under its own lock**:

| | result |
|---|---|
| `wrap-caret` / `wrap-bound` / `wrap-spawn` | **7/7 letters into the victim, every offset** |
| letters typed while the clip played | landed |
| letters in Wispr's note | none |
| letters inside the delivered sentence | none |
| `redirectedAX` | 5 |
| delivery | 12–18 ms |

**Every earlier reading that said otherwise was contaminated.** Two harness
instances were typing probe letters into the same victim document at once — the
runner proved it by finding its own three-letter sweep arriving from another
process's pid — and that is also what produced the doubled letters and the
two-pid traces that took a night to explain. The loop takes a lock file now
(`~/.walkie-talkie/wispr-loop.lock`, a second instance exits 2), and no
measurement of this is worth anything without it.

- **The insertion is on `HotkeyTap.axQueue`**, serial and `.userInteractive`,
  **200 ms per character** through `AXUIElementSetMessagingTimeout`, a character
  that misses the deadline **said to be lost** rather than queued behind the
  next. The tap only decides, translates the keycode through the cached layout,
  swallows and hands it on — an AX round trip inside the tap's callback stalls
  every keystroke on the Mac.
- **Non-printables** — Return, Tab, the arrows, Delete — go by `postToPid` on the
  same queue, keeping their place, and are logged as best effort.
- **⌘ and ⌃ always pass**, so ⌘Tab and ⌘Space stay the system's.
- **The gate is the Scratchpad window's existence**, cached by the 25 ms watcher;
  no focus reading is true (see below).
- **The note is never the delivered text in Scratchpad mode** (`noteMayDeliver`,
  off). Two runs once delivered `added 'qz'` — a pair of probe *keystrokes* — as
  though they were the sentence. On a timeout with no row the answer is
  **"No words came back"**, never the note.
- **The swallow does not leak.** Where a letter appeared twice, it had been
  *posted* twice from two different pids, each copy with its own `SWALLOWED`
  line; `noteDuplicate` says so in the log now.
- **Wispr's own ⌘V leaves ⌘ down in the session, and only this app puts it back**
  (the sixth stale ⌘, 2026-09-14). Its paste is `keycode 9, flags 0x20100000` —
  ⌘ stamped on the key *and on its release* — and it posts no `flagsChanged`
  after it, so `flagsState` reports ⌘ held until Victor's next real keystroke:
  every gesture gated on `bare` refuses and every *wait for a bare wire* loop
  spins its full allowance. It shows only with the **wrap off**, which is the
  tell that found it — wrapped, the swallow eats both halves and the session
  never sees the release. The tap posts the clearing `flagsChanged` on ⌘'s own
  keycode for any Wispr ⌘V key-up it is **letting through**, stamped, off the tap
  thread, and says so in the log.
- **The seventh stale ⌘ is the sixth one with no tap running, and it is healed at
  launch** (2026-09-14). `wispr-alone` — relay stopped, Wispr pastes for itself,
  relay relaunched — came back with `/test/state.sessionFlags == ["command"]`:
  Wispr's ⌘V key-up carries ⌘ and posts no `flagsChanged` behind it, and with no
  tap alive there is nobody to put it back, so the session was already holding a
  modifier before the relay's first line of log. It is the first occurrence this
  app did not cause and the only one it can fix from outside a keystroke. So
  `HotkeyTap.clearStaleModifiersAtLaunch()` runs from
  `applicationDidFinishLaunching` **after `SingleInstance.enforce`** (the instance
  just stood down is the likeliest poster of the last event): for each of ⌘ ⌥ ⌃ ⇧
  fn it compares `CGEventSource.flagsState(.combinedSessionState)` against
  `keyState` on **both** of that modifier's keycodes, and a flag no key is holding
  down gets a stamped `flagsChanged` **on the modifier's own keycode**, carrying
  the state the keyboard is left in rather than `[]` — a modifier he really is
  holding survives the clearing of one he is not. `⌨️ a stale <modifier> from
  before the relay started was put back down`, and silence when there is nothing
  to say.
- **A cancel during the settle must NOT disarm the swallow** (adversarial run,
  2026-09-14 03:04). `forward-left` posted 200 ms after the stop tore the capture
  down while Wispr's ⌘V was still 300 ms away, and the trace shows what that
  costs: `↓ key 9 pid 81316 flags 0x20100000 — passed`. Wispr's text went into
  TextEdit — the one promise the whole wrap exists to keep — and its ⌘-stamped
  key-up left `sessionFlags ['command']` behind. **Never disarm while Wispr may
  still paste.** The cancel now sets `discardOnArrival`: Victor is told it is
  cancelled at once, Wispr is told to dismiss, everything stays armed, and
  whatever still arrives — a ⌘V, a row going terminal, a note, or nothing by
  `captureTimeout` — is swallowed and **dropped**. The Scratchpad closes with the
  capture, which is to say after Wispr has finished with it. `capturing` stays
  true for that stretch, which is honest: the swallow really is armed.
- **…but a cancelled capture may not outlive the gesture that supersedes it**
  (the regression that fix left behind, measured on `3b4be96` by
  `wrap-cancel-in-settle --settle-delay-ms=100,200,500,1000`). `capturing` stayed
  true for up to the full **30 s** of `captureTimeout` and the **next** relay
  dictation never opened — `never listening (8.1 s)` — because two different
  things refused it. `retireCaptureIfSettled` saw a row that was not terminal and
  kept the capture, so `beginCapture` returned early and the new sentence had no
  swallow, no row poll and no delivery; and the **phase** stayed `transcribing`,
  which is what the machine's `Settling` state and `startDictation` read as
  *words in flight*, so the click was answered with *nothing to start, nothing to
  stop*. Both are fixed
  in `WisprFlowSource`. `cancel()` calls `state.reset`: the swallow is armed but
  nothing is **awaited**, which are two claims and only the first was ever true
  after a cancel — and `pollHistory` no longer feeds `state.sawRow` while
  `discardOnArrival`, or the next tick would put the phase straight back.
  `retireCaptureIfSettled` sends a discarded capture to `retireDiscardedCapture`,
  which lets `endCapture` release everything it holds — the Scratchpad, the
  keyboard guard, the sink, the deadline — and opens the new dictation's own
  capture in the same call. What survives is only the swallow, **keyed by
  `retiredDiscardRow`**: `WisprHistory.entry(rowid:)` watches that row (`newest()`
  cannot answer about it any more — by then the new dictation is on top) and the
  claim is let go when the row is terminal plus `pasteGrace`, when its ⌘V arrives
  and is dropped, or at a **5 s** ceiling. `injected(from:)` checks the retired
  row **before** `capturing`, because the capture running by then belongs to the
  next sentence and that key is not its delivery.
- **After a cancel the Scratchpad closes when Wispr is finished with it, not when
  the capture is** (measured **3.2 s** on `3b4be96`; target < 1.5 s). The close
  asked at `closeListening` works — what nobody was watching for is that Wispr
  **reopens** the window ~2 s later when it writes its note, and a cancelled
  sentence does not reach `endCapture` until Wispr has finished transcribing words
  nobody wants, so the second window stood over his work taking his keystrokes for
  the whole difference. `armDiscardClose` polls at `historyTick` from the dismiss
  and re-arms the close as soon as either the row for **that** dictation is
  terminal (`dismissed` / `empty` / …, read by rowid) or `pasteGrace` has passed
  since the ⌃Escape went out, whichever comes first. The **ask-exactly-once** rule
  is unchanged and now has a reader: `WisprScratchpad.closeIsInFlight` exposes
  `closeASAP`, `armCloseOnSight` guards on it as it always did, and `endCapture`
  consults it before starting a second close of its own.
- **A chord that goes out after its dictation is over opens a window nobody owns**
  (adversarial round 2, Finding 1). `postScratchpad` moves the bookkeeping now and
  hands the keys to `scratchpadQueue`, which waits `settleForOptionsPlus` and then
  for a bare wire — so on an 18 ms dictation the hold `holdScratchpad` asked for
  landed **after** the cancel had ended everything. Wispr read the down/up pair as
  a *tap*, opened its Scratchpad, and the window stood for **57 s** with the
  keyboard guard already disarmed (`scratchpadWindowOpen:true`,
  `keyRedirect.armed:false`, AX `['Status', 'Scratchpad']`, reproduced at 100, 200
  and 500 ms). A queued **hold** is therefore stamped with
  `HotkeyTap.dictationEpoch` and dropped at post time when that epoch has moved
  on — the epoch is retired in `gestureSeen` and in `closeListening`, *after* the
  release, because the release is the one chord that must still go out. A
  **release** is never dropped for a stale epoch (a key stuck down is the worse
  failure by a wide margin) but is dropped when the hold it releases never went
  out, so the pair leaves the wire untouched. `tapWisprScratchpad` carries no
  epoch: it belongs to the window, not to a sentence.
- **…and the close that was *itself* opening the window** (the same finding, one
  build later: the epoch fix was necessary and not sufficient). Every cancel row
  still left an orphan at +3 s and +15 s, and the log said why —
  `the Scratchpad window appeared — closing it on sight`, then `chord DOWN/UP`,
  and no `orphan Scratchpad closed` anywhere. **After a dismissed dictation Wispr
  closes its own Scratchpad**, and the close asked while the window was up is
  *emitted* a moment later, after the wire has gone bare, into a world with
  nothing to close — so the toggle **opened** one. The 25 ms watcher had already
  finished (it saw the window go), and the sweep was looking for a window that
  did not exist yet.
  **`WisprScratchpad.ensureClosed(reason:)` is now the only way this app closes
  that window** — close-on-sight, after a delivery, after a cancel, the hold's
  precondition, the sweep and the menu row all go through it, and `closeWindow`
  is a one-line alias so every existing caller does too. It re-reads the window's
  existence **at post time, riding with the keys**
  (`HotkeyTap.tapWisprScratchpad(if:)`, checked on the posting queue immediately
  before they go out, a skipped press taking its own release with it), and
  afterwards looks once more, `recheckAfterClose` = 0.6 s — longer than the tap's
  own 250 ms hold plus the queue's settle — so a window that is there now is one
  **this app** put there: `🗒️ the close opened it — toggled back`, up to
  `closeAttempts`. `closingNow` keeps two callers from overlapping, and
  `closeIsInFlight` covers it as well as `armCloseOnSight`'s `closeASAP`.
  The one deliberate exception is `POST /test/wispr-scratchpad {"tap": true}`,
  which is the raw toggle the harness opens a window *with*.
- **The orphan sweep runs continuously while idle, and does not care what ended.**
  `WisprScratchpad.startIdleSweep(isIdle:)` from `WisprFlowSource.prepare()`: one
  AX existence read every 0.5 s, and any window that has stood for more than
  **1 s** while `phase == idle` with no capture, no microphone and no speculation
  is closed through `ensureClosed` and logged `🗒️ orphan Scratchpad closed`.
  Arming it *for twelve seconds after a capture* was exactly wrong: the orphan is
  made by a toggle that lands late, so it does not exist yet while such a sweep
  is looking, and by the +3 s and +15 s where the runner found the window
  standing, nothing was watching at all. Verified from a desk with no dictation
  at all — `POST /test/wispr-scratchpad {"tap": true}` to open one, then
  `a Scratchpad window has stood for 1.0 s with no dictation in flight`,
  `the Scratchpad closed on attempt 1`, `orphan Scratchpad closed`, **2.6 s** from
  open to closed.
- **A late *open* edge is the last sentence's, not the next one's** (Finding 2,
  `notifyMs = 4109`). The notification's OPEN arrived after the relay's own stop —
  in Attack 7 *before* the delivery, in Attack 10 with no Scratchpad involved at
  all — and was read as a dictation Victor had started by hand: `dictation
  abandoned (a new dictation started)`, the ring back up, the halo, the selection
  watcher and the recorder all restarted, the ring down again 500 ms later. This
  is the symmetric half of the close-edge rule, and it is asked **before**
  `state.notify`, because `notify(true)` takes an `idle` machine into `listening`
  and would put the phase back into a sentence that is over. `lateOpenEdge()`
  needs the relay's own stop to be the last thing that happened
  (`lastStopAt >= gestureAt`, within **12 s**) and then either the stopped
  sentence's capture still open, or **no newer `History` row** — Wispr writes the
  row at the gesture (357 ms), so a dictation that has really started has one of
  its own and a late notification about the old one does not.
- **`POST /test/wispr-handsfree` intercepts, and `{"hand": true}` does not**
  (Finding 3). The route called `gestureSeen(relay: true)`, so `intercepting` was
  true: the relay swallowed Wispr's ⌘V and re-delivered the sentence itself —
  `lastDelivery={via:wispr-cmdv,kind:route,to:caret}` on a run whose whole point
  was that it would only watch. The old behaviour is kept (it is the transcribe
  primitive the harness is built on) and the promise it was breaking gets its own
  flag: `{"hand": true}` posts the same chord with `relay: false`, which is ring
  only — nothing swallowed, nothing delivered, `relayStarted` and `intercepting`
  both false.
- **A recogniser that has quit is not a recogniser that is slow** (Finding 5).
  Wispr killed mid-settle left the relay holding `Transcribing...` for the whole
  **30 s** of `captureTimeout` before `No words came back`. `pollHistory` now asks
  whether Wispr's **main** process is there — `NSWorkspace` filtered on the
  anchored executable path `/Applications/Wispr Flow.app/Contents/MacOS/Wispr
  Flow`, never the bundle id or the name, both of which match the nested
  Accessibility helper — and two consecutive absences (300 ms;
  `runningApplications` is KVO-updated and one blank reading during Wispr's own
  relaunch is not a death) end it with `⚠️ Wispr Flow quit — the sentence is
  lost`. `closeListening` releases the chord and asks the Scratchpad close,
  `endCapture` disarms the guard and takes the window down, and `ensureClosed`
  is asked for any window the dead instance left — nothing else is going to.
  **Absence is not the only way it dies, and on this rig not the likely one**:
  the harness relaunches Wispr **200 ms** after the kill, so two absences 300 ms
  apart never see it, which is why `wispr-dies-mid-settle` still waited out its
  30 s on the build that was supposed to have fixed it. The pid of Wispr's main
  process is therefore read at the chord (`wisprPidAtChord`) and a **different**
  pid is the same fact and cannot be missed: the process this sentence was
  dictated into is gone, and whatever is running now has never heard of it.
- **A row with nothing in it stops being progress after 8 s** (Attack 12). Two
  seconds of digital silence left row 12814 in `raw_transcript` with `asrText`,
  `formattedText` and `pastedText` all empty **for ever** — Wispr never made it
  terminal — and the relay sat out its full 30 s. `silenceCeiling` is 8 s from the
  microphone's close, the same number the settle gives up on and Wispr's own p99,
  so nothing that was going to arrive is cut off; the answer is **"No speech was
  heard"**, which is a different sentence to show him than *no words came back*.
  `WisprHistory.Entry.asrText` was added for it: `status` alone cannot tell
  *still thinking* from *heard nothing*.
- **A gesture during the settle that is not a cancel was already safe** — the same
  run's `forward-click` 100 ms after the stop is a no-op (`nothing to start,
  nothing to stop`), the ⌘V is swallowed and the sentence delivers normally.
- **A dictation that came back with nothing owes the window and the keyboard back
  most, not least.** `endCapture` claimed `scratchpadWindowHandled` at the
  *release*, so a timeout left the Scratchpad standing — the runner watched it for
  three seconds after `No words came back`, with his keystrokes going into the
  note throughout. It now disarms the guard and closes the window on **every**
  exit from a Scratchpad capture, whatever ended it.

### The measured truth about his keystrokes, and what is accepted

Wispr's Scratchpad panel takes the keyboard for a stretch of every dictation, and **what he types
in that stretch is lost**. This is what three nights of measurement actually establish:

- **The window is up for the whole sentence**, from the chord to the close. It is not dangerous for
  all of it: keys typed *during the recording* are re-posted and land in the app he is in.
- **The dangerous stretch is the tail** — from Wispr's own paste into its note until the relay's
  close takes the window down, roughly **0.5–2 s after the stop gesture**. In that window no
  *key-posting* route reaches him: an application that is frontmost with **no key window has no first
  responder**, and `postToPid` to a *verified-live* victim drops the character exactly as the
  session post does. ⌘V survives only because `performKeyEquivalent` needs no first responder,
  which is why the **delivery** works and the letters do not.
- **Accessibility is the route that works, and it works off the tap thread.** `AXSelectedText`
  needs no key window, which is the whole point; the call is a synchronous round trip into another
  application, so it happens on `HotkeyTap.axQueue` — serial, `.userInteractive`, **200 ms per
  character** through `AXUIElementSetMessagingTimeout`, and a character that misses the deadline is
  **said to be lost** rather than queued behind the next. The tap does only what a tap can do
  quickly: decide, translate the keycode through the layout, swallow, hand it on. Measured
  2026-09-14 02:10 — `seen=7 redirectedAX=5 redirectedKey=2 passed=0`, **all seven probe letters in
  the victim document**. Ships on; `WT_SCRATCHPAD_AX_INSERT=0` turns it off.
- **`TISGetInputSourceProperty` asserts the main thread, and the tap is not it.** Three runs died
  on this and every one of them looked like something else — a dictation that simply stopped, a
  relay that was dead when I looked, an AX insertion that seemed to be the culprit. The crash
  report is unambiguous: `_dispatch_assert_queue_fail` → `TSMGetInputSourceProperty` →
  `HotkeyTap.translate`, `SIGTRAP`. The layout is read once on the main thread
  (`refreshKeyboardLayout`, re-read when the input source changes) and the tap touches only a
  `Data`. **Never call a TIS function from the event tap.**
- **And no focus reading is true**, in either direction: the Scratchpad reports `AXFocused == false`
  while it is taking the keystrokes, and the victim reports its own `AXTextArea` as focused while
  receiving none of them. The gate is the window's **existence**, because that is the only thing
  that correlates.

**So the accepted cost is a second or two of the keyboard, once per dictation** — the same trade
Victor made knowingly for the sink, and the reason he rejected the sink as the *primary* path was
its cost being paid on *his focus*, not on a second of typing he was not doing anyway. A dictation
is a thing he is speaking, not typing, through.
- **The theft cannot be undone.** Re-activating the victim does nothing (`activate` says *be
  frontmost* and it already is); `AXMain` / `AXFocused` on the window he was typing in logs
  `the focus owner is still Wispr`.
- **The FRONT is a different loss and it is given back** (2026-09-14). The bullet above is about
  the *key window*, which cannot be recovered because the victim never stopped being frontmost.
  The **close chord** posted at the stop is another matter: Wispr answers it by activating
  `com.electron.wispr-flow`, so the victim really goes behind — measured on two caret dictations
  Victor lost out of Terminal, `the front app changed since the chord — his keys go to pid 92966,
  not 46446`, in the same second as `scratchpad chord DOWN/UP`. Every close now funnels through
  `WisprScratchpad.onCloseFinished` and `WisprFlowSource.putTheFrontBack` hands the front back:
  only when Wispr is frontmost at that moment, to `frontBeforeLast` (the app he was in when it was
  taken, not the one from the chord), `activate` plus `AXRaise`/`AXMain`/`AXFocused`, at +0.45 s
  and +1.5 s, five per minute at most, logged under `🪟`. **Never on
  `didActivateApplication` during the sentence** — handing the front back while Wispr is still
  writing its note aims Wispr's own insertion at his document.
- **`activate` does not take a front back; `AXFrontmost` does** (measured 2026-09-14, 06:13 vs
  06:14, theft provoked on purpose). A background app asking for *another* app to be frontmost is
  declined by macOS — the first build logged `it would not go back to Terminal` twice.
  `AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute, true)` is
  granted, because it is asked with the Accessibility trust. Both calls are made and both results
  are in the log line.
- **`frontmost_app()` in the rig cannot see a stolen front.** It asks System Events for the first
  process whose `frontmost` is true, and that answered **`Terminal` while
  `NSWorkspace.frontmostApplication` answered `Wispr Flow`** — so `focus never moved off the
  victim` stayed green through the very loss Victor reported. Read the front with `NSWorkspace`
  before trusting that assertion about a Wispr window.

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

## Shot markers — a spoken index injected into the recogniser's ear (2026-09-14)

Rules for `ShotMarker`. The problem: every frame carries the second it was taken at
(`shot-00:56…`) and an agent handed five of those has to guess which clause each belongs to.
Victor: *"e mult mai util dacă le-aș referi după index … că, după timp, e greu să estimezi."*

- **The mechanism is two microphones, one voice.** Wispr is pinned to the Loopback device
  `🎓 TO Wispr`; the relay's `MicRecorder` opens the **physical** device. So a sound played into
  the Loopback device's output side reaches **Wispr and nothing else** — not the speakers, not
  the corpus. Measured: the corpus WAV recorded in parallel with a marker run is `-91.0 dB`.
- **Both halves live in `ShotMarker`** — `play(index:whenQuiet:)` says it, `resolve(text:available:)`
  reads it back. One vocabulary (the phrase, the number words, the digit forms); split over two
  files it drifts the first time somebody rewords one end.
- **The source is asked `acceptsAudioMarkers`, never *are you Wispr*.** Default `false` on the
  protocol; only `WisprFlowSource` says yes. The local model opens the physical microphone
  itself and would need the marker spliced into its own buffer — a different mechanism, not built.

### What was measured the day it was built

| | |
|---|---|
| markers in `asrText`, spliced into a 20 s clip of his voice | both, in position |
| the same in `formattedText` | both, **promoted to their own paragraphs** |
| three markers into a **silent** dictation | `Screenshot one. Screenshot two. Screenshot three.` |
| one marker 6 s into an **unbroken** 12 s sentence | **no trace at all** |
| marker level against the voice | −15.7 dB mean against −26.8 — the marker is the *louder* one |
| a marker landing mid-word | cuts it: `pus sub un strat` → `pus sub un-` / `Strat` |

- **Masking is not a level problem and cannot be turned up.** The marker already wins on level
  and still vanished: a recogniser handed two voices at once transcribes the one that makes a
  sentence. Hence the gate — `MicRecorder.quietSeconds ≥ 0.12 s`, polled every 40 ms on
  `ShotMarker`'s own queue, ceiling **1.5 s** and then spoken anyway, because a marker lost
  costs nothing and a marker never said costs the picture its place in the sentence. The wait is
  in the log: `(1540 ms for a gap)` is the ceiling being reached.
- **Overlapping is his gesture, not an edge case** — *"De exemplu, ăsta acum"*, pressed
  mid-clause. A marker that only worked in a pause he happened to leave would mostly not work.

### The rules that cost something

- **The number is reserved at the shutter, before `screencapture` runs**, and stored **by path**
  (`shotMarkerNumbers`, carried on the `Message` beside `sources`). Two presses a third of a
  second apart can finish in the other order, and a number read off the list's position would
  then name the wrong frame — the one failure that makes the feature untrustworthy.
- **The safety net is a set of real pictures, not a count.** A capture that failed leaves a
  number spoken with nothing behind it, and a count would renumber every marker after it onto
  the wrong frame. A marker outside the set is taken out of the words and logged.
- **The words are rewritten before the corpus is filed** (`resolvingShotMarkers`, at the top of
  `deliver`). The relay's own recording never heard the marker, so filing `Screenshot one.`
  against it would put a pair in the corpus whose transcript says words its audio does not.
- **`onTestDictation` calls the same helper**, because that route's claim is that a fabricated
  transcript enters where a real one does — and it enters *below* `deliver`.
- **The shutter is not on the main thread** (`HotkeyTap.onScreenshot` → `DispatchQueue.global()`),
  so `reserveMarker` may not read `source`: `setEngine` reassigns it from the main thread.
  `wireDictationSource` publishes `markerMeter` under `stateLock` instead, and nil is the whole
  of *do not speak markers*.
- **`POST /test/shot-marker` is the unit test**, both halves, for `wispr-state/simulate`'s reason.
- `WT_SHOT_MARKERS=0` off for a run; `WT_MARKER_DEVICE` points it elsewhere. With no matching
  device it says so **once** and stays quiet — a Mac where Wispr has been moved back to the
  built-in microphone is one where a marker reaches nobody.

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
  `Settling` in `docs/gestures.puml` has no arrow out of it for a forward click, so
  a click there is an internal no-op rather than a guarded one (2026-09-14) — the
  phantom dictation is unreachable, not merely defended against. `startDictation`
  carries `!settling` behind it; and `retireCaptureIfSettled` replaces the
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
  into Word; and a second 🔼 click landed inside the settle, where the handler asked only about
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
