#!/usr/bin/env python3
"""What does decoding a take in pause-cut chunks cost in words, and what does it save in wait?

The relay is getting a mode where, while Victor still talks, the local model already
decodes finished stretches of the take ("chunks") cut at his pauses, so that at the stop
only the tail is left. This replays that, offline, over held-out takes > 25 s:

  (a) the take decoded whole — exactly what the relay does today;
  (b) the take cut by the rule below, each chunk decoded alone, texts joined by a space;

both through the helper's own `transcribe` (`helpers/whisper_helper.py` — imported, not
re-implemented: same LID pin, vocabulary prompt, ladder, loop retry and loop cut), with the
model Victor uses (`RELAY_WHISPER_MODEL`, default here `~/.walkie-talkie/models/whisper-large-victor`).

**The cut rule** is `ChunkPlanner.cut` (Sources/WalkieTalkie/ChunkPlanner.swift), ported line
for line in `cut_at`, asked on the relay's 0.5 s tick (`plan`); every number is a flag:
  - the stream is metered in 64 ms hops with `VoicedMeter`'s arithmetic (RMS vs an adaptive
    floor: instant attack, 2 %/hop release, 9 dB over it and over 180 absolute);
  - from `trigger` s after the last cut, the **longest** pause (unvoiced run since the last cut)
    >= minGap (capGap 0.3 once `now - lastCut >= hardCap`), with >= 2 s voiced before it, whose
    cut point — its middle, or 0.4 s into one still going — is >= minChunk after the last cut;
  - the tail [lastCut, end] is decoded too, unless a chunk exists and it has < 0.3 s voiced.

**The wait after the stop** is simulated on a serial helper: a chunk is handed over when its
cut is *decided* (at `now`, not at the cut point, which lies in the past) and starts once the
helper is free; the tail starts at max(end, helper free). Decode times are the ones measured
here, per chunk, in this one process, at `nice -n 19` on a Mac Victor was using — so they are
a little pessimistic, and equally so for both arms.

Usage (one process, sequential; ~3 h for everything on the large model on a busy Mac):
    nice -n 19 /usr/local/bin/python3 evals/chunked-decode/chunked_decode.py run
    /usr/local/bin/python3 evals/chunked-decode/chunked_decode.py report     # no model needed
Decodes are cached in `out/cache.jsonl` (gitignored) keyed by (take, span, prompt), so a sweep
point that cuts where another one did costs nothing, and `report` re-scores without a GPU.
"""
import argparse
import hashlib
import io
import itertools
import json
import os
import random
import re
import sys
import time
import unicodedata
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
CACHE = os.path.join(OUT, "cache.jsonl")
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
# The LoRA's held-out slice: never trained on, and it carries Wispr's *raw* recogniser
# text (`ref_asr`) — an independent reference with no "Screenshot 1:" markers in it.
HELDOUT = os.path.expanduser("~/workspace/voice-distill/eval/heldout.json")
DEFAULT_MODEL = os.path.expanduser("~/.walkie-talkie/models/whisper-large-victor")

SR = 16000
HOP = 1024
HOP_S = HOP / SR

# ---------------------------------------------------------------- the meter (VoicedMeter)


def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")


def voiced_hops(x, over_floor_db=9.0, absolute_floor=180.0):
    """One verdict per full 64 ms hop — `VoicedMeter.judge` + `record`, same arithmetic
    as `evals/voiced-seconds.py` (float32, +1e-6, floor seeded on the first hop)."""
    nb = len(x) // HOP
    f = x[: nb * HOP].astype(np.float32).reshape(nb, HOP)
    rms = np.sqrt((f * f).mean(axis=1)) + np.float32(1e-6)
    ratio = np.float32(10.0 ** (over_floor_db / 20.0))
    out = np.zeros(nb, dtype=bool)
    floor = np.float32(-1)
    for i, r in enumerate(rms):
        if floor < 0 or r < floor:
            floor = r
        else:
            floor += (r - floor) * np.float32(0.02)
        out[i] = r > max(np.float32(absolute_floor), floor * ratio)
    return out


def voiced_s(v, a, b):
    """Voiced seconds in [a, b) (seconds), counting hops that start inside it."""
    i, j = int(np.ceil(a / HOP_S - 1e-9)), int(np.ceil(b / HOP_S - 1e-9))
    return float(v[i:j].sum()) * HOP_S


