# Decoding a long take in pause-cut chunks while he talks (2026-10-21)

What the local model loses in words, and gains in wait, when a take is decoded as chunks cut at
Victor's pauses (`ChunkPlanner` + `LocalWhisperSource`) instead of whole after the stop.

## Recommendation

1. **Fix the word timings on chunks first: it is the one finding that blocks shipping.** The relay
   sends every chunk as `{"pcm", "words": true}`. With `word_timestamps=True`, mlx_whisper moves
   `seek` to the last word's end and decodes what is left of the clip, the pause the chunk was cut
   in, as a new window. That window hears a farewell: `La revedere!`, `Da, da.`, `Mare!`,
   `Bine ați venit!`. **82 of 119 chunks** (default rule) came back with such a tail, and pooled
   WER went **13.1 % → 18.2 % (+5.1 pt, CI +3.6…+6.8)**, with insertions at 170 against 73 for
   the whole take. The cure, measured: **keep only the first window's segments**
   (`seg["seek"] == 0`) when the clip fits in one 30 s window. WER goes back to the plain-text
   number (**14.1 %**), with 0 stock phrases. It belongs in the helper or in `join`. Things that do
   *not* work: `hallucination_silence_threshold` 1 or 2 (no change, because its `window_end_time`
   is the 30 s window and not the clip), and dropping words that start after the voice ends
   (+4.2) or in the clip's last 0.5 s (+3.2) or 1 s (+5.5), because Whisper stretches the
   invented words across the whole pause. The alternative is to ask words for a chunk only when a
   cue is pending, as the whole take does. The words also cost **×1.69** decode time on chunks
   (measured back to back, 119 chunks), not the +45 % measured on whole takes.
2. **Parameters: `trigger 10, minGap 0.9, minChunk 8`** (keep `hardCap 28 / capGap 0.3`,
   `minVoiced 2`, `ongoingPad 0.4`), **plus the previous chunk's last sentence as extra prompt
   context.**
   - **WER: 12.6 % chunked vs 13.1 % whole (−0.5 pt, 95 % CI −2.0…+0.8)**, so no measurable
     loss. Romanian 19.6 vs 20.6, English 3.7 vs 3.5. Without the context: 12.7 %.
   - **Wait after the stop, priced with the app's own decode line: 3.86 s → 2.35 s mean
     (−39 %), median 3.65 → 2.26, p90 4.69 → 2.91.** Measured directly at low load (20 takes,
     plain decodes): whole 3.38 s → tail 1.40 s. Still decoding a chunk at the stop: 11 of 40
     takes (the last cut is often decided within the last 2 s).
   - 2.3 chunks per take, never shorter than 8 s; tail 7.6 s mean; 8 of 40 tails dropped
     (< 0.3 s voiced).
   - The shipped default (`10 / 0.6 / 6`) costs **+0.9 pt (CI −0.2…+2.2)**, waits 2.60 s mean,
     and has 17 of 40 takes still decoding a chunk at the stop.
3. **The tail can skip its language-ID pass.** `pick_language` is a separate encoder pass:
   **0.56 s of the tail's 1.40 s** (20 takes, low load). The chunks already know the language,
   so passing it to the tail would bring it to about 0.85 s.

The direction is consistent across the sweep: **bigger chunks cut at longer pauses lose less.**
`minChunk 4` costs +1.6 to +1.9 pt with CIs clear of zero, `minGap 0.4` +1.5 to +2.1, while every
`minGap 0.9 / minChunk ≥ 8` point is at or below the whole take. In his words, *don't feed too
small chunks*. The worst chunk seen was 2.5 s voiced in 10 s: `subagentul` invented twice. The
vocabulary prompt has nothing to bias against in a short chunk. A cut at a 0.6 s pause often lands
mid-thought (`…deci trebuie ca | acel overlay…`); a 0.9 s pause is between thoughts more often.
`minVoiced 4` alone (`t10-g0.6-c6-v4`) gets +0.1, with fewer chunks.

## Setup

- **Takes:** 40 from the LoRA's held-out slice (`~/workspace/voice-distill/eval/heldout.json`,
  never trained on), all > 25 s. 22 Romanian and 18 English, stratified by duration, 25–59 s,
  1,420 s of audio, 1–7 chunks each under the default rule.
