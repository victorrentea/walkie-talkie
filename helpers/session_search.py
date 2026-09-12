#!/usr/bin/env python3
"""Search Claude Code's session journals for the words Victor remembers saying.

**The question it answers is the one the terminal cannot.** `Rebind to…` lists
the destinations the relay has spoken to, newest first, and that list is right
until the session he wants is the one from Tuesday — at which point the only
thing he remembers about it is a sentence. This walks the transcripts and finds
the sentence.

**Only what was on screen counts.** A transcript holds four kinds of text and
three of them are noise here: thinking blocks, tool calls and their results are
things the agent did, not things either of them said, and searching them turns
every query into five hundred hits (measured: `bluetooth` matches 516 of 1013
files raw, and a handful of them are about Bluetooth). So a hit is either a
human prompt or a text block the assistant actually printed — *"nu thinking, nu
tool calls, ci doar mesajele vizibile în terminal"*.

**Two stages, because 1.3 GB is too much to parse and too little to index.**
`rg -l` over the window is a quarter of a second and cuts the corpus to the
files that contain the word at all; only those are streamed, line by line, and
`json.loads` runs only on the lines that hold the needle. Nothing is kept in
memory but one snippet and a counter per session, which is the other half of
the ask — *"fără să mai ții lucruri în memorie, ci direct pe jurnalele de
sesiuni"*. No index to build, no index to go stale, and the answer is as fresh
as the file on disk.

**It streams its output.** One JSON object per line, per session, as it is
found, so the panel fills in as the scan runs instead of after it; the last line
is `{"done": true, …}`. Results come out newest-session-first because the file
list is sorted by mtime, which is also why `--limit` can stop the scan early:
the twenty most recent hits are the answer, and the fortnight behind them is
work nobody is waiting for.

Usage:
    session_search.py --query "bluetooth keep alive" [--days 14] [--limit 25]
    session_search.py --recent [--limit 25]          # metadata only, no search
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import time

PROJECTS = os.path.expanduser("~/.claude/projects")
RIPGREP = "/opt/homebrew/bin/rg"

# The tty a session is running in, left on disk by the `terminal-title.sh` hook
# for its own caching. Reading it is free and it is the only place the link
# between a session id and a Terminal tab is written down — see `tty_map`.
TTY_PREFIX = "/tmp/claude-terminal-title-"
TTY_SUFFIX = ".tty"

# How much of a matched line to show. Enough to recognise the sentence, short
# enough that six rows still fit in the panel.
BEFORE, AFTER = 60, 140


# --- what counts as a visible message ---------------------------------------

def visible_text(rec):
    """The text this record put on Victor's screen, or None.

    Returns `(role, text)` with role in `me` / `claude`.
    """
    kind = rec.get("type")
    if kind not in ("user", "assistant"):
        return None
    # A sidechain is a subagent's own transcript: real text, but it scrolled past
    # in a task panel he was not reading, and it is never the session he is
    # looking for.
    if rec.get("isSidechain") or rec.get("isMeta"):
        return None
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return None

    content = msg.get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        # `text` only: `thinking`, `tool_use`, `tool_result` and `image` are the
        # three-quarters of a transcript this search exists to ignore.
        parts = [b.get("text", "") for b in content
                 if isinstance(b, dict) and b.get("type") == "text"]
    else:
        return None

    text = "\n".join(p for p in parts if p).strip()
    if not text:
        return None
    if kind == "user":
        # A tool result arrives wearing a user message; so do the harness'
        # reminders, hook output and the expansion of a slash command. None of
        # them are things he said.
        if rec.get("toolUseResult") is not None:
            return None
        head = text.lstrip()[:20]
        if head.startswith(("<command-", "<local-command", "<system-reminder",
                            "<user-prompt", "Caveat:", "<task-notification")):
            return None
        return ("me", text)
    return ("claude", text)


def snippet(text, terms):
    """The words around the first term, on one line, with ellipses."""
    low = text.lower()
    at = min((low.find(t) for t in terms if low.find(t) >= 0), default=0)
    start, end = max(0, at - BEFORE), min(len(text), at + AFTER)
    cut = " ".join(text[start:end].split())
    if start > 0:
        cut = "…" + cut
    if end < len(text):
        cut += "…"
    return cut


# --- the corpus --------------------------------------------------------------

def candidates(days, max_files):
    """Every transcript touched inside the window, newest first."""
    cutoff = time.time() - days * 86400
    files = []
    for path in glob.iglob(os.path.join(PROJECTS, "*", "*.jsonl")):
        try:
            st = os.stat(path)
        except OSError:
            continue
        if st.st_mtime >= cutoff:
            files.append((st.st_mtime, path))
    files.sort(reverse=True)
    return files[:max_files]


def prefilter(files, term):
    """The subset whose bytes contain `term` at all, ripgrep doing the reading.

    Order is preserved — newest first — because that is what makes `--limit` a
    sensible thing to stop on. A missing ripgrep is not an error: the scan then
    reads everything, which is slower and identical.
    """
    if not os.path.exists(RIPGREP):
        return files
    hit = set()
    paths = [p for _, p in files]
    # Chunked, because a thousand paths is past what one argv can carry.
    for i in range(0, len(paths), 150):
        chunk = paths[i:i + 150]
        try:
            out = subprocess.run([RIPGREP, "-l", "-i", "-F", "--", term] + chunk,
                                 capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.TimeoutExpired):
            return files
        hit.update(line for line in out.stdout.splitlines() if line)
    return [(m, p) for m, p in files if p in hit]


def tty_map():
    """`session -> (/dev/ttysNNN, is the newest session to claim that tty)`.

    **The tab a session is running in is written down already**, by the
    `terminal-title.sh` hook, which caches the tty it worked out so it does not
    have to walk the process tree twice. Reading that cache is the whole of how
    this app knows where a session from Tuesday lives.

    **The second half of the tuple is what makes it usable.** A tty is recycled:
    `ttys016` has belonged to a dozen sessions this fortnight, and every one of
    them left a file saying so. The file's mtime is when that session first fired
    a hook, i.e. when it started — so the newest claimant of a tty is the session
    sitting in it now, and everyone else is a former tenant. Whether the tab is
    still open at all is a question for Terminal.app, and the app asks it.
    """
    owners = {}
    claims = {}
    for path in glob.iglob(TTY_PREFIX + "*" + TTY_SUFFIX):
        session = path[len(TTY_PREFIX):-len(TTY_SUFFIX)]
        try:
            device = open(path).read().strip()
            stamp = os.stat(path).st_mtime
        except OSError:
            continue
        if not device:
            continue
        claims[session] = device
        if stamp > owners.get(device, (0, ""))[0]:
            owners[device] = (stamp, session)
    return {s: (d, owners.get(d, (0, ""))[1] == s) for s, d in claims.items()}


def scan(path, mtime, terms, want_text, ttys):
    """One transcript, streamed. Returns the row to print, or None.

    Memory here is one snippet and three counters whatever the file's size — a
    13 MB transcript is read, not held.
    """
    session = os.path.splitext(os.path.basename(path))[0]
    row = {"session": session, "path": path, "mtime": mtime,
           "cwd": "", "branch": "", "title": "", "hits": 0,
           "role": "", "snippet": ""}
    needle = terms[0] if terms else ""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                # Two substring tests before any parsing: the titles are two
                # records in a file of thousands, and the needle is absent from
                # almost every line of the ones that contain it at all.
                has_title = "-title" in line
                if not has_title and (not want_text or needle not in line.lower()):
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                kind = rec.get("type")
                if kind == "ai-title" and rec.get("aiTitle"):
                    row["title"] = rec["aiTitle"]
                    continue
                if kind == "custom-title" and rec.get("customTitle"):
                    # What `/rename` set wins over the generated title, the same
                    # precedence Claude Code's own window title uses.
                    row["title"] = rec["customTitle"]
                    continue
                if not want_text:
                    continue
                seen = visible_text(rec)
                if not seen:
                    continue
                role, text = seen
                low = text.lower()
                if not all(t in low for t in terms):
                    continue
                row["hits"] += 1
                # The **latest** match is kept, not the first: what he is trying
                # to recognise is where that session got to, and a word said once
                # at the top is the least of what the session was about.
                row["role"] = role
                row["snippet"] = snippet(text, terms)
                row["cwd"] = rec.get("cwd") or row["cwd"]
                row["branch"] = rec.get("gitBranch") or row["branch"]
    except OSError:
        return None
    if want_text and not row["hits"]:
        return None
    if not row["cwd"]:
        row["cwd"] = project_cwd(path)
    row["folder"] = os.path.basename(row["cwd"].rstrip("/")) or row["cwd"]
    device, owner = ttys.get(session, (None, False))
    row["tty"], row["ttyOwner"] = device, owner
    return row


def project_cwd(path):
    """The folder a transcript belongs to, read back off the directory name.

    `~/.claude/projects/-Users-victorrentea-workspace-walkie-talkie/` — the
    mangling is lossy (a folder with a dash in it is indistinguishable from a
    slash), so this is the fallback for a file whose records carried no `cwd`,
    never the first answer.
    """
    name = os.path.basename(os.path.dirname(path))
    return name.replace("-", "/", 1).replace("-", "/") if name.startswith("-") else name


def tail_title(path):
    """The session's title from the last 256 KB — for `--recent`, which does not
    read the file otherwise. Both title records are re-appended on every save."""
    try:
        with open(path, "rb") as f:
            size = f.seek(0, 2)
            f.seek(max(0, size - 256 * 1024))
            chunk = f.read().decode("utf-8", "replace")
    except OSError:
        return ""
    title = ""
    for line in chunk.splitlines():
        if "-title" not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") == "custom-title" and rec.get("customTitle"):
            title = rec["customTitle"]
        elif rec.get("type") == "ai-title" and rec.get("aiTitle"):
            title = rec["aiTitle"]
    return title


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", default="")
    ap.add_argument("--recent", action="store_true")
    ap.add_argument("--days", type=float, default=21)
    ap.add_argument("--limit", type=int, default=25)
    ap.add_argument("--max-files", type=int, default=600)
    args = ap.parse_args()

    terms = [t for t in args.query.lower().split() if t]
    want_text = bool(terms) and not args.recent
    started = time.time()

    ttys = tty_map()
    files = candidates(args.days, args.max_files)
    if want_text:
        # Prefiltered on the longest term: the rarest word costs the least to
        # look for and every other term is checked in the parse anyway.
        files = prefilter(files, max(terms, key=len))

    found = 0
    for mtime, path in files:
        row = (scan(path, mtime, terms, want_text, ttys) if want_text
               else recent_row(path, mtime, ttys))
        if not row:
            continue
        found += 1
        sys.stdout.write(json.dumps(row, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        if found >= args.limit:
            break

    sys.stdout.write(json.dumps({"done": True, "found": found,
                                 "scanned": len(files),
                                 "elapsed": round(time.time() - started, 3)}) + "\n")
    sys.stdout.flush()


def recent_row(path, mtime, ttys):
    """`--recent`: the session's name badge, with no search behind it."""
    session = os.path.splitext(os.path.basename(path))[0]
    cwd = project_cwd(path)
    device, owner = ttys.get(session, (None, False))
    return {"session": session, "path": path, "mtime": mtime, "cwd": cwd,
            "folder": os.path.basename(cwd.rstrip("/")) or cwd, "branch": "",
            "title": tail_title(path), "hits": 0, "role": "", "snippet": "",
            "tty": device, "ttyOwner": owner}


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # The panel closed, or the next keystroke superseded this scan and the
        # app hung up. Both are ordinary here.
        os._exit(0)
