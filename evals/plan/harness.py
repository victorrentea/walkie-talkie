#!/usr/bin/env python3
"""The test plan's runner (docs/test-plan.md). One process drives the installed app over the
loopback routes; cases are small functions that return a verdict. Nothing here edits the app.

    evals/plan/harness.py [--only PREFIX,...] [--skip PREFIX,...] [--changed-since SHA] [--list] [--report PATH]

`--changed-since SHA` SKIPs every case tagged `covers=(…)` whose covered files did not change between
SHA and the working tree (`unchanged since SHA`); a case without `covers` always runs. With `--list`
it only prints what would run. The rules (names, `File:regex`, the implicit covers): `evals/plan/README.md`.

**One timing knob** (2026-09-29, `evals/plan/timing-audit.md`): every wait that ends on a condition
uses `tmo(<path>)` = (measured p99 of that path × 1.5 + 1 s) × `WT_HARNESS_SLOW` (default 1.0; the
Tart guest driver sets 1.5). Deliberate stalls — a SIGSTOP's length, a soak's gap, a watch window
for something that must NOT happen — are not timeouts and are never scaled. Soak loop lengths:
`WT_SOAK_N` (`cases_wispr_soak.py`).

Every case leaves the relay as it found it (bind, override, faults, cancel). A case that needs a
gesture is tagged `gesture` and only runs when the process was started under `hands-off`
(HANDS_OFF=1 in the environment, which `run-gestures.sh` sets).

**ElevenLabs is opt-in per case** (2026-09-27, Victor: *"pune plafon + regula ca testele locale sa
prefere intotdeauna motor local"*): the run sets the engine to the local Whisper and puts his back
at exit; only the cases in `ELEVEN_ENGINE` switch to an ElevenLabs engine, for their duration.
Those run against the fake Scribe (`fake_scribe.py`, `WT_FAKE_SCRIBE=1`, the default) unless they
are in `VENDOR_ONLY`; a case that would reach the real service is SKIPped when the month has fewer
than `WT_ELEVEN_MIN_CREDITS` (3000) of `WT_ELEVEN_QUOTA` (10000) credits left, or the usage cannot
be read. `WT_FAKE_SCRIBE=0` sends every ElevenLabs case to the real service, under that cap."""
import json, os, signal, subprocess, sys, time, urllib.request, urllib.error, datetime, traceback, re, wave, shutil

HOME = os.path.expanduser("~/.walkie-talkie")
LOG = HOME + "/relay.log"
OUTBOX = HOME + "/outbox.jsonl"
WORK = os.environ.get("WT_WORK", "/tmp/wt-plan")
os.makedirs(WORK, exist_ok=True)
CORPUS = os.path.expanduser("~/.walkie-talkie/voice-corpus")
CLIP_EN = CORPUS + "/2026-09-18/21-05-35-11l735.wav"      # 3.5 s, "If I dictate now, how good is this dictation, I wonder?"
CLIP_EN_LONG = CORPUS + "/2026-09-18/23-59-48-11l129.wav" # 157 s EN
# **Real speech above Q8's floor** (2026-09-27, batch 7): the local model stands in for a failed
# Scribe upload only with ≥ 1.5 s voiced (`ElevenLabsSource.fallbackVoicedFloor`, on every
# failure; 2.0 until Q13, 2026-09-27). CLIP_EN measured 1.1–1.9 s voiced until Q13, because
# 1365-frame Loopback buffers each dropped a tail the meter never saw; the meter carries the tail
# since (`VoicedMeter`). The first 12 s of CLIP_EN_LONG measure ~3.5 s — the clip every "fallback
# delivers" case plays, kept so those cases do not ride on a clip near the floor.
CLIP_SPEECH_SECONDS = 12
def _speech_clip():
    out = os.path.join(os.environ.get("WT_WORK", "/tmp/wt-plan"), "speech12.wav")
    if not os.path.exists(out) and os.path.exists(CLIP_EN_LONG):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        r = wave.open(CLIP_EN_LONG)
        w = wave.open(out, "wb"); w.setparams(r.getparams())
        w.writeframes(r.readframes(int(r.getframerate() * CLIP_SPEECH_SECONDS))); w.close(); r.close()
    return out
CLIP_SPEECH = _speech_clip()
# **Our own Loopback device** (2026-09-26): pure Pass-Thru, created from the plist
# (`~/Library/Application Support/Loopback/Devices.plist`, template `🎙️TO Zoom`, new UUIDs, then
# `open -a Loopback` once). `🎓 TO Wispr` belongs to the Wispr teacher-labelling rig and carries the
# built-in mic as a source; the two must never be confused.
# `WT_LOOPBACK` names it elsewhere: in the Tart lab (docs/vm-lab.md) there is no Loopback app.
LOOPBACK = os.environ.get("WT_LOOPBACK", "🧪 WT Inject")
LOCK_PATH = HOME + "/wispr-loop.lock"   # the one runner lock on this Mac (helpers/wispr_loop.py)

