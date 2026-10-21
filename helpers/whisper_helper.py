#!/usr/bin/env python3
"""Long-lived local transcriber for Walkie Talkie.

**It is a daemon and not a script because of one measurement**: importing
`mlx_whisper` costs 7.4s and the first transcription pays another 2.8s to load
the weights, while a second one takes 1.3s. Shelling out per dictation would put
ten seconds between Victor finishing a sentence and the agent seeing it — so the
process starts once, warms up once, and then answers in about a tenth of the
audio's length.

Protocol, one JSON object per line each way:

    →  {"wav": "/path/to/file.wav", "words": true}      (`words` optional)
    →  {"pcm": "/path/to/window.pcm", "segments": true}  (live captions, below)
    ←  {"ok": true, "text": "…", "language": "ro", "avg_logprob": -0.21,
        "compression_ratio": 1.4, "no_speech_prob": 0.0, "decode_s": 0.83,
        "words": [{"text": " există", "start": 1.54, "end": 2.56}, …],
        "memory": {"active_mb": 1543.3, "cache_mb": 512.2, "peak_mb": 2365.8,
                   "cache_limit_mb": 512}}
    ←  {"ok": false, "error": "…"}

and once, unprompted, at start-up:

    ←  {"ready": true, "model": "…", "memory": {…}}
       (or {"ready": false, "error": "…"})

`memory` is MLX's own accounting and is the only place that separates the
weights from the Metal buffer pool — see `memory_stats` and the cache-limit
note below it. Consumers may ignore it; nothing in the protocol depends on it.

stdout carries **only** protocol lines. mlx and huggingface both write progress
bars and warnings to stdout, so every model call is wrapped in a redirect —
without it the first tqdm bar corrupts the stream and the relay sees garbage.

Three decode settings here were measured rather than guessed — the language
pin, the vocabulary prompt and `condition_on_previous_text`. See
`evals/short-clip-lid.md` for the first two (803 of Victor's own clips, four
configs, 3212 decodes).

`condition_on_previous_text=False` is the oldest of them. Left at its default (True), 3 of 20
sample dictations fell into repetition loops — "nu știu, nu știu, nu știu…" for
forty words — and because every looped word is an insertion, those three alone
moved pooled WER from 37% to 50%. The flag is right *here* and would be wrong in
victor-macos-addons, which streams short chunks and genuinely needs the previous
one for continuity.
"""
import contextlib
import json
import math
import os
import re
import tempfile
import sys
import time


MODEL = os.environ.get("RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")

# Victor speaks these two and no others. Whisper picks a language off its 30s
# window *before* it decodes a word, and with three seconds of speech and
# twenty-seven of padding in that window the pick is a guess — a guess that does
# not produce a wrong word but a fluent sentence in a language nobody spoke.
# Measured over 803 clips: 50% of those under 2s, 28% at 2-3s and 19% at 3-4s
# came back in neither of these. Restricting the argmax to the two takes that to
# **0% in every bucket**, and it is free — `transcribe(language=None)` already
# runs this exact encoder pass internally, so pinning only relocates it (paired
# cost: -22ms).
LANGUAGES = tuple(os.environ.get("RELAY_WHISPER_LANGUAGES", "ro,en").split(","))

# **The words he says that a general model has never heard him say.**
#
# Whisper's `initial_prompt` is decoder context, not a filter: it does not
# constrain the output, it makes these spellings cheap. Recall on these very
# terms over their 490 occurrences in the reference transcripts went 0.67 -> 0.88
# with it — `Claude` 0.33 -> 0.85 (without it the model writes `cloud`, `claw`,
# and turns `CLAUDE.md` into `CloudMD`), `frontend` 0.10 -> 0.70, `petclinic`
# 0.00 -> 0.60, `backend` 0.44 -> 0.92, `IntelliJ` 0.59 -> 0.88. Median WER under
# five seconds went 0.300 -> 0.222.
#
# **Every term is attested in his own transcripts and was most broken without
# this.** `Devoxx`, `repo` and `VS Code` were guessed at, checked against the
# corpus (0, 1 and 2 occurrences) and thrown out. A prompt is capped at 224
# tokens and attention weights its tail hardest, so it is a short list of things
# that actually go wrong — not a glossary.
#
# **It costs repetition loops**, which is why `compression_ratio` is now read on
# the Swift side: 7 more across 803 clips, all of them caught by that ratio and
# none of them by the `avg_logprob` floor, because a loop is *confidently*
# wrong.
VOCABULARY = os.environ.get("RELAY_WHISPER_VOCABULARY", (
    "Claude Code, CLAUDE.md, Copilot, subagent, subagenți, MCP, skill, hook, "
    "prompt, commit, push, backend, frontend, IntelliJ, JetBrains, "
    "Walkie Talkie, Wispr Flow, petclinic, agentic."
))

