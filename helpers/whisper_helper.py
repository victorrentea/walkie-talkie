#!/usr/bin/env python3
"""Long-lived local transcriber for Walkie Talkie.

**It is a daemon and not a script because of one measurement**: importing
`mlx_whisper` costs 7.4s and the first transcription pays another 2.8s to load
the weights, while a second one takes 1.3s. Shelling out per dictation would put
ten seconds between Victor finishing a sentence and the agent seeing it — so the
process starts once, warms up once, and then answers in about a tenth of the
audio's length.

Protocol, one JSON object per line each way:

    →  {"wav": "/path/to/file.wav"}
    ←  {"ok": true, "text": "…", "language": "ro", "avg_logprob": -0.21,
        "compression_ratio": 1.4, "no_speech_prob": 0.0,
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
import os
import sys

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


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
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


def transcribe(path):
    with quiet():
        # Decoded once, here, and handed to both halves as an array: the LID pass
        # needs the samples anyway, and passing the path twice would shell out to
        # ffmpeg twice for the same file.
        samples = A.load_audio(path)
        lang = pick_language(samples)
        return mlx_whisper.transcribe(
            samples,
            path_or_hf_repo=MODEL,
            language=lang,
            initial_prompt=VOCABULARY_RO if lang == "ro" else VOCABULARY,
            verbose=False,
            condition_on_previous_text=False,
        )


# Warm up on a second of silence so the weights are resident before Victor's
# first sentence, rather than his first sentence paying for them. Same reason
# victor-macos-addons warms up before its GUI starts.
try:
    warm = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".warmup.wav")
    if not os.path.exists(warm):
        import wave
        with wave.open(warm, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00" * 32000)
    transcribe(warm)
    emit({"ready": True, "model": MODEL, "memory": memory_stats()})
except Exception as e:  # noqa: BLE001
    emit({"ready": False, "error": f"warm-up failed: {e}"})
    sys.exit(1)


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
        wav = req["wav"]
        if not os.path.exists(wav):
            emit({"ok": False, "error": f"no such file: {wav}"})
            continue
        res = transcribe(wav)
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
            "avg_logprob": min((s.get("avg_logprob", 0.0) for s in segs), default=0.0),
            "compression_ratio": max((s.get("compression_ratio", 0.0) for s in segs), default=0.0),
            "no_speech_prob": max((s.get("no_speech_prob", 0.0) for s in segs), default=0.0),
            # Rides along on every answer rather than needing its own request:
            # the interesting question about this pool is how it moves across a
            # day of dictations, and a number nobody has to ask for is the only
            # kind that gets looked at.
            "memory": memory_stats(),
        })
    except Exception as e:  # noqa: BLE001 — one bad request must not kill the daemon
        emit({"ok": False, "error": str(e)})
