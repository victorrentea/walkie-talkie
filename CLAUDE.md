# Wispr Relay — working notes

See `README.md` for what this is and how it works. This file is for rules that
must survive across sessions.

## UI language: English only

**Every string the app renders on screen is in English** — the title, the hint
legend, flash messages, error banners. No Romanian in the UI, ever, even though
Victor dictates in Romanian and these notes discuss it in Romanian.

Why: the overlay is on screen during workshops, in front of an international
audience and often mirrored to a projector. A Romanian label is noise to the room
at best and a distraction at worst.

This applies only to what is *rendered*. Log lines, comments and commit messages
are unaffected, and the dictation content itself is obviously whatever language
he spoke.

Current strings live in `RelayWindow.swift`:
- `Self.shotHint` + `recordText` — the recording row (`🔴 📸 ×2 🖱️/F3`)
- `Self.pickHint` + `pickText` — the ⌘⇧-picked row (`🎯 hold ⌘⇧🖱️`, then
  `🎯 ×2 div#cart > span.price`); the label beside the outline in
  `chrome-extension/inspect.js` counts too, and so do its one error string
  (`⚠ no relay session took it`) and the toolbar title in `relay.js`
- `titleText` — `🤖 <label>` / `⏸️ 🤖 <label>`
- `flash(_:)` / `flashTitle(_:)` call sites in `AppDelegate.swift`
- `StatusItem.swift` — the menu bar item's `Pause` / `Resume` / `Exit`

## Scope: dictation helper only

There is **no text entry** and **no selection shortcut**. Both existed and were
deliberately removed — everything except "one more shot" now happens by itself
when Wispr starts listening, and that one is reachable without the keyboard at
all (see *Mouse 4 is the shutter*). Do not reintroduce a typing affordance:
the panel's `canBecomeKey` is false precisely so the overlay can never steal the
caret from the app Victor is working in.

## What pause is (and is not)

Pause **does not touch Wispr Flow**. That is the whole purpose of it: Victor
pauses so he can dictate into a browser, a chat, a commit message *normally*,
without those words also landing in the agent's queue. Nothing in this app may
try to stop, mute or intercept the transcription — it only stops acting on it.

Concretely, `paused` bails out of four places and nowhere else: `captureContext`
(no flash, no selection probe, no screen capture), `plusOneShot` (F3 does
nothing), `send` (nothing reaches the outbox), and `syncBorrowedGestures` — which
hands mouse 4 back to LinearMouse *and* ⌘⇧-click back to Chrome. That last one is
load-bearing rather than tidy: dictating into a browser is the reason he paused,
and an inspector still eating his ⌘⇧-clicks would be the one thing pause was
supposed to stop. Wispr keeps reporting that it
is listening, which is why `recordText` also hides the recording row while
paused — advertising F3 in a state where it does nothing would be a lie.

## Title states

Titles are `<emoji> <label>: <state>`, where the label is `folder@branch` of the
directory the overlay was launched in — the same thing Claude Code's status line
shows, e.g. `ai@master`. It said "Agent" until two overlays could exist at once;
with two sessions on screen, identical titles hide the only fact that matters,
which is *which repo* is about to receive what he says. `SessionLabel` derives it
from the working directory (inherited from the session, since `/relay` launches
`start.sh` inside it), re-reads the branch every 10s, and yields to `--label`.

| state | label |
|---|---|
| idle (the chip) | `🤖 ai@master` — no state word: "standing by" is what he can already infer from nothing happening |
| Wispr recording | `🤖 ai@master`, unchanged, **plus the recording row below it** |
| paused (chip click, or the menu bar) | `⏸️ 🤖 ai@master` — the ⏸️ goes **in front of** the robot, never instead of it |

Paused prefixes rather than replaces, and carries no state word. The chip's job
is still to say *which agent this is*; pause is a modifier on that, not a
different thing — and it is the same order as the menu bar item (`⏸️🤖`), which
is the other place the state shows. The old form was `⏹️ ai@master: Paused`, from
when paused was a panel in the corner with room for a word.

**Dictating no longer has a title of its own.** It used to be `🎙️ …` with dots
cycling 1→2→3→1, and there was a glass-shine sweep every 5s to go with it. All of
that has moved into the recording row: the top line now stays `🤖 folder@branch`
through the whole dictation — that is the fact that does not change — and what
does change lives one row down.