# **The prompt is chosen by the language, because the two languages fail
# differently.** Mining the substitutions of 129 clips decoded with no prompt at
# all, the top English errors are the terms above (`claude` -> `cloud`, `md` ->
# `cloudmd`); the top *Romanian* errors are not vocabulary at all, they are
# **diacritics** — `să` -> `sa` (10), `în` -> `in` (6), `și` -> `si` (4),
# `compară` -> `compara` — the model writing Victor's language flat. A glossary
# of English product names buys nothing against that, and the measurement says
# so: on Romanian clips the list above moves WER 23.8% -> 24.1%, i.e. nowhere.
#
# What does move it is decoder context that is *itself* written in diacritics.
# Measured on 548 held-out clips (never searched on), routing Romanian to the
# list below and leaving English on the list above:
#
#     overall   15.9% -> 15.2%   (bootstrap 2000x: -0.69, 95% CI [-1.27, -0.19],
#                                 better in 100% of resamples)
#     Romanian  22.6% -> 21.2%
#     English    8.7% ->  8.7%   (unchanged by construction)
#     repetition loops  7 -> 5
#
# **Routing is what makes it safe.** The same Romanian prompt applied to *every*
# clip is a disaster — 18 loops in 129 against 2, because Romanian context over
# English audio decodes into Romanian-shaped noise and runs away (`Chau coă coă
# coă…`). Nearly all of those loops are on non-Romanian clips, which routing
# never shows it. The LID pass already knows the answer before decoding starts;
# this only stops throwing it away.
#
# **The gain is small and the dev set lied about it.** On the 129 clips the
# search ran over it read -1.9 points; on the two held-out sets, -2.7 and -0.5.
# The honest figure is the pooled -0.7. Kept because it is consistent in every
# split, never worse on English, and costs fewer loops, not more.
# **It carries the English terms too, and that is not redundancy.** The first
# version of this list was Romanian only, and WER liked it — but term recall
# caught what WER could not see: he speaks Romanian *with English terms in it*,
# and a Romanian-only prompt stops priming them. On the same held-out clips,
# `backend` fell 0.88 -> 0.50 and `claude` 0.88 -> 0.75 while the diacritics rose.
# Adding the technical terms back costs nothing (45 of the 224 tokens were used)
# and buys them back above where they started:
#
#     term        today   ro-only   this list
#     să           0.88     0.94      0.93
#     în           0.78     0.86      0.85
#     claude       0.88     0.75      0.92
#     backend      0.88     0.50      1.00
#
# `commit` sits at 0.41 under every prompt tried — it is heard as `me`, and no
# amount of decoder context has moved it. Left documented rather than solved.
VOCABULARY_RO = os.environ.get("RELAY_WHISPER_VOCABULARY_RO", (
    "să, și, în, întâi, îți, îmi, această, când, făcut, ștergem, trebuie, "
    "aș, două, când, până, mâine, așa, început, terminăm, încearcă, "
    "schimbă, vezi, adaugă, românește, Claude Code, CLAUDE.md, Copilot, MCP, "
    "subagent, subagenți, skill, hook, prompt, commit, push, backend, "
    "frontend, IntelliJ, petclinic, Walkie Talkie, Wispr Flow, agentic, "
    "sesiune, dictare, agent."
))


