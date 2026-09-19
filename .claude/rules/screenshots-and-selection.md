---
paths:
  - "Sources/WalkieTalkie/ScreenCapture.swift"
  - "Sources/WalkieTalkie/CaptureFlash.swift"
  - "Sources/WalkieTalkie/CaptureEffects.swift"
  - "Sources/WalkieTalkie/CursorMarker.swift"
  - "Sources/WalkieTalkie/WindowContext.swift"
  - "Sources/WalkieTalkie/SelectionCapture.swift"
  - "docs/pointer-line.md"
  - "evals/**"
---

# Screenshots and the selection

Covers the shutter: what a shot is named, what travels to the agent, the on-screen confirmation, where files live, and how the highlighted text is read (shutter and watcher). Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## The shot's name (2026-09-19 — it says the number, and nothing else)

- **`screenshot-3-original.jpg`, `screenshot-3-800px.jpg`, and for a drag `screenshot-3.jpg`** (the region, unscaled). The digit is the picture's place in this dictation — 0 is the automatic context frame — and it is the same digit the sentence's token says (`📸3`). `ScreenCapture.stem` writes it, `ScreenCapture.number(of:)` reads it back, `sibling(of:)` computes the other two names from it. → journal: *The envelope becomes tokens where he made them (2026-09-19)*
- **Everything the name used to carry is a token in the words now** — the offset, the pointer (`[📸1🖱️@1000:800]`) and the dragged rectangle (`[📸3✂️900,345→2594,574]`). Said once, where he said it, instead of twice in two notations. The bullets below describe the *old* name and are kept for the reasoning; the later date wins on the shape.
- **The number is reserved at the gesture and is unconditional** (`AppDelegate.reservePicture`): two presses a third of a second apart can finish in the other order, and the name needs a number whether or not a marker can be placed. The cue is the optional half (`cueLocked`).
- **The disambiguating `-2` goes on the base, before the suffix** (`uniqueBase`): every dictation in a session folder produces a `screenshot-0`, and a `screenshot-0-original-2.jpg` would take its siblings into names nothing can compute.

## The shot's name (before 2026-09-19)

- **Name a shot by offset and pointer, in image pixels.** `shot-01:23(mouse-at-1034x1466px).jpg` — 1m23s into the dictation, pointer at x=1034, y=1466 in *the pixels of that image*, top-left origin (`ScreenCapture.stem` + `tagCursor`). Both facts ride in the name because the path already travels in `paths`; nothing downstream learns a new key. → journal: *The shot's name is *when in the sentence* and *where the mouse was**
- **`00:00` is the automatic context shot, by definition.** A shot with no dictation around it keeps a timestamp instead: "elapsed since the start" of nothing is not a fact. → journal: *The shot's name is *when in the sentence* and *where the mouse was**
- **The colon is legal; the Finder lies about it.** APFS takes `:` and every path handler is POSIX, but the Finder renders it as `/` (`shot-00/00(…)`), so a folder Victor opens by hand reads differently from what the agent sees. → journal: *The shot's name is *when in the sentence* and *where the mouse was**
- **Pixels, without a denominator.** It was a percentage pair (`-cursor-34.2x71.8pct`), then briefly `-cursor-at-1034x1466-of-3024x1890`; Victor dropped the denominator because raw pixels are what he can check against a screen. The consequence is accepted: a downsampled frame needs its own dimensions read back before these numbers mean anything. Do not reintroduce the denominator without asking. → journal: *The shot's name is *when in the sentence* and *where the mouse was**
- **Measure the size off the JPEG header, never compute it from the screen.** `pixelSize(of:)` after `screencapture` returns (no decode); frame × backing scale is a guess that mirrored displays, HiDPI modes and a sleeping external monitor all break. Hence the shot is **named provisionally and renamed afterwards**; a failed rename leaves the provisional name — a shot with no pointer in its name is still a shot. → journal: *The shot's name is *when in the sentence* and *where the mouse was**
- **Do not port Victor Addons' convention onto this one, or the reverse.** Its `2026-08-14_00-34-42_at1200x500.jpg` is in **global CG points** (y down from the primary display's top, negatives normal on a screen to the left) answering "where on the desk"; this one is in **pixels of that image** answering "where in this picture do I look". → journal: *The shot's name is *when in the sentence* and *where the mouse was**

## What travels: the 800 px copy

