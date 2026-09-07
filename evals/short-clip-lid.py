#!/usr/bin/env python3
"""Does pinning language ID to {ro, en} — and a vocabulary prompt — fix the short clips?

**The failure this is about is written down in `CLAUDE.md`.** `language=None` in
`helpers/whisper_helper.py` lets the model pick a language off its 30-second
window *before* it decodes a word; with two seconds of speech and twenty-eight
of padding in that window, the pick is a guess, and a wrong pick is not a wrong
word — it is a fluent sentence in a language Victor does not speak. `Teşekkürler.`
for a Romanian sentence. 12% of clips at 2–3s, 0% past five seconds. The note
ends by naming the lever and saying it has not been pulled: *"restricting
language ID to {ro, en} would have caught every case counted above"*. This is
the measurement that says whether that is true, and what it costs elsewhere.

Four configs, the same 803 clips, the same warm model:

    A   language=None                                     — today
    B   language = argmax over {ro, en} of the model's own LID
    C   B + initial_prompt=VOCAB
    D   A + initial_prompt=VOCAB

B and D are run so the two changes can be attributed separately: if C wins, the
next question is always *which half of C*.

`condition_on_previous_text=False` is in every config and is never a variable.
It is the one decode setting that was already measured — 3 of 20 dictations fell
into repetition loops with it at its default — and an eval that quietly turned it
back on would be measuring that instead.

**The reference is Wispr Flow's transcript, not ground truth.** The 803 rows this
runs over are the ones carrying both: `text` is what Wispr made of the WAV (which
Victor considers the better transcript) and `asr` is what the local model made of
it. So every number here is a *disagreement* rate, the same caveat the 442-clip
table in `CLAUDE.md` carries — and `--suspect` prints the rows where Wispr is the
one that is wrong, because those move an aggregate silently. `retina` → `Rentea`
is the one to look at first.

**The empty-output column cannot be compared to the 71%-under-1s figure in
`CLAUDE.md`, and the reason is the eval set itself.** A row qualifies here by
having a non-empty `asr`, so every clip the baseline returned nothing for was
excluded before the first decode ran. Config A's empty rate is therefore ~0 by
construction and means nothing; what the column *does* measure, honestly, is
whether B, C or D turn a clip that had words into one that has none.

**One model, loaded once.** `mlx_whisper.transcribe` caches the weights in
`ModelHolder`, so calling it in-process 3212 times pays the 2.8s load once;
shelling out per sample would have paid it 3212 times. The WAVs are already
16 kHz mono, so they are read with `wave` and handed over as an array — passing
the path would put an `ffmpeg` fork in front of every one of them.

    python3 evals/short-clip-lid.py                      # everything, all four configs
    python3 evals/short-clip-lid.py --limit 20           # smoke test
    python3 evals/short-clip-lid.py --config A,B --under 8
    python3 evals/short-clip-lid.py --report             # re-score what is on disk
    python3 evals/short-clip-lid.py --suspect            # rows where Wispr looks wrong

Rows append to `evals/work/short-clip-lid.jsonl` (gitignored, ~3 MB) one per
(sample, config), and a rerun skips what is already there — a 50-minute run that
dies at minute 40 resumes.
"""

import argparse
import contextlib
import json
import os
import re
import statistics
import sys
import time
import unicodedata
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
RESULTS = os.path.join(WORK, "short-clip-lid.jsonl")
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
MODEL = os.environ.get("RELAY_WHISPER_MODEL", "mlx-community/whisper-large-v3-turbo")

# The two languages Victor speaks. Everything else in the model's 99 is a way to
# be fluently wrong.
SPOKEN = ("ro", "en")

