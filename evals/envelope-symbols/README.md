# envelope-symbols — can a model read the markings, and how small can they get

Victor, 2026-09-19, with the template in full: *"Is it clear what I mean? … evaluate to see
whether even a Sonnet model can understand what the symbols in this transcription mean … The end
goal, as you can tell, is to reduce the amount of clutter at the end of the dictation and those
footers."*

So: three envelopes carrying **the same six attachments**, the artifacts really on disk under the
names each envelope uses, and eleven questions a reader can only answer by understanding the
markings — *which file shows only the region I framed, where was my pointer at 📸1, which
screenshot was automatic, how long did the recording run, what is `-original`*.

| envelope | chars | Sonnet | Opus |
|---|---|---|---|
| `current` — the app's shape before today | 1810 | 30/33 | 32/33 |
| **`victor` — his template** | **925** | **33/33** | **33/33** |
| `shrunk` — the derivable rows collapsed into one convention line | 763 | 32/33 | 33/33 |

## Round two, 2026-09-20 — does the agent infer the digit?

Victor, reading a footer whose rows differed by one character: *"Chiar e nevoie de astea? Nu
inferă agentul singur că în loc de `1` trebuie să pună `2`? Trage eval."*

The scene grew a **third** plain frame so the repetition is the one he is looking at (📸0, 📸1,
📸2 whole screens, 📸3 the framed region), and two questions were added that only the collapsed
row can lose: *which file would you open to see screenshot 2 at full resolution*, and *where was
the pointer for 📸2*. One thing changes between arms and nothing else.

36 runs, 13 questions, Sonnet and Opus, six repeats each:

| envelope | chars | Sonnet | Opus |
|---|---|---|---|
| `victor` — a legend row per frame, what shipped | 1047 | 78/78 | 78/78 |
| `onerow` — the plain rows folded into `[📸n = …]` | 887 | **76**/78 | 78/78 |
| **`onerow_auto` — the same, plus ` auto` on 📸0** | **892** | **78/78** | **78/78** |

**He is right about the inference, and it is not close: `s2_full` is 36/36.** Every run of every
arm named `screenshot-2-original.jpg`, which means instantiating `n` *and* applying the
`-original` rule to a frame no row mentions. `mouse2` is 36/36 too.

**What folding costs is the one question the footer never answered.** *Which frame was automatic*
was always an inference — 📸0 has no gesture behind it — and both models said so in `unclear` in
**every** run of both rounds. While each frame had a row of its own, the inference held; with one
templated row Sonnet answered `none` twice out of six, and said exactly why: *"No screenshot
marker lacked a deliberate 🖱️/✂️ action tag, so I couldn't identify one taken automatically."*
Four out of six against six out of six is not significant on its own (Fisher, p ≈ 0.45) — it is
the models' own stated reasoning that makes it worth acting on rather than the count.

**So ` auto` ships with the fold**: five characters that turn the last guess in the envelope into
a fact, and the result is 78/78 on both models in **155 characters less** than the envelope it
replaces (−15%).

One scoring bug found and fixed in the same pass: `screenshots` expected `3` after the scene grew
a fourth frame, so it read 0/6 everywhere. Uniform across arms, so it never touched the
comparison — but it is exactly the kind of thing that would have.

**Even Sonnet reads the symbols perfectly**, and better than the prose they replace, in half the
characters. `current` loses three on `-original`'s resolution, which it never states. `shrunk` is
18% smaller again and costs Sonnet the one question that is *inferred* rather than said — which
frame was automatic — so **his template is what shipped**.

Both models, in every run, said the same two things in the free-text `unclear` field:

- **which frame is automatic is a guess** (📸0 simply has no press behind it). Right every time,
  still a guess: `[📸0🖱️@1000:800 auto]` would end it for five characters.
- **a gap in the numbering reads as a lost picture** — the sketch jumps 📸1 → 📸3. The shipped
  implementation numbers pictures consecutively as they attach.

## Running it

```
./build.py                 # renders the scene's artifacts with headless Chrome
./ask.py --repeats 6       # one `claude -p` per (envelope, model, repeat)
./score.py
```

`ask.py` stages each run in its own temp directory under the names *that* envelope refers to, so
the comparison measures comprehension and not filename guessing. Nothing of Victor's screen is
here: the scene is `page.html` rendered at 3456×2234.