- **Every capture writes two files; the `-small.jpg` is what travels.** The original as `screencapture` produced it, and a sibling at `ScreenCapture.handoverWidth` (800) wide, used by `ScreenCapture.handover` / `AppDelegate.shotsClause`. The retina original is what Victor opens himself. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **An *area* frame writes three** (2026-09-19): the display, its 800 px copy, and `-zoom.jpg`, the dragged rectangle cut out of that frame **unscaled**. Rules and reasoning in `area-crop.md`, *The file and the envelope*. It does not contradict the 0.87 bullet below — that one is a crop at the **pointer**, added to every shutter shot with no box drawn; this is the region he framed himself, and `evals/pointing-proof/` measured 21/28 without it against 15/16 with it. → journal: *The region he framed travels at its own size (2026-09-19)*
- **Tokens are in the pixels, not in the JPEG bytes.** An image costs `width × height / 750` tokens once the reading tool has fitted it to 2000 px on the long edge, so a 3456×2234 desktop always lands at ~3450 tokens whatever the JPEG weighs — compressing harder buys nothing. At 1000 px ~860, at 800 px ~550. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **That the small copy is free was measured, not assumed** (`evals/`, 39 runs over two real dictations replayed off the outbox): seven-frame Gmail dictation, accuracy 0.95 either way, 29,349 tokens against 48,350, $0.38 against $0.56; on the "what was I pointing at" fixture the small frames produced byte-identical answers. `evals/text-vs-pixels.md` (2026-08-22, 33 runs) walked the ladder: 6/6 clean at 800, 6/6 at 700, no legibility failure even at 500 px. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **800 is deliberately one rung above what the evidence allows.** 700 is where the measurement points (−51 % a frame instead of −36 %), but three repeats a cell is thin and Victor reads these frames too. Do not take the rest of the saving without a harder fixture — the missing rung is the one that would find a cliff in production instead of in `evals/`. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **Say the width in one place.** `ScreenCapture.handoverWidth` is not private and `AppDelegate.shotsClause` interpolates it; a second literal is how the shipped sentence comes to disagree with the pixels. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **Scale through ImageIO's thumbnail path** (scales during the JPEG decode). The burned-in cursor mark was removed from this path partly because it cost ~100 ms of exactly the decode-and-re-encode this avoids. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **`prune()` counts frames, not files**, and drops the sibling with its frame; counting both would silently halve a cap expressed in pictures. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **The pointer line was measured and deliberately not built.** OCR at the recorded cursor, quoted in the shots clause, held accuracy at 1.00, cut the agent's turns from 12 to 5 and thinking from 3,109 to 1,323 output tokens, one run in three answering without opening a picture. Not here because Victor chose to keep the shutter path short. Read `docs/pointer-line.md` before either building it or re-deriving it. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **Order, not timestamps.** The name carries where in the sentence and where the pointer was; the line says the list is oldest first. That was enough for 7-item alignment at 0.95. → journal: *The agent gets an 800px copy, Victor keeps the retina frame*
- **`$WALKIE_SHOTS` is a real variable, exported from `~/.zshrc`, not a placeholder.** `AppDelegate.shotsRootAbbreviated` writes the shots root that way and the shell the envelope is pasted into expands it; the app cannot set it, because the terminal was running before the relay bound to it. Do not "fix" it back to an absolute path — and on a fresh machine, add the export or the agent cannot open a single frame. → journal: *The shots clause becomes a list, and the folder becomes $WALKIE_SHOTS (2026-09-13)*
- **The clause is a `- ` list with the title in `'…'`**, not a `; `-joined sentence with `= title` (through 2026-09-12). Window titles carry their own punctuation; the line break and the quotes are what a title cannot forge. `evals/variants.py` deliberately still renders the old shape — its fixtures live in a temp dir where the variable resolves to nothing. → journal: *The shots clause becomes a list, and the folder becomes $WALKIE_SHOTS (2026-09-13)*

### Three things that sound like improvements and are not

