"""Run every variant of every fixture through a real agent, N times, and score it.

`claude -p` and not the API on purpose. What is being measured is not whether a
model *can* read seven screenshots — it plainly can — but what an agent handed
this line **chooses** to do: how many of the pictures it opens, whether it opens
the one it was told it probably does not need, and what that costs. Only the
real harness makes that decision; an API call with the images pre-attached has
already made it for us.

Usage is reported per run. `fresh` — input + cache_creation — is the number to
compare across variants: cache_read is the system prompt, identical everywhere,
and including it would drown the signal in a constant.

    python3 evals/run.py                        # everything, 3 repeats
    python3 evals/run.py --repeats 1 --fixture unsubscribe
    python3 evals/run.py --variant small,current
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fixtures import FIXTURES          # noqa: E402
from variants import VARIANTS, estimate_tokens   # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
RESULTS = os.path.join(HERE, "results.jsonl")


def one_run(line, question, cwd):
    """One `claude -p`, returning the answer and what it cost.

    `--allowedTools Read` and nothing else: the fixtures are old screenshots on
    a disk, there is nothing here to edit, and a run that wandered off into the
    repo would be measuring the wrong thing.
    """
    prompt = line + "\n\n" + question
    started = time.time()
    proc = subprocess.run(
        ["claude", "-p", "--output-format", "json", "--allowedTools", "Read"],
        input=prompt, capture_output=True, text=True, cwd=cwd, timeout=600)
    elapsed = time.time() - started
    if proc.returncode != 0:
        return {"error": proc.stderr[-500:], "elapsed": elapsed}
    try:
        d = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"error": "unparseable: " + proc.stdout[-500:], "elapsed": elapsed}
    u = d.get("usage", {})
    return {
        "answer": d.get("result", ""),
        "fresh": u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0),
        "cache_read": u.get("cache_read_input_tokens", 0),
        "output": u.get("output_tokens", 0),
        "cost": d.get("total_cost_usd", 0.0),
        "turns": d.get("num_turns", 0),
        "elapsed": elapsed,
    }


def score(answer, truth):
    """Ordered, positional, and deliberately forgiving about spelling.

    What is being tested is whether picture *k* was matched to thing *k*, so an
    answer that names every sender correctly but in the wrong order has failed
    the only thing this measures. `SHEIN` vs `Shein` has not failed anything.
    """
    arr = _parse_array(answer)
    if arr is None:
        return 0.0, None
    hits = 0
    for i, want in enumerate(truth):
        if i < len(arr) and want.lower() in str(arr[i]).lower().replace("&amp;", "&"):
            hits += 1
    return hits / len(truth), arr


def _parse_array(answer):
    m = re.search(r"\[.*\]", answer or "", re.S)
    if not m:
        return None
    try:
        v = json.loads(m.group(0))
        return v if isinstance(v, list) else None
    except json.JSONDecodeError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--fixture", default=",".join(FIXTURES))
    ap.add_argument("--variant", default=",".join(VARIANTS))
    args = ap.parse_args()

    fixtures = [f.strip() for f in args.fixture.split(",")]
    variants = [v.strip() for v in args.variant.split(",")]
    os.makedirs(WORK, exist_ok=True)

    with open(RESULTS, "a") as log:
        for fname in fixtures:
            fx = FIXTURES[fname]
            missing = [p for p in [fx["context"]] + fx["shots"] if not os.path.exists(p)]
            if missing:
                print("skipping %s — %d source frame(s) gone from disk" % (fname, len(missing)))
                continue
            wd = os.path.join(WORK, fname)
            for vname in variants:
                line, files = VARIANTS[vname](fx, wd)
                offered = sum(estimate_tokens(p) for p in files)
                for r in range(args.repeats):
                    res = one_run(line, fx["question"], cwd=wd)
                    if "error" in res:
                        print("  %-16s %-16s run%d  ERROR %s" % (fname, vname, r, res["error"][:80]))
                        continue
                    acc, arr = score(res["answer"], fx["truth"])
                    row = dict(fixture=fname, variant=vname, run=r, accuracy=acc,
                               offered_tokens=offered, parsed=arr, line_chars=len(line), **res)
                    log.write(json.dumps(row) + "\n")
                    log.flush()
                    print("  %-12s %-16s run%d  acc %.2f  fresh %6d  out %4d  %5.1fs  $%.3f"
                          % (fname, vname, r, acc, res["fresh"], res["output"],
                             res["elapsed"], res["cost"]))


if __name__ == "__main__":
    main()
