"""Who is right when the meter and Whisper's timings disagree? Two independent witnesses: Silero (no words)
and Scribe (the words the feature actually runs on, with spacing tokens)."""
import json, os, re, numpy as np, datetime as dt
from common import *
from tier_a import features
rk = lambda v: np.argsort(np.argsort(v))
sp = lambda a, b: float(np.corrcoef(rk(np.array(a, float)), rk(np.array(b, float)))[0, 1])
a = {r['id']: r for r in json.load(open(OUT + '/tier_a.json'))}
s = {r['id']: r for r in json.load(open(OUT + '/silero.json'))}
R = [r for r in clips() if r['id'] in a and r['id'] in s]
print('n', len(R))
for k in ('lead', 'pause_ratio', 'pauses_gt1', 'longest'):
    w = [r.get(k) or 0 for r in R]; m = [a[r['id']][k] for r in R]; v = [s[r['id']][k] for r in R]
    print(f'{k:12s} word~silero {sp(w,v):.3f}  meter~silero {sp(m,v):.3f}  word~meter {sp(w,m):.3f}   medians w {np.median(w):.2f} m {np.median(m):.2f} s {np.median(v):.2f}')
# Lead disagreement: |w-s| large
big = [r for r in R if abs((r.get('lead') or 0) - s[r['id']]['lead']) > 1.5]
print('lead off by >1.5s word vs silero:', len(big), 'meter within .3 of silero in', sum(abs(a[r['id']]['lead'] - s[r['id']]['lead']) < .3 for r in big))
w3 = [r for r in R if (r.get('lead') or 0) > 3]
print('word lead>3:', len(w3), ' silero agrees:', sum(s[r['id']]['lead'] > 3 for r in w3), ' meter agrees:', sum(a[r['id']]['lead'] > 3 for r in w3))
s3 = [r for r in R if s[r['id']]['lead'] > 3]
print('silero lead>3:', len(s3), ' word agrees:', sum((r.get('lead') or 0) > 3 for r in s3), ' meter agrees:', sum(a[r['id']]['lead'] > 3 for r in s3))

# Scribe: outbox `affect` joined to the corpus by the words.
norm = lambda t: re.sub(r'\W+', ' ', re.sub(r'\[\?\]', '', t or '').lower()).strip()
cor = []
for l in open(CORPUS + '/corpus.jsonl'):
    try: d = json.loads(l)
    except: continue
    if d.get('engine') == 'elevenlabs': cor.append(d)
by = {norm(d['text'])[:80]: d for d in cor}
J = []
for l in open(os.path.expanduser('~/.walkie-talkie/outbox.jsonl')):
    try: r = json.loads(l)
    except: continue
    f = r.get('affect')
    if not f or (r.get('delivery') or {}).get('via') not in ('elevenlabs-scribe', 'scribe-guard'): continue
    d = by.get(norm(r.get('text'))[:80])
    if d: J.append((r, f, d))
print('scribe joined', len(J), 'of 91; hesitant', sum(f['verdict'] != 'none' for _, f, _ in J))
rows = []
for r, f, d in J:
    t = features({'id': d['id'], 'wav': d['wav']})
    if t: rows.append((f, t))
print('with audio', len(rows))
for k_s, k_m in (('lead', 'lead'), ('pauseRatio', 'pause_ratio'), ('pausesOver', 'pauses_gt1'), ('span', 'span'), ('rate', 'peak_rate_span'), ('rate', 'bursts')):
    x = [f.get(k_s) or 0 for f, _ in rows]; y = [t[k_m] for _, t in rows]
    print(f'scribe {k_s:10s} ~ meter {k_m:15s} {sp(x,y):.3f}  median {np.median(x):.2f} / {np.median(y):.2f}')
json.dump([(f, t) for f, t in rows], open(OUT + '/scribe_join.json', 'w'), default=float)
