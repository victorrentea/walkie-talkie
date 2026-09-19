# pointing-proof — nothing selected, only a box dragged round it

Victor, 2026-09-19, after `evals/capture-proof`: *"Dar dacă nu selectez text, ci
doar drag wheel în jurul unui paragraf sau propoziție, înțelege agentul ce text
e vorba? Din poză adică."*

`capture-proof` answered the question with a **highlight** on the page — the blue
rectangle told the reader where to look, and every condition scored the word
24/24. This one takes the highlight away. Nothing is selected anywhere; the only
thing that says *this text* is the rectangle the wheel drag left behind.

## What actually travels, which is not a crop

Since 2026-09-14 (`ScreenCapture.grabArea`, Victor: *"să se trimită nu doar
decupată poza, ci poza e ecranul integral, dar cu coordonate ce zonă am
selectat"*), a wheel drag sends **the whole display**, shrunk to 800 px on the
long edge, with the rectangle carried as four numbers in the name and one
sentence in the clause:

```
- shot-1-00:04(area-900x345-to-2594x574px)-small.jpg in 'Google Chrome — …'
Each is ≤800px wide; drop the -small for the full-resolution original. A name with
`area-x1xy1-to-x2xy2px` in it is a whole screen with a rectangle I dragged on it, in
that picture's own pixels, top-left origin — I am pointing at that region, not
cropping to it.
```

Those numbers are in the pixels of the **full-resolution** frame (3456 wide);
the file actually handed over is **800 px** wide. Nothing in the envelope says
so — *"that picture's own pixels"* reads as the picture the reader is holding,
and it is not the one the numbers are measured on.

## The five conditions

| | the agent is handed |
|---|---|
| `small` | **what ships**: the whole screen at 800 px, rectangle in the name |
| `sized` | the same, with the clause spelling out both frame sizes and the scale factor |
| `full` | the same 800 px copy **plus** the full-resolution original on disk |
| `both` | the whole screen at 800 px **and** the framed region as a second 800 px file |
| `crop` | only the region, at 800 px — what the app did before 2026-09-14 |

Four scenes, one target **sentence** each, always the *second* of its paragraph,
so a box round it has a sentence above and a sentence below inside the same
block and *"the paragraph"* is not an answer. The margins are a hand's, not a
designer's — 7–88 px of slop, different on each side. The words are a dictation
that cannot be carried out without knowing which sentence is meant (*"Rewrite
this sentence to be shorter and plainer"*), and each run is its own `claude -p`
(Sonnet) in its own empty directory.

## What it found (2026-09-19, 96 runs)

| condition | runs | right sentence | right place | verbatim |
|---|---|---|---|---|
| `small` — **what ships** | 28 | **21/28** | 22/28 | 0.82 |
| `sized` — the scale spelled out | 12 | 7/12 | 7/12 | 0.73 |
| `full` — full-resolution beside it | 12 | 10/12 | **12/12** | 0.95 |
| `both` — screen + the region as a file | 16 | **15/16** | 15/16 | 0.96 |
| `crop` — the region alone | 28 | **28/28** | 28/28 | 1.00 |

*right sentence* = the quote **is** the framed sentence; *right place* = it
overlaps it by six words or more; *verbatim* = `difflib` ratio to it.

**So: yes, he can point with the wheel alone and be understood — three times in
four.** What ships gets the sentence 21/28, and **six of the seven misses are in
another paragraph of the page**, not a neighbouring sentence. Against `crop`'s
28/28 that is p = 0.006 (Fisher); pooling the two conditions that hand over
nothing but the 800 px screen (`small` + `sized`, 28/40) it is p = 0.001.

**The failure is not the coordinates being unreadable, it is the rectangle being
eyeballed onto a picture 4.3× smaller than the one it was measured on.** Every
miss says so in its own words: *"mapped the dragged rectangle's full-res coords
to the small screenshot by scale … landing on the last two lines of paragraph
3"*, and paragraph 3 is not the one. Which is also why **spelling the arithmetic
out did not help**: `sized` hands over the frame size, the copy's size and the
factor, and scores 7/12 — no better than saying nothing. Arithmetic was never
the missing piece; resolution was.

**Two things fix it, and they are the two that hand over pixels.** The
full-resolution original on disk puts *right place* at 12/12 (its two misses
quote the whole paragraph in the one scene whose box genuinely spans it) — but
it costs a second, 3450-token read, and only when the agent thinks to make it.
Sending the framed region **as its own 800 px file beside the screen** scores
15/16 at 550 tokens, which is `crop`'s accuracy without giving up the thing the
2026-09-14 change bought: the screen is still there, so *"put something here"*
is still sayable, and the zoom answers *"what does it say here"*.

That is a change to `shotsClause` and `grabArea` and it is **not made** — it is
a recommendation with a measurement behind it, and the pointing-versus-cropping
call was Victor's.

## The one limit that no format fixes

A rectangle over wrapped text cannot select a sentence — it selects a **band of
lines**, and a sentence that starts mid-line shares its first line with the one
before it. Scene 2's box is the honest case: both `full` runs that missed had
located it *exactly* (*"it tightly bounds this paragraph's four lines, no more,
no less"*) and then quoted the paragraph. If he wants a sentence rather than a
region, the highlight is still the instrument — that is what `capture-proof`
measured, and it was 24/24.

## Running it

```
./render.py                 # four scenes, headless Chrome at 1728×1117 @2×
./ask.py --repeats 4        # one `claude -p` per run, in a temp dir each
./score.py
```

`render.py` needs Chrome and Pillow; `ask.py` needs `claude` on the PATH. The
page is rendered rather than photographed off Victor's screen — 3456×2234, the
geometry `capture-proof` ran on — so **no frame of his desk is in this
directory** and the two samples (`sample-screen.jpg`, `sample-zoom.jpg`) are the
synthetic page. What the render does not have is the menu bar and Chrome's own
chrome; it shifts the text down the frame and changes nothing about its size in
pixels, which is the variable under test.