# The vocabulary prompt, derived from the corpus and not from imagination —
# `--vocab` prints the derivation, term by term, with the reference frequency
# and the baseline's recall on it.
#
# **Every term is attested and most are measurably broken.** The core of the
# list is the terms the baseline actually mangles: `frontend` → `front-end`
# (recall 0.70 over 10), `subagenți` → `sub agenți`/`subagents` (0.70 over 10),
# `JetBrains` → `jet brains` (0.67 over 3), `backend` → `back-end` (0.76 over
# 25), `IntelliJ` → `intelliju`/`inteliju` (0.76 over 17), and the one that
# matters most, `Claude` → `cloud`/`claw`/`cloudmd` (0.92 over 52, and `md`
# 0.93 over 61 — `CLAUDE.md` comes back as `cloudmd`).
#
# The rest — Copilot, MCP, skill, hook, prompt, commit, push, petclinic,
# Walkie Talkie, Wispr Flow, agentic — already score 1.00 and are in as cheap
# insurance on the words whose loss would cost an agent the most. **Terms that
# were guessed and then thrown out on the evidence**: `Devoxx` (n=0 — he does
# not say it into this microphone), `repo` (n=1), `VS Code` (n=2). The cap that
# decides the length is not Whisper's 224 tokens, which this is nowhere near
# (65 under the `ro` tokenizer), but that a long prompt is itself a source of
# hallucination.
#
# **It only ever reaches the first window.** `transcribe` seeds `all_tokens`
# with the prompt and then, because `condition_on_previous_text=False`, sets
# `prompt_reset_since = len(all_tokens)` after every window — so a clip under
# 30s is prompted throughout and a two-minute one is prompted for its first
# thirty seconds and decoded bare after that. That is the right shape for this
# question (the failure is short clips) and it is why the long buckets should
# be expected to barely move.
VOCAB = ("Claude Code, CLAUDE.md, Copilot, subagent, subagenți, MCP, skill, hook, "
         "prompt, commit, push, backend, frontend, IntelliJ, JetBrains, "
         "Walkie Talkie, Wispr Flow, petclinic, agentic.")

CONFIGS = {
    "A": {"lid": False, "prompt": None, "what": "language=None — today"},
    "B": {"lid": True, "prompt": None, "what": "language = argmax over {ro, en}"},
    "C": {"lid": True, "prompt": VOCAB, "what": "B + vocabulary prompt"},
    "D": {"lid": False, "prompt": VOCAB, "what": "A + vocabulary prompt"},
}

BUCKETS = [(0, 2, "<2"), (2, 3, "2–3"), (3, 4, "3–4"), (4, 5, "4–5"), (5, 6, "5–6"),
           (6, 8, "6–8"), (8, 12, "8–12"), (12, 30, "12–30"), (30, 1e9, "30+")]


def bucket(duration):
    for lo, hi, name in BUCKETS:
        if lo <= duration < hi:
            return name
    return "30+"


# ---------------------------------------------------------------- normalisation

def normalise(text):
    """Lowercase, strip diacritics, strip punctuation, collapse whitespace.

    The hyphen goes to a **space**, not to nothing, and that is a judgement call
    worth naming: the baseline writes `back-end` where Wispr writes `backend`,
    and neither reading costs an agent anything. Splitting them makes that a
    two-token miss instead of a one-token miss, which understates the model
    slightly and is at least symmetric across the four configs. Joining them
    would have been the other defensible choice and would flatter `backend`
    while breaking `walkie-talkie`.
    """
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    # Romanian comma-below survives NFD on some fonts; fold it by hand.
    text = text.replace("ș", "s").replace("ț", "t").replace("ş", "s").replace("ţ", "t")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def tokens(text):
    return normalise(text).split()


def wer(ref_tokens, hyp_tokens):
    """Levenshtein over words, divided by the reference length.

    Iterative two-row DP: the longest clip here is twenty minutes, and a full
    matrix for it is 3000×3000 ints for no reason.
    """
    if not ref_tokens:
        return 0.0 if not hyp_tokens else 1.0
    prev = list(range(len(hyp_tokens) + 1))
    for i, r in enumerate(ref_tokens, 1):
        cur = [i] + [0] * len(hyp_tokens)
        for j, h in enumerate(hyp_tokens, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h))
        prev = cur
    return prev[-1] / len(ref_tokens)


# ---------------------------------------------------------------- the corpus

def eval_rows(under=None, seed_long=None):
    """The 803 rows that carry both transcripts, newest-first order irrelevant.

    A row qualifies on `asr` being non-empty: that is the local model's own
    output, so the row has a baseline to compare against and a Wispr reference
    to compare to. Rows without it are the ones the relay produced itself, where
    `text` *is* the local output and scoring it against itself measures nothing.
    """
    rows = []
    with open(os.path.join(CORPUS, "corpus.jsonl")) as f:
        for line in f:
            r = json.loads(line)
            if not (r.get("asr") or "").strip():
                continue
            if not os.path.exists(os.path.join(CORPUS, r["wav"])):
                continue
            rows.append(r)
    rows.sort(key=lambda r: r["duration"])
    if under is None:
        return rows
    # The documented fallback: everything short, where the problem lives, plus a
    # seeded sample of the long ones as a regression control.
    import random
    short = [r for r in rows if r["duration"] < under]
    long_ = [r for r in rows if r["duration"] >= under]
    random.Random(seed_long or 0).shuffle(long_)
    return sorted(short + long_[:150], key=lambda r: r["duration"])


