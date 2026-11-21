"""Blind judge: Opus sees the context frame, the raw recognition and the two edits in random order.
usage: judge.py out/cases.jsonl out/edits.jsonl out/judged.jsonl [workers]
       LEFT=file:key RIGHT=file:key judge.py … compares any two arms (default: edits A vs B)"""
import base64, json, os, random, subprocess, sys, threading
cases = {json.loads(l)["id"]: json.loads(l) for l in open(sys.argv[1])}
def arm(spec, default_key):
    f, k = (spec.split(":") + [default_key])[:2] if spec else (sys.argv[2], default_key)
    return {json.loads(l)["id"]: json.loads(l)[k] for l in open(f)}
L, R = arm(os.environ.get("LEFT"), "A"), arm(os.environ.get("RIGHT"), "B")
edits = [{"id": i, "A": L[i], "B": R[i]} for i in L if i in R]
workers = int(sys.argv[4]) if len(sys.argv) > 4 else 6
env = {k: v for k, v in os.environ.items() if not (k.startswith("CLAUDE_CODE_") or k == "CLAUDECODE")}
ASK = """A speech recogniser wrote RAW from Victor's voice (Romanian and/or English, a software trainer).
Two editors cleaned it; the picture is his screen when he spoke. Judge each edit against what he most
likely SAID and MEANT (the screen helps you tell what he meant; it is not something he said).
For each edit count: fixes = recognition errors it corrected (misheard word/name/identifier, also fillers or
false starts removed correctly); harms = changes that make it wrong (a correct word replaced, meaning changed,
words copied from the screen that he did not say, translation, a fix to the wrong word). Punctuation alone is neutral.
RAW: <<<{raw}>>>
EDIT 1: <<<{e1}>>>
EDIT 2: <<<{e2}>>>
Answer with one JSON object only: {{"e1": {{"fixes": n, "harms": n, "notes": "..."}}, "e2": {{"fixes": n, "harms": n, "notes": "..."}}, "better": "1"|"2"|"same"}}"""
out, lock = open(sys.argv[3], "w"), threading.Lock()
random.seed(11)
jobs = [(e, random.random() < 0.5) for e in edits]
def judge(e, flip):
    c = cases[e["id"]]
    e1, e2 = (e["B"], e["A"]) if flip else (e["A"], e["B"])
    ask = ASK.format(raw=c["words"], e1=e1, e2=e2)
    if c.get("pre"):  # no picture: the talk before the dictation is the context
        ask = ask.replace("the picture is his screen when he spoke", "PRIOR is what the room microphone transcribed in the minutes before (imperfect)")
        ask = ask.replace("the screen helps you", "PRIOR helps you").replace("from the screen", "from PRIOR")
        ask = ask.replace("RAW: <<<", "PRIOR: <<<" + c["pre"] + ">>>\nRAW: <<<", 1)
    content = ([{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                "data": base64.b64encode(open(c["shot"], "rb").read()).decode()}}] if c.get("shot") else []) + \
              [{"type": "text", "text": ask}]
    p = subprocess.run([os.path.expanduser("~/.local/bin/claude"), "-p", "--model", "opus", "--input-format", "stream-json",
        "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
        "--setting-sources", ""], input=json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n",
        capture_output=True, text=True, env=env, cwd=os.path.expanduser("~/.walkie-talkie/quick"), timeout=300)
    res = ""
    for line in p.stdout.splitlines():
        try: ev = json.loads(line)
        except Exception: continue
        if ev.get("type") == "result": res = ev.get("result") or ""
    try:
        j = json.loads(res[res.index("{"): res.rindex("}") + 1])
        A, Bv = (j["e2"], j["e1"]) if flip else (j["e1"], j["e2"])
        better = {"1": "B" if flip else "A", "2": "A" if flip else "B"}.get(str(j.get("better")), "same")
        row = {"id": e["id"], "A": A, "B": Bv, "better": better}
    except Exception as ex:
        row = {"id": e["id"], "error": str(ex), "raw": res[:300]}
    with lock: out.write(json.dumps(row, ensure_ascii=False) + "\n"); out.flush()
def work(chunk):
    for e, f in chunk: judge(e, f)
ts = [threading.Thread(target=work, args=(jobs[i::workers],)) for i in range(workers)]
[t.start() for t in ts]; [t.join() for t in ts]
print("judged", len(jobs))
