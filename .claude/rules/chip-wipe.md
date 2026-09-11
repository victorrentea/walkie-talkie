---
paths:
  - "Sources/WalkieTalkie/ChipWipe.swift"
---

# The oblique wipe

Rules for the 60° line that swaps one chip message for the next (`ChipWipe.swift`), and for the
`WT_SHOOT_WIPE` contact sheet that is the only way to review it.
Full history and reasoning: docs/journal.md — see the sections named after each rule below.

## Shape and timing

- **A line at 60°, never a fade.** A fade says *this is ending*; a wipe says *this became that*,
  since at every instant both are on screen with a boundary between them. The chip is 200 points
  by 40 to 100: a vertical edge crosses every row at the same instant and reads as a curtain, a
  horizontal one takes rows off one at a time and reads as three events; at 45° the travel is
  dominated by the chip's height and the sweep looks like it is going *down*. 60° is his number
  and the only one that works. → journal: *The oblique wipe: a message replaces a message*
- **0.32 s, and the floor is the brightening, not the wipe.** This runs on every flash the app
  raises, dozens of times a day, an inch from what he is reading — but below about a quarter of a
  second the band crosses a 200 pt chip faster than the eye resolves it and the whole thing
  collapses into a flicker, worse than the instant swap it replaced. 0.32 leaves the band roughly
  four frames over any given word. → journal: *The oblique wipe: a message replaces a message*
- **The band is 13 pt at 0.55 alpha with a 3 pt soft edge.** 26 pt at 0.90 with a 7 pt edge was a
  flare, not a brightening: a white blob over two glyphs of *both* strings at the seam, so the
  first letter of `Dictation cancelled` arrived inside a bright smudge — *"strălucește D-ul, cumva,
  mult straniu"*. Compared frame by frame on three sheets before choosing.
  → journal: *What the cancel actually looked like, and the two things wrong with it (2026-09-09)*

## Construction

- **Both halves of the swap are pictures, and the live rows are muted by `alphaValue`, never
  `isHidden`.** One picture of the old content erased over the live new content is wrong on any
  message longer than the one it replaces: the chip's background is transparent, so wherever the
  old picture has no ink the new row shows through it — `Cancelled` sticking its tail out past
  `Listening…` from the first frame, on the side the line has not reached. Two masked pictures
  over an alpha-muted view tree is the only arrangement in which the region ahead of the line is
  honestly *only* the old chip. Alpha and not `isHidden` because `layoutContent` owns `isHidden`
  on every one of those rows and would fight for it; **`ChipWipe.cancel` is the single place it is
  given back**, so an interrupted sweep cannot leave the chip blank.
  → journal: *The oblique wipe: a message replaces a message*
- **The light is stencilled by the text's own pixels — by luminance, not by alpha.** Every row is
  white ink carrying a dark halo; the halo has alpha too, so a stencil cut from alpha is a blurred
  blob around each glyph and, lit up, the row becomes a white slab with the letters lost inside
  it. The brightest **channel** of a premultiplied pixel is the white ink's own coverage and reads
  a black halo as zero. Measured on a rendered sheet: alpha-stencilled the seam is an unreadable
  smear, luminance-stencilled it is the words, brighter.
  → journal: *The oblique wipe: a message replaces a message*
- **Grow the stencil by one point.** The ink is already white, so white light on it changes
  nothing; the fattening fills the halo and gives the stroke a rim, which is what makes "a bit
  brighter" mean anything. → journal: *The oblique wipe: a message replaces a message*
- **The band leads the erasing edge by a quarter of its own width, and each picture carries its
  own copy of the band**, clipped by its own ink and its own side of the line. A single glow over
  the union lit the outgoing and incoming words *at once* wherever it crossed the seam — two
  different strings superimposed, a smear rather than a line.
  → journal: *The oblique wipe: a message replaces a message*
- **A row that no longer fits leaves through a `fadeHeight` (12 pt) vertical ramp, on a mask over
  a holder layer wrapping the picture** — the picture's own mask is already the sweep and a layer
  has one. The chip hugs its state, so `🔴 Listening... [HQ]` over `petclinic@main` is 23 pt
  taller than the one-row `🗑️ Cancelled` and the window has already resized when the sweep plays;
  top-aligned and clipped to the host, the second row was **cut through the middle of its
  letters** for the whole third of a second, and the sweep was blamed for it.
  → journal: *What the cancel actually looked like, and the two things wrong with it (2026-09-09)*