# ---------------------------------------------------------------- ElevenLabs: local first, a cap, a fake (2026-09-27)
# 26 Sep 2026: this suite alone burned 4 561 of the month's 10 000 credits (2 159 scribe_v2 +
# 2 402 scribe_v2_realtime). Victor, 27 Sep: "pune plafon + regula ca testele locale sa prefere
# intotdeauna motor local" · "poti emula daca vrei apiul lor de streaming pt testele de live subtitles".
LOCAL_ENGINE = "whisper"                 # the ids of StatusItem / AppDelegate.engine(named:)
ELEVEN_ENV = HOME + "/elevenlabs.env"    # re-read by the app at every engine pick (reloadKey)
FAKE_MARK = "# fake-scribe: written by evals/plan/harness.py, removed at its exit"
FAKE_ON = os.environ.get("WT_FAKE_SCRIBE", "1") != "0"
QUOTA = int(os.environ.get("WT_ELEVEN_QUOTA", "10000"))
MIN_CREDITS = int(os.environ.get("WT_ELEVEN_MIN_CREDITS", "3000"))
# The engine a case needs for its duration — every case that reads `engine()` expecting ElevenLabs
# (`cases_audio.pre`, `cases_gestures.need_el`, `cases_queue`) or switches to it itself and uploads.
# Batch-only cases get `eleven` (no socket: nothing streamed, fewer credits on the real service).
# Not here, because they switch themselves and upload nothing: TL3, TL22, TR19; local: TR15.
_LIVE = "TL29 TL30 TR9 LC13 B1 B2 B3 B4 B5"
_BATCH = ("TL8 TL9 TL10 TL11 TL12 TL13 TL14 TL15 TL16 TL25 TL32 TR10 TR11 TR12 TR13 TR14 TR23 TR24 "
          "Q1 Q2 Q3 Q4 Q5 Q6 TG1 TG2 TG3 TG4 TG6 TG7 TG8 TG9 TG13 TG14 TG15 TG17 TG18 TG20 TG25 TG28 "
          "TG29 TG36 TG40 TG41")
ELEVEN_ENGINE = dict([(c, "eleven") for c in _BATCH.split()] + [(c, "eleven-live") for c in _LIVE.split()])
# Every upload answered by the `/test/eleven` fault switch — no credits even on the real service,
# so these run whatever the cap says.
FAULT_ONLY = set("TL11 TL13 TL14 TL32 TR10 TR11 TR12 TR13 TR14".split())
# What only the real service can answer: the 10-min ceiling's 19 MB upload against URLSession's
# own 20 s timeout. Real (and under the cap) even with the fake on.
VENDOR_ONLY = {"TL25"}
# **The Tart guest** (docs/vm-lab.md): `lab_only` cases run only there. `WT_LAB=1` (run-phase.sh
# exports it) or the hypervisor's own flag; the host without either SKIPs them.
def _in_lab():
    if os.environ.get("WT_LAB") == "1":
        return True
    try:
        return subprocess.run(["sysctl", "-n", "kern.hv_vmm_present"], capture_output=True,
                              text=True, timeout=3).stdout.strip() == "1"
    except Exception:
        return False
IN_LAB = _in_lab()
# Extra per-case restores a case module registers (cases_wispr: the fake History DB line, the
# chord mute); `cleanup()` runs them after every case and at exit, whatever the case did.
CLEANUPS = []
RUN = {"credits_before": None, "usage_error": None, "engine0": None, "fake": None, "results": [],
       "credits_after": None}


# ---------------------------------------------------------------- timing (2026-09-29, timing-audit.md)
# Victor, 2026-09-29: *"why do these tests take so long?"* — most of a wave was the harness waiting on
# round numbers and on its own Recover staging, not on the app. One knob scales every condition
# timeout for a slower machine; nothing else in a case carries its own slack.
SLOW = max(0.5, float(os.environ.get("WT_HARNESS_SLOW", "1.0") or 1.0))
# Measured p99 (seconds) of what the waits wait on — the lab's waves 3–5 (quiet guest, n in
# timing-audit.md; the max of the small samples stands in for the p99) and the desk.
P99 = {
    "mic_open": 10.0,       # gesture → `mic: recording through`: < 1 s warm, 10 s behind the 6 s main-thread
                            # stall after a Wispr relaunch (W5a TW4, finding 4) — the waits that follow a relaunch
    "wispr_row": 3.0,       # close → words from Wispr's row, relay sentence (p90 1.8–2.2, max 2.92 s)
    "caret": 3.0,           # his standalone sentence → pasted at TextEdit's caret (p90 1.5–2.6 s)
    "local": 8.5,           # a local decode alone, warm (p50 1.5 s, max 8.45 s)
    "q14": 11.1,            # close → words through Q14 / local-auto (p50 4.5–4.6 s, wave 3 max 11.1 s)
    "terminal": 7.0,        # close → the words IN the witness tab (settle + typing; p90 6.2–6.4 s)
    "q14_terminal": 16.0,   # Q14 words + the typing into the witness (11.1 + ~5 s)
    "wispr_relaunch": 15.0, # `/test/wispr-proc relaunch` → a new pid and `/engine.ready` (W5a TW4: 14.5 s)
    "recover_staged": 1.0,  # a cancel → `state.recoverable` (same log second)
}

def tmo(p99):
    """A condition wait's timeout: the measured p99 × 1.5 + 1 s, times `WT_HARNESS_SLOW`. `p99` is a
    key of `P99` or seconds."""
    s = P99[p99] if isinstance(p99, str) else float(p99)
    return (s * 1.5 + 1.0) * SLOW


# ---------------------------------------------------------------- transport
def _port():
    for p in (8917, 8918, 8919):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{p}/up", timeout=2) as r:
                if json.load(r).get("ok"):
                    return p
        except Exception:
            pass
    return None

