"""Tense has no labels. A teacher: audEERING's w2v2 (arousal/dominance/valence, trained on natural podcast
speech). Not the product — 200 M parameters, CC-BY-NC-SA — only the yardstick cheap features are held to.
Each clip: up to 3 windows of 8 s over its speech, averaged."""
import json, os, sys, time
import numpy as np, torch, torch.nn as nn
from transformers import Wav2Vec2Model, Wav2Vec2PreTrainedModel, AutoConfig
from common import *
NAME = 'audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim'

class Head(nn.Module):
    def __init__(s, c):
        super().__init__()
        s.dense = nn.Linear(c.hidden_size, c.hidden_size); s.dropout = nn.Dropout(c.final_dropout)
        s.out_proj = nn.Linear(c.hidden_size, c.num_labels)
    def forward(s, x):
        return s.out_proj(s.dropout(torch.tanh(s.dense(s.dropout(x)))))

class Emotion(Wav2Vec2PreTrainedModel):
    def __init__(s, c):
        super().__init__(c); s.wav2vec2 = Wav2Vec2Model(c); s.classifier = Head(c); s.post_init()
    def forward(s, x):
        return s.classifier(s.wav2vec2(x)[0].mean(dim=1))

dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
cfg = AutoConfig.from_pretrained(NAME)
m = Emotion.from_pretrained(NAME, config=cfg).to(dev).eval()
sil = {r['id']: r for r in json.load(open(OUT + '/silero.json'))}
rows = [r for r in clips() if r['id'] in sil]
path = OUT + '/teacher.jsonl'
done = {json.loads(l)['id'] for l in open(path)} if os.path.exists(path) else set()
rows = [r for r in rows if r['id'] not in done]
if len(sys.argv) > 1: rows = rows[:int(sys.argv[1])]
print(dev, len(rows), 'to go', flush=True)
t0 = time.time(); W = 8 * SR
with open(path, 'a') as f, torch.no_grad():
    for i, r in enumerate(rows, 1):
        x = read_wav(os.path.join(CORPUS, r['wav'])) / 32768
        a = int(sil[r['id']]['lead'] * SR); b = min(len(x), a + int((sil[r['id']]['span'] + .2) * SR))
        s = x[a:b] if b - a > SR else x
        st = [0] if len(s) <= W else list(np.linspace(0, len(s) - W, 3).astype(int))
        o = []
        for k in st:
            c = s[k:k + W]; c = (c - c.mean()) / np.sqrt(c.var() + 1e-7)
            o.append(m(torch.from_numpy(c.copy()).float()[None].to(dev)).cpu().numpy()[0])
        o = np.stack(o)
        f.write(json.dumps({'id': r['id'], 'arousal': float(o[:, 0].mean()), 'dominance': float(o[:, 1].mean()),
                            'valence': float(o[:, 2].mean()), 'arousal_max': float(o[:, 0].max())}) + '\n'); f.flush()
        if i % 100 == 0 or i == len(rows): print(i, round((time.time() - t0) / i, 3), 's/clip', flush=True)