def read_wav(path):
    """16 kHz mono PCM straight off disk, as float32 in [-1, 1).

    `mlx_whisper` forks `ffmpeg` for anything it is handed as a path. The corpus
    is already at the sample rate the model wants — `VoiceCorpus.swift` writes it
    that way — so the fork buys nothing and costs a process per sample per config,
    3212 of them.
    """
    import numpy as np
    with wave.open(path, "rb") as f:
        assert f.getframerate() == 16000 and f.getnchannels() == 1 and f.getsampwidth() == 2, \
            f"{path}: expected 16kHz mono s16, got {f.getframerate()}Hz " \
            f"{f.getnchannels()}ch {f.getsampwidth() * 8}bit"
        raw = f.readframes(f.getnframes())
    return (np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0)


# ---------------------------------------------------------------- the model

@contextlib.contextmanager
def quiet():
    """mlx and huggingface write tqdm bars to stdout; this eval prints there too."""
    with open(os.devnull, "w") as dev:
        with contextlib.redirect_stdout(dev), contextlib.redirect_stderr(dev):
            yield


_mx = _whisper = _audio = None


def _lazy():
    global _mx, _whisper, _audio
    if _whisper is None:
        with quiet():
            import mlx.core as mx
            import mlx_whisper
            from mlx_whisper import audio as audio_mod
        _mx, _whisper, _audio = mx, mlx_whisper, audio_mod
    return _mx, _whisper, _audio


def detect_spoken(samples):
    """The restricted language ID. One encoder pass; returns (code, probs, ms).

    This is `transcribe`'s own LID with one line changed. Upstream it is

        mel_segment = pad_or_trim(mel, N_FRAMES, axis=-2).astype(dtype)
        _, probs = model.detect_language(mel_segment)
        decode_options["language"] = max(probs, key=probs.get)   # over all 99

    and the restriction is entirely in that last line: `probs` is already a dict
    over every language code, so taking the argmax over two keys of it needs no
    new forward pass and no surgery on the tokenizer's mask.

    **The model is fetched through `ModelHolder`, not `load_model`.** That is the
    cache `transcribe` itself uses, keyed on the repo path, so asking it here
    means the LID pass and the decode share one 2.5 GB copy of the weights.
    `mx.float16` matches `transcribe`'s default (`fp16=True`); asking for float32
    would populate the holder with a second dtype and make every later decode use
    it.

    The mel is computed over the first 30 seconds only. Upstream computes it for
    the whole file because it needs all of it to decode anyway; here a twenty
    minute clip would pay for 40 windows to answer a question asked of the first.
    """
    mx, mlx_whisper, audio_mod = _lazy()
    from mlx_whisper.transcribe import ModelHolder
    t0 = time.time()
    with quiet():
        model = ModelHolder.get_model(MODEL, mx.float16)
        head = samples[:audio_mod.N_SAMPLES]
        mel = audio_mod.log_mel_spectrogram(head, n_mels=model.dims.n_mels,
                                            padding=audio_mod.N_SAMPLES)
        mel = audio_mod.pad_or_trim(mel, audio_mod.N_FRAMES, axis=-2).astype(mx.float16)
        _, probs = model.detect_language(mel)
    code = max(SPOKEN, key=lambda c: probs[c])
    return code, {c: round(probs[c], 4) for c in SPOKEN}, (time.time() - t0) * 1000


