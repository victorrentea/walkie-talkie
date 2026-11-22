#!/usr/bin/env python3
"""What opening the picture costs in his real sessions, beyond its pixels: the round trip.

For every area prompt (same scan as read_rate.py) it finds the agent's first tool-calling message.
*picture-only*: every tool call in it reads a screenshot of that prompt — the agent stopped to
look before doing anything else, so text in the prompt could have saved that whole request.
*mixed*: the picture was read in parallel with other work — nothing to save but the pixels.
For picture-only turns: seconds from the last tool result to the next assistant record (the
second request's time to first block), that request's context size, and the output tokens of
the look itself. Prints medians; nothing private.

    python3 evals/crop-ocr/turn_cost.py [--since 2026-11-01]
"""
import argparse, collections, datetime, glob, json, os, re, statistics

import read_rate as rr


def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def scan(path, since):
    out, cur = [], None
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
        stamp = d.get("timestamp") or ""
        if t == "attachment":
            a = d.get("attachment") or {}
            s = "\n".join(x for x in (a.get("content") or []) if isinstance(x, str)) if a.get("type") == "hook_additional_context" else ""
            m = rr.FOLDER.search(s)
            if rr.TOKEN.search(s) and m and stamp >= since:
                cur = {"folder": os.path.basename((m.group(1) or m.group(2)).rstrip("/")), "t0": ts(stamp), "msgs": [], "events": []}
                out.append(cur)
        elif t == "user":
            s, tool = rr.text_of(d.get("message") or {})
            if tool and not s:
                if cur:
                    cur["events"].append(("result", ts(stamp)))
                continue
            if cur and not cur["msgs"]:
                continue                                         # the words of the attachment just seen
            cur = None
            m = rr.FOLDER.search(s)
            if rr.TOKEN.search(s) and m and stamp >= since and "<task-notification>" not in s:
                cur = {"folder": os.path.basename((m.group(1) or m.group(2)).rstrip("/")), "t0": ts(stamp), "msgs": [], "events": []}
                out.append(cur)
        elif t == "assistant" and cur:
            msg = d.get("message") or {}
            mid = msg.get("id")
            if not cur["msgs"] or cur["msgs"][-1]["id"] != mid:
                cur["msgs"].append({"id": mid, "first": ts(stamp), "last": ts(stamp), "tools": [], "usage": msg.get("usage") or {}, "model": msg.get("model")})
                cur["events"].append(("assistant", ts(stamp)))
            m = cur["msgs"][-1]
            m["last"] = ts(stamp)
            m["usage"] = msg.get("usage") or m["usage"]
            for b in msg.get("content") or []:
                if b.get("type") == "tool_use":
                    blob = json.dumps(b.get("input") or {}, ensure_ascii=False)
                    m["tools"].append("shot" if (cur["folder"] in blob and "screenshot-" in blob and b.get("name") == "Read") else b.get("name"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-11-01")
    a = ap.parse_args()
    prompts = {}
    for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        try:
            if "✂️" not in open(f, errors="replace").read():
                continue
        except OSError:
            continue
        for p in scan(f, a.since):
            if p["msgs"]:
                prompts[(p["folder"], round(p["t0"]))] = p
    kinds = collections.Counter()
    gap, ctx, outs, to_look = [], [], [], []
    for p in prompts.values():
        first = next((i for i, m in enumerate(p["msgs"]) if m["tools"]), None)
        if first is None:
            kinds["no tool call at all"] += 1
            continue
        m = p["msgs"][first]
        if "shot" not in m["tools"]:
            kinds["first tools: other work (picture later or never)"] += 1
            continue
        if any(t != "shot" for t in m["tools"]):
            kinds["first tools: picture + other work in parallel"] += 1
            continue
        kinds["first tools: picture only"] += 1
        if first + 1 < len(p["msgs"]):
            nxt = p["msgs"][first + 1]
            results = [t for k, t in p["events"] if k == "result" and m["last"] <= t <= nxt["first"]]
            if results:
                gap.append(nxt["first"] - max(results))
                u = nxt["usage"]
                ctx.append((u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0))
                outs.append(m["usage"].get("output_tokens") or 0)
                to_look.append(m["last"] - p["t0"])
    n = sum(kinds.values())
    print(f"since {a.since}: {n} area prompts answered by a Claude Code session")
    for k, v in kinds.most_common():
        print(f"  {v:4d} ({100*v/n:.0f}%)  {k}")
    if gap:
        q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(len(xs) * p))]
        print(f"picture-only turns measured: {len(gap)}")
        print(f"  prompt → the look is issued: median {statistics.median(to_look):.1f} s")
        print(f"  tool result → next assistant record (the extra request's first block): median {statistics.median(gap):.1f} s, p25 {q(gap,.25):.1f}, p75 {q(gap,.75):.1f}, p90 {q(gap,.9):.1f}")
        print(f"  context re-read by that request: median {statistics.median(ctx):,.0f} tokens, p75 {q(ctx,.75):,.0f}")
        print(f"  output tokens of the look: median {statistics.median(outs):.0f}")


if __name__ == "__main__":
    main()
