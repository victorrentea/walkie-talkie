#!/usr/bin/env python3
"""Beat index (q23) over time per run, aligned on the AUDIO each engine saw (the clip's envelope:
web `wave_abs_mean` at 10 Hz, native [pmspec] wave_abs_mean per frame), cross-correlated against
the first run. Then per pair: beats within ±100 ms, and the share of 30 Hz ticks (2..10 s of the
reference) with the same index. usage: index2.py <ref.log> <other.log>..."""
import sys, re, json, numpy as np
sys.path.insert(0, __file__.rsplit("/", 1)[0]); import model as M
G = np.arange(0, 12, 1 / 30)
def load(path):
    lines = open(path).read().splitlines()
    md = [json.loads(re.search(r'\{.*\}', l).group(0)) for l in lines if "[mdaudio]" in l]
    if md:
        t = np.array([x["time"] for x in md]); q = np.array([x["q23"] for x in md]); env = np.array([x["wave_abs_mean"] for x in md])
        beats = [t[i] for i in range(1, len(q)) if q[i] != q[i - 1]]
        return t, q, np.interp(G, t, env, left=0, right=0), beats
    pm = [json.loads(l.split("[pmaudio] ", 1)[1]) for l in lines if "[pmaudio]" in l]
    ps = {json.loads(l.split("[pmspec] ", 1)[1])["frame"]: json.loads(l.split("[pmspec] ", 1)[1])["wave_abs_mean"] for l in lines if "[pmspec]" in l}
    pr = M.Preset(); t, q, beats, env = [], [], [], []
    for r in pm:
        b, i, _, _ = pr.step(r["bass"], r["mid"], r["treb"], 30, 1 / 30)
        tt = r["frame"] / 30; t.append(tt); q.append(i); env.append(ps.get(r["frame"], 0))
        if b: beats.append(tt)
    return np.array(t), np.array(q), np.interp(G, t, env, left=0, right=0), beats
R = {p.split("/")[-1].replace(".log", ""): load(p) for p in sys.argv[1:]}
keys = list(R); ref = R[keys[0]][2]; ref = (ref - ref.mean()) / (ref.std() or 1)
lag = {}
for k in keys:
    e = R[k][2]; e = (e - e.mean()) / (e.std() or 1)
    best = max(range(-90, 91), key=lambda s: np.dot(ref[max(0, s):len(G) + min(0, s)], e[max(0, -s):len(G) - max(0, s)]) / (len(G) - abs(s)))
    lag[k] = best / 30   # seconds to ADD to k's clock to land on the reference's
    t, q, _, b = R[k]; print(f"{k:12s} lag {lag[k]:+.2f} s, {len(b):2d} beats at " + " ".join(f"{x + lag[k]:.2f}" for x in b))
def at(t, q, x): return q[np.searchsorted(t, x, side="right") - 1] if x >= t[0] else -1
grid = np.arange(2.0, 10.0, 1 / 30)
print("\n| pair | beats a/b (2..10 s) | a's beats within 100 ms of a b beat | same index over 2..10 s |")
print("|---|---|---|---|")
for i in range(len(keys)):
    for j in range(i + 1, len(keys)):
        a, b = keys[i], keys[j]; (ta, qa, _, ba), (tb, qb, _, bb) = R[a], R[b]
        ba = [x + lag[a] for x in ba if 2 <= x + lag[a] <= 10]; bb = [x + lag[b] for x in bb if 2 <= x + lag[b] <= 10]
        hit = np.mean([min(abs(np.array(bb) - x)) <= 0.1 for x in ba]) * 100 if ba and bb else 0
        same = np.mean([at(ta, qa, x - lag[a]) == at(tb, qb, x - lag[b]) for x in grid]) * 100
        print(f"| {a} vs {b} | {len(ba)}/{len(bb)} | {hit:.0f}% | {same:.0f}% |")
