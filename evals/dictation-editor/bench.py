"""Editor benchmark: same system prompt and message shape as DictationEditor.swift.
usage: bench.py haiku|<mlx-model-path> out.jsonl [limit]"""
import json, os, sys, time, subprocess, copy
B = os.path.dirname(os.path.abspath(__file__))
SYSTEM = open(f"{B}/system.txt").read()
rows = [json.loads(l) for l in open(f"{B}/pairs.jsonl")][: int(sys.argv[3]) if len(sys.argv) > 3 else None]

def message(r):
    m = "<speaker>Victor Rentea</speaker>\n"
    if r["vocab"]: m += "<vocabulary>" + ", ".join(r["vocab"]) + "</vocabulary>\n"
    m += f"<app>{r['app']}</app>\n"
    if r["url"]: m += f"<url>{r['url'][:200]}</url>\n"
    m += f"<before_caret>{r['before']}</before_caret>\n"
    if r["selection"]: m += f"<selection_replaced>{r['selection']}</selection_replaced>\n"
    if r["after"]: m += f"<after_caret>{r['after']}</after_caret>\n"
    if r["names"]: m += "<names>" + ", ".join(r["names"]) + "</names>\n"
    if r["files"]: m += "<files>" + ", ".join(r["files"]) + "</files>\n"
    lang = {"en": "English", "ro": "Romanian"}.get((r.get("lang") or "")[:2])
    if lang and os.environ.get("LANGHINT"): m += f"<language>{lang}</language>\n"
    return m + f"<dictation>{r['asr']}</dictation>"

out = open(sys.argv[2], "w")
which = sys.argv[1]
if which == "haiku":
    env = {k: v for k, v in os.environ.items() if not (k.startswith("CLAUDE_CODE_") or k == "CLAUDECODE")}
    def start():
        p = subprocess.Popen([os.path.expanduser("~/.local/bin/claude"), "-p", "--model", "haiku", "--input-format", "stream-json",
            "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
            "--setting-sources", "", "--system-prompt", SYSTEM], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, env=env, cwd=os.path.expanduser("~/.walkie-talkie/quick"))
        time.sleep(8); return p
    p = start(); turns = 0
    for r in rows:
        if turns == 40: p.terminate(); p = start(); turns = 0
        t = time.time()
        p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": message(r)}}) + "\n"); p.stdin.flush()
        for line in p.stdout:
            e = json.loads(line)
            if e.get("type") == "result": res = e.get("result") or ""; break
        turns += 1
        out.write(json.dumps({"id": r["id"], "out": res.strip(), "s": round(time.time() - t, 3)}, ensure_ascii=False) + "\n"); out.flush()
    p.terminate()
else:
    import mlx.core as mx
    from mlx_lm import load, generate
    from mlx_lm.models.cache import make_prompt_cache
    model, tok = load(which)
    def ids(msgs): return tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=True)
    sys_ids = tok.apply_chat_template([{"role": "system", "content": SYSTEM}], tokenize=True)
    base = make_prompt_cache(model)
    model(mx.array([sys_ids]), cache=base); mx.eval([c.state for c in base])
    generate(model, tok, prompt=ids([{"role": "system", "content": SYSTEM}, {"role": "user", "content": "<dictation>warm up</dictation>"}]), max_tokens=8)
    for r in rows:
        full = ids([{"role": "system", "content": SYSTEM}, {"role": "user", "content": message(r)}])
        assert full[: len(sys_ids)] == sys_ids
        t = time.time()
        cache = copy.deepcopy(base)
        res = generate(model, tok, prompt=full[len(sys_ids):], prompt_cache=cache,
                       max_tokens=int(len(r["asr"]) / 2.5) + 40)
        out.write(json.dumps({"id": r["id"], "out": res.strip(), "s": round(time.time() - t, 3), "prompt_tokens": len(full)}, ensure_ascii=False) + "\n"); out.flush()
