import sys, os, io, wave, numpy as np
os.environ["RELAY_WHISPER_MODEL"] = sys.argv[1]
sys.path.insert(0, "/Users/victorrentea/workspace/walkie-talkie/helpers")
si, so = sys.stdin, sys.stdout
sys.stdin, sys.stdout = io.StringIO(""), io.StringIO()
try:
    import whisper_helper as wh
finally:
    sys.stdin, sys.stdout = si, so
W = "/tmp/wt-plan"
def rd(p):
    w = wave.open(p); x = np.frombuffer(w.readframes(w.getnframes()), np.int16); return x
take = rd(f"{W}/chunk-markers-take.wav")
L = {n: len(rd(f"{W}/chunk-markers-{n}.wav")) / 16000 for n in ("2a", "2b", "3a", "3b")}
t2 = 9.5 + 1.4 + L["2a"]; g1 = t2 + 0.3
t3 = t2 + 0.6 + L["2b"] + 1.4 + L["3a"]; g2 = t3 + 0.3
cut1 = 9.5 + 0.7; cut2 = 9.5 + 1.4 + L["2a"] + 0.6 + L["2b"] + 0.7
x = take.astype(np.float32) / 32768
def dec(samples):
    r = wh.transcribe("x", words=True, samples=samples)
    return wh.timed_words(r, r.get("_samples"))
def place(words, t, label):
    k = next((i for i, w in enumerate(words) if w["start"] >= t), len(words))
    before = "".join(w["text"] for w in words[max(0, k - 4):k]); after = "".join(w["text"] for w in words[k:k + 4])
    print(f"  {label} t={t:.2f}: …{before} [📸] {after}…")
    if k < len(words): print(f"      next word '{words[k]['text']}' starts {words[k]['start']:.2f}, previous ends {words[k-1]['end']:.2f}")
print("gaps (file s):", round(g1, 2), round(g2, 2), "cuts:", round(cut1, 2), round(cut2, 2))
print("A) whole take:")
ww = dec(x)
place(ww, g1, "📸1"); place(ww, g2, "📸2")
print("B) chunked at the 1.4 s gaps:")
cw = []
for a, b in ((0, cut1), (cut1, cut2), (cut2, len(x) / 16000)):
    seg = x[int(a * 16000):int(b * 16000)]
    for w in dec(seg):
        cw.append({"text": w["text"], "start": w["start"] + a, "end": w["end"] + a})
place(cw, g1, "📸1"); place(cw, g2, "📸2")