- **Reference:** `ref_asr`, Wispr Flow's raw recogniser text for the same WAV. It is independent of
  this model and carries no `Screenshot N:` markers. Scored after normalisation: lowercase,
  punctuation stripped, Romanian diacritics folded (ș/ş→s, ț/ţ→t, ă/â→a, î→i). Both arms are
  scored against the same reference, so its own errors cancel out of the delta. Pooled WER, with
  a paired bootstrap (2000×) of the delta per take.
- **Model and decode:** `~/.walkie-talkie/models/whisper-large-victor` (his Engine pick since
  2026-10-20 12:19), through the helper's own `transcribe` (imported from
  `helpers/whisper_helper.py`). That means the LID pin, the vocabulary prompt by language, the
  loop ladder, the no-prompt retry and `cut_loops`. Whole = the take's samples; chunk = the
  same samples sliced at the cut.
- **The cut rule** is `ChunkPlanner.cut` ported line for line (`cut_at`) and asked on the relay's
  0.5 s tick. The meter is `VoicedMeter`'s arithmetic, as in `evals/voiced-seconds.py`. The tail
  is dropped under 0.3 s voiced once a chunk exists. Texts are joined with one space.
- **Context variant:** the helper's `transcribe` takes no prompt argument, so the script swaps the
  module's `VOCABULARY` / `VOCABULARY_RO` for the call: vocabulary, then the previous chunk's
  last sentence (≤ 30 words; two sentences if the last one is under 4 words). The
  previous-sentence part sits at the tail end of the prompt, where Whisper weighs it most.
- **The wait.** The helper is simulated as serial. A chunk is handed over when its cut is
  *decided* (the tick, which is later than the cut point) and costs ×1.69 for its words. The tail
  starts at max(stop, helper free). Two prices:
  - **App speed**: `decode = 1.60 s + 0.064 × audio`. That is Theil–Sen over the 200 warm
    whisper-local decodes in `decode-rate.jsonl` since the large model went in (loops excluded).
    This is the headline.
  - **Measured**: this batch's own decode times. They are 3–4× slower than in normal use, because
    it ran at `nice 19` beside his day's work: load average 250–400 for most of the run, 6 at the
    end. These waits are noisy, and a helper running slow makes the chunks queue up (`c10` rows,
    p90 up to 36 s). Use them for direction only. Whole-take decodes were measured once and
    reused for every config.
- **Hallucination counters** (summed over the 40 takes):
  - text from a span with < 0.5 s voiced;
  - spans with an n-gram (1–4) repeated 3× back to back, when the reference has none;
  - stock phrases beyond the reference's count (`Mulțumesc`, `Thank you for watching`,
    `La revedere`, `Bine ați venit`, …);
  - words repeated across a cut;
  - spans decoded in another language than the whole take.

  Whole-take baseline: 1 loop, 3 stock phrases. No plain-text chunk config adds a stock phrase or
  a loop; only the word-timestamp rows do (16–17).

## Results

Δ is chunked − whole pooled WER in points, with the bootstrap 95 % CI. "Chunked vs whole" is the
WER of the chunked transcript measured against the whole-take transcript. Wait cells are
whole → chunked, in seconds. The same rows are in `out/summary.json` after a run.

