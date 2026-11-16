#!/usr/bin/env python3
"""The helper itself on recorded wakes, detectors alone vs `--confirm base` (2026-11-16).

    ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/replay_confirm.py

Each clip goes through `helpers/wake_word.py --wav` twice, with the app's own
arguments; counted: `wake` events (and `rejected` ones). Sets: every live trigger kept
in `santa/triggers/` (said or false by the large model's label beside it), his 30
takes of *Hey Santa*, 20 `say` takes of *hey gepetto*.
"""
import glob
import json
import os
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~/.walkie-talkie/wake")
HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "helpers", "wake_word.py")
SAID = re.compile(r"santa|gep+et+o|claude", re.I)
BASE = [sys.executable, "-I", HELPER, "--triggers", "", "--hold", "/nonexistent",
        "--model", HOME + "/hey_claude.onnx", "--threshold", "0.5",
        "--whisper-wake", HOME + "/hey_santa_whisper.npz", "--whisper-threshold", "0.6",
        "--also", f"hey gepetto={HOME}/hey_gepetto_whisper.npz@0.9"]


def run(wav, confirm):
    out = subprocess.run(BASE + ["--wav", wav] + (["--confirm", "base"] if confirm else []),
                         capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout
    ev = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
    return ([e for e in ev if e["event"] == "wake"], [e for e in ev if e["event"] == "rejected"],
            [e for e in ev if e["event"] == "error"])


def main():
    clips = []
    for f in sorted(glob.glob(HOME + "/santa/triggers/*.wav")):
        txt = open(f[:-4] + ".txt").read() if os.path.exists(f[:-4] + ".txt") else ""
        clips.append(("trigger, said" if SAID.search(txt) else "trigger, false", f))
    clips += [("his takes", f) for f in sorted(glob.glob(HOME + "/santa/real/*.wav"))]
    random.seed(1)
    clips += [("say gepetto", f) for f in random.sample(sorted(glob.glob(HOME + "/gepetto/pos/*.wav")), 20)]
    with ThreadPoolExecutor(4) as ex:
        res = list(ex.map(lambda c: (c, run(c[1], False), run(c[1], True)), clips))
    tally = {}
    for (name, f), off, on in res:
        t = tally.setdefault(name, [0, 0, 0])
        t[0] += 1
        t[1] += bool(off[0])
        t[2] += bool(on[0])
        if on[2] or off[2]:
            print("  error:", os.path.basename(f), (on[2] or off[2])[0].get("error"))
        if bool(off[0]) != bool(on[0]) or "-v" in sys.argv:
            heard = (on[1] or on[0] or [{}])[0].get("heard")
            print(f"  {name:15s} {os.path.basename(f)[:34]:34s} alone {len(off[0])} → confirmed {len(on[0])}  heard: {heard!r}")
    print()
    for name, (n, off, on) in sorted(tally.items()):
        print(f"{name:15s} {n:3d} clips   wakes, detectors alone {off:3d}   with --confirm {on:3d}")


if __name__ == "__main__":
    main()
