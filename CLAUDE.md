# Claude Bubble — working notes

See `README.md` for what this is and how it works. This file is for rules that
must survive across sessions.

## UI language: English only

**Every string the app renders on screen is in English** — the title, the hint
legend, flash messages, error banners. No Romanian in the UI, ever, even though
Victor dictates in Romanian and these notes discuss it in Romanian.

Why: the bubble is on screen during workshops, in front of an international
audience and often mirrored to a projector. A Romanian label is noise to the room
at best and a distraction at worst.

This applies only to what is *rendered*. Log lines, comments and commit messages
are unaffected, and the dictation content itself is obviously whatever language
he spoke.

Current strings live in `BubbleWindow.swift`:
- `Self.hints` — the shortcut legend
- `applyTitleText()` — `<label>: Stand by` / `: Listening…` / `: Paused`
- `flash(_:)` / `flashTitle(_:)` call sites in `AppDelegate.swift`

## Scope: dictation helper only

There is **no text entry** and **no selection shortcut**. Both existed and were
deliberately removed — everything except ⌃⌥P now happens by itself when Wispr
starts listening. Do not reintroduce a typing affordance without being asked:
the panel's `canBecomeKey` is false precisely so the bubble can never steal the
caret from the app Victor is working in.

## Title states

Titles are `<emoji> <label>: <state>`, where the label is `folder@branch` of the
directory the bubble was launched in — the same thing Claude Code's status line
shows, e.g. `ai@master`. It said "Agent" until two bubbles could exist at once;
with two sessions on screen, identical titles hide the only fact that matters,
which is *which repo* is about to receive what he says. `SessionLabel` derives it
from the working directory (inherited from the session, since `/bubble` launches
`start.sh` inside it), re-reads the branch every 10s, and yields to `--label`.

| state | label |
|---|---|
| idle (the chip) | `🤖 ai@master` — no state word: "standing by" is what he can already infer from nothing happening |
| Wispr recording | `🎙️ ai@master: Listening` + dots cycling 1→2→3→1 every 0.45s |
| paused (single click) | `⏹️ ai@master: Paused` |
| ⌃⌥P pressed | `📸 Plus One Shot` for 1.6s, then back to the state title |

The dots are load-bearing: a frozen "listening" label is indistinguishable from a
hung app, and the entire point of the state is reassurance that speech is being
captured. Same reason for the glass-shine sweep every 5s while listening.

Idle wears ⏸️ and paused wears ⏹️ — one glyph apart, because the words alone are
too close to tell apart from across a room. Opacity separates them further (1.00
vs 0.30).

## The subtitle row

Only one row ever sits under the title, and **at rest there is none** — idle, the
bubble is nothing but `🤖 ai@master`. It appears for:

- the `⌃⌥P 📸` legend, **while dictating and not paused** — the only window in
  which that shortcut does anything;
- any `flash(_:)` message, in any state. This is why flashes outrank the legend:
  the Accessibility warning fires at launch, long before a dictation, and would
  otherwise be invisible.

## Size: minimal, per state

`layoutContent()` hugs the **current** state's content — not the widest state
there is. Standing by is what the bubble does for hours, so it must be no bigger
than `🤖 ai@master` needs — not even the 26px normally kept clear for the ✕, since
the chip has none. It used to reserve room for the longest title and for the
hidden `⌃⌥P` legend, which bought a bubble that never twitched at the cost of
empty space the whole time.

Resizing on a state change is therefore expected and fine. The one thing that
must **not** resize is the dot animation, so the width is measured from
`titleWidthProbe` — the current state's title with all three dots.

## Two shapes: the chip and the panel

The bubble has two forms, and `anchored` in `BubbleWindow` is the switch.

**Anchored (at rest)** — bare text, `🤖 folder@branch`, no blur, no rounded
rect, no window shadow, alpha 0.80, trailing the cursor. Parked in a corner it
was either invisible or pointless; riding along with the pointer it answers the
one question worth answering at rest — *which agent is this?* — where he is
already looking. There is **no ✕ on the chip**: an end-session button on
something that moves away as you reach for it means nothing.

**Panel (anything happening)** — what the bubble has always been, top-left of the
current screen, with the blur, the ✕ on hover, and full opacity. Entered by
dictation, a prompt, a flash, **and by pausing** — pause is deliberately a panel
state, because it is the only route left to ending a session at rest: click the
chip to pause, hover the panel, hit the ✕.

Tracking has two modes, and the second is what keeps the chip catchable:
*engaged* pins it to the cursor every frame at 60 Hz (anything lazier reads as
lag, because it is lag), and after ~0.25s of stillness it *settles* and stays put
until the cursor travels 70px. Growing into the panel is animated (0.22s ease
out); everything else resizes instantly.

## The prompt is held, not sent

The prompt shown after a dictation is **not yet in the outbox**. It sits in
`AppDelegate.held` for 3–5s (`minHold`/`maxHold`, scaled by word count) behind a
**Cancel** button in the bottom-right, and only `commit()` — on the countdown
running out, on a click on the bubble body, or on quit — ever writes it.

That delay is the whole point: the agent polls the outbox every couple of
seconds, so a line already written may already be a tool call in flight. Cancel
can only mean something while nothing has been written. Escape in the terminal
remains the tool for work already under way.

Ordering is preserved: a second dictation arriving mid-countdown releases the
first one before displaying itself.

## Dark mode

The bubble must look right in **both** appearances, and it follows the system
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
and the bubble should look switched off.

## Placement

**Chip**: below-right of the cursor (`anchorGap`), flipped at the screen edges so
it is never half off-screen, never under the pointer.

**Panel**: top-left of **whichever screen the cursor is on**. A bubble stranded on
the other monitor is a bubble he cannot see; where it sits *on* that screen is
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
