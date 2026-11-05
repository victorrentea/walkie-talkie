"""An arbiter that saw neither the words nor the app's meter: Silero VAD over every clip."""
import json, os
import numpy as np
from multiprocessing import Pool
from common import *

def init():
    global M, F
    import torch; torch.set_num_threads(1)
    from silero_vad import load_silero_vad, get_speech_timestamps as F
    M = load_silero_vad(onnx=False)

def one(r):
    import torch
    x = read_wav(os.path.join(CORPUS, r['wav']))
    if x is None or len(x) < SR: return None
    ts = F(torch.from_numpy(x / 32768), M, sampling_rate=SR, min_silence_duration_ms=120, speech_pad_ms=30)
    if not ts: return None
    seg = [(t['start'] / SR, t['end'] / SR) for t in ts]
    gaps = [seg[i + 1][0] - seg[i][1] for i in range(len(seg) - 1)]
    span = seg[-1][1] - seg[0][0]
    return {'id': r['id'], 'lead': seg[0][0], 'span': span, 'gaps': [round(g, 3) for g in gaps], 'seg': len(seg),
            'pause_ratio': sum(gaps) / max(span, .5), 'pauses_gt1': sum(g > 1 for g in gaps), 'longest': max(gaps, default=0)}

if __name__ == '__main__':
    rows = list(clips())
    with Pool(8, init) as p:
        out = [o for o in p.imap(one, rows, 8) if o]
    json.dump(out, open(OUT + '/silero.json', 'w'), default=float)
    print(len(out))
