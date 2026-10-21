#!/usr/bin/env python3
"""A fake `helpers/whisper_helper.py` for the desk's chunk tests (`cases_chunks.py`, 2026-10-22).

Speaks the real helper's protocol byte for byte — one JSON object per line each way, the hello line
first — so the installed app can be driven deterministically while it chunks a take
(`LocalWhisperSource`, 2026-10-21). The app runs it instead of the model when `WT_WHISPER_HELPER`
names this file (env, or a line in `~/.walkie-talkie/elevenlabs.env`, read at every spawn; the
harness writes it and asks `POST /test/whisper {"restart": true}`).

    →  {"wav": path, "words"?, "language"?}          a whole take (or Recover, the local fallback)
    →  {"pcm": path, "words"?, "language"?}          a chunk cut while he speaks; with `language`: the tail
    →  {"pcm": path, "segments": true}               the live caption's window (its own helper process)
    ←  {"ok": true, "text", "language", "avg_logprob", "compression_ratio", "no_speech_prob",
        "coverage", "words"? (only when asked), "segments"? (only when asked), "decode_s", "memory"}
    ←  {"ok": false, "error"}
    ←  {"ready": true, "model": "fake-whisper …", "memory"}      once, at start

**The text says which audio it decoded.** `r<n> <kind> <seconds>s <md5[:6]>` — `n` the request's
number in this epoch (sentence requests only, across helper restarts), `kind` `wav`｜`chunk`｜`tail`,
the audio's length and the hash of its samples. A take assembled from chunks is delivered as the
chunk answers joined by spaces, so a case can read the order, the lengths and which audio went where
straight off the delivered words. Asked for words: one per token, Whisper's leading space kept, spread
over the audio (they spell the text, as `LocalWhisper.Result.timedWords` demands).

**Behaviour: `~/.walkie-talkie/fake-whisper.json`, re-read at every request** (`WT_FAKE_WHISPER_CONTROL`
moves it). All optional:

    epoch          a string; every log line carries it, `n` counts within it (a case sets a fresh one)
    model          the hello's model name (default "fake-whisper")
    helloDelay     seconds before the hello · helloFail: true｜"why" → {"ready": false} and exit 1
    language       answered language (default "en") · delay / perSecond: seconds per request, fixed + × audio s
    live           {"delay", "perSecond", "fail", "die"} for the live caption's windows (default 0.05 s)
    rules          [ {match…, action…}, … ] — every rule that matches merges in, in order:
        match:  n (int｜[int]) · kind ("wav"｜"chunk"｜"tail"｜"pcm" = chunk or tail) · nth (int｜[int],
                the Nth request of that kind in this epoch) · words (bool) · minSeconds / maxSeconds
        action: delay · perSecond · fail (true｜"why" → ok:false) · empty (text "") · text (override) ·
                hang (true｜seconds: never answers — the app's 300 s budget kills it, or /test/whisper kill) ·
                die (exit code; after the delay, without answering) · language · logprob · cr

**Every request is logged** to `~/.walkie-talkie/fake-whisper.jsonl` (`WT_FAKE_WHISPER_LOG`), under an
`flock`, one `request` line at arrival and one `answer`｜`die`｜`hang` line after:
`{event, t (epoch s), at (ISO), pid, epoch, n, nth, kind, path, exists, seconds, words, language,
segments, md5, rules, action, text, decode_s}`; plus a `hello` line per process.

    python3 evals/plan/fake_whisper_helper.py --selftest     # pipes requests into a copy of itself

Python 3.9-compatible (the lab guest's /usr/bin/python3), stdlib only. Importable: `arm()`, `reset()`,
`requests()`, `answers()` are what the cases use."""
import datetime
import fcntl
import hashlib
import json
import os
import sys
import time
import wave

HOME = os.path.expanduser("~/.walkie-talkie")
CONTROL = os.environ.get("WT_FAKE_WHISPER_CONTROL") or os.path.join(HOME, "fake-whisper.json")
LOG = os.environ.get("WT_FAKE_WHISPER_LOG") or os.path.join(HOME, "fake-whisper.jsonl")
RATE = 16000


# ---------------------------------------------------------------- the harness's side (importable)
def arm(**control):
    """A fresh epoch with this behaviour; the log emptied. Returns the epoch."""
    control.setdefault("epoch", "e%d" % int(time.time() * 1000))
    _write_json(CONTROL, control)
    with open(LOG, "w"):
        pass
    return control["epoch"]


