# crop-ocr — should a text crop travel as text?

**The question** (Victor, 2026-11-22): he drags an area (`📸n✂️x,y→x,y`, `screenshot-n.jpg`) more and
more often instead of highlighting text, and the area is often just text. Would OCR on the cut-out —
local, or a cheap model — with the text put straight into the prompt save time and tokens, because
the agent would not have to open the picture?

**The answer: no, not as a token saver, and barely as a speed-up. Do not build it now.**

- **There are no pixels to save.** A crop is tiny: median **57 tokens** to open (51 over all 1,634
  areas in the outbox), against 21 for its OCR text. The area token itself is ~15.
- **What a look really costs is the round trip, not the picture**: ~5 s and ~$0.02 when the agent
  stops to look before doing anything else. That happens on **30 %** of area prompts — and text in
  the prompt only removes it when the crop is text (**42 %** of crops), the agent agrees not to look
  (it does not, unless the rules tell it to), and the OCR is right.
- **Apple Vision is not right often enough to be trusted blind**: exact on **12 of 38** real text
  crops, `O→0` / `I→l` / `|→1` in code, icons and emoji dropped or invented, and **confidence 1.0 on
  the wrong lines**. Haiku reads far better (25/38 exact, 0 % on code) and would fit in the
  background, but that is a model call per crop to save a look on roughly one area prompt in eight
  (30 % × 42 %, if the two are independent).
- **The behavioural eval agrees**: with the OCR text beside the token the agent still opened the
  picture 8/8 (hedged row) and 5/8 (plain row); told the text replaces the look, 4/8. Median wall
  6.8 → 6.0 s, cost $0.217 → $0.213.

Everything below is measured on his own data on 2026-11-22. Raw per-crop results are in `out/`
(gitignored — private screens); only scripts and numbers are committed.

## 1. What exists today

- A drag writes three files: the display (`-original`), its 800 px copy, and **`screenshot-n.jpg`,
  the box cut out unscaled** (`ScreenCapture.writeRegionCopy`). The envelope carries only the token
  `[📸n✂️x1,y1→x2,y2]`; rules v3 (`AgentRules.text`) tell the agent the cut-out exists and to *look
  at that first*. Nothing is paid for the picture until the agent Reads it.
- **The app OCRs nothing.** `Vision` is imported only by `FaceRead`; `DictationEditor`'s header
  mentions *OCR of the window* in a list of things considered, and reads the screen through
  Accessibility. The only OCR code is `evals/probes/ocr.swift`.
- `evals/text-vs-pixels.md` already settled the neighbouring question: whole-screen OCR costs the
  same as the 800 px picture and loses the layout; one line under the pointer is ~20 tokens and cut
  turns 12 → 5, with the agent correcting the OCR from the pixels in 2 runs of 3 — *text is a hint,
  the pixels are the authority*. Measured and deliberately not built (`docs/pointer-line.md`).

## 2. His crops

**Usage** (`~/.walkie-talkie/outbox.jsonl`, 5,074 dictations):

| month | dictations | with an area | with a highlight |
|---|---|---|---|
| 2026-09 | 1,643 | 1 % | 22 % |
| 2026-10 | 2,035 | 32 % | 15 % |
| 2026-11 (to the 22nd) | 1,042 | **41 %** | 13 % |

1,634 areas in all, 1.5 per area prompt (median 1, max 10). He is right about the shift.

**Size**, from the corners in every token (the whole history, not a sample): image tokens
p10 **6** · p50 **51** · p75 179 · p90 586 · p99 2,640; 64 % of areas are under 100 tokens, 87 % under 400.

**What is in them** — the 151 cut-outs still in the shots cache (`collect.py`; the cache keeps 300
frames, so this is **21–22 Nov only, mostly work on a website**), each read and labelled by Haiku
(`read_model.py`; Haiku and the reference model agree on the label for 26 of 38):

| kind | crops | share | image tokens, median | OCR chars, median · p90 |
|---|---|---|---|---|
| text-only | 25 | 17 % | 42 | 17 · 99 |
| mostly text (a little chrome) | 39 | 26 % | 56 | 35 · 267 |
| UI with text | 53 | 35 % | 100 | 28 · 416 |
| pictorial (text absent or incidental) | 34 | 23 % | 36 | 0 · 41 |

So **42 % are text**, and the text is short: 77 % of those are ≤ 80 characters, 98 % ≤ 300. Two of
four spot-checked by eye were a photo or a thumbnail *with* words on it — the words alone would have
said the wrong thing about what he was pointing at. 53 of 151 have a line sliced by the box's edge.
A free classifier — Vision's text boxes covering ≥ 30 % of the crop — finds the text crops at 84 %
precision, 59 % recall (≥ 15 %: 68 % / 89 %).

## 3. How well each reader reads

