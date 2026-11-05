"""The only real truth: Victor's ear. 40 clips, blind (no text, no score), the strata hidden in key.json:
what each detector claims, against what he hears. Answers go to out/listen/labels.jsonl via a local server.
    python listen.py build    # picks the clips, cuts them
    python listen.py serve    # http://127.0.0.1:8767
    python listen.py score"""
import http.server, json, os, random, subprocess, sys
import numpy as np
from common import *
D = OUT + '/listen'; PORT = 8767

def build():
    os.makedirs(D, exist_ok=True); random.seed(20261105)
    ids = json.load(open(OUT + '/hes_ids.json')); p = np.load(OUT + '/hes_p.npy')
    C = {r['id']: r for r in clips()}
    th = np.sort(p)[-int(len(p) * .12)]          # the audio verdict's positives: about the word verdict's base rate
    T = {r['id']: r for r in json.load(open(OUT + '/tense_rows.json'))}
    arz = np.array([r['arz'] for r in T.values()])
    def ok(i): return 8 <= C[i]['seconds'] <= 45
    w = {i: word_verdict(C[i]) for i in ids}; a = dict(zip(ids, p >= th))
    pick = {}
    def take(tag, pool, n):
        pool = [i for i in pool if ok(i) and i not in pick]; random.shuffle(pool)
        for i in pool[:n]: pick[i] = tag
    take('H_both', [i for i in ids if w[i] and a[i]], 8)
    take('H_audio_only', [i for i in ids if a[i] and not w[i]], 8)
    take('H_words_only', [i for i in ids if w[i] and not a[i]], 6)
    top = sorted(T.values(), key=lambda r: -r['arz'])[:len(T) // 10]
    take('T_arousal_annoyed', [r['id'] for r in top if r['annoyed'] >= 2], 5)
    take('T_arousal_calm', [r['id'] for r in top if r['annoyed'] == 0], 5)
    take('T_words_only', [r['id'] for r in T.values() if r['annoyed'] >= 2 and r['arz'] < .5], 3)
    take('neutral', [i for i in ids if not w[i] and not a[i] and i in T and abs(T[i]['arz']) < 1 and T[i]['annoyed'] == 0], 5)
    items = list(pick.items()); random.shuffle(items)
    key = []
    for n, (i, tag) in enumerate(items, 1):
        name = f'c{n:02d}.m4a'
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', os.path.join(CORPUS, C[i]['wav']), '-t', '30', '-c:a', 'aac', '-b:a', '64k', f'{D}/{name}'], check=True)
        key.append({'clip': name, 'id': i, 'stratum': tag})
    json.dump(key, open(D + '/key.json', 'w'), indent=0)
    print(len(key), 'clips'); print({t: sum(k['stratum'] == t for k in key) for t in set(pick.values())})

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=HERE, **k)
    def log_message(s, *a): pass
    def do_GET(s):
        if s.path == '/clips':
            names = sorted(k['clip'] for k in json.load(open(D + '/key.json')))
            done = [json.loads(l)['clip'] for l in open(D + '/labels.jsonl')] if os.path.exists(D + '/labels.jsonl') else []
            b = json.dumps({'clips': names, 'done': done}).encode(); s.send_response(200); s.send_header('content-type', 'application/json'); s.end_headers(); s.wfile.write(b); return
        if s.path == '/' : s.path = '/listen.html'
        if s.path.endswith('.m4a'): s.path = '/out/listen/' + os.path.basename(s.path)
        elif s.path != '/listen.html': s.send_error(404); return
        super().do_GET()
    def do_POST(s):
        d = json.loads(s.rfile.read(int(s.headers['content-length'])))
        with open(D + '/labels.jsonl', 'a') as f: f.write(json.dumps({'clip': d['clip'], 'label': d['label']}) + '\n')
        s.send_response(204); s.end_headers()

def score():
    key = {k['clip']: k['stratum'] for k in json.load(open(D + '/key.json'))}
    last = {}
    for l in open(D + '/labels.jsonl'):
        d = json.loads(l); last[d['clip']] = d['label']
    import collections
    t = collections.defaultdict(collections.Counter)
    for c, l in last.items(): t[key[c]][l] += 1
    for k in sorted(t): print(f'{k:20s}', dict(t[k]))
    h = lambda ks: (sum(t[k]['hesitant'] + t[k]['both'] for k in ks), sum(sum(t[k].values()) for k in ks))
    print('audio verdict precision', h(['H_both', 'H_audio_only']), ' word verdict precision', h(['H_both', 'H_words_only']))

if __name__ == '__main__':
    {'build': build, 'score': score, 'serve': lambda: http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()}[sys.argv[1]]()
