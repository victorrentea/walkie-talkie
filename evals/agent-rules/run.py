#!/usr/bin/env python3
"""Do Claude, Codex and Copilot still act on a dictated prompt once its two
instruction clauses moved into their global instructions? (2026-11-12, `AgentRules`)

    python3 evals/agent-rules/run.py [--reps 3] [--long-reps 2] [--only claude,codex,copilot]

Each case is a dictated sentence wrapped the way `AppDelegate.terminalLine` wraps it:
`short` (the rules are installed, the envelope carries only data) and `long` (the
old envelope, both clauses under the words). Every run is a real headless session of
the harness in an empty folder, reading the global instructions Walkie installed.

**Nothing is bypassed.** Each harness keeps its permission system and is allowed
only what the cases need: `walkie-reply`, `walkie-dict`, and writing a file in its
own empty folder (Codex: its `workspace-write` sandbox), plus reading the shots folder. `WALKIE_EVAL_LOG` makes the
two helpers record the call instead of acting (no pop-up, no dictionary write), and
the score is read off that record.

`copilot-norules` is the negative control: the short envelope to a Copilot started
with `--no-custom-instructions`. It must fail the reply/dict cases, or the eval
proves nothing.
"""
import argparse
import concurrent.futures as cf
import json
import os
import shutil
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS_ROOT = os.environ.get("WALKIE_SHOTS") or os.path.expanduser(
    "~/Library/Caches/ro.victorrentea.wispr-relay/shots")
SHOTS = "2026-11-12-13-09-24"  # a real folder under $WALKIE_SHOTS, one frame in it
# v3 (2026-11-13): a frame with a dragged box, its cut-out `screenshot-1.jpg` reading
# "Claude Code v2.1.322" — copied from `fixture-v3/` into $WALKIE_SHOTS at start.
SHOTS_V3 = "eval-agent-rules-v3"
AREA = "1085,85→1350,130"
AREA_LONG = ("[📸1✂️ = user-selected area between corners (x,y) given in its token, cut out at "
             "📁/screenshot-1.jpg; full screen available at -800px and -original.jpg at 1920x1080px]")

QUESTION = ('[If I asked you a question, also run: walkie-reply "<the answer in ≤2 short sentences>" '
            '[--image <path> when a small picture says it better]. Only to answer me — never to ask me '
            'something, never to report work done.]')
DICT = ('[If you are 100% sure a term I said came out misheard (a name, a tool, a technical word — not a '
        'Romanian ending), also run: walkie-dict add "<right spelling>" --heard "<as transcribed>". '
        'Silently, no need to tell me.]')

# reply: walkie-reply must (True) / must not (False) be run. dict: the right spelling
# walkie-dict must be given, or None for "must not be run". file: a file the task makes.
CASES = [
    dict(id="question-en", words="What is the capital of Australia?", reply=True, dict=None),
    dict(id="question-ro", words="Câte zile are luna februarie într-un an bisect?", reply=True, dict=None),
    dict(id="task", words="Create a file named hello.txt containing the word hi in the current folder.",
         reply=False, dict=None, file="hello.txt"),
    dict(id="statement", words="Just so you know, the demo moved to Thursday. Nothing to do right now.",
         reply=False, dict=None),
    dict(id="misheard", words="Add a line to notes.txt in the current folder saying that I use cloud code, "
                               "Anthropic's coding agent for the terminal, every day.",
         reply=False, dict="claude code", file="notes.txt"),
    # Only the rules say where 📸0 is: the short envelope names the folder and nothing else.
    dict(id="screenshot", words="Which app's name is at the left of the menu bar at the top of my screen?",
         reply=True, dict=None, says="terminal"),
    dict(id="question-compare", words="Which country has the larger population, Romania or Hungary?",
         reply=True, dict=None),
    # v3: an area is its token alone; only the rules say where its cut-out is.
    dict(id="area-inline", words=f"What version number is written in this box [📸1✂️{AREA}]?",
         reply=True, dict=None, says="2.1.322", shots=SHOTS_V3, long_rows=[AREA_LONG]),
    # v3, Wispr: the token could not go in the words, so the footer carries it alone.
    dict(id="area-footer", words="What version number is written in the box I selected on screen?",
         reply=True, dict=None, says="2.1.322", shots=SHOTS_V3, short_rows=[f"[📸1✂️{AREA}]"],
         long_rows=[f"[📸1✂️ = user-selected area between corners (x,y) ({AREA.replace('→', ')→(')}) at "
                    "📁/screenshot-1.jpg; full screen available at -800px and -original.jpg at 1920x1080px]"]),
    dict(id="move", words="Don't change anything, just tell me: this one [📸1✂️960,80→1070,180 moved to "
                          "1500,80→1610,180], should it go up, down, left or right?",
         reply=True, dict=None, says="right", shots=SHOTS_V3,
         long_rows=["[📸1✂️ = user-drawn MOVE: the box between corners (x,y) (960,80)→(1070,180) should move "
                    "to the box (1500,80)→(1610,180); the first box cut out at 📁/screenshot-1.jpg; full screen "
                    "available at -800px and -original.jpg at 1920x1080px]"]),
]