# No relay is not fatal at import: `--help`, `--list` and `--changed-since … --list` need none.
# The first request without one exits as before.
PORT = _port()
B = f"http://127.0.0.1:{PORT}" if PORT else None

def _base():
    if not B:
        raise SystemExit("no relay on 8917-8919")
    return B

def get(path, timeout=6):
    with urllib.request.urlopen(_base() + path, timeout=timeout) as r:
        return json.load(r)

def post(path, body=None, timeout=25):
    data = json.dumps(body if body is not None else {}).encode()
    req = urllib.request.Request(_base() + path, data, {"content-type": "application/json"})
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

def when(mark, pattern, timeout, step=0.05):
    """Wall-clock time the pattern first shows in the log after `mark`, or None."""
    return wait_for(lambda: time.time() if log_has(mark, pattern) else None, timeout, step)

# ---------------------------------------------------------------- busy, the harness's own Recover aside
# **Audio staged for Recover holds `busy` for five minutes** (`restartBlockers`: a restart would wipe
# `cancelled/`). It is a restart gate, not a sentence: nothing the harness does next is refused by it.
# Waves 4–5 waited it out after every case that ended in a cancel — 60 s in `engine_back` (inside the
# case's time), the rest of the five minutes in `wait_idle`, 180 s more at exit: 1 613 s of wave 4's
# 5 133 and ~750 s of wave 5's 2 762. The harness's OWN staging is ignored now; staging it did not do
# (Victor's cancel before the run, or between two cases) is still waited out, because the next case's
# cancel would replace his file (`keepCancelled` keeps one). In the Tart guest every staging is ours.
OWN_RECOVER = set()
RECOVER_WHY = "audio staged for Recover"

def _staged_at(rec):
    try:
        exp = datetime.datetime.fromisoformat(str(rec.get("expiresAt")).replace("Z", "+00:00")).timestamp()
        return exp - 300.0
    except Exception:
        return None

def recover_is_ours(s):
    rec = s.get("recoverable") or {}
    if not rec:
        return False
    if IN_LAB or rec.get("path") in OWN_RECOVER:
        return True
    t0, at = RUN.get("case_t0"), _staged_at(rec)
    return t0 is not None and at is not None and at >= t0 - 0.5

def busy_why(s=None):
    """`busyWhy` without the harness's own Recover staging."""
    s = s if s is not None else state()
    why = list(s.get("busyWhy") or [])
    if recover_is_ours(s):
        why = [w for w in why if not str(w).startswith(RECOVER_WHY)]
    return why

def relay_busy(s=None):
    """`state.busy`, the harness's own Recover staging aside — what every settle wait reads."""
    return bool(busy_why(s))

def wait_idle(timeout=600):
    """Victor may be dictating: never start a case over his sentence."""
    paused_since = [None]
    def idle():
        s = state()
        if not relay_busy(s):
            return True
        # A prompt paused by a pointer that never moves (a huge panel unfolding under it) never
        # resolves on its own: after 20 s cancel it through POST /test/prompt (batch 4, G5).
        if any("Paused" in str(r) for r in s.get("chip") or []) or (s.get("prompt") or {}).get("paused"):
            paused_since[0] = paused_since[0] or time.time()
            if time.time() - paused_since[0] > 20:
                code, _ = post("/test/prompt", {"do": "cancel"})
                print(f"  (wait_idle: a paused prompt panel held 20 s — POST /test/prompt cancel → {code})")
                paused_since[0] = None
                if code != 200:
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

def kill_tty(tty):
    """Every process on that tty but `login` (root's). `pkill -t ttysNNN` matches nothing on this Mac
    (measured 2026-09-26: rc 1 with `cat` alive on the tty), so every close met Terminal's
    "terminate?" sheet and left the window behind — ~50 orphans in one evening."""
    out = subprocess.run(["ps", "-t", tty.replace("/dev/", ""), "-o", "pid=,comm="], capture_output=True, text=True).stdout
    for ln in out.splitlines():
        pid, _, comm = ln.strip().partition(" ")
        if pid.isdigit() and "login" not in comm and int(pid) != os.getpid():
            try:
                os.kill(int(pid), 9)
            except (ProcessLookupError, PermissionError):
                pass
    time.sleep(0.3)

def _tab_state(dev):
    """'busy', 'idle' or 'gone' — the Terminal tab on that tty, asked by tty, never by name."""
    r = osa('tell application "Terminal"',
            'repeat with w in windows',
            'try',
            'repeat with t in tabs of w',
            f'if tty of t is "{dev}" then return (busy of t) as text',
            'end repeat',
            'end try',
            'end repeat',
            'return "gone"',
            'end tell')
    return {"true": "busy", "false": "idle"}.get(r, "gone")

