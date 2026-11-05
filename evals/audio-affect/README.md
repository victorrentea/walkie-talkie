# Audio-affect: `[voice: hesitant]` / `[voice: tense]` without words (2026-11-05)

`VoiceAffect` needs `words[]`, which only Scribe gives; Wispr Flow and the local model get nothing. Asked: can
the verdict come from the waveform alone? No recogniser, no timings.

Numbers below: 2,355 clips of his corpus with word timings (`voice-distill/runs/timing.jsonl`, Whisper turbo,
until 2026-09-26), trained and tested on different **days**. Scored by Victor's blind listening test the same
day: **read *His ear* first, it overturns both headline guesses below.** No transcript or audio in this folder is committed (`out/` is gitignored; the
repo is public).

## His ear: 40 clips, blind (2026-11-05)

| stratum | heard as | |
|---|---|---|
| audio or word verdict hesitant, not skipped | hesitant 5 of 19 | word verdict 4/13, audio verdict 4/14 |
| of which audio-only | hesitant 1 of 6 | plus 2 skipped: he was **whispering** |
| neutral control | hesitant 1 of 5 | the base rate, roughly |
| top-decile arousal, annoyed words | **tense 5 of 5** | the words are audible, so not audio alone |
| top-decile arousal, calm words | **tense 2 of 5** | the case the tag exists for |
| low arousal, annoyed words | tense 1 of 3 | |
| every other clip | tense 0 of 24 | no false tense in the hesitant or neutral strata |

- **Hesitant: neither verdict beats the control.** About 30 % by ear against 20 %, on n = 13–14 (roughly 10–60 %).
  The rule measures silence, and silence is not hesitation. Porting it to audio would copy the error faster.
- **Tense: audio works, and the section below undersold it.** Top arousal is tense in 7 of 10, the rest 1 of 27.
  Text was the wrong yardstick. Still one listener, one run, 10 clips, and the arousal here is the big teacher;
  the cheap F0 + level replica is rho 0.935 against it but was not itself played to him.
- **Whisper breaks the meter**: both whispered clips were audio-only positives, quiet speech read as silence.
  Whispered takes need a guard; `level` is not normalised and the clips were played as recorded.

## What shipped: `tense_app.py` → `VoiceTension.swift` (2026-11-05)

Pitch only (level is the mic's as much as his), a small autocorrelation tracker, no praat. 1,748 of 1,759 clips have
3 s of pitched voice. Held-out days against the teacher's arousal: rho 0.815, top decile AUROC 0.888 (praat's F0
median alone: 0.90). **Against his ear, which this replica had not been played to, on 33 of the 40 clips: AUROC 0.905.**
At one sentence in ten: tense 4 of 6 over the bar, 4 of 27 under it. The bar was the study's top decile, chosen
before looking; the weights were not fitted on his labels. Still one listener, and over-represents tense clips.

## What the app can already hear

Wispr's dictation has the mic open beside it (`WisprFlowSource.feedOwnSentence`): `meter.meterHops` exists there
and the WAV lands in the corpus. So tier A costs nothing new, and raw samples are available for tier B. The
evidence is `WisprFlowSource.swift:554` and the corpus's `wispr-flow` rows; no change was made to the app.

| tier | input | new in the app |
|---|---|---|
| A | `meterHops` (64 ms RMS + voiced), `common.py:meter` is that meter replayed | nothing |
| B | Silero VAD (15.5 h of audio in 26 s on 8 cores) | a model |
| C | F0 (praat), filled-pause finder | a pitch tracker |

## Hesitant: it reproduces the word verdict, which his ear does not confirm

Truth = the app's own rule on Whisper's timings, 220 positives of 2,194.

| features | AUROC | recall at precision 0.8 | precision at recall 0.5 |
|---|---|---|---|
| A, hops | 0.902 | 0.34 | 0.64 |
| A + B, Silero | 0.922 | 0.39 | 0.69 |
| A + B + C | 0.925 | 0.33 | 0.67 |
| A, on clips where words and Silero agree | 0.952 | 0.60 | 0.82 |

Under the 0.8 precision the spec requires on the word truth, **but that truth is the weaker witness**:

| against Silero (Spearman) | word timings | app's meter |
|---|---|---|
| pause ratio | 0.686 | **0.816** |
| pauses over 1 s | 0.689 | **0.835** |
| longest pause | 0.816 | **0.919** |
| lead | **0.759** | 0.703 |

Whisper stretches words over short pauses (median pause ratio 0.11, Silero 0.19). The two rules, words and
Silero, agree on only 44 % of their positives (182 of 416). Agreement with Silero says the meter measures
silence well, not that a silence is hesitation.

- **The app's thresholds do not transfer**: the meter's pause ratio has median 0.51, words 0.11; the voiced gate
  drops quiet consonants. `0.35` would fire on most sentences.
- **`lead` is the meter's weak spot**: a click or a breath ends it early. Word lead > 3 s: 165 of 267 caught.
- **Rate survives**: voiced bursts per second, Spearman 0.81 with Scribe's words/s (78 joined clips), 0.69 with Whisper's.
- **Lost**: restarts, but only 16 of 227 verdicts needed them. Fillers cannot be judged: Whisper drops them, so
  this truth has none, and tier C's filled-pause finder is **unproven**, not useless.
- Silero's own 0.98 on the agreed set is circular (Silero is half that truth) and is not a result.

## `[?]`: not reliably, the pause cannot find its word

With no timings, the pause is placed by share of voiced time. 389 pauses ≥ 2.5 s, clips of ~61 words: **median
2.8 words off, 52 % within 3, 69 % within 5, p90 16.5**. Those are only the 261 clips of 830 where meter and
words count the same pauses (meter-only 698, words-only 137). The `[?]` is worth more than the tag exactly for
its place, so this is the weakest result. An untested option: run the local model with word timings only on
sentences that have such a pause.

## Tense: loudness and pitch are cheap, and the words are the wrong test

Teacher = audEERING w2v2 arousal, a yardstick only (CC-BY-NC-SA, 200 M parameters). 1,759 clips, normalised per
mic + language; `mic` is unknown for half of them, so that normalisation is partial.

- **Arousal is reproduced**: held-out Spearman **0.84** from hops, **0.935** with F0 (top decile AUROC 0.905 / 0.975). F0 median alone 0.90.
- **Arousal is not annoyance**: against Haiku reading the words (247 annoyed vs 1,037 neutral), AUROC teacher
  0.575, hops 0.551, hops + F0 0.564, the best single feature `f0_std` 0.632; duration is not the confound. The
  top arousal decile is 31 % annoyed against 12 % elsewhere.
- **Today's flag** (spread ≥ 9 dB): fires on 1.3 %, 22 % annoyed against 14 %, on ~23 clips. No per-mic baseline.
- The words are a poor yardstick by design: the tag exists for anger in calm words. A low AUROC here does not
  disprove tense, it just proves nothing. Haiku's labels were not checked by hand.

## Run

    uv venv --python 3.12 $V; uv pip install --python $V/bin/python numpy scipy scikit-learn praat-parselmouth torch silero-vad transformers soundfile
    python tier_a.py; python silero.py; python tier_b.py; python teacher.py; python text_labels.py 99999 <cwd>
    python arbiter.py; python hesitant.py; python place.py; python tense.py
    python listen.py build; python listen.py serve   # http://127.0.0.1:8767
    python listen.py score

`listen.py`: 40 clips, blind, no text; strata in `out/listen/key.json`.