- **Compacting the line saves nothing.** Factoring the directory out of seven paths (~90 characters a frame) measured *inside the noise* — 50,320 tokens against 48,350, i.e. slightly worse. The compact form was kept anyway for what it **says**, not what it saves: that the list is chronological and that the context frame may be skipped. Do not go looking for tokens in the wording again; they are in the pixels. → journal: *Three things that sound like improvements and are not*
- **Dropping the automatic context frame costs accuracy** (0.93 against 0.95). It is not a spare. He starts talking about what is *already on his screen*, so it is routinely **picture one of the enumeration** — in the Gmail dictation it is the first of the seven senders. It is offered cheaply with a hint that it can be skipped, never withheld. → journal: *Three things that sound like improvements and are not*
- **A native-resolution crop at the pointer, offered beside the small frame, scored 0.87** — worse than the small frame alone. Not because the crop is unreadable: because two pictures per shot make the **sequence** harder to hold, and one run came back with the first two shots swapped. Sequence is what these messages are made of. → journal: *Three things that sound like improvements and are not*

## Every frame says which window

- **Read the frontmost app and focused window title with `WindowContext.describe()` and name it beside the file in the line** (`shot-00:31(…)-small.jpg = Google Chrome — Gmail – Inbox (24,277)`). One Accessibility call replaces several hundred tokens of looking, and answers what pixels answer worst: two frames of the same IDE at the same zoom are two different files. → journal: *Every frame says which window it came from*
- **Sample it at the gesture, never inside the capture.** `screencapture` is a subprocess we wait on; a title read after it returns names the window he *ended up* in front of. Same rule as the cursor and the offset. → journal: *Every frame says which window it came from*
- **It goes in the line and the outbox, never in the file name.** A window title is arbitrary text with `/`, quotes, colons and eighty characters of headline; sanitising it strips exactly the characters that identify the page. In the outbox it is `sources`, keyed by **base name** (the folder is already in `paths` and `screen`). Truncated from the head at 80 characters (`fitHead`): a title puts its subject first. → journal: *Every frame says which window it came from*
- **The AX read is duplicated from `TerminalBinding.focusedWindow` on purpose.** That one is about binding (resolves a target, answers with a frame to fly a rectangle from); folding provenance into it would tie two unrelated features to one signature. → journal: *Every frame says which window it came from*
- **`NSWorkspace.frontmostApplication` is a main-thread question; the hop is `main.sync` guarded by `Thread.isMainThread`.** Every caller is an event tap, a CoreAudio callback or an HTTP listener, and a deadlock in the shutter path is not a bug anyone would enjoy finding later. → journal: *Every frame says which window it came from*

## Capture order and the on-screen mark

- **Flash first.** `CaptureFlash.announce()` at the top of `captureContext` / `plusOneShot`, before the selection probe and before `screencapture`, with the slow work on a background queue. Fired from inside `ScreenCapture.grab` it landed after a clipboard probe that sleeps up to 400 ms and a subprocess — a receipt that far behind the gesture no longer says *now*. Its panel is `sharingType = .none`, so firing first cannot put it in the shot. → journal: *Capture order: flash first*
- **The cursor mark is on the screen, never in the picture.** `CaptureFlash.markCursor` drops the red target on the desktop for ~2 s on the automatic capture and every back-button shot (both via `announce(cursor:)`). **`CursorMarker` no longer touches the file**: a mark painted into the frame covers the thing being pointed at, an agent cannot know the red circle is not UI, and the burn-in was a second JPEG pass (~100 ms; at quality 1.0 the file came back *larger*). Verified: zero `systemRed` pixels in a 312×312 box around the recorded position, against 949 before. → journal: *The cursor mark is on the screen, never in the picture*
- **The mark blooms: 0.5× → 3.6×, fading 0.5 → 0, inside half a second** (2026-08-29), and turns a quarter as it does (2026-08-31; the mark is four-fold symmetric, so 90° lands on its own drawing). Scale and rotation travel as **one animation on `transform`**, not `transform.scale` beside `transform.rotation.z` — two animations each rebuild the matrix from the model value and overwrite instead of composing. It runs −90° to 0 so the resting transform stays the plain scale. → journal: *The cursor mark is on the screen, never in the picture*
- **Size the panel to the mark at its largest**, or the bloom is clipped by its own window a third of the way out. → journal: *The cursor mark is on the screen, never in the picture*
- **`sharingType = .none`, so it cannot be verified with a screenshot** — the only checks are the drawing itself and Victor's eyes. That the *file* is clean is the checkable half. → journal: *The cursor mark is on the screen, never in the picture*
- **The 🔴 pulses 1.0 → 0.25 and back, 1.1 s each way — slow on purpose.** Anything brisker is something blinking next to the cursor while he is trying to think. Only the dot animates; the count must stay readable at every instant. → journal: *The cursor mark is on the screen, never in the picture*

