#!/usr/bin/env python3
"""The test plan's runner (docs/test-plan.md). One process drives the installed app over the
loopback routes; cases are small functions that return a verdict. Nothing here edits the app.

    evals/plan/harness.py [--only PREFIX,...] [--skip PREFIX,...] [--list] [--report PATH]

Every case leaves the relay as it found it (bind, override, faults, cancel). A case that needs a
gesture is tagged `gesture` and only runs when the process was started under `hands-off`
(HANDS_OFF=1 in the environment, which `run-gestures.sh` sets)."""
import json, os, subprocess, sys, time, urllib.request, urllib.error, datetime, traceback, re, wave, shutil

HOME = os.path.expanduser("~/.walkie-talkie")
LOG = HOME + "/relay.log"
OUTBOX = HOME + "/outbox.jsonl"
WORK = os.environ.get("WT_WORK", "/tmp/wt-plan")
os.makedirs(WORK, exist_ok=True)
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
CLIP_EN = CORPUS + "/2026-09-18/21-05-35-11l735.wav"      # 3.5 s, "If I dictate now, how good is this dictation, I wonder?"
CLIP_EN_LONG = CORPUS + "/2026-09-18/23-59-48-11l129.wav" # 157 s EN
# **Our own Loopback device** (2026-09-26): pure Pass-Thru, created from the plist
# (`~/Library/Application Support/Loopback/Devices.plist`, template `🎙️TO Zoom`, new UUIDs, then
# `open -a Loopback` once). `🎓 TO Wispr` belongs to the Wispr teacher-labelling rig and carries the
# built-in mic as a source; the two must never be confused.
# `WT_LOOPBACK` names it elsewhere: in the Tart lab (docs/vm-lab.md) there is no Loopback app.
LOOPBACK = os.environ.get("WT_LOOPBACK", "🧪 WT Inject")
LOCK_PATH = HOME + "/wispr-loop.lock"   # the one runner lock on this Mac (helpers/wispr_loop.py)


# ---------------------------------------------------------------- transport
def _port():
    for p in (8917, 8918, 8919):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{p}/up", timeout=2) as r:
                if json.load(r).get("ok"):
                    return p
        except Exception:
            pass
    raise SystemExit("no relay on 8917-8919")

PORT = _port()
B = f"http://127.0.0.1:{PORT}"

def get(path, timeout=6):
    with urllib.request.urlopen(B + path, timeout=timeout) as r:
        return json.load(r)