def run_one(samples, cfg):
    """One decode under one config. Everything here except `language` and
    `initial_prompt` is `whisper_helper.transcribe`, verbatim."""
    mx, mlx_whisper, _ = _lazy()
    lid_ms, probs, language = 0.0, None, None
    if cfg["lid"]:
        language, probs, lid_ms = detect_spoken(samples)
    t0 = time.time()
    with quiet():
        res = mlx_whisper.transcribe(
            samples,
            path_or_hf_repo=MODEL,
            language=language,
            verbose=False,
            condition_on_previous_text=False,
            initial_prompt=cfg["prompt"],
        )
    segs = res.get("segments") or []
    return {
        "text": (res.get("text") or "").strip(),
        "language": res.get("language"),
        "lid_probs": probs,
        "lid_ms": round(lid_ms, 1),
        "decode_s": round(time.time() - t0, 3),
        "avg_logprob": min((s.get("avg_logprob", 0.0) for s in segs), default=0.0),
        "compression_ratio": max((s.get("compression_ratio", 0.0) for s in segs), default=0.0),
        "no_speech_prob": max((s.get("no_speech_prob", 0.0) for s in segs), default=0.0),
    }


# ---------------------------------------------------------------- the run

def load_done():
    done = set()
    if os.path.exists(RESULTS):
        with open(RESULTS) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                done.add((r["id"], r["config"]))
    return done


def main_run(args):
    rows = eval_rows(under=args.under)
    if args.limit:
        rows = rows[:args.limit]
    configs = [c.strip() for c in args.config.split(",")]
    os.makedirs(WORK, exist_ok=True)
    done = load_done()
    todo = [(r, c) for r in rows for c in configs if (r["id"], c) not in done]
    audio = sum(r["duration"] for r, _ in todo)
    print("%d samples × %s = %d decodes to run (%.0f min of audio, ~%.0f min at 0.0355×)"
          % (len(rows), "".join(configs), len(todo), audio / 60, audio * 0.0355 / 60))
    started = time.time()
    with open(RESULTS, "a") as log:
        for n, (r, cname) in enumerate(todo, 1):
            samples = read_wav(os.path.join(CORPUS, r["wav"]))
            try:
                out = run_one(samples, CONFIGS[cname])
            except Exception as e:  # noqa: BLE001 — one bad clip must not end the run
                print("  %s %s ERROR %s" % (r["id"][:8], cname, e))
                continue
            row = dict(id=r["id"], config=cname, wav=r["wav"], duration=r["duration"],
                       ref=r["text"], baseline=r["asr"], **out)
            log.write(json.dumps(row, ensure_ascii=False) + "\n")
            log.flush()
            if n % 25 == 0 or n == len(todo):
                el = time.time() - started
                print("  %4d/%d  %5.1f min elapsed, ~%.1f min left"
                      % (n, len(todo), el / 60, el / n * (len(todo) - n) / 60))


# ---------------------------------------------------------------- scoring

def rare_vocabulary(rows):
    """The 2000 commonest reference words, so everything else is 'rare'.

    Rare-word recall is the metric that matters most for a dictation going to an
    agent, and `CLAUDE.md` says why: *"a mangled identifier costs the agent
    everything, a wrong verb ending costs nothing"*. Plain WER counts them the
    same.
    """
    import collections
    freq = collections.Counter()
    for r in rows:
        freq.update(tokens(r["ref"]))
    return set(w for w, _ in freq.most_common(2000))


def score(rows):
    common = rare_vocabulary([r for r in rows if r["config"] == "A"] or rows)
    for r in rows:
        ref, hyp = tokens(r["ref"]), tokens(r["text"])
        r["wer"] = wer(ref, hyp)
        r["empty"] = not r["text"].strip()
        r["wrong_lang"] = bool(r["text"].strip()) and r["language"] not in SPOKEN
        rare = [w for w in ref if w not in common]
        hyp_set = set(hyp)
        r["rare_n"] = len(rare)
        r["rare_hit"] = sum(1 for w in rare if w in hyp_set)
        # A repetition loop is not a bad transcript, it is a different kind of
        # object, and it has to be counted separately or it eats every average
        # it is put into: `af af af af…` for a 0.6s clip whose reference is two
        # words scores WER 43.8, and one of those moves the mean of 119 samples
        # by 0.37. `CLAUDE.md` already records this shape from the other side —
        # three looped dictations moved pooled WER from 37% to 50%.
        r["loop"] = r["wer"] > 2.0
    return rows


