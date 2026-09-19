# capture-proof — the pictures are clean, and one word is legible in them

Two questions asked of real files rather than of the source, on 2026-09-19:

1. **Is anything Walkie Talkie draws inside a picture Walkie Talkie takes?** —
   Victor: *"Când Walkie Talkie face film sau poză, legat sau nelegat, în poza
   aceea trebuie să nu apară nici tulipa mouse-ului, nici lanțul de fulgere,
   nici orice alte săgeți care ar mai fi fost pe ecran din partea lui Walkie."*
2. **Does an agent reliably know which word he highlighted?** — and is the
   wheel-drag crop worth sending beside the whole page, or instead of it?

`evals/test_capture_decorations.py` already answers the first question *about the
source*: every window this process makes sets `sharingType` to `.none`. This
directory answers it about the **files**, which is the half a source scan cannot
reach — and it covers `ScreenFilm`, whose frames come from
`CGDisplayCreateImage` and not from `/usr/sbin/screencapture`, a capture client
the promise had never been measured on.

## Running it

```
./gen.py 1:p3:backing:1 2:p2:variance:2 3:p1:subprocess:2 4:p4:encode:2
./shoot.sh 1            # …2, 3, 4 — one scene each
./crop.py 1 2 3 4
python3 report.py       # the artifact table
python3 kits.py         # one folder per eval run, neutral filenames
python3 score.py        # after pasting the agents' answers into results.json
```

`shoot.sh` needs the installed app running and answering on 8917. Per scene it
loads `scene-N.html` in Chrome (one word selected by script — a real browser
selection, the same pixels a drag leaves), parks the pointer on that word, opens
a dictation through `POST /test/dictation/start` so the halo, the ring and the
chip are all on the screen, and then takes:

- the app's own frame — whatever `ScreenCapture.grab` just wrote, which is the
  same function the 🔽 shutter calls, plus its 800 px handover copy;
- an independent `/usr/sbin/screencapture` of the same screen;
- a 4 s, 20-frame recording through `WT_SHOOT_FILM=4 ./.build/debug/WalkieTalkie`
  — `ScreenFilm`, the path the 🔽 ↑ gesture drives;
- a **control** frame seconds earlier with no dictation open.

The one thing in the run that synthesises input is the pointer move, done under
`hands-off`. **That is why the control frame is taken five seconds after the
last release**: the locks, the amber frame and the cursor badge belong to Victor
Addons, which sets no sharing type anywhere, so they *are* in any frame taken
while they are up — and a reader would take them for Walkie's.

## What it found (2026-09-19, macOS 15.7, one built-in display, 3456×2234)

Four scenes, three unbound and one bound to `ttys002`; in every one the log line
`◯ caret halo on` precedes `context screen captured`, and `GET /test/state`
answers `listening: true`, `ringUp: true` with four rows on the chip.

| frame | ring px | chevron px | cursor-mark px |
|---|---|---|---|
| the app's own shot | 0 | 0 | 0 |
| its 800 px handover copy | 0* | 0* | 0* |
| independent `screencapture` | 0 | 0 | 0 |
| film frame 5 of 20 | 0 | 0 | 0 |

Counted in a 1200 px box around the pointer — the halo's ring is r=105 pt =
210 px, so the box holds it nearly three times over. \*the handover copy's raw
counts are non-zero and so are the control's, shrunk the same way: they are
colour fringes the 800 px downscale puts on Chrome's own toolbar, and the copy
is a thumbnail of a frame already measured clean.

Stronger, because it needs no colour model at all: **the app's shot differs from
the control in 0.0% of its pixels, in 0 regions** — the frame taken with
everything up is the frame taken with nothing up. The film frames differ in
0.03–0.07%, in 8–10 regions, every one of them the menu-bar clock, a menu-bar
extra or a tab favicon, and none within 600 px of the pointer.

## The word, and the crop

24 agent runs (Sonnet), four scenes × three conditions × two repeats. Three of
the four words appear **twice** in their own paragraph and the highlight is on
the second, so the answer is graded twice: the word, and whether the context it
quoted pins the right occurrence.

| condition | right word | occurrence pinned |
|---|---|---|
| the whole screen (800 px) | 8/8 | 4/6 |
| the wheel-drag crop alone | 8/8 | 6/6 |
| both files together | 8/8 | 3/6 |

**The word is never the problem** — 24/24, and the 800 px handover copy of a
3456 px screen is legible enough on its own. What the crop buys is *which one*:
handed the page, an agent quotes the sentence, and the sentence holds both
occurrences; handed the crop, it quotes the lines it was given. Handing over
both did not help and in this sample hurt — the page invites the wider quote
back. Sending the crop **instead of** the page is the reading with the evidence
behind it; sending both is the one that sounded obvious and did not measure.

No frame of Victor's screen is committed here — the repo is public and his
screen is his desk. `sample-crop.jpg` is a crop of the synthetic page only.