The liveness those animations provided is still load-bearing, and is now the
pulsing 🔴: a frozen recording row is indistinguishable from a hung app, and the
entire point of the state is reassurance that speech is being captured.

Paused wears ⏹️ because it is the one state that has to be readable from across a
room. Opacity separates it further (1.00 vs 0.30).

## The recording row

While dictating and not paused, one row sits directly under the title:

```
🤖 ai@master
🔴 📸 ×2 🖱️/F3
```

That is the whole of what the overlay says during a dictation, and it is Victor's
list, not a designer's: **how many pictures this message is carrying, and the two
ways to add another.** The count includes the automatic context capture — he took
that one by starting to talk, and a count that skipped it would disagree with
what the agent receives. It goes up live, so taking a shot needs no other receipt.

**The count says `×1` from the instant the row opens**, before `screencapture`
has returned (`AppDelegate.contextShotPending`). It used to say `×0` for the best
part of a second — a clipboard probe that sleeps up to 400ms plus a subprocess —
and then flick to `×1`; but a picture *is* being taken in that second, so zero
was simply wrong, and wrong in the one moment he looks at the row. It falls back
to zero only if the capture genuinely fails, which is the only case where zero is
the truth. `captureContext` therefore runs **before** `overlay.setListening(true)`
in `dictation.onChange`: it books the shot synchronously, and `setListening(true)`
zeroes the count, so the other order publishes a `×1` into a row about to reset it.

The inputs sit inside this row rather than in a legend of its own. They are the
only things that do anything while he talks, and they belong beside the number
they change. The mouse is named first because it is the half that needs saying:
F3 has always been there, while the back button is borrowed only for the length
of the dictation.

**The glyph alone names the mouse** — `🖱️/F3`, not `🖱️back/F3`. The word said
*which button* exactly once, on the first dictation after it was introduced;
after that the hand knows, and what remained was three characters of width taken
out of a row riding over the work he is looking at. The 🖱️ still has to be
there — that half of the pair is the one a keyboard-shaped hint would never
suggest.

## Two gestures are borrowed, and only while dictating

Mouse 4 and ⌘⇧-click in Chrome both belong to other software the rest of the time,
and `syncBorrowedGestures()` is the single switch that takes them and gives them
back. The two sections below are one argument applied twice.

## Mouse 4 is the shutter, but only while dictating

The back side button (`MOUSE_BUTTON_4` = 3) takes a shot, and the relay
**swallows it** so nothing else acts on it — while Wispr is recording and
forwarding is on, and at no other time.

That button is Victor's Return key: LinearMouse
(`~/.config/linearmouse/linearmouse.json`) maps it to a `keyPress: ["enter"]`,
which is what he submits with all day. Borrowing it is only defensible because
of how narrow the window is — during a dictation an Enter lands in whatever
happens to have focus, which is never what he meant, and the point of the whole
overlay is that he is *away from the keyboard*. Asking him to reach for F3 to
attach a picture put the one thing he does mid-sentence back on the keyboard.

Three rules keep the theft honest:

- **Gated on `listening && !paused`**, pushed to the tap by
  `AppDelegate.syncBorrowedGestures()` from both edges that can change the answer
  (Wispr starting/stopping, pause toggling). At rest and while paused the button
  is untouched and still types Return. That one method sets **both** borrowed
  gestures — this button and ⌘⇧-click in Chrome — from a single expression, so the
  recording row can never advertise one of them in a state where it is dead.
- **Only the bare press.** LinearMouse maps ⌘+button separately to ⌘Return, so
  any modifier passes straight through: one gesture must not quietly become two
  different things.
- **Both halves are swallowed** (`otherMouseDown` *and* `otherMouseUp`, which is
  why the tap mask grew). LinearMouse sits downstream of this tap and would
  otherwise still see an orphan release to act on.

**Tap order is what makes this work, and it is not guaranteed.** Both apps use
`.cgSessionEventTap` at `.headInsertEventTap`, where the most recently installed
tap sees events first. LinearMouse starts at login and the relay starts per
session, i.e. always later — so the relay wins. If LinearMouse is ever restarted
*after* a relay, it will convert the button to Return before this tap sees it and
the shot silently stops working; restarting the relay fixes it.

## The cursor is in the file name