def post(path, body=None, timeout=25):
    data = json.dumps(body if body is not None else {}).encode()
    req = urllib.request.Request(B + path, data, {"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.load(e)
        except Exception:
            return e.code, {}

def state():
    return get("/test/state")

def engine():
    return get("/engine")

def lc():
    return state()["liveCaption"]

def caption(text, partial="", gentle=False):
    post("/test/live-caption", {"text": text, "partial": partial, "gentle": gentle})

def caption_off():
    post("/test/live-caption", {"on": False})


# ---------------------------------------------------------------- log / outbox
def log_mark():
    return os.path.getsize(LOG)

def log_since(mark):
    with open(LOG, "rb") as f:
        f.seek(mark)
        return f.read().decode("utf-8", "replace")

def log_has(mark, pattern):
    return re.search(pattern, log_since(mark)) is not None

def outbox_tail(n=1):
    with open(OUTBOX, "rb") as f:
        lines = f.read().decode("utf-8", "replace").strip().split("\n")
    return [json.loads(l) for l in lines[-n:] if l.strip()]

def outbox_count():
    with open(OUTBOX, "rb") as f:
        return f.read().count(b"\n")

def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


# ---------------------------------------------------------------- waiting
def wait_for(cond, timeout=30, step=0.1, what="condition"):
    end = time.time() + timeout
    while time.time() < end:
        try:
            v = cond()
            if v:
                return v
        except Exception:
            pass
        time.sleep(step)
    return None

def wait_idle(timeout=600):
    """Victor may be dictating: never start a case over his sentence."""
    paused_since = [None]
    def idle():
        s = state()
        if not s["busy"]:
            return True
        # A prompt paused by a pointer that never moves (a huge panel unfolding under it) never
        # resolves on its own: give up after 20 s instead of 600 (no HTTP route dismisses it).
        if any("Paused" in str(r) for r in s.get("chip") or []):
            paused_since[0] = paused_since[0] or time.time()
            if time.time() - paused_since[0] > 20:
                raise SystemExit("PAUSED")
        else:
            paused_since[0] = None
        return False
    try:
        ok = wait_for(idle, timeout, 0.5, "relay idle")
    except SystemExit:
        raise RuntimeError("prompt panel paused by the pointer for 20 s (autosend held) — needs ⎋ by hand")
    if not ok:
        raise RuntimeError("relay busy for %ds: %s" % (timeout, state()["busyWhy"]))

def sample(seconds, hz=20, fn=lc):
    out, t0 = [], time.time()
    while time.time() - t0 < seconds:
        s = fn(); s["t"] = round(time.time() - t0, 3); out.append(s)
        time.sleep(1.0 / hz)
    return out


# ---------------------------------------------------------------- the witness tab
WITNESS = {"tty": None, "file": WORK + "/witness.txt"}

def osa(*lines):
    cmd = ["osascript"]
    for l in lines:
        cmd += ["-e", l]
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()

def witness_open(name="wt-witness"):
    """A Terminal tab running `cat` into a file: a non-shell foreground the guard lets through."""
    if WITNESS["tty"]:
        return WITNESS["tty"]
    open(WITNESS["file"], "w").close()
    script = f"printf '\\\\e]0;{name}\\\\a'; stty -echo; exec cat >> {WITNESS['file']}"
    tty = osa(f'tell application "Terminal" to set t to do script "{script}"',
              'tell application "Terminal" to get tty of t')
    WITNESS["tty"] = tty.replace("/dev/", "")
    time.sleep(0.8)
    return WITNESS["tty"]

def witness_text():
    try:
        return open(WITNESS["file"], encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return ""

def witness_clear():
    open(WITNESS["file"], "w").close()

def witness_close():
    """Kill the tab's `cat` first: a window with a running process makes Terminal ask
    "terminate?" and the close silently does nothing (18 orphan windows on 2026-09-26)."""
    if WITNESS["tty"]:
        subprocess.run(["pkill", "-t", WITNESS["tty"]], capture_output=True)
        time.sleep(0.3)
        osa('tell application "Terminal" to close (every window whose name contains "wt-witness") saving no')
        WITNESS["tty"] = None

def bind_witness():
    tty = witness_open()
    code, r = post("/bind", {"tty": tty})
    return r

def unbind():
    post("/unbind")


# ---------------------------------------------------------------- audio through the Loopback
def loopback_alive():
    import numpy as np, sounddevice as sd
    idx = [i for i, d in enumerate(sd.query_devices()) if LOOPBACK.lower() in d["name"].lower()][0]
    sr = 48000; t = np.arange(int(sr * 1.5)) / sr
    tone = (0.3 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
    rec = sd.playrec(np.repeat(tone[:, None], 2, 1), sr, channels=2, device=(idx, idx), blocking=True)[:, 0]
    spec = np.abs(np.fft.rfft(rec * np.hanning(len(rec)))) ** 2; f = np.fft.rfftfreq(len(rec), 1 / sr)
    share = spec[(f > 430) & (f < 450)].sum() / max(1e-9, spec[(f > 80) & (f < 8000)].sum())
    return share > 0.2

def play(wav, peak=0.5, lead=0.5, tail=0.5, seconds=None):
    """Play a 16 kHz mono WAV into the Loopback device, blocking. Silent for the room."""
    import numpy as np, sounddevice as sd
    from scipy.signal import resample_poly
    idx = [i for i, d in enumerate(sd.query_devices()) if LOOPBACK.lower() in d["name"].lower()][0]
    w = wave.open(wav); a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
    sr = w.getframerate()
    if seconds:
        a = a[: int(sr * seconds)]
    a = resample_poly(a, 48000, sr)
    if peak:
        a = a / max(1e-6, np.abs(a).max()) * peak
    a = np.concatenate([np.zeros(int(48000 * lead), np.float32), a.astype(np.float32), np.zeros(int(48000 * tail), np.float32)])
    sd.play(np.repeat(a[:, None], 2, 1), 48000, device=idx, blocking=True)
    return len(a) / 48000

def mic_override(name):
    return post("/test/mic", {"device": name})[1]

def silence_wav(seconds, path=None):
    path = path or f"{WORK}/silence{int(seconds)}.wav"
    w = wave.open(path, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(b"\x00\x00" * int(16000 * seconds)); w.close()
    return path

def gesture(name):
    """Posts a real chord (CGEventPost) — only under the hands-off locks."""
    if not os.environ.get("HANDS_OFF"):
        raise RuntimeError("gesture outside hands-off")
    return post("/test/gesture", {"name": name})[1]

def dictate_loopback(wav, wait_after=2.0, seconds=None, stop=True):
    """F10, play the WAV into the Loopback, F10; returns (mark, played seconds)."""
    mark = log_mark()
    gesture("forward-right")
    if not wait_for(lambda: log_has(mark, r"mic: recording through"), 8):
        post("/test/cancel")
        raise RuntimeError("the microphone never opened")
    time.sleep(0.4)
    played = play(wav, seconds=seconds)
    time.sleep(wait_after)
    if stop:
        gesture("forward-right")
    return mark, played

def wait_delivered(mark, timeout=60):
    return wait_for(lambda: log_has(mark, r"📦 delivery:|words landed|dictation abandoned|No words|held"), timeout, 0.3)


# ---------------------------------------------------------------- the registry
CASES = []

def case(id, tags=(), expect=""):
    def deco(fn):
        CASES.append({"id": id, "fn": fn, "tags": set(tags), "expect": expect, "doc": (fn.__doc__ or "").strip()})
        return fn
    return deco

def cleanup():
    """The relay as it was found: no bind, no override, no faults, nothing held, nothing open."""
    try:
        s = state()
        if s["listening"] or s["isRecording"] or s["settling"]:
            post("/test/cancel")
            time.sleep(0.5)
        post("/test/eleven", {"clear": True})
        post("/test/mic", {"device": None})
        caption_off()
        if s.get("bound"):
            unbind()
    except Exception:
        pass

def take_lock():
    """`helpers/wispr_loop.py`'s lock, same format: one process drives this Mac at a time
    (the teacher-labelling batch takes it too since 2026-09-26). A dead holder is ignored."""
    try:
        pid, started = open(LOCK_PATH).read().split(None, 1)
        os.kill(int(pid), 0)
        raise SystemExit(f"another runner holds {LOCK_PATH}: pid {pid} since {started.strip()}")
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        pass
    with open(LOCK_PATH, "w") as f:
        f.write("%d %s\n" % (os.getpid(), time.strftime("%Y-%m-%d %H:%M:%S")))

def release_lock():
    try:
        if open(LOCK_PATH).read().split()[0] == str(os.getpid()):
            os.remove(LOCK_PATH)
    except Exception:
        pass

def run(selected, report_path):
    results = []
    t_start = datetime.datetime.now()
    print(f"relay on {PORT}, {len(selected)} case(s), report → {report_path}")
    for c in selected:
        if "gesture" in c["tags"] and not os.environ.get("HANDS_OFF"):
            results.append((c, "SKIP", "needs hands-off", 0)); print(f"  {c['id']}: SKIP (gesture, no hands-off)"); continue
        try:
            wait_idle()
        except RuntimeError as e:
            # A relay stuck busy (e.g. a prompt panel paused by the pointer) would make every later
            # case wait 600 s too: record it, write the report, stop the batch.
            results.append((c, "ERROR", f"not started — {e}", 0)); print(f"  {c['id']}: ERROR — {e}")
            with open(report_path, "w") as f:
                f.write(render(results, t_start))
            break
        t0 = time.time()
        try:
            verdict, note = c["fn"]()
        except Exception as e:
            verdict, note = "ERROR", f"{type(e).__name__}: {e}\n{traceback.format_exc(limit=2)}"
        finally:
            cleanup()
        dt = time.time() - t0
        results.append((c, verdict, note, dt))
        print(f"  {c['id']}: {verdict} ({dt:.1f}s) — {str(note).splitlines()[0][:150] if note else ''}")
        with open(report_path, "w") as f:
            f.write(render(results, t_start))
    return results

def render(results, t_start):
    counts = {}
    for _, v, _, _ in results:
        counts[v] = counts.get(v, 0) + 1
    out = [f"# Test plan run — {t_start:%Y-%m-%d %H:%M}", "",
           "Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a "
           "defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.", "",
           " · ".join(f"{k} {v}" for k, v in sorted(counts.items())), "",
           "| case | verdict | s | expectation | observed |", "|---|---|---|---|---|"]
    for c, v, note, dt in results:
        note = str(note or "").replace("|", "\\|").replace("\n", "<br>")
        out.append(f"| {c['id']} | **{v}** | {dt:.0f} | {c['expect'].replace('|', '\\|')} | {note} |")
    return "\n".join(out) + "\n"

def main():
    import importlib, fnmatch
    # Run as a script this file is `__main__`; the case modules' `from harness import *` must
    # bind to THIS module or their `@case` registers into a second, unseen copy.
    sys.modules["harness"] = sys.modules[__name__]
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    for mod in ("cases_lc", "cases_lifecycle", "cases_delivery", "cases_gestures", "cases_audio"):
        try:
            importlib.import_module(mod)
        except ModuleNotFoundError as e:
            if mod not in str(e):
                raise
    args = sys.argv[1:]
    only = skip = None; report = f"{here}/report-{datetime.datetime.now():%Y-%m-%d-%H%M}.md"
    i = 0
    while i < len(args):
        if args[i] == "--only": only = args[i + 1].split(","); i += 2
        elif args[i] == "--skip": skip = args[i + 1].split(","); i += 2
        elif args[i] == "--report": report = args[i + 1]; i += 2
        elif args[i] == "--list":
            for c in CASES: print(c["id"], sorted(c["tags"]), "—", c["doc"].splitlines()[0] if c["doc"] else "")
            return
        else: i += 1
    # `--only TD2,LC*`: an exact id, or a glob (`TD2*`, `T[LD]*`).
    def picked(cid, pats): return any(cid == p or fnmatch.fnmatch(cid, p) for p in pats)
    sel = [c for c in CASES if (not only or picked(c["id"], only)) and not (skip and picked(c["id"], skip))]
    take_lock()
    try:
        run(sel, report)
    finally:
        cleanup()
        witness_close()
        release_lock()

if __name__ == "__main__":
    main()
