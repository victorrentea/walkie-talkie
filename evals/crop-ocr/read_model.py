#!/usr/bin/env python3
"""A model reads each crop through `claude -p` (subscription, lean flags, one image per call):
verbatim text + what kind of crop it is. Appends to out/read-<model>.jsonl; re-running skips
crops already read.

    python3 evals/crop-ocr/read_model.py --model haiku                 # every crop
    python3 evals/crop-ocr/read_model.py --model opus --ids out/reference-ids.txt
"""
import argparse, concurrent.futures, json, pathlib, re, subprocess, tempfile, time

HERE = pathlib.Path(__file__).parent
OUT = HERE / "out"
PROMPT = """Read the image {path} (one Read call) and answer with ONE JSON object, nothing else:
{{"kind": "text-only" | "mostly-text" | "ui-with-text" | "pictorial",
 "content": "code" | "terminal" | "prose" | "ui-labels" | "table" | "mixed" | "none",
 "language": "en" | "ro" | "mixed" | "none",
 "cut": true | false,
 "text": "<every character of text visible in the image, verbatim, line by line with \\n between lines, reading order; keep case, punctuation, diacritics, symbols and emoji exactly; no description, no correction of typos; empty string if no text>"}}
kind: text-only = nothing but characters on a plain background; mostly-text = text plus a little chrome (an icon, a border, a button edge); ui-with-text = controls, icons or layout matter as much as the words; pictorial = a picture, icon, chart or photo where text is absent or incidental.
cut: true if a line of text is visibly sliced by the edge of the image."""


def read(model, crop, empty):
    cmd = ["claude", "-p", PROMPT.format(path=crop["file"]), "--model", model, "--output-format", "json",
           "--allowedTools", "Read", "--add-dir", str(OUT / "crops"),
           "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--setting-sources", ""]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=empty, capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL)
        d = json.loads(p.stdout)
    except Exception as e:                                      # noqa: BLE001 — logged, the crop is retried next run
        return {"id": crop["id"], "error": repr(e)[:300]}
    wall = time.time() - t0
    raw = d.get("result") or ""
    m = re.search(r"\{.*\}", raw, re.S)
    try:
        ans = json.loads(m.group(0)) if m else None
    except json.JSONDecodeError:
        ans = None
    u = d.get("usage") or {}
    row = {"id": crop["id"], "model": next(iter(d.get("modelUsage") or {}), model), "wall": round(wall, 2),
           "api_ms": d.get("duration_api_ms"), "turns": d.get("num_turns"), "cost": d.get("total_cost_usd"),
           "in": u.get("input_tokens"), "cache_w": u.get("cache_creation_input_tokens"),
           "cache_r": u.get("cache_read_input_tokens"), "out": u.get("output_tokens")}
    if ans is None:
        row["error"] = "unparsed: " + raw[:200]
    else:
        row.update({k: ans.get(k) for k in ("kind", "content", "language", "cut", "text")})
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--ids")
    ap.add_argument("--parallel", type=int, default=3)
    a = ap.parse_args()
    crops = [json.loads(l) for l in open(OUT / "crops.jsonl")]
    if a.ids:
        keep = set(pathlib.Path(a.ids).read_text().split())
        crops = [c for c in crops if c["id"] in keep]
    dest = OUT / f"read-{a.model}.jsonl"
    done = {json.loads(l)["id"] for l in open(dest)} if dest.exists() else set()
    todo = [c for c in crops if c["id"] not in done]
    empty = tempfile.mkdtemp(prefix="crop-ocr-")
    with concurrent.futures.ThreadPoolExecutor(a.parallel) as ex, open(dest, "a") as f:
        for i, row in enumerate(ex.map(lambda c: read(a.model, c, empty), todo), 1):
            if "error" in row and "kind" not in row:
                print("ERR", row["id"], row["error"][:120], flush=True)
                continue
            f.write(json.dumps(row, ensure_ascii=False) + "\n"); f.flush()
            if i % 20 == 0:
                print(i, "/", len(todo), flush=True)
    print("done", dest)


if __name__ == "__main__":
    main()
