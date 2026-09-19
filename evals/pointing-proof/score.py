#!/usr/bin/env python3
"""Score the answers on three questions, because they fail separately.

1. **the right sentence** — the quote, normalised, *is* the sentence the box was
   drawn around. This is the question Victor asked.
2. **the right place** — the quote overlaps the target by at least six words in a
   row. An answer can quote the neighbouring sentence, or the target plus its
   neighbour, and still have found the box; an answer that lands in another
   paragraph has not.
3. **verbatim** — `difflib`'s ratio between the quote and the target. A reader
   that located the region and then paraphrased what it saw is a different
   failure from one that looked in the wrong place, and only this column
   separates them.
"""
import difflib, json, pathlib, re, sys
from collections import defaultdict

HERE = pathlib.Path(__file__).parent


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", re.sub(r"\s+", " ", (s or "").lower())).strip()


def overlaps(quote, target, run=6):
    q, t = norm(quote).split(), norm(target).split()
    return any(" ".join(t[i:i + run]) in " ".join(q) for i in range(max(0, len(t) - run + 1)))


def paragraphs():
    """The four paragraphs of `page.html`, normalised — so a miss can say
    whether it stayed in the block the box was drawn on or left it."""
    html = (HERE / "page.html").read_text()
    return {m.group(1): norm(re.sub(r"<[^>]+>", " ", m.group(2)))
            for m in re.finditer(r'<p id="(p\d)">(.*?)</p>', html, re.S)}


def where(quote, paras):
    n = norm(quote)
    if not n:
        return "—"
    hits = [p for p, text in paras.items() if n[:60] in text]
    return hits[0] if len(hits) == 1 else "?"


def main(path):
    data = json.load(open(path))
    t_of = {s: json.loads((HERE / "out" / s / "truth.json").read_text()) for s in "1234"}
    truth = {s: t_of[s]["sentence"] for s in t_of}
    paras = paragraphs()
    by = defaultdict(lambda: {"n": 0, "sentence": 0, "place": 0, "ratio": []})
    misses = []
    for r in data["answers"]:
        t = truth[r["scene"]]
        c = by[r["condition"]]
        c["n"] += 1
        exact = norm(r.get("quote")) == norm(t)
        near = overlaps(r.get("quote"), t)
        c["sentence"] += exact
        c["place"] += near
        c["ratio"].append(difflib.SequenceMatcher(None, norm(r.get("quote")), norm(t)).ratio())
        if not exact:
            block = where(r.get("quote"), paras)
            right = t_of[r["scene"]]["paragraph"]
            misses.append((r["run"], r["scene"], r["condition"],
                           "overlaps it" if near else
                           (f"other sentence, same {block}" if block == right
                            else f"ANOTHER BLOCK ({block}, not {right})"),
                           (r.get("quote") or r.get("error", "—"))[:60]))

    print(f"{'condition':10}{'runs':>6}{'right sentence':>17}{'right place':>14}{'verbatim':>11}")
    for cond in ("small", "sized", "full", "both", "crop"):
        c = by[cond]
        if not c["n"]:
            continue
        print(f"{cond:10}{c['n']:6}{c['sentence']:>10}/{c['n']:<6}"
              f"{c['place']:>8}/{c['n']:<5}{sum(c['ratio'])/len(c['ratio']):>11.2f}")
    tot = {k: sum(by[c][k] for c in by) for k in ("n", "sentence", "place")}
    print(f"{'TOTAL':10}{tot['n']:6}{tot['sentence']:>10}/{tot['n']:<6}{tot['place']:>8}/{tot['n']:<5}")
    if misses:
        print("\nnot the sentence:")
        for m in misses:
            print("  " + " ".join(f"{x:<32}" if i == 3 else f"{x:<8}" for i, x in enumerate(m[:4])) + m[4])


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else HERE / "results.json")