def close_tty_tab(tty):
    """Close the harness's own tab on `tty` **without ever raising Terminal's "Terminate?" sheet**
    (2026-09-27). Kill everything on the tty, wait up to 5 s for the tab's `busy` to go false, and
    only then close its window — by tty, never by name. A tab still busy is left open and logged:
    a close on it raises the sheet, and the sheet is a dialog on Victor's screen that outlives the
    run (he found several on 2026-09-27, the by-name close of `wt-witness*` having fired on tabs
    whose `cat` had not died yet). Returns 'closed', 'gone' or 'busy'."""
    if not tty:
        return "gone"
    dev = "/dev/" + tty.replace("/dev/", "")
    kill_tty(tty)
    t0, st = time.time(), _tab_state(dev)
    while st == "busy" and time.time() - t0 < 5:
        time.sleep(0.2)
        st = _tab_state(dev)
    if st == "busy":
        print(f"  ⚠️ tab {dev} still busy 5 s after the kill — left open, not closed "
              "(closing it would raise Terminal's Terminate? sheet)", flush=True)
        return "busy"
    if st == "idle":
        osa('tell application "Terminal"',
            'repeat with w in windows',
            'try',
            'repeat with t in tabs of w',
            f'if tty of t is "{dev}" then',
            'close w saving no',
            'return "closed"',
            'end if',
            'end repeat',
            'end try',
            'end repeat',
            'end tell')
        return "closed"
    return "gone"

def close_tabs_named(name):
    """Every tab in a window whose title contains `name`, each through `close_tty_tab` — for an
    orphan whose tty the run no longer knows. `name` is always a `wt-witness*` title."""
    out = osa(f'tell application "Terminal" to get tty of every tab of (every window whose name contains "{name}")')
    for dev in sorted(set(re.findall(r"/dev/ttys\d+", out))):
        close_tty_tab(dev)

def witness_close():
    """Kill the tab's `cat` first: a window with a running process makes Terminal ask
    "terminate?" and the close silently does nothing (18 orphan windows on 2026-09-26) —
    and since 2026-09-27 the close waits for the tab to be idle (`close_tty_tab`)."""
    if WITNESS["tty"]:
        close_tty_tab(WITNESS["tty"])
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
    """Play a 16 kHz mono WAV into the Loopback device, blocking. Silent for the room.
    With the fake Scribe up, it is first told what this clip says (`fake_script`)."""
    fake_script(wav, seconds)
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
    if not wait_for(lambda: log_has(mark, r"mic: recording through"), tmo("mic_open")):
        post("/test/cancel")
        raise RuntimeError("the microphone never opened")
    time.sleep(0.4)
    played = play(wav, seconds=seconds)
    time.sleep(wait_after)
    if stop:
        gesture("forward-right")
    return mark, played

def wait_delivered(mark, timeout=None):
    """Until the sentence's words landed or it ended without them; `timeout` defaults to Q14's p99
    (the slowest way words land) through `tmo`."""
    timeout = tmo("q14") if timeout is None else timeout
    return wait_for(lambda: log_has(mark, r"📦 delivery:|words landed|dictation abandoned|No words|held"), timeout, 0.3)


# ---------------------------------------------------------------- ElevenLabs: usage, engine, the fake
def _his_lines(lines):
    """`elevenlabs.env` without the block `fake_env` writes (FAKE_MARK … FAKE_MARK (end))."""
    out, inside = [], False
    for l in lines:
        if l.startswith(FAKE_MARK):
            inside = not l.endswith("(end)")
            continue
        if not inside:
            out.append(l)
    return out

def _eleven_key():
    k = os.environ.get("ELEVENLABS_API_KEY")
    if k:
        return k
    try:
        for line in _his_lines(open(ELEVEN_ENV, encoding="utf-8").read().splitlines()):
            if line.strip().startswith("ELEVENLABS_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"') or None
    except FileNotFoundError:
        pass
    return None

def eleven_usage():
    """(credits used this calendar month, None) or (None, why). `/v1/user/subscription` answers
    nulls for this key; the character-stats breakdown by model is what the dashboard shows."""
    try: q = state().get("elevenQuota") or {}   # prefer the app's own reading (its 🧾 row)
    except Exception: q = {}
    if isinstance(q.get("used"), int): return q["used"], None
    key = _eleven_key()
    if not key:
        return None, "no ELEVENLABS_API_KEY"
    now = datetime.datetime.now(datetime.timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    url = ("https://api.elevenlabs.io/v1/usage/character-stats?start_unix=%d&end_unix=%d&breakdown_type=model"
           % (int(start.timestamp() * 1000), int(now.timestamp() * 1000)))
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"xi-api-key": key}), timeout=15) as r:
            d = json.load(r)
        return int(round(sum(sum(v or 0 for v in series) for series in (d.get("usage") or {}).values()))), None
    except Exception as e:
        return None, f"{type(e).__name__}: {e}"

def credits_left():
    b = RUN["credits_before"]
    return None if b is None else QUOTA - b

def is_eleven(c):
    return str(c.get("engine") or "").startswith("eleven")

def needs_real(c):
    """The case would spend real ElevenLabs credits."""
    return is_eleven(c) and c["id"] not in FAULT_ONLY and (not RUN["fake"] or c["id"] in VENDOR_ONLY)

def routes_fake(c):
    return bool(RUN["fake"]) and is_eleven(c) and c["id"] not in VENDOR_ONLY

def cap_blocks(c):
    """The SKIP note when the credit cap stops this case, else None."""
    if not needs_real(c):
        return None
    left = credits_left()
    if left is None:
        return f"credit cap (? left — usage unreadable: {RUN['usage_error']})"
    if left < MIN_CREDITS:
        return f"credit cap ({left} left)"
    return None

