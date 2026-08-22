# Reading the screen as text instead of sending the picture

**The question.** A relay message is mostly pixels — one to seven frames at
861 tokens each since `handoverWidth = 1000`. macOS can hand us the same screen
as *text*, two different ways: the Accessibility tree (what VoiceOver reads) and
Vision OCR (what Live Text reads). Both are free of API cost and run locally.
Is either of them a cheaper way to say what is on the screen?

**The answer, in one line: no — not for the whole screen, and yes — for the
one square inch under the pointer.** Whole-desktop text costs *the same as the
picture* and throws away the layout the picture was carrying. Pointer-local text
costs ~1/40th of the picture and answered the pointing fixture 3/3.

Everything below was measured on the same frames the other evals use, still on
disk in `~/.Trash/shots` (`Outbox.retireLegacyShots` moved them there, which is
the second time that decision has paid for itself). Probes are in
`evals/probes/`; token counts are `o200k_base` as a stand-in for Claude's
tokenizer, so read them as ±10%, and image counts come from the `width ×
height / 750` rule the other evals validated.

## What a frame costs, every way we can send it

| what travels, per frame | tokens | where the number is from |
|---|---|---|
| retina JPG, 3456×2234 | 3,450 | `results.jsonl`, `offered_tokens` |
| **1000px JPG — today** | **861** | `results.jsonl`, `offered_tokens` |
| 800px JPG | 551 | the `w×h/750` rule |
| 700px JPG | 422 | the `w×h/750` rule |
| Vision OCR, flat text, whole desktop | **890** (816–995 over 7 frames) | this study |
| Vision OCR + a normalized box per line | **2,096** | this study |
| **the one line under the pointer** | **10–30** | this study |
| window title (`sources`, already sent) | ~8 | already in the line |

The three OCR rows are the whole study. A Gmail desktop OCRs to ~2,500
characters, and UI text tokenizes badly — **2.79 chars per token**, not the ~4
of prose, because it is fragments, counts, dates and symbols rather than
sentences. 2,500 characters of that is 890 tokens, which is the same 861 the
picture already costs.

## Three findings

**1. Whole-screen text is not cheaper than the picture. It is the same price.**
Within noise, frame for frame. The intuition that "text is cheap, images are
expensive" is a statement about *retina* images — it stopped being true the day
`handoverWidth` went to 1000. There is no saving here to collect.

**2. The moment you make the text answer the question, it costs 2.4× the
picture.** `unsubscribe` asks who sent the mail **open in the reading pane on
the right**. That is a spatial fact. Flat OCR of all seven frames contains all
seven sender names in *every single frame* — the inbox list on the left is in
the picture too — so the flat text discriminates nothing:

```
frame 1: DZone/FAN Courier/H&M/SHEIN/Sezamo/Shakespeare
frame 2: DZone/H&M/SHEIN/Sezamo/Shakespeare
...
frame 7: DZone/H&M/SHEIN/Sezamo/Shakespeare
```

Seven frames, one differing token between them. To recover "on the right" you
have to ship a coordinate with every line, and that is the 2,096-token row —
**more than twice the picture, to say less than the picture says**. A screenshot
is a very good compression of a layout. That is what it is *for*.

**3. The line under the pointer is nearly free, and it is the whole answer to
the question Victor actually asks.** On the `pointed` fixture — three shots, the
cursor coordinate already in each file name — OCR plus a nearest-box lookup at
that coordinate returns:

| shot | cursor (px in frame) | line returned | key |
|---|---|---|---|
| 1 | 580,1119 | `DO NOT COPY TEXT TO/FROM CODING AGENT. have that agent reach for the data itself.` | ✓ |
| 2 | 1171,766 | `for architecture/review` | ✓ |
| 3 | 884,1863 | `→in browser/sql LIMIT OFFSET` | ✓ |

3/3, at 23–83 characters a shot. The same quotes the model returned from the
pixels, including the `LIMIT OFFSET` line that every image variant got
byte-identically. **~20 tokens against 861.**

And it does not repeat the mistake `small-crop` made (0.87, sequence scrambled):
a crop is a *second picture per shot*, and the evals showed two pictures per
shot break the ordering. A quoted line is not a picture. It rides in the same
clause as the file name, which is where the offset and the cursor already live.

## This already exists — for Chrome, behind a deliberate gesture

`chrome-extension/inspect.js` sends `text: elementText(el)` with every ⌘⇧-click
pick, truncated to 160 characters, precisely because a bare CSS selector has
"nothing to recognise it by". And `SelectionCapture.readQuiet` takes what is
highlighted at every shutter press, through the Accessibility API, for free.

So the relay already reads text off the screen in two of the three places it
could. What is missing is the third and most general: **he points at things far
more often than he ⌘⇧-clicks them, and pointing is what mouse 4 already
records.** The cursor coordinate is in the file name and nothing reads it back.

