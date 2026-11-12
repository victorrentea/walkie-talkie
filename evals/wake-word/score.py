import sys, numpy as np, soundfile as sf
from openwakeword.model import Model
m = Model(wakeword_models=[sys.argv[1]], inference_framework="onnx")
key = list(m.models.keys())[0]
for path in sys.argv[2:]:
    a, sr = sf.read(path, dtype="int16")
    if a.ndim > 1: a = a[:, 0]
    assert sr == 16000, (path, sr)
    a = np.concatenate([np.zeros(16000, np.int16), a, np.zeros(16000, np.int16)])
    m.reset()
    peak, at = 0.0, 0
    for i in range(0, len(a) - 1280, 1280):
        s = m.predict(a[i:i+1280])[key]
        if s > peak: peak, at = s, i / 16000 - 1
    print(f"{peak:.3f}\t{at:6.1f}s\t{path}")
