---
paths:
  - "Sources/WalkieTalkie/AppDelegate.swift"
  - "Sources/WalkieTalkie/Outbox.swift"
  - "Sources/WalkieTalkie/SessionLabel.swift"
---

# Destinations and the outbox

Rules for where a dictation goes and when it is written: the held prompt, the outbox line, the unbound hold (`awaitingBind`), the home folder, the clipboard, the send flight and the prompt panel's keys. Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## When the outbox is written

- **Write the JSONL line at delivery, never before.** `commit` returns into `holdForBind` *before* `Outbox.send`; a held sentence lives in memory and nowhere else, so a relay left unbound all day leaves no log behind it. Victor's 2026-08-27 choice stands: *"an outbox filled all day for a watcher that is usually not there is not a feature, it is a log of his private dictation."* → journal: *The outbox half of the 2026-08-27 decision stands*
- **A bound terminal's line is written after the keystrokes, on `.delivered` only** (2026-09-26): `commit` hands the message to `deliverToTerminal`, which writes the row and `lastDelivery` when `TerminalBinding.deliver` answers `.delivered`. A refusal, a dead tab or a failed send leaves no receipt (TR21, TD15, TD16 used to). `session_end` and an unbound non-dictation message still write at `commit` — the outbox is their delivery. **A spawn writes its `spawn:` row when its window is bound** (2026-09-26, TR22: `spawnClaude` → `adoptSpawnedWindow(tty:adopted:)`), and a failed spawn writes none; from the launch to that bind `busy` says `spawning` (`spawnsInFlight`, TD25). Deliveries run on one serial queue, in order. → journal: *Fixes to the test plan's findings, batch 1*
- **The recipient is the terminal latched when the microphone closed** (Victor's Q2, 2026-09-26: *"vechi, ca poate vreau să deschid altă dictare deja"*). `dictationStoppedListening` sets `latch` beside `latchedAtCaret`; `deliver` takes it, `send` puts it on `Message.target`, `commit` hands it to `deliverToTerminal(_:line:to:)`. A bind to B in the settle or under the panel no longer sends A's sentence to B (TD4, TR24, TG19); an unbind no longer holds it (TD29) — it goes to A while A lives, else to the caret (below). `target == nil` means *the next bind*: the binding at `commit` if one has landed, else held. A sentence with no close on this side (`POST /test/dictation`) is addressed at `send`. `GET /test/state.latchedTarget` shows it (`latchedTargetPending` when it is *the next bind*). → journal: *Fixes to the test plan's findings, batch 2*
- **A terminal gone at delivery → the words are pasted at the caret** (Victor's Q4, 2026-09-26): `deliverToTerminal` on `.targetGone` records `caret` and `pasteText`s the envelope; no outbox line; the binding goes as before. → journal: *Fixes to the test plan's findings, batch 1*
- **Shots with no transcript go out alone after 120 s — counted from the stop** (2026-09-26, TL1, TD8). The orphan timer (`orphanTimerFired`) does nothing while the sentence is open, settling or its words are in flight, and re-arms; `dictationStoppedListening` re-arms it from the close. It used to fire 120 s after the *start* and wipe a long sentence's envelope under him (context, selection, markers, `dictationStartedAt`), sending its shots on their own. → journal: *Fixes to the test plan's findings, batch 3*
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

- **Nothing bound at the close → held, never the caret** (Victor's Q1, 2026-09-26: *"bind to send memory"*). `latchedAtCaret = pasteMode`; the unbound caret clause (`!isBound && !spawnPending && spawnPickInFlight == nil`) is gone, and so is the halo's `listening && !isBound` caret clause. The caret is the forward click / F7 (`pasteMode`), the back click's clean sentence, and a sentence **Wispr's own chord** opened with nothing bound (`noteHandStartedAtCaret` sets `pasteMode` — holding it would take Wispr away from every app while the relay is unbound). 🔼 → over a clean sentence takes it to the terminal (`cleanRedirected`; TG13). The chip counts what waits: `📨 N waiting — bind to send`. → journal: *Fixes to the test plan's findings, batch 2*
- **`awaitingBind` is a queue, delivered in order** (Victor's Q3, 2026-09-26: *both are kept*). It held one sentence until then and a second replaced the first silently (TD2). `releaseAwaitingBind` commits every held sentence oldest first; the serial delivery queue keeps the typing order. → journal: *Fixes to the test plan's findings, batch 1*
- **Five minutes per sentence**, the same net as `Recover Cancelled Dictation`. On expiry the chip says `⏳ held dictation expired — ⌘V to paste it`; the alternative is a sentence he believes is still on its way. → journal: *`awaitingBind`: one sentence, five minutes*
- **Release it from `showBound`, deliberate or not.** Every route into a binding passes through it (⌘⌃B, the chords, `POST /bind`, the restart's restore, a spawned window adopting itself). Unlike the spawn and caret take-backs, the poll cannot produce a binding out of nothing, so it can never be the call that releases this. → journal: *`awaitingBind`: one sentence, five minutes*
- **The chip says `⏳ bind to send — ⌘⌃B` while he talks**, in the destination row, naming the *gesture*; it comes down the moment a bind lands. → journal: *`awaitingBind`: one sentence, five minutes*
- **`syncLocalCapture`'s cost is outside this app.** With **Mouse Gestures: Wheel** the wheel is the relay's for as long as the relay runs — middle-click stops opening links in Chrome and closing tabs in VS Code (*"folosesc middle click sa inchid de ex taburi chrome/vsc"*). In the default mode it costs nothing. The line to put back to `isBound` is one, named in `syncLocalCapture`'s own comment. The unbound double-click branch at the bottom of `HotkeyTap`'s middle-button chain is unreachable now and is left standing for the flip back. → journal: *The one gate whose price is outside this app*
- **Pause never comes back, and `holdsForBind` must never become a menu tick** — a tick for it would be pause under another name. *"nu mai vreau să am conceptul de pauză"* (2026-09-01). Disconnect is the "hand the mouse back" gesture: reachable from the right-held chord and the menu, and it says *which* terminal it let go of. A click on the chip at rest does nothing. → journal: *Pause still does not come back*, *Pause is gone*

## Sentences queue: max 2 in flight, delivered in order (Q12, 2026-09-26 batch 6)

- **A start while the last sentence's words are in flight is queued, not refused** — `startBlocker`
  asks `queueRefusal()`: refused only with **two already in flight** (flash *⏳ Two sentences in
  flight — wait for one to land*, log `start refused — two sentences are already in flight`), an
  engine that is not `queuesSentences` (only ElevenLabs is: local and Wispr keep batch 3's refusal),
  a spawn or a film in flight, or within **0.8 s of the stop** (the same click twice).
  `WT_SENTENCE_QUEUE=0` (env / `elevenlabs.env`) puts the old rule back.
- **A sentence the local model is decoding is parked on every engine** (D, 2026-09-28 wave 3 —
  two Wispr Q14 answers were dropped silently when the next sentence closed them): `startBlocker`
  lets the start through when `fallingBack` and `fallbackParkRefusal()` is nil, `startDictation`
  parks it (`queuesSentences || fallingBack`), and `dictationBegan` parks instead of closing (a raw
  chord that skipped `startDictation`). Not parkable (a second one parked, a spawn, a film) → refused
  with the flash *⏳ The previous sentence is still being transcribed locally*. Cases TN4 (Scribe 401),
  TW33 (Wispr NULL row).
- **The mechanism is a swap, not a rewrite.** Every per-sentence field stays where `deliver` / `send`
  read it; `parkLiveSentence()` moves them into the in-flight `Sentence` (`Envelope`:
  `takeEnvelope` / `putEnvelope`, the shutter's under `stateLock`), the new sentence starts fresh,
  and the parked one's answer runs with its envelope swapped back in (`run`, `answeringInBackground`
  — the microphone, the chip's live rows, the halo, the film, `settleGiveUp` and `orphanFlush` stay
  the live sentence's). A new per-sentence field **must be added to `Envelope`**, or the second
  sentence inherits it.
- **Answers find their sentence by take** (`DictationSource.take` / `answeringTake`, set around each
  `didTranscribe` / `didEnd`); the fallback's by `contextSentence`. **Order:** an answer waits
  (`Sentence.waiting`) behind an older sentence in flight and behind a held prompt panel —
  `drainSentences()` at every answer and at `releaseHeld`. A cancel never waits.
- **🔼← = the live sentence**: recording, else the newest in flight — `source.cancelTake(live.take)`,
  not the source's newest upload. When the live one ends, the parked one becomes live again
  (`unparkIfIdle`: its fields, its `Transcribing…` row, its give-up).
- `GET /test/state.sentences` (`{id, state, target, startedAt, take, waiting}`, oldest first),
  `state.sentenceQueue`; cases `evals/plan/cases_queue.py` Q1–Q6. → journal: *batch 6, item 5*

## The envelope: tokens where he made them, a legend under the words (2026-09-19)

Victor's own template, and the shape that ships. Full reasoning: journal, *The envelope becomes
tokens where he made them (2026-09-19)*.

- **Every attachment is a bracket in the sentence**, built by `ShotMarker.Token` and nowhere else: `[📸1🖱️@1000:800]`, `[📸3✂️900,345→2594,574]`, `[selected: "…" from app Chrome]`, `[chrome-selection-1: <its text>]`. `ShotMarker.render` is a lookup into prepared tokens — it decides *where* they go and never what they say.
- **The footer is a legend keyed by those tokens** (`AppDelegate.artifactsClause`): `[📁=<folder>]` once and only when something is in it — the line that *defines* `📁` carries it (2026-09-20) — then a row per artifact. **The plain frames share one `[📸n = 📁/screenshot-n-800px.jpg, or -original.jpg at 3456x2234px]`** since 2026-09-20, measured at 36/36 on naming a frame no row mentions (`at 800px width` dropped 2026-09-29: 12/12 fresh Sonnet/Opus runs still read 800 as the width and derived 450, `evals/envelope-width/`); the `auto` token has a line of its own with **no blank line** under it (2026-09-29); the conditions and the two tests are in `screenshots-and-selection.md`, *The footer folds the plain frames into one row*. A row that carries a clock never folds.
- **An area whose token is in the words keeps its corners there only** (2026-10-07, Victor: *"only the
  first scissors should say [it] … the whole thing is inferable from just the number"*). Its row reads
  `[📸1✂️ = user-selected area between corners (x,y) given in its token, cut out at 📁/screenshot-1.jpg;
  …]`, and two or more such areas (same screen size, no ⇧-drag, `screenshot-n-original.jpg` names) fold
  into one `[📸n✂️ = … cut out at 📁/screenshot-n.jpg; …]`. An area not placed in the words (Wispr) keeps
  the full row with its corners. Not re-measured with `evals/envelope-symbols/`.
- **`auto` marks the frame he did not press for** — `[📸0🖱️@1000:800 auto]`, from `AppDelegate.leading` only. It was the last thing in the envelope a reader had to guess.
- **A token the words could not carry keeps its row and gains `at m:ss`.** Placement needs word timings, so on Wispr Flow (no timings; spoken markers aside — `dictation-source.md`, *Markers*) nothing is inline and the footer is the whole envelope. That is not a degradation; it is the addressing the tokens are an optimisation over.
- **The context frame leads the words and has no cue.** He took it by starting to talk. At the caret there is none at all — that mode takes no context shot, and Victor confirmed it stays that way (2026-09-19). **Superseded 2026-09-23 for the forward click**: its caret sentence is a prompt and carries the whole `terminalLine` envelope, context frame included (`AppDelegate.caretPrompt`); the back click's is the words alone (`cleanSentence`). → journal: *Forward is a prompt, back is plain words*
- **`[Focused window: …]` and `picksClause` are gone**; the application survives only inside a highlight's token, where it says which app the text came *from*. The hint is `[Dictated in RO or EN]`.
- **Measured before shipping** — `evals/envelope-symbols/`, 18 runs, 11 comprehension questions: **Sonnet 33/33 and Opus 33/33** on Victor's template against 30/33 and 32/33 on the envelope it replaces, at **925 characters against 1810**. **Round two, 2026-09-20**, 36 runs over a scene with three plain frames: folding those rows is free (36/36 on naming 📸2's full-resolution file) and costs only the inferred *which frame was automatic*, which ` auto` then answers outright — 78/78 both models, 155 characters less.
- **Number the pictures consecutively as they attach.** Every run of the eval remarked on the gap in the sketch's `📸1 … 📸3`; a hole reads as a picture that was lost.

## What the envelope enumerates (2026-09-13)

- **Three lists, one shape, one clock.** The frames (`shotsClause`), the highlights (`selectionsClause`) and the picked elements (`picksClause`) are each a heading followed by `- ` lines, and every line starts with `mm:ss` from the moment the dictation opened — the same reading a frame already carries in its name. Victor's reason is one sentence: the agent should know *when* in the dictation each thing happened, relative to what he was saying. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **`Message` carries `selectionAt` and `selectionSource` beside `selection`**, and `extraSelections` is a `SelectionRecord` (`at`, `text`, `source`). New fields beside the old ones, never a new meaning for an old one: `selection`, `selections[].at` and `elements[].text` are documented by name in the `relay` skill and still say exactly what they said. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **The outbox gained `selectionAt` / `selectionIn`, `selections[].seconds` / `.in`, and `elements[].at` / `.textChars`.** Offsets in the JSON are **numbers**; `m:ss` is for reading, and anything comparing two of them would otherwise be parsing a clock back. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*

## Scope and focus

- **No typing affordance on the overlay's own surface.** `canBecomeKey` is false (except `RelayPanel.wantsKey` while the transcript is edited) precisely so the overlay can never steal the caret from the app Victor is working in. Delivering into a bound terminal is the opposite gesture: words go somewhere else without the overlay becoming key; `.keystroke` is the one place focus moves, to the target and straight back. → journal: *Scope: dictation helper only*
- **`captureContext` runs before `overlay.setListening(true)` in `dictation.onChange`.** It books the context shot synchronously (`contextShotPending`, so the row says `×1` from the instant it opens, not `×0` for the ~400ms clipboard probe plus a subprocess), and `setListening(true)` zeroes the count — the other order publishes a `×1` into a row about to reset it. → journal: *The recording rows*
- **Every AppKit call in an `ElementPicker` callback needs its own hop to main.** The callbacks run on the listener thread; `overlay.setSpawnDestination` called directly set a window frame off the main queue and took the app down with a `SIGTRAP` inside `NSWMWindowCoordinator`. `captureContext` never had the problem because it already hops. → journal: *What a caret dictation carries (2026-09-08)*

## Home folder (`Outbox.adoptLegacyHome`)

- **`~/.wispr-relay` is merged into `~/.walkie-talkie` on first launch — a merge, not a rename.** It holds the voice corpus, 300 MB of Victor's own speech paired with transcripts. The VS Code extension and the skill's `install.sh` create `~/.walkie-talkie/ide/` with `mkdir -p` before the first renamed relay runs, so a rename-if-absent would have skipped itself forever. Each entry moves only when the destination has none of that name, directories on both sides merge one level down, nothing is overwritten. → journal: *The rename, and the two places the old name survives*
- **`--home` skips the merge, checked rather than assumed** — without the guard a test instance drags the real corpus into a scratch directory. → journal: *The rename, and the two places the old name survives*
- **`IDEBridge` reads both registries** (`~/.wispr-relay/ide/` and `~/.walkie-talkie/ide/`): an extension host keeps the code loaded when its window opened, and a window not yet reloaded would fall back to a blind paste. → journal: *The rename, and the two places the old name survives*
- **The bundle id stays `ro.victorrentea.wispr-relay`** (with it the Caches path and queue labels): macOS keys Accessibility, Screen Recording and the microphone to it. → journal: *The rename, and the two places the old name survives*

## The clipboard holds the finished sentence (Q17, 2026-09-28)

Victor: *"întotdeauna la finalul dictării cu walkie-talkie să rămână în clipboard ce s-a dictat …
scriem în clipboard la final promptul sau dictarea curată, indiferent ce și cum."* → journal:
*Wispr as engine: decisions Q14–Q23*.

- **At the end of every dictation the final text is written to the pasteboard** — whatever the
  engine (Wispr, ElevenLabs, local, the local fallback) and wherever it went (bound terminal, spawn,
  caret, a held sentence at its release, a panel sent after an edit): the **prompt envelope**
  (`terminalLine`, byte for byte what the agent received) for a relay sentence, **the clean words**
  for a plain one (the back click, right ⌘⌥ held). One call site at the end of delivery, never
  per destination.
- **The previous clipboard is never restored.** The sentence is always one ⌘V away; that is the
  feature (W5 argued the other way and was overruled).
- **Wispr's own clipboard dance comes after ours** (W8: Wispr writes its text ~30 ms before
  `formatted` and restores the old clipboard ~250 ms later, even when its ⌘V is dropped), so on a
  Wispr sentence the write is re-asserted once Wispr's restore has passed.
- **⌘⇧P is gone** (and ⌘⌃P before it). Nothing re-pastes: ⌘V does. The chip's row after a delivery
  names **⌘V** (`PasteHint`). Do not bring a re-paste key back — the clipboard holds the sentence.
- **A cancelled dictation writes nothing** — there is no finished text; *Recover Cancelled
  Dictation* is that case's door. **A cancelled prompt panel does** (its words are finished text):
  the envelope goes on the clipboard and the hint follows.
- **One door: `AppDelegate.holdOnClipboard(_:why:)`** — called from `commit` (every relay sentence,
  bound, spawned or held for a bind), `pasteText` (every caret sentence), the two *the source
  inserted it itself* branches of `deliver`, and a cancelled panel. Log line `📋 N chars on the
  clipboard — <why> (Q17)`; `GET /test/state.pasteboard` shows the write as `writer: walkie`.

## The held prompt

- **Hold for `minHold`–`maxHold`, scaled by word count** (the journal records 3–5 s; `AppDelegate` currently reads `minHold = 4.0`, `maxHold = 7.0` — the constants are the source of truth), behind a **Cancel** button bottom-right. → journal: *The prompt is held, not sent*
- **Stamps are m:ss from the moment the dictation opened, drawn on the frames** (`AppDelegate.shotStamps`, `RelayWindow.layoutShots`, since 2026-09-02) — a dark pill in the thumbnail's left corner, 10pt semibold monospaced digits. Wall-clock does not locate a moment *inside* the message. → journal: *The prompt is held, not sent*
- **The context screen is counted but not stamped**: `shotStamps` gives it an empty string, not a missing entry, so stamps stay index-aligned with the frames. → journal: *The prompt is held, not sent*
- **Count from `pendingScreen` + `pendingShotOffsets`, never from `attached`** — the screen travels in its own outbox field, so `attached` prints a total one lower than the `📸 ×N` he watched climb. The `🎙️ sent + N 📸` flash counts the same way. → journal: *The prompt is held, not sent*
- **Sample offsets at the gesture** (`plusOneShot`'s `takenAt`): `screencapture` returns a subprocess later, and a second of drift is a whole sentence. → journal: *The prompt is held, not sent*
- **Ordering is preserved**: a second dictation arriving mid-countdown releases the first before displaying itself. → journal: *The prompt is held, not sent*
- **Under Autosend, the pointer on the panel stops the clock** (2026-09-23, *"să se oprească din trimitere până când iau mouse-ul de pe el"*): `RelayWindow.syncHoverPause`, autosend only, and **leaving restarts the hold whole** — resumed, a hover begun at 0.9 s would send the instant he let go. Read from `panel.frame` vs `NSEvent.mouseLocation` on every hover edge and countdown tick, ignored for the 0.25 s unfold (the panel swells out of the cursor). The hint row says `⏸ Paused — ⏎ to send, ⎋ to cancel`; shot `prompt-autosend-paused`.

## The send flight

- **A plain white outline, from the panel onto the terminal, 0.55 s** (2026-09-23, evening). The destination terminal's own picture rode this flight for one morning (`BindFlight.windowPicture`, a window-id grab) and was taken out the same day — Victor: *"shouldn't be an image. It should just be a plain border because taking screenshots of the screen is not robust … Move from that panel into the terminal"*. The **spawn** flight is the same outline, from the panel to the new window (`outlined: true`, no `picturing:`); with no panel it grows out of the chip. Do not put a picture back on either.
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
- Do not write the outbox line before delivery, and do not let a held sentence replace another.

## The agent answers a dictated question beside the pointer (2026-10-07, `ReplyPanel`)

**Its name is the reply pop-up** (2026-10-08, Victor: *"Let's call it reply pop-up. Make sure we align
the terms on this"*) — not *answer panel*; logs say `💬 the reply pop-up's …`.

- **Name = in front, 📍 = bind** (2026-10-08, *"if I click the name … it's not rebind … it brings in
  front the wrong terminal … the new icon … next to the death face … would rebind me, but it only
  displays if I'm not already bound to that terminal … the [pin] that shows caret"*). A click on the
  name brings that terminal forward where it is (`ReplyPanel.onRaise` → `resolve(tty:)` →
  `bringToFront`), binds nothing. **📍** (`Glyphs.mapPin`, drawn) sits left of ☠️, only when Walkie is
  not bound to that tty (`ReplyPanel.isBound`); it binds with the border flight (`onBind` →
  `rebindFromMenu(fly:)`). The bullets below that say the name binds are superseded.
- **🔼 → over the pop-up answers its sender** (2026-10-09, Victor: *"If I do the gesture for … bound
  prompting while my mouse is over the tooltip with the reply … close the bubble … first rebind me to
  the sender terminal, just like if I would press the pin button … an easy way to chat back with the
  agent"*). `onForwardRight` at rest (nothing listening or recording) with the pointer over the pop-up
  (`ReplyPanel.ttyUnderPointer`, frame + 8 pt) → `AppDelegate.replyBack`: the pop-up closes, the 📍's
  bind runs (`rebindFromMenu(fly: true, then:)`; skipped when already bound to that tty) and the bound
  prompt opens once the bind lands. A sender gone → `⚠️ no terminal on …`, nothing opened.
  Mid-sentence the gesture keeps its flip. Log `💬 🔼 → over the reply pop-up — …`.
- **🔼 → over the pop-up dissolves it to the right** (2026-10-09, Victor: *"swipe to right, fade out,
  and then in the same time turn into pieces … something to suggest that I took my focus and send it
  to it"*; then, over a 9-column burst that flew 320 pt with spin: *"I don't want to make it an
  explosion, more of a dissolve effect, in smaller pieces"*). `ReplyPanel.shatter` renders the
  pop-up's layer into an image; `ReplyBurst` cuts it into 8 pt grains (pixel-snapped, no edge
  antialiasing — fractional edges drew a grid), each starting at its own moment (left edge first plus
  a random scatter, ≤ 0.3 s), easing in, drifting ≤ 70 pt right and a little up, shrinking to 0.3 and
  fading, 0.75 s in all. Timer-driven (`apply(u)`), so `REPLY_BURST_PNG=<dir> swift test --filter
  ReplyBurstTests` renders it at six moments. Only `replyBack` dissolves; ✕, ☠️, 📍 and the name still
  just close.
- **The wrong terminal came forward because AX's focused window was stale**: `raise(pid:)` raised
  `kAXFocusedWindow` right after AppleScript put the tab's window at index 1, which can still be the
  previous key window. `bringToFront` and `presentOnRetina` now answer the window's top-left and
  `raise(pid:windowAt:)` raises the AX window at that `kAXPosition` (focused one only when none matches;
  log `🪟 no window of pid … at (x, y)`).

Victor: *"when I am asking directly a question … the agent is able to reach me back … a bit of a
panel that appears next to the mouse carrying the response … super important to be brief"*, then
*"if my mouse doesn't move, that should don't start any timer … having an X icon in the corner for
me to dismiss it explicitly"*.

- **Only a prompt with a `?` asks for it** — `terminalLine` adds `AppDelegate.questionHint`,
  `[If I asked you a question, also run: walkie-reply "<the answer in ≤2 short sentences>" [--image <path> when a small picture says it better]. Only to answer me — never to ask me something, never to report work done.]`, after
  `[Dictated in RO or EN]`. Every other prompt pays nothing. **Narrowed 2026-10-08**: an agent
  answered *"E oare posibil?"* (a request) by doing it, then `walkie-reply "Gata: …"` — Victor: *"nu
  că au terminat … un pic abuz"*. Then, the same night: *"exclusiv când eu întreb ceva. Atât … Niciodată
  să nu fie folosit ca să mă întrebe Claude pe mine ceva"* — **only the answer to his question; never
  a question for him, never a completion notice.**
- **Every corner resizes it** (2026-10-09, Victor: *"make the dialog window … resizable by the right
  or left bottom corner? Actually all the corners … in case there's a longer response"*): a press
  within 12 pt of a corner (`ReplyRoot.Grip`, the system's diagonal resize cursor there — macOS 15's
  `NSCursor.frameResize`) is tracked by the window (`trackEvents`, the content is rebuilt at every
  step) and the opposite corner stays put; ≥ 240 × 90 pt. The size is kept while it is open
  (`userSize` — a streaming ⚡ answer too) and forgotten at the close. **Long answers scroll**: fitted,
  the words take ≤ 45 % of the screen's height; past what they are given they scroll (overlay
  scroller, the wheel works on the never-key panel, opened at the beginning — a text field is
  flipped). `maxChars` 400 → 4000. Desk: `POST /test/quick {"resize": {w, h}}`.
- **Pictures ride the answer** (2026-10-09, Victor: *"the reply bubble should be able to show
  images. As much as they fit that window, small, but when clicked, opened up"*):
  `walkie-reply "<answer>" --image <path>` (repeatable, ≤ 8; text optional with a picture) posts
  `images: [path]`; `ReplyPanel.keep` copies each readable one into
  `~/Library/Caches/ro.victorrentea.wispr-relay/replies/` (newest 100 kept), so a scratch file the
  agent deletes still opens. Under the words: one picture spans the width, ≤ 170 pt tall; several
  are one 72 pt row, aspect kept, cropped to fill, as many as fit, the last shown wearing `+N` for
  the rest (`thumbLayout`). A click opens it in Preview — the `+N` one opens itself and every
  hidden one; the pop-up stays; a press that moves drags it. `questionHint` mentions
  `[--image <path> when a small picture says it better]`.
- **`helpers/walkie-reply`** (linked into `~/.local/bin`, which is on the sessions' PATH; `~/bin` is
  not) posts `{token, text, from: <git toplevel basename>}` to `POST /reply` on 8917–8919. The token is
  `~/.walkie-talkie/reply-token` (0600, made at launch): the port answers any web page (CORS `*`) and
  no page can know it — a wrong token is a 403 and `⚠️ 💬 POST /reply refused`.
- **The panel**: **zooms in out of the pointer** (2026-10-08 afternoon, Victor: *"should not swipe in from the bottom, but zoom in … from small to its final size, by also increasing in opacity"* — the toast rising from the screen's bottom lived one build): scale 0.3 → 1 and alpha 0 → 1 over 0.3 s, ease-out cubic, no overshoot, around the edge's centre nearest the pointer; sitting **centred on the pointer's x, its top edge 14 pt under the pointer** (above it when there is no room) — below-right until that day; does not follow,
  `sharingType = .none`, ≤ 400 chars, header: the walkie icon, then `<folder> — <task from the tab title>` (else `<folder> · <tty>`; `walkie-reply` sends the tty of its first ancestor that has one). **The name is a link**: hand cursor + underline on hover, a click binds that terminal (`rebindFromMenu`, from "the answer panel", `fly: true` — bound, brought forward, and **its window's outline flies into the chip**, the mouse bind's receipt, outlined), **and closes the panel** (2026-10-08: *"it did not close the window. Should have"*). The header is the body's 15 pt (semibold, 60 % white), one line, `…` at the end. **The walkie (26 pt, 2026-10-08) is the other click**: hand cursor, and a click puts that terminal in front **centred on the Retina, at once, no flight** (`TerminalBinding.presentOnRetina` — size kept, shrunk to the visible frame; lid closed → the pointer's screen), closes the panel, **binds nothing** (Victor: *"pop in front … on the retina in the center of the screen … with no animation"*; log `💬 the answer's walkie clicked`). **It stays until the ✕** (drawn, as large as the walkie since 2026-10-08,
  first-mouse) or a click on the name — no clock, no bar**. **A newer answer queues behind it** and comes up at the pointer once it is closed (2026-10-08: *"să nu apară una peste alta … pe rând, stau la coadă"*); log `… queued behind the open one — N waiting` (Victor: *"NO PROGRESSBAR. i have to manually
  dismiss it"*; a countdown that started when the pointer moved lived for one build). Log `💬 answer
  from <from> — N chars; up until the ✕`, `💬 answer dismissed (✕)`.
- **☠️ left of the ✕ = kamikaze to that session** (2026-10-08, Victor: *"to the left of the X … an
  emoji with a skull … with a click, it sends kamikaze back to the session that sent this message"*):
  shown only when the answer names a tty; closes the panel, `TerminalBinding.resolve(tty:)` (bind's
  lookup without the binding) → `sendKamikaze` — the shell guard still stands; no tab → `kamikazeNotSent`.
  Log `💬 the answer's ☠️ clicked`, `☠️ kamikaze — sent from the answer panel to ttysNNN`.
- **The panel is a surface, not a document** (2026-10-08, *"drag the little window … by clicking on the
  text and the text shouldn't be selectable"*): the words are an `InertLabel` (not selectable, no hit),
  a press anywhere off the four clickables is `performDrag`; `ReplyRoot` sets the **arrow** over the
  panel (*"the mouse has the icon from what's underneath"* — Chrome's I-beam won through), leaving
  the hand to the walkie, the name, ☠️ and ✕ (`ReplyRoot.hot`). **The clickables drag too** (same day, *"anything as long as I
  don't click it but drag it"*): a press that moves past 3 pt drags the panel and clicks nothing
  (`PressOrDrag`). **The name's label is never hit** — `ReplyRoot.link` takes its press (click or
  drag); the `NSTextField` with mouse overrides did not move the panel (*"even if I drag on the title"*).

## ⚡ Quick question (2026-10-09, `QuickAsk`)

Victor: *"a dumb mode or a quick fast mode to this walkie-talkie that will answer as fast as it
can"*, on his subscription; *"the key to bind it to. I think forward and left"*.

- **🔼 ← at rest opens it** (`onLocalCancel`): only when `cancelSentenceOrPanel` found nothing to
  cancel and no answer is coming (`QuickAsk.cancel`, which 🔼 ← also does). It is a **clean**
  sentence (`startDictation(paste: true, clean: true, quick: true)` — words only, no picture, no
  attachment) whose `deliver` sends the words to `askQuick` **before** any caret or terminal route:
  nothing is typed anywhere, no outbox line, the question goes on the clipboard (Q17),
  `lastDelivery.to = "quick"`. The chip's destination row says `⚡ quick answer — opus`.
  `quickAsk` is an `Envelope` field.
- **The answer streams into the reply pop-up** (`ReplyPanel.live`), header `⚡ <the question>` so
  he sees what was heard, no tty, so only the ✕. It opens at once — an agent's open pop-up steps
  back to the head of the queue, a finished ⚡ one is replaced — and rewrites in place, top edge
  fixed, ≤ 20 repaints a second. ✕ while it is coming drops the rest (`dismissedLive`).
- **One pre-started `claude -p` per question** (stream-json in and out), replaced the moment it has
  answered, started at launch: Victor, *"a conversation history over the day … will make it slower
  after a while"*. Lean: its own system prompt (≤ 3 short sentences, plain text, the question's
  language, mind the recognition mistakes), `--tools ""`, `--strict-mcp-config`,
  `--setting-sources ""`, cwd `~/.walkie-talkie/quick/`. `WT_QUICK_MODEL` (default `opus` since 2026-10-10, was `haiku`) and
  `WT_QUICK_EFFORT` (`low`), env or `elevenlabs.env`. `--bare` loses the subscription login. 45 s
  timeout; an idle process that dies is restarted, three times at most.
- **Measured** (`evals/quick-ask/`): in the app, first word **0.55 s** median, whole answer
  **1.03 s**; a cold `claude -p` 1.40 / 2.51 s; warm with Claude Code's own ~104k-token prompt
  1.52 / 3.15 s. Opus warm and lean reaches its first word as fast (0.58 s), finishes 0.5 s later.
- **Desk route:** `POST /test/quick {"text", "wait": true}` → `{answer, error, firstWordMs, totalMs,
  model}`; **`wait: "all"`** also waits for the checks → `web` and `review` (the 🔎 and 🧐 answers), `shown` (the pop-up's words).
  Log: `⚡ quick answer (Opus 5.5) — first word 0.73 s, whole 1.39 s, N chars`.
- **Opus, signed, then answered again twice** (2026-10-10, Victor: *"n-aș putea folosi ceva mai
  inteligent decât Haiku … un răspuns imediat, apoi unul căutat, apoi unul criticat … în funcție de
  cât timp îl las"*). **Each stage writes the whole answer again and replaces the one before**, so
  the ✕ at any moment leaves a complete answer: ⚡ from memory → 🔎 searched (corrected/completed,
  each claim with an inline exact quote „…" [n], `[n] site — url` lines, `✏️ what changed` when it
  did) → 🧐 reviewed (an adversarial reviewer that opens the cited pages, checks every quote is
  there and means what is claimed, and writes it again fixed, same format). Footer:
  `— Opus 5.5 · ⚡ from memory` / `· 🔎 searched` / `· 🔎 searched · 🧐 reviewed`, and under it
  what is running (`🔎 Searching the internet…`, `🧐 Reviewing the quotes…`); a failed stage
  shows `⚠️ why` there and keeps the last good answer. A stage's words are not streamed, only its
  finished answer. Each check is its own lean `claude -p` with `--tools/--allowedTools
  WebSearch,WebFetch` (`QuickAsk.webPrompt`, `reviewPrompt`, `citeFormat`), started while the stage
  before it runs; 120 s each. **The ✕ — or 🔼 ← — stops everything** (`ReplyPanel.onLiveDismissed`
  → `QuickAsk.cancel`); the pop-up stays `liveOpen` until the review is done. Measured: answer
  ~2 s, 🔎 at ~11–19 s, 🧐 at ~20–29 s.
