#!/usr/bin/env python3
"""Which repos has Victor actually been working in — read off Claude Code's own transcripts.

**Why this exists.** `SpawnFolderMenu` names the folders a ⌘-wheel spawn can open
in, and until now that list was six names hardcoded in Swift: the projects he
happened to be working on the day it was written. A list like that is wrong the
week after, and it is wrong silently — a project missing from it costs the first
sentence of every session started in it, spoken out loud to tell the agent where
it is.

The answer he asked for: *"analizând conversațiile pe care le-am avut cu
Claude-ul … să determin care sunt proiectele în care am lucrat"*. Claude Code
already writes down every message it has ever exchanged, tagged with the working
directory it happened in — so where he has been working is a fact on this disk,
not something to guess at or maintain by hand.

**The measure is token burn, not visits.** *"m-ar interesa să-mi faci un top 5 …
în care am lucrat și am promptat mult, sau am ars mult stoc"*. Every assistant
record carries its own `usage`, so the sum over a window is exactly that. The
weights below approximate what the tokens cost, but the choice barely matters:
measured over his real 14-day window, ranking by weighted cost, by raw output
tokens and by number of prompts produced the **same top five**, with only 4th and
5th swapping. So this is not a metric that needs defending — any of the three
would have named the same projects.

**And it is cheap, which is the other half of the ask** (*"nu vreau să mănânci
token ca să evaluezi unde s-au petrecut mulți token … dar nici să execuți asta
la fiecare click"*). Nothing here calls a model; it reads files. The whole
14-day window is ~1 GB across ~800 transcripts and scans in **under four
seconds**, because a line is only handed to the JSON parser once a raw byte scan
has found `"assistant"` in it — which is a small minority of them. That is well
inside what a once-a-day background run can spend, so there is no cache to keep
correct and no incremental-read offset to get wrong.

Writes `~/.walkie-talkie/recent-projects.json`. Run it by hand any time:

    ./helpers/recent_projects.py            # rewrite the file
    ./helpers/recent_projects.py --print    # …and show the table
"""

import argparse
import json
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
WORKSPACE = os.path.join(HOME, "workspace")
TRANSCRIPTS = os.path.join(HOME, ".claude", "projects")

# **What a token is worth, roughly.** Output is the expensive one, a cache read
# is nearly free, and a cache write sits between an input token and an output
# one. These are proportions rather than prices: the file is a ranking, and
# nothing downstream reads the absolute number.
WEIGHTS = {"output": 5.0, "cache_creation": 1.25, "input": 1.0, "cache_read": 0.1}


def bucket(cwd):
    """The *project* a working directory belongs to, or None.

    **Everything under `~/workspace/<x>/` is `<x>`**, however deep, and that
    rollup is the whole of the interesting logic. Sessions run in
    `petclinic/petclinic-backend/.codecity-tool` and in
    `agentic-how/.claude-worktrees/<something>`; both are Victor working on the
    project at the top, and left alone they came out as separate entries — one
    of them ranked seventh, splitting the work of the project that ranked first.
    Rolling up is also what makes worktrees and nested tool checkouts free
    rather than a case to handle.

    Outside `~/workspace` there is nothing to roll up to, so the git root stands
    on its own. Outside `$HOME` there is nothing at all: those are scratchpads
    under `/private/tmp`, which is a session's own litter and not a project.
    """
    if not cwd.startswith(HOME + os.sep):
        return None
    if cwd.startswith(WORKSPACE + os.sep):
        top = cwd[len(WORKSPACE) + 1:].split(os.sep)[0]
        # A dot-directory directly under the workspace is not a project.
        if not top or top.startswith("."):
            return None
        path = os.path.join(WORKSPACE, top)
    else:
        path = git_root(cwd)
        if not path:
            return None
    # Git repositories only — his words. `.git` is a directory in a checkout and
    # a *file* in a worktree, so this deliberately tests neither.
    return path if os.path.exists(os.path.join(path, ".git")) else None


_roots = {}


def git_root(cwd):
    """The repository `cwd` sits in, found without shelling out to git.

    Walking up looking for `.git` is what `git rev-parse --show-toplevel` does,
    and doing it here keeps this a pure-stdlib script with no subprocess per
    distinct directory — there are hundreds of those in a fortnight.
    """
    if cwd in _roots:
        return _roots[cwd]
    d = cwd
    found = None
    while d.startswith(HOME) and d != HOME:
        if os.path.exists(os.path.join(d, ".git")):
            found = d
            break
        d = os.path.dirname(d)
    _roots[cwd] = found
    return found


