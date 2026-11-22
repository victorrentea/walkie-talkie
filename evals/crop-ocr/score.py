#!/usr/bin/env python3
"""Scores Vision OCR (three configs) and Haiku against the reference model's reading, per stratum.
CER/WER on whitespace-collapsed NFC text (order-sensitive); word recall/precision are order-free,
which is the fairer number for UI crops where reading order is arbitrary. Prints tables only.

    python3 evals/crop-ocr/score.py [--ref fable]
"""
import argparse, collections, json, pathlib, re, statistics, unicodedata

OUT = pathlib.Path(__file__).parent / "out"
MONO_APPS = {"Terminal", "Code", "IntelliJ IDEA", "Xcode", "iTerm2"}
DIACRITICS = set("ăâîșțĂÂÎȘȚşţŞŢ")


def norm(s):
    s = unicodedata.normalize("NFC", s or "")
    return re.sub(r"\s+", " ", s).strip()


def lev(a, b):
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[-1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def words(s):
    return re.findall(r"[^\W_]+", s.lower())


def load(name):
    p = OUT / name
    return {json.loads(l)["id"]: json.loads(l) for l in open(p)} if p.exists() else {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", default="fable")
    a = ap.parse_args()
    crops = load("crops.jsonl")
    ref = {i: r for i, r in load(f"read-{a.ref}.jsonl").items() if r.get("text") is not None}
    haiku = load("read-haiku.jsonl")
    ocr = collections.defaultdict(dict)
    for l in open(OUT / "ocr.jsonl"):
        r = json.loads(l)
        ocr[r["config"]][pathlib.Path(r["file"]).stem] = r
    cands = {c: {i: "\n".join(x["t"] for x in r["lines"]) for i, r in d.items()} for c, d in ocr.items()}
    cands["haiku"] = {i: r.get("text") or "" for i, r in haiku.items()}

    def strata(i):
        r, c = ref[i], crops[i]
        out = ["all"] if not c.get("synthetic") else []
        win = (c.get("window") or "").split(" — ")[0]             # the frame's own front window, not the prompt's app
        out.append("mono, real crops" if (win in MONO_APPS or r.get("content") in ("code", "terminal")) and not c.get("synthetic") else
                   "mono, bands cut from terminal/IDE frames (synth_mono.py)" if c.get("synthetic") else
                   "prose" if r.get("content") == "prose" else "ui labels / mixed")
        if any(ch in DIACRITICS for ch in r["text"]) or r.get("language") in ("ro", "mixed"):
            out.append("romanian")
        lines = ocr["accurate"].get(i, {}).get("lines") or []
        if lines:
            hpx = statistics.median(x["h"] * c["h"] for x in lines)
            out.append("small text (line box < 26 px)" if hpx < 26 else "larger text")
        if r.get("cut"):
            out.append("line cut by the edge")
        return out

    rows = collections.defaultdict(lambda: collections.defaultdict(list))
    per_crop = []
    for i, r in ref.items():
        R = norm(r["text"])
        if len(R) < 2:
            continue
        rw = collections.Counter(words(R))
        rec = {"id": i, "ref_chars": len(R), "strata": strata(i)}
        for name, d in cands.items():
            C = norm(d.get(i, ""))
            cw = collections.Counter(words(C))
            hit = sum((rw & cw).values())
            m = {"cer": lev(R, C) / len(R), "wer": lev(R.split(), C.split()) / max(len(R.split()), 1),
                 "recall": hit / max(sum(rw.values()), 1), "precision": hit / max(sum(cw.values()), 1) if cw else 0.0,
                 "exact": R == C, "exact_ci": R.lower() == C.lower(),
                 "dia_ref": sum(ch in DIACRITICS for ch in R), "dia_ok": 0}
            if m["dia_ref"]:
                rd = collections.Counter(ch for ch in R if ch in DIACRITICS)
                cd = collections.Counter(ch for ch in C if ch in DIACRITICS)
                m["dia_ok"] = sum((rd & cd).values())
            rec[name] = m
            for s in rec["strata"] + ["everything scored"]:
                rows[s][name].append(m)
        per_crop.append(rec)
    with open(OUT / "scores.jsonl", "w") as f:
        for rec in per_crop:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    names = ["accurate", "accurate+lc", "fast", "haiku"]
    print(f"reference: {a.ref}, {len(per_crop)} crops with text\n")
    print("| stratum | n | " + " | ".join(f"{n} CER med / mean · word recall · exact" for n in names) + " |")
    print("|---|---|" + "---|" * len(names))
    for s in sorted(rows, key=lambda s: (s != "all", s)):
        cells = []
        for n in names:
            ms = rows[s][n]
            cells.append(f"{100*statistics.median(m['cer'] for m in ms):.1f}% / {100*statistics.mean(m['cer'] for m in ms):.1f}% · "
                         f"{100*statistics.mean(m['recall'] for m in ms):.0f}% · {sum(m['exact'] for m in ms)}/{len(ms)}")
        print(f"| {s} | {len(rows[s][names[0]])} | " + " | ".join(cells) + " |")
    print("\ndiacritics kept (of those in the reference):",
          {n: f"{sum(m['dia_ok'] for m in rows['everything scored'][n])}/{sum(m['dia_ref'] for m in rows['everything scored'][n])}" for n in names})
    print("pooled CER (sum of edits / sum of chars):",
          {n: f"{100*sum(m['cer']*r['ref_chars'] for m, r in zip(rows['everything scored'][n], per_crop))/sum(r['ref_chars'] for r in per_crop):.1f}%" for n in names})


if __name__ == "__main__":
    main()
