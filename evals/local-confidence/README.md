# 🎤 — when is the local model unsure? (2026-10-22)

Victor: *"când confidence pentru voice-to-text transcription pe model local e mic, să termine
orice dictare curată cu iconul unui microfon"*.

**Setup.** 400 takes he dictated on Wispr Flow / ElevenLabs between 2026-10-04 and 10-22 (after
the Turbo LoRA was trained, so none taught it), 2–60 s, decoded again by `whisper-turbo-victor`
through this repo's helper (`decode.py`). Reference: the cloud text — Wispr's *formatted* text,
so a good take still scores ~15 % WER; median WER here 18 %. 395 decoded.

**Result** (`analyze.py`), bad = WER ≥ 30 % (26 % of takes):

| signal | floor | takes flagged | of those, bad |
|---|---|---|---|
| worst segment (`avg_logprob`, the existing gate) | −0.25 | 15 % | 36 % |
| worst segment | −0.3 | 9 % | 35 % |
| **whole-take mean (`mean_logprob`)** | −0.2 | 19 % | 41 % |
| **whole-take mean** | **−0.25** | **9 %** | **54 %** |
| whole-take mean | −0.3 | 4 % | 71 % |

The worst segment is no better than chance at any floor: a 30–60 s take always holds one shaky
segment, so it flags the long takes, which are mostly fine; the takes that are wrong as a whole are
short and low throughout. The helper now also sends `mean_logprob` — each segment's `avg_logprob`
weighted by its tokens — and the app's floor is **−0.25** (`LocalWhisper.micFloor`): about one plain
dictation in eleven ends with 🎤, and more than half of those really are wrong (the reference's
formatting makes that an underestimate).

`out/` holds the decodes — Victor's words, so it is ignored (public repo).
