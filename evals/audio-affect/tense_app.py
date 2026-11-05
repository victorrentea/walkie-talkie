"""The tense detector the app runs: pitch from the waveform, nothing else. No words, no recogniser, no level
(the level is the microphone's as much as his). `VoiceTension.swift` is this file's `pitch` and `features`,
line for line. Scored on the teacher's arousal (held-out days) and on the only truth, his blind ear.
    uv run --python 3.12 --with numpy --with scikit-learn python tense_app.py"""
import json, os, sys
import numpy as np
from multiprocessing import Pool
from sklearn.linear_model import Ridge
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score
from common import *

FS = 8000                       # after halving: F0 needs nothing higher
WIN, HOP_P = 320, 160           # 40 ms every 20 ms
LO, HI = FS // 400, FS // 75    # lags: 400 Hz down to 75 Hz
PITCHED, GATE = 0.6, 180.0      # correlation that counts as a voice; the meter's absolute floor


def pitch(x):
    """Semitones over 100 Hz, one per pitched frame."""
    n = len(x) // 2
    y = (x[:2 * n:2] + x[1:2 * n:2]) / 2
    out = []
    for s in range(0, n - WIN - HI, HOP_P):
        a = y[s:s + WIN] - y[s:s + WIN].mean()
        e0 = float(a @ a)
        if (e0 / WIN) ** .5 < GATE: continue
        best = np.zeros(HI + 1)
        for L in range(LO, HI + 1):
            b = y[s + L:s + L + WIN]; b = b - b.mean(); e = float(b @ b)
            if e > 0: best[L] = float(a @ b) / (e0 * e) ** .5
        top = best.max()
        if top < PITCHED: continue
        L = next(k for k in range(LO, HI + 1) if best[k] >= .9 * top)  # the shortest lag: no octave down
        while L < HI and best[L + 1] > best[L]: L += 1                 # up to the peak, not its shoulder
        f = float(L)
        if LO < L < HI:                                                # between two lags
            d = best[L - 1] - 2 * best[L] + best[L + 1]
            if d < 0: f += .5 * (best[L - 1] - best[L + 1]) / d
        out.append(12 * np.log2(FS / f / 100))
    return np.array(out)


def features(p):
    """(median, p95 over the median, spread), in semitones."""
    m = np.median(p)
    return float(m), float(np.percentile(p, 95) - m), float(p.std())


def one(r):
    x = read_wav(os.path.join(CORPUS, r['wav']))
    if x is None: return None
    p = pitch(x)
    return None if len(p) < 150 else {'id': r['id'], 'n': len(p), 'f': features(p)}   # 3 s of pitched voice


if __name__ == '__main__':
    T = json.load(open(OUT + '/tense_rows.json'))
    path = OUT + '/tense_app.json'
    if not os.path.exists(path):
        with Pool(8) as w: rows = [q for q in w.imap(one, T, 8) if q]
        json.dump(rows, open(path, 'w'))
    rows = json.load(open(path)); by = {r['id']: r for r in T}
    print(len(T), 'clips,', len(rows), 'with 3 s of pitched voice')
    X = np.array([r['f'] for r in rows]); y = np.array([by[r['id']]['arz'] for r in rows])
    day = np.array([by[r['id']]['wav'][:10] for r in rows])
    rk = lambda v: np.argsort(np.argsort(v)); sp = lambda p, q: float(np.corrcoef(rk(p), rk(q))[0, 1])
    hi = y >= np.percentile(y, 90)
    for i, n in enumerate(['median', 'p95-med', 'std']):
        print(f'  {n:8s} rho {sp(X[:, i], y):+.3f}  top-decile AUROC {roc_auc_score(hi, X[:, i]):.3f}')
    p = np.zeros(len(y))
    for tr, te in GroupKFold(5).split(X, y, day): p[te] = Ridge(1.0).fit(X[tr], y[tr]).predict(X[te])
    print(f'held-out days, ridge: rho {sp(p, y):.3f}  top-decile AUROC {roc_auc_score(hi, p):.3f}')
    fit = Ridge(1.0).fit(X, y); print('weights', fit.coef_.round(4).tolist(), 'intercept', round(float(fit.intercept_), 4))
    key = {k['id']: k for k in json.load(open(OUT + '/listen/key.json'))}
    last = {}
    for l in open(OUT + '/listen/labels.jsonl'):
        d = json.loads(l); last[d['clip']] = d['label']
    score = dict(zip([r['id'] for r in rows], p))
    ear = [(score[i], last[k['clip']] in ('tense', 'both'), last[k['clip']], k['stratum'], by[i]['arz'] if i in by else None)
           for i, k in key.items() if i in score and k['clip'] in last and last[k['clip']] != 'skip']
    print('his ear:', len(ear), 'clips with a score,', sum(e[1] for e in ear), 'tense; labels', sorted(set(e[2] for e in ear)))
    s = np.array([e[0] for e in ear]); t = np.array([e[1] for e in ear])
    print(f'  AUROC against his ear {roc_auc_score(t, s):.3f}')
    for q in (80, 85, 90, 93, 95, 97):
        th = np.percentile(p, q); f = s >= th
        print(f'  fires on {100 - q}% of his corpus (>= {th:+.2f}): ear tense {int(t[f].sum())} of {int(f.sum())}, elsewhere {int(t[~f].sum())} of {int((~f).sum())}')
    json.dump({'p': p.tolist(), 'ids': [r['id'] for r in rows]}, open(OUT + '/tense_app_p.json', 'w'))