# ---------------------------------------------------------------- the cut rule


def cut_at(v, last_cut, now, trigger=10.0, min_gap=0.6, min_chunk=6.0, hard_cap=28.0,
           cap_gap=0.3, min_voiced=2.0, ongoing_pad=0.4):
    """`ChunkPlanner.cut`, line for line: the hops metered by `now` that start at or after
    `lastCut`; every unvoiced run among them is a pause (one still going ends at `now`); a
    pause counts if it is >= the gap, has >= minVoiced of speech since lastCut before it, and
    its cut point (middle, or `ongoingPad` into one still going) is >= minChunk after lastCut
    and <= now. The longest wins, a tie goes to the later one. None = wait for more audio."""
    if now - last_cut < trigger:
        return None
    gap = cap_gap if now - last_cut >= hard_cap else min_gap
    n_done = min(len(v), int(np.floor(now / HOP_S + 1e-9)))   # hops complete by `now`
    k0 = int(np.ceil(last_cut / HOP_S - 1e-9))                # first hop with t >= lastCut
    pauses, run, voiced, voiced_at = [], None, 0.0, []
    for k in range(k0, n_done):
        at = k * HOP_S
        if v[k]:
            if run is not None:
                pauses.append((run, at, False))
                run = None
            voiced += HOP_S
        elif run is None:
            run = at
            voiced_at.append(voiced)
    if run is not None:
        pauses.append((run, max(run, now), True))
    best = None
    for i, (s, e, ongoing) in enumerate(pauses):
        length = e - s
        if length < gap or voiced_at[i] < min_voiced:
            continue
        at = s + min(length / 2, ongoing_pad) if ongoing else s + length / 2
        if at - last_cut < min_chunk or at > now:
            continue
        if best is None or length >= best[0]:
            best = (length, at)
    return None if best is None else best[1]


def plan(v, dur, tick=0.5, tail_min_voiced=0.3, **tuning):
    """`[(start, end, decided_at)]` chunks in seconds, then the tail (decided_at = dur) or
    None when it is dropped. The relay asks `ChunkPlanner.cut` on a 0.5 s main-queue tick
    while recording, so the simulation asks at the same instants."""
    chunks, last = [], 0.0
    k = 1
    while k * tick <= dur + 1e-9:
        now = k * tick
        c = cut_at(v, last, now, **tuning)
        if c is not None:
            chunks.append((last, c, now))
            last = c
        k += 1
    tail = (last, dur, dur)
    if chunks and voiced_s(v, last, dur) < tail_min_voiced:
        return chunks, None
    return chunks, tail


# ---------------------------------------------------------------- text and scoring

_FOLD = str.maketrans("ăâîșşțţ", "aaisstt")


def norm(s):
    s = unicodedata.normalize("NFC", (s or "").lower()).translate(_FOLD)
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    s = re.sub(r"[^\w\s]", " ", s).replace("_", " ")
    return s.split()


def align(ref, hyp):
    """(sub, ins, del) of the minimum edit between two word lists."""
    R, H = len(ref), len(hyp)
    d = np.zeros((R + 1, H + 1), dtype=np.int32)
    d[:, 0] = np.arange(R + 1)
    d[0, :] = np.arange(H + 1)
    for i in range(1, R + 1):
        ri = ref[i - 1]
        for j in range(1, H + 1):
            d[i, j] = min(d[i - 1, j] + 1, d[i, j - 1] + 1, d[i - 1, j - 1] + (ri != hyp[j - 1]))
    i, j, s, ins, dele = R, H, 0, 0, 0
    while i > 0 or j > 0:
        if i > 0 and j > 0 and d[i, j] == d[i - 1, j - 1] + (ref[i - 1] != hyp[j - 1]):
            s += ref[i - 1] != hyp[j - 1]
            i, j = i - 1, j - 1
        elif j > 0 and d[i, j] == d[i, j - 1] + 1:
            ins += 1
            j -= 1
        else:
            dele += 1
            i -= 1
    return s, ins, dele


STOCK = [
    "thank you for watching", "thanks for watching", "please subscribe", "subtitles by",
    "amara org", "multumesc pentru vizionare", "va multumesc pentru vizionare",
    "abonati va", "subtitrarea", "multumesc", "thank you", "like si subscribe",
    "la revedere", "bine ati venit",
]


