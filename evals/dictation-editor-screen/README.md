# ✍️ Does a screenshot help the dictation editor? (2026-11-21)

Victor: *"la nevoie, poți să-i trecuri și o poză … Poți să faci un mic eval să vezi dacă ajută … în terminal
mă mai ajută să vadă conținutul terminalului … foarte des promptez într-un Claude"*.

**Setup.** 42 of his dictated prompts (raw ElevenLabs / local-model text; prompts are never edited, so the
words are the recogniser's) whose context frame 📸0 is still in the shots cache — Chrome 17, Terminal 12,
PowerPoint 7, VS Code 3, Zoom 2, Finder 1. Two of them carry a mishearing an agent later taught
`walkie-dict` (`crisp → Krisp`, `UTH → OAuth`); for those the pair and the term are taken out of the
vocabulary, so a fix has to come from the screen. `build_cases.py` → `run.py`: Haiku in kept sessions (4 × 2
processes, as `DictationEditor` keeps one), the app's system prompt (`system.txt`, extracted from the Swift
source), vocabulary + replacements + speaker; **A** = no picture, **B** = + the 800 px frame and one rule
(use the screen only to spell what was said, never copy from it). `judge.py`: Opus, blind (edits in random
order), sees the frame, counts fixes and harms per edit, picks the better one.

| | fixes | harms | judged better | latency median / p90 |
|---|---|---|---|---|
| A — no picture | 64 | 10 | 8 | 0.96 / 1.52 s |
| B — + screenshot | 67 | 8 | 10 | 1.48 / 2.04 s |

24 of 42 judged the same. The targeted pair: `Krisp` fixed by both (the other occurrence of the
word in the same sentence was enough), `OAuth` by neither — both wrote `JWT`; the frame did not show it.

**Reading.** No measurable gain: +3 fixes, −2 harms, 10 vs 8 wins — inside what a second run of the same
arm would move (most A/B differences were not about the screen at all: `Mută` → `Mut`, a false start kept
or not). The picture's own effect cut both ways: one real fix (`DBKLI` → `db-cli`, the skill name on
screen) against two copies of the screen into his words (`segment` → `beam`, `Chrome` → `Victor
Chrome`) — the *Haiku copies the screen* failure of 2026-10-22 (`dictation-source.md`). And **+0.5 s at the
median** on every plain sentence. Not shipped.

**What this does not measure.** Neither arm had the Accessibility context the app sends (500 characters
around the caret, names, files) — it cannot be rebuilt for old prompts; that text is what already carries
the terminal's last lines in Terminal. The frame is 📸0, taken when he **started** speaking, not at the
delivery. 42 cases, one run each, one judge. A wider test would record the AX context and a frame at the
delivery for real plain dictations, and try Sonnet with the picture (it did not copy the screen in October).

## Round 2 — Sonnet, and the talk before the dictation (same day)

Victor: *"eval a sonnet too"*, then *"ar ajuta oare și un segment de transcriere de dinainte de prompt? din
transcrierea continuă … în cursuri vorbesc mult și poate s-ar prinde mai ușor din ce am vorbit deja"*.

- **Sonnet** = `MODEL=sonnet EFFORT=low run.py …` (the model `WT_EDITOR_MODEL=sonnet` switches to).
- **The talk before** = `build_pre.py`: victor-mac's continuous transcript
  (`addons-output/<day>-transcription.txt`, `[HH:MM]` lines, both microphones) from the 5 minutes before the
  dictation started, the dictation's own minute left out (the room transcript hears it too), last 1500
  characters. 1018 of his raw prompts since 2026-11-10 have ≥ 300 characters of it; 40 sampled. `CTX=pre
  run.py` puts it in `<earlier_speech>` with a rule like the screen's; the judge sees it as PRIOR, no picture.

| comparison (A → B) | fixes A / B | harms A / B | better A · B · same | latency median A → B |
|---|---|---|---|---|
| Sonnet: no picture → screenshot (42) | 91 / 99 | 12 / 14 | 8 · 11 · 23 | 1.55 → 1.61 s |
| Haiku → Sonnet, both no picture (42) | 61 / 89 | 11 / 16 | 7 · 20 · 15 | 0.96 → 1.55 s |
| Haiku: none → talk before (40) | 40 / 59 | 7 / 13 | 11 · 12 · 17 | 1.10 → 1.00 s |
| **Sonnet: none → talk before (40)** | 98 / 107 | **14 / 6** | **7 · 13** · 20 | 1.53 → 1.64 s |

**Reading.**
- **Sonnet edits better than Haiku** (20 sentences to 7; +28 fixes for +5 harms), for ~+0.6 s at the median.
- **The screenshot still buys nothing with Sonnet** either: +8 fixes, +2 harms, 11 vs 8 — noise.
- **The talk before helps Sonnet** — more fixes (+9) *and* fewer harms (14 → 6), 13 sentences to 7, at no
  latency cost (the text is ~400 tokens). It is the only context in this eval that moved the harms down.
  Examples from the judge: `hâderele` → `headerele`, `Danlua de azele` → `Download-ează-le`, *Fable*
  kept as the model name because the talk before named it.
- **With Haiku it is a wash**: +19 fixes but harms 7 → 13 — it translated an English sentence into
  Romanian after a Romanian minute (this run did not pass `<language>`, which the app does and which cut
  that failure in October), and copied a selected text's numbers into the words.

**Not proven yet.** One run per arm, one judge: a second run of the winning arm should come before a
switch. In the app the transcript lags (whisper writes a line when its chunk closes), so at delivery the
last ~10–30 s may be missing — the eval already left out the dictation's own minute, which is close.

## Round 3 — the confirmation run: the talk before does NOT hold (same evening)

Victor: *"run a thorough confirmation run. then implement the sonnet + speech if it proves right"*.
120 fresh prompts (`SEED=23 EXCLUDE=out/cases-pre.jsonl build_pre.py`, none from round 2), the same arms,
two blind judges (`JUDGE=fable` for the second).

| comparison (A → B), 120 cases | fixes A / B | harms A / B | better A · B · same |
|---|---|---|---|
| Sonnet: none → talk before, judge Opus | 253 / 262 | 27 / 38 | 38 · 30 · 52 |
| Sonnet: none → talk before, judge Fable | 242 / 257 | 49 / 78 | 44 · 29 · 47 |
| Haiku → Sonnet, neither with the talk, judge Opus | 140 / 241 | 49 / 35 | 16 · 65 · 39 |
| Haiku (none) → Sonnet + talk before, judge Opus | 146 / 248 | 48 / 44 | 20 · 64 · 36 |

- **Round 2's win for the talk before was noise** (40 cases, 13 vs 7). On 120, both judges prefer Sonnet
  *without* it (38 vs 30, 44 vs 29) and both count more harms with it
  (27 → 38, 49 → 78) for a handful more fixes. **Not implemented.**
- **Sonnet over Haiku is confirmed**: 65 sentences to 16, latency median
  0.99 → 1.44 s (p90 1.48 → 2.25 s).
- 40 cases and one judge is not a measurement here: the same arm pair flipped sign at 120.
- **Shipped 2026-11-22: Sonnet at low effort, without the talk before** (Victor: *"Treci la Sonnet ca
  redactor"*) — `DictationEditor.model` / `effort`, `WT_EDITOR_MODEL` / `WT_EDITOR_EFFORT` switch back.
