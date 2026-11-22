#!/usr/bin/python3
"""Guest only: a stand-in for `claude -p` speaking the stream-json Walkie's QuickAsk.Worker expects.

NOT a model. The lab guest has no logged-in Claude, so the ⚡ quick question, its 🔎 web check and 🧐 review,
and the ✍️ dictation redactor would have nothing to talk to. This script plays their far end with scripted
text, so the REAL Walkie UI (left edge, reply pop-up and its phases, the chip's Redacting row) can be filmed.
Which role it plays is read from --system-prompt, exactly as the app sets it. Every answer below is made up
for the demo site's fictional library "brewkit".
"""
import json, re, sys, time

args = sys.argv[1:]
system = args[args.index("--system-prompt") + 1] if "--system-prompt" in args else ""
role = ("editor" if "dictation editor" in system else "review" if "adversarial reviewer" in system
        else "web" if "Search the web" in system else "merge" if "researchers" in system else "answer")


def out(obj): sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()


def stream(text, seconds):
    words = re.findall(r"\S+\s*", text)
    for w in words:
        out({"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": w}}})
        time.sleep(seconds / max(1, len(words)))
    out({"type": "result", "subtype": "success", "is_error": False, "result": text})


def text_of(content):
    if isinstance(content, str): return content
    return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")


ANSWER = "Probably not. brewkit's last release was in 2022, and the project has been quiet since."
WEB = ('No. brewkit was archived in March 2023 [1: "This repository has been archived by the owner"], '
       'and its authors recommend moving to brewkit-next [2: "we recommend brewkit-next for new projects"].\n'
       "[1] https://github.example/brewkit/brewkit\n[2] https://brewkit.example/blog/farewell\nCHANGED")
REVIEW = ('No. brewkit was archived in March 2023 [1: "This repository has been archived by the owner"]; '
          'brewkit-next is its maintained successor, with a release last week [2: "v4.2.0"].\n'
          "[1] https://github.example/brewkit/brewkit\n[2] https://github.example/brewkit/brewkit-next/releases\nCHANGED")

for line in sys.stdin:
    try: msg = json.loads(line)
    except ValueError: continue
    if msg.get("type") != "user": continue
    said = text_of(msg["message"]["content"])
    if role == "editor":
        m = re.search(r"<dictation>(.*?)</dictation>", said, re.S)
        t = (m.group(1) if m else said).strip()
        t = re.sub(r",\s*(um+|uh+|erm?)\s*,", ",", t, flags=re.I)             # the fillers go
        t = re.sub(r"\b(um+|uh+|erm?)\b[,.]?\s*", "", t, flags=re.I)
        t = re.sub(r"\bso,\s", "so ", t); t = re.sub(r"\s{2,}", " ", t).strip()
        time.sleep(1.6)
        stream(t, 0.2)
    elif role == "web":
        time.sleep(0.8)
        q = "brewkit library maintained archived"
        out({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebSearch", "input": {"query": q}}]}})
        time.sleep(1.6)
        out({"type": "user", "tool_use_result": {"query": q, "results": [{"content": [
            {"url": "https://github.example/brewkit/brewkit"}, {"url": "https://brewkit.example/blog/farewell"}]}]}})
        time.sleep(1.0)
        stream(WEB, 1.2)
    elif role in ("review", "merge"):
        time.sleep(0.8)
        out({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebFetch",
                                                            "input": {"url": "https://github.example/brewkit/brewkit"}}]}})
        time.sleep(2.0)
        stream(REVIEW, 1.2)
    else:
        time.sleep(0.7)
        stream(ANSWER, 1.3)
