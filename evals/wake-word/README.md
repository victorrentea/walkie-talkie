# "Hey Claude" on his voice

`score.py <model.onnx> <16 kHz wav>...` — the peak wake score anywhere in each clip (1 s of silence
padded either side, a fresh `reset()` per clip). Run with the wake venv:

    ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/score.py ~/.walkie-talkie/wake/hey_claude.onnx <wavs>

## 2026-11-12 — gdiamos/hey-claude, before any take of his

| set | clips | result |
|---|---|---|
| `say` voices, "Hey Claude, I have a question." | 3 | Karen 0.995, Samantha 0.963, Daniel 0.001 |
| his corpus, every 30th clip (116 min) | 300 | **one ≥ 0.5**: 0.871 on "I just had to unblock you…" (2026-10-20/14-04-37-local445); next 0.019 |
| his corpus, *hey Claude* mid-sentence | 2 | 0.001, 0.014 |

So: ~1 false wake per 2 h of his speech at 0.5; whether it wakes on his deliberate *Hey Claude* is
unknown until he records some — then pick the threshold (or train on his voice).

## 2026-11-12 — "hey santa", a Whisper-encoder detector of our own

openWakeWord on synthetic voices was measured by greg1232/hey-claude at 59 % recall / 127 false
wakes an hour on real people; their replacement — Whisper tiny's encoder on a 2 s window, mean+max,
a logistic regression — did 84 % / 53. `train_whisper_wake.py` is that idea on **his** data:
positives `say` (14 voices × 3 rates × 3 pitches, 378 clips) in his own room tone; negatives his
corpus speech (1,800 windows), his room (800), 280 confusables (*Santa Claude*, *hey Sandra*,
*Fanta*, *hey Claude*…), two rounds of hard negatives. Held out: voices Ioana + Daniel, corpus days
≥ 2026-11-01 scored streaming (2 s / 0.4 s stride, 2 s refractory).

| threshold | recall (held-out voices, 54) | false wakes, 46 min of his speech |
|---|---|---|
| 0.50 | 91 % | 0 |
| 0.70 | 80 % | 0 |
| 0.90 | 65 % | 0 |

46 min resolves "< 1.3 an hour" at best. Shipped at **0.6** (`WT_SANTA_THRESHOLD`). Live in the
helper: ~1.5 s to run a 6.5 s file, ~450 MB resident with both detectors. Not yet scored on his
own *Hey Santa* — drop takes in `~/.walkie-talkie/wake/santa/real/*.wav` and retrain.