Reference = the session's top model (Fable 5.2) reading the same file, 38 real crops with text
stratified over prose / UI / Romanian (`read_model.py --model fable`, `score.py`); 4 of 4 checked by
eye were right. CER is on whitespace-collapsed text; *word recall* ignores order.

| stratum | n | Vision `.accurate` CER med / mean · recall · exact | Vision `.fast` | Haiku 5.5 |
|---|---|---|---|---|
| all real crops | 38 | 4.9 % / 15.7 % · 86 % · **12/38** | 12.0 % / 23.4 % · 65 % · 7/38 | 0.0 % / 7.3 % · 96 % · **25/38** |
| prose | 10 | 1.9 % / 4.4 % · 93 % · 3/10 | 6.1 % / 10.1 % · 70 % · 0/10 | 0.0 % / 2.4 % · 100 % · 8/10 |
| UI labels / mixed | 16 | 17.9 % / 24.4 % · 82 % · 5/16 | 24.3 % / 31.7 % · 63 % · 4/16 | 0.0 % / 11.9 % · 91 % · 10/16 |
| small text (line box < 26 px) | 33 | 4.1 % / 13.7 % · 87 % · 7/33 | 23.5 % / 26.1 % · 59 % · 3/33 | 0.6 % / 8.2 % · 99 % · 16/33 |
| a line cut by the edge | 24 | 17.9 % / 26.9 % · 73 % · **0/24** | 30.8 % / 42.0 % · 47 % · 0/24 | 5.8 % / 14.2 % · 95 % · 5/24 |

(The last two rows include 11 bands cut at random from full frames by `synth_mono.py`.)
`usesLanguageCorrection` changes nothing measurable (16.3 % mean against 15.7 %).

**Code, terminal output and Romanian, against exact truth** (`render_known.py`: eight texts rendered
in Menlo / Helvetica — his real crops of that day held almost no code, so this stratum is synthetic):

| sample | font px | Vision `.accurate` | `.accurate` + correction | `.fast` | Haiku |
|---|---|---|---|---|---|
| Java, retina | 24 | 2.7 % | 4.5 % | 12.4 % | 0.0 % |
| shell | 24 | 4.2 % | 4.2 % | 17.8 % | 0.0 % |
| JSON | 24 | 0.6 % | 0.6 % | 35.4 % | 0.0 % |
| stack trace | 22 | 0.3 % | 0.8 % | 8.7 % | 0.0 % |
| Java, non-retina | 12 | 6.6 % | 8.0 % | 24.1 % | 0.0 % |
| shell, small | 18 | 1.8 % | 3.1 % | 7.2 % | 0.4 % |
| Romanian prose | 28 | 2.6 % | 2.1 % | 20.5 % | 0.0 % |
| Romanian, small | 18 | 0.7 % | 0.7 % | 14.3 % | 0.0 % |

What Vision gets wrong, in order of how much it matters:

- **Identifiers**: `O→0` (×3), `I→l`, `|→1`, `{→1`, `->` → `→` in the code samples; a digit `0` read
  as `O` inside a real file name. These are exactly the characters a grep or an edit depends on.
- **Icons and emoji** are dropped or turned into a character (`/`, `§`, `®`, `v` for a tick, `*` for
  `✳`); two tiny crops came back empty.
- **Lines sliced by the box** come back as plausible wrong words — 0 of 24 exact.
- **Romanian**: `.accurate` keeps the diacritics (10/11 on real crops, `ș` as the cedilla form
  `ş`); **`.fast` has no Romanian at all** — every `ă ș ț â î` flattened. `.fast` is out.
- **Confidence does not flag any of it**: 44 of 49 crops had every line at confidence 1.0, and 20 of
  those 44 were over 5 % CER.

## 4. Token math

Measured through `claude -p` usage on Opus 5.5 (`measure_tokens.py`), not taken from the rule:

| what the agent reads | tokens |
|---|---|
| a 48×36 crop | 18 |
| 160×44 | 26 |
| 311×94 (his median crop) | **62** |
| 640×190 | 175 |
| 1150×560 | 854 |
| 1600×1000 | 2,102 |
| 2400×1400 (fitted to ~2000 px by the Read tool) | 3,086 |
| 1,000 chars of his crops' OCR text | **499** (2.0 chars/token) |

This is the documented `⌈w/28⌉ × ⌈h/28⌉` plus ~14 for the tool result — `w×h/750` is the same thing
for large images and reads low under ~300 px. His crop text tokenises at **2.0 chars per token**
(fragments, numbers, symbols), worse than the 2.79 `text-vs-pixels.md` measured for UI text.

Per crop, over the 151 on disk: opening the picture costs **57 tokens median (200 mean)**; its OCR
text in a row costs **21 median (46 mean)**, and is cheaper than the picture in 150 of 151. For the
text crops under 300 characters: 40 tokens of text against 82 of picture.

