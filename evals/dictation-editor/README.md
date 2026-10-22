# ✍️ The dictation editor — Haiku vs a local model (2026-10-22)

Victor: *"un model local n-ar putea face față acestei redactări?"* and *"mi se pare mult să mai aștept
încă o secundă și jumătate"*.

**Setup.** 200 of his Wispr Flow dictations since 2026-10-01 (Terminal 56, VS Code 56, Chrome 50,
PowerPoint 17, …; 122 en / 77 ro), each with Wispr's raw recognition (`asrText`), Wispr's formatted
text (the reference) and the context Wispr saved (500/500 around the caret, its screen nouns, its
dictionary). `bench.py` builds the editor's exact message (`DictationEditor.message`, `system.txt`
extracted from the Swift source) and runs one model; `score.py` scores against Wispr's text.
`out/` holds his words: ignored (public repo).

**Result, as the app delivers it** (an edit refused by `acceptable` → the raw words):

| | refused | WER→Wispr | CER→Wispr | sentences better / worse | latency median / p90 |
|---|---|---|---|---|---|
| no editor (raw) | — | 10.3 % | 8.7 % | — | — |
| Haiku, session, as shipped | 5 | 10.7 % | 8.8 % | 44 / 48 | 1.46 / 2.59 s |
| Haiku + "never translate" | 9 | 11.3 % | 9.4 % | 44 / 46 | 1.49 / 2.29 s |
| **Haiku + `<language>`** | 2 | **10.1 %** | **8.6 %** | **61 / 43** | 1.54 / 2.19 s |
| Qwen3-4B-Instruct, 4-bit, local, zero-shot | 2 | 10.7 % | 9.1 % | 32 / 33 | 2.10 / 4.16 s |

- **Haiku translated** English dictations into Romanian (5/200, 9/200 with a rule against it): the
  long session is full of Romanian. Telling it the recogniser's language cut it to 2; the word-overlap
  guard (`keptShare` ≥ 0.5 — Wispr's own most drastic edit kept 60 %) refuses the rest.
- **The local model is not faster**: it has to write the whole sentence back, ~50 tokens, and a 4 B
  model on the M1 Max takes 0.6–4 s for that. Zero-shot it barely edits, and once copied a vocabulary
  name into the sentence.
- The reference is Wispr's style, not ground truth; on Wispr's own (already good) recognition the
  editor's gain is small. Raw ElevenLabs / local-model text has more to fix.
- **A fine-tuned small model is the remaining road**: 17,056 of his raw→formatted pairs (with context)
  sit in Wispr's DB; a 0.6–1.7 B model trained on them would be both closer to Wispr and ~2× faster.
