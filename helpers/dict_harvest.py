#!/usr/bin/env python3
"""dict_harvest — the weekly pass that finds misheard → right word pairs in the week's conversations
and feeds them to walkie-dict (2026-11-14).

    python3 helpers/dict_harvest.py                 # last 7 days, apply the sure pairs, write the report
    python3 helpers/dict_harvest.py --dry-run       # same, change nothing
    python3 helpers/dict_harvest.py --days 2 --limit 40 --dry-run   # a quick look

**Why.** Victor, 2026-11-14: *"Nu ar fi mai corect să mutăm colectarea cuvintelor stâlcite-corecte
scanând conversațiile săptămânal … avem mai bun context văzând toată conversația … nu distragem
atenția sesiunii de lucru"* — and *"ținta finală e să lucreze în weekend, să aibă mai mult conținut
de inspectat (probabil cu subagenți)"*. Until now the only path was `AppDelegate.dictionaryHint`:
the agent receiving the prompt, mid-task and with one sentence of context, decided alone.

**What it reads.** Every dictation of the window from `~/.walkie-talkie/outbox.jsonl` (the text as
recognised, before any agent saw it), each matched to the conversation it went into — Claude Code
transcripts (`~/.claude/projects/*/*.jsonl`) and Copilot CLI events (`~/.copilot/session-state/*/
events.jsonl`) — to take the agent's reply after it and Victor's next message. The strongest
evidence is his own correction in the next message ("nu, am zis X"); next, the agent writing the
term right in its reply. A dictation with no transcript match still goes in, with no context.

**Who decides.** Parallel `claude -p` workers (Sonnet, on the subscription, lean flags — no tools,
no settings, no MCP: `reference_lean_claude_p`), one per chunk of dictations — the "subagents".
Each returns pairs with a quote as evidence. **Pairs accumulate across weeks** in
`dict-harvest/ledger.json`, one sighting per dictation (keyed by its timestamp, so re-running the
same days counts nothing twice); only high-confidence sightings count. A pair is promoted
(`walkie-dict add <right> --heard <heard>`) at **2** sightings when one of them is his own
correction (`word*`), at **3** when all are inferred — and never while another spelling for the
same `heard` has as many. An unpromoted pair not seen again for 60 days fades out (120 for one hour; Victor: "poate chiar de 60 zile"). A pair whose
`heard` is not literally in the dictation is thrown away (the model invented it). Pairs already in
`vocabulary.txt` are given to the workers as KNOWN and skipped.

**Output.** `~/.walkie-talkie/dict-harvest/<date>.md` (+ `.json` with every proposal).
Scheduled weekly by the LaunchAgent `ro.victorrentea.dict-harvest` (Saturday 03:30).
"""
import argparse
import collections
import concurrent.futures as cf
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
WT = os.path.join(HOME, ".walkie-talkie")
OUT = os.path.join(WT, "dict-harvest")
VOCAB = os.path.join(WT, "vocabulary.txt")
LEDGER = os.path.join(OUT, "ledger.json")
PROMOTE_CORRECTED, PROMOTE_DEDUCED = 2, 3   # sightings to enter the dictionary: with one of his * fixes / inferred only
FORGET_DAYS = 60                             # an unpromoted pair not seen again for this long is dropped
WALKIE_DICT = os.path.join(HOME, ".local", "bin", "walkie-dict")
TOKEN = re.compile(r"\[[^\]]{0,300}\]")   # [📸0 auto], [selected: …], footer rows
# His correction convention (Victor, 2026-11-14): the next prompt, usually the very next one, carries
# the right word followed by an asterisk — "claude-gpt*". Not markdown (**bold**, *em*), not a glob.
STARRED = re.compile(r"(?<![\w*])([\w][\w.\-/'’ăâîșțşţ]*)\*(?![\w*])")   # the word just before the *; a multi-word fix is read from NEXT itself

