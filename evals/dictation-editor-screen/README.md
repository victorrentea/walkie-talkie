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