def table(rows, configs):
    import collections
    by = collections.defaultdict(list)
    for r in rows:
        by[(r["config"], bucket(r["duration"]))].append(r)
    lines = []
    head = "| bucket | n | " + " | ".join(
        "%s wer med / >0.3 / rare-rec / loop / wrong-lang / empty" % c for c in configs) + " |"
    lines.append(head)
    lines.append("|" + "---|" * (2 + len(configs)))
    for _, _, name in BUCKETS:
        n = len(by.get((configs[0], name), []))
        if not n:
            continue
        cells = []
        for c in configs:
            g = by.get((c, name), [])
            if not g:
                cells.append("—")
                continue
            wers = [x["wer"] for x in g]
            rn = sum(x["rare_n"] for x in g) or 1
            rh = sum(x["rare_hit"] for x in g)
            cells.append("%.2f / %.0f%% / %.0f%% / %.0f%% / %.0f%% / %.0f%%" % (
                statistics.median(wers),
                100 * sum(1 for x in wers if x > 0.3) / len(g),
                100 * rh / rn,
                100 * sum(1 for x in g if x["loop"]) / len(g),
                100 * sum(1 for x in g if x["wrong_lang"]) / len(g),
                100 * sum(1 for x in g if x["empty"]) / len(g)))
        lines.append("| %s | %d | %s |" % (name, n, " | ".join(cells)))
    return "\n".join(lines)


def pooled(rows, configs, pred, label):
    import collections
    by = collections.defaultdict(list)
    for r in rows:
        if pred(r):
            by[r["config"]].append(r)
    out = []
    for c in configs:
        g = by.get(c, [])
        if not g:
            continue
        wers = [x["wer"] for x in g]
        rn = sum(x["rare_n"] for x in g) or 1
        out.append("| %s | %s | %d | %.3f | %.3f | %.0f%% | %.1f%% | %.1f%% | %.1f%% | %.1f%% |" % (
            label, c, len(g), statistics.median(wers),
            # Mean of WER **capped at 1.0**. An uncapped mean over this set is a
            # report about four looped clips and nothing else.
            statistics.mean(min(x, 1.0) for x in wers),
            100 * sum(x["rare_hit"] for x in g) / rn,
            100 * sum(1 for x in wers if x > 0.3) / len(g),
            100 * sum(1 for x in g if x["loop"]) / len(g),
            100 * sum(1 for x in g if x["wrong_lang"]) / len(g),
            100 * sum(1 for x in g if x["empty"]) / len(g)))
    return out


def regressions(rows, base="A", other="C", threshold=0.1):
    """Samples the change made *worse*. The whole point of asking about C.

    A vocabulary prompt is the classic way to buy three identifiers and pay for
    them with a hallucinated fourth on a clip that was already fine, so the
    number that decides C is not its median WER but this count.
    """
    idx = {(r["id"], r["config"]): r for r in rows}
    hurt = []
    for (rid, c), r in idx.items():
        if c != other:
            continue
        b = idx.get((rid, base))
        if b and r["wer"] - b["wer"] > threshold:
            hurt.append((r["wer"] - b["wer"], b, r))
    hurt.sort(reverse=True, key=lambda t: t[0])
    return hurt


