---
paths:
  - "Sources/WalkieTalkie/AppDelegate.swift"
  - "Sources/WalkieTalkie/Outbox.swift"
  - "Sources/WalkieTalkie/SessionLabel.swift"
---

# Destinations and the outbox

Rules for where a dictation goes and when it is written: the held prompt, the outbox line, the unbound hold (`awaitingBind`), the home folder, ⌘⌃P, the send flight and the prompt panel's keys. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## When the outbox is written

- **Write the JSONL line at delivery, never before.** `commit` returns into `holdForBind` *before* `Outbox.send`; a held sentence lives in memory and nowhere else, so a relay left unbound all day leaves no log behind it. Victor's 2026-08-27 choice stands: *"an outbox filled all day for a watcher that is usually not there is not a feature, it is a log of his private dictation."* → journal: *The outbox half of the 2026-08-27 decision stands*
- **`session_end` is not delivered to terminals.** It is addressed to a watcher and means nothing to a terminal; quitting (✕, menu **Quit**) still writes it, unbinding does not. → journal: *Bound to a terminal: the second destination*
- **Only `commit()` writes the held prompt** — on the countdown running out, a click on the overlay body, or quit. The agent polls the outbox every couple of seconds, so a line already written may already be a tool call in flight; Cancel can only mean something while nothing has been written. → journal: *The prompt is held, not sent*

## Unbound: hold, do not refuse (`holdsForBind`, 2026-09-11)

- **With nothing bound the app does everything it does bound; the sentence waits for the bind.** *"tot ce pot să fac când sunt legat de un terminal să pot să fac și atunci când sunt nelegat, urmând a mă lega ulterior"*. `AppDelegate.holdsForBind` is one `static let`, the one word to flip if the hold proves worse than the refusal was. `hasDestination = isBound || spawnPending || pasteMode`; with none of them the dictation is held rather than dropped. → journal: *Unbound is inert — retired (2026-09-11)*

  | gate | unbound, before | unbound, now |
  |---|---|---|
  | `captureContext` — flash, selection probe, screen capture | off | **on** |
  | `plusOneShot` — mouse 4 | off | **on** |
  | `areaShot` — the wheel drag | off | **on** |
  | `syncBorrowedGestures` — mouse 4, ⌘⇧-click, the selection watcher | off | **on** |
  | `syncLocalCapture` — the wheel's claim on the microphone | off | **on** |
  | `StatusItem`'s **Start Dictation** row | greyed | **live** |
  | `send` — the delivery | dropped | **held, then delivered** |
  | the outbox line | not written | **written at delivery, not before** |
  | `corpus.captureLocal` | on | on |