def reset():
    """No rules, a fresh epoch — what every case leaves behind."""
    return arm()


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


def log_lines(epoch=None):
    try:
        with open(LOG, encoding="utf-8") as f:
            rows = [json.loads(l) for l in f if l.strip()]
    except (OSError, ValueError):
        return []
    return [r for r in rows if epoch is None or r.get("epoch") == epoch]


def requests(epoch=None, live=False):
    """The `request` lines of this epoch, in arrival order; the live caption's only with `live`."""
    return [r for r in log_lines(epoch) if r.get("event") == "request" and (live or r.get("kind") != "live")]


def answers(epoch=None, live=False):
    return [r for r in log_lines(epoch) if r.get("event") in ("answer", "die", "hang")
            and (live or r.get("kind") != "live")]


# ---------------------------------------------------------------- the helper
def _now():
    t = time.time()
    return t, datetime.datetime.fromtimestamp(t).isoformat(timespec="milliseconds")


def _control():
    try:
        with open(CONTROL, encoding="utf-8") as f:
            c = json.load(f)
        return c if isinstance(c, dict) else {}
    except (OSError, ValueError):
        return {}


def _emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _audio(path, pcm):
    """(seconds, md5 of the samples) — read at arrival, as the real helper loads it."""
    if pcm:
        with open(path, "rb") as f:
            data = f.read()
        return len(data) / (2.0 * RATE), hashlib.md5(data).hexdigest()
    try:
        w = wave.open(path)
        frames = w.readframes(w.getnframes())
        secs = w.getnframes() / float(w.getframerate() or RATE)
        w.close()
        return secs, hashlib.md5(frames).hexdigest()
    except Exception:  # noqa: BLE001 — not a PCM WAV: the bytes still say which file it was
        with open(path, "rb") as f:
            data = f.read()
        return max(0, len(data) - 44) / (2.0 * RATE), hashlib.md5(data).hexdigest()


def _log(entry, count=False):
    """Append one line under an exclusive lock. With `count`: first number this request within its
    epoch (sentence requests across every helper process; per kind for `nth`)."""
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            if count:
                f.seek(0)
                n = nth = 0
                for line in f:
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    if r.get("event") != "request" or r.get("epoch") != entry.get("epoch"):
                        continue
                    if r.get("kind") != "live":
                        n += 1
                    if r.get("kind") == entry["kind"]:
                        nth += 1
                entry["n"] = None if entry["kind"] == "live" else n + 1
                entry["nth"] = nth + 1
            f.seek(0, os.SEEK_END)
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            f.flush()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
    return entry


def _one_of(want, got):
    return got in want if isinstance(want, list) else got == want


def _matches(rule, req):
    if "n" in rule and (req["n"] is None or not _one_of(rule["n"], req["n"])):
        return False
    if "kind" in rule:
        k = rule["kind"]
        if not (k == req["kind"] or (k == "pcm" and req["kind"] in ("chunk", "tail"))):
            return False
    if "nth" in rule and not _one_of(rule["nth"], req["nth"]):
        return False
    if "words" in rule and bool(rule["words"]) != bool(req["words"]):
        return False
    if "minSeconds" in rule and req["seconds"] < float(rule["minSeconds"]):
        return False
    if "maxSeconds" in rule and req["seconds"] > float(rule["maxSeconds"]):
        return False
    return True


def _words(text, seconds):
    toks = text.split()
    if not toks:
        return []
    lo, hi = min(0.1, seconds / 4), max(0.0, seconds - min(0.1, seconds / 4))
    step = (hi - lo) / len(toks) if hi > lo else 0.0
    return [{"text": " " + t, "start": round(lo + i * step, 3), "end": round(lo + (i + 0.8) * step, 3)}
            for i, t in enumerate(toks)]


def _sleep(seconds):
    end = time.time() + max(0.0, seconds)
    while True:
        left = end - time.time()
        if left <= 0:
            return
        time.sleep(min(0.2, left))


