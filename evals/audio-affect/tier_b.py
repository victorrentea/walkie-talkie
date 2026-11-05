"""Tier B: the waveform itself, cheap enough for a Mac app. F0 (praat), level against his own voiced
median, and a filled-pause finder: ≥ 0.3 s voiced at a nearly flat F0 and steady level — an „ăăă" has no
word in it, so it needs no recogniser."""
import json, os
import numpy as np, parselmouth
from multiprocessing import Pool
from common import *
from common import runs

def one(r):
    x = read_wav(os.path.join(CORPUS, r['wav']))
    if x is None or len(x) < SR: return None
    snd = parselmouth.Sound(x.astype(np.float64) / 32768, sampling_frequency=SR)
    p = snd.to_pitch(time_step=.01, pitch_floor=70, pitch_ceiling=350)
    f = p.selected_array['frequency']; v = f > 0
    if v.sum() < 30: return None
    st = 12 * np.log2(f[v] / np.median(f[v]))
    fill, fill_s = 0, 0.
    for a, b in runs(v):
        if b - a < 30: continue
        n = 12 * np.log2(f[a:b] / np.median(f[a:b]))
        # sliding 300 ms: flat within ±0.6 semitone
        w = 30
        flat = np.array([n[k:k + w].max() - n[k:k + w].min() < 1.2 for k in range(0, b - a - w + 1, 5)])
        if flat.any():
            fill += 1; fill_s += flat.sum() * .05
    intensity = snd.to_intensity(time_step=.01, minimum_pitch=70).values[0]
    ii = intensity[intensity > np.median(intensity) - 5] if len(intensity) else np.zeros(1)
    return {'id': r['id'], 'f0_med': float(np.median(f[v])), 'f0_p95': float(np.percentile(st, 95)), 'f0_p5': float(np.percentile(st, 5)),
            'f0_std': float(st.std()), 'f0_slope': float(np.abs(np.diff(st)).mean()) * 100, 'voiced_frac': float(v.mean()),
            'int_std': float(ii.std()), 'int_p95': float(np.percentile(ii, 95)), 'fill': fill, 'fill_s': float(fill_s),
            'f0_hi_share': float((st > 3).mean())}

if __name__ == '__main__':
    rows = list(clips())
    with Pool(6) as p:
        o = [x for x in p.imap(one, rows, 8) if x]
    json.dump(o, open(OUT + '/tier_b.json', 'w'), default=float); print(len(o))