Every shot is `shot-<timestamp>-cursor-34.2x71.8pct.jpg` — where the pointer was,
as a percentage of the frame, **top-left origin** like the image itself
(`ScreenCapture.cursorTag`).

He points at things while he talks — "this button", "that line" — and the
sentence alone cannot say which. The reading rides in the **name** rather than in
a new outbox field because the name is already in front of the agent: the path
travels in `paths`, so the pointer arrives with the picture and nothing
downstream has to learn a new key to benefit from it.

**Percentages, not pixels**, because the agent reads the shot through a tool that
downsamples it: a pixel coordinate stops pointing at the right thing the moment
the picture is resized.

The position is sampled **at the gesture** and carried down into
`ScreenCapture.grab(cursor:)`, never read inside it — by the time the capture
runs, a clipboard probe and a subprocess later, the hand has moved on.

The 🔴 pulses 1.0 → 0.25 and back, 1.1s each way — slow on purpose. Anything
brisker is something blinking next to the cursor while he is trying to think.
Only the dot animates; the count must stay readable at every instant.

**At rest there is no second row at all**, and flashes still get one: any
`flash(_:)` message summons it in any state, because the Accessibility warning
fires at launch, long before a dictation.

## Size: minimal, per state

`layoutContent()` hugs the **current** state's content — not the widest state
there is. Standing by is what the overlay does for hours, so it must be no bigger
than `🤖 ai@master` needs — not even the 26px normally kept clear for the ✕, since
the chip has none. It used to reserve room for the longest title and for the
hidden shortcut legend, which bought an overlay that never twitched at the cost of
empty space the whole time.

Resizing on a state change is therefore expected and fine, and so is the hair of
width the recording row gains at `×10`.

Row heights, for checking a layout change without seeing it: title 16, recording
row 17, ⌘⇧-picked row 17, selection 15, `rowGap` 6 between them, `pad` 12 all
round. So the idle chip is 40 tall, and dictating with a selection is 84 (107
with a pick waiting).

**No screen capture can contain this window**, and `RELAY_CAPTURABLE=1` no
longer buys it back on macOS 15 (verified 2026-07-31: transparent image, both
whole-display and `screencapture -l <windowid>`). Two ways to see a change
anyway:

- `kill -USR1 <pid>` → `<home>/snapshot.png`, the view drawing itself. This is
  how `docs/*.png` are made: `RELAY_DEMO=1` for the content, USR1 at each state,
  composite onto a dark backdrop. A panel's blur is missing from the shot (the
  window server draws it, not the view); the chip comes out exactly as he sees it.
- `CGWindowListCopyWindowInfo` for geometry: the bounds say which rows are up,
  and comparing the origin to the cursor says whether it is still anchored.

## Two shapes: the chip and the panel

The overlay has two forms, and `anchored` in `RelayWindow` is the switch.

**Anchored (at rest *and while dictating*)** — bare text, `🤖 folder@branch` plus
the recording row when there is one, no blur, no rounded rect, no window shadow,
alpha 0.80, trailing the cursor. Parked in a corner it was either invisible or
pointless; riding along with the pointer it answers the one question worth
answering at rest — *which agent is this?* — where he is already looking. There
is **no ✕ on the chip**: an end-session button on something that moves away as
you reach for it means nothing. (The menu bar item is the ✕ that stays put.)

**Panel (the message, and only the message)** — what the overlay has always been,
top-left of the current screen, with the blur, the ✕ on hover, and full opacity.
Entered by a prompt and by a flash. **Nothing else.**

**Paused is not a panel state.** It was, on the argument that pausing was the
only route to a ✕ at rest. The menu bar now carries Pause/Resume *and* Exit, so
that argument is gone — and what was left was a half-screen panel parked over his
work for the whole time he dictates into other apps, which is minutes, saying
something he entered on purpose. It stays a chip: `⏸️ 🤖 folder@branch`, at 0.30.

**Dictating is not a panel state.** It was, and that put a half-screen window
over his work for the entire time he talked, to report a state he had just
entered on purpose. The panel is now for the one thing he must actually read:
what Wispr heard, while Cancel can still stop it. That is also why the F3 receipt
is a number in the recording row and not a `flash(_:)` — a flash is a panel, and
taking a picture mid-dictation must not throw one across the screen.