def _answer(line):
    c = _control()
    epoch = c.get("epoch")
    req = json.loads(line)
    path = req.get("pcm") or req.get("wav")
    pcm = bool(req.get("pcm"))
    segments = bool(req.get("segments"))
    kind = "live" if segments else ("wav" if not pcm else ("tail" if req.get("language") else "chunk"))
    exists = bool(path) and os.path.exists(path)
    seconds, md5 = (0.0, None)
    if exists:
        try:
            seconds, md5 = _audio(path, pcm)
        except OSError:
            exists = False
    t, at = _now()
    entry = _log({"event": "request", "t": round(t, 3), "at": at, "pid": os.getpid(), "epoch": epoch,
                  "kind": kind, "path": path, "exists": exists, "seconds": round(seconds, 3),
                  "words": bool(req.get("words")), "language": req.get("language"), "segments": segments,
                  "md5": md5}, count=True)
    if not exists:
        _log(dict(entry, event="answer", t=round(time.time(), 3), action="missing"))
        return _emit({"ok": False, "error": "no such file: %s" % path})

    if kind == "live":
        act = dict({"delay": 0.05, "perSecond": 0.0}, **(c.get("live") or {}))
        fired = []
    else:
        act = {"delay": float(c.get("delay", 0.2)), "perSecond": float(c.get("perSecond", 0.02))}
        fired = []
        for i, rule in enumerate(c.get("rules") or []):
            if isinstance(rule, dict) and _matches(rule, entry):
                fired.append(i)
                act.update({k: v for k, v in rule.items()
                            if k not in ("n", "kind", "nth", "words", "minSeconds", "maxSeconds")})
    t0 = time.monotonic()
    _sleep(float(act.get("delay") or 0) + float(act.get("perSecond") or 0) * seconds)
    base = dict(entry, rules=fired)
    if act.get("die") is not None and act.get("die") is not False:
        code = 1 if act["die"] is True else int(act["die"])
        _log(dict(base, event="die", t=round(time.time(), 3), action="die", code=code))
        sys.stdout.flush()
        os._exit(code)
    if act.get("hang"):
        _log(dict(base, event="hang", t=round(time.time(), 3), action="hang"))
        _sleep(3600 if act["hang"] is True else float(act["hang"]))
    if act.get("fail"):
        why = act["fail"] if isinstance(act["fail"], str) else "fake failure (rule %s)" % fired
        _log(dict(base, event="answer", t=round(time.time(), 3), action="fail", error=why))
        return _emit({"ok": False, "error": why})
    if "text" in act:
        text = str(act["text"])
    elif act.get("empty"):
        text = ""
    elif kind == "live":
        text = "live %.2fs %s" % (seconds, md5[:6])
    else:
        text = "r%d %s %.2fs %s" % (entry["n"], kind, seconds, md5[:6])
    language = act.get("language") or req.get("language") or c.get("language") or "en"
    decode_s = time.monotonic() - t0
    out = {
        "ok": True, "text": text, "language": language,
        "avg_logprob": float(act.get("logprob", -0.2)), "compression_ratio": float(act.get("cr", 1.3)),
        "no_speech_prob": 0.01,
        "coverage": {"segments": 1 if text else 0, "duration": round(seconds, 2),
                     "covered": round(seconds, 2) if text else 0.0, "gap": 0.0, "gap_at": 0.0,
                     "temperature": 0.0, "retried": False, "cut": 0},
        "decode_s": round(decode_s, 3),
        "memory": {"active_mb": 0.0, "cache_mb": 0.0, "peak_mb": 0.0, "cache_limit_mb": 0},
    }
    if req.get("words"):
        out["words"] = _words(text, seconds)
    if segments:
        out["segments"] = [{"text": " " + text, "start": 0.0, "end": round(seconds, 3)}] if text else []
    _log(dict(base, event="answer", t=round(time.time(), 3), action="empty" if not text else "ok",
              text=text, decode_s=round(decode_s, 3)))
    _emit(out)


REAL_HELPER = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                           "helpers", "whisper_helper.py")
LOCK = os.path.join(HOME, "wispr-loop.lock")   # the one runner lock (harness.take_lock)


def harness_alive():
    """**Only while a harness run holds the runner lock** — a `WT_WHISPER_HELPER` line left behind
    by a crashed run must never put fake words into one of Victor's own sentences.
    `WT_FAKE_WHISPER_FORCE=1` (the self-test) skips the check."""
    if os.environ.get("WT_FAKE_WHISPER_FORCE") == "1":
        return True
    try:
        with open(LOCK) as f:
            pid = int(f.read().split()[0])
        os.kill(pid, 0)
        return True
    except (OSError, ValueError, IndexError):
        return False