**The other side.** Agents do not open every crop (`read_rate.py`, Claude Code transcripts, main
sessions; an open through a subagent or a glob is not seen, so these are floors):

| since | area prompts | areas | cut-out opened | any file of that shot | prompts opening none |
|---|---|---|---|---|---|
| 2026-10-01 | 953 | 1,391 | 63 % | 69 % | 23 % |
| 2026-11-13 (rules v3) | 241 | 360 | 64 % | 69 % | 26 % |

On the 21–22 Nov crops themselves: text crops were opened **20 of 54**, pictorial 18 of 30, UI 23 of
44 — the agent usually did not need the text crop at all. Always inlining would therefore *add*
~21–46 tokens on the 31 % never opened and *save* ~36–150 on the 69 % that are — a net of a few tens
of tokens per crop either way, inside a request that re-reads a median **96,000** tokens of context.
There is no token case for or against.

**What a look costs beyond its pixels** (`turn_cost.py`, 440 area prompts since 1 Nov):

| the agent's first tool-calling message | prompts |
|---|---|
| other work — the picture later or never | 231 (52 %) |
| **the picture and nothing else** | **133 (30 %)** |
| the picture in parallel with other work | 70 (16 %) |
| no tool call at all | 6 (1 %) |

For the 124 picture-only looks with a measurable follow-up: the look is issued 2.7 s after the prompt
(median); the next request's first block lands **5.3 s** after the tool result (p25 3.1, p75 6.9,
p90 10.5 — an upper bound on what is saved, since that block's thinking would happen anyway); that
request re-reads a median 96,354 tokens of cached context (p75 224,676) and the look itself is 212
output tokens. At Opus 5.5 prices ($0.20/MTok cache read, $20/MTok output) that is **~$0.024 a look**.
That — not the 57 tokens of pixels — is the whole prize, and it is on the table for 30 % of area
prompts × the share that are text × the share the agent then really skips. On the 21–22 Nov sample
only 3 of 75 prompts began with a picture-only look.

## 5. Latency

| reader | per crop | where it could run |
|---|---|---|
| Vision `.accurate`, en + ro | p50 **20 ms**, p90 63, max 129 (first call of the process 176) | anywhere |
| Vision `.fast` | p50 6 ms | — (no Romanian, 65 % recall) |
| Haiku 5.5, `claude -p`, lean flags, cold process | wall p50 **4.0 s**, p90 6.4 (API 2.9 s); $0.0017 a crop | background only |
| the main agent's own look | ≤ 5.3 s median, 30 % of area prompts | — |

**Nothing needs to wait at the stop.** The cut-out is on disk long before the envelope is built:
crop written → prompt delivered was p10 8.6 s, median **17 s**, never under 1 s over 131 crops. Either
reader finishes while he is still talking; a Haiku answer that is late would simply be left out.

## 6. Behavioural eval

`behave.py`: 8 of his text crops (4 where Vision slipped, 4 where it was exact), 5 asked for verbatim
(*type out exactly what this box says*), 3 for the gist, each delivered four ways to a headless Claude
Code session on Opus 5.5 with the installed rules v3 — 32 runs, $6.94 notional.

| variant | opened the picture | wall, median | input tokens, median | output | cost | verbatim exact | gist right |
|---|---|---|---|---|---|---|---|
| `pic` — today's envelope | 8/8 | 6.8 s | 72,292 | 373 | $0.217 | 3/5 | 3/3 |
| `text+pic` — OCR row, hedged (*may misread, the picture is the authority*) | 8/8 | 7.0 s | 72,634 | 361 | $0.215 | 3/5 | 3/3 |
| `text` — OCR row, plain | 5/8 | 6.3 s | 72,476 | 316 | $0.214 | 3/5 | 3/3 |
| `text-first` — row says *use it instead of opening the picture* | 4/8 | 6.0 s | 72,441 | 284 | $0.213 | 3/5 | 3/3 |

- **A hedge buys nothing**: told the text may be wrong, the agent looks every time, and the row is
  pure overhead (+210 characters).
- **Without the look, the saving is real only when the run becomes one request**: 2 of the 7 runs
  that did not open the picture finished in 1 turn, 3.4 s and 36,000 input tokens against 6–7 s and
  72,000. The other 5 still reported 2 turns (not investigated).
- **Asked for exact characters, the agent looks whatever the row says** (19 of 20 verbatim runs) —
  the right instinct, and the reason no OCR slip reached an answer here: the two non-exact verbatim
  cases are the same two crops in every variant, `pic` included, 0.4 % and 1.4 % off the reference
  on lines sliced by the box (one `text` run 2.9 %; one `text-first` answer added a remark). The gist was right 12/12 with or without the picture. **Not measured:** an edit task where a
  misread identifier is trusted — the eval's asks were too honest to provoke it.

