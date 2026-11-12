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