def serve():
    if not harness_alive():
        # Spawned with no run behind it: be the real model instead (same interpreter — the app
        # picked one that has mlx_whisper), or say so loudly.
        sys.stderr.write("fake whisper helper: no harness run holds %s — running the real helper\n" % LOCK)
        sys.stderr.flush()
        if os.path.exists(REAL_HELPER):
            os.execv(sys.executable, [sys.executable, REAL_HELPER])
        _emit({"ready": False, "error": "WT_WHISPER_HELPER points at the fake and no harness run is live"})
        sys.exit(1)
    c = _control()
    _sleep(float(c.get("helloDelay") or 0))
    t, at = _now()
    _log({"event": "hello", "t": round(t, 3), "at": at, "pid": os.getpid(), "epoch": c.get("epoch"),
          "kind": "hello", "fail": c.get("helloFail")})
    if c.get("helloFail"):
        why = c["helloFail"] if isinstance(c["helloFail"], str) else "fake warm-up failure"
        _emit({"ready": False, "error": "warm-up failed: %s" % why})
        sys.exit(1)
    _emit({"ready": True, "model": "%s (evals/plan/fake_whisper_helper.py)" % c.get("model", "fake-whisper"),
           "memory": {"active_mb": 0.0, "cache_mb": 0.0, "peak_mb": 0.0, "cache_limit_mb": 0}})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if not harness_alive():
            # The run ended (or crashed) with this process still up: answer nothing fake. Dying is
            # what the app already handles — it brings a helper up again, which execs the real one.
            _emit({"ok": False, "error": "the fake whisper helper outlived its harness run — exiting"})
            sys.exit(1)
        try:
            _answer(line)
        except Exception as e:  # noqa: BLE001 — one bad request must not kill the daemon (the real one's rule)
            _emit({"ok": False, "error": "fake helper: %s: %s" % (type(e).__name__, e)})