def phrase_count(words, phrase):
    p = phrase.split()
    return sum(words[i:i + len(p)] == p for i in range(len(words) - len(p) + 1))


def stock_extra(ref_w, hyp_w):
    """Stock phrases the hypothesis has more of than the reference (longest first, so
    'thank you for watching' is not also counted as 'thank you')."""
    extra = 0
    for ph in sorted(STOCK, key=len, reverse=True):
        extra += max(0, phrase_count(hyp_w, ph) - phrase_count(ref_w, ph))
    return extra


def has_loop(words, copies=3):
    """An n-gram (n = 1..4) repeated `copies` times back to back."""
    for n in range(1, 5):
        for i in range(len(words) - n * copies + 1):
            g = words[i:i + n]
            if all(words[i + k * n:i + (k + 1) * n] == g for k in range(1, copies)):
                return True
    return False


def boundary_dup(a, b, k=4):
    """Words chunk b repeats from chunk a's end (longest suffix of a == prefix of b, ≤ k)."""
    for n in range(min(k, len(a), len(b)), 0, -1):
        if a[-n:] == b[:n]:
            return n
    return 0


# ---------------------------------------------------------------- takes


def select_takes(n_ro=22, n_en=18, min_s=25.0, seed=7):
    """Held-out takes > 25 s, stratified by duration within each language, so the long
    ones (where the hard cap and several chunks happen) are in it, not just the median."""
    h = json.load(open(HELDOUT))
    picked = []
    for lang, n in (("ro", n_ro), ("en", n_en)):
        pool = sorted((x for x in h if x["language"] == lang and x["seconds"] > min_s
                       and os.path.exists(os.path.join(CORPUS, x["wav"]))
                       and len(norm(x["ref_asr"])) >= 20),
                      key=lambda x: (x["seconds"], x["id"]))
        rnd = random.Random(seed)
        for q in range(n):  # one from each of n equal-count duration strata
            a, b = q * len(pool) // n, (q + 1) * len(pool) // n
            picked.append(pool[a + rnd.randrange(max(1, b - a))])
    return picked


# ---------------------------------------------------------------- the model


class Decoder:
    def __init__(self, model):
        os.environ["RELAY_WHISPER_MODEL"] = model
        sys.path.insert(0, os.path.join(REPO, "helpers"))
        stdin, stdout = sys.stdin, sys.stdout
        sys.stdin, sys.stdout = io.StringIO(""), io.StringIO()  # its protocol loop ends at once
        try:
            import whisper_helper as wh
        finally:
            sys.stdin, sys.stdout = stdin, stdout
        self.wh = wh
        self.base = (wh.VOCABULARY, wh.VOCABULARY_RO)
        self.cache = {}
        os.makedirs(OUT, exist_ok=True)
        if os.path.exists(CACHE):
            for line in open(CACHE):
                try:
                    r = json.loads(line)
                    self.cache[r["key"]] = r
                except ValueError:
                    pass

    def __call__(self, take_id, x, a, b, prompt="", words=False):
        """Decode samples [a, b) seconds of a take; `prompt` is appended to the helper's own
        vocabulary prompt (the previous chunk's last sentence, for the context variant)."""
        i, j = int(round(a * SR)), int(round(b * SR))
        # words: False, True ("|w", text only), "w2" (keeps the timed words) or "h<T>" (words
        # with mlx_whisper's hallucination_silence_threshold=T, timed words kept)
        mode = "w" if words is True else (words or "")
        key = f"{take_id}|{i}|{j}|{hashlib.sha1(prompt.encode()).hexdigest()[:10]}" + (f"|{mode}" if mode else "")
        if key in self.cache:
            return self.cache[key]
        wh = self.wh
        samples = wh.mx.array(x[i:j]).astype(wh.mx.float32) / 32768.0
        if prompt:
            wh.VOCABULARY = self.base[0] + " " + prompt
            wh.VOCABULARY_RO = self.base[1] + " " + prompt
        try:
            t0 = time.monotonic()
            orig = wh.mlx_whisper.transcribe
            if mode.startswith("h"):
                import functools
                wh.mlx_whisper.transcribe = functools.partial(
                    orig, hallucination_silence_threshold=float(mode[1:]))
            try:
                res = wh.transcribe(None, words=bool(mode), samples=samples)
            finally:
                wh.mlx_whisper.transcribe = orig
            if mode == "f" and (j - i) <= 30 * SR:
                # the cure: on a clip that fits one window, only the first window's segments.
                # With word_timestamps mlx_whisper seeks to the last word's end and decodes the
                # leftover pause as a new window — that is where "La revedere!" comes from.
                segs = [g for g in res.get("segments") or [] if g.get("seek", 0) == 0]
                res["segments"] = segs
                res["text"] = "".join(g.get("text") or "" for g in segs)
            dt = time.monotonic() - t0
        finally:
            wh.VOCABULARY, wh.VOCABULARY_RO = self.base
        r = {"key": key, "text": (res.get("text") or "").strip(), "lang": res.get("language"),
             "decode_s": round(dt, 3), "audio_s": round((j - i) / SR, 3),
             "retried": bool(res.get("retried")), "cut": res.get("cut") or 0}
        if mode and mode != "w":
            r["words"] = [[w["text"], w["start"], w["end"]] for w in wh.timed_words(res)]
        self.cache[key] = r
        with open(CACHE, "a") as f:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
        return r