- **`awaitingBind` holds one sentence, not a queue.** A second dictation replaces the first; the replaced one is not lost, ⌘⌃P still pastes it because `lastDictation` is set above the hold. → journal: *`awaitingBind`: one sentence, five minutes*
- **Five minutes**, the same net as `Recover Cancelled Dictation`. On expiry the chip says `⏳ held dictation expired — ⌘⌃P to paste it`; the alternative is a sentence he believes is still on its way. → journal: *`awaitingBind`: one sentence, five minutes*
- **Release it from `showBound`, deliberate or not.** Every route into a binding passes through it (⌘⌃B, the chords, `POST /bind`, the restart's restore, a spawned window adopting itself). Unlike the spawn and caret take-backs, the poll cannot produce a binding out of nothing, so it can never be the call that releases this. → journal: *`awaitingBind`: one sentence, five minutes*
- **The chip says `⏳ bind to send — ⌘⌃B` while he talks**, in the destination row, naming the *gesture*; it comes down the moment a bind lands. → journal: *`awaitingBind`: one sentence, five minutes*
- **`syncLocalCapture`'s cost is outside this app.** With **Use Logi Gestures unticked** the wheel is the relay's for as long as the relay runs — middle-click stops opening links in Chrome and closing tabs in VS Code (*"folosesc middle click sa inchid de ex taburi chrome/vsc"*). In the default mode it costs nothing. The line to put back to `isBound` is one, named in `syncLocalCapture`'s own comment. The unbound double-click branch at the bottom of `HotkeyTap`'s middle-button chain is unreachable now and is left standing for the flip back. → journal: *The one gate whose price is outside this app*
- **Pause never comes back, and `holdsForBind` must never become a menu tick** — a tick for it would be pause under another name. *"nu mai vreau să am conceptul de pauză"* (2026-09-01). Disconnect is the "hand the mouse back" gesture: reachable from the right-held chord and the menu, and it says *which* terminal it let go of. A click on the chip at rest does nothing. → journal: *Pause still does not come back*, *Pause is gone*

## Scope and focus

- **No typing affordance on the overlay's own surface.** `canBecomeKey` is false (except `RelayPanel.wantsKey` while the transcript is edited) precisely so the overlay can never steal the caret from the app Victor is working in. Delivering into a bound terminal is the opposite gesture: words go somewhere else without the overlay becoming key; `.keystroke` is the one place focus moves, to the target and straight back. → journal: *Scope: dictation helper only*
- **`captureContext` runs before `overlay.setListening(true)` in `dictation.onChange`.** It books the context shot synchronously (`contextShotPending`, so the row says `×1` from the instant it opens, not `×0` for the ~400ms clipboard probe plus a subprocess), and `setListening(true)` zeroes the count — the other order publishes a `×1` into a row about to reset it. → journal: *The recording rows*
- **Every AppKit call in an `ElementPicker` callback needs its own hop to main.** The callbacks run on the listener thread; `overlay.setSpawnDestination` called directly set a window frame off the main queue and took the app down with a `SIGTRAP` inside `NSWMWindowCoordinator`. `captureContext` never had the problem because it already hops. → journal: *What a caret dictation carries (2026-09-08)*

## Home folder (`Outbox.adoptLegacyHome`)

- **`~/.wispr-relay` is merged into `~/.walkie-talkie` on first launch — a merge, not a rename.** It holds the voice corpus, 300 MB of Victor's own speech paired with transcripts. The VS Code extension and the skill's `install.sh` create `~/.walkie-talkie/ide/` with `mkdir -p` before the first renamed relay runs, so a rename-if-absent would have skipped itself forever. Each entry moves only when the destination has none of that name, directories on both sides merge one level down, nothing is overwritten. → journal: *The rename, and the two places the old name survives*
- **`--home` skips the merge, checked rather than assumed** — without the guard a test instance drags the real corpus into a scratch directory. → journal: *The rename, and the two places the old name survives*
- **`IDEBridge` reads both registries** (`~/.wispr-relay/ide/` and `~/.walkie-talkie/ide/`): an extension host keeps the code loaded when its window opened, and a window not yet reloaded would fall back to a blind paste. → journal: *The rename, and the two places the old name survives*
- **The bundle id stays `ro.victorrentea.wispr-relay`** (with it the Caches path and queue labels): macOS keys Accessibility, Screen Recording and the microphone to it. → journal: *The rename, and the two places the old name survives*

## ⌘⌃P pastes the last envelope

- **Paste the whole `terminalLine`, recorded at `commit`** (since 2026-09-04): `📸 ×2 0:38`, the quoted selection, the picked selectors and the frame paths — byte for byte what the session received, since `commit` records `terminalLine(m)`, the same call `deliverToTerminal` and `spawnClaude` make. Where this lands is overwhelmingly another agent, and the screenshots are the half that cannot be retyped. → journal: *⌘⌃P pastes the last dictation*
- **Recorded at `commit`, so a cancelled prompt does not overwrite the last thing that went out**, and an edit is folded in. Replace Wispr pastes the words: that mode builds no envelope. → journal: *⌘⌃P pastes the last dictation*
- **The clipboard is not restored afterwards** — unlike `TerminalBinding`'s blind paste, here he asked for it. Silent on success; `⚠️ nothing dictated yet` is the one thing said aloud. From the menu the ⌘V waits a beat for AppKit to give the caret back. → journal: *⌘⌃P pastes the last dictation*

## The held prompt

- **Hold for `minHold`–`maxHold`, scaled by word count** (the journal records 3–5 s; `AppDelegate` currently reads `minHold = 4.0`, `maxHold = 7.0` — the constants are the source of truth), behind a **Cancel** button bottom-right. → journal: *The prompt is held, not sent*
- **Stamps are m:ss from the moment the dictation opened, drawn on the frames** (`AppDelegate.shotStamps`, `RelayWindow.layoutShots`, since 2026-09-02) — a dark pill in the thumbnail's left corner, 10pt semibold monospaced digits. Wall-clock does not locate a moment *inside* the message. → journal: *The prompt is held, not sent*
- **The context screen is counted but not stamped**: `shotStamps` gives it an empty string, not a missing entry, so stamps stay index-aligned with the frames. → journal: *The prompt is held, not sent*
- **Count from `pendingScreen` + `pendingShotOffsets`, never from `attached`** — the screen travels in its own outbox field, so `attached` prints a total one lower than the `📸 ×N` he watched climb. The `🎙️ sent + N 📸` flash counts the same way. → journal: *The prompt is held, not sent*
- **Sample offsets at the gesture** (`plusOneShot`'s `takenAt`): `screencapture` returns a subprocess later, and a second of drift is a whole sentence. → journal: *The prompt is held, not sent*
- **Ordering is preserved**: a second dictation arriving mid-countdown releases the first before displaying itself. → journal: *The prompt is held, not sent*

## The send flight

- **An outline only (`outlined:`, since 2026-09-07), 0.7 s, through the same `BindFlight` machinery.** *"vreau să se ducă spre un border doar … doar să înțeleg că se duce într-un terminal, undeva"*. `carrying:` and `panelImage()` are gone. → journal: *The send flight (2026-09-04)*
- **Re-resolve the destination, never remember it.** `Target.sourceFrame` is stale after any drag; ask `terminalWindowFrame(tty:)` for the window showing the bound tty *now*. → journal: *The send flight (2026-09-04)*
- **No flight for IDE and keystroke targets** — nothing outside those apps can name their window's frame honestly. → journal: *The send flight (2026-09-04)*
- **Hold the dialog for the flight, and release it at once on every path with no flight.** `resolvePrompt` holds the panel on every send, `sendFlight` schedules the fade `spawnPanelFadeDelay` later; an IDE or keystroke target, a window that could not be found, a send with no panel behind it must release immediately — a dialog waiting for a flight that never comes is a dialog that never closes. A cancel (the 🗑️ row) does not fly; Replace Wispr holds no prompt. → journal: *The send flight (2026-09-04)*

## ⏎ and click-to-edit

- **⏎ sends, swallowed in `HotkeyTap` (`promptHeld`, `onPromptEnter`), bare only, and only while a prompt is up.** ⌘⏎ and ⇧⏎ belong to other people; outside the hold window the key is untouched. → journal: *⏎ sends it, and clicking the words edits them*
- **Only the words are editable** (`promptWords` / `promptExtras`, `showSentPrompt` takes raw `words:`); if the two do not agree the text is not editable. → journal: *⏎ sends it, and clicking the words edits them*
- **The clock stops in the field and restarts whole on leaving.** Clicking outside the panel counts (a global mouse monitor armed only while editing). → journal: *⏎ sends it, and clicking the words edits them*
- **`RelayPanel.wantsKey` gates `canBecomeKey`, and `.nonactivatingPanel` keeps the terminal frontmost.** Handing the keyboard back is `orderOut` + `orderFrontRegardless`. → journal: *⏎ sends it, and clicking the words edits them*
- **`PromptField` is one view, not a label swapped for a field, and its `mouseDown` override is load-bearing** — a label swallows the click, so before it clicking the words reached nothing. → journal: *⏎ sends it, and clicking the words edits them*

## Do not

- **Do not reintroduce pause**, and do not make `holdsForBind` a menu tick — a tick for it would be pause under another name. → journal: *Pause still does not come back*
- **Do not reintroduce a typing affordance** on the overlay's surface. → journal: *Scope: dictation helper only*
- Do not write the outbox line before delivery, and do not turn `awaitingBind` into a queue.
