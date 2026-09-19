#!/usr/bin/env python3
"""Lay out one folder per eval run, with neutral filenames.

Neutral because the answer must come out of the pixels: a path with the scene
number or the word in it is a way to be right without having read anything.
"""
import json, pathlib, shutil, itertools

TRUTH = {"1": "backing", "2": "variance", "3": "subprocess", "4": "encode"}
CONDITIONS = {
    "page": ["21-app-shot-handover.jpg"],          # the whole screen, as handed over
    "crop": ["41-crop.jpg"],                        # only the wheel-drag region
    "both": ["21-app-shot-handover.jpg", "41-crop.jpg"],
}
NAMES = {"21-app-shot-handover.jpg": "screen.jpg", "41-crop.jpg": "region.jpg"}
REPEATS = 2

root = pathlib.Path("eval"); shutil.rmtree(root, ignore_errors=True); root.mkdir()
runs = []
for i, (scene, cond, rep) in enumerate(
        itertools.product(sorted(TRUTH), CONDITIONS, range(1, REPEATS + 1)), start=1):
    d = root / f"run-{i:02d}"; d.mkdir()
    for f in CONDITIONS[cond]:
        shutil.copy(f"out/{scene}/{f}", d / NAMES[f])
    runs.append({"run": f"run-{i:02d}", "scene": scene, "condition": cond,
                 "repeat": rep, "truth": TRUTH[scene], "dir": str(d.resolve()),
                 "files": [NAMES[f] for f in CONDITIONS[cond]]})
json.dump(runs, open(root / "manifest.json", "w"), indent=1)
print(f"{len(runs)} runs")
for r in runs[:6]:
    print(" ", r["run"], r["condition"], r["files"])