def main_report(args):
    rows = score([json.loads(l) for l in open(RESULTS)])
    configs = sorted(set(r["config"] for r in rows))
    print("%d rows, %d samples, configs %s\n" % (
        len(rows), len(set(r["id"] for r in rows)), configs))
    print(table(rows, configs))
    print("\n| set | cfg | n | wer med | wer mean≤1 | rare-rec | wer>0.3 | loop | wrong-lang | empty |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for line in pooled(rows, configs, lambda r: r["duration"] < 5, "<5s"):
        print(line)
    for line in pooled(rows, configs, lambda r: r["duration"] < 8, "<8s"):
        print(line)
    for line in pooled(rows, configs, lambda r: r["duration"] >= 12, "12s+"):
        print(line)
    for line in pooled(rows, configs, lambda r: True, "all"):
        print(line)
    for other in [c for c in configs if c != "A"]:
        hurt = regressions(rows, "A", other)
        print("\n=== %s worse than A by >0.1 WER: %d of %d" % (
            other, len(hurt), sum(1 for r in rows if r["config"] == other)))
        for d, b, r in hurt[:args.worst]:
            print("  +%.2f  %s  %.1fs" % (d, b["wav"], b["duration"]))
            print("    REF: %s" % b["ref"].replace("\n", " ")[:240])
            print("    A  : %s" % b["text"].replace("\n", " ")[:240])
            print("    %s  : %s" % (other, r["text"].replace("\n", " ")[:240]))
    lid = [r["lid_ms"] for r in rows if r["config"] == "B"]
    if lid:
        print("\nrestricted LID cost: median %.0f ms, mean %.0f ms over %d passes"
              % (statistics.median(lid), statistics.mean(lid), len(lid)))


def main_fixed(args):
    """Clips config A decoded into a language Victor does not speak, and what B did.

    This is the evidence the report is built from. An aggregate that moves 4% is
    a claim; `Teşekkürler.` becoming the sentence he actually said is the proof.
    """
    rows = score([json.loads(l) for l in open(RESULTS)])
    idx = {(r["id"], r["config"]): r for r in rows}
    bad = sorted([r for r in rows if r["config"] == "A" and r["wrong_lang"]],
                 key=lambda r: r["duration"])
    print("%d clips config A decoded into a language he does not speak\n" % len(bad))
    for a in bad:
        print("%.1fs  %s  [%s]" % (a["duration"], a["wav"], a["language"]))
        print("  REF: %s" % a["ref"].replace("\n", " ")[:200])
        print("  A  : %s" % a["text"].replace("\n", " ")[:200])
        for c in ("B", "C", "D"):
            o = idx.get((a["id"], c))
            if o:
                print("  %s  : [%s] %s" % (c, o["language"], o["text"].replace("\n", " ")[:200]))
        print()


def main_suspect(args):
    """Rows where the *reference* is the broken one.

    `CLAUDE.md` is explicit that the line beside a recording is not ground truth,
    and Wispr Flow has its own failure mode: a personal dictionary that writes
    Victor's surname over words that sound like it. `retina screen` comes back
    from Wispr as `Rentea screen` and the local model, which has never heard of
    him, gets it right — and is scored wrong for it. A handful of these do not
    move an 803-row aggregate, but they are the reason a 3-point difference is
    not a result.
    """
    rows = [json.loads(l) for l in open(RESULTS) if '"config": "A"' in l or True]
    rows = [r for r in rows if r["config"] == "A"]
    hits = []
    for r in rows:
        ref, hyp = tokens(r["ref"]), tokens(r["text"])
        if "rentea" in ref and "rentea" not in hyp:
            hits.append(("rentea", r))
        elif len(ref) < 3 and r["duration"] > 5:
            hits.append(("ref shorter than the clip", r))
    print("%d suspect references\n" % len(hits))
    for why, r in hits[:args.worst]:
        print("%.1fs  %s  (%s)" % (r["duration"], r["wav"], why))
        print("  REF: %s" % r["ref"].replace("\n", " ")[:200])
        print("  A  : %s\n" % r["text"].replace("\n", " ")[:200])


def main_vocab(args):
    """Where VOCAB came from: reference frequency and baseline recall, per term.

    Printed rather than hardcoded so the next person can see the prompt is a
    measurement and not a wish list — and so a term that stops being mangled can
    be dropped from it on evidence.
    """
    import collections
    rows = [json.loads(l) for l in open(os.path.join(CORPUS, "corpus.jsonl"))]
    rows = [r for r in rows if (r.get("asr") or "").strip()]
    ref, hit = collections.Counter(), collections.Counter()
    for r in rows:
        h = set(tokens(r["asr"]))
        for t in tokens(r["text"]):
            ref[t] += 1
            hit[t] += t in h
    print("%-14s %5s %8s" % ("term", "n", "baseline recall"))
    for term in sorted(set(tokens(VOCAB))):
        if ref[term]:
            print("%-14s %5d %11.2f" % (term, ref[term], hit[term] / ref[term]))
        else:
            print("%-14s %5d %11s" % (term, 0, "— not in the references"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="A,B,C,D")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--under", type=float, default=None,
                    help="short-run mode: every clip under this, plus 150 seeded longer ones")
    ap.add_argument("--worst", type=int, default=3)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--fixed", action="store_true")
    ap.add_argument("--suspect", action="store_true")
    ap.add_argument("--vocab", action="store_true")
    args = ap.parse_args()
    if args.vocab:
        return main_vocab(args)
    if args.report:
        return main_report(args)
    if args.fixed:
        return main_fixed(args)
    if args.suspect:
        return main_suspect(args)
    main_run(args)


if __name__ == "__main__":
    main()
