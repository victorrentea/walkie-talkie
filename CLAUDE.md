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
- `applyTitleText()` — `Agent on stand-by` / `Agent listening…` / `Agent paused`
- `flash(_:)` call sites in `AppDelegate.swift`

## Title states

| state | label |
|---|---|
| idle | `💬 Agent on stand-by` |
| Wispr recording | `🎙️ Agent listening` + dots cycling 1→2→3→1 every 0.45s |
| paused (single click) | `⏸ Agent paused` |

The dots are load-bearing: a frozen "listening" label is indistinguishable from a
hung app, and the entire point of the state is reassurance that speech is being
captured. Same reason for the glass-shine sweep every 5s while listening.

## Opacity states

| state | alpha |
|---|---|
| paused | 0.30 |
| listening / editing / hovered | 1.00 |
| idle | 0.45 |

Translucent by default so it sits quietly over whatever Victor is doing; opaque
the moment it matters (he is dictating, typing, or looking straight at it).

## Placement

Top-left of **whichever screen the cursor is on**, re-checked every 0.4s. A
bubble stranded on the other monitor is a bubble he cannot see. It anchors its
top edge so it grows downward, and never teleports while he is editing or
holding a mouse button.