def last_sentence(text, max_words=30):
    parts = [p.strip() for p in re.split(r"(?<=[.?!])\s+", text.strip()) if p.strip()]
    s = parts[-1] if parts else ""
    if len(s.split()) < 4 and len(parts) > 1:
        s = parts[-2] + " " + s
    return " ".join(s.split()[-max_words:])


# ---------------------------------------------------------------- production speed

DECODE_RATE = os.path.expanduser("~/.walkie-talkie/decode-rate.jsonl")
# Victor switched the Engine to whisper-large-victor at 2026-10-20 12:19 local (relay.log).
PROD_SINCE = "2026-10-20T09:20Z"


def production_line(since=PROD_SINCE):
    """`decode = a + b × audio` (Theil–Sen, like `DecodeRate`) over the app's own warm
    whisper-local decodes since the large model went in — what a decode costs on this Mac in
    normal use, as opposed to this nice'd batch competing with everything else."""
    pts = []
    try:
        for line in open(DECODE_RATE):
            r = json.loads(line)
            if (r.get("engine") == "whisper-local" and not r.get("cold") and r.get("at", "") >= since
                    and r.get("audio", 0) > 0.5 and (r.get("compression") or 0) <= 2.4):
                pts.append((r["audio"], r["decode"]))
    except OSError:
        return None
    if len(pts) < 8:
        return None
    x = np.array([p[0] for p in pts]); y = np.array([p[1] for p in pts])
    i, j = np.triu_indices(len(x), 1)
    ok = np.abs(x[j] - x[i]) > 1.0
    b = float(np.median((y[j] - y[i])[ok] / (x[j] - x[i])[ok]))
    a = float(np.median(y - b * x))
    return {"a": a, "b": b, "n": len(pts)}


PROD = production_line()


def prod_s(audio):
    return PROD["a"] + PROD["b"] * audio if PROD else float("nan")


# ---------------------------------------------------------------- one configuration