def fake_env(on):
    """Point the app's ElevenLabs URLs at the fake (or back), through `elevenlabs.env` — the app
    re-reads it at every engine pick, while the harness's own environment never reaches an app
    that `relay-restart.sh` launched with `open`. Only lines carrying FAKE_MARK are written or
    removed; everything else in the file (his key) is left byte for byte."""
    try:
        lines = open(ELEVEN_ENV, encoding="utf-8").read().splitlines()
        mode = os.stat(ELEVEN_ENV).st_mode & 0o777
    except FileNotFoundError:
        lines, mode = [], 0o600
    keep = _his_lines(lines)
    if on and RUN["fake"]:
        live, batch = RUN["fake"]["urls"]
        # The app takes the whole rest of the line as the value, so the mark goes on a line of its own.
        keep += [FAKE_MARK, f"WT_ELEVEN_LIVE_URL={live}", f"WT_ELEVEN_BATCH_URL={batch}"]
        if not _eleven_key():   # the lab guest after a reset: a key only the fake accepts
            keep.append("ELEVENLABS_API_KEY=fake-scribe")
        keep.append(FAKE_MARK + " (end)")
    if keep == lines:
        return
    tmp = ELEVEN_ENV + ".harness-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(keep) + ("\n" if keep else ""))
    os.chmod(tmp, mode)
    os.replace(tmp, ELEVEN_ENV)

def set_engine(eid, timeout=60):
    """POST /engine once the relay is idle (a switch mid-sentence is refused); True when taken.
    Idle = `relay_busy` false: the harness's own Recover staging never held a switch back
    (`setEngine` refuses only mid-sentence), yet it cost 60 s after every cancelling case."""
    wait_for(lambda: not relay_busy(), timeout, 0.5)
    for _ in range(3):
        _, r = post("/engine", {"id": eid})
        if r.get("engine") == eid:
            return True
        time.sleep(1.0)
    return False

def engine_for_case(c):
    """Switch to the case's ElevenLabs engine, fake or real. A pick of the engine already running
    re-reads nothing (`setEngine` returns early), so it goes through the local one first."""
    fake_env(routes_fake(c))
    if engine()["engine"] == c["engine"]:
        set_engine(LOCAL_ENGINE)
    return set_engine(c["engine"])

def engine_back():
    """After every case: the local engine again, whatever the case did."""
    try:
        if engine()["engine"] != LOCAL_ENGINE:
            set_engine(LOCAL_ENGINE)
    except Exception:
        pass

_WAV_SECONDS = {}
def _duration(wav):
    if wav not in _WAV_SECONDS:
        try:
            w = wave.open(wav); _WAV_SECONDS[wav] = w.getnframes() / float(w.getframerate()); w.close()
        except Exception:
            _WAV_SECONDS[wav] = None
    return _WAV_SECONDS[wav]

def fake_script(wav, seconds=None):
    """Tell the fake what the clip about to be played says: the corpus `.txt` beside it, cut to
    the share played (CLIP_SPEECH is the first 12 s of CLIP_EN_LONG). No `.txt` (silence) → no
    words, and the fake answers from the energy alone."""
    if not RUN["fake"]:
        return
    src, share = wav, 1.0
    if wav == CLIP_SPEECH and _duration(CLIP_EN_LONG):
        src, share = CLIP_EN_LONG, CLIP_SPEECH_SECONDS / _duration(CLIP_EN_LONG)
    txt = os.path.splitext(src)[0] + ".txt"
    words = open(txt, encoding="utf-8", errors="replace").read().split() if os.path.exists(txt) else []
    d = _duration(wav)
    if seconds and d:
        share *= min(1.0, seconds / d)
    if words and share < 1.0:
        words = words[: max(1, int(round(len(words) * share)))]
    try:
        RUN["fake"]["state"].set_script({"words": words, "wav": wav, "seconds": seconds})
    except Exception as e:
        print(f"  (fake_script: {type(e).__name__}: {e})")

def eleven_setup():
    """At the start of a run: the month's credits, a stale fake line gone, the fake up, the engine local."""
    used, why = eleven_usage()
    RUN["credits_before"], RUN["usage_error"] = used, why
    fake_env(False)                       # a crashed run's lines
    if FAKE_ON:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fake_scribe
        srv, port = fake_scribe.serve(0)
        RUN["fake"] = {"server": srv, "port": port, "urls": fake_scribe.urls(port), "state": fake_scribe.STATE}
    wait_idle()
    RUN["engine0"] = engine()["engine"]
    if RUN["engine0"] != LOCAL_ENGINE and not set_engine(LOCAL_ENGINE):
        print(f"  (could not switch the engine to {LOCAL_ENGINE}: still {engine()['engine']})")
    left = credits_left()
    print(f"ElevenLabs: {used if used is not None else '?'} credits used this month, "
          f"{left if left is not None else '?'} of {QUOTA} left (cap {MIN_CREDITS}){' — ' + why if why else ''}; "
          f"engine {RUN['engine0']} → {LOCAL_ENGINE} for the run; fake Scribe "
          + (f"on port {RUN['fake']['port']}" if RUN["fake"] else "off (WT_FAKE_SCRIBE=0)"))

def eleven_teardown():
    """The file first, then his engine: picking an ElevenLabs engine re-reads the file."""
    fake_env(False)
    e0 = RUN["engine0"]
    try:
        if e0 and engine()["engine"] != e0:
            wait_for(lambda: not relay_busy(), 120, 0.5)
            set_engine(e0)
    except Exception as e:
        print(f"  (engine not restored to {e0}: {type(e).__name__}: {e})")
    if RUN["fake"]:
        RUN["fake"]["server"].shutdown()
    if RUN["credits_before"] is not None:
        RUN["credits_after"], _ = eleven_usage()


