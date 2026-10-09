#!/usr/bin/env python3
"""**How fast is a ⚡ quick question answered?** (2026-10-09, `QuickAsk`)

Three ways to ask the same general questions, timed to the first word and to the
whole answer:

    evals/quick-ask/bench.py cold [haiku|sonnet|opus]   # a fresh `claude -p` per question
    evals/quick-ask/bench.py warm [model] [--default]   # one already-started process per question, as QuickAsk does
    evals/quick-ask/bench.py app                        # the installed app: POST /test/quick {"wait": true}

`warm` starts each process, lets it settle 5 s, then asks — the start-up is not
on the clock, because QuickAsk pays it while nobody is waiting. `--default`
keeps Claude Code's own system prompt, tools and settings (~104k input tokens)
instead of QuickAsk's lean flags (~700). Every run spends a little of the
subscription; `app` also opens a reply pop-up per question on the screen.
"""
from __future__ import annotations

import json
import os
import statistics
import subprocess
import sys
import time
import urllib.request

QUESTIONS = [
    "Why is the sky blue?",
    "Care e capitala Australiei?",
    "How many bytes are in a kibibyte?",
    "What's the difference between a process and a thread?",
    "Cine a scris Luceafărul?",
    "What does HTTP 418 mean?",
]

LEAN = ["--tools", "", "--strict-mcp-config", "--setting-sources", "",
        "--system-prompt", "Answer briefly: at most 3 short sentences, plain text, in the language of the question."]


def stream_cmd(model: str, lean: bool) -> list[str]:
    cmd = ["claude", "-p", "--model", model, "--effort", "low", "--input-format", "stream-json",
           "--output-format", "stream-json", "--verbose", "--include-partial-messages",
           "--no-session-persistence"]
    return cmd + (LEAN if lean else ["--tools", ""])


def read_answer(lines, t0: float) -> tuple[float | None, float, str]:
    first, text = None, ""
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("type") == "stream_event":
            ev = e.get("event", {})
            if ev.get("type") == "content_block_delta" and ev.get("delta", {}).get("type") == "text_delta":
                first = first or time.time() - t0
                text += ev["delta"]["text"]
        if e.get("type") == "result":
            return first, time.time() - t0, e.get("result") or text
    return first, time.time() - t0, text


def cold(model: str):
    for q in QUESTIONS:
        t0 = time.time()
        p = subprocess.Popen(["claude", "-p", q, "--model", model, "--effort", "low", "--output-format",
                              "stream-json", "--verbose", "--include-partial-messages",
                              "--no-session-persistence"] + LEAN,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, text=True)
        first, _, answer = read_answer(p.stdout, t0)
        p.wait()
        yield q, first, time.time() - t0, answer   # the CLI's exit is on the clock: it is, for a cold ask


def warm(model: str, lean: bool):
    for q in QUESTIONS:
        p = subprocess.Popen(stream_cmd(model, lean), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, bufsize=1)
        time.sleep(5)
        t0 = time.time()
        p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": q}}) + "\n")
        p.stdin.flush()
        first, total, answer = read_answer(p.stdout, t0)
        p.stdin.close()
        p.terminate()
        yield q, first, total, answer


def app():
    port = os.environ.get("WT_PORT", "8917")
    for q in QUESTIONS:
        req = urllib.request.Request(f"http://127.0.0.1:{port}/test/quick",
                                     data=json.dumps({"text": q, "wait": True}).encode(), method="POST")
        r = json.load(urllib.request.urlopen(req, timeout=60))
        first = r["firstWordMs"] / 1000 if r.get("firstWordMs") is not None else None
        yield q, first, r["totalMs"] / 1000, r.get("answer") or f"⚠️ {r.get('error')}"
        time.sleep(4)   # the next process is started after an answer; give it the time a person would


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("cold", "warm", "app"):
        print(__doc__)
        return 2
    mode = argv[0]
    model = next((a for a in argv[1:] if not a.startswith("--")), "haiku")
    runs = {"cold": lambda: cold(model), "warm": lambda: warm(model, "--default" not in argv), "app": app}[mode]()
    firsts, totals = [], []
    for q, first, total, answer in runs:
        print(f"{'–' if first is None else f'{first:5.2f}'} s first · {total:5.2f} s whole · {q[:40]:40} → {answer[:70]!r}",
              flush=True)
        if first is not None:
            firsts.append(first)
        totals.append(total)
    if firsts:
        print(f"\n{mode} {model if mode != 'app' else ''}: first word median {statistics.median(firsts):.2f} s "
              f"(max {max(firsts):.2f}) · whole median {statistics.median(totals):.2f} s (max {max(totals):.2f})")
    return 0 if len(firsts) == len(QUESTIONS) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
