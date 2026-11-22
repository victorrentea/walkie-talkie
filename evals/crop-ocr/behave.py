#!/usr/bin/env python3
"""The same request about a text crop, delivered four ways to a real headless Claude Code session
(the installed agent rules, as evals/agent-rules/run.py runs it; subscription):

  pic        today's short envelope: the area token + [📁=…]; the agent must open screenshot-1.jpg
  text+pic   the same + one row with Apple Vision's reading, hedged ("OCR, may misread …")
  text       the same row, unhedged
  text-first the same row saying the text replaces the look (what a rules v4 line would say)

Cases are his own text crops (reference = the top model's reading, out/read-fable.jsonl); five ask
for the text verbatim (scored by CER against the reference — an OCR slip trusted shows up here),
three for its gist (read by hand). No '?' in the words and only Read allowed, so nothing calls
walkie-reply. Records whether the picture was opened, tokens, cost, wall time → out/behave.jsonl.

    python3 evals/crop-ocr/behave.py [--model opus] [--reps 1]
"""
import argparse, concurrent.futures, json, pathlib, random, shutil, subprocess, tempfile, time

import score

OUT = pathlib.Path(__file__).parent / "out"
VERBATIM = "Type out exactly what this box says, character for character, and nothing else."
GIST = "Say in one short sentence what this text is about, nothing else."
ROWS = {"pic": None,
        "text+pic": '[📸1✂️ reads (OCR, may misread a character — the picture is the authority): "{t}"]',
        "text": '[📸1✂️ text: "{t}"]',
        # what a rules v4 line would say, carried in the row because the installed rules are v3
        "text-first": '[📸1✂️ text, read by OCR — use it instead of opening the picture; open screenshot-1.jpg only if '
                      'layout or colour matters, or the text looks garbled: "{t}"]'}


def cases():
    random.seed(3)
    crops = score.load("crops.jsonl"); ref = score.load("read-fable.jsonl"); sc = score.load("scores.jsonl")
    ok = [i for i, r in ref.items() if not crops[i].get("synthetic") and r["kind"] in ("text-only", "mostly-text")
          and 25 <= len(r["text"]) <= 400]
    wrong = [i for i in ok if sc[i]["accurate"]["cer"] > 0.02]
    right = [i for i in ok if sc[i]["accurate"]["cer"] <= 0.02]
    random.shuffle(wrong); random.shuffle(right)
    pick = wrong[:4] + right[:4]
    return [{"id": i, "ask": VERBATIM if k % 8 not in (3, 6, 7) else GIST, "crop": crops[i], "ref": ref[i]["text"],
             "ocr_cer": sc[i]["accurate"]["cer"]} for k, i in enumerate(pick)]


def run(model, case, variant, ocr, root):
    folder = pathlib.Path(root) / f"{case['id']}-{variant.replace('+', '')}"
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(case["crop"]["file"], folder / "screenshot-1.jpg")
    c = case["crop"]
    words = f"[📸1✂️0,0→{c['w']},{c['h']}] {case['ask']}"
    rows = ["[dictated 💻 · 🎙️]", f"[📁={folder}]"]
    if ROWS[variant]:
        rows.append(ROWS[variant].format(t=ocr[case["id"]].replace("\n", " ⏎ ")))
    prompt = words + "\n\n" + "\n".join(rows)
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "stream-json", "--verbose",
           "--allowedTools", "Read", "--add-dir", str(root), "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}']
    cwd = tempfile.mkdtemp(prefix="crop-behave-")
    t0 = time.time()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=420, stdin=subprocess.DEVNULL)
    wall = time.time() - t0
    opened, res = False, {}
    for line in p.stdout.splitlines():
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get("type") == "assistant":
            for b in (d.get("message") or {}).get("content") or []:
                if b.get("type") == "tool_use" and "screenshot-1" in json.dumps(b.get("input") or {}):
                    opened = True
        elif d.get("type") == "result":
            res = d
    u = res.get("usage") or {}
    ans = (res.get("result") or "").strip()
    row = {"case": case["id"], "ask": "verbatim" if case["ask"] == VERBATIM else "gist", "variant": variant,
           "opened": opened, "turns": res.get("num_turns"), "wall": round(wall, 1), "api_ms": res.get("duration_api_ms"),
           "total_in": sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")),
           "out": u.get("output_tokens"), "cost": res.get("total_cost_usd"), "prompt_chars": len(prompt),
           "ocr_cer": case["ocr_cer"], "answer": ans}
    if row["ask"] == "verbatim":
        A = score.norm(ans.strip("`\"“” \n")); R = score.norm(case["ref"])
        row["cer"] = score.lev(R, A) / len(R)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="opus")
    ap.add_argument("--reps", type=int, default=1)
    ap.add_argument("--only", default=",".join(ROWS))
    a = ap.parse_args()
    ocr = {}
    for l in open(OUT / "ocr.jsonl"):
        r = json.loads(l)
        if r["config"] == "accurate":
            ocr[pathlib.Path(r["file"]).stem] = "\n".join(x["t"] for x in r["lines"])
    root = tempfile.mkdtemp(prefix="crop-behave-shots-")
    jobs = [(c, v) for _ in range(a.reps) for c in cases() for v in ROWS if v in a.only.split(",")]
    with concurrent.futures.ThreadPoolExecutor(2) as ex, open(OUT / "behave.jsonl", "a") as f:
        for row in ex.map(lambda j: run(a.model, j[0], j[1], ocr, root), jobs):
            row["model"] = a.model
            f.write(json.dumps(row, ensure_ascii=False) + "\n"); f.flush()
            print(row["case"][-22:], row["variant"], "opened" if row["opened"] else "not opened", row["turns"], "turns",
                  row["wall"], "s", row["total_in"], "in", row["out"], "out", f"${row['cost']:.3f}" if row["cost"] else "",
                  f"CER {100*row['cer']:.1f}%" if "cer" in row else "", flush=True)


if __name__ == "__main__":
    main()