# ---------------------------------------------------------------- the registry
CASES = []

def case(id, tags=(), expect="", engine=None, lab_only=False, pre=None, covers=None):
    """`engine`: the engine the case needs for its duration (`eleven`｜`eleven-live`｜`wispr`);
    the cases written before 2026-09-27 get it from `ELEVEN_ENGINE`. Tagged `eleven` (+ `live`)
    or `wispr`. `lab_only`: SKIP outside the Tart guest (`IN_LAB`), tagged `lab`. `pre`: a
    callable answering a SKIP reason (or None), asked before the engine is switched.
    `covers`: what in the repo this case exercises, for `--changed-since` — a Sources file's stem
    (`"WisprFlowSource"`), a repo path or prefix (`"helpers/whisper_helper.py"`), or `"Stem:regex"`
    (only a change whose added/removed lines match the regex counts — for `AppDelegate`, which
    every change touches). None = always runs."""
    def deco(fn):
        eng = engine or ELEVEN_ENGINE.get(id)
        el = str(eng or "").startswith("eleven")
        t = (set(tags) | ({"eleven"} if el else set()) | ({"live"} if eng == "eleven-live" else set())
             | ({"wispr"} if eng == "wispr" else set()) | ({"lab"} if lab_only else set()))
        CASES.append({"id": id, "fn": fn, "tags": t, "expect": expect, "doc": (fn.__doc__ or "").strip(),
                      "engine": eng, "lab_only": lab_only, "pre": pre,
                      "covers": tuple(covers) if covers else None,
                      "module": getattr(fn, "__module__", None)})
        return fn
    return deco


# ---------------------------------------------------------------- what a case covers (`covers=`)
# The areas the Wispr / lab cases are tagged with, composed per case (`COVER["wispr"] + …`). A
# `Stem:regex` entry counts a change to that file only when a changed line matches — AppDelegate,
# HotkeyTap and ElementPicker are touched by nearly every commit, and only some of it is the area.
COVER = {
    "wispr": ("WisprFlowSource", "WisprState", "WisprHistory", "WisprHistoryWatch", "WisprOwnership",
              "WisprWatch", "WisprNotes", "WisprSink", "WisprTestHooks", "ProcessClock", "DictationSource",
              r"AppDelegate:(?i)wispr|history|ownTake|borrow|standalone|firewall"),
    "gesture": (r"HotkeyTap:(?i)gesture|forward|wispr|chord|ptt|modifier|cmdv|⌘V|paste|firewall|swallow|redirect",
                "ElementPicker"),               # every /test/* route lives in ElementPicker
    "recorder": ("MicRecorder", "InputDevice", "AudioDevices", "VoicePrep",
                 r"AppDelegate:(?i)\bmic\b|recorder|DEAF|meter|voiced|override"),
    "local": ("LocalWhisperSource", "Transcriber", "DecodeRate", "AutoLocal", "helpers/whisper_helper.py",
              r"AppDelegate:(?i)local|fallback|whisper|decode|budget|forced"),
    "eleven": ("ElevenLabsSource", "ElevenLabsLive", r"AppDelegate:(?i)eleven|scribe"),
    "delivery": ("TerminalBinding", "Outbox", "PasteHint",
                 r"AppDelegate:(?i)deliver|latch|sentence|park|queue|recover|cancel|route|bind|prompt|outbox|clipboard"),
    "chip": (r"RelayWindow:(?i)wispr|listening|opening|starting|local|budget|wait|transcrib|refus", "OverlayStates"),
    "restart": ("RestartGate", "QuitGate", "Relaunch", "relay-restart.sh", "tools/restart_gate.py"),
}

def covers(*areas, extra=()):
    """`covers=covers("wispr", "local")`: the union of those `COVER` areas, plus `extra` entries."""
    out = []
    for a in areas:
        out += [e for e in COVER[a] if e not in out]
    return tuple(out) + tuple(extra)


# ---------------------------------------------------------------- --changed-since (skip what did not change)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHANGED = {"sha": None, "files": None, "diff": {}}