| config | WER chunked | WER whole | Δ (95 % CI) | RO c/w | EN c/w | chunked vs whole | chunks/take | shortest chunk | tail mean/med s | wait measured: whole → chunked (mean / med / p90) | wait at app speed: whole → chunked (mean / med / p90) | still decoding a chunk at the stop (app speed / measured) | text in <0.5 s voiced | loops | stock phrases | dup words at cuts | LID flips |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| default | 14.1 | 13.1 | +0.9 (-0.2…+2.2) | 22.3/20.6 | 3.5/3.5 | 9.0 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 4.14 / 3.77 / 7.36 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 26 | 1 | 1 | 0 | 2 | 2 |
| t8-g0.4-c4 | 15.0 | 13.1 | +1.8 (+0.7…+3.1) | 22.9/20.6 | 4.9/3.5 | 9.7 | 3.52 | 4.5 | 5.8 / 5.6 | 10.37 → 3.87 / 3.82 / 6.22 | 3.86 → 2.47 / 2.19 / 4.01 | 15 / 23 | 1 | 1 | 0 | 3 | 0 |
| t8-g0.4-c6 | 15.2 | 13.1 | +2.1 (+1.0…+3.3) | 23.5/20.6 | 4.5/3.5 | 9.9 | 3.30 | 6.0 | 6.4 / 6.4 | 10.37 → 4.83 / 3.96 / 6.71 | 3.86 → 2.30 / 2.09 / 3.36 | 10 / 24 | 1 | 1 | 0 | 5 | 0 |
| t8-g0.4-c10 | 14.0 | 13.1 | +0.8 (-0.4…+2.0) | 21.7/20.6 | 4.0/3.5 | 8.7 | 2.38 | 10.0 | 6.8 / 6.7 | 10.37 → 12.74 / 7.42 / 29.11 | 3.86 → 2.54 / 2.26 / 3.77 | 15 / 28 | 0 | 2 | 0 | 1 | 1 |
| t8-g0.6-c4 | 14.9 | 13.1 | +1.7 (+0.6…+3.0) | 23.3/20.6 | 4.0/3.5 | 9.2 | 3.27 | 4.5 | 6.5 / 6.3 | 10.37 → 4.31 / 3.97 / 6.74 | 3.86 → 2.36 / 2.11 / 3.11 | 12 / 26 | 1 | 1 | 0 | 2 | 0 |
| t8-g0.6-c6 | 14.5 | 13.1 | +1.4 (+0.2…+2.6) | 22.8/20.6 | 3.9/3.5 | 9.1 | 3.05 | 6.0 | 6.9 / 6.7 | 10.37 → 4.06 / 3.97 / 5.89 | 3.86 → 2.26 / 2.10 / 2.91 | 10 / 24 | 1 | 1 | 0 | 2 | 0 |
| t8-g0.6-c10 | 13.4 | 13.1 | +0.3 (-0.9…+1.4) | 20.8/20.6 | 3.9/3.5 | 8.1 | 2.25 | 10.0 | 7.2 / 8.0 | 10.37 → 13.31 / 7.87 / 35.97 | 3.86 → 2.47 / 2.27 / 3.47 | 14 / 28 | 1 | 2 | 0 | 0 | 0 |
| t8-g0.9-c4 | 14.1 | 13.1 | +1.0 (+0.0…+2.1) | 21.8/20.6 | 4.2/3.5 | 8.1 | 2.75 | 4.6 | 7.3 / 7.0 | 10.37 → 6.40 / 5.55 / 10.30 | 3.86 → 2.31 / 2.20 / 3.00 | 10 / 30 | 2 | 1 | 0 | 2 | 0 |
| t8-g0.9-c6 | 13.7 | 13.1 | +0.6 (-0.7…+1.8) | 21.2/20.6 | 4.1/3.5 | 8.3 | 2.62 | 6.0 | 7.7 / 7.3 | 10.37 → 6.37 / 5.52 / 10.42 | 3.86 → 2.27 / 2.16 / 2.97 | 9 / 27 | 2 | 1 | 0 | 2 | 0 |
| t8-g0.9-c10 | 12.6 | 13.1 | -0.5 (-1.8…+0.6) | 19.8/20.6 | 3.4/3.5 | 7.3 | 2.02 | 10.0 | 7.9 / 8.1 | 10.37 → 10.08 / 8.02 / 17.17 | 3.86 → 2.43 / 2.46 / 3.08 | 13 / 28 | 2 | 2 | 0 | 2 | 0 |
| t10-g0.4-c4 | 15.0 | 13.1 | +1.9 (+0.8…+3.1) | 23.7/20.6 | 3.9/3.5 | 9.3 | 3.17 | 4.6 | 7.1 / 7.2 | 10.37 → 9.30 / 5.24 / 25.13 | 3.86 → 2.56 / 2.21 / 4.11 | 15 / 27 | 1 | 1 | 0 | 3 | 1 |
| t10-g0.4-c6 | 14.6 | 13.1 | +1.5 (+0.5…+2.6) | 23.0/20.6 | 3.9/3.5 | 9.1 | 3.10 | 6.0 | 7.0 / 6.7 | 10.37 → 6.82 / 4.63 / 15.34 | 3.86 → 2.53 / 2.19 / 4.11 | 15 / 27 | 1 | 1 | 0 | 3 | 2 |
| t10-g0.4-c10 | 14.0 | 13.1 | +0.8 (-0.4…+2.0) | 21.7/20.6 | 4.0/3.5 | 8.7 | 2.38 | 10.0 | 6.8 / 6.7 | 10.37 → 12.74 / 7.42 / 29.11 | 3.86 → 2.54 / 2.26 / 3.77 | 15 / 28 | 0 | 2 | 0 | 1 | 1 |
| t10-g0.6-c4 | 14.7 | 13.1 | +1.6 (+0.4…+2.9) | 23.3/20.6 | 3.8/3.5 | 9.2 | 3.12 | 4.6 | 6.6 / 6.7 | 10.37 → 6.62 / 4.05 / 18.15 | 3.86 → 2.63 / 2.29 / 4.33 | 18 / 28 | 1 | 1 | 0 | 2 | 1 |
| t10-g0.6-c10 | 13.4 | 13.1 | +0.3 (-0.9…+1.4) | 20.8/20.6 | 3.9/3.5 | 8.1 | 2.25 | 10.0 | 7.2 / 8.0 | 10.37 → 13.31 / 7.87 / 35.97 | 3.86 → 2.47 / 2.27 / 3.47 | 14 / 28 | 1 | 2 | 0 | 0 | 0 |
| t10-g0.9-c4 | 14.0 | 13.1 | +0.9 (-0.1…+1.8) | 21.8/20.6 | 3.9/3.5 | 8.0 | 2.75 | 4.6 | 7.0 / 6.7 | 10.37 → 7.77 / 6.17 / 14.10 | 3.86 → 2.44 / 2.25 / 3.43 | 15 / 30 | 3 | 1 | 0 | 2 | 1 |
| t10-g0.9-c6 | 13.4 | 13.1 | +0.2 (-1.0…+1.3) | 20.8/20.6 | 3.8/3.5 | 8.0 | 2.62 | 6.0 | 7.4 / 6.7 | 10.37 → 6.23 / 5.53 / 10.42 | 3.86 → 2.40 / 2.27 / 3.09 | 14 / 27 | 3 | 1 | 0 | 2 | 2 |
| t10-g0.9-c10 | 12.6 | 13.1 | -0.5 (-1.8…+0.6) | 19.8/20.6 | 3.4/3.5 | 7.3 | 2.02 | 10.0 | 7.9 / 8.1 | 10.37 → 10.08 / 8.02 / 17.17 | 3.86 → 2.43 / 2.46 / 3.08 | 13 / 28 | 2 | 2 | 0 | 2 | 0 |
| t15-g0.4-c4 | 13.7 | 13.1 | +0.5 (-0.7…+1.7) | 21.2/20.6 | 3.9/3.5 | 8.0 | 2.30 | 5.3 | 9.7 / 11.4 | 10.37 → 7.48 / 6.87 / 10.67 | 3.86 → 2.72 / 2.46 / 4.17 | 12 / 28 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.4-c6 | 13.7 | 13.1 | +0.6 (-0.6…+1.7) | 21.4/20.6 | 3.9/3.5 | 8.1 | 2.17 | 6.0 | 9.7 / 11.7 | 10.37 → 6.94 / 6.76 / 10.25 | 3.86 → 2.58 / 2.46 / 4.09 | 10 / 26 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.4-c10 | 13.8 | 13.1 | +0.6 (-0.6…+2.0) | 21.4/20.6 | 4.0/3.5 | 8.1 | 2.02 | 10.0 | 8.6 / 8.8 | 10.37 → 7.00 / 5.86 / 11.00 | 3.86 → 2.76 / 2.44 / 4.30 | 12 / 26 | 2 | 1 | 0 | 2 | 0 |
| t15-g0.6-c4 | 13.3 | 13.1 | +0.2 (-1.0…+1.3) | 20.6/20.6 | 3.9/3.5 | 7.5 | 2.30 | 5.3 | 9.7 / 11.4 | 10.37 → 7.55 / 6.93 / 10.67 | 3.86 → 2.74 / 2.46 / 4.17 | 12 / 28 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.6-c6 | 13.6 | 13.1 | +0.5 (-0.7…+1.6) | 21.2/20.6 | 3.9/3.5 | 7.9 | 2.15 | 6.0 | 10.1 / 12.1 | 10.37 → 6.76 / 5.88 / 10.25 | 3.86 → 2.55 / 2.46 / 3.83 | 9 / 26 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.6-c10 | 13.4 | 13.1 | +0.3 (-1.1…+1.7) | 20.8/20.6 | 4.0/3.5 | 7.6 | 1.95 | 10.0 | 9.2 / 9.5 | 10.37 → 6.79 / 5.79 / 11.00 | 3.86 → 2.72 / 2.46 / 4.18 | 10 / 27 | 2 | 1 | 0 | 2 | 0 |
| t15-g0.9-c4 | 13.4 | 13.1 | +0.2 (-1.0…+1.5) | 20.8/20.6 | 3.9/3.5 | 7.5 | 2.15 | 5.3 | 9.2 / 11.0 | 10.37 → 7.10 / 6.45 / 10.21 | 3.86 → 2.63 / 2.48 / 4.12 | 13 / 27 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.9-c6 | 13.7 | 13.1 | +0.6 (-0.7…+1.8) | 21.4/20.6 | 3.9/3.5 | 7.8 | 2.02 | 6.0 | 9.6 / 11.7 | 10.37 → 6.66 / 5.98 / 10.21 | 3.86 → 2.54 / 2.48 / 3.85 | 11 / 26 | 0 | 1 | 0 | 2 | 1 |
| t15-g0.9-c10 | 13.6 | 13.1 | +0.5 (-0.9…+1.9) | 21.0/20.6 | 4.2/3.5 | 7.4 | 1.80 | 10.7 | 9.1 / 9.0 | 10.37 → 6.67 / 5.70 / 10.77 | 3.86 → 2.53 / 2.48 / 4.00 | 10 / 25 | 1 | 1 | 0 | 2 | 0 |
| default+context | 13.5 | 13.1 | +0.3 (-1.0…+1.6) | 21.4/20.6 | 3.3/3.5 | 7.9 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 5.96 / 5.68 / 8.70 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 28 | 1 | 1 | 0 | 2 | 2 |
| default+words | 18.2 | 13.1 | +5.1 (+3.6…+6.8) | 26.5/20.6 | 7.5/3.5 | 13.2 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 5.94 / 4.88 / 9.57 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 28 | 1 | 1 | 16 | 1 | 2 |
| default+words-trim | 17.4 | 13.1 | +4.2 (+2.8…+5.9) | 25.4/20.6 | 7.1/3.5 | 12.4 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 4.33 / 4.09 / 6.66 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 24 | 1 | 1 | 6 | 1 | 2 |
| default+words-end05 | 16.3 | 13.1 | +3.2 (+1.9…+4.6) | 24.4/20.6 | 6.0/3.5 | 11.3 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 4.33 / 4.09 / 6.66 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 24 | 1 | 1 | 2 | 1 | 2 |
| default+words-end1 | 18.7 | 13.1 | +5.5 (+4.1…+6.9) | 26.0/20.6 | 9.3/3.5 | 13.9 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 4.33 / 4.09 / 6.66 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 24 | 1 | 1 | 1 | 4 | 2 |
| default+words-firstwin | 14.1 | 13.1 | +0.9 (-0.2…+2.2) | 22.3/20.6 | 3.5/3.5 | 9.0 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 3.05 / 3.10 / 4.76 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 12 | 1 | 1 | 0 | 2 | 2 |
| default+words-hst1 | 18.2 | 13.1 | +5.1 (+3.6…+6.8) | 26.5/20.6 | 7.5/3.5 | 13.1 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 3.42 / 3.28 / 5.31 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 19 | 1 | 1 | 17 | 1 | 2 |
| default+words-hst2 | 18.2 | 13.1 | +5.1 (+3.6…+6.8) | 26.5/20.6 | 7.5/3.5 | 13.1 | 2.98 | 6.0 | 6.9 / 6.7 | 10.37 → 3.18 / 3.10 / 4.76 | 3.86 → 2.60 / 2.29 / 4.33 | 17 / 16 | 1 | 1 | 16 | 1 | 2 |
| t10-g0.6-c6-v4 | 13.2 | 13.1 | +0.1 (-1.0…+1.3) | 20.7/20.6 | 3.7/3.5 | 6.5 | 1.93 | 6.9 | 8.6 / 7.4 | 10.37 → 7.88 / 4.96 / 11.93 | 3.86 → 2.58 / 2.32 / 3.50 | 12 / 26 | 1 | 1 | 0 | 0 | 1 |
| t10-g0.9-c8 | 12.7 | 13.1 | -0.5 (-1.8…+0.6) | 19.8/20.6 | 3.5/3.5 | 7.4 | 2.30 | 8.0 | 7.6 / 7.8 | 10.37 → 6.54 / 5.60 / 10.22 | 3.86 → 2.35 / 2.26 / 2.91 | 11 / 26 | 2 | 1 | 0 | 0 | 0 |
| **t10-g0.9-c8+context** | **12.6** | 13.1 | **-0.5 (-2.0…+0.8)** | 19.6/20.6 | 3.7/3.5 | 7.3 | 2.30 | 8.0 | 7.6 / 7.8 | 10.37 → 5.18 / 4.75 / 8.15 | **3.86 → 2.35 / 2.26 / 2.91** | 11 / 22 | 2 | 1 | 0 | 0 | 0 |
| t10-g0.6-c10+context | 12.9 | 13.1 | -0.3 (-1.7…+0.9) | 20.1/20.6 | 3.6/3.5 | 7.5 | 2.25 | 10.0 | 7.2 / 8.0 | 10.37 → 6.43 / 4.48 / 13.35 | 3.86 → 2.47 / 2.27 / 3.47 | 14 / 24 | 1 | 2 | 0 | 0 | 0 |
| t10-g0.9-c10+context | 12.4 | 13.1 | -0.7 (-2.2…+0.5) | 19.6/20.6 | 3.3/3.5 | 7.1 | 2.02 | 10.0 | 7.9 / 8.1 | 10.37 → 5.53 / 4.46 / 9.55 | 3.86 → 2.43 / 2.46 / 3.08 | 13 / 21 | 2 | 2 | 0 | 2 | 0 |

