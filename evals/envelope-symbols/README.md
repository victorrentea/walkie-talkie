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
./ask.py --repeats 3       # one `claude -p` per (envelope, model, repeat)
./score.py
```

`ask.py` stages each run in its own temp directory under the names *that* envelope refers to, so
the comparison measures comprehension and not filename guessing. Nothing of Victor's screen is
here: the scene is `page.html` rendered at 3456×2234.