## 7. The options, weighed

| option | verdict |
|---|---|
| always inline OCR text beside the token | No. 58 % of crops are not text; ±tens of tokens; adds wrong text with full confidence. |
| inline only when text-ish and short (coverage ≥ 30 %, ≤ 300 chars) | The only form worth considering. Saves at most one ~5 s look on a minority of prompts, and only with a rule telling the agent to trust it. |
| inline text **and** keep the picture as the authority | What `text-vs-pixels.md` recommends for the pointer line — but for a crop the eval shows the agent then looks anyway (8/8), so nothing is saved. |
| Haiku instead of Vision, in the background | Accurate enough (0 % on code), fits the 8–17 s before the stop, but a model call per crop (30 a day on average this month, 150 on a busy one) to save a look on about one area prompt in eight. |
| never | **Recommended for now.** |

What a text row loses: layout, colour, which element is the highlighted one, the icon or photo the
words sit on (two of four crops checked by eye), and the agent's own chance to read the pixels
correctly — Opus reads a crop better than Vision does.

What it costs to change: a new row is a new instruction, so `AgentRules.text` gains a line and
`version` goes to 4; every running agent falls back to the long envelope until it holds v4, and
`evals/agent-rules/run.py` must be re-run on the three harnesses (~$15 notional on Claude alone).

## If it is built anyway

The cheap, honest shape — a hint that sometimes saves a look, never a replacement:

- **Where:** `ScreenCapture.writeRegionCopy` already has the cut-out in memory; run one
  `VNRecognizeTextRequest` (`.accurate`, `["en-US", "ro-RO"]`, no language correction) on the queue
  that writes it, never on the shutter path, and keep the result beside the area in `Message`
  (outbox `areas[].text`). Nothing waits for it: absent at the stop → no row.
- **When:** text boxes cover ≥ 30 % of the crop, 8–300 characters, every line at confidence 1.0, no
  box touching the crop's edge (the sliced lines are the wrong ones). On the sample that gate passes
  **26 of 151 crops (17 %)** — and of the 10 of those that have a reference, Vision was exact on 1 and
  over 5 % CER on 4. The gate picks text crops; it does not pick the ones Vision read right.
- **Envelope:** a footer row per qualifying area, `[📸1✂️ "…"]`, lines joined with ` ⏎ `, clamped like
  a selection (`clampForTerminal`). One line in `AgentRules.text` (v4): *a `[📸n✂️ "…"]` row is that
  box read by OCR — enough for what it says; open the picture for layout, colour, or before you copy
  an identifier from it.* `AgentRules.needed` returns 4 only for a prompt that carries such a row.
- **Then measure it where it matters**: `evals/agent-rules` with two new cases (a text box answered
  without the look; an identifier with an `O/0` trap that must trigger the look), and `turn_cost.py`
  a week later — the share of picture-only looks should fall from 30 %, or it comes out again.

Est: 2-3h of Opus 5.5 for $20-35 (the agent-rules re-run included).

## What could not be measured

- **Older crops**: the cache holds 300 frames, so content was classified for 21–22 Nov only (a
  website, little code). Sizes and open rates cover the whole history; kinds do not.
- **Real code crops**: none to speak of in the sample; the code numbers are rendered text.
- **The reference is a model**, checked by eye on 4 crops; on lines sliced by the box even two strong
  readers disagree.
- **Codex and Copilot** transcripts were not scanned for open rates (Claude Code only).
- **The 5.3 s** is time to the next request's first block, thinking included — an upper bound.
- **A misread trusted in an edit** — see the eval's last bullet.

## Reproducing

```sh
python3 evals/crop-ocr/collect.py                              # out/crops/ + out/crops.jsonl
swiftc -O evals/crop-ocr/ocr.swift -o /tmp/crop-ocr
/tmp/crop-ocr evals/crop-ocr/out/crops/*.jpg > evals/crop-ocr/out/ocr.jsonl
python3 evals/crop-ocr/read_model.py --model haiku             # label + read every crop
python3 evals/crop-ocr/read_model.py --model fable --ids evals/crop-ocr/out/reference-ids.txt
python3 evals/crop-ocr/score.py                                # the accuracy table
python3 evals/crop-ocr/render_known.py --ocr /tmp/crop-ocr --haiku
python3 evals/crop-ocr/measure_tokens.py --model opus
python3 evals/crop-ocr/read_rate.py --since 2026-10-01
python3 evals/crop-ocr/turn_cost.py
python3 evals/crop-ocr/behave.py && python3 evals/crop-ocr/behave_report.py
```

Every model call is `claude -p` on the subscription; no image leaves the Mac any other way. The
whole study: 165 Haiku reads ($0.28 notional), 52 Fable reads ($5.51), 32 eval runs ($6.94).