SYSTEM = """You find speech-recognition mistakes in dictated prompts. The speaker, Victor, is a Romanian \
software trainer who dictates prompts to coding agents in Romanian and English, full of tool names, \
product names, people's names and technical terms. For each numbered item you get DICTATION (the \
recogniser's raw output), REPLY (what the agent answered next) and NEXT (Victor's next message), \
when known.

Find terms the recogniser wrote wrong: a name, product, tool, command, file, or technical/English \
word. NOT: Romanian grammar endings or diacritics, filler words, punctuation, style, a word that is \
merely unusual. Each pair needs evidence from the context:
- "user-corrected": NEXT corrects it. His usual way: NEXT (often his very next message) holds the \
right word followed by an asterisk — "claude-gpt*" means "the word you got wrong is claude-gpt"; a \
STARRED line lists those. Find the span of DICTATION it replaces. Also "nu, am zis X", "I meant X";
- "agent-used": REPLY clearly refers to the same thing spelled right;
- "well-known": an unmistakable known name (e.g. "Cloud Code" for "Claude Code") — high only if certain.

Skip pairs already listed in KNOWN. "heard" must be copied exactly from DICTATION (the shortest span \
that is wrong, 1–4 words); "right" is the correct spelling. Reply with ONLY a JSON array, no prose:
[{"item": 3, "heard": "...", "right": "...", "evidence": "user-corrected|agent-used|well-known", \
"quote": "<≤15 words from REPLY/NEXT proving it>", "confidence": "high|medium"}]
Return [] when there is nothing."""


def starred(next_msg):
    """His corrections in a next message: a short message ending in * is the corrected phrase whole
    ("pe numele titlului sesiunii*", "un sunet*" — the 30 days before 2026-11-14); elsewhere, the
    word right before a *."""
    t = TOKEN.sub(" ", next_msg or "").strip()
    if t.endswith("*") and not t.endswith("**") and len(t.split()) <= 8:
        return [t.rstrip("*").strip()]
    return [m.strip().rstrip(".,;:") for m in STARRED.findall(t)]


def norm(s):
    return re.sub(r"\s+", " ", TOKEN.sub(" ", s or "")).strip().lower()


def dictations(since, limit):
    out = []
    for line in open(os.path.join(WT, "outbox.jsonl"), errors="ignore"):
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if j.get("kind") != "dictation" or (j.get("ts") or "") < since:
            continue
        text = (j.get("text") or "").strip()
        if len(text.split()) >= 3:
            out.append({"ts": j["ts"], "text": text, "app": j.get("app") or ""})
    return out[-limit:] if limit else out