def run_config(takes, dec, cfg, context=False, words=False, trim=0.0, trim_end=0.0):
    rows = []
    for t in takes:
        x, v, dur = t["x"], t["v"], t["dur"]
        chunks, tail = plan(v, dur, **cfg)
        spans = chunks + ([tail] if tail else [])
        texts, decs, prev = [], [], ""
        for n_span, (a, b, _) in enumerate(spans):
            # `words`: chunks as the app sends them ({"words": true}); the tail stays plain
            w = words if n_span < len(chunks) else False
            r = dec(t["id"], x, a, b, prompt=last_sentence(prev) if (context and prev) else "", words=w)
            if trim and w and r.get("words") is not None:
                # drop the words Whisper started after the chunk's voice had ended: what
                # word-timestamp seeking decodes out of the trailing pause
                vv = np.nonzero(v[int(np.ceil(a / HOP_S - 1e-9)):int(np.ceil(b / HOP_S - 1e-9))])[0]
                voice_end = (vv[-1] + 1) * HOP_S + (np.ceil(a / HOP_S - 1e-9) * HOP_S - a) if len(vv) else 0.0
                r = dict(r, text="".join(wd[0] for wd in r["words"] if wd[1] < voice_end + trim).strip())
            if trim_end and w and r.get("words") is not None:
                # drop what starts in the chunk's last `trim_end` s: the leftover that
                # word-timestamp seeking re-decodes after the last word (`README`, the trap)
                r = dict(r, text="".join(wd[0] for wd in r["words"] if wd[1] < (b - a) - trim_end).strip())
            texts.append(r["text"])
            decs.append(r)
            prev = r["text"] or prev
        # the wait: a serial helper, each chunk handed over when its cut is decided
        # chunks go out as {"pcm", "words": true} (LocalWhisperSource): their decode costs
        # WORDS_FACTOR x the plain one measured here (the `words` mode measures it)
        free = 0.0
        for (a, b, at), r in zip(chunks, decs):
            free = max(free, at) + r["decode_s"] * (1.0 if words else WORDS_FACTOR)
        busy_at_stop = max(0.0, free - dur)
        tail_dec = decs[-1]["decode_s"] if tail else 0.0
        wait = max(free, dur) + tail_dec - dur
        # the same wait with every decode priced by the app's own line (production speed)
        pfree = 0.0
        for (a, b, at) in chunks:
            pfree = max(pfree, at) + prod_s(b - a) * WORDS_FACTOR
        pwait = max(pfree, dur) + (prod_s(tail[1] - tail[0]) if tail else 0.0) - dur
        hyp = " ".join(s for s in texts if s)
        hw = norm(hyp)
        span_words = [norm(s) for s in texts]
        rows.append({
            "id": t["id"], "lang": t["lang"], "dur": dur,
            "chunks": len(chunks), "tail_s": (tail[1] - tail[0]) if tail else 0.0,
            "tail_dropped": tail is None,
            "chunk_lens": [b - a for (a, b, _) in chunks],
            "hyp": hyp, "sub_ins_del": align(t["ref_w"], hw), "n_ref": len(t["ref_w"]),
            "vs_whole": sum(align(t["whole_w"], hw)), "n_whole": len(t["whole_w"]),
            "wait": wait, "busy_at_stop": busy_at_stop, "wait_whole": t["whole_dec"],
            "pwait": pwait, "pwait_whole": prod_s(dur), "pbusy": pfree > dur,
            "silent_text": sum(1 for (a, b, _), w in zip(spans, span_words)
                               if w and voiced_s(v, a, b) < 0.5),
            "loops": sum(1 for w in span_words if has_loop(w)) if not has_loop(t["ref_w"]) else 0,
            "stock": stock_extra(t["ref_w"], hw),
            "dup_words": sum(boundary_dup(span_words[i], span_words[i + 1])
                             for i in range(len(span_words) - 1)),
            "lang_flips": sum(1 for r in decs if r["text"] and r["lang"] != t["whole_lang"]),
            "empty_spans": sum(1 for (a, b, _), w in zip(spans, span_words)
                               if not w and voiced_s(v, a, b) >= 1.0),
        })
    return rows


