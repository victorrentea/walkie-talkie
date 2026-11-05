"""Tense. Two yardsticks, neither of them Victor: the teacher's arousal (audio) and Haiku's annoyance (words).
Everything is normalised per microphone + language first — raw acoustics are mostly who and where."""
import json, numpy as np, collections
from sklearn.ensemble import HistGradientBoostingRegressor as GR, HistGradientBoostingClassifier as GC
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score, precision_recall_curve
from common import *
a = {r['id']: r for r in json.load(open(OUT + '/tier_a.json'))}
b = {r['id']: r for r in json.load(open(OUT + '/tier_b.json'))}
t = {}
for l in open(OUT + '/teacher.jsonl'):
    d = json.loads(l); t[d['id']] = d
y = {}
for l in open(OUT + '/text_labels.jsonl'):
    d = json.loads(l); y[d['id']] = d['annoyed']
R = [r for r in clips() if all(r['id'] in q for q in (a, b, t, y)) and a[r['id']]['voiced_s'] > 3]
print(len(R), 'clips; annoyed', sorted(collections.Counter(y[r['id']] for r in R).items()))
grp = np.array([r['mic'] + '|' + r['language'] for r in R]); day = np.array([r['ts'][:10] for r in R])
A = 'level_mean level_spread level_p95_50'.split(); B = 'f0_med f0_p95 f0_std f0_slope f0_hi_share int_std int_p95 voiced_frac'.split()
X = np.array([[a[r['id']][k] for k in A] + [b[r['id']][k] for k in B] + [a[r['id']]['bursts'], a[r['id']]['peak_rate_span']] for r in R], float)
names = A + B + ['bursts', 'peak_rate']
def z(v, g):
    v = v.astype(float).copy()
    for k in set(g):
        m = g == k; med = np.median(v[m], axis=0); v[m] = (v[m] - med) / (1.4826 * np.median(np.abs(v[m] - med), axis=0) + 1e-6)
    return v
Z = z(X, grp)
ar = np.array([t[r['id']]['arousal'] for r in R]); val = np.array([t[r['id']]['valence'] for r in R]); dom = np.array([t[r['id']]['dominance'] for r in R])
arz = z(ar[:, None], grp)[:, 0]; valz = z(val[:, None], grp)[:, 0]
ann = np.array([y[r['id']] for r in R])
rk = lambda v: np.argsort(np.argsort(v)); sp = lambda p, q: float(np.corrcoef(rk(p), rk(q))[0, 1])
print('arousal raw: by group', {k[:22]: round(float(np.median(ar[grp == k])), 3) for k in sorted(set(grp))})
print('--- single features vs arousal z (within mic+lang)')
for i, n in sorted(enumerate(names), key=lambda q: -abs(sp(Z[:, q[0]], arz))):
    print(f'  {n:14s} {sp(Z[:, i], arz):+.3f}')
def cvr(x, v):
    p = np.zeros(len(v))
    for tr, te in GroupKFold(5).split(x, v, day): p[te] = GR(max_depth=3, max_iter=200, learning_rate=.05).fit(x[tr], v[tr]).predict(x[te])
    return p
ia = [names.index(k) for k in A]; ib = [names.index(k) for k in B] ; ir = [names.index('bursts'), names.index('peak_rate')]
pa = cvr(Z[:, ia + ir], arz); pb = cvr(Z, arz)
print(f'predict arousal, held-out days: tier A (hops) rho {sp(pa, arz):.3f}   tier A+F0 rho {sp(pb, arz):.3f}')
hi = arz >= np.percentile(arz, 90)
for tag, p in (('A', pa), ('A+F0', pb)):
    pr, rc, _ = precision_recall_curve(hi, p)
    print(f'  top-decile arousal, {tag}: AUROC {roc_auc_score(hi, p):.3f}  P@R.5 {pr[rc >= .5].max():.2f}')
print('--- does audio rise on clips annoyed in the WORDS? (AUROC annoyed≥2 vs 0; 0.5 = no)')
m = (ann >= 2) | (ann == 0); yy = (ann >= 2)[m]
print(' n', int(yy.sum()), 'vs', int((~yy).sum()))
for n, v in [('teacher arousal z', arz), ('teacher valence z (low=negative)', -valz), ('teacher arousal-valence', arz - valz), ('tier A model of arousal', pa), ('A+F0 model of arousal', pb)] + [(k, Z[:, names.index(k)]) for k in ('level_spread', 'f0_p95', 'f0_std', 'level_mean')]:
    print(f'  {n:34s} {roc_auc_score(yy, v[m]):.3f}')
m3 = ann >= 0
print(' annoyed≥2 rate in top arousal decile vs rest: %.1f%% vs %.1f%%' % (100 * (ann[hi] >= 2).mean(), 100 * (ann[~hi] >= 2).mean()))
print('--- today\'s rule (level spread ≥ 9 dB, raw)')
raw = X[:, names.index('level_spread')]; f = raw >= 9
print(f' fires on {f.mean():.1%}; by mic', {k[:14]: round(float((raw[grp == k] >= 9).mean()), 2) for k in sorted(set(grp))})
print(f' annoyed≥2 among fired {100 * (ann[f] >= 2).mean():.1f}% vs not {100 * (ann[~f] >= 2).mean():.1f}%;  top-decile arousal among fired {100 * hi[f].mean():.1f}%')
# Candidates for the listening test.
json.dump([{'id': r['id'], 'wav': r['wav'], 'arz': float(arz[i]), 'valz': float(valz[i]), 'annoyed': int(ann[i]), 'text': r['text'][:400], 'p': float(pb[i])} for i, r in enumerate(R)], open(OUT + '/tense_rows.json', 'w'))