## Where shots live

- **Shots go to `~/Library/Caches/ro.victorrentea.wispr-relay/shots/<session-stamp>/`; `--home` does not move them** (it still moves the outbox). Caches is a staging area, never an archive: each retina JPG is a megabyte or two and macOS may purge it under disk pressure — welcome. `/tmp` clears on reboot and a 3-day sweep, neither of which is "when the disk is full". The outbox stays in `~/.walkie-talkie`: a log the system may delete is not a log. → journal: *Shots live in Caches, one folder per relay session*
- **The pre-Caches pile goes to the Trash on launch, not to `rm`** (`Outbox.retireLegacyShots`). `prune()` walks `cacheRoot` only, so the 300 cap never applied to `~/.walkie-talkie/shots` — 382 MB in 209 retina JPGs when measured. Old outbox lines still name those files; they go when he empties the Trash. → journal: *Shots live in Caches, one folder per relay session*
- **The per-session folder is what makes the names safe.** Every session produces `shot-00:00(…)` again; the pointer position separates same-offset shots in almost every real case and `unique()` appends `-2` for the rest — "dictate twice without moving the mouse" is not exotic. → journal: *Shots live in Caches, one folder per relay session*
- **`prune()` keeps the newest 300 across all session folders**, not per folder — a per-folder cap would keep 300 per restart and bound nothing. Emptied session folders are removed; the current one never is. → journal: *Shots live in Caches, one folder per relay session*
- **Sample the position at the gesture and carry it into `ScreenCapture.grab(cursor:)`; never read it inside.** By the time the capture runs — a clipboard probe and a subprocess later — the hand has moved on. → journal: *Shots live in Caches, one folder per relay session*

## The selection: shutter

- **The shutter files what is highlighted at that moment, stamped with its offset** (`stashExtraSelection`, into `pendingExtraSelections`). `pendingSelection` is unchanged: the subject, frozen at the first non-empty read, never overwritten. Three cases are skipped as noise: nothing highlighted; the same text the frozen slot holds (the common case); the same text as the previous extra. Exception: a dictation that opened with nothing highlighted takes the first mid-sentence highlight into the frozen slot — the subject arriving late. → journal: *The shutter also takes the selection*
- **The shutter reads with `SelectionCapture.read()`: Accessibility, then a synthetic ⌘C with the clipboard snapshotted and restored.** It was AX-only (`readQuiet`) until 2026-08-31 and the result was that the feature did not work where he actually uses it: a highlight in a Chrome *page* is exactly the case AX cannot see, so every shot over one filed nothing, silently. The ⌘C is a price he asked to pay; with nothing selected the probe is a no-op. → journal: *The shutter also takes the selection*
- **Extras ride the outbox as `selections`** (`[{at: "0:31", seconds: 31, text: …, in: "<window>"}]`) while `selection` keeps carrying the first one, so nothing reading the queue has to learn a key. `at` keeps the `m:ss` it shipped with and `seconds`/`in` were added on 2026-09-13. → journal: *The shutter also takes the selection*
- **`fileSelection(announceOnRepeat:)` is shared with the watcher.** A **press** that found a highlight already carried still earns the `“ selecting …` receipt (a shutter that says nothing reads as one that missed); a **poll** that finds the same text has found nothing. The chip shows the words for four seconds, then `“ ×N`. → journal: *The shutter also takes the selection*

## The selection: watcher (2026-09-09)

