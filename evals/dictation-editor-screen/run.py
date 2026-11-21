"""Haiku edits each case twice in kept sessions, as DictationEditor does: A = no picture, B = + the
context frame (800 px). Same system prompt and message shape as DictationEditor.swift; the
Accessibility context (text around the caret, names) cannot be rebuilt for old prompts, so neither
arm has it — B measures what the picture adds over the vocabulary alone.
usage: [MODEL=haiku EFFORT=] run.py out/cases.jsonl out/edits.jsonl [workers]"""
import base64, json, os, re, subprocess, sys, threading, time
B = os.path.dirname(os.path.abspath(__file__))
SYSTEM = open(f"{B}/system.txt").read().strip()
SCREEN_RULE = ("\n- <screen> is a picture of the screen the words land on: use it like the other context tags — "
               "only to spell names and identifiers that sound like what was said; never copy words, phrases or "
               "meaning from it that were not spoken in <dictation>.")
HOME = os.path.expanduser("~/.walkie-talkie")
lines = [l.strip() for l in open(f"{HOME}/vocabulary.txt") if l.strip() and not l.startswith("#")]
TERMS = [l for l in lines if "→" not in l]
PAIRS = [tuple(x.strip() for x in l.split("→")) for l in lines if "→" in l]
cases = [json.loads(l) for l in open(sys.argv[1])]
workers = int(sys.argv[3]) if len(sys.argv) > 3 else 4
CTX = os.environ.get("CTX", "screen")   # the B arm's extra context: screen | pre
PRE_RULE = ("\n- <earlier_speech> is what the room microphone transcribed in the minutes before this dictation "
            "(the speaker and others, imperfectly): use it only to spell names and terms that sound like what was "
            "said; never copy words, phrases or meaning from it that were not spoken in <dictation>.")
MODEL, EFFORT = os.environ.get("MODEL", "haiku"), os.environ.get("EFFORT", "")
env = {k: v for k, v in os.environ.items() if not (k.startswith("CLAUDE_CODE_") or k == "CLAUDECODE")}

def message(c, screen):
    terms, pairs = TERMS, PAIRS
    if c.get("heard"):  # the fix under test must come from the screen, not the dictionary
        terms = [t for t in terms if t.lower() != c["written"].lower()]
        pairs = [p for p in pairs if p[0].lower() != c["heard"].lower()]
    m = "<speaker>Victor Rentea</speaker>\n"
    m += "<vocabulary>" + ", ".join(terms) + "</vocabulary>\n"
    m += "<replacements>" + "; ".join(f"{h} → {w}" for h, w in pairs) + "</replacements>\n"
    if screen and CTX == "pre":
        return m + f"<earlier_speech>{c['pre']}</earlier_speech>\n<dictation>{c['words']}</dictation>"
    if screen: m += "<screen>the attached picture</screen>\n"
    m += f"<dictation>{c['words']}</dictation>"
    if not screen: return m
    data = base64.b64encode(open(c["shot"], "rb").read()).decode()
    return [{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}},
            {"type": "text", "text": m}]

def start(system):
    return subprocess.Popen([os.path.expanduser("~/.local/bin/claude"), "-p", "--model", MODEL, *(["--effort", EFFORT] if EFFORT else []), "--input-format",
        "stream-json", "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--tools", "",
        "--strict-mcp-config", "--setting-sources", "", "--system-prompt", system], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=env, cwd=os.path.expanduser("~/.walkie-talkie/quick"))

def ask(p, content):
    t = time.time()
    p.stdin.write(json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n"); p.stdin.flush()
    for line in p.stdout:
        e = json.loads(line)
        if e.get("type") == "result":
            return (e.get("result") or "").strip(), round(time.time() - t, 3)
    return "", round(time.time() - t, 3)

out, lock = open(sys.argv[2], "w"), threading.Lock()
def work(chunk):
    pa, pb = start(SYSTEM), start(SYSTEM + (PRE_RULE if CTX == "pre" else SCREEN_RULE))
    for c in chunk:
        a, sa = ask(pa, message(c, False))
        b, sb = ask(pb, message(c, True))
        with lock:
            out.write(json.dumps({"id": c["id"], "A": a, "sA": sa, "B": b, "sB": sb}, ensure_ascii=False) + "\n"); out.flush()
    pa.terminate(); pb.terminate()
ts = [threading.Thread(target=work, args=(cases[i::workers],)) for i in range(workers)]
[t.start() for t in ts]; [t.join() for t in ts]
print("done", len(cases))