def _finite(obj):
    """NaN and ±inf become null (2026-09-29).

    `json.dumps` writes them as bare `NaN` / `-Infinity`, which is not JSON:
    Swift's `JSONSerialization` rejects the **whole reply**, and the relay
    reported "the local model gave no answer" and dropped the sentence. A
    1-1.4 s near-silent take can decode with `avg_logprob: NaN` — three of
    Victor's dictations were lost that way on 2026-09-29 (09:48, 09:59).
    """
    if isinstance(obj, float):
        return obj if math.isfinite(obj) else None
    if isinstance(obj, dict):
        return {k: _finite(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_finite(v) for v in obj]
    return obj


def emit(obj):
    sys.stdout.write(json.dumps(_finite(obj), ensure_ascii=False, allow_nan=False) + "\n")
    sys.stdout.flush()


@contextlib.contextmanager
def quiet():
    """Keep mlx/tqdm chatter off the protocol stream."""
    with open(os.devnull, "w") as dev:
        with contextlib.redirect_stdout(dev), contextlib.redirect_stderr(dev):
            yield


try:
    with quiet():
        import mlx_whisper
        import mlx.core as mx
        import numpy as np
        from mlx_whisper import audio as A
        from mlx_whisper.transcribe import ModelHolder
except Exception as e:  # noqa: BLE001 — any import failure is the same answer
    emit({"ready": False, "error": f"cannot import mlx_whisper: {e}"})
    sys.exit(1)


# **MLX keeps every buffer it frees, and by default it never stops.**
#
# `set_cache_limit` defaults to the *memory* limit, which on a 64 GB machine is
# effectively unbounded — so the pool of freed Metal buffers grows for as long
# as the daemon lives and is never returned to the system. Measured on 2026-09-17
# over 40 corpus clips: weights held a flat 1543 MB while the cache climbed
# 1159 -> 1396 -> 1541 -> 1711 MB and was still rising when the run ended. After
# three hours of real use this process and its sibling in victor-macos-addons
# were holding 5.7 GB and 3.5 GB, ~95% of it this pool, 3.5 GB of it pushed out
# to swap.
#
# The cache holds *no state* — only buffers already freed, kept for reuse — so
# capping it cannot change a transcription, and the same 40 clips were decoded
# to prove it rather than to assume it. 39 came back byte-identical. The 40th
# differed, and the control run says why: two runs with *no* cap differed on
# that same clip and no other (" pewns pewns…" vs " bolts" vs " you"). It is
# 1.6s of silence whose reference text is empty, so temperature fallback
# resamples it differently every time. Whisper's nondeterminism, not the cap's.
#
# 512 MB rather than 0: disabling the cache entirely would make every allocation
# round-trip to the Metal driver. This keeps reuse for the common buffer shapes
# and only cuts the unbounded tail. The measured cost was +4.9% median latency —
# smaller than the 6% spread between two *identical* runs, so at n=40 it is not
# distinguishable from noise.
_CACHE_LIMIT = int(os.environ.get("RELAY_WHISPER_CACHE_LIMIT_MB", "512")) * 1024 * 1024
if _CACHE_LIMIT > 0:
    mx.set_cache_limit(_CACHE_LIMIT)


# **Word timings, for the screenshot markers** (2026-10-04). `ShotMarker.place`
# puts a picture's reference in front of the first word that had not started at
# the press, which needs every word's start on the recording's own clock — what
# ElevenLabs' `words[]` gave and this model did not. `word_timestamps=True` is
# mlx_whisper's cross-attention DTW. **It costs +45 % decode time** (60 clips,
# 952 s of audio, same process, alternating), so it is off unless the request
# says `"words": true` — the relay asks only when a picture, highlight or pick
# was cued during the take. `RELAY_WHISPER_WORDS=1` makes it the default.
# Precision: `evals/local-word-timing/`.
WORDS = os.environ.get("RELAY_WHISPER_WORDS", "0") == "1"

# **Which decoder heads the DTW reads.** mlx_whisper does not load any from the
# model folder — it uses every head of the last half of the decoder (40 on
# turbo) unless told. OpenAI's own list for large-v3-turbo (the
# `alignment_heads` in openai/whisper-large-v3-turbo's generation_config.json,
# same as `_ALIGNMENT_HEADS["large-v3-turbo"]` in openai/whisper) is six of them.
# Applied only to a model with turbo's decoder shape (4 layers × 20 heads) —
# the LoRA keeps it. `RELAY_WHISPER_ALIGNMENT=default` keeps mlx's 40.
TURBO_ALIGNMENT_HEADS = [[2, 4], [2, 11], [3, 3], [3, 6], [3, 11], [3, 14]]
# **And large-v3's ten** (2026-10-21, openai/whisper-large-v3's
# generation_config.json): until then a large-v3 model — the `whisper-large-victor`
# LoRA, 32 layers × 20 heads — fell back to mlx's 320, and the 18:22:54 take's last
# 69 words all came back at 139.48 s with zero length (the 📸 landed at the end)
# while the opening sentence was read four times over. With these: 367 words, no
# repeats, speech to 164.3 s, the picture where he took it. 128 mels keeps
# large-v1/v2 (80 mels, other heads) out.
LARGE_V3_ALIGNMENT_HEADS = [[7, 0], [10, 17], [12, 18], [13, 12], [16, 1], [17, 14],
                            [19, 11], [21, 4], [24, 1], [25, 6]]
ALIGNMENT = os.environ.get("RELAY_WHISPER_ALIGNMENT", "official")


def use_alignment_heads():
    if ALIGNMENT != "official":
        return
    try:
        model = ModelHolder.get_model(MODEL, mx.float16)
        shape = (model.dims.n_text_layer, model.dims.n_text_head)
        if shape == (4, 20):
            model.set_alignment_heads(np.array(TURBO_ALIGNMENT_HEADS))
        elif shape == (32, 20) and model.dims.n_mels == 128:
            model.set_alignment_heads(np.array(LARGE_V3_ALIGNMENT_HEADS))
    except Exception as e:  # noqa: BLE001 — timings are a nicety; the words are not
        print(f"alignment heads not set: {e}", file=sys.stderr)


try:  # beside this file — in the bundle's Resources and in helpers/
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from word_onsets import snap_starts
except Exception as e:  # noqa: BLE001 — the words still go out, unsnapped
    snap_starts = None
    print(f"word_onsets not importable: {e}", file=sys.stderr)


def timed_words(res, samples=None):
    """`[{text, start, end}]` across every segment, the text exactly as Whisper
    spelled it (leading space included), so the tokens join back into `text`.
    With the samples, each start is moved onto the voice it names
    (`word_onsets.snap_starts` — Whisper starts the word after a pause in the pause)."""
    out = []
    for seg in res.get("segments") or []:
        for w in seg.get("words") or []:
            out.append({"text": w.get("word", ""),
                        "start": round(float(w.get("start", 0.0)), 3),
                        "end": round(float(w.get("end", 0.0)), 3)})
    if samples is not None and out and snap_starts is not None:
        try:
            out = snap_starts(out, samples)
        except Exception as e:  # noqa: BLE001 — unsnapped timings beat none
            print(f"word onsets not snapped: {e}", file=sys.stderr)
    return out


def memory_stats():
    """MLX's own accounting, in MB — the only honest view of this process.

    `ps` and Activity Monitor report the Metal buffer pool as ordinary resident
    memory, so they show a number that looks like a leak and cannot be split
    into weights and cache. These three can: `active` is what is actually held
    (weights, ~1543 MB), `cache` is the reusable pool the limit above governs,
    and `peak` is the high-water mark since the process started.
    """
    return {
        "active_mb": round(mx.get_active_memory() / 2**20, 1),
        "cache_mb": round(mx.get_cache_memory() / 2**20, 1),
        "peak_mb": round(mx.get_peak_memory() / 2**20, 1),
        "cache_limit_mb": _CACHE_LIMIT // 2**20,
    }


def pick_language(samples):
    """The model's own language ID, argmax'd over `LANGUAGES` alone.

    `detect_language` already returns the full distribution over all 99 codes,
    so restricting it needs no second pass and no tokenizer surgery — the whole
    change is which keys the max is taken over. `ModelHolder` is the same cache
    `transcribe` uses, and float16 matches what it runs at, so this shares the
    resident weights rather than loading a second copy.

    Returns None on anything unexpected, which falls the caller back to
    Whisper's own unrestricted pick — the old behaviour, and the right failure
    for a helper whose job is to answer rather than to be right.
    """
    try:
        model = ModelHolder.get_model(MODEL, mx.float16)
        mel = A.log_mel_spectrogram(samples[:A.N_SAMPLES],
                                    n_mels=model.dims.n_mels, padding=A.N_SAMPLES)
        mel = A.pad_or_trim(mel, A.N_FRAMES, axis=-2).astype(mx.float16)
        _, probs = model.detect_language(mel)
        if isinstance(probs, (list, tuple)):
            probs = probs[0]
        if not all(code in probs for code in LANGUAGES):
            return None
        return max(LANGUAGES, key=lambda code: probs[code])
    except Exception as e:  # noqa: BLE001
        print(f"language detection failed: {e}", file=sys.stderr)
        return None


# Same number as `LocalWhisper.loopCeiling` on the Swift side (803 clips, zero
# false alarms): above it the decode is one syllable repeated, not a transcript.
LOOP_CEILING = 2.4


def _worst_ratio(res):
    return max((s.get("compression_ratio") or 0.0 for s in res.get("segments") or []), default=0.0)


# **The temperature ladder is ours, and a loop ends it** (2026-10-04).
#
# mlx_whisper re-decodes a 30 s window at 0.2, 0.4 … 1.0 when the greedy pass
# looks bad and keeps the **last** rung, whatever it is. On 16:28:10 a 90 s take
# took 32.6 s (predicted 2.4 s) and came back with 669 × "AM": a near-silent
# window decoded fine at 0.0 (cr 0.7) but under `avg_logprob` -1.0, so the
# ladder climbed, and the 1.0 rung looped for 224 tokens and was kept — twice,
# since the relay's no-prompt retry then climbed the same ladder again. Every
# looped decode in `decode-rate.jsonl` is that animal: median 0.36× the audio
# against 0.096× for the other 549.
#
# Here the transcriber is asked for one temperature, and `Whisper.decode` runs
# the ladder itself, **for a loop only**: the greedy rung is kept unless it
# loops, a loop climbs to 0.2 and 0.4 (each looped rung is 224 tokens of
# decode, ~1.5 s; 0.6–1.0 are where the 16:28 loop was *made*), and the least
# looped rung is kept. A low `avg_logprob` no longer climbs: on his clips those
# windows are near-silence, heat only invents words there, and the relay's own
# −0.6 floor already warns about them.
LADDER = (0.0, 0.2, 0.4)


def _install_ladder():
    from dataclasses import replace
    from mlx_whisper.whisper import Whisper
    if getattr(Whisper.decode, "walkie_ladder", False):
        return
    plain = Whisper.decode

    def decode(self, mel, options=None, **kw):
        if options is None or options.temperature != 0.0 or mel.ndim != 2:
            return plain(self, mel, options, **kw) if options is not None else plain(self, mel, **kw)
        tried = []
        for t in LADDER:
            r = plain(self, mel, replace(options, temperature=t), **kw)
            tried.append(r)
            if r.compression_ratio <= LOOP_CEILING:
                return r
        return min(tried, key=lambda r: r.compression_ratio)

    decode.walkie_ladder = True
    Whisper.decode = decode


# **What still loops is cut out of the words** (2026-10-04): a run of four or
# more copies of the same stretch (1–40 characters, at least one letter in it)
# keeps its first copy. "AM AM AM…" ×669 → "AM"; "们"×223 → "们". Four, because
# Victor does say "nu, nu, nu" and "de exemplu, de exemplu". Done on each looped
# segment's words, so the timed words and the text still join back into each other.
_REPEAT = re.compile(r"([^\n]{1,40}?)\1{3,}")
_LETTER = re.compile(r"[^\W\d_]")


def collapse_repeats(text):
    """`(text, [(start, end)…])` — the text with every loop cut, and the cut spans."""
    cuts = [(m.start() + len(m.group(1)), m.end())
            for m in _REPEAT.finditer(text) if _LETTER.search(m.group(1))]
    out, at = [], 0
    for a, b in cuts:
        out.append(text[at:a])
        at = b
    out.append(text[at:])
    return "".join(out), cuts


def cut_loops(res):
    """Cut the repeats out of every looped segment; returns how many characters went."""
    gone = 0
    for seg in res.get("segments") or []:
        if (seg.get("compression_ratio") or 0.0) <= LOOP_CEILING:
            continue
        words = seg.get("words") or []
        if words:
            joined, starts, at = "", [], 0
            for w in words:
                starts.append(at)
                joined += w.get("word", "")
                at = len(joined)
            _, cuts = collapse_repeats(joined)
            keep = [w for w, s in zip(words, starts) if not any(a <= s < b for a, b in cuts)]
            seg["words"] = keep
            text = "".join(w.get("word", "") for w in keep)
            gone += len(joined) - len(text)
        else:
            text, cuts = collapse_repeats(seg.get("text") or "")
            gone += sum(b - a for a, b in cuts)
        seg["text"] = text
    if gone:
        res["text"] = "".join(s.get("text") or "" for s in res.get("segments") or [])
    res["cut"] = gone
    return gone


def load_pcm(path):
    """A live-caption window: raw int16 LE, mono, 16 kHz — the relay's own take,
    copied out of memory. No ffmpeg (a subprocess per window would be ~40 ms of a
    decode that has to be quick). The live caption runs in a helper of its own,
    which the relay SIGKILLs when the dictation closes mid-window (2026-10-05):
    the final decode is never queued behind it."""
    return mx.array(np.fromfile(path, dtype="<i2")).astype(mx.float32) / 32768.0


def transcribe(path, words=WORDS, samples=None, language=None):
    with quiet():
        # Decoded once, here, and handed to both halves as an array: the LID pass
        # needs the samples anyway, and passing the path twice would shell out to
        # ffmpeg twice for the same file.
        if samples is None:
            samples = A.load_audio(path)
        # **A language the caller already knows skips the LID pass** (2026-10-21):
        # the tail of a chunked take reuses its chunks' language — 0.56 s of the
        # tail's 1.40 s (`evals/chunked-decode/`).
        lang = language if language in LANGUAGES else pick_language(samples)

        def decode(prompt):
            return mlx_whisper.transcribe(
                samples,
                path_or_hf_repo=MODEL,
                language=lang,
                initial_prompt=prompt,
                verbose=False,
                condition_on_previous_text=False,
                word_timestamps=words,
                temperature=0.0,  # the ladder runs inside `Whisper.decode` — `_install_ladder`
            )

        res = decode(VOCABULARY_RO if lang == "ro" else VOCABULARY)
    first_window_only(res, words, samples)
    res["duration"] = len(samples) / A.SAMPLE_RATE
    res["_samples"] = samples
    res["retried"] = False
    # **A loop gets one more try, without the vocabulary prompt** (2026-09-29).
    # The prompt is what buys the loops (`evals/short-clip-lid.md`), and on
    # 09:52:49 a 2.5 s take came back as 223 × "们" (cr 37) and was pasted at the
    # caret after 6.3 s of reverse tunnel. Re-decoded without the prompt the same
    # clip gave cr 0.27. Costs one extra decode, and only when the first looped.
    first = _worst_ratio(res)
    if first > LOOP_CEILING:
        with quiet():
            again = decode(None)
        first_window_only(again, words, samples)
        second = _worst_ratio(again)
        print(f"looped (cr {first:.1f}) — retried without the prompt: cr {second:.1f}, "
              f"{'kept the retry' if second < first else 'kept the first'}", file=sys.stderr)
        if second < first:
            again["duration"], again["retried"] = res["duration"], True
            again["_samples"] = samples
            res = again
    cut_loops(res)
    return res


def first_window_only(res, words, samples):
    """**With word timings, a clip that fits one window is read once** (2026-10-21).

    With `word_timestamps=True` mlx_whisper seeks to the end of the last word and
    decodes what is left of the 30 s window again — on a chunk ending in a pause,
    that leftover is silence and the model invents a closing phrase (*"La
    revedere!"*, *"Da, da."*): 82 of 119 chunks, WER 13.1 % → 18.2 %
    (`evals/chunked-decode/`). A clip ≤ 30 s is all in the first window, so only
    the segments with `seek == 0` are kept — WER back to the plain-text 14.1 %.
    """
    if not words or len(samples) > A.N_SAMPLES:
        return
    segs = res.get("segments") or []
    kept = [s for s in segs if s.get("seek", 0) == 0]
    if len(kept) == len(segs) or not kept:
        return
    print(f"first window only: {len(segs) - len(kept)} later segment(s) dropped "
          f"({' | '.join((s.get('text') or '').strip()[:40] for s in segs if s not in kept)})",
          file=sys.stderr)
    res["segments"] = kept
    res["text"] = "".join(s.get("text") or "" for s in kept)


def coverage(res):
    """Where in the audio the words came from — to catch a missing middle.

    Whisper decodes in 30 s windows and can seek past speech; the transcript
    then reads fine and simply lacks a stretch. The longest stretch with no
    segment, and where it sits, is what makes that visible in the relay log.
    """
    segs = res.get("segments") or []
    dur = res.get("duration") or 0.0
    edges = [0.0] + [x for s in segs for x in (s.get("start", 0.0), s.get("end", 0.0))] + [dur]
    gaps = [(edges[i + 1] - edges[i], edges[i]) for i in range(0, len(edges) - 1, 2)]
    gap, at = max(gaps, default=(0.0, 0.0))
    return {
        "segments": len(segs),
        "duration": round(dur, 2),
        "covered": round(sum(max(0.0, s.get("end", 0.0) - s.get("start", 0.0)) for s in segs), 2),
        "gap": round(max(0.0, gap), 2),
        "gap_at": round(at, 2),
        "temperature": max((s.get("temperature") or 0.0 for s in segs), default=0.0),
        "retried": bool(res.get("retried")),
        "cut": res.get("cut") or 0,
    }


# Warm up on a second of silence so the weights are resident before Victor's
# first sentence, rather than his first sentence paying for them. Same reason
# victor-macos-addons warms up before its GUI starts.
#
# **Never next to this file** (2026-09-26, batch 6): installed, this script lives
# inside the signed app bundle, and a file written there breaks
# `codesign --verify` of the installed app. The app's data folder, else $TMPDIR.
def _warmup_path():
    for d in (os.path.expanduser("~/.walkie-talkie"), tempfile.gettempdir()):
        try:
            os.makedirs(d, exist_ok=True)
            if os.access(d, os.W_OK):
                return os.path.join(d, ".warmup.wav")
        except OSError:
            continue
    return os.path.join(tempfile.gettempdir(), ".warmup.wav")


_install_ladder()

try:
    warm = _warmup_path()
    if not os.path.exists(warm):
        import wave
        with wave.open(warm, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00" * 32000)
    transcribe(warm)
    use_alignment_heads()
    emit({"ready": True, "model": MODEL, "memory": memory_stats()})
except Exception as e:  # noqa: BLE001
    emit({"ready": False, "error": f"warm-up failed: {e}"})
    sys.exit(1)


def timed_segments(res):
    """`[{text, start, end}]`, seconds into the audio — what the live caption
    commits by: a segment two decodes in a row agree on is fixed on screen and
    the next window starts at its end (`LocalLiveCaption`)."""
    return [{"text": s.get("text", ""),
             "start": round(float(s.get("start", 0.0)), 3),
             "end": round(float(s.get("end", 0.0)), 3)}
            for s in res.get("segments") or []]


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
        path = req.get("pcm") or req.get("wav")
        if not path or not os.path.exists(path):
            emit({"ok": False, "error": f"no such file: {path}"})
            continue
        t0 = time.monotonic()
        want_words = bool(req.get("words", WORDS))
        samples = load_pcm(path) if req.get("pcm") else None
        res = transcribe(path, words=want_words, samples=samples, language=req.get("language"))
        decode_s = time.monotonic() - t0
        segs = res.get("segments") or []
        # The worst segment, not the average: a dictation is unusable if any part
        # of it was hallucinated, and averaging hides one bad segment inside
        # twenty good ones. `avg_logprob` is the signal that actually separates —
        # measured over the corpus, a gate at -0.6 caught 7 of 11 semantically
        # broken transcripts while falsely rejecting 0 of 40 good ones, whereas
        # `no_speech_prob` caught none of them.
        emit({
            "ok": True,
            "text": (res.get("text") or "").strip(),
            "language": res.get("language"),
            # NaN anywhere makes the worst one NaN (sent as null): `min` alone
            # would answer depending on where in the list the NaN sat.
            "avg_logprob": min((s.get("avg_logprob", 0.0) for s in segs), default=0.0,
                               key=lambda v: -math.inf if v != v else v),
            "compression_ratio": max((s.get("compression_ratio", 0.0) for s in segs), default=0.0),
            "no_speech_prob": max((s.get("no_speech_prob", 0.0) for s in segs), default=0.0),
            "coverage": coverage(res),
            # Present only when asked for (the default): `[{text, start, end}]`,
            # seconds into the WAV, the ruler `MicRecorder.offset(of:)` measures on.
            **({"words": timed_words(res, res.get("_samples"))} if want_words else {}),
            **({"segments": timed_segments(res)} if req.get("segments") else {}),
            "decode_s": round(decode_s, 3),
            # Rides along on every answer rather than needing its own request:
            # the interesting question about this pool is how it moves across a
            # day of dictations, and a number nobody has to ask for is the only
            # kind that gets looked at.
            "memory": memory_stats(),
        })
    except Exception as e:  # noqa: BLE001 — one bad request must not kill the daemon
        emit({"ok": False, "error": str(e)})
