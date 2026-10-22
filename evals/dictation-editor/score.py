import json, re, sys, statistics as st
B = sys.argv[1]
P = {json.loads(l)["id"]: json.loads(l) for l in open(f"{B}/pairs.jsonl")}
def words(s): return re.findall(r"\w+", s.lower())
def ed(a, b):
    d = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        p, d[0] = d[0], i
        for j, y in enumerate(b, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (x != y))
    return d[-1]
def wer(r, h): return ed(words(r), words(h)) / max(1, len(words(r)))
def cer(r, h): return ed(r.strip(), h.strip()) / max(1, len(r.strip()))
print(f"{'':10s} {'n':>4s} {'WER→Wispr':>10s} {'CER→Wispr':>10s} {'exact':>6s} {'drift>30%':>9s} {'lat med':>8s} {'p90':>6s}")
base = [(wer(p["ref"], p["asr"]), cer(p["ref"], p["asr"])) for p in P.values()]
print(f"{'raw ASR':10s} {len(base):4d} {st.mean(b[0] for b in base):10.1%} {st.mean(b[1] for b in base):10.1%} {sum(p['asr'].strip()==p['ref'].strip() for p in P.values()):6d}")
for name in sys.argv[2:]:
    rows = [json.loads(l) for l in open(f"{B}/{name}.jsonl")]
    W = [wer(P[r["id"]]["ref"], r["out"]) for r in rows]
    C = [cer(P[r["id"]]["ref"], r["out"]) for r in rows]
    drift = sum(wer(P[r["id"]]["asr"], r["out"]) > 0.3 for r in rows)
    exact = sum(P[r["id"]]["ref"].strip() == r["out"].strip() for r in rows)
    S = sorted(r["s"] for r in rows)
    print(f"{name:10s} {len(rows):4d} {st.mean(W):10.1%} {st.mean(C):10.1%} {exact:6d} {drift:9d} {st.median(S):7.2f}s {S[int(len(S)*.9)]:5.2f}s")
