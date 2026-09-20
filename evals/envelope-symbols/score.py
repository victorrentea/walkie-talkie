#!/usr/bin/env python3
"""Grade the answers question by question, and say what each envelope costs.

Two of the eleven questions are deliberately unanswerable from today's envelope
— it has no token for the *start* of a screen recording and none for the
automatic frame — so `current` is expected to lose those; what matters is
whether the new tokens are read correctly, and whether shrinking the footer
costs any of it.
"""
import json, pathlib, re, sys
from collections import defaultdict

import envelopes

HERE = pathlib.Path(__file__).parent
# The paragraph the framed region falls in, so `region_says` can be checked
# against what is really in those pixels rather than against one phrasing.
REGION_TEXT = ("the capture path spends its budget in three places the window server round "
               "trip the encoder and the file write a subprocess per frame costs two hundred "
               "milliseconds on this machine which is already over the budget a five frame "
               "per second recording has so the recorder reaches for the in process call "
               "instead and keeps the subprocess for stills")


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def nums(s):
    return [int(n) for n in re.findall(r"\d+", str(s))]


def grade(q, got, variant):
    if got is None:
        return False
    if q == "screenshots":
        # Three whole screens plus the framed one — the scene grew a third plain
        # frame on 2026-09-20 so the repeated legend rows would be visible.
        return nums(got) == [4]
    if q == "automatic":
        return nums(got) == [0] or norm(got) in ("screenshot 0", "0")
    if q == "mouse1":
        return nums(got) == list(envelopes.MOUSE[1])
    if q == "mouse2":
        return nums(got) == list(envelopes.MOUSE[2])
    if q == "s2_full":
        # **The question the collapsed row is betting on**: with one `[📸n = …]`
        # line instead of three, naming 📸2's full-resolution file means
        # instantiating `n` and applying the `-original` rule, neither of which
        # is written out anywhere for that particular frame.
        name = str(got).split("/")[-1]
        want = ("screenshot-2-original.jpg" if variant != "current"
                else "shot#02(mouse-at-640x430px).jpg")
        return name == want
    if q == "corners":
        return nums(got) == list(envelopes.AREA)
    if q == "region_file":
        want = "screenshot-3.jpg" if variant != "current" else "-zoom.jpg"
        name = str(got).split("/")[-1]
        return want in name and "800px" not in name and "original" not in name
    if q == "region_says":
        words = norm(got).split()
        return len(words) >= 4 and " ".join(words[:5]) in REGION_TEXT
    if q == "film_seconds":
        return nums(got)[:1] == [envelopes.FILM_SECONDS]
    if q == "sel_app":
        return norm(envelopes.SELECTED_APP) in norm(got)
    if q == "element_page":
        return envelopes.ELEMENT_URL in str(got)
    if q == "after_s1":
        return norm(got).startswith("linia asta e problema")
    if q == "original_res":
        return nums(got)[:2] == [3456, 2234]
    return False


QUESTIONS = ["screenshots", "automatic", "mouse1", "mouse2", "s2_full",
             "corners", "region_file", "region_says", "film_seconds",
             "sel_app", "element_page", "after_s1", "original_res"]


def main(path):
    rows = json.load(open(path))["answers"]
    by = defaultdict(lambda: defaultdict(list))
    cost = defaultdict(list)
    for r in rows:
        key = (r["variant"], r["model"])
        cost[key].append(r.get("cost") or 0)
        for q in QUESTIONS:
            by[key][q].append(grade(q, r.get(q), r["variant"]))

    print(f"{'envelope':9} {'model':7} {'chars':>6} " +
          " ".join(f"{q[:6]:>7}" for q in QUESTIONS) + f"{'TOTAL':>9}{'$/run':>7}")
    for variant in ("current", "victor", "shrunk", "onerow", "onerow_auto"):
        text, _ = envelopes.VARIANTS[variant]()
        for model in ("sonnet", "opus"):
            key = (variant, model)
            if not by[key]:
                continue
            cells = [by[key][q] for q in QUESTIONS]
            ok = sum(sum(c) for c in cells)
            n = sum(len(c) for c in cells)
            print(f"{variant:9} {model:7} {len(text):6} " +
                  " ".join(f"{sum(c):>4}/{len(c):<2}" for c in cells) +
                  f"{ok:>6}/{n:<3}{sum(cost[key])/len(cost[key]):>7.2f}")

    print("\nwhat they said was unclear:")
    for r in rows:
        if r.get("unclear") and str(r["unclear"]).strip() not in ("", "none", "None"):
            print(f"  [{r['variant']}/{r['model']}] {str(r['unclear'])[:160]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else HERE / "results.json")