def block_text(content):
    if isinstance(content, str):
        return content
    return "\n".join(b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") == "text")


def conversations(since_epoch):
    """[(path, [(role, text)])] for every transcript touched in the window."""
    convs = []
    for path in glob.glob(os.path.join(HOME, ".claude", "projects", "*", "*.jsonl")):
        if "evals" in path or os.path.getmtime(path) < since_epoch:
            continue
        turns = []
        for line in open(path, errors="ignore"):
            if '"type":"user"' not in line and '"type":"assistant"' not in line:
                continue
            try:
                j = json.loads(line)
            except ValueError:
                continue
            if j.get("isMeta") or j.get("isSidechain") or j.get("type") not in ("user", "assistant"):
                continue
            t = block_text((j.get("message") or {}).get("content")).strip()
            if t:
                turns.append((j["type"], t))
        if turns:
            convs.append((path, turns))
    for path in glob.glob(os.path.join(HOME, ".copilot", "session-state", "*", "events.jsonl")):
        if os.path.getmtime(path) < since_epoch:
            continue
        turns = []
        for line in open(path, errors="ignore"):
            if '"user.message"' not in line and '"assistant.message"' not in line:
                continue
            try:
                j = json.loads(line)
            except ValueError:
                continue
            d = j.get("data") or {}
            if j.get("type") == "user.message" and d.get("source") != "memory" and (d.get("content") or "").strip():
                turns.append(("user", d["content"].strip()))
            elif j.get("type") == "assistant.message" and (d.get("content") or "").strip():
                turns.append(("assistant", d["content"].strip()))
        if turns:
            convs.append((path, turns))
    return convs


def attach_context(items, convs):
    index = [(p, i, norm(t)) for p, turns in convs for i, (r, t) in enumerate(turns) if r == "user"]
    by_path = dict(convs)
    for it in items:
        key = norm(it["text"])[:60]
        hit = next(((p, i) for p, i, t in index if key and key in t), None)
        it["reply"] = it["next"] = ""
        if not hit:
            continue
        p, i = hit
        turns = by_path[p]
        reply = []
        for r, t in turns[i + 1:]:
            if r == "user":
                it["next"] = TOKEN.sub(" ", t)[:600]
                break
            reply.append(t)
        it["reply"] = "\n".join(reply)[:1200]
        it["where"] = p


def known_pairs():
    known = []
    if os.path.exists(VOCAB):
        for l in open(VOCAB):
            l = l.strip()
            if l and not l.startswith("#"):
                known.append(l)
    return known


def ask(chunk, known, model):
    body = ["KNOWN: " + "; ".join(known), ""]
    for n, it in enumerate(chunk, 1):
        body.append(f"## item {n}\nDICTATION: {it['text']}")
        if it["reply"]:
            body.append(f"REPLY: {it['reply']}")
        if it["next"]:
            body.append(f"NEXT: {it['next']}")
            fixes = starred(it["next"])
            if fixes:
                body.append("STARRED: " + "; ".join(fixes))
        body.append("")
    cmd = ["claude", "-p", "--model", model, "--tools", "", "--strict-mcp-config", "--setting-sources", "",
           "--no-session-persistence", "--system-prompt", SYSTEM]
    p = subprocess.run(cmd, input="\n".join(body), capture_output=True, text=True, timeout=900)
    m = re.search(r"\[.*\]", p.stdout, re.S)
    if p.returncode or not m:
        raise RuntimeError((p.stderr or p.stdout)[-400:])
    out = []
    for r in json.loads(m.group(0)):
        try:
            it = chunk[int(r["item"]) - 1]
        except (KeyError, ValueError, IndexError, TypeError):
            continue
        heard, right = str(r.get("heard", "")).strip(), str(r.get("right", "")).strip()
        if not heard or not right or heard.lower() == right.lower() or heard.lower() not in it["text"].lower():
            continue   # empty, a no-op, or a span the model made up
        out.append({**r, "heard": heard, "right": right, "ts": it["ts"], "dictation": it["text"]})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--limit", type=int, default=0, help="only the newest N dictations")
    ap.add_argument("--chunk", type=int, default=25)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    start = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=a.days)
    items = dictations(start.strftime("%Y-%m-%dT%H:%M:%S"), a.limit)
    attach_context(items, conversations(start.timestamp() - 86400))
    known = known_pairs()
    chunks = [items[i:i + a.chunk] for i in range(0, len(items), a.chunk)]
    print(f"{len(items)} dictations, {sum(bool(i.get('where')) for i in items)} with their conversation, "
          f"{len(chunks)} chunks", flush=True)

    found, failed = [], 0
    with cf.ThreadPoolExecutor(a.workers) as ex:
        for fut in cf.as_completed([ex.submit(ask, c, known, a.model) for c in chunks]):
            try:
                found += fut.result()
            except Exception as e:   # one chunk must not sink the week
                failed += 1
                print("chunk failed:", str(e)[:200], file=sys.stderr)

    # The ledger: every sighting across weeks, keyed by the dictation's timestamp so a re-run of the
    # same days counts nothing twice. Victor, 2026-11-14: *"corecțiile explicite sau deduse ar trebui
    # să se acumuleze între săptămâni (eventual cu un counter) și la 2 (sau 3) apariții să fie
    # promovate în dicționar"*. Only high-confidence sightings count.
    ledger = json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}
    for f in found:
        e = ledger.setdefault(f["heard"].lower() + " → " + f["right"],
                              {"heard": f["heard"], "right": f["right"], "sightings": {}, "promoted": None})
        e["sightings"][f["ts"]] = {k: f.get(k) for k in ("evidence", "confidence", "quote")} | {"dictation": f["dictation"][:160]}
    horizon = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=FORGET_DAYS)).strftime("%Y-%m-%dT%H:%M:%S")
    for e in ledger.values():   # an unpromoted pair not seen again in FORGET_DAYS fades out
        if not e["promoted"]:
            e["sightings"] = {ts: s for ts, s in e["sightings"].items() if ts >= horizon}
    ledger = {k: e for k, e in ledger.items() if e["sightings"]}

    def counted(e):
        return [s for s in e["sightings"].values() if s.get("confidence") == "high"]

    def needed(e):
        return PROMOTE_CORRECTED if any(s.get("evidence") == "user-corrected" for s in counted(e)) else PROMOTE_DEDUCED

    rivals = collections.defaultdict(list)
    for e in ledger.values():
        rivals[e["heard"].lower()].append(e)
    applied, review = [], []
    seen_now = {(f["heard"].lower(), f["right"]) for f in found}
    for key, e in sorted(ledger.items(), key=lambda kv: -len(counted(kv[1]))):
        n = len(counted(e))
        contested = any(r is not e and len(counted(r)) >= n for r in rivals[e["heard"].lower()])
        entry = {"heard": e["heard"], "right": e["right"], "count": n, "needed": needed(e),
                 "evidence": sorted({s.get("evidence") or "?" for s in e["sightings"].values()}),
                 "quote": next(iter(e["sightings"].values())).get("quote", ""), "contested": contested}
        if e["promoted"]:
            continue
        if n >= needed(e) and not contested:
            if not a.dry_run:
                r = subprocess.run([WALKIE_DICT, "add", e["right"], "--heard", e["heard"]], capture_output=True, text=True)
                entry["walkie_dict"] = (r.stdout + r.stderr).strip()[-200:]
                e["promoted"] = dt.datetime.now().strftime("%Y-%m-%d")
            applied.append(entry)
        elif (e["heard"].lower(), e["right"]) in seen_now:
            review.append(entry)
    if not a.dry_run:
        os.makedirs(OUT, exist_ok=True)
        json.dump(ledger, open(LEDGER, "w"), ensure_ascii=False, indent=1)

    os.makedirs(OUT, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d")
    json.dump({"dictations": len(items), "chunks": len(chunks), "failed_chunks": failed, "dry_run": a.dry_run,
               "applied": applied, "review": review, "all": found},
              open(os.path.join(OUT, stamp + ".json"), "w"), ensure_ascii=False, indent=1)
    md = [f"# Dictionary harvest {stamp}" + (" (dry run)" if a.dry_run else ""), "",
          f"{len(items)} dictations over {a.days:g} days, {sum(bool(i.get('where')) for i in items)} matched to "
          f"their conversation, {len(chunks)} chunks ({failed} failed).", "",
          f"## {'Would promote' if a.dry_run else 'Promoted to the dictionary'} ({len(applied)})", ""]
    row = lambda e: (f"- `{e['heard']}` → **{e['right']}** {e['count']}/{e['needed']} ({', '.join(e['evidence'])})"
                     + (" — contested by another spelling" if e["contested"] else "") + f" — “{e['quote']}”")
    md += [row(e) for e in applied]
    md += ["", f"## Seen this run, still counting ({len(review)})", ""]
    md += [row(e) for e in review]
    path = os.path.join(OUT, stamp + ".md")
    open(path, "w").write("\n".join(md) + "\n")
    print("\n".join(md))
    print("report:", path)


if __name__ == "__main__":
    sys.exit(main())