def summarise(rows, takes):
    def wer(rs, key="sub_ins_del", n="n_ref"):
        e = sum(sum(r[key]) if isinstance(r[key], (list, tuple)) else r[key] for r in rs)
        return 100.0 * e / max(1, sum(r[n] for r in rs))
    whole = {t["id"]: t for t in takes}
    base = [{"sub_ins_del": whole[r["id"]]["whole_sid"], "n_ref": r["n_ref"]} for r in rows]
    # paired bootstrap of the pooled WER delta, chunked − whole
    rnd = np.random.default_rng(0)
    ec = np.array([sum(r["sub_ins_del"]) for r in rows], float)
    ew = np.array([sum(b["sub_ins_del"]) for b in base], float)
    nr = np.array([r["n_ref"] for r in rows], float)
    deltas = []
    for _ in range(2000):
        k = rnd.integers(0, len(rows), len(rows))
        deltas.append(100 * (ec[k].sum() - ew[k].sum()) / nr[k].sum())
    lo, hi = np.percentile(deltas, [2.5, 97.5])
    by_lang = {}
    for lang in ("ro", "en"):
        rs = [r for r in rows if r["lang"] == lang]
        bs = [b for b, r in zip(base, rows) if r["lang"] == lang]
        if rs:
            by_lang[lang] = (wer(rs), wer(bs))
    sid_c = np.array([r["sub_ins_del"] for r in rows]).sum(0)
    sid_w = np.array([b["sub_ins_del"] for b in base]).sum(0)
    waits = np.array([r["wait"] for r in rows])
    ww = np.array([r["wait_whole"] for r in rows])
    return {
        "wer_chunked": wer(rows), "wer_whole": wer(base), "delta": wer(rows) - wer(base),
        "ci": (lo, hi), "by_lang": by_lang,
        "wer_vs_whole": wer(rows, "vs_whole", "n_whole"),
        "sid_chunked": sid_c.tolist(), "sid_whole": sid_w.tolist(),
        "chunks": np.mean([r["chunks"] for r in rows]),
        "chunked_takes": sum(r["chunks"] > 0 for r in rows),
        "min_chunk": min((c for r in rows for c in r["chunk_lens"]), default=0.0),
        "tail": np.mean([r["tail_s"] for r in rows]),
        "tail_med": float(np.median([r["tail_s"] for r in rows])),
        "dropped": sum(r["tail_dropped"] for r in rows),
        "wait": waits.mean(), "wait_med": float(np.median(waits)),
        "wait_p90": float(np.percentile(waits, 90)),
        "wait_whole": ww.mean(), "wait_whole_med": float(np.median(ww)),
        "busy": sum(r["busy_at_stop"] > 0 for r in rows),
        "pwait": float(np.mean([r["pwait"] for r in rows])),
        "pwait_med": float(np.median([r["pwait"] for r in rows])),
        "pwait_p90": float(np.percentile([r["pwait"] for r in rows], 90)),
        "pwait_whole": float(np.mean([r["pwait_whole"] for r in rows])),
        "pwait_whole_med": float(np.median([r["pwait_whole"] for r in rows])),
        "pwait_whole_p90": float(np.percentile([r["pwait_whole"] for r in rows], 90)),
        "pbusy": sum(r["pbusy"] for r in rows),
        "silent_text": sum(r["silent_text"] for r in rows),
        "loops": sum(r["loops"] for r in rows),
        "stock": sum(r["stock"] for r in rows),
        "dup_words": sum(r["dup_words"] for r in rows),
        "lang_flips": sum(r["lang_flips"] for r in rows),
        "empty_spans": sum(r["empty_spans"] for r in rows),
    }


# ---------------------------------------------------------------- main

DEFAULT = dict(trigger=10.0, min_gap=0.6, min_chunk=6.0, hard_cap=28.0)
# chunks decoded as the app sends them ({"words": true}) and two cures for what that costs
WORD_VARIANTS = {
    "words": dict(words=True),
    "words-trim": dict(words="w2", trim=0.2),    # drop words starting > 0.2 s after the voice
    "words-end05": dict(words="w2", trim_end=0.5),  # drop words starting in the last 0.5 s
    "words-end1": dict(words="w2", trim_end=1.0),
    "words-firstwin": dict(words="f"),            # keep the first window's segments only
    "words-hst1": dict(words="h1"),              # hallucination_silence_threshold=1
    "words-hst2": dict(words="h2"),
}
WORDS_FACTOR_FILE = os.path.join(OUT, "words_factor.json")
try:
    WORDS_FACTOR = json.load(open(WORDS_FACTOR_FILE))["factor"]
except (OSError, ValueError, KeyError):
    WORDS_FACTOR = 1.45  # the helper's own measurement (+45 %, 60 clips) until `words` has run


def configs(args):
    out = [("default", dict(DEFAULT), False)]
    for tr, mg, mc in itertools.product(args.triggers, args.min_gaps, args.min_chunks):
        c = dict(DEFAULT, trigger=tr, min_gap=mg, min_chunk=mc)
        name = f"t{tr:g}-g{mg:g}-c{mc:g}"
        if c != DEFAULT:
            out.append((name, c, False))
    out.append(("default+context", dict(DEFAULT), True))
    # follow-ups the sweep pointed at: longer chunks, a longer gap, more speech per chunk, context
    out += [
        ("default+words", dict(DEFAULT), False),
        ("default+words-trim", dict(DEFAULT), False),
        ("default+words-end05", dict(DEFAULT), False),
        ("default+words-end1", dict(DEFAULT), False),
        ("default+words-firstwin", dict(DEFAULT), False),
        ("default+words-hst1", dict(DEFAULT), False),
        ("default+words-hst2", dict(DEFAULT), False),
        ("t10-g0.6-c6-v4", dict(DEFAULT, min_voiced=4.0), False),
        ("t10-g0.9-c8", dict(DEFAULT, min_gap=0.9, min_chunk=8.0), False),
        ("t10-g0.9-c8+context", dict(DEFAULT, min_gap=0.9, min_chunk=8.0), True),
        ("t10-g0.6-c10+context", dict(DEFAULT, min_chunk=10.0), True),
        ("t10-g0.9-c10+context", dict(DEFAULT, min_gap=0.9, min_chunk=10.0), True),
    ]
    return out


