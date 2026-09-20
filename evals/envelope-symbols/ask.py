#!/usr/bin/env python3
"""Hand one envelope to a fresh agent and ask it what the markings mean.

Nothing in the prompt explains a symbol: the envelope is pasted exactly as the
relay would write it into a session, the questions are what an agent would have
to work out for itself, and the artifacts are on disk under the names that
envelope uses, so *which file would you open* is a question with a right answer.

Every run is its own `claude -p` in its own directory, so no run sees another's
answer or this repo's CLAUDE.md.
"""
import argparse, json, pathlib, re, shutil, subprocess, tempfile
from concurrent.futures import ThreadPoolExecutor

import envelopes

HERE = pathlib.Path(__file__).parent
SHOTS = HERE / "shots" / "2026-09-19-17-32-15"

QUESTIONS = """
Answer these about the message above, as one JSON object and nothing else. Open
files only if you need them. Do not explain outside the JSON — reply with the
object even if a picture is not what you expected; say so in "unclear" instead.

{
 "screenshots": <how many still screenshots are attached, as a number>,
 "automatic": "<which of them, if any, was taken automatically when I started \
talking rather than by a deliberate press — answer with its number, or 'none'>",
 "mouse1": "<where my mouse pointer was when screenshot 1 was taken, as x,y>",
 "s2_full": "<the file name you would open to see screenshot 2 at full \
resolution>",
 "mouse2": "<where my mouse pointer was when screenshot 2 was taken, as x,y>",
 "corners": "<the corners of the region I framed with a drag, as x1,y1,x2,y2>",
 "region_file": "<the file name that shows ONLY that framed region, nothing else>",
 "region_says": "<the first six words of the text inside that framed region>",
 "film_seconds": "<how many seconds the screen recording lasted, as a number>",
 "sel_app": "<the application the text I had highlighted came from>",
 "element_page": "<the page URL the element I picked in Chrome is on>",
 "after_s1": "<the words of mine immediately after screenshot 1 was taken>",
 "original_res": "<the pixel size of the full-resolution frames>",
 "unclear": "<anything in the message you had to guess at, in one line>"
}
"""


def stage(variant, folder):
    _, names = envelopes.VARIANTS[variant]()
    for key, name in names.items():
        src = SHOTS / envelopes.CANONICAL[key]
        dst = folder / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        if not dst.exists():
            shutil.copy(src, dst)


def one(variant, model, run):
    folder = pathlib.Path(tempfile.mkdtemp(prefix=f"wt-sym-{variant}-{model}-"))
    stage(variant, folder)
    text, _ = envelopes.VARIANTS[variant]()
    prompt = text.replace(envelopes.FOLDER, str(folder)) + "\n\n---\n" + QUESTIONS
    p = subprocess.run(["claude", "-p", prompt, "--model", model,
                        "--allowedTools", "Read,Bash(ls:*)", "--output-format", "json"],
                       cwd=folder, capture_output=True, text=True, timeout=900)
    answer = {"run": run, "variant": variant, "model": model}
    try:
        result = json.loads(p.stdout)
        answer["cost"] = result.get("total_cost_usd")
        answer["turns"] = result.get("num_turns")
        m = re.search(r"\{.*\}", result["result"], re.S)
        answer.update(json.loads(m.group(0)))
    except Exception as e:
        answer["error"] = f"{type(e).__name__}: {e}"
        answer["raw"] = p.stdout[-1500:]
    print(f"{run} {variant}/{model}: "
          f"{answer.get('region_file', answer.get('error', '?'))}", flush=True)
    shutil.rmtree(folder, ignore_errors=True)
    return answer


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", default="victor,onerow,onerow_auto")
    ap.add_argument("--models", default="sonnet,opus")
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--out", default=str(HERE / "results.json"))
    a = ap.parse_args()

    jobs, n = [], 0
    for variant in a.variants.split(","):
        for model in a.models.split(","):
            for _ in range(a.repeats):
                n += 1
                jobs.append((variant, model, f"run-{n:02d}"))
    with ThreadPoolExecutor(max_workers=a.jobs) as pool:
        answers = list(pool.map(lambda j: one(*j), jobs))
    answers.sort(key=lambda r: r["run"])
    pathlib.Path(a.out).write_text(json.dumps({"answers": answers}, indent=1,
                                              ensure_ascii=False))
    print(f"\n{len(answers)} answers -> {a.out}")
