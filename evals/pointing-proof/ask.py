#!/usr/bin/env python3
"""Hand one scene, in one condition, to a fresh agent — and ask it the only
question that matters: *which text am I pointing at?*

The envelope is `AppDelegate.terminalLine`'s, reproduced clause for clause
(`shotsClause`, `dictatedHint`), with two deliberate differences: the folder is a
real temporary directory rather than `$WALKIE_SHOTS` (the eval's agent has no
`.zshrc` exporting it), and a last paragraph asks for the answer as JSON. The
words are a dictation that **cannot** be carried out without knowing which
sentence is meant — *rewrite this sentence* names no sentence.

Each run is its own `claude -p` process in its own empty directory, so no run
sees another's answer, this repo's CLAUDE.md, or any of the other scenes.
"""
import argparse, json, pathlib, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).parent
OUT = HERE / "out"
WINDOW = "Google Chrome — Notes on latency budgets"
HINT = "[this text dictated and transcribed in RO or EN by Wispr Flow]"
WORDS = "Rewrite this sentence to be shorter and plainer, keep the meaning."

# `ScreenCapture.handoverWidth` and the two sentences `shotsClause` appends.
NOTE = ("Each is ≤800px wide; drop the -small for the full-resolution original.")
AREA_NOTE = (" A name with `area-x1xy1-to-x2xy2px` in it is a whole screen with a "
             "rectangle I dragged on it, in that picture's own pixels, top-left "
             "origin — I am pointing at that region, not cropping to it.")
# The candidate fix, measured as its own condition: the rectangle is in the
# **full-resolution** frame's pixels and the file handed over is the 800 px copy
# of it, which `AREA_NOTE` does not say — "that picture's own pixels" reads as
# the picture the reader is holding, and it is not.
SIZED_NOTE = (" A name with `area-x1xy1-to-x2xy2px` in it is a whole screen with a "
              "rectangle I dragged on it, top-left origin — I am pointing at that "
              "region, not cropping to it. Those numbers are in the pixels of the "
              "full-resolution frame, {w}x{h}; the -small copy is that same frame "
              "scaled to {sw}x{sh}, so scale the rectangle by {f:.3f} to find it there.")
# The pre-2026-09-14 sentence, for the condition that reproduces that behaviour.
CROP_NOTE = (" Anything named `area-` is a region I dragged a box around, not the "
             "whole screen — its edges are mine, not the display's.")

ASK = """
Before you rewrite anything: which sentence am I pointing at?

Reply with one JSON object and nothing else:
{"quote": "<the sentence, copied verbatim from the screen>",
 "how": "<one short line: how you located it>",
 "confidence": "high|medium|low"}
"""


def envelope(truth, condition, folder):
    if condition == "crop":
        name = f"area-1-00:04({truth['crop_px'][0]}x{truth['crop_px'][1]}px)-small.jpg"
        note = NOTE + CROP_NOTE
    elif condition == "both":
        # The candidate that keeps the pointing gesture *and* the pixels: the
        # display as it is, plus the framed region as a second 800 px file.
        name = (f"{truth['stem']}-small.jpg in '{WINDOW}'\n"
                f"- {truth['stem']}-zoom-small.jpg")
        note = NOTE + AREA_NOTE + (" The `-zoom` file is that same rectangle on "
                                   "its own, at 800px — the region's pixels, "
                                   "where the screen frame has the region's place.")
    elif condition == "sized":
        name = f"{truth['stem']}-small.jpg"
        w, h = truth["screen_px"]
        sw, sh = truth["small_px"]
        note = NOTE + SIZED_NOTE.format(w=w, h=h, sw=sw, sh=sh, f=sw / w)
    else:
        name = f"{truth['stem']}-small.jpg"
        note = NOTE + AREA_NOTE
    return (f"{WORDS}\n{HINT}\n[Focused window: {WINDOW}]\n"
            f"[screenshots are in {folder}/ open only if the words need it:\n"
            f"- {name} in '{WINDOW}'\n{note}]\n{ASK}")


def stage(scene, condition, folder):
    """Put on disk exactly the files that condition's agent could open."""
    d = OUT / scene
    truth = json.loads((d / "truth.json").read_text())
    if condition == "crop":
        src = d / f"{truth['crop_stem']}-small.jpg"
        shutil.copy(src, folder / f"area-1-00:04({truth['crop_px'][0]}x{truth['crop_px'][1]}px)-small.jpg")
    else:
        shutil.copy(d / f"{truth['stem']}-small.jpg", folder / f"{truth['stem']}-small.jpg")
        # `full` is the condition where the clause's "drop the -small" is true.
        if condition == "full":
            shutil.copy(d / f"{truth['stem']}.jpg", folder / f"{truth['stem']}.jpg")
        if condition == "both":
            shutil.copy(d / f"{truth['crop_stem']}-small.jpg",
                        folder / f"{truth['stem']}-zoom-small.jpg")
    return truth


def one(scene, condition, run, model="sonnet"):
    folder = pathlib.Path(tempfile.mkdtemp(prefix=f"wt-point-{scene}-{condition}-"))
    truth = stage(scene, condition, folder)
    prompt = envelope(truth, condition, folder)
    p = subprocess.run(["claude", "-p", prompt, "--model", model,
                        "--allowedTools", "Read", "--output-format", "json"],
                       cwd=folder, capture_output=True, text=True, timeout=600)
    answer = {"run": run, "scene": scene, "condition": condition, "raw": p.stdout[-4000:]}
    try:
        text = json.loads(p.stdout)["result"]
        m = re.search(r"\{.*\}", text, re.S)
        answer.update(json.loads(m.group(0)))
        answer.pop("raw", None)
    except Exception as e:
        answer["error"] = f"{type(e).__name__}: {e}"
    print(f"{run} {scene}/{condition}: "
          f"{answer.get('quote', answer.get('error', '?'))[:90]}", flush=True)
    shutil.rmtree(folder, ignore_errors=True)
    return answer


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenes", default="1,2,3,4")
    ap.add_argument("--conditions", default="small,full,crop")
    ap.add_argument("--repeats", type=int, default=2)
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--out", default=str(HERE / "results.json"))
    a = ap.parse_args()

    jobs, n = [], 0
    for scene in a.scenes.split(","):
        for condition in a.conditions.split(","):
            for _ in range(a.repeats):
                n += 1
                jobs.append((scene, condition, f"run-{n:02d}", a.model))
    with ThreadPoolExecutor(max_workers=a.jobs) as pool:
        answers = list(pool.map(lambda j: one(*j), jobs))
    answers.sort(key=lambda r: r["run"])
    pathlib.Path(a.out).write_text(json.dumps({"model": a.model, "answers": answers}, indent=1))
    print(f"\n{len(answers)} answers -> {a.out}")
