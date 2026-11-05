"""The verdict again, now with two truths: the app's word verdict (Whisper timings) and the same rule measured
by Silero (a witness with no words). Tiers: A = the app's hops; B = + Silero; C = + F0 / filled pauses."""
import json, numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier as GB
from sklearn.model_selection import GroupKFold
from sklearn.metrics import roc_auc_score, precision_recall_curve
from common import *
a = {r['id']: r for r in json.load(open(OUT + '/tier_a.json'))}
s = {r['id']: r for r in json.load(open(OUT + '/silero.json'))}
b = {r['id']: r for r in json.load(open(OUT + '/tier_b.json'))}
R = [r for r in clips() if r['id'] in a and r['id'] in s and r['id'] in b and (r.get('n_words') or 0) >= 5]
day = np.array([r['ts'][:10] for r in R])

def A(r):
    t = a[r['id']]; g = np.array(t['gaps_a'] or [0.]); sp = max(t['span'], .5)
    return [t['lead'], t['tail'], t['span'], t['dur'], t['pause_ratio'], t['longest'], t['pauses_gt1'], t['pauses_gt05'],
            g[g > .3].sum() / sp, g[g > .5].sum() / sp, g[g > 1].sum() / sp, (g > 2.5).sum(), t['peak_rate_span'], t['bursts'], t['voiced_s'] / sp]
def S(r):
    t = s[r['id']]; g = np.array(t['gaps'] or [0.]); sp = max(t['span'], .5)
    return [t['lead'], t['span'], t['pause_ratio'], t['pauses_gt1'], t['longest'], g[g > .5].sum() / sp, g[g > 1].sum() / sp, (g > 2.5).sum(), t['seg'] / sp]
def C(r):
    t = b[r['id']]; return [t['f0_std'], t['f0_slope'], t['voiced_frac'], t['fill'] / max(a[r['id']]['span'], .5), t['fill_s'] / max(a[r['id']]['span'], .5)]
XA = np.array([A(r) for r in R], float); XS = np.array([S(r) for r in R], float); XC = np.array([C(r) for r in R], float)

def cv(x, y):
    p = np.zeros(len(y))
    for tr, te in GroupKFold(5).split(x, y, day):
        p[te] = GB(max_depth=3, max_iter=150, learning_rate=.05).fit(x[tr], y[tr]).predict_proba(x[te])[:, 1]
    return p
def rep(t, y, p):
    pr, rc, _ = precision_recall_curve(y, p)
    f = lambda q: rc[pr >= q].max() if (pr >= q).any() else 0
    print(f'{t:44s} +{int(y.sum()):4d}/{len(y)} AUROC {roc_auc_score(y,p):.3f}  R@P.8 {f(.8):.2f}  R@P.7 {f(.7):.2f}  P@R.5 {pr[rc>=.5].max():.2f}')

word = np.array([word_verdict(r) for r in R], int)
def sil_v(r):
    t = s[r['id']]; sp = t['span']
    n = r.get('n_words') or 0
    sig = [t['pause_ratio'] >= .35, t['pauses_gt1'] >= 4, sp >= 4 and n / max(sp, .1) < 1.4, t['lead'] > 3.0]
    return sum(sig) >= 2
sv = np.array([sil_v(r) for r in R], int)
both = word & sv; eith = word | sv
print('word+', word.sum(), 'silero+', sv.sum(), 'both', both.sum(), 'either', eith.sum(), 'jaccard %.2f' % (both.sum() / eith.sum()))
print('--- truth = word verdict')
for n, x in (('A hops', XA), ('A+B silero', np.c_[XA, XS]), ('A+B+C f0/fill', np.c_[XA, XS, XC]), ('B alone', XS)):
    rep(n, word, cv(x, word))
print('--- truth = both witnesses agree (excluding clips where they disagree)')
keep = (word == sv)
for n, x in (('A hops', XA), ('A+B silero', np.c_[XA, XS]), ('A+B+C', np.c_[XA, XS, XC])):
    p = cv(x, both); rep(n, both[keep], p[keep])
p = cv(np.c_[XA, XS, XC], word)
np.save(OUT + '/hes_p.npy', p); json.dump([r['id'] for r in R], open(OUT + '/hes_ids.json', 'w'))
# How much of the rate survives
w = np.array([r.get('rate') or 0 for r in R])
rk = lambda v: np.argsort(np.argsort(v))
print('rate~bursts', round(float(np.corrcoef(rk(w), rk(XA[:, 13]))[0, 1]), 3))
# filled pauses vs Scribe: does `fill` see them?