- **`rememberChip` takes the outgoing picture at the first relayout of a turn and releases it on
  the next hop through the main queue** — not at the flash. Cancelling is `setListening(false)`,
  `clearSelection()`, then `flash("🗑️ Cancelled")` in one call stack, the first two each
  relayouting; Core Animation commits once at the end of the turn, so a capture taken at the flash
  draws the collapsed `🎙️` nobody ever saw, and the row the sweep exists to replace vanishes in a
  jump one frame earlier. The main-queue hop drains after the stack unwinds and before the frame
  is committed — exactly the boundary that matters.
  → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **It is drawn in the chip's own layer, not a window of its own** (unlike `UnbindPop` and
  `BindFlight`, whose drawing leaves the chip). It never leaves the chip, the chip is riding the
  pointer, and a separate window would have to chase the cursor and would composite at its own
  opacity instead of the chip's 0.80. The one price: **`RelayWindow.snapshot` must stand a sweep
  down before it photographs anything**, or a `kill -USR1` landing inside those 0.32 s writes out
  an empty chip. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*

## Where it does not apply

- **Not the panel.** `anchored` is the test, the same one `refreshChrome` asks: a line travelling
  across a transcript, a quotation, a strip of frames and two buttons is a page being turned, a far
  bigger claim than one row changing. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **Not when nothing is on screen** — there is nothing to wipe *from*, and a stripe of light over
  blank desktop announces nothing. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **`showSentPrompt` clears its flash without the sweep** — what comes next is the panel
  unfolding, not another chip. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **Off entirely under `RELAY_SHOOT`.** `docs/overlay-states.html` photographs *states*; a
  transition is not one, and it needs no `Shot`. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*

## `WT_SHOOT_WIPE`

`WT_SHOOT_WIPE=/tmp/wipe.png ./.build/debug/WalkieTalkie` draws the cancel sweep as a strip of 13
frames on a dark ground and quits (`ChipWipe.shoot`, `RelayWindow.shootWipe`). The chip is
invisible to every screen capture (`sharingType`), the sweep lasts 0.32 s and is drawn in layers,
so `RelayWindow.snapshot` (view tree, stands a wipe down first) cannot see it either; it took a bug
report to notice a row cut in half for a third of a second, dozens of times a day.

- **`CALayer.render(in:)` honours `mask` but ignores animations.** Checked with a throwaway
  program before any of this was written — the effect is two masked pictures and a stencil, and a
  renderer that ignored masks would have produced a confident lie.
  → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **The motion is posed, not animated.** `picture()` returns its layer **and** a `pose(t)` that
  sets the same three values the CA animations set — the edge's position, the band's, the glow's
  opacity — so the sheet is the effect at an instant. **`ease(t)` is CoreAnimation's
  `easeInEaseOut` written out** (the cubic Bézier `0.42, 0, 0.58, 1`, solved by Newton): a sheet
  drawn from a different curve than the one that ships is a picture of something nobody sees.
  → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **On a dark ground.** The ink is white with a halo: on white the brightening is invisible, on
  transparency it is unjudgeable; a terminal is what it actually sits on.
  → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*
- **It drives the two layouts by hand, not through `flash(_:)`** — that hands the sweep to
  `rememberChip`/`wipe`, which plays it on screen over a third of a second, the thing that cannot
  be photographed. → journal: *`WT_SHOOT_WIPE` — because this is the least reviewable thing in the app*

## Do not

- **Do not replace the wipe with a fade, in either direction.** The half-second dissolve on the
  message leaving with nothing on the message arriving was an asymmetric fade for a symmetric
  event. → journal: *The oblique wipe: a message replaces a message*
- **Do not mute rows with `isHidden`, and do not add a second place that un-mutes them** —
  `ChipWipe.cancel` is the one. → journal: *The oblique wipe: a message replaces a message*
- **Do not cut the stencil from alpha, and do not share one band between the two pictures.**
  → journal: *The oblique wipe: a message replaces a message*