Tracking has two modes, and the second is what keeps the chip catchable:
*engaged* pins it to the cursor every frame at 60 Hz (anything lazier reads as
lag, because it is lag), and after ~0.25s of stillness it *settles* and stays put
until the cursor travels 70px. Growing into the panel is animated (0.22s ease
out); everything else resizes instantly.

## The menu bar item

`StatusItem.swift` puts a 🤖 in the menu bar for the whole life of the process,
with the session label as a disabled header and two commands: **Pause/Resume**
and **Exit**.

It exists because neither shape is a dependable place to find the app. The chip
belongs to the pointer and hides while he types; the panel comes and goes with
what is happening; and the ✕ lives only on the panel, so ending a session at rest
meant pausing first just to make a panel to close. The menu bar is the one place
that is always in the same pixels.

The label is read in `menuWillOpen`, not pushed on a timer — with two overlays up,
two identical 🤖 say nothing about which session a click is about to end, and the
only moment the answer has to be right is the moment he is looking at it.

**Pause is here and not only on the chip** because the chip is a moving target —
it rides the cursor and vanishes while he types — and pausing is something he
does *on his way into another app*, i.e. precisely when he has no patience to
chase a label around. The item is worded as the verb it performs (`Pause` while
running, `Resume` while paused), not as a checkbox of the current state, and the
menu bar glyph becomes `⏸️🤖` — the same order as the chip. That glyph matters:
while he is typing the chip is hidden, so the menu bar is then the only thing on
screen saying forwarding is off. `AppDelegate.togglePause(reason:)` is the single
switch behind both routes, so the two can never disagree.

Exit goes through the same `endSession(reason:)` as the ✕, so the outbox still
gets its `session_end` before the process dies. There is no ⌘Q key equivalent:
the app is `.accessory` and never becomes key, so the hint would advertise a
shortcut that does nothing outside the open menu.

## The prompt is held, not sent

The prompt shown after a dictation is **not yet in the outbox**. It sits in
`AppDelegate.held` for 3–5s (`minHold`/`maxHold`, scaled by word count) behind a
**Cancel** button in the bottom-right, and only `commit()` — on the countdown
running out, on a click on the overlay body, or on quit — ever writes it.

That delay is the whole point: the agent polls the outbox every couple of
seconds, so a line already written may already be a tool call in flight. Cancel
can only mean something while nothing has been written. Escape in the terminal
remains the tool for work already under way.

**The last line of the prompt is the pictures, with their times:**

```
↪ public Order placeOrder(Cart cart) {
extract the tax calculation out of this method
📸 ×2 0:38
```

`AppDelegate.shotLine` builds it, and the stamps are **m:ss from the moment the
dictation opened**, not wall-clock. The count on its own answers "did my shots
land"; it does not answer the question he has a few seconds later, which is
*which* moments he caught. In a three-minute dictation `📸 ×4` is four
indistinguishable files, while `0:38 · 1:52 · 2:41` is a table of
contents — and this panel, with the Cancel clock running, is the last instant at
which noticing a missing one is free. Wall-clock would say nothing here: the
shots exist only as parts of this message, and `15:22:07` does not locate a
moment *inside* it.

**The context screen is counted but not stamped.** It is always at zero — he
took it by starting to talk — so its `0:00` is the one stamp that carries no
information, and printing it only pushed the stamps that do mean something a
column to the right. What is listed are the moments he chose; a dictation whose
only picture is the automatic one therefore reads `📸 ×1`, with nothing after it.

The count is built from `pendingScreen`
plus `pendingShotOffsets`, **not** from `attached` — the screen travels in its
own outbox field, so counting `attached` would print a total one lower than the
`📸 ×N` he just watched climb in the recording row. The `🎙️ sent + N 📸` flash
counts the same way, for the same reason.

