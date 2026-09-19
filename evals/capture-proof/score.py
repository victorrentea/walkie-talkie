#!/usr/bin/env python3
"""Score the eval on two questions, not one.

*Which word* is the question Victor asked. *Which one of them* is the question
a repeated word asks back: three of the four scenes highlight the **second**
occurrence of a word that appears twice in the same paragraph, so an answer can
name the right word and still be pointing at the wrong place on the page. An
answer counts as *pinned* when the context it quotes contains the highlighted
occurrence and not the other one.
"""
import json
from collections import defaultdict

TRUTH = {"1": ("backing", None), "2": ("variance", "displays"),
         "3": ("subprocess", "stills"), "4": ("encode", "cheap")}

rows = json.load(open("results.json"))["answers"]
by = defaultdict(lambda: {"n": 0, "word": 0, "pinned": 0, "pinnable": 0})
for r in rows:
    word, tell = TRUTH[r["scene"]]
    c = by[r["condition"]]
    c["n"] += 1
    ok = r["word"].strip().lower() == word
    c["word"] += ok
    if tell:
        c["pinnable"] += 1
        ctx = r["context"].lower()
        # pinned = the quoted context carries the highlighted occurrence and
        # does not also carry the other one
        others = {"2": "between runs", "3": "per frame", "4": "its encode time"}
        c["pinned"] += (tell in ctx) and (others[r["scene"]] not in ctx)

print(f"{'condition':10} {'runs':>5} {'right word':>12} {'occurrence pinned':>20}")
for cond in ("page", "crop", "both"):
    c = by[cond]
    print(f"{cond:10} {c['n']:5} {c['word']:>6}/{c['n']:<5} "
          f"{c['pinned']:>12}/{c['pinnable']:<6}")
tot = {k: sum(by[c][k] for c in by) for k in ("n", "word", "pinned", "pinnable")}
print(f"{'TOTAL':10} {tot['n']:5} {tot['word']:>6}/{tot['n']:<5} {tot['pinned']:>12}/{tot['pinnable']:<6}")
