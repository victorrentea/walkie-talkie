#!/usr/bin/env python3
"""How often does an agent open an area's picture? Reads Claude Code session transcripts
(~/.claude/projects/*/*.jsonl, main sessions only): for every dictated prompt carrying
`📸n✂️…`, looks at the tool calls up to the next prompt of Victor's and records whether
`screenshot-n.jpg` (the cut-out), `-800px` or `-original` of that prompt's folder was opened
(Read, or named in a Bash command). Prints counts only; writes out/read-rate.jsonl.

    python3 evals/crop-ocr/read_rate.py [--since 2026-10-01]
"""
import argparse, collections, glob, json, os, pathlib, re

OUT = pathlib.Path(__file__).parent / "out"
TOKEN = re.compile(r"📸(\d+)✂️")     # with the walkie-inbox mod the words say `[📸1✂️]`, the corners ride a hook attachment
FOLDER = re.compile(r"\[📁=([^\]\s]+)\]|((?:\$WALKIE_SHOTS|/Users/[^\s\]]*?/shots)/\d{4}-\d\d-\d\d-[\d-]+)")


def text_of(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c, False
    parts, tool = [], False
    for b in c or []:
        if b.get("type") == "text":
            parts.append(b.get("text", ""))
        elif b.get("type") == "tool_result":
            tool = True
    return "\n".join(parts), tool


def scan(path, since):
    prompts, cur = [], None
    for line in open(path, errors="replace"):
        if '"type"' not in line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get("isSidechain"):
            continue
        t = d.get("type")
        if t == "attachment":                                   # the mod's rows: folder + corners
            a = d.get("attachment") or {}
            if a.get("type") != "hook_additional_context":
                continue
            s = "\n".join(x for x in (a.get("content") or []) if isinstance(x, str))
            ns = sorted(set(TOKEN.findall(s)))
            m = FOLDER.search(s)
            if not (ns and m) or (d.get("timestamp") or "") < since:
                continue
            folder = os.path.basename((m.group(1) or m.group(2)).rstrip("/"))
            if cur and not cur["busy"] and not cur["folder"]:
                cur["folder"] = folder
                cur["areas"] = sorted(set(cur["areas"]) | set(ns))
            elif not (cur and cur["folder"] == folder):
                cur = {"ts": d.get("timestamp"), "folder": folder, "areas": ns, "opened": {},
                       "question": False, "long": False, "busy": False, "mod": True}
                prompts.append(cur)
        elif t == "user":
            s, tool = text_of(d.get("message") or {})
            if tool and not s:
                continue                                        # a tool result, not a prompt
            ns = sorted(set(TOKEN.findall(s)))
            if cur and cur.get("mod") and not cur["busy"]:      # the words of the attachment just seen
                cur["question"] = "?" in s
                continue
            cur = None
            if (d.get("timestamp") or "") < since:
                continue
            if ns and "📸" in s[:4000] and "<task-notification>" not in s:
                m = FOLDER.search(s)
                folder = os.path.basename((m.group(1) or m.group(2)).rstrip("/")) if m else None
                cur = {"ts": d.get("timestamp"), "folder": folder, "areas": ns, "opened": {},
                       "question": "?" in s.split("\n[")[0], "long": "cut out as" in s, "busy": False}
                prompts.append(cur)
        elif t == "assistant" and cur:
            cur["busy"] = True
            cur["model"] = (d.get("message") or {}).get("model")
            for b in (d.get("message") or {}).get("content") or []:
                if b.get("type") != "tool_use":
                    continue
                blob = json.dumps(b.get("input") or {}, ensure_ascii=False)
                if cur["folder"] and cur["folder"] not in blob:
                    continue
                for n in cur["areas"]:
                    for kind, pat in (("cut", rf"screenshot-{n}(?:-\d+)?\.jpg"), ("800", rf"screenshot-{n}-800px"),
                                      ("orig", rf"screenshot-{n}-original")):
                        if re.search(pat, blob):
                            cur["opened"].setdefault(n, [])
                            if kind not in cur["opened"][n]:
                                cur["opened"][n].append(kind)
    return prompts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-11-13")           # rules v3: an area is its token alone
    a = ap.parse_args()
    files = [f for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
             if os.path.getmtime(f) > 0]
    prompts = []
    for f in files:
        try:
            if "✂️" not in open(f, errors="replace").read():
                continue
        except OSError:
            continue
        prompts += scan(f, a.since)
    # the same prompt appears again in a resumed/forked transcript: keep one per (ts, folder)
    prompts = [p for p in prompts if p["folder"] and p.get("model")]     # no folder: quoted text, not a delivery
    uniq = {(p["folder"], tuple(p["areas"])): p for p in prompts}
    prompts = sorted(uniq.values(), key=lambda p: p["ts"] or "")
    OUT.mkdir(exist_ok=True)
    with open(OUT / "read-rate.jsonl", "w") as f:
        for p in prompts:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")
    crops = cut = any_ = 0
    per_prompt = collections.Counter()
    for p in prompts:
        got = 0
        for n in p["areas"]:
            crops += 1
            o = p["opened"].get(n, [])
            cut += "cut" in o
            any_ += bool(o)
            got += bool(o)
        per_prompt["all" if got == len(p["areas"]) else "some" if got else "none"] += 1
    print(f"since {a.since}: {len(prompts)} prompts with an area, {crops} areas")
    print(f"  cut-out opened: {cut} ({100*cut/max(crops,1):.0f}%)   any file of that shot opened: {any_} ({100*any_/max(crops,1):.0f}%)")
    print("  per prompt:", dict(per_prompt))
    q = [p for p in prompts if p["question"]]
    print("  with a '?':", len(q), "opened ≥1:", sum(bool(p["opened"]) for p in q))
    print("  by model:", collections.Counter((p.get("model") or "?") for p in prompts).most_common(5))


if __name__ == "__main__":
    main()