def _git(*args):
    r = subprocess.run(["git", "-C", REPO] + list(args), capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout

def changed_files(sha):
    """Repo paths that differ between `sha` and the working tree (committed or not), plus untracked
    files — what a build from here would carry that `sha` did not."""
    if CHANGED["sha"] != sha:
        _git("rev-parse", "--verify", sha + "^{commit}")
        files = set(_git("diff", "--name-only", sha, "--").split())
        files |= set(_git("ls-files", "--others", "--exclude-standard").split())
        CHANGED.update(sha=sha, files=sorted(files), diff={})
    return CHANGED["files"]

def _diff_lines(path):
    if path not in CHANGED["diff"]:
        out = _git("diff", "-U0", CHANGED["sha"], "--", path)
        CHANGED["diff"][path] = [l[1:] for l in out.splitlines()
                                 if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    return CHANGED["diff"][path]

def _matches(entry, path):
    stem = os.path.splitext(os.path.basename(path))[0]
    name, _, rx = entry.partition(":")
    hit = name == stem or name == path or ("/" in name and path.startswith(name.rstrip("/") + "/"))
    if not hit:
        return False
    if not rx:
        return True
    try:
        lines = _diff_lines(path)
    except SystemExit:
        return True                # an untracked file: no diff to filter, it changed
    return not lines or any(re.search(rx, l) for l in lines)

_IMPLICIT = {}

def _implicit(module):
    """This runner, the case's module and every `cases_*` / `fake_*` module it imports, transitively
    (a helper edited in `cases_wispr_soak` changes the chaos cases that use it)."""
    if module not in _IMPLICIT:
        here, seen, todo = os.path.dirname(os.path.abspath(__file__)), set(), [module] if module else []
        while todo:
            m = todo.pop()
            if m in seen:
                continue
            seen.add(m)
            try:
                src = open(os.path.join(here, m + ".py"), encoding="utf-8").read()
            except OSError:
                continue
            todo += re.findall(r"^\s*(?:from|import)\s+((?:cases|fake)_\w+)", src, re.M)
        _IMPLICIT[module] = ["evals/plan/harness.py"] + sorted(f"evals/plan/{m}.py" for m in seen)
    return _IMPLICIT[module]

def unchanged_since(c, sha):
    """The SKIP note when nothing `c` covers changed since `sha`, else None. This runner, the case's
    own module and the case modules it imports are always covered: a case edited since `sha` runs."""
    if not c.get("covers"):
        return None
    files = changed_files(sha)
    implicit = _implicit(c.get("module")) + (["evals/plan/fake_scribe.py"] if is_eleven(c) else [])
    for path in files:
        if path in implicit or any(_matches(e, path) for e in c["covers"]):
            return None
    return f"unchanged since {sha}"

def cleanup():
    """The relay as it was found: his binding back (else none), no override, no faults, nothing held,
    nothing open. The binding is put back since 2026-10-10 — a desk run used to leave him unbound."""
    try:
        s = state()
        if s["listening"] or s["isRecording"] or s["settling"]:
            post("/test/cancel")
            time.sleep(0.5)
        post("/test/eleven", {"clear": True})
        post("/test/mic", {"device": None})
        caption_off()
        if RUN.get("bound0"):
            post("/bind", {"tty": RUN["bound0"]})
        elif s.get("bound"):
            unbind()
    except Exception:
        pass
    for fn in CLEANUPS:
        try:
            fn()
        except Exception as e:
            print(f"  (cleanup {getattr(fn, '__name__', fn)}: {type(e).__name__}: {e})")

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

def _note_own_recover():
    """The file this case staged for Recover (if any) is the harness's: later waits ignore it."""
    try:
        rec = state().get("recoverable") or {}
        at, t0 = _staged_at(rec), RUN.get("case_t0")
        if rec.get("path") and at is not None and t0 is not None and at >= t0 - 0.5:
            OWN_RECOVER.add(rec["path"])
    except Exception:
        pass

def run(selected, report_path):
    results = RUN["results"]
    t_start = RUN.setdefault("t_start", datetime.datetime.now())
    print(f"relay on {PORT}, {len(selected)} case(s), report → {report_path}")
    for c in selected:
        if "gesture" in c["tags"] and not os.environ.get("HANDS_OFF"):
            results.append((c, "SKIP", "needs hands-off", 0)); print(f"  {c['id']}: SKIP (gesture, no hands-off)"); continue
        why = "needs the Tart guest (lab_only)" if c.get("lab_only") and not IN_LAB else None
        if not why and RUN.get("changed_since"):
            why = unchanged_since(c, RUN["changed_since"])
        if not why and c.get("pre"):
            try:
                why = c["pre"]()
            except Exception as e:
                why = f"precondition failed: {type(e).__name__}: {e}"
        if why:
            results.append((c, "SKIP", why, 0)); print(f"  {c['id']}: SKIP {why}")
            with open(report_path, "w") as f:
                f.write(render(results, t_start))
            continue
        capped = cap_blocks(c)
        if capped:
            results.append((c, "SKIP", capped, 0)); print(f"  {c['id']}: SKIP {capped}")
            with open(report_path, "w") as f:
                f.write(render(results, t_start))
            continue
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
        RUN["case_t0"] = t0
        try:
            if c.get("engine") and not engine_for_case(c):
                raise RuntimeError(f"POST /engine {c['engine']} was not taken (engine {engine()['engine']})")
            if RUN["fake"]:
                RUN["fake"]["state"].scripts = []
                RUN["fake"]["state"].fault = {}
            verdict, note = c["fn"]()
            if is_eleven(c):
                note = f"[{c['engine']} → {'fake Scribe' if routes_fake(c) else 'real ElevenLabs'}] {note}"
        except Exception as e:
            verdict, note = "ERROR", f"{type(e).__name__}: {e}\n{traceback.format_exc(limit=2)}"
        finally:
            cleanup()
            _note_own_recover()
            engine_back()
            RUN["case_t0"] = None
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
           " · ".join(f"{k} {v}" for k, v in sorted(counts.items())), "", _eleven_header(), "",
           "| case | verdict | s | expectation | observed |", "|---|---|---|---|---|"]
    for c, v, note, dt in results:
        note = str(note or "").replace("|", "\\|").replace("\n", "<br>")
        expect = c["expect"].replace("|", "\\|")   # outside the f-string: the lab's /usr/bin/python3 is 3.9
        out.append(f"| {c['id']} | **{v}** | {dt:.0f} | {expect} | {note} |")
    foot = _eleven_footer()
    return "\n".join(out) + "\n" + (("\n" + foot + "\n") if foot else "")

def _eleven_header():
    b, left = RUN["credits_before"], credits_left()
    credits = (f"**{b}** credits used this month before the run, **{left}** of {QUOTA} left" if b is not None
               else f"credits unreadable ({RUN['usage_error']})")
    cap = "cases that would spend real credits **SKIP**" if (left is None or left < MIN_CREDITS) else "real cases allowed"
    fake = (f"fake Scribe on port {RUN['fake']['port']} (live + batch, `WT_FAKE_SCRIBE=1`)" if RUN["fake"]
            else "fake Scribe off (`WT_FAKE_SCRIBE=0`): ElevenLabs cases go to the real service")
    return (f"ElevenLabs: {credits}; cap {MIN_CREDITS} → {cap}. Engine for the run: `{LOCAL_ENGINE}` "
            f"(was `{RUN['engine0']}`, put back at exit); only `eleven`-tagged cases switch. {fake}.")

def _eleven_footer():
    a, b = RUN["credits_after"], RUN["credits_before"]
    lines = []
    if a is not None and b is not None:
        lines.append(f"ElevenLabs credits after the run: **{a}** — this run used **{a - b}** "
                     "(ElevenLabs' daily buckets can lag by minutes; the dashboard is the final word).")
    if RUN["fake"]:
        st = RUN["fake"]["state"].describe()["stats"]
        lines.append(f"Fake Scribe: {st['sessions']} live session(s), {st['chunks']} chunks ({st['audioSeconds']} s), "
                     f"{st['partials']} partials, {st['commits']} commits, {st['batch']} batch upload(s), "
                     f"{st['errorsSent']} error(s) sent.")
    return "\n\n".join(lines)

def main():
    import importlib, fnmatch
    # Run as a script this file is `__main__`; the case modules' `from harness import *` must
    # bind to THIS module or their `@case` registers into a second, unseen copy.
    sys.modules["harness"] = sys.modules[__name__]
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    for mod in ("cases_lc", "cases_lifecycle", "cases_delivery", "cases_gestures", "cases_audio", "cases_queue",
                "cases_wispr", "cases_wispr_soak", "cases_wispr_chaos", "cases_localnow", "cases_localauto", "cases_w4real", "cases_kamikaze"):
        try:
            importlib.import_module(mod)
        except ModuleNotFoundError as e:
            if mod not in str(e):
                raise
    args = sys.argv[1:]
    only = skip = None; listing = False; report = f"{here}/report-{datetime.datetime.now():%Y-%m-%d-%H%M}.md"
    i = 0
    while i < len(args):
        if args[i] == "--only": only = args[i + 1].split(","); i += 2
        elif args[i] == "--skip": skip = args[i + 1].split(","); i += 2
        elif args[i] == "--report": report = args[i + 1]; i += 2
        elif args[i] == "--changed-since": RUN["changed_since"] = args[i + 1]; i += 2
        elif args[i] == "--list": listing = True; i += 1
        elif args[i] in ("-h", "--help"):
            print(__doc__); return
        # An unknown flag used to be skipped, so `harness.py --help` ran all 146 cases (2026-09-27,
        # 11:50: piped into `head`, it died of SIGPIPE mid-case and left the relay `listening`).
        else: raise SystemExit(f"unknown argument {args[i]!r}\n\n{__doc__}")
    # `--only TD2,LC*`: an exact id, or a glob (`TD2*`, `T[LD]*`).
    def picked(cid, pats): return any(cid == p or fnmatch.fnmatch(cid, p) for p in pats)
    sel = [c for c in CASES if (not only or picked(c["id"], only)) and not (skip and picked(c["id"], skip))]
    if RUN.get("changed_since"):
        n = len(changed_files(RUN["changed_since"]))
        print(f"--changed-since {RUN['changed_since']}: {n} file(s) changed")
    if listing:
        for c in sel:
            skip_note = unchanged_since(c, RUN["changed_since"]) if RUN.get("changed_since") else None
            print(c["id"], sorted(c["tags"]), "—", c["doc"].splitlines()[0] if c["doc"] else "",
                  f"· covers {len(c['covers'])} entries" if c.get("covers") else "· no covers (always runs)",
                  f"· SKIP {skip_note}" if skip_note else "")
        return
    take_lock()
    # run-phase.sh stops a phase with SIGINT, then SIGKILL; a SIGTERM must reach the `finally` too
    # (the fake's lines in elevenlabs.env, his engine).
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    # The band only moves while the display is awake (its CADisplayLink stops with the screen:
    # 2026-09-28 07:20, LC1 read `reveal` 0 for 1.8 s after ten idle minutes). Wake it, keep it up.
    if shutil.which("caffeinate"):
        subprocess.run(["caffeinate", "-u", "-t", "2"])
        subprocess.Popen(["caffeinate", "-dis", "-w", str(os.getpid())])
    try:
        t0 = get("/target") or {}
        RUN["bound0"] = t0.get("address") if t0.get("bound") else None
    except Exception:
        RUN["bound0"] = None
    try:
        eleven_setup()
        run(sel, report)
    finally:
        cleanup()
        witness_close()
        close_tabs_named("wt-witness")   # any orphan a case left, through the same kill → idle → close
        eleven_teardown()
        if RUN.get("t_start"):
            with open(report, "w") as f:
                f.write(render(RUN["results"], RUN["t_start"]))
        release_lock()

if __name__ == "__main__":
    main()