def scan(days):
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    # The mtime filter is the cheap half of the window: a transcript last
    # touched three weeks ago cannot hold a record from the last two, so it is
    # never opened. A day of slack, because mtime is when the file was last
    # *appended to*, not when the records in it were written.
    stale = time.time() - (days + 1) * 86400

    totals = defaultdict(lambda: {"score": 0.0, "prompts": 0, "last": 0.0})
    if not os.path.isdir(TRANSCRIPTS):
        return totals

    for project in os.scandir(TRANSCRIPTS):
        if not project.is_dir():
            continue
        for entry in os.scandir(project.path):
            if not entry.name.endswith(".jsonl"):
                continue
            try:
                if entry.stat().st_mtime < stale:
                    continue
            except OSError:
                continue
            read(entry.path, cutoff, totals)
    return totals


def read(path, cutoff, totals):
    try:
        fh = open(path, "rb")
    except OSError:
        return
    with fh:
        for line in fh:
            # The fast gate: only assistant records carry `usage`, and they are
            # a minority of the lines. Everything else is rejected by a byte
            # scan that never builds a Python object.
            if b'"assistant"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                # A live process is appending to this file while we read it, and
                # it has survived every schema this app has had. One unparseable
                # tail line is not a reason to discard the other five hundred.
                continue
            if rec.get("type") != "assistant":
                continue
            when = parse_time(rec.get("timestamp"))
            if when is None or when < cutoff:
                continue
            # **`cwd` is per record, not per session**, which is what makes a
            # session that `cd`s between repos attribute honestly to both.
            where = bucket(rec.get("cwd") or "")
            if where is None:
                continue
            usage = (rec.get("message") or {}).get("usage") or {}
            row = totals[where]
            row["score"] += (
                usage.get("output_tokens", 0) * WEIGHTS["output"]
                + usage.get("cache_creation_input_tokens", 0) * WEIGHTS["cache_creation"]
                + usage.get("input_tokens", 0) * WEIGHTS["input"]
                + usage.get("cache_read_input_tokens", 0) * WEIGHTS["cache_read"]
            )
            row["prompts"] += 1
            row["last"] = max(row["last"], when.timestamp())


def parse_time(ts):
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def rank(totals):
    """Every qualifying project, best first — **not** just the top five.

    The menu takes its five *after* removing the ones he has pinned, and a pin
    can be taken off at any moment. A file holding only five would mean an
    unpinned project vanishing entirely until the next scan, which is precisely
    the case he named: *"acel proiect să apară în lista de proiecte recente,
    doar dacă am deschis recent în acel folder vreo muncă"* — it can only appear
    if the answer is already on disk.
    """
    rows = []
    for path, row in totals.items():
        # A project deleted or renamed since the sessions that named it.
        if not os.path.isdir(path):
            continue
        rows.append({
            "name": os.path.basename(path),
            "path": path,
            "score": round(row["score"]),
            "prompts": row["prompts"],
            "lastUsed": datetime.fromtimestamp(row["last"], timezone.utc)
            .isoformat(timespec="seconds").replace("+00:00", "Z"),
        })
    rows.sort(key=lambda r: -r["score"])
    disambiguate(rows)
    return rows


def disambiguate(rows):
    """Two projects can share a folder name — `~/workspace/training-assistant`
    and `~/PycharmProjects/training-assistant` are both real here. A menu with
    the same word twice in it is a menu that cannot be answered, so the loser
    wears its parent."""
    seen = defaultdict(list)
    for r in rows:
        seen[r["name"]].append(r)
    for name, group in seen.items():
        if len(group) < 2:
            continue
        for r in group:
            parent = os.path.basename(os.path.dirname(r["path"]))
            r["name"] = f"{parent}/{name}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=14,
                    help="how far back to look (default: 14, Victor's two weeks)")
    ap.add_argument("--out", default=os.path.join(HOME, ".walkie-talkie", "recent-projects.json"))
    ap.add_argument("--print", dest="show", action="store_true",
                    help="also print the ranking as a table")
    args = ap.parse_args()

    started = time.time()
    rows = rank(scan(args.days))
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "days": args.days,
        "tookSeconds": round(time.time() - started, 2),
        "projects": rows,
    }

    out = args.out
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # Written whole and moved into place: the app reads this file on a gesture,
    # and a half-written one would be read as no recent projects at all.
    tmp = out + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh, indent=1)
        fh.write("\n")
    os.replace(tmp, out)

    if args.show:
        print(f"{len(rows)} projects, last {args.days} days, {payload['tookSeconds']}s\n")
        print(f"{'#':>3}  {'score':>9}  {'prompts':>7}  {'last':<10}  project")
        for i, r in enumerate(rows, 1):
            last = r["lastUsed"][:10]
            print(f"{i:>3}  {r['score']/1e6:8.1f}M  {r['prompts']:>7}  {last:<10}  {r['name']}")
    else:
        print(f"{len(rows)} projects → {out} ({payload['tookSeconds']}s)", file=sys.stderr)


if __name__ == "__main__":
    main()