How to read the rows:

- `tT-gG-cC`: trigger T, minGap G, minChunk C. `default` is `t10-g0.6-c6`.
- With trigger ≤ minChunk, `t8-…-c10` and `t10-…-c10` cut the same way (a cut can only come
  once now ≥ lastCut + 10), so those rows are identical.
- `+words` rows decode the chunks as the app does, with word timings.
  - `-firstwin` keeps only the first window's segments.
  - `-trim` / `-end05` / `-end1` drop words after the voice, or in the clip's last 0.5 / 1 s.
  - `-hst1/2` set mlx_whisper's `hallucination_silence_threshold`.
- The plain rows' texts stand for `+words-firstwin` too: on `default` the two have identical WER.

### Caveats

- 40 takes, 2,659 reference words. A difference under ~1.5 pt is inside the bootstrap noise,
  which is why the recommendation leans on the trend across the sweep, not on one cell.
- The app-speed line fits *whole WAV* decodes (ffmpeg + IPC included). A pcm chunk skips ffmpeg,
  so chunk and tail prices are slightly pessimistic.
- The whole take with `words: true` (asked only when a cue is pending) may hit the same
  `seek`-to-last-word trap when it ends in a long pause. `evals/local-word-timing/` found the
  text identical on 59 of 60 takes, so it is rare there. Not re-measured here.

## Reproduce

```bash
nice -n 19 /usr/local/bin/python3 evals/chunked-decode/chunked_decode.py run     # ~3 h on a busy Mac
nice -n 19 /usr/local/bin/python3 evals/chunked-decode/chunked_decode.py words   # ×words factor
/usr/local/bin/python3 evals/chunked-decode/chunked_decode.py report             # re-score from cache, no GPU
/usr/local/bin/python3 evals/chunked-decode/chunked_decode.py plan               # the cuts alone
```

`--only <config…>` runs a subset. `out/` holds the decode cache, per-config rows and the summary.
It is gitignored because it carries his transcripts.
