import json, os, sys, io, contextlib, re
import numpy as np, mlx_whisper
from mlx_whisper import audio as A
src = open("/Users/victorrentea/workspace/walkie-talkie/helpers/whisper_helper.py").read()
code = src[src.index("def _voice_meter(samples):"):src.index("\ndef coverage(res):")]
ns = {"np": np, "A": A, "sys": sys}; exec(code, ns)
M = sys.argv[1]
root = os.path.expanduser("~/.walkie-talkie/voice-corpus")
def run(samples, lang=None):
    with contextlib.redirect_stdout(io.StringIO()):
        return mlx_whisper.transcribe(samples, path_or_hf_repo=M, language=lang, verbose=False,
                                      condition_on_previous_text=False, word_timestamps=True, temperature=0.0)
def check(label, samples, lang=None):
    res = run(samples, lang)
    later = [s for s in res["segments"] if s.get("seek", 0) != 0]
    before = res["text"]
    ns["first_window_only"](res, True, samples)
    kept = [s for s in res["segments"] if s.get("seek", 0) != 0]
    print(f"{label}: later={len(later)} kept={len(kept)}")
    for s in later:
        v = ns["_voice_meter"](samples)(s["start"], s["end"])
        print(f"    {'KEPT ' if s in kept else 'DROP '} [{s['start']:.1f}-{s['end']:.1f}] voiced {v:.2f}s {s['text'][:70]!r}")
# (a) the clip that lost real words
a = A.load_audio(os.path.join(root, "2026-08-04/14-44-20-b0bb7123.wav"))
check("14-44-20 (real words in window 2)", a)
# (b) chunk-like clips: 9-15 s of speech + 1.6 s of digital silence
rows = []
for l in open(os.path.join(root, "corpus.jsonl")):
    try: r = json.loads(l)
    except Exception: continue
    if 9 <= (r.get("duration") or 0) <= 15 and os.path.exists(os.path.join(root, r["wav"])): rows.append(r)
for r in rows[-400::40][:8]:
    x = np.asarray(A.load_audio(os.path.join(root, r["wav"])))
    x = np.concatenate([x, np.zeros(int(1.6 * 16000), np.float32)])
    check(f"{r['wav'][-30:]} + 1.6 s silence", x)
