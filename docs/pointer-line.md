# The line under the pointer — measured, not shipped

**Status: deliberately not built.** Everything below was measured on 2026-08-22
and then left alone, to keep the shutter path as simple as it is. This file
exists so the next person does not re-derive it, and so the decision reads as a
choice rather than as an oversight.

## What it is

Every shot already records **where the pointer was**, in the pixels of that
frame, in its own file name — `shot-00:38(mouse-at-1034x1466px).jpg`. Nothing
reads that coordinate back. The idea is one clause more in the shots line:

```
[what the mouse was resting on in each, read off the screen:
 shot-00:02(mouse-at-580x1119px)-small.jpg = "DO NOT COPY TEXT TO/FROM CODING AGENT…";
 shot-00:11(mouse-at-884x1863px)-small.jpg = "→in browser/sql LIMIT OFFSET"]
```

The text comes from Vision OCR run at that coordinate: recognise the frame, take
the observation whose box is nearest the point, quote its string. ~20 tokens a
shot against the 550 the picture now costs.

## What it is worth

`evals/`, variant `small-ptrtext`, three runs on the `pointed` fixture, against
`small` as the baseline:

| | `small` | `small-ptrtext` |
|---|---|---|
| accuracy | 1.00 | 1.00 |
| turns, median | 12 | **5** |
| output tokens, median | 3,109 | **1,323** |
| best run | 10,512 fresh | **2 fresh, 1 turn, 12s** |

One run in three answered **without opening a single picture**. The other two
opened them and *corrected the OCR* — `⭐` where OCR had read `¿`, and
`- Claude Opus ≥med for architecture/review` where OCR had cut the line short.
That is the relationship the feature wants: **the text is a hint, the pixels are
the authority.**

The saving is therefore not in the pictures — it is in the *looking*. The frames
are ~20% of a real exchange and the agent's own turns are the other 80%, which
is the half this halves.

## Why it is not shipped

- **The shutter path is short and this would lengthen it.** `VNRecognizeTextRequest`
  at `.accurate` is ~650ms on a retina frame (~104ms at `.fast`, which finds half
  the lines). That cannot go where the burned-in cursor mark used to be — it was
  removed from there for costing ~100ms. It belongs **after** `screencapture`
  returns, on the queue that already writes the `-small.jpg` sibling: nothing
  needs the text until `commit`, and the dictation is still running.
- **Simplicity now beats 5 turns later.** Victor's call, and the honest one: the
  measurement will keep.

## Do not turn it into `ptrtext-only`

The tempting next step — quote the line, drop the picture — is already
contradicted by the runs. The one run that trusted the text alone returned the
**poorer** answer (`for architecture/review`, having lost the `- Claude Opus
≥med` in front of it) and still scored 1.00, because the fixture key is a
substring match. A text-only variant will therefore look better in the table than
it is. And `unsubscribe` would fail it outright: the pointer was not on the
sender.

It could at best be a per-shot decision. It cannot be the default.

## How to build it, when it is built

Everything needed already exists somewhere in the repo:

1. **The OCR** — `evals/probes/ocrline.swift` is the whole algorithm in 40 lines:
   `VNRecognizeTextRequest`, then the observation minimising `dy*3 + dx` to the
   normalised cursor point. The `*3` weights y because a text row is wide and
   short. Move it into a `PointerText.swift` beside `SelectionCapture`, which is
   its sibling in every way — both answer "what was he looking at, in characters".
2. **The coordinate** — already sampled at the gesture and carried into
   `ScreenCapture.grab(cursor:)`. Read it there, not from the file name.
3. **Which frame to OCR** — the small one is enough. Verified: the pointer line
   resolves identically off the 1000px copy and off retina, at 554ms against
   650ms. That also means it can run *after* `writeHandoverCopy`.
4. **Where it goes** — the shots clause in `AppDelegate.shotsClause`, and
   `pointerTexts` in the outbox keyed by base name, exactly as `sources` (the
   window titles) already are. **Not the file name**: same argument as the window
   title — arbitrary text with quotes and slashes in it does not survive being
   made into a filename, and Victor reads these names himself.
5. **When there is nothing** — skip the clause. No AX selection, no OCR hit, an
   empty desktop: the absent clause reads as "he was not pointing at words",
   which is true more often than not. Do not emit `= ""`.

## Traps

- **Do not offer a crop instead.** A native-resolution crop at the pointer was
  measured at 0.87 and one run returned the first two shots swapped: two
  pictures per shot break the sequence, and sequence is what these messages are
  made of. A quoted line is not a picture, which is the whole reason this
  variant is safe where that one was not.
- **Quote it, do not assert it.** The line is an OCR reading and OCR is wrong
  about symbols (`¿` for `⭐`, `»` for `→`). The clause says "read off the
  screen" for that reason; the agent then corrects it against the frame, which
  is what two of the three runs did.
- **The AX hit test is the better version of this and is not available yet.**
  `AXUIElementCopyElementAtPosition` at the cursor gets a form field's *value*
  and a truncated label's *full* text, which OCR structurally cannot. It also
  returns nothing in VS Code without screen-reader mode and little in IntelliJ,
  where OCR still works. If both are ever built, OCR is the floor and AX is the
  upgrade — never the other way round.
- **`evals/text-vs-pixels.md` is the fuller argument**, including why dumping the
  *whole* screen as text is not a saving at all: an OCR of a Gmail desktop is 890
  tokens against the picture's 861, and 2,096 once the coordinates the layout
  questions need are attached.
