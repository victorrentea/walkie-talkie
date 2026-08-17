# evals — what a dictation costs, and whether it still lands

A relay message is mostly pictures. The words are a sentence; the screenshots
are one to seven retina frames, and each one costs about **3450 tokens** to
open — `width × height / 750` after the Read tool has fitted it to 2000px on
the long edge, which a 3456×2234 desktop always hits. The JPEG's file size does
not enter into it, so compressing harder buys nothing.

That is the bill. This directory exists because the obvious ways to cut it are
all guesses until they are run, and two of the most plausible ones turn out to
make the answers *worse*.

## Running it

```sh
python3 evals/run.py                                   # everything, 3 repeats
python3 evals/run.py --repeats 4 --fixture unsubscribe --variant compact,small
```

Results append to `results.jsonl`. Each row is one `claude -p` run: the answer,
`fresh` (input + cache_creation — the number to compare, since cache_read is
the constant system prompt), output tokens, cost, turns, and a score.

**`claude -p`, not the API, on purpose.** The question is not whether a model
*can* read seven screenshots — it plainly can. It is what an agent handed this
line **chooses** to do: how many frames it opens, whether it opens the one it
was told it probably does not need, and what that costs. An API call with the
images pre-attached has already made that decision for us.

## The fixtures are real dictations

Both come out of `~/.wispr-relay/outbox.jsonl` with their screenshots still on
disk. Nothing is synthesised — the whole question is whether an agent can
follow *Victor's* pointing, and a made-up sequence would answer it about a
made-up habit.

- **`unsubscribe`** (2026-07-31) — seven clauses, seven frames, one sender each:
  *"Nu mai vreau să văd mail-uri ca ăsta de la Fan Courier. Nici ca acesta de la
  Sesame. Nici ca ăsta de la H&M…"*. The transcript **is** the answer key, which
  is the point: he enumerates what he is pointing at, one clause per picture.
  This is the hardest thing a relay message asks for and the most common shape.
- **`pointed`** (2026-08-13) — three frames and, in so many words, *"tell me what
  words have I pointed out"*. This is the fixture that says whether the cursor
  coordinate in the file name is worth anything.

## What was measured

31 runs across five shapes, then 8 more on the shape that matters. Pooled over
the `unsubscribe` fixture, where every frame genuinely has to be opened:

| variant | line | images | n | accuracy | fresh tokens | cost |
|---|---|---|---|---|---|---|
| `current` | `[look at: …] [context: …]`, absolute paths | retina | 3 | 0.95 | 48,350 | $0.556 |
| `compact` | folder said once, order stated | retina | 7 | 0.94 | 50,320 | $0.593 |
| **`small`** | **as `compact`** | **1000px** | **8** | **0.95** | **29,349** | **$0.380** |

And across both fixtures, the two ideas that did not survive contact:

| variant | n | accuracy |
|---|---|---|
| `small-nocontext` — drop the automatic frame | 6 | 0.93 |
| `small-crop` — small frame + native crop at the pointer | 6 | 0.87 |

## What it says

**1. The pixels are the bill; the addressing is a rounding error.** Factoring
the directory out of seven paths saves ~90 characters a frame and measured
*nothing* — `compact` is inside the noise of `current`, and if anything slightly
above it. Downscaling the same frames to 1000px took 39% off the whole exchange.
The compact line stayed anyway, for what it says rather than what it saves: that
the list is chronological, and that the context frame can be skipped.

**2. 1000px is free.** Not "acceptable" — free. On `pointed`, every variant
returned **byte-identical answers**, quoting `⇒in browser/sql LIMIT OFFSET` and
`- Claude Opus ≥med for architecture/review` off a code editor at a quarter of
the resolution. Hence `ScreenCapture.handoverWidth`: the retina frame stays on
disk for Victor, a `-small.jpg` sibling travels to the agent.

**3. The automatic context frame is not a spare — it is usually picture one.**
Dropping it looked like the obvious saving, and it cost accuracy (0.93). The
reason is worth keeping: he starts talking about what is *already on his screen*,
so in the Gmail dictation the context frame is the first of the seven senders.
It is offered cheaply, with a hint that it can be skipped, rather than withheld.

**4. A crop at the pointer makes things worse (0.87).** Not because the crop is
unreadable — because two pictures per shot make the *sequence* harder to hold,
and one run duly came back with the first two shots swapped. Sequence is what
these messages are made of. The cursor coordinate in the file name is enough.

**5. Order beats timestamps.** Nothing in these runs needed wall-clock times.
What the frames carry is `shot-00:38(mouse-at-1034x1466px).jpg` — where in the
sentence, and where the pointer was — plus a line saying the list is oldest
first. That was sufficient for 7-item alignment at 0.95.

## A fixture whose answer key was wrong

The first `pointed` key was written by hand off a crop around the pointer that
showed two candidate lines, and the wrong one was written down. Fifteen runs
then answered `DO NOT COPY TEXT TO/FROM CODING AGENT` identically — every
variant, every repeat — which is what sent someone back to the pixels. The key
was wrong; the model was right, unanimously and reproducibly.

It is recorded in `fixtures.py` rather than quietly corrected, because a
suspiciously flat 0.67 across five variants is exactly the shape a broken eval
makes, and the next person to see one should recognise it.