- **While a dictation runs, the highlight is read on a 1 s tick with `SelectionCapture.readQuiet` — Accessibility only, never ⌘C.** `AppDelegate.pollSelection`. A synthetic ⌘C once a second, all sentence, would fight his own copying, spend 400 ms of pasteboard wait per tick, and race its own clipboard restore. **A Chrome page therefore remains the shutter's job** (⌘⇧-click is the better answer there anyway). → journal: *A highlight is picked up on its own (2026-09-09)*
- **File only after three identical reads in a row** — *"3 selecții identice = m-am oprit"*. Dragging grows a selection (`Hel`, `Hello wor`, `Hello world`); filing the first thing seen puts a fragment in the message *and* the whole line beside it. The tick is one second (*"pune 1s în loc de 0,6, să nu fie grabă"*; it shipped at 0.6 for an hour). → journal: *A highlight is picked up on its own (2026-09-09)*
- **Stamp when first seen, not when confirmed.** Measured: a ⌘A two seconds into a dictation comes out `0:02`, not `0:04`. → journal: *A highlight is picked up on its own (2026-09-09)*
- **One final read when the microphone closes, with no settling** (`finalSelectionRead`, posted to the same serial queue so it lands after any read in flight). A highlight made in the last two seconds never gets its three reads, and that is precisely when he selects the thing he just described. `polledSeen` still applies. `/test/dictation` makes the same call with the send hung off it, so the close-only path is reachable from a desk. → journal: *A highlight is picked up on its own (2026-09-09)*
- **`polledSeen` is a set, not a last-value check** — once each per dictation; going back to something selected earlier is not a second entry. Losing the highlight clears what was settling, so re-selecting the same text must settle again. → journal: *A highlight is picked up on its own (2026-09-09)*
- **Half a second of AX messaging timeout** on both the system-wide element and the focused one; the default allowance is seconds and an app mid-beachball would stall the queue. A serial `DispatchQueue` is the other half: a read that outran its interval delays the next instead of overlapping. → journal: *A highlight is picked up on its own (2026-09-09)*
- **Drive it from `syncBorrowedGestures` (bare `live`, Replace Wispr included) and log both edges** (`👁 selection watcher on/off`) — *"why did it not pick up my selection"* has to be answerable from the log. → journal: *A highlight is picked up on its own (2026-09-09)*

## The selection in the envelope: one stamped list (2026-09-13)

- **Every highlight is one `- ` line, in the shots clause's shape**, under `text selected during dictation:` — `- 00:08 in 'Terminal — ✳ walkie-talkie': "…"`. `AppDelegate.selectionsClause`, shared by `terminalLine` and `caretLine`. The two pre-2026-09-13 shapes (`[selected: …]` for the subject, `[selected 0:31: …]` per extra) are gone; do not put either back. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **The frozen selection is line one of that list, not a clause of its own**, and it carries an offset like the rest (`pendingSelectionAt`, `Message.selectionAt`, outbox `selectionAt`). It is `00:00` in the ordinary case and is *not* zero for the one case the old shape could not express: a dictation that opened with nothing highlighted, where the subject arrives mid-sentence through `fillsTheBlank`. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **The window is read when the highlight is filed, never at delivery** (`WindowContext.describe()` in `fileSelection`; outbox `selectionIn` / `selections[].in`). The envelope is built seconds later behind the held panel, and a title read then names the window he ended up in front of — the same rule the shot's own window reading follows. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **Read it *before* `stateLock` is taken, never under it.** `WindowContext` hops to the main queue and waits there; everything that publishes to the chip takes `stateLock` *from* the main queue. The two together are a deadlock with a highlight on one side of it. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **`mm:ss` in the envelope, `m:ss` on the chip, one calculation** (`AppDelegate.clock(_:pad:)`, with `stamp` and `envelopeStamp` over it). The envelope already carries a clock — every frame is named `shot-00:05(…)` — and a highlight reading `0:05` beside a frame reading `00:05` is two readings to reconcile; the chip is a few characters wide beside the cursor and cannot spend the column. Never fork the arithmetic. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*
- **`POST /test/selection {"text": …}` files a highlight as though he had made one**, entering at `fileSelection` so the offset, the window reading, the frozen-slot rule and the *already carried* skip all run. It fakes the **reading** and nothing else — it is the only desk-reachable route into the one attachment that is read off the screen. `evals/test_envelope.py` is what it exists for. → journal: *Every selection and every pick says when, and a pick says what it said (2026-09-13)*

## The highlight lands *inside* the sentence (2026-09-14)

- **Every highlight filed mid-dictation is announced to the recogniser as `selected text N`, and
  the words replace the marker at delivery.** The sentence comes back with the paragraph quoted
  where he said it instead of a line under it he has to align by its `mm:ss`. The mechanism, the
  vocabulary and the costs are `ShotMarker`'s — read `.claude/rules/dictation-source.md`, *The
  second kind*. → journal: *The highlight lands inside the sentence (2026-09-14)*