def load_takes(dec, args):
    takes = select_takes(args.n_ro, args.n_en)
    loaded = []
    for x in takes:
        pcm = read_wav(os.path.join(CORPUS, x["wav"]))
        t = {"id": x["id"], "lang": x["language"], "x": pcm, "dur": len(pcm) / SR,
             "v": voiced_hops(pcm), "ref_w": norm(x["ref_asr"])}
        if dec is not None:
            r = dec(t["id"], pcm, 0.0, t["dur"])
        else:  # report only: the whole decode must already be in the cache
            r = _cached(t["id"], 0, len(pcm))
        t["whole_dec"], t["whole_lang"] = r["decode_s"], r["lang"]
        t["whole_w"] = norm(r["text"])
        t["whole_sid"] = align(t["ref_w"], t["whole_w"])
        t["whole_loop"] = has_loop(t["whole_w"]) and not has_loop(t["ref_w"])
        t["whole_stock"] = stock_extra(t["ref_w"], t["whole_w"])
        loaded.append(t)
    return loaded


_CACHED = None


def _cached(take_id, i, j, prompt="", words=False):
    mode = "w" if words is True else (words or "")
    global _CACHED
    if _CACHED is None:
        _CACHED = {}
        for line in open(CACHE):
            r = json.loads(line)
            _CACHED[r["key"]] = r
    return _CACHED[f"{take_id}|{i}|{j}|{hashlib.sha1(prompt.encode()).hexdigest()[:10]}" + (f"|{mode}" if mode else "")]


class CacheOnly:
    def __call__(self, take_id, x, a, b, prompt="", words=False):
        return _cached(take_id, int(round(a * SR)), int(round(b * SR)), prompt, words)


