"""Tier A: only the hop series the app already holds. No words, no recogniser, nothing new on the mic."""
import json, os, sys
import numpy as np
from multiprocessing import Pool
from common import *


def features(r):
    x = read_wav(os.path.join(CORPUS, r["wav"]))
    if x is None or len(x) < SR:
        return None
    rms, v = meter(x)
    if not v.any():
        return None
    # A gap under two hops is the meter's flicker, not a pause.
    idx = np.where(v)[0]
    a, b = idx[0], idx[-1] + 1
    span = (b - a) * HOP_S
    sil = [(e - s) * HOP_S for s, e in runs(~v[a:b])]
    sil = [g for g in sil if g >= 0.128]
    db = 20 * np.log10(rms[v])
    env = 20 * np.log10(rms[a:b])
    env = env - np.median(env[v[a:b]])
    # Syllable proxy: local maxima of the level, ≥ 3 dB over its neighbours' valley, voiced.
    e = np.convolve(rms[a:b], [.25, .5, .25], "same")
    peaks = np.where((e[1:-1] > e[:-2]) & (e[1:-1] >= e[2:]) & v[a:b][1:-1])[0] + 1
    voiced_s = v[a:b].sum() * HOP_S
    t = {"id": r["id"], "dur": len(x) / SR, "lead": a * HOP_S, "tail": (len(v) - b) * HOP_S, "span": span,
         "voiced_s": voiced_s, "pause_ratio": sum(sil) / span if span else 0, "longest": max(sil, default=0),
         "pauses_gt1": sum(g > 1 for g in sil), "pauses_gt05": sum(g > .5 for g in sil),
         "peak_rate": len(peaks) / max(voiced_s, .5), "peak_rate_span": len(peaks) / max(span, .5),
         "bursts": len(runs(v[a:b])) / max(span, .5), "level_mean": float(db.mean()),
         "level_spread": float(db.std()), "level_p95_50": float(np.percentile(db, 95) - np.median(db)),
         "gaps_a": [round(g, 3) for g in sil]}
    return t


if __name__ == "__main__":
    rows = list(clips())
    with Pool(8) as p:
        out = [f for f in p.imap(features, rows, 16) if f]
    os.makedirs(OUT, exist_ok=True)
    json.dump(out, open(OUT + "/tier_a.json", "w"), default=float)
    print(len(rows), "clips,", len(out), "with audio")
