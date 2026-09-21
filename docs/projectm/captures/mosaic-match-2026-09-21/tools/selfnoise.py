import numpy as np, model as M
FPS = 30; HOST = 16000
def run_shift(engine, shift):   # the audio starts `shift` samples later: a different frame phase
    pr = M.Preset(); rows = []
    for k in range(int(M.SEC * FPS)):
        t = (k + 1) / FPS; upto = int(t * HOST) - shift
        ring = M.audio[max(0, upto - 2048):max(0, upto)]
        if ring.size < 2048: ring = np.concatenate([np.zeros(2048 - ring.size), ring])
        (b, m, tr), _ = engine.step(ring, 1 / FPS)
        rows.append(pr.step(b, m, tr, FPS, 1 / FPS)[:2] + (t,))
    return np.array(rows)
def hits(a, b):
    ta = a[a[:, 0] > 0, 2]; tb = b[b[:, 0] > 0, 2]
    return ta.size, tb.size, np.mean([np.min(np.abs(tb - x)) <= 2.5 / FPS for x in ta]) * 100, (a[:, 1] == b[:, 1]).mean() * 100
for name, mk in [("web", lambda: M.Web()), ("native-raw", lambda: M.Native(False))]:
    ref = run_shift(mk(), 0)
    for sh in (1, 8, 80, 160, 267, 533):
        r = run_shift(mk(), sh); n0, n1, h, same = hits(ref, r)
        print(f"{name:10s} vs itself shifted {sh:4d} samples ({sh / 16:5.1f} ms): beats {n0}/{n1}, within 2 frames {h:5.1f}%, same index {same:5.1f}%")