## The Accessibility route, and why there is no number for it here

The AX tree is the better *shape* — it is a tree, so "the reading pane" is a
subtree rather than an x-coordinate, and it carries roles and states OCR cannot
see. It is also what a real screen reader uses, which is what the question asked
about.

**It could not be measured from this session.** `AXIsProcessTrusted()` returns
true, but every window handed back reports role `AXApplication` with the
application's own attribute list — the stub tree an untrusted client gets —
and System Events sees zero windows for every app. The TCC database says why:

```
com.anthropic.claude-code   0     ← denied
com.apple.Terminal          2
ro.victorrentea.wispr-relay 2
```

Two ways to get the number: tick **Claude Code** in System Settings → Privacy &
Security → Accessibility, or run `evals/probes/axdump.swift` from inside the
relay, which is already trusted.

**What to expect when it is measured**, so the result can be checked against a
prediction rather than rationalised afterwards:

- The AX tree of a Gmail tab will be **larger than its OCR**, not smaller — it
  contains every row's `aria-label`, every button name, every date, including
  what is scrolled out of view, where OCR sees only what is on the glass. Call
  it 3–10×, i.e. 3,000–9,000 tokens: worse than retina.
- Coverage is uneven in exactly the apps he uses. Native Cocoa (Terminal, Mail,
  Finder) is complete; Chrome builds its renderer tree lazily on first query and
  is complete once it does; VS Code exposes a tree only in screen-reader mode;
  IntelliJ needs *Support screen readers* on and is partial even then. A frame
  is never unavailable; a tree often is.
- A **hit test** — `AXUIElementCopyElementAtPosition` at the cursor, then the
  element's value plus a parent or two — is the AX shape of finding 3, and is
  the one AX variant worth building. It is more precise than OCR (it gets a
  form field's value, a truncated label's full text) and it degrades to nothing
  in the apps above, where OCR still works.

## What is worth doing, in order

1. **Eval `small-800` and `small-700`.** One constant, no new code, and the
   image bill drops 36% / 51% if it holds. As a cheap proxy: OCR of the retina
   frame stays clean down to 700px wide and collapses at 600 (`»in browser/sql
   LIMIT OFFSET` → `San broawry Cane uorare`), and the Gmail sender names
   survive to 600. Claude reads worse-than-OCR text better than OCR does, so
   700 is a plausible floor and 800 a safe one — but the evals decide, the same
   way they decided 1000.
2. **Eval `small-ptrtext`** — today's frame plus `[at pointer: "…"]` from the
   OCR hit test. +20 tokens; the question is whether accuracy on `pointed`
   holds at 1.0 while the frame shrinks under it.
3. **Then eval `ptrtext-only`** on `pointed` — the pointer line with no picture
   at all. 20 tokens against 861. This is the only variant that could take a
   real bite, and the only one likely to fail: `unsubscribe` would certainly
   fail it (the pointer was not on the sender), so it can at best become a
   per-shot decision, never the default.
4. **Do not dump the screen as text**, by OCR or by AX. It is finding 1 and 2,
   and it is the idea the question started from.

**And a ceiling worth stating.** On `unsubscribe/small` the seven frames are
6,027 of 29,349 fresh tokens — **the pictures are ~20% of the exchange**, and
the other 23,000 is the agent working. Retina → 1000px was a 39% cut because it
removed 18,000 tokens; there are only 6,000 left in there. 800px saves ~2,200,
about 7% of a real exchange. Worth taking, not worth a week.

## Cost of the OCR itself

`VNRecognizeTextRequest` on a 3456×2234 frame: **~650ms** at `.accurate`,
**~104ms** at `.fast` (which finds half the lines — 84 against 170 — so it is
not the setting for a full dump, though it may be enough for a hit test). It
finds the pointer line just as well on the 1000px copy as on the retina one, at
554ms.

650ms cannot go where the burned-in cursor mark used to be — that was removed
from the capture path for costing ~100ms. It goes *after* `screencapture`
returns, off the shutter path, on the queue that already writes the `-small.jpg`
sibling: the dictation is still running, and nothing needs the text until
`commit`.

## Reproducing

```sh
swiftc -O evals/probes/ocr.swift -o /tmp/ocr
/tmp/ocr ~/.Trash/shots/shot-2026-07-31-13-16-35.jpg          # flat text + stats on stderr
/tmp/ocr ~/.Trash/shots/shot-2026-07-31-13-16-35.jpg --boxes  # + a normalized box per line

swiftc -O evals/probes/ocrline.swift -o /tmp/ocrline
/tmp/ocrline ~/.Trash/shots/shot-2026-08-13-03-06-13-cursor-25.6x83.4pct.jpg 884 1863
```

`axdump.swift` is the AX walker, and returns the stub tree until the calling
process is granted Accessibility — which is itself the fastest way to check
whether it has been.
