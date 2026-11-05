"""The `[?]`: Wispr gives a text with no timings, the mic gives a pause at second t. Can the pause be put
between the right two words? Estimate: the word count scaled by the share of voiced time before the pause.
Truth: the index of the same pause in Whisper's word gaps (timing.jsonl), paired in order, only in clips
where meter and words see the same number of pauses ≥ the limit."""
import json, os, numpy as np
from common import *
LIM = 2.5
a = {r['id']: r for r in json.load(open(OUT + '/tier_a.json'))}
s = {r['id']: r for r in json.load(open(OUT + '/silero.json'))}
err, rel, nw, n_pairs = [], [], [], 0
seen = cnt_eq = cnt_ne = 0
hit = miss = fa = 0
for r in clips():
    if r['id'] not in a: continue
    gaps = r['gaps']; n = r['n_words']
    wk = [i for i, g in enumerate(gaps) if g >= LIM]
    x = read_wav(os.path.join(CORPUS, r['wav']))
    rms, v = meter(x)
    idx = np.where(v)[0]; lo, hi = idx[0], idx[-1] + 1
    pa = [(s0 + lo, e0 + lo) for s0, e0 in runs(~v[lo:hi]) if (e0 - s0) * HOP_S >= LIM]
    hit += min(len(wk), len(pa)); miss += max(0, len(wk) - len(pa)); fa += max(0, len(pa) - len(wk))
    if not wk and not pa: continue
    seen += 1
    if len(wk) != len(pa): cnt_ne += 1; continue
    cnt_eq += 1
    total = v[lo:hi].sum()
    # Longest-silence hops are not speech, so the share is of voiced hops, as the app could compute it.
    for k, (p, _) in zip(wk, pa):
        share = v[lo:p].sum() / total
        est = share * n - 1            # gap k sits after word k (0-based)
        err.append(abs(est - k)); rel.append(abs(est - k) / n); nw.append(n)
e = np.array(err); print('pauses ≥ 2.5 s: word gaps paired', hit, ' words only', miss, ' meter only', fa)
print('clips with any', seen, 'same count', cnt_eq, 'different', cnt_ne)
print(f'placed {len(e)}  median err {np.median(e):.1f} words  p75 {np.percentile(e,75):.1f}  p90 {np.percentile(e,90):.1f}  within 1: {(e<=1).mean():.0%}  within 3: {(e<=3).mean():.0%}  within 5: {(e<=5).mean():.0%}  median clip {np.median(nw):.0f} words')
