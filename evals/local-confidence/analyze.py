#!/usr/bin/env python3
"""Which confidence, and which floor, picks out the bad local transcripts.

    python3 evals/local-confidence/analyze.py evals/local-confidence/out/turbo-lora-400.jsonl

WER against the cloud text, accent- and punctuation-folded. The reference is
Wispr's *formatted* text, so a good take still scores ~15 % (fillers, numbers);
"bad" is ≥ 30 % (and ≥ 50 %). For the worst segment (`avg_logprob`) and the
token-weighted mean (`mean_logprob`): how many takes each floor flags, and how
many of those are bad (precision) out of all the bad ones (recall).
"""
import json, re, sys, unicodedata


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return re.findall(r"[a-z0-9]+", "".join(c for c in s if not unicodedata.combining(c)))


def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    if not r:
        return None
    d = list(range(len(h) + 1))
    for i, a in enumerate(r, 1):
        p, d[0] = d[0], i
        for j, b in enumerate(h, 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (a != b))
    return d[-1] / len(r)


rows = []
for line in open(sys.argv[1]):
    d = json.loads(line)
    if not d.get("ok") or d.get("mean_logprob") is None:
        continue
    w = wer(d["ref"], d["text"])
    if w is not None:
        worst = d["avg_logprob"] if d["avg_logprob"] is not None else -9
        rows.append({"worst": worst, "mean": d["mean_logprob"], "wer": w})
n = len(rows)
for key in ("worst", "mean"):
    for bad_at in (0.3, 0.5):
        bad = sum(r["wer"] >= bad_at for r in rows)
        print(f"[{key}] {n} takes, WER ≥ {bad_at:.0%}: {bad} ({100 * bad / n:.0f} %)")
        for floor in (-0.2, -0.25, -0.3, -0.35, -0.4):
            flagged = [r for r in rows if r[key] < floor]
            hit = sum(r["wer"] >= bad_at for r in flagged)
            print(f"   < {floor}: flags {len(flagged)} ({100 * len(flagged) / n:.0f} %), "
                  f"precision {100 * hit / max(1, len(flagged)):.0f} %, recall {100 * hit / max(1, bad):.0f} %")
