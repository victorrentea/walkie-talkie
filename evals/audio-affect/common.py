"""Shared by the audio-affect eval: the corpus, the app's own meter replayed, the word verdict.

The question (Victor, 2026-11-05): `VoiceAffect` needs `words[]`, which only Scribe gives. Can the
same verdict be read off the waveform alone, so that it also works on Wispr Flow and the local model?

`meter()` is `MicRecorder`'s meter byte for byte (`evals/voiced-seconds.py`, `VoicedMeter`): 1024-frame
hops at 16 kHz, adaptive floor, 9 dB over it, absolute floor 180. That is deliberate — tier A may only
use what the app already holds during a Wispr dictation.
"""
import json, os, sqlite3, wave
import numpy as np

CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
TIMING = os.path.expanduser("~/workspace/voice-distill/runs/timing.jsonl")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
HOP, SR = 1024, 16000
HOP_S = HOP / SR


def read_wav(path):
    with wave.open(path, "rb") as w:
        if w.getsampwidth() != 2 or w.getframerate() != SR:
            return None
        n, ch = w.getnframes(), w.getnchannels()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32)
    return x.reshape(-1, ch).mean(axis=1) if ch > 1 else x


def meter(x, over_floor_db=9.0, absolute_floor=180.0):
    """(rms per hop, voiced per hop), as the app computes them."""
    nb = len(x) // HOP
    if nb == 0:
        return np.zeros(0), np.zeros(0, bool)
    f = x[: nb * HOP].reshape(nb, HOP)
    rms = np.sqrt((f * f).mean(axis=1)) + 1e-6
    floor, ratio = rms[0], 10 ** (over_floor_db / 20)
    voiced = np.zeros(nb, bool)
    for i, r in enumerate(rms):
        floor = r if r < floor else floor + (r - floor) * 0.02
        voiced[i] = r > max(absolute_floor, floor * ratio)
    return rms, voiced


def runs(mask):
    """[(start, end)] of the True runs."""
    d = np.diff(np.concatenate(([0], mask.astype(int), [0])))
    return list(zip(np.where(d == 1)[0], np.where(d == -1)[0]))


def word_signals(r):
    """The six signals of `VoiceAffect.analyse`, from a timing.jsonl row. Whisper keeps no fillers and
    `timing.py`'s restart is the plain adjacent repeat — both named in the report."""
    gaps = r.get("gaps") or []
    span = r.get("span") or 0
    s = {
        "pause_ratio": (r.get("pause_ratio") or 0) >= 0.35,
        "pauses_over": sum(g > 1.0 for g in gaps) >= 4,
        "slow": span >= 4 and (r.get("rate") or 9) < 1.4,
        "lead": (r.get("lead") or 0) > 3.0,
        "restarts": (r.get("restarts") or 0) >= 2,
        "fillers": (r.get("fillers") or 0) >= 2 and (r.get("fillers") or 0) / max(1, r.get("n_words") or 1) >= 0.08,
    }
    return s


def word_verdict(r):
    return (r.get("n_words") or 0) >= 5 and sum(word_signals(r).values()) >= 2


def clips():
    """timing.jsonl joined with the corpus: every clip that has word timings."""
    db = sqlite3.connect(CORPUS + "/corpus.db")
    meta = {i: (w, m, s, t) for i, w, m, s, t in db.execute("select id,wav,mic,source,ts from samples")}
    for line in open(TIMING):
        r = json.loads(line)
        if "gaps" not in r or r["id"] not in meta:
            continue
        r["wav"], r["mic"], r["source"], r["ts"] = meta[r["id"]]
        r["mic"] = r["mic"] or "?"
        yield r
