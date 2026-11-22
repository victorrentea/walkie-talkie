#!/usr/bin/python3
"""Guest only: a stand-in for `claude -p` speaking the stream-json Walkie's QuickAsk.Worker expects.

NOT a model. The lab guest has no logged-in Claude, so the ⚡ quick question, its 🔎 web check and 🧐 review,
and the ✍️ dictation redactor would have nothing to talk to. This script plays their far end with scripted
text, so the REAL Walkie UI (left edge, reply pop-up and its phases, the chip's Redacting row) can be filmed.
Which role it plays is read from --system-prompt, exactly as the app sets it. Every answer below is made up
; the quick-question answers state only what was verified about Netflix/Hystrix.
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


ANSWER = "No. Hystrix is in maintenance mode; Netflix stopped active development in 2018."
# Only what the coordinator verified on 2026-11-22: the README's status line, the last release, Netflix's advice.
WEB = ('No. Hystrix is in maintenance mode [1: "Hystrix is no longer in active development, and is currently in maintenance mode"]; '
       'the last release is 1.5.18, from November 2018 [1: "1.5.18"].\n'
       "[1] https://github.com/Netflix/Hystrix\nCHANGED")
REVIEW = ('No. Hystrix has been in maintenance mode since 2018 (last release 1.5.18) '
          '[1: "Hystrix is no longer in active development, and is currently in maintenance mode"]. '
          'Netflix recommends resilience4j for new projects [2: "resilience4j"].\n'
          "[1] https://github.com/Netflix/Hystrix\n[2] https://github.com/resilience4j/resilience4j\nCHANGED")

for line in sys.stdin:
    try: msg = json.loads(line)
    except ValueError: continue
    if msg.get("type") != "user": continue
    said = text_of(msg["message"]["content"])
    if role == "editor":
        m = re.search(r"<dictation>(.*?)</dictation>", said, re.S)
        t = (m.group(1) if m else said).strip()
        open(__import__("os").path.expanduser("~/film/redactor.log"), "a").write("heard: " + t + "\n")   # what the recogniser wrote, before any correction (for the editor)
        t = re.sub(r",\s*(um+|uh+|erm?)\s*,", ",", t, flags=re.I)             # the fillers go
        t = re.sub(r"\b(um+|uh+|erm?)\b[,.]?\s*", "", t, flags=re.I)
        t = re.sub(r"\bso,\s", "so ", t); t = re.sub(r"\s{2,}", " ", t).strip()
        # the learned vocabulary the app sends along (<replacements>: heard → written), as the real redactor uses it
        for block in re.findall(r"<replacements>(.*?)</replacements>", said, re.S):
            for heard, written in re.findall(r"^\s*(.+?)\s*(?:→|->)\s*(.+?)\s*$", block, re.M):
                t = re.sub(re.escape(heard), written, t, flags=re.I)
        t = re.sub(r"\bresilience[\s-]*(for|four|4)[\s-]*(jay|gee|j|g)\b", "Resilience4j", t, flags=re.I)   # however Whisper spelled it
        t = re.sub(r"\b(is|are|was),\s", r"\1 ", t)
        time.sleep(1.6)
        stream(t, 0.2)
    elif role == "web":
        time.sleep(0.8)
        q = "Hystrix maintained status"
        out({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebSearch", "input": {"query": q}}]}})
        time.sleep(1.6)
        out({"type": "user", "tool_use_result": {"query": q, "results": [{"content": [
            {"url": "https://github.com/Netflix/Hystrix"}, {"url": "https://github.com/resilience4j/resilience4j"}]}]}})
        time.sleep(1.8)
        stream(WEB, 1.2)
    elif role in ("review", "merge"):
        time.sleep(0.8)
        out({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "WebFetch",
                                                            "input": {"url": "https://github.com/Netflix/Hystrix"}}]}})
        time.sleep(3.2)
        stream(REVIEW, 1.2)
    else:
        time.sleep(0.7)
        stream(ANSWER, 1.3)
