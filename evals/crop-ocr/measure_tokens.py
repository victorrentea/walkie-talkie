#!/usr/bin/env python3
"""What a crop costs the agent that opens it, measured through `claude -p` usage — not the w×h/750 rule.

Each run is a lean headless session told to Read one file and answer `ok`. Total input
(input + cache write + cache read, both turns) minus the same run on a 1-byte text file leaves
the image's own tokens (counted twice: the tool result enters turn 2, nothing re-reads it later
here). Images are one real crop rescaled to exact sizes, so only the pixels vary.
Text: the same trick with OCR text of his crops pasted into the prompt → tokens per character.

    python3 evals/crop-ocr/measure_tokens.py --model opus
"""
import argparse, json, pathlib, subprocess, tempfile

OUT = pathlib.Path(__file__).parent / "out"
SIZES = [(48, 36), (160, 44), (311, 94), (640, 190), (1150, 560), (1600, 1000), (2400, 1400)]


def run(model, prompt, add_dir, cwd):
    cmd = ["claude", "-p", prompt, "--model", model, "--output-format", "json", "--allowedTools", "Read",
           "--add-dir", add_dir, "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--setting-sources", ""]
    d = json.loads(subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=300,
                                  stdin=subprocess.DEVNULL).stdout)
    u = d["usage"]
    return {"total_in": u["input_tokens"] + u["cache_creation_input_tokens"] + u["cache_read_input_tokens"],
            "out": u["output_tokens"], "turns": d["num_turns"], "ms": d["duration_ms"], "api_ms": d.get("duration_api_ms"),
            "cost": d["total_cost_usd"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="opus")
    a = ap.parse_args()
    work = pathlib.Path(tempfile.mkdtemp(prefix="crop-tok-"))
    crops = [json.loads(l) for l in open(OUT / "crops.jsonl")]
    big = max((c for c in crops if not c.get("synthetic")), key=lambda c: c["w"] * c["h"])
    rows = []
    (work / "f0000x0000.txt").write_text("x")
    base = run(a.model, f"Read the file {work}/f0000x0000.txt and answer only: ok", str(work), str(work))
    none = run(a.model, "Answer only: ok", str(work), str(work))
    rows.append({"what": "no tool call", **none}); rows.append({"what": "Read of a 1-byte file", **base})
    print("no tool call:", none); print("Read of a 1-byte text file:", base, flush=True)
    for w, h in SIZES:
        f = work / f"f{w:04d}x{h:04d}.jpg"
        subprocess.run(["sips", "-z", str(h), str(w), big["file"], "--out", str(f)], capture_output=True, check=True)
        r = run(a.model, f"Read the file {f} and answer only: ok", str(work), str(work))
        img = (r["total_in"] - base["total_in"])                # the image sits in one request only (turn 2)
        rows.append({"what": f"{w}x{h}", "px": w * h, "image_tokens": img, "rule_750": round(w * h / 750), **r})
        print(f"{w}x{h}: image ≈ {img} tokens (w·h/750 = {w*h/750:.0f}); wall {r['ms']} ms", flush=True)
    # text: OCR lines of all his crops, concatenated, cut at n characters
    text = ""
    for l in open(OUT / "ocr.jsonl"):
        r = json.loads(l)
        if r["config"] == "accurate":
            text += "\n".join(x["t"] for x in r["lines"]) + "\n"
    for n in (0, 1000, 4000):
        r = run(a.model, "Answer only: ok. Ignore the text below.\n<text>\n" + text[:n] + "\n</text>", str(work), str(work))
        rows.append({"what": f"text {n} chars", "chars": n, **r})
        print(f"text {n} chars: total_in {r['total_in']}", flush=True)
    t0 = next(r for r in rows if r["what"] == "text 0 chars")["total_in"]
    for r in rows:
        if r.get("chars"):
            print(f"  {r['chars']} chars of his OCR text = {r['total_in'] - t0} tokens → {r['chars']/(r['total_in']-t0):.2f} chars/token")
    with open(OUT / f"tokens-{a.model}.json", "w") as f:
        json.dump(rows, f, indent=1)


if __name__ == "__main__":
    main()