Offsets are sampled **at the gesture** (`plusOneShot`'s `takenAt`), like the
cursor and for the same reason: `screencapture` returns a subprocess later, and a
second of drift is a whole sentence.

Ordering is preserved: a second dictation arriving mid-countdown releases the
first one before displaying itself.

## Dark mode

The overlay must look right in **both** appearances, and it follows the system
automatically — nothing pins an appearance. That holds only as long as every
colour is either a dynamic system colour (`labelColor`, `secondaryLabelColor`,
`textBackgroundColor`, `systemRed`) or a translucent white/black overlay that
works on any backdrop. The blur is `NSVisualEffectView(.hudWindow)`, which
adapts on its own.

**Do not hardcode a literal colour for anything that sits on a variable
backdrop.** The ✕ was drawn with a hardcoded white cross: fine on light mode's
dark disc, nearly invisible against dark mode's light one. Custom-drawn views
resolve dynamic colours against `effectiveAppearance` inside `draw(_:)`, so
using them is enough — no appearance observers needed.

## Opacity states

| state | alpha |
|---|---|
| paused | 0.30 |
| idle chip | 0.80 |
| every panel state | 1.00 |

The chip is translucent because it now rides over his actual work and has to read
as an overlay; the panels are opaque because each of them exists to be read.

Paused keeps 0.30, because there the fade *is* the message: forwarding is off,
and the overlay should look switched off.

## Placement

**Chip**: below-right of the cursor (`anchorGap`), flipped at the screen edges so
it is never half off-screen, never under the pointer.

**Panel**: top-left of **whichever screen the cursor is on**. An overlay stranded on
the other monitor is an overlay he cannot see; where it sits *on* that screen is
left alone, so one he dragged out of the way stays out of the way. It anchors its
top edge so it grows downward, and never teleports while a mouse button is down.

## Capture order: flash first

The red vignette fires **before** the selection probe and before `screencapture`
— `CaptureFlash.announce()` at the top of `captureContext` / `plusOneShot`, with
the slow work pushed onto a background queue. It used to fire from inside
`ScreenCapture.grab`, i.e. after a clipboard probe that sleeps up to 400ms and a
subprocess we wait on, so the confirmation landed visibly late — after the window
had already widened and the selection was long taken. A receipt that arrives that
far behind the gesture no longer says *now*.

`CaptureFlash`'s panel is `sharingType = .none`, so firing it first cannot put it
in the shot it is confirming.

## Picking elements in Chrome

Hold ⌘⇧ over a page **while dictating**, the element under the cursor is outlined
and named; ⌘⇧-click and its selector joins that dictation. It resolves the demonstratives — "make
*this* button blue" is not actionable, and a CSS path is the same sentence with
the pronoun filled in.

**It is a Chrome extension (`chrome-extension/`), and the relay is only a
mailbox.** CDP is the obvious design and it is the wrong one twice over:

- Since Chrome 136 `--remote-debugging-port` is refused on the default profile,
  and `--load-extension` is ignored outright as of 151 (verified 2026-08-15:
  the flag loads nothing, and `--disable-extensions-except` alongside it disables
  everything). Driving Victor's *actual* browser over CDP would mean relaunching
  it against a throwaway `--user-data-dir` — a browser without his tabs or his
  logins, i.e. not the thing he is looking at.
- From outside, pointing at a DOM node means mapping a screen point through the
  window origin, the height of the browser chrome, page zoom and device pixel
  ratio, then mapping the element's box back out to draw a rectangle round it.
  Inside the page there is no mapping at all — `elementFromPoint` and
  `getBoundingClientRect` are already in the coordinate system the outline is
  drawn in, and stay right after a zoom.

So `ElementPicker.swift` is an HTTP listener on loopback and nothing else. The
inspector — outline, label, ⌘⇧ gate, swallowed click, selector — is `inspect.js`.
Ports are 8917–8919, first free one per relay; the extension posts to **all** of
them, which is the same shape as the outbox, where one dictation reaches whoever
is listening.

Installing it is a manual step, once: `chrome://extensions` → Developer mode →
Load unpacked. There is no scriptable route left in Chrome 151 (`Extensions.
loadUnpacked` over CDP works, but only for a browser started with
`--enable-unsafe-extension-debugging`, which his is not).

### It lives only while the recording row does

`ElementPicker.dictating` is set from the same `listening && !paused` as mouse 4,
by the same `syncBorrowedGestures()`. Outside that window `/ping` answers 503 and
the extension reads a refusal exactly like no relay at all, so ⌘⇧ in Chrome goes
straight back to opening links in new tabs.

It was armed around the clock for about an hour, and that is the wrong shape:
⌘⇧-click is how a link opens in a new tab, so an inspector that can take it at any
moment is a browser that intermittently stops opening links with nothing on
screen to explain why. Tied to the dictation, the theft is narrow *and visible* —
the row saying the gesture is live and the gesture itself appear and disappear
together, which is the same bargain mouse 4 already made.

The extension caches its probe for only 1s (`PROBE_TTL_MS`) because the answer
now flips every time he starts and stops talking, rather than once a session.

### The hint is the row, and the row is beside the cursor

While dictating and before he has picked anything, the row reads `🎯 hold ⌘⇧🖱️`.
After the first pick it gives way to `🎯 ×2 div#cart > span.price`, because the
question changes: before, the only thing worth saying is *that this is possible*;
after, he knows the gesture, and what he cannot check without a name is whether
the click caught the button or the div wrapped around it.

The word **hold** stays in it. The gesture arms only after 400ms, so `⌘⇧🖱️` alone
would describe a click that does nothing and read as a bug the first time he
tried it.

### ⌘⇧ has to be *held*

400ms, alone, with any other keypress abandoning the hold (`HOLD_MS`,
`poisoned`). ⌘⇧-click opens a link in a new tab and jumps to it; a quick one still
does, and only a deliberate hold arms the outline — the two gestures are told
apart by the one thing that actually differs, which is time. Every ⌘⇧ shortcut is
typed faster than the gate as well, so ⌘⇧T/⌘⇧N/⌘⇧R never arm it.

**The chord, not the ⌘.** It was bare ⌘ for an hour, which was wrong: ⌘-click is
how a link opens in a new tab, which Victor does all day, and one modifier is far
easier to hit by accident than two. Releasing *either* half ends the gesture, and
`poisoned` survives until the chord breaks — so ⌘C followed by reaching for ⇧
without letting go of ⌘ stays a shortcut rather than turning into a hold
halfway through.

Two more gates on top: with **no relay session running** the extension never arms
(it probes `/ping` first, so the gesture in a browser with no agent behind it
means exactly what Chrome says it means), and the same refusal covers **paused**
and **not currently dictating**, which is now the common case.

Verified 2026-08-15, driving a test Chrome over CDP: plain click → page sees it;
chord-click under the gate → page sees it; chord held past the gate → swallowed
and picked; ⌘C first then held → page sees it; chord released → page sees it. And
against the relay directly: at rest `/ping` and `/pick` both answer 503 and
nothing is recorded; with the dictation flag set, both answer 200 and the pick
lands.

### The pick queue still survives a dictation opening

Unlike shots and the selection, `pendingPicks` survives `captureContext` — not
because picks can predate a dictation (they cannot any more; the gesture is dead
outside one) but because **Cancel puts them back**. A cancelled prompt leaves its
elements in the queue for the retry, and those legitimately predate the dictation
they end up riding, which is why the stamps can still come out **negative**:
`🎯 −0:08 …` means he pointed at it eight seconds before he started saying it
again. In the ordinary case every stamp is positive.

They go stale after 10 minutes (`pickTTL`) — a queue left behind by a cancelled
prompt he never retried is litter, not context. Nothing else clears it, so a
dictation whose transcript never arrives keeps its picks rather than stranding
them: `flushOrphaned` releases the *shots* on their own because a picture is
worth looking at unaccompanied, while a bare selector is nothing to act on.

**Cancel puts them back.** `releaseHeld(send: false)` returns the elements to the
queue — cancelling means the sentence was wrong, not that he pointed at the wrong
things, and re-taking a pick means finding the element in the page again, which
is the expensive half of the gesture. Shots are not restored: another one can be
taken blind, and the screen has moved on anyway.

### Why the row names the newest pick

`ElementPick.short` is the **tail** of the selector, for the same reason the tail
is what identifies it: the head is the page he is already looking at. The green
flash in the page is gone the moment he lets go of the chord, so this row remains
of the receipt for the rest of the sentence.

Built as a row with a separate glyph label, like the recording row. Not for an
animation (nothing pulses here) but because `measure()` is a font metric and both
🎯 and `×` fall back to faces the monospaced metrics know nothing about: inline,
the underestimate was ~2 characters, and AppKit ellipsized the count away.
`glyphRowWidth` asks the label via `sizeToFit` instead of asking the font. The
rows above tolerate the same error only because they never truncate.

## The selection is frozen for the whole dictation

The first non-empty read wins, and nothing overwrites it until the message is
sent or flushed (`stashSelection` bails when `pendingSelection` is already set;
`captureContext` clears it only when a *new* dictation opens). He talks for a
minute, another window jumps in front, he switches apps to look something up —
none of that changes what he is talking about. Later probes exist only to fill a
blank the first one left.