def fmt_table(results, takes):
    lines = ["| config | WER chunked | WER whole | Δ (95 % CI) | RO c/w | EN c/w | chunked vs whole "
             "| chunks/take | shortest chunk | tail mean/med s | wait measured: whole → chunked (mean / med / p90) "
             "| wait at app speed: whole → chunked (mean / med / p90) | still decoding a chunk at the stop (app speed / measured) "
             "| text in <0.5 s voiced | loops | stock phrases | dup words at cuts | LID flips |",
             "|" + "---|" * 18]
    for name, s in results:
        bl = s["by_lang"]
        lines.append(
            f"| {name} | {s['wer_chunked']:.1f} | {s['wer_whole']:.1f} | {s['delta']:+.1f} "
            f"({s['ci'][0]:+.1f}…{s['ci'][1]:+.1f}) | {bl['ro'][0]:.1f}/{bl['ro'][1]:.1f} "
            f"| {bl['en'][0]:.1f}/{bl['en'][1]:.1f} | {s['wer_vs_whole']:.1f} | {s['chunks']:.2f} "
            f"| {s['min_chunk']:.1f} | {s['tail']:.1f} / {s['tail_med']:.1f} "
            f"| {s['wait_whole']:.2f} → {s['wait']:.2f} / {s['wait_med']:.2f} / {s['wait_p90']:.2f} "
            f"| {s['pwait_whole']:.2f} → {s['pwait']:.2f} / {s['pwait_med']:.2f} / {s['pwait_p90']:.2f} "
            f"| {s['pbusy']} / {s['busy']} "
            f"| {s['silent_text']} | {s['loops']} | {s['stock']} | {s['dup_words']} "
            f"| {s['lang_flips']} |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["run", "report", "plan", "words"])
    ap.add_argument("--model", default=os.environ.get("RELAY_WHISPER_MODEL", DEFAULT_MODEL))
    ap.add_argument("--n-ro", type=int, default=22)
    ap.add_argument("--n-en", type=int, default=18)
    ap.add_argument("--triggers", type=float, nargs="+", default=[8.0, 10.0, 15.0])
    ap.add_argument("--min-gaps", type=float, nargs="+", default=[0.4, 0.6, 0.9])
    ap.add_argument("--min-chunks", type=float, nargs="+", default=[4.0, 6.0, 10.0])
    ap.add_argument("--only", nargs="*", help="config names to run (default: all)")
    args = ap.parse_args()

    if args.mode == "plan":  # the cuts alone, no model: for checking the rule
        for x in select_takes(args.n_ro, args.n_en):
            pcm = read_wav(os.path.join(CORPUS, x["wav"]))
            v = voiced_hops(pcm)
            ch, tail = plan(v, len(pcm) / SR, **DEFAULT)
            print(f"{x['id'][:8]} {x['language']} {len(pcm)/SR:5.1f}s voiced {v.mean():.2f} "
                  f"cuts {[round(b, 2) for (_, b, _) in ch]} decided {[round(at, 2) for (*_, at) in ch]} "
                  f"tail {'dropped' if tail is None else round(tail[1]-tail[0], 1)}")
        return

    dec = Decoder(args.model) if args.mode in ("run", "words") else CacheOnly()
    if args.mode in ("run", "words"):  # weights resident before anything is timed
        warm = read_wav(os.path.join(REPO, "evals", ".warmup.wav")) if os.path.exists(
            os.path.join(REPO, "evals", ".warmup.wav")) else np.zeros(SR, dtype="<i2")
        dec.wh.transcribe(None, words=False, samples=dec.wh.mx.array(warm).astype(dec.wh.mx.float32) / 32768.0)
    t0 = time.time()
    takes = load_takes(dec if args.mode in ("run", "words") else None, args)
    if args.mode == "words":  # what the app's {"words": true} on every chunk costs, and changes
        plain = timed = same = n = 0
        for t in takes:
            chunks, _ = plan(t["v"], t["dur"], **DEFAULT)
            for (a, b, _) in chunks:
                # both fresh, back to back on the same span: the load on this Mac moves a lot
                x = dec.wh.mx.array(t["x"][int(round(a * SR)):int(round(b * SR))]).astype(dec.wh.mx.float32) / 32768.0
                t0 = time.monotonic(); r0 = dec.wh.transcribe(None, words=False, samples=x)
                t1 = time.monotonic(); r1 = dec.wh.transcribe(None, words=True, samples=x)
                t2 = time.monotonic()
                plain += t1 - t0; timed += t2 - t1; n += 1
                same += norm(r0.get("text")) == norm(r1.get("text"))
        out = {"factor": timed / plain, "chunks": n, "plain_s": plain, "words_s": timed,
               "text_identical": same}
        json.dump(out, open(WORDS_FACTOR_FILE, "w"), indent=1)
        print(out)
        return
    print(f"{len(takes)} takes, {sum(t['dur'] for t in takes):.0f} s audio, "
          f"whole decoded in {sum(t['whole_dec'] for t in takes):.0f} s", file=sys.stderr)
    results = []
    for name, cfg, ctx in configs(args):
        if args.only and name not in args.only:
            continue
        rows = run_config(takes, dec, cfg, context=ctx, **WORD_VARIANTS.get(name.split("+", 1)[-1], {}))
        s = summarise(rows, takes)
        results.append((name, s))
        print(f"[{time.time()-t0:6.0f}s] {name}: WER {s['wer_chunked']:.1f} vs whole {s['wer_whole']:.1f} "
              f"({s['delta']:+.1f}), {s['chunks']:.2f} chunks, wait {s['wait_whole']:.2f} → {s['wait']:.2f}",
              file=sys.stderr, flush=True)
        with open(os.path.join(OUT, f"rows-{name}.json"), "w") as f:
            json.dump(rows, f, ensure_ascii=False, indent=1, default=float)
    whole_loops = sum(t["whole_loop"] for t in takes)
    whole_stock = sum(t["whole_stock"] for t in takes)
    print(f"whole-take baseline: loops {whole_loops}, stock phrases {whole_stock}, "
          f"sub/ins/del {np.array([t['whole_sid'] for t in takes]).sum(0).tolist()}")
    if PROD:
        print(f"app speed: decode = {PROD['a']:.2f} s + {PROD['b']:.3f} × audio "
              f"({PROD['n']} warm whisper-local decodes since {PROD_SINCE}); chunks × {WORDS_FACTOR:.2f} for words")
    print(fmt_table(results, takes))
    with open(os.path.join(OUT, "summary.json"), "w") as f:
        json.dump({n: s for n, s in results}, f, indent=1, default=float)


if __name__ == "__main__":
    main()
