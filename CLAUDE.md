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
- `Self.shotKey` + `recordText` — the recording row (`🔴 📸 ×2 F3`)
- `titleText` — `🤖 <label>` / `⏸️ 🤖 <label>`
- `flash(_:)` / `flashTitle(_:)` call sites in `AppDelegate.swift`
- `StatusItem.swift` — the menu bar item's `Pause` / `Resume` / `Exit`

## Scope: dictation helper only

There is **no text entry** and **no selection shortcut**. Both existed and were
deliberately removed — everything except F3 now happens by itself when Wispr
starts listening. Do not reintroduce a typing affordance without being asked:
the panel's `canBecomeKey` is false precisely so the overlay can never steal the
caret from the app Victor is working in.

## What pause is (and is not)

Pause **does not touch Wispr Flow**. That is the whole purpose of it: Victor
pauses so he can dictate into a browser, a chat, a commit message *normally*,
without those words also landing in the agent's queue. Nothing in this app may
try to stop, mute or intercept the transcription — it only stops acting on it.

Concretely, `paused` bails out of three places and nowhere else: `captureContext`
(no flash, no selection probe, no screen capture), `plusOneShot` (F3 does
nothing), and `send` (nothing reaches the outbox). Wispr keeps reporting that it
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
🔴 📸 ×2 F3
```

That is the whole of what the overlay says during a dictation, and it is Victor's
list, not a designer's: **how many pictures this message is carrying, and the key
that adds another.** The count includes the automatic context capture — he took
that one by starting to talk, and a count that skipped it would disagree with
what the agent receives. It goes up live, so pressing F3 needs no other receipt.

`F3` sits inside this row rather than in a legend of its own. It is the only key
that does anything while he talks, and it belongs beside the number it changes.

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
row 17, selection 15, `rowGap` 6 between them, `pad` 12 all round. So the idle
chip is 40 tall, and dictating with a selection is 84.

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

## The selection is frozen for the whole dictation

The first non-empty read wins, and nothing overwrites it until the message is
sent or flushed (`stashSelection` bails when `pendingSelection` is already set;
`captureContext` clears it only when a *new* dictation opens). He talks for a
minute, another window jumps in front, he switches apps to look something up —
none of that changes what he is talking about. Later probes exist only to fill a
blank the first one left.