def envelope(case, long):
    shots = case.get("shots", SHOTS)
    if not long:  # rules v2/v3: icons, the folder, and only what the rules cannot say
        lines = ["[dictated 💻 · 🎤]", f"[📁=$WALKIE_SHOTS/{shots}]", *case.get("short_rows", [])]
        return "[📸0 auto]\n" + case["words"] + "\n\n" + "\n".join(lines)
    lines = ["[Transcribed in RO or EN by 💻 Local Whisper Turbo LoRA · 🎤]"]
    if "?" in case["words"]:
        lines.append(QUESTION)
    lines.append(DICT)
    frames = ("[📸n = 📁/screenshot-n-800px.jpg, or -original.jpg at 1920x1080px]" if "short_rows" in case
              or "long_rows" in case else "[📸0 = 📁/screenshot-0-800px.jpg, or -original.jpg at 1920x1080px]")
    lines += [f"[📁=$WALKIE_SHOTS/{shots}]", frames, *case.get("long_rows", [])]
    return "[📸0 auto]\n" + case["words"] + "\n\n" + "\n".join(lines)


def command(harness, prompt):
    if harness == "claude":
        return ["claude", "-p", prompt, "--output-format", "json",
                "--allowedTools", "Bash(walkie-reply:*)", "Bash(walkie-dict:*)", "Write", "Edit", "Read",
                "--add-dir", SHOTS_ROOT,
                "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}']
    if harness == "codex":
        return ["codex", "exec", "--skip-git-repo-check", "--json", "-s", "workspace-write", prompt]
    extra = ["--no-custom-instructions"] if harness == "copilot-norules" else []
    return ["copilot", "-p", prompt, "--no-color", "--allow-tool", "shell(walkie-reply)",
            "shell(walkie-dict)", "write", "--add-dir", SHOTS_ROOT, *extra]


def run(job):
    harness, case, long, rep, out = job
    name = f"{harness}__{case['id']}__{'long' if long else 'short'}__{rep}"
    cwd = os.path.join(out, name)
    shutil.rmtree(cwd, ignore_errors=True)
    os.makedirs(cwd)
    log = os.path.join(cwd, "calls.jsonl")
    env = dict(os.environ, WALKIE_EVAL_LOG=log)
    started = time.time()
    try:
        p = subprocess.run(command(harness, envelope(case, long)), cwd=cwd, env=env, capture_output=True,
                           text=True, timeout=420, stdin=subprocess.DEVNULL)
        stdout, err, code = p.stdout, p.stderr, p.returncode
    except subprocess.TimeoutExpired:
        stdout, err, code = "", "timeout", -1
    open(os.path.join(cwd, "stdout.txt"), "w").write(stdout)
    open(os.path.join(cwd, "stderr.txt"), "w").write(err)
    calls = [json.loads(l) for l in open(log)] if os.path.exists(log) else []
    replies = [c["argv"] for c in calls if c["cmd"] == "walkie-reply"]
    dicts = [c["argv"] for c in calls if c["cmd"] == "walkie-dict"]
    checks = {"reply": bool(replies) == case["reply"]}
    if case["dict"]:
        checks["dict"] = any(case["dict"] in " ".join(a).lower() for a in dicts)
    else:
        checks["dict"] = not dicts
    if case.get("says"):
        checks["says"] = any(case["says"] in " ".join(a).lower() for a in replies)
    if case.get("file"):
        checks["file"] = os.path.exists(os.path.join(cwd, case["file"]))
    cost = None
    if harness == "claude":
        try:
            cost = json.loads(stdout).get("total_cost_usd")
        except Exception:
            pass
    return dict(run=name, harness=harness, case=case["id"], form="long" if long else "short", rep=rep,
                exit=code, seconds=round(time.time() - started), replies=replies, dicts=dicts,
                checks=checks, ok=all(checks.values()), cost_usd=cost)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--long-reps", type=int, default=2)
    ap.add_argument("--only", default="claude,codex,copilot,copilot-norules")
    ap.add_argument("--cases", default="")
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--workers", type=int, default=5)
    args = ap.parse_args()
    args.out = os.path.abspath(args.out)  # WALKIE_EVAL_LOG is read from inside each run's folder
    cases = [c for c in CASES if not args.cases or c["id"] in args.cases.split(",")]
    jobs = []
    for harness in args.only.split(","):
        for case in cases:
            if harness == "copilot-norules":
                jobs.append((harness, case, False, 0, args.out))
                continue
            jobs += [(harness, case, False, r, args.out) for r in range(args.reps)]
            jobs += [(harness, case, True, r, args.out) for r in range(args.long_reps)]
    os.makedirs(args.out, exist_ok=True)
    fixture = os.path.join(SHOTS_ROOT, SHOTS_V3)
    shutil.rmtree(fixture, ignore_errors=True)
    shutil.copytree(os.path.join(HERE, "fixture-v3"), fixture)
    results = []
    with cf.ThreadPoolExecutor(args.workers) as pool:
        for r in pool.map(run, jobs):
            results.append(r)
            print(("✓" if r["ok"] else "✗"), r["run"], f"{r['seconds']}s", r["checks"],
                  r["replies"][:1], r["dicts"][:1], flush=True)
            json.dump(results, open(os.path.join(args.out, "results.json"), "w"), ensure_ascii=False, indent=1)
    print("\n== passed / runs, by harness and form")
    for harness in args.only.split(","):
        for form in ("short", "long"):
            rs = [r for r in results if r["harness"] == harness and r["form"] == form]
            if rs:
                print(f"{harness:16} {form:5} {sum(r['ok'] for r in rs)}/{len(rs)}")
    print(f"\nClaude cost reported: ${sum(r['cost_usd'] or 0 for r in results):.2f}")


if __name__ == "__main__":
    main()