# ---------------------------------------------------------------- self-test
def selftest():
    """A copy of this file as a subprocess, its control and log in a temp folder; requests piped
    in the app's own shapes; every answer and log line checked."""
    import struct
    import subprocess
    import tempfile
    tmp = tempfile.mkdtemp(prefix="fake-whisper-")
    env = dict(os.environ, WT_FAKE_WHISPER_CONTROL=os.path.join(tmp, "c.json"),
               WT_FAKE_WHISPER_LOG=os.path.join(tmp, "l.jsonl"), WT_FAKE_WHISPER_FORCE="1")
    global CONTROL, LOG
    CONTROL, LOG = env["WT_FAKE_WHISPER_CONTROL"], env["WT_FAKE_WHISPER_LOG"]

    def pcm_file(name, seconds, seed):
        p = os.path.join(tmp, name)
        with open(p, "wb") as f:
            f.write(b"".join(struct.pack("<h", (i * seed) % 2000 - 1000) for i in range(int(RATE * seconds))))
        return p

    def wav_file(name, seconds):
        p = os.path.join(tmp, name)
        w = wave.open(p, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"\x01\x00" * int(RATE * seconds)); w.close()
        return p

    c1, c2, tl, whole = pcm_file("c1.pcm", 9.5, 7), pcm_file("c2.pcm", 8.25, 11), pcm_file("t.pcm", 3.0, 13), \
        wav_file("w.wav", 20.75)
    failures = []

    def check(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            failures.append(what)

    def start():
        return subprocess.Popen([sys.executable, os.path.abspath(__file__)], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    def ask(p, obj, timeout=10):
        p.stdin.write(json.dumps(obj) + "\n"); p.stdin.flush()
        line = p.stdout.readline()
        return json.loads(line) if line else None

    epoch = arm(delay=0.0, perSecond=0.0, language="ro",
                rules=[{"n": 3, "delay": 0.4}, {"kind": "chunk", "nth": 2, "words": True, "text": "two words"},
                       {"n": 5, "fail": "boom"}, {"n": 6, "empty": True}, {"n": 8, "die": 3}])
    p = start()
    hello = json.loads(p.stdout.readline())
    check(hello.get("ready") is True and "fake-whisper" in hello.get("model", ""), "hello: %s" % hello)

    a1 = ask(p, {"pcm": c1, "words": False})
    check(a1["ok"] and a1["text"].startswith("r1 chunk 9.50s ") and "words" not in a1 and a1["language"] == "ro",
          "chunk 1, no words: %r" % a1["text"])
    a2 = ask(p, {"pcm": c2, "words": True})
    check(a2["text"] == "two words" and [w["text"] for w in a2["words"]] == [" two", " words"]
          and "".join(w["text"] for w in a2["words"]).strip() == a2["text"]
          and all(0 <= w["start"] <= w["end"] <= 8.25 for w in a2["words"]), "chunk 2 with words (rule nth 2)")
    t0 = time.time()
    a3 = ask(p, {"pcm": tl, "words": False, "language": "en"})
    check(a3["text"].startswith("r3 tail 3.00s ") and a3["language"] == "en" and time.time() - t0 >= 0.35,
          "the tail: language kept, 0.4 s delay (rule n 3): %r" % a3["text"])
    a4 = ask(p, {"wav": whole, "words": True})
    check(a4["text"].startswith("r4 wav 20.75s ") and "".join(w["text"] for w in a4["words"]).strip() == a4["text"],
          "a whole WAV with words: %r" % a4["text"])
    a5 = ask(p, {"wav": whole})
    check(a5 == {"ok": False, "error": "boom"}, "fail (rule n 5): %s" % a5)
    a6 = ask(p, {"pcm": c1})
    check(a6["ok"] and a6["text"] == "", "empty (rule n 6)")
    a7 = ask(p, {"pcm": os.path.join(tmp, "gone.pcm")})
    check(a7 == {"ok": False, "error": "no such file: %s" % os.path.join(tmp, "gone.pcm")}, "missing file")
    live = ask(p, {"pcm": c1, "segments": True})
    check(live["ok"] and live["segments"] and live["segments"][0]["end"] == 9.5, "a live window (segments)")
    a8 = ask(p, {"pcm": c2})
    p.wait(5)
    check(a8 is None and p.returncode == 3, "die (rule n 8): no answer, exit %s" % p.returncode)

    # The next process goes on counting — the death does not repeat.
    p = start()
    json.loads(p.stdout.readline())
    a9 = ask(p, {"pcm": c2})
    check(a9["ok"] and a9["text"].startswith("r9 chunk "), "a restarted helper continues at r9: %r" % a9["text"])
    p.stdin.close(); p.wait(5)

    reqs, ans = requests(epoch), answers(epoch)
    check([r["n"] for r in reqs] == list(range(1, 10)), "requests numbered 1..9: %s" % [r["n"] for r in reqs])
    check([r["kind"] for r in reqs] == ["chunk", "chunk", "tail", "wav", "wav", "chunk", "chunk", "chunk", "chunk"],
          "kinds: %s" % [r["kind"] for r in reqs])
    check(len(requests(epoch, live=True)) == 10, "the live window logged apart")
    check([a["action"] for a in ans] == ["ok", "ok", "ok", "ok", "fail", "empty", "missing", "die", "ok"],
          "actions: %s" % [a["action"] for a in ans])
    check(len({r["pid"] for r in reqs}) == 2, "two helper pids in the log")

    _write_json(CONTROL, {"epoch": "slow", "helloDelay": 0.5, "helloFail": "no weights"})
    t0 = time.time()
    p = start()
    bad = json.loads(p.stdout.readline())
    p.wait(5)
    check(bad == {"ready": False, "error": "warm-up failed: no weights"} and p.returncode == 1
          and time.time() - t0 >= 0.45, "slow hello, then a failed warm-up: %s" % bad)

    # No harness run behind it and no force: it must not answer as the fake. (The real helper's
    # hello would take the model's load time, so only the refusal path is checked here: the
    # real helper is pointed at a path that does not exist.)
    env_nolock = dict(env, WT_FAKE_WHISPER_FORCE="0", HOME=tmp)
    p = subprocess.Popen([sys.executable, "-c",
                          "import sys; sys.argv=['x']; sys.path.insert(0, %r); import fake_whisper_helper as F; "
                          "F.REAL_HELPER='/nonexistent'; F.LOCK=%r; F.serve()"
                          % (os.path.dirname(os.path.abspath(__file__)), os.path.join(tmp, "no.lock"))],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         env=env_nolock)
    out, err = p.communicate(timeout=10)
    check(p.returncode == 1 and '"ready": false' in out and "no harness run" in err,
          "no harness lock → never the fake (exit %s): %s" % (p.returncode, out.strip()))

    print("selftest: %d failure(s)" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    serve()