- **The list under the words is the fallback, and it is chosen by the absence of the marker.** A
  highlight whose marker was found is left out of `selectionsClause`; a highlight whose marker was
  lost — masked by continuous speech, filed after the microphone closed, past the tenth — keeps the
  line it always had. Victor: *"în cazul în care markerul nu este detectat în textul transcris, pui
  transcripția ca acum, la final"*. → journal: *The highlight lands inside the sentence (2026-09-14)*
- **Inline text is clamped at the same 400 characters the clause clamps at** (`clampForTerminal`),
  and the outbox still carries the whole of it, plus `selections[].marker` and
  `selections[].inlined` — the one place *why is this highlight not under the sentence* is
  answerable after the fact. → journal: *The highlight lands inside the sentence (2026-09-14)*

## Nothing this app draws is in the picture, and a test says so (2026-09-14)

- **The lightning ring, the drop arrow and the tap ripple are already invisible to every capture**
  — `sharingType = .none` on every panel, re-measured the day Victor asked for them to be hidden
  during the shutter: a control panel at `.readOnly` comes back in the frame and the same panel at
  `.none` does not (`screencapture -x -D`, both displays, macOS 15.7), every window this process
  owns reports `kCGWindowSharingState == 0`, and two real mid-dictation frames have no gold annulus
  at the recorded pointer. **Do not add a hide-and-restore around the capture**: it buys nothing and
  costs a blink of his own UI at the moment the shutter's confirmation is supposed to be drawn.
  → journal: *Nothing this app draws is in the picture (2026-09-14)*
- **`evals/test_capture_decorations.py` is the guard** — it counts the windows each file makes
  against the `sharingType` lines it sets, and `--self-test` proves it fails on a bare panel. A
  guarantee nobody can see is one that lapses silently. → journal: *Nothing this app draws is in the picture (2026-09-14)*
- **`evals/capture-proof/` is the same claim measured on files**, including the film — `ScreenFilm`
  takes its frames with `CGDisplayCreateImage`, a different capture client from
  `/usr/sbin/screencapture`, and until 2026-09-19 the flag had never been checked on that path. It
  holds: four scenes, bound and unbound, **0 ring / chevron / cursor-mark pixels** in a 1200 px box
  around the pointer, and the app's own shot differs from a control frame taken with nothing open
  in **0.0% of its pixels, 0 regions**. Re-run it after anything that moves a panel or the capture
  order; it needs the installed app on 8917. → journal: *The pictures are clean, and it is a
  measurement now (2026-09-19)*
- **What *is* in his frames comes from the other two apps.** Victor Addons and Victor Effects set no
  sharing type anywhere, so the hands-off 🔒 corners, the amber frame, the banners and any effect
  playing from the tablet do land in these pictures. That is deliberate there — an effect nobody can
  screen-share is an effect that is not on the projector — and changing it is a decision for those
  repos, not this one. → journal: *Nothing this app draws is in the picture (2026-09-14)*

## The selection: frozen, and not outliving the dictation

- **No *unconditional* probe at the gesture — reverted the same day it shipped** (2026-09-16). `stashSelection` briefly stashed whatever was already highlighted as the subject, on every destination, and is deleted. Victor: *"să nu mai preia automat selecția la începutul dictării, pentru că deseori rămâne selectat textul care nu are treabă cu ce am spus. Să preia doar textul selectat în timpul dictării."* A highlight left over from something else is not the subject just because it is still on screen.
- **…but a highlight he made five seconds ago is** (2026-09-18). `AppDelegate.probeRecentSelection`, from `dictationBegan`: the probe is back, gated not on what is on screen but on **when he selected it**. `HotkeyTap.secondsSinceSelectionGesture` against `recentSelectionSeconds` (**5**, his number: *"more than let's say ten seconds ago or five seconds ago, five, then not to pick selection"*). A stale highlight leaves no stamp and is exactly as invisible as it has been since 2026-09-16.
- **The recency is measured, never polled.** Three gestures stamp `HotkeyTap.lastSelectionGestureAt`, all in code that already runs on every event: a **left-button release after a >4 pt drag** (already computed for `onSelectionDragEnded`, stamped *above* its `dictating` gate), a **left-up with `mouseEventClickState ≥ 2`** (double/triple click, which selects without moving and so fails the slop test), and **⇧ + arrow / Home / End / Page**, or **⌘A**, on the `keyDown` path. Cost while idle: nothing — no timer, no thread, no AX call.
- **Do not replace it with `AXObserver` / `kAXSelectedTextChangedNotification`.** It is the textbook push answer and it is worse on all three axes: an observer per pid, re-registered on every app switch; a callback on plain **caret moves** in most text views, i.e. once per keystroke all day; and the same blind spot `readQuiet` has — IntelliJ's editor, WhatsApp and Chrome page content do not answer `AXSelectedText`, so they never post the notification either.
- **The probe reads loud (`read()`, ⌘C fallback), on `selectionQueue`, on every destination including the caret.** The stamp has already proved he made the gesture with his own hand, which is the deliberateness the shutter and the drag-release probe pay their ⌘C under; `readQuiet()` alone would miss precisely IntelliJ and WhatsApp, the 2026-09-14 complaint. Nothing waits on the 400 ms — the selection is not read again until the envelope is built.
- **The drag stamp's one false positive is accepted and named:** it says *a drag happened*, not *text was selected*, so dragging a window, a file or a scrollbar within five seconds of starting a dictation can still pick up a stale highlight. The double-click and ⇧-arrow stamps cannot. It is the 2026-09-16 complaint at a small fraction of its old rate, not its elimination.
- **`polledSeen` is reset by `resetPolledForDictation`, not by the watcher's seeding assignment** (2026-09-18). The seed used to be both the reset and the seed (`polledSeen = readQuiet().map { [$0] } ?? []`), which breaks the moment anything else on `selectionQueue` files a highlight before the watcher arms: the assignment drops what the gesture probe just took, and the watcher files the same text again three ticks later — second marker, second line in the envelope, second chip receipt. The reset is keyed to `dictationStartedAt`, so whichever of the probe and the seed reaches the queue first performs it and the other adds to what it found; the seed now **inserts**.
- **The first non-empty read still wins for the whole dictation — it is just never taken at the gesture any more.** `fileSelection`'s `fillsTheBlank` rule (only writes `pendingSelection` while it is still nil) is now the *only* way the slot is filled; `captureContext` still clears it only when a *new* dictation opens. Later probes exist only to fill a blank the first one left.
- **The watcher is seeded with the baseline highlight, or it silently reintroduces the same bug.** `syncSelectionWatch` reads whatever is selected the moment it arms and puts it straight into `polledSeen` (`SelectionCapture.readQuiet()`, off the caller's thread). Without this, a stale highlight held unchanged for `selectionSettleReads` polls "settles" and gets filed exactly as if it had been grabbed at the gesture — the watcher's own 1 s tick would have re-created the complaint on its own. Only a highlight that *changes* during the sentence is ever filed by the poll or the drag-release probe now.
- **Cancel must call `overlay.clearSelection()`** (2026-09-04). `cancelLocalRecording` cleared `pendingSelection` under the lock, but the row is the overlay's own copy and the `🗑️ Cancelled` flash draws *over* the chip; the last highlight sat beside the cursor with no dictation behind it. → journal: *…but it must not outlive it (2026-09-04)*
- **Probes capture `dictationStartedAt` before probing and drop the result if it changed.** `read()`'s ⌘C polls the pasteboard up to 400 ms; the wheel held through those 400 ms is a cancel, and the probe wrote everything the cancel had cleared straight back — a `pendingSelection` riding the *next* sentence. Nil means the sentence ended, a different instant means a new one began; both `fileSelection` and `stashExtraSelection` check. → journal: *…but it must not outlive it (2026-09-04)*

## Do not

- Do not reintroduce the denominator without asking.
- Do not widen the gesture probe back to *whatever is highlighted* — the recency stamp is the whole of why it is allowed back (2026-09-18).
- Do not swap the gesture stamp for an `AXObserver`; it costs more and sees less.
- Do not make the watcher's seed assign to `polledSeen` again.
- Do not port either convention onto the other (image pixels here, global CG points in Victor Addons).
- Do not take the rest of the saving without a harder fixture.
- Do not go looking for tokens in the wording again; they are in the pixels.
- Do not put `[selected: …]` / `[selected 0:31: …]` back, and do not fork the stamp arithmetic between the chip and the envelope.
- Do not call `WindowContext.describe()` while holding `stateLock`.
- Do not hide the overlay's own decorations around a capture — they are not in it (`sharingType`).
- Read `docs/pointer-line.md` before either building the pointer line or re-deriving it.
