#!/usr/bin/env python3
"""T-G — gestures and the tap (docs/test-plan.md §7.5), the [R] cases only.

Every gesture goes in through `POST /test/gesture` (the ⌃⌥⌘F-key chord Options+ makes for it), so
every case that makes one is tagged `gesture` and runs only under `hands-off` (HANDS_OFF=1). The
[S]/[D] cases (CGEvent scripts, devices, Codex) are not here.

The frame every case runs in (`G`):
- `POST /test/key-trace {"on": true}` at the start, `{"on": false}` at the end;
- the relay's recorder pointed at our own Loopback (`mic_override("WT Inject")`), silent unless a
  case plays a clip into it — no case opens the room's microphone;
- `WisprSink` opened and made key where the plan wants a front app that records stray keys, read
  with `GET /test/sink`, restored and closed at the end;
- after every gesture `state().sessionFlags == []` within 300 ms (T-G29's stale-modifier guard;
  the chord goes out 45 ms after the POST, so the first read is at +100 ms). A PASS with a stale
  flag is downgraded to FAIL. Bursts timed tighter than that (F10 train, 🔽/🔽→ at +60 ms, the
  stall) check once after the burst, and say so;
- at the end: nothing in flight (`/test/cancel`, then the settle waited out), nothing held for a
  bind (flushed into the witness `cat`), the engine back where it was, the sink restored.

Verdicts: PASS = the app does what the plan expects · BUG = the plan's predicted defect confirmed ·
FAIL = neither · SKIP = a precondition is not met (the note says which).

Opt-ins: `WT_COLD_WHISPER=kill` lets T-G3/4/41 SIGKILL a warm local helper to get the cold model
they need (default: SKIP when the model is warm or loading); `WT_ALLOW_SPAWN=1` lets T-G9 run (a
wrong prediction there spawns a real Claude Code window)."""
import os, re, sys, time, subprocess

# `harness.py` run as a script is `__main__`; a plain `import harness` would load a second copy with
# its own CASES (never read by the runner), its own WITNESS (never closed) and a second port probe.
# Alias the running script as `harness` first, so this module shares the runner's objects.
_runner = sys.modules.get("__main__")
if _runner is not None and os.path.basename(getattr(_runner, "__file__", "") or "") == "harness.py":
    sys.modules["harness"] = _runner

from harness import *  # noqa: E402,F401,F403 — the runner's vocabulary
from harness import (get, post, state, engine, log_mark, log_since, wait_for, gesture, mic_override,  # noqa: E402
                     bind_witness, unbind, witness_open, witness_clear, witness_text, WITNESS, osa, play,
                     loopback_alive, outbox_count, outbox_tail, CLIP_EN, WORK, case)


# ---------------------------------------------------------------- constants
INJECT = "WT Inject"                 # our own Loopback (never the Wispr teacher rig's device)
EL = ("eleven", "eleven-live")
RETRIGGER, DWELL, BACK_SETTLE = 0.6, 2.0, 0.8
FLAGS_WINDOW = 0.3
KEYCODE = {"forward-click": 98, "forward-right": 109, "forward-left": 103, "forward-up": 100,
           "forward-down": 101, "back-click": 97, "back-down": 111, "back-right": 96,
           "back-left": 99, "back-up": 118}
FKEY = {98: "F7", 109: "F10", 103: "F11", 100: "F8", 101: "F9", 97: "F6", 111: "F12", 96: "F5",
        99: "F3", 118: "F4"}

STRAY_RETURN = re.compile(r"⌨️ 🔽 → — Return\s*$", re.M)          # F5's bare-Return branch
OWN_STOP = "⌨️ 🔽 → — stopping the plain dictation (own engine)"
WISPR_STOP = "⌨️ 🔽 → — stopping the plain dictation; Return once its words land"
CLEAN_START_OWN = "back click — a clean dictation on the Engine (the start)"
CLEAN_START_WISPR = "back click — Wispr Flow's hands-free toggle (the start)"
BANKED = re.compile(r"dictate gesture with .* not ready — bringing it up")
RESUMED = re.compile(r"up after a gesture that had to wait — opening the microphone")


# ---------------------------------------------------------------- small helpers
def now():
    return time.perf_counter()

def sleep_until(t):
    d = t - now()
    if d > 0:
        time.sleep(d)

def st():
    """state(), or {} while the main thread does not answer (the route times out at 2 s)."""
    try:
        s = state()
        return s if "listening" in s else {}
    except Exception:
        return {}

def n(pattern, text):
    return len(re.findall(pattern, text, re.M))

def chip_text(s):
    return " | ".join(s.get("chip") or [])

def engine_id():
    try:
        return engine().get("engine")
    except Exception:
        return None

def whisper_info():
    try:
        return engine().get("whisper") or {}
    except Exception:
        return {}

def set_engine(eid):
    _, r = post("/engine", {"id": eid})
    return r.get("engine") == eid

def wispr_running():
    """Wispr Flow is up (its bundle id in LaunchServices' list — `pgrep -x` answers for the helper)."""
    try:
        out = subprocess.run(["/usr/bin/lsappinfo", "list"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return False
    return "com.electron.wispr-flow" in out

def sink_events():
    try:
        return get("/test/sink").get("events") or []
    except Exception:
        return []

def returns_in(evs):
    return [e for e in evs if e.get("route") == "keyDown" and any(c in (e.get("text") or "") for c in "\r\n")]

def fkeys_in(evs):
    """keyDowns carrying a function-key character (NSF1FunctionKey 0xF704 …)."""
    return [e for e in evs if e.get("route") == "keyDown"
            and any(0xF704 <= ord(c) <= 0xF74F for c in (e.get("text") or ""))]

def brief(evs):
    return [f"{e.get('route')}:{e.get('text', '')!r}" for e in evs][:8]

def wait_listening(timeout=6):
    return wait_for(lambda: st().get("listening"), timeout, 0.05)

def wait_mic(mark, timeout=8):
    return wait_for(lambda: "mic: recording through" in log_since(mark), timeout, 0.05)

def wait_stopped(mark, timeout=3):
    return wait_for(lambda: "🎙️ recording stopped" in log_since(mark), timeout, 0.03)

def wait_delivery(mark, timeout=40):
    return wait_for(lambda: "📦 delivery:" in log_since(mark), timeout, 0.2)

def need_el():
    e = engine_id()
    if e not in EL:
        return f"engine is {e!r}; the plan's gesture cases assume ElevenLabs ({' / '.join(EL)})"
    return None

def need_audio():
    try:
        return None if loopback_alive() else \
            "the 440 Hz pass-thru check on 🧪 WT Inject failed — toggle the device in Loopback"
    except Exception as e:
        return f"no Loopback / sounddevice: {type(e).__name__}: {e}"

def flush_held():
    """A sentence held for a bind is delivered into the witness (a `cat`) — never left behind."""
    bind_witness()
    wait_for(lambda: not st().get("awaitingBind", True), 10, 0.2)
    unbind()

def quiesce(timeout=45):
    """Nothing in flight: cancel an open sentence, wait out the settle / panel / delivery, flush a
    sentence held for a bind. A cancel in the settle does not stop the upload (§3 item 2), so the
    settle is waited for, not assumed."""
    end, cancels = time.time() + timeout, 0
    while time.time() < end:
        s = st()
        if not s:
            time.sleep(0.5)
            continue
        if s["listening"] or s["isRecording"] or s["speculative"]:
            if cancels < 4:
                post("/test/cancel")
                cancels += 1
            time.sleep(0.6)
            continue
        if s.get("awaitingBind"):
            flush_held()
            continue
        if not [w for w in (s.get("busyWhy") or []) if w != "held for a bind"]:
            return s
        time.sleep(0.4)
    s = st()
    print(f"    quiesce: still busy after {timeout}s: {s.get('busyWhy')}")
    return s

def cold_whisper(g):
    """None when the local model is cold (the precondition of T-G3/4/41); else why not."""
    w = whisper_info()
    if w.get("ready") or w.get("loading"):
        if os.environ.get("WT_COLD_WHISPER") != "kill":
            return (f"the local model is not cold (ready={w.get('ready')}, loading={w.get('loading')}) — "
                    "the case needs a cold model: relaunch the relay, or run with WT_COLD_WHISPER=kill")
        post("/test/whisper", {"kill": True})
        # T-L7: `ready` stays true on a dead helper until a request trips over the pipe — trip one.
        if not wait_for(lambda: not whisper_info().get("ready"), 1.5, 0.2):
            try:
                post("/test/local-fallback", {"wav": CLIP_EN}, timeout=30)
            except Exception:
                pass
        if not wait_for(lambda: not whisper_info().get("ready"), 5, 0.2):
            return "SIGKILL did not clear whisper.ready"
        g.notes.append("helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill)")
    return None

def to_whisper(g):
    g.engine0 = engine_id()
    return set_engine("whisper")

def bank_outcome(mark, limit=150):
    """After a banked gesture: ('opened', s) when the resumed start opened the microphone,
    ('dropped', s) when the model came up and 2.5 s later nothing had opened, or ('timeout', s)."""
    t, ready_at = now(), None
    while now() - t < limit:
        if RESUMED.search(log_since(mark)):
            return "opened", now() - t
        if ready_at is None and whisper_info().get("ready"):
            ready_at = now()
        if ready_at is not None and now() > ready_at + 2.5:
            return "dropped", now() - t
        time.sleep(0.25)
    return "timeout", now() - t


# ---------------------------------------------------------------- the frame of every case
class G:
    """Key trace, quiet microphone, the sink, the flags guard, and the way back."""

    def __init__(self, cid, sink=True):
        self.cid, self.want_sink, self.sink = cid, sink, False
        self.stale, self.notes, self.sent, self.after = [], [], [], []
        self.engine0 = None

    def __enter__(self):
        self.mark = log_mark()
        self.t0 = now()
        post("/test/key-trace", {"on": True})
        r = mic_override(INJECT)
        if INJECT.lower() not in str(r.get("override", "")).lower():
            self.notes.append(f"mic override not taken: {r}")
        if self.want_sink:
            post("/test/sink", {"on": True})
            time.sleep(0.3)
            self.key_sink()
        return self

    def key_sink(self):
        """(Re)make the sink the key window — after a witness tab has taken the front."""
        code, r = post("/test/sink", {"key": True})
        if code != 200:
            self.notes.append(f"sink refused the key window: {r.get('error', r)}")
        self.sink = True
        time.sleep(0.3)
        post("/test/sink/clear")

    def zero(self):
        """Offsets in the note are measured from here."""
        self.t0 = now()

    def step(self, name, check=True):
        t = now()
        gesture(name)
        self.sent.append((name, t - self.t0))
        if check:
            self.flags(name, t)
        return t

    def flags(self, label, t=None):
        """The stale-modifier guard (T-G29): `sessionFlags == []` within 300 ms of the step."""
        t = now() if t is None else t
        sleep_until(t + 0.1)
        seen = None
        while True:
            seen = st().get("sessionFlags")
            if seen == []:
                return True
            if now() > t + 0.1 + FLAGS_WINDOW:
                break
            time.sleep(0.03)
        self.stale.append(f"{label}: {seen}")
        return False

    def log(self):
        return log_since(self.mark)

    def done(self, verdict, msg):
        parts = [msg]
        if self.stale:
            parts.append("STALE modifiers after " + "; ".join(self.stale))
            if verdict == "PASS":
                verdict = "FAIL"
        if self.sent:
            parts.append("sent " + " ".join(f"{nm}@{t:.3f}s" for nm, t in self.sent))
        parts += self.notes
        return verdict, " · ".join(p for p in parts if p)

    def skip(self, why):
        return "SKIP", why

    def __exit__(self, *exc):
        def engine_back():
            if self.engine0 and engine_id() != self.engine0:
                quiesce(20)
                if not set_engine(self.engine0):
                    print(f"    {self.cid}: could not put the engine back to {self.engine0}")
        def sink_back():
            if self.sink:
                post("/test/sink", {"restore": True})
                time.sleep(0.2)
                post("/test/sink", {"on": False})
        steps = [quiesce] + list(self.after) + [engine_back, sink_back,
                                                 lambda: post("/test/key-trace", {"on": False})]
        for fn in steps:
            try:
                fn()
            except Exception as e:
                print(f"    {self.cid} cleanup: {type(e).__name__}: {e}")
        return False


def spoken(g, start="forward-right", stop="forward-right", after_play=1.0):
    """Start with `start`, play CLIP_EN into WT Inject, stop with `stop` (flags checked, ~0.13 s, so
    the next gesture still lands in the ~1.3 s upload). Returns the log mark, or None when the
    microphone never opened."""
    m = log_mark()
    g.step(start)
    if not wait_mic(m, 8):
        return None
    time.sleep(0.4)
    play(CLIP_EN)
    time.sleep(after_play)
    if stop:
        g.step(stop)
    return m

def hold_panel(g):
    """/test/dictation into the bound witness → the prompt panel. Returns seconds until `busyWhy`
    says `prompt on screen`, or None (autosend holds it 1 s)."""
    t = now()
    post("/test/dictation", {"text": f"walkie-talkie test plan {g.cid}: a held prompt, ignore it"})
    ok = wait_for(lambda: "prompt on screen" in (st().get("busyWhy") or []), 2.0, 0.02)
    return (now() - t) if ok else None

def witness_b_open():
    """A second witness (`cat` into its own file) for the rebind case."""
    path = WORK + "/witness-b.txt"
    open(path, "w").close()
    script = f"printf '\\\\e]0;wt-witness-b\\\\a'; stty -echo; exec cat >> {path}"
    tty = osa(f'tell application "Terminal" to set t to do script "{script}"',
              'tell application "Terminal" to get tty of t')
    time.sleep(0.8)
    _B_TTY[0] = tty.replace("/dev/", "")
    return _B_TTY[0], path

_B_TTY = [None]

def witness_b_close():
    """Kill the tab's `cat` first — Terminal will not close a window with a running process."""
    if _B_TTY[0]:
        subprocess.run(["pkill", "-t", _B_TTY[0]], capture_output=True)
        time.sleep(0.3)
        _B_TTY[0] = None
    osa('tell application "Terminal" to close (every window whose name contains "wt-witness-b") saving no')


# ================================================================ the cases
@case("TG1", tags=("gesture",),
      expect="🔼 F7 at idle opens a caret prompt (pasteMode, chip `at caret`). Predicted defect: the key "
             "trace is blind to it (no `↓ key 98` line — the F-key branches return nil, not swallow())")
def tg1():
    """F7 idle → caret prompt; the key trace does not see the swallow."""
    with G("TG1") as g:
        why = need_el()
        if why:
            return g.skip(why)
        t = g.step("forward-click")
        opened = wait_listening(6)
        dt = now() - t
        s, L = st(), g.log()
        chip = chip_text(s)
        caret = bool(s.get("pasteMode")) and "at caret" in chip
        clicked = "forward button — a dictation at the caret" in L
        downs = n(r"⌨️trace ↓ key 98 pid", L)
        ups = n(r"⌨️trace ↑ key 98 pid \d+ \(ours\)[^\n]*passed", L)
        msg = (f"listening={bool(opened)} {dt * 1000:.0f} ms after the POST, pasteMode={s.get('pasteMode')}, "
               f"chip «{chip[:90]}», trace ↓98×{downs}, ↑98 (ours) passed×{ups}")
        if not (opened and caret and clicked):
            return g.done("FAIL", "no caret prompt — " + msg)
        if downs == 0:
            return g.done("BUG", "caret prompt opened; the trace is blind to the swallowed F7 — " + msg)
        return g.done("PASS", msg)


@case("TG2", tags=("gesture",),
      expect="F10 train at 0/300/600/900 ms → one start and three `re-triggered … dropped`; at 1.6 s "
             "`only NNN ms old — not stopping`; at 2.3 s it stops. Predicted defect (R21): the 2 s dwell "
             "runs from the main-thread edge, so the 2.3 s stop is refused too")
def tg2():
    """F10 re-fire train, the sliding 0.6 s window and the 2 s dwell."""
    with G("TG2") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        t0 = now()
        for off in (0.0, 0.3, 0.6, 0.9, 1.6, 2.3):
            sleep_until(t0 + off)
            g.step("forward-right", check=False)
        sleep_until(t0 + 3.2)
        g.flags("after the F10 train (300 ms spacing, no per-step check)")
        s, L = st(), g.log()
        retrig = re.findall(r"F10 re-triggered (\d+)ms after", L)
        refused = re.findall(r"only (\d+)ms old — not stopping", L)
        starts = n(r"🎙️ recording started for", L) or n(r"mic: recording through", L)
        stopped = n(r"🎙️ recording stopped", L) > 0 or not s.get("listening")
        msg = (f"starts={starts}, re-triggered at {retrig} ms, refused at sentence ages {refused} ms, "
               f"stopped by +3.2 s={stopped}")
        if starts == 1 and len(retrig) == 3 and len(refused) == 1 and stopped:
            return g.done("PASS", msg)
        if starts == 1 and len(retrig) == 3 and len(refused) == 2 and not stopped:
            return g.done("BUG", f"the 2.3 s stop was refused as well (age {refused[-1]} ms < 2000: "
                                 "the dwell starts at the main-thread edge) — " + msg)
        return g.done("FAIL", msg)


def cold_open(g, name):
    """`name` on the cold local model with the flags checked after the fact, so the microphone's opening is
    timed from the gesture (not from the end of the 0.1–0.4 s flags check). (mark, opened, seconds, still cold)."""
    m = log_mark()
    t = g.step(name, check=False)
    opened = wait_mic(m, 3)
    dt = now() - t if opened else None
    cold = not whisper_info().get("ready")
    g.flags(name, t)
    return m, bool(opened), dt, cold


@case("TG3", tags=("gesture",),
      expect="🔼← F11 cancels a sentence opened on a cold local model: the gesture opens the microphone within 0.5 s "
             "while the model loads (2026-09-26 decision — nothing is banked), F11 cancels it, and nothing opens once "
             "the model is up. Before: the gesture was banked, F11 had nothing to cancel, the microphone opened ~10 s later")
def tg3():
    """F11 on a sentence opened against a cold model (Engine = whisper)."""
    with G("TG3") as g:
        why = need_el() or cold_whisper(g)
        if why:
            return g.skip(why)
        if not to_whisper(g):
            return g.done("FAIL", "POST /engine {id: whisper} was not taken")
        m, opened, dt, cold = cold_open(g, "forward-right")
        time.sleep(0.5)
        tc = g.step("forward-left")
        closed = wait_for(lambda: not st().get("listening") and not st().get("isRecording"), 3, 0.05)
        m2 = log_mark()
        up = wait_for(lambda: whisper_info().get("ready"), 90, 0.5)
        time.sleep(2.5)
        L = log_since(m)
        cancelled = "🗑️ dictation cancelled" in L
        reopened = "mic: recording through" in log_since(m2) or bool(st().get("listening"))
        banked = bool(BANKED.search(L))
        msg = (f"mic {'opened %.2f s after the gesture' % dt if opened else 'did not open in 3 s'} "
               f"(model still loading={cold}); cancel line={cancelled}, closed={bool(closed)} "
               f"(F11 at +{tc - g.t0:.2f} s); model up={bool(up)}, anything opened after it={reopened}; banked={banked}")
        if banked or reopened:
            return g.done("BUG", "the start outlived the cancel — " + msg)
        if opened and dt <= 0.5 and cold and cancelled and closed:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG4", tags=("gesture",),
      expect="🔽 click on a cold local model opens the microphone within 0.5 s as a clean dictation (context shot "
             "skipped), the second 🔽 click stops it, and the words arrive at the caret once the model is up. "
             "Before: the click was banked, the resumed start was a caret prompt with a context shot, and the second "
             "click was the shutter")
def tg4():
    """A back-click sentence on a cold model stays a clean one and is delivered when the model is up."""
    with G("TG4") as g:
        why = need_el() or need_audio() or cold_whisper(g)
        if why:
            return g.skip(why)
        if not to_whisper(g):
            return g.done("FAIL", "POST /engine {id: whisper} was not taken")
        g.key_sink()
        m, opened, dt, cold = cold_open(g, "back-click")
        if not opened:
            return g.done("FAIL", "the back click never opened the microphone (cold model)")
        time.sleep(0.4)
        play(CLIP_EN)
        time.sleep(0.8)
        L1 = log_since(m)
        started_clean = CLEAN_START_OWN in L1
        shot = "context screen captured" in L1
        skipped = "context screen skipped — a clean dictation" in L1
        m2 = log_mark()
        g.step("back-click")
        time.sleep(1.0)
        L2 = log_since(m2)
        stop = "(the stop)" in L2
        shutter = "📸 attached to in-flight dictation" in L2
        landed = wait_for(lambda: (st().get("lastDelivery") or {}).get("via") == "local-whisper"
                          and "📦 delivery:" in log_since(m2), 120, 0.3)
        time.sleep(1.0)
        s, evs = st(), sink_events()
        d = s.get("lastDelivery") or {}
        chars = sum(len(e.get("text") or "") for e in evs)
        waited = re.search(r"the local model came up ([\d.]+) s after the stop", log_since(m2))
        msg = (f"mic {'opened %.2f s after the click' % dt} (model still loading={cold}); clean start={started_clean}; "
               f"context shot captured={shot} skipped={skipped}; second click stop={stop} shutter={shutter}; "
               f"words {'waited %s s for the model, then ' % waited.group(1) if waited else ''}"
               f"{'landed' if landed else 'did NOT land'}: to={d.get('to')} via={d.get('via')}, sink got {chars} chars")
        if shot and shutter and not stop:
            return g.done("BUG", "the start was a caret prompt — " + msg)
        # No picture is the criterion: on the own engine a clean sentence is booked without ever reaching
        # `captureContext`, so its `context screen skipped` line exists only on Wispr's path.
        if dt <= 0.5 and cold and started_clean and not shot and stop and landed and d.get("to") == "caret" and chars > 0:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


def back_pair(g, gap):
    """🔽 then 🔽→ `gap` s later, the sink in front. Returns (log, sink events, state 1 s on, gap sent)."""
    post("/test/sink/clear")
    m = log_mark()
    t1 = g.step("back-click", check=False)
    sleep_until(t1 + gap)
    t2 = g.step("back-right", check=False)
    sleep_until(t1 + gap + 1.0)
    s = st()
    g.flags(f"🔽/🔽→ +{gap * 1000:.0f} ms (checked after the pair)")
    return log_since(m), sink_events(), s, t2 - t1

def wispr_quiet(g, timeout=15):
    """Wait for Wispr's microphone to close; cancel, then dismiss (🔽←) if it stays open."""
    if wait_for(lambda: not st().get("wisprHearing", True), timeout, 0.25):
        return True
    post("/test/cancel")
    if wait_for(lambda: not st().get("wisprHearing", True), 4, 0.25):
        return True
    g.step("back-left")
    return bool(wait_for(lambda: not st().get("wisprHearing", True), 6, 0.25))


@case("TG6", tags=("gesture",),
      expect="🔽 then 🔽→ on ElevenLabs stops the clean sentence at both gaps. Predicted defect (R21): at "
             "+60 ms the tap has not heard of the sentence yet — `🔽 → — Return`, keycode 36 in the sink, the "
             "sentence still open; at +500 ms the correct stop")
def tg6():
    """🔽 then 🔽→ at +60 ms / +500 ms on the relay's own engine."""
    with G("TG6") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        LA, evA, sA, gapA = back_pair(g, 0.06)
        quiesce(30)
        time.sleep(BACK_SETTLE + 0.2)
        LB, evB, sB, gapB = back_pair(g, 0.5)
        startA, startB = CLEAN_START_OWN in LA, CLEAN_START_OWN in LB
        strayA, strayB = bool(STRAY_RETURN.search(LA)), bool(STRAY_RETURN.search(LB))
        stopA, stopB = OWN_STOP in LA, OWN_STOP in LB
        retA, retB = returns_in(evA), returns_in(evB)
        msg = (f"+{gapA * 1000:.0f} ms: stray Return={strayA}, stop={stopA}, sink Returns={len(retA)}, "
               f"open 1 s on={sA.get('listening')} · +{gapB * 1000:.0f} ms: stray Return={strayB}, "
               f"stop={stopB}, sink Returns={len(retB)}, open 1 s on={sB.get('listening')}")
        if not (startA and startB):
            return g.done("FAIL", "the back click did not start a clean sentence on the Engine — " + msg)
        if strayA and stopB and not strayB:
            return g.done("BUG", "the +60 ms 🔽→ typed a Return and left the sentence open — " + msg)
        if stopA and stopB and not strayA and not strayB:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG7", tags=("gesture",),
      expect="the same 🔽/🔽→ pair on Engine = wispr stops Wispr's sentence at +60 ms and at +500 ms (the arm "
             "is set on the tap thread — the asymmetry with T-G6)")
def tg7():
    """🔽 then 🔽→ at +60 ms / +500 ms on Engine = wispr."""
    with G("TG7") as g:
        why = need_el()
        if why:
            return g.skip(why)
        if not wispr_running():
            return g.skip("Wispr Flow is not running — its chord would reach macOS instead (T-G42)")
        g.engine0 = engine_id()
        if not set_engine("wispr"):
            return g.done("FAIL", "POST /engine {id: wispr} was not taken")
        g.zero()
        LA, evA, sA, gapA = back_pair(g, 0.06)
        quietA = wispr_quiet(g)
        quiesce(30)
        time.sleep(BACK_SETTLE + 0.2)
        LB, evB, sB, gapB = back_pair(g, 0.5)
        quietB = wispr_quiet(g)
        startA, startB = CLEAN_START_WISPR in LA, CLEAN_START_WISPR in LB
        okA = WISPR_STOP in LA and not STRAY_RETURN.search(LA)
        okB = WISPR_STOP in LB and not STRAY_RETURN.search(LB)
        msg = (f"+{gapA * 1000:.0f} ms: stop branch={okA}, sink {brief(evA)} · +{gapB * 1000:.0f} ms: "
               f"stop branch={okB}, sink {brief(evB)} · Wispr closed after each: {quietA}/{quietB}")
        if not (startA and startB):
            return g.done("FAIL", "the back click did not post Wispr's start — " + msg)
        return g.done("PASS" if okA and okB else "FAIL", msg)


@case("TG8", tags=("gesture", "audio"),
      expect="🔼← F11 in the settle throws the sentence away. Predicted defect (§3.2, R2): `🗑️ Cancelled`, "
             "then the words are delivered anyway (`📦 delivery` after the cancel line)")
def tg8():
    """Cancel in the settle still delivers."""
    with G("TG8", sink=False) as g:
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        bind_witness()
        witness_clear()
        m = spoken(g)
        if m is None:
            return g.done("FAIL", "the microphone never opened")
        if not wait_stopped(m):
            return g.done("FAIL", "the F10 stop did not land")
        early = "📦 delivery:" in log_since(m)
        g.step("forward-left")
        wait_for(lambda: "📦 delivery:" in log_since(m) or not st().get("busy", True), 40, 0.3)
        time.sleep(1.5)
        L, s = log_since(m), st()
        ic, idl = L.find("🗑️ dictation cancelled"), L.find("📦 delivery:")
        msg = (f"cancel line={ic >= 0}, lastDelivery={s.get('lastDelivery')}, "
               f"witness got {len(witness_text())} chars")
        if early or (idl >= 0 and ic >= 0 and idl < ic):
            return g.done("FAIL", "the words landed before the cancel — the race was lost, inconclusive · " + msg)
        if ic >= 0 and idl > ic:
            return g.done("BUG", "cancelled, then delivered — " + msg)
        if ic >= 0 and idl < 0:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG9", tags=("gesture", "audio"),
      expect="F11 in the settle of a spawn sentence throws it away. Predicted defect: delivered anyway, and "
             "to the bound terminal / caret, not `spawn:` (the cancel cleared the spawn flag only)")
def tg9():
    """Cancel in the settle of a spawn still delivers — elsewhere."""
    with G("TG9", sink=False) as g:
        if os.environ.get("WT_ALLOW_SPAWN") != "1":
            return g.skip("a wrong prediction spawns a real Claude Code window — run with WT_ALLOW_SPAWN=1")
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        bind_witness()
        witness_clear()
        m = spoken(g, start="forward-up")
        if m is None:
            return g.done("FAIL", "the microphone never opened")
        if not wait_stopped(m):
            return g.done("FAIL", "the F10 stop did not land")
        early = "📦 delivery:" in log_since(m)
        g.step("forward-left")
        wait_for(lambda: "📦 delivery:" in log_since(m) or not st().get("busy", True), 40, 0.3)
        time.sleep(1.5)
        L, s = log_since(m), st()
        to = (s.get("lastDelivery") or {}).get("to", "")
        ic, idl = L.find("🗑️ dictation cancelled"), L.find("📦 delivery:")
        msg = f"cancel line={ic >= 0}, delivered after it={idl > ic >= 0}, to={to!r}"
        if early:
            return g.done("FAIL", "the words landed before the cancel — inconclusive · " + msg)
        if ic >= 0 and idl > ic and not to.startswith("spawn:"):
            return g.done("BUG", msg)
        if ic >= 0 and idl < 0:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG10", tags=("gesture",),
      expect="🔼← F11 while the prompt panel is held cancels it (`✕ cancelled`, no outbox row). Predicted "
             "defect: nothing — the panel sends at the end of its hold")
def tg10():
    """F11 does not cancel the held panel."""
    with G("TG10") as g:
        bind_witness()
        g.key_sink()
        c0, m = outbox_count(), log_mark()
        g.zero()
        up = hold_panel(g)
        if up is None:
            return g.skip(f"the prompt panel was never seen (autosend={st().get('autosend')}, 1 s hold)")
        t = g.step("forward-left")
        time.sleep(2.5)
        L, c1 = log_since(m), outbox_count()
        cancelled, sent = "✕ cancelled —" in L, c1 > c0
        msg = (f"panel up {up * 1000:.0f} ms after /test/dictation, F11 at +{t - g.t0:.3f} s; outbox +{c1 - c0}, "
               f"✕ cancelled={cancelled}, autosend={st().get('autosend')}")
        if sent and not cancelled:
            return g.done("BUG", msg)
        if cancelled and not sent:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG11", tags=("gesture",),
      expect="🔽→ while the panel is held is not the panel's ⏎ (its Return is stamped ours). Predicted defect: "
             "the ⏎ branch ignores the stamp — trace `SWALLOWED by the prompt panel's ⏎` on key 36 (ours), panel sent")
def tg11():
    """🔽→ sends the held panel."""
    with G("TG11") as g:
        bind_witness()
        g.key_sink()
        c0, m = outbox_count(), log_mark()
        g.zero()
        up = hold_panel(g)
        if up is None:
            return g.skip(f"the prompt panel was never seen (autosend={st().get('autosend')}, 1 s hold)")
        t = g.step("back-right", check=False)
        sent = wait_for(lambda: outbox_count() > c0, 3, 0.02)
        sent_ms = (now() - t) * 1000
        g.flags("back-right (checked after the outbox poll)", t)
        time.sleep(0.5)
        L, evs = log_since(m), sink_events()
        swallowed = re.search(r"⌨️trace ↓ key 36 pid \d+ \(ours\)[^\n]*SWALLOWED by the prompt panel's ⏎", L)
        passed = re.search(r"⌨️trace ↓ key 36 pid \d+ \(ours\)[^\n]*— passed", L)
        msg = (f"panel up {up * 1000:.0f} ms after /test/dictation; outbox row "
               f"{'%.0f ms after the 🔽→' % sent_ms if sent else 'never'}; trace: swallowed by the panel="
               f"{bool(swallowed)}, passed={bool(passed)}; sink Returns={len(returns_in(evs))}; "
               f"autosend={st().get('autosend')}")
        if swallowed:
            return g.done("BUG", msg)
        if passed or returns_in(evs):
            return g.done("PASS", msg)
        return g.done("FAIL", "no key-36 trace line — 🔽→ took another branch · " + msg)


@case("TG12", tags=("gesture", "audio"),
      expect="clean-submit Return eaten by another panel → words in the sink, no 36; panel A sent early")
def tg12():
    """Clean-submit Return eaten by another sentence's panel — not automated."""
    return ("SKIP", "needs sentence A's panel held while a clean sentence B settles with its queued Return; two "
                    "overlapping sentences cannot be staged deterministically from one Loopback — run by hand")


@case("TG13", tags=("gesture", "audio"),
      expect="🔼→ over a bound clean sentence redirects it: `↪️ redirected` and `lastDelivery.to == terminal:…`. "
             "Predicted defect: the flash says so but the clean sentence still lands at the caret")
def tg13():
    """🔼→ over a bound clean sentence: the redirect flash lies."""
    with G("TG13") as g:
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        bind_witness()
        tty = WITNESS["tty"]
        g.key_sink()
        m = spoken(g, start="back-click", stop=None, after_play=0.5)
        if m is None:
            return g.done("FAIL", "the back click never opened the microphone")
        g.step("forward-right")
        redirected = wait_for(lambda: "↪️ redirected mid-sentence" in log_since(m), 3, 0.05)
        time.sleep(BACK_SETTLE + 0.2)
        g.step("back-click")
        wait_delivery(m, 40)
        time.sleep(1.0)
        s, evs = st(), sink_events()
        to = (s.get("lastDelivery") or {}).get("to", "")
        msg = (f"redirect line={bool(redirected)}, lastDelivery.to={to!r} (bound {tty}), "
               f"sink got {sum(len(e.get('text') or '') for e in evs)} chars")
        if redirected and to == "caret":
            return g.done("BUG", msg)
        if redirected and to.endswith(tty or "?"):
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG14", tags=("gesture",),
      expect="a kamikaze flick that re-fires (+2.5 s / +2.8 s) toggles once. Predicted defect: F9 has no "
             "re-fire guard — on, then `taken back`")
def tg14():
    """Kamikaze re-fire untoggles."""
    with G("TG14") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        m = log_mark()
        t0 = g.step("forward-right")
        if not wait_mic(m, 8):
            return g.done("FAIL", "the dictation never opened")
        sleep_until(t0 + 2.5)
        g.step("forward-down", check=False)
        sleep_until(t0 + 2.8)
        g.step("forward-down", check=False)
        time.sleep(0.8)
        g.flags("after the two F9 (300 ms apart, checked after)")
        L, s = log_since(m), st()
        on = n(r"☠️ kamikaze — this sentence closes its agent when done", L)
        off = n(r"☠️ kamikaze taken back", L)
        row = "kamikaze" in chip_text(s).lower()
        msg = f"on×{on}, taken back×{off}, chip row={row}"
        if on >= 1 and off >= 1 and not row:
            return g.done("BUG", msg)
        if on == 1 and off == 0 and row:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG15", tags=("gesture",),
      expect="a film flick that re-fires (+2.5 s / +2.8 s) starts one recording. Predicted defect: F4 has no "
             "re-fire guard — start then stop (`caught no frames` / a few frames)")
def tg15():
    """Film re-fire → start + stop."""
    with G("TG15") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        m = log_mark()
        t0 = g.step("forward-right")
        if not wait_mic(m, 8):
            return g.done("FAIL", "the dictation never opened")
        sleep_until(t0 + 2.5)
        g.step("back-up", check=False)
        sleep_until(t0 + 2.8)
        g.step("back-up", check=False)
        time.sleep(0.8)
        g.flags("after the two F4 (300 ms apart, checked after)")
        L, s = log_since(m), st()
        started = n(r"🎬 recording display", L)
        stop = re.search(r"🎬 recording stopped — (\d+) frames over ([\d.]+)s", L)
        filming = s.get("filming")
        msg = (f"film started×{started}, stopped={stop.group(0) if stop else None}, filming={filming}, "
               f"chip «{chip_text(s)[:80]}»")
        if started and (stop or "caught no frames" in chip_text(s)) and not filming:
            return g.done("BUG", msg)
        if started == 1 and not stop and filming:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG16", tags=("gesture",),
      expect="🔼↓ F9 while the panel is held (words not yet committed) marks that prompt kamikaze. Predicted "
             "defect: `☠️ kamikaze gesture with no sentence in flight — ignored`")
def tg16():
    """F9 during the panel is ignored."""
    with G("TG16") as g:
        bind_witness()
        g.key_sink()
        c0, m = outbox_count(), log_mark()
        g.zero()
        up = hold_panel(g)
        if up is None:
            return g.skip(f"the prompt panel was never seen (autosend={st().get('autosend')}, 1 s hold)")
        g.step("forward-down")
        time.sleep(2.5)
        L = log_since(m)
        ignored = "☠️ kamikaze gesture with no sentence in flight — ignored" in L
        kam = False
        if outbox_count() > c0:
            try:
                tail = outbox_tail(1)[0]
                kam = "kamikaze" in ((tail.get("line") or "") + (tail.get("text") or "")).lower()
            except Exception:
                pass
        msg = f"panel up {up * 1000:.0f} ms; ignored line={ignored}; sent prompt carries kamikaze={kam}"
        if ignored and not kam:
            return g.done("BUG", msg)
        if kam:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG17", tags=("gesture",),
      expect="🔼↑ F8 on a caret sentence is refused visibly (a log line / flash), not converted. Predicted "
             "defect: silent — `convertDictationToSpawn` returns false with no word")
def tg17():
    """F8 on a caret sentence is silent."""
    with G("TG17") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.step("forward-click")
        if not wait_listening(6):
            return g.done("FAIL", "the caret sentence never opened")
        s0 = st()
        m = log_mark()
        g.step("forward-up")
        time.sleep(1.0)
        s1 = st()
        lines = [l for l in log_since(m).splitlines()
                 if "⌨️trace" not in l and "POST /test/gesture" not in l
                 and re.search(r"spawn|✨|🔼 ↑|F8|refus|ignored|convert", l)]
        new_rows = [r for r in (s1.get("chip") or []) if r not in (s0.get("chip") or [])
                    and re.search(r"spawn|✨|refus|ignor|session|folder", r, re.I)]   # not the running clock
        converted = bool(s1.get("spawnPending"))
        msg = (f"spawnPending={converted}, pasteMode={s1.get('pasteMode')}, log {lines[:3]}, "
               f"new chip rows {new_rows[:3]}")
        if converted:
            return g.done("FAIL", "the caret sentence was converted into a spawn — " + msg)
        if not lines and not new_rows and s1.get("pasteMode"):
            return g.done("BUG", msg)
        return g.done("PASS", msg)


@case("TG18", tags=("gesture", "audio"),
      expect="an unbound sentence bound during its upload goes to the terminal just bound. Predicted defect "
             "(§3.3): the chip said `bind to send`, the destination latched at mic close, `lastDelivery.to == caret`")
def tg18():
    """Bind during the upload → still pasted at the caret."""
    with G("TG18") as g:
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        tty = witness_open()
        g.key_sink()
        m = log_mark()
        g.step("forward-right")
        if not wait_mic(m, 8):
            return g.done("FAIL", "the microphone never opened")
        time.sleep(0.4)
        chip = chip_text(st())
        play(CLIP_EN)
        time.sleep(1.0)
        g.step("forward-right")
        if not wait_stopped(m):
            return g.done("FAIL", "the F10 stop did not land")
        early = "📦 delivery:" in log_since(m)
        bind_witness()
        wait_delivery(m, 40)
        wait_for(lambda: (st().get("lastDelivery") or {}).get("to", "").startswith(("terminal:", "caret")), 10, 0.3)
        s = st()
        to = (s.get("lastDelivery") or {}).get("to", "")
        msg = f"chip at the start «{chip[:60]}»; lastDelivery.to={to!r} (bound {tty} during the upload)"
        if early:
            return g.done("FAIL", "delivered before the bind landed — inconclusive · " + msg)
        if to == "caret":
            return g.done("BUG", msg)
        if to.endswith(tty):
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG19", tags=("tty",),
      expect="a rebind to B while A's prompt panel is held: the plan's documents imply A (the panel shows A). "
             "Predicted defect (R11): `commit` reads the target at commit time — delivered to B")
def tg19():
    """Rebind during the panel → delivered to B."""
    with G("TG19") as g:
        bind_witness()
        tty_a = WITNESS["tty"]
        tty_b, path_b = witness_b_open()
        g.after.append(witness_b_close)
        g.key_sink()
        c0, m = outbox_count(), log_mark()
        g.zero()
        up = hold_panel(g)
        if up is None:
            return g.skip(f"the prompt panel was never seen (autosend={st().get('autosend')}, 1 s hold)")
        tb = now()
        post("/bind", {"tty": tty_b})
        wait_for(lambda: outbox_count() > c0, 5, 0.05)
        time.sleep(0.8)
        to = (st().get("lastDelivery") or {}).get("to", "")
        b_chars = len(open(path_b, encoding="utf-8", errors="replace").read())
        msg = (f"panel up {up * 1000:.0f} ms, rebind at +{tb - g.t0:.3f} s; lastDelivery.to={to!r} "
               f"(A={tty_a}, B={tty_b}); B's witness got {b_chars} chars")
        if to.endswith(tty_b):
            return g.done("BUG", msg)
        if to.endswith(tty_a):
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG20", tags=("gesture", "audio"),
      expect="🔽↓ F12 (unbind) in the settle → the words still land in the terminal latched at the close "
             "(Victor's Q2, 2026-09-26: an unbind after the latch does not hold the sentence); nothing held")
def tg20():
    """F12 during the settle. Until 2026-09-26 the expectation was *held for the next bind*; Q2 latches the
    whole recipient at the close, so the case now asserts the sentence reaches the unbound witness."""
    with G("TG20") as g:
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        bind_witness()
        tty = WITNESS["tty"]
        g.key_sink()
        witness_clear()
        m = spoken(g)
        if m is None:
            return g.done("FAIL", "the microphone never opened")
        if not wait_stopped(m):
            return g.done("FAIL", "the F10 stop did not land")
        early = "📦 delivery:" in log_since(m)
        g.step("back-down")
        unbound = wait_for(lambda: st().get("bound") is None, 3, 0.05)
        wait_delivery(m, 40)
        time.sleep(0.8)
        s1 = st()
        to1, held1 = (s1.get("lastDelivery") or {}).get("to", ""), s1.get("awaitingBind")
        chars = len(witness_text())
        msg = (f"unbound by F12={bool(unbound)}; after it: to={to1!r}, awaitingBind={held1}, "
               f"bound={s1.get('bound')}; witness {chars} chars")
        if early:
            return g.done("FAIL", "delivered before the unbind landed — inconclusive · " + msg)
        if unbound and to1.endswith(tty) and not held1 and chars > 0:
            return g.done("PASS", msg)
        if to1 == "held" and held1:
            return g.done("BUG", "held by an unbind after the close (Q2 says: the latched terminal) · " + msg)
        return g.done("FAIL", msg)


def _adopted(n_):
    return ("SKIP", f"T-G{n_}: adopted hand-started Wispr sentences (`/test/wispr-handsfree {{hand: true}}`) are out "
                    "of scope for this suite (Wispr Flow is out of scope of the plan) — not automated here")

@case("TG21", expect="adopted Wispr sentence: 🔽← → `nothing to cancel`, Wispr keeps listening")
def tg21():
    """Adopted Wispr: 🔽← — out of scope."""
    return _adopted(21)

@case("TG22", expect="adopted Wispr sentence: 🔽 → shutter")
def tg22():
    """Adopted Wispr: 🔽 — out of scope."""
    return _adopted(22)

@case("TG23", expect="adopted Wispr sentence: 🔽→ → keycode 36 in the sink while `wisprHearing`")
def tg23():
    """Adopted Wispr: 🔽→ — out of scope."""
    return _adopted(23)

@case("TG24", expect="adopted Wispr sentence: 🔼 / 🔼→ → nothing")
def tg24():
    """Adopted Wispr: 🔼 / 🔼→ — out of scope."""
    return _adopted(24)


@case("TG25", tags=("gesture", "stall"),
      expect="main stalled 8 s: an F10 at +1.0 s is queued (acts after the stall); at +4.5 s the tap is failing "
             "open. Expected: a ⌃⌥⌘F-key never reaches the front app. Predicted defect: it leaks — the sink "
             "records ⌃⌥⌘F10 (`🧊 main thread silent`, trace `failing open`)")
def tg25():
    """Stall: F10 queued at +1.0 s, leaked at +4.5 s."""
    with G("TG25") as g:
        why = need_el()
        if why:
            return g.skip(why)
        post("/test/sink/clear")
        g.zero()
        post("/test/stall", {"seconds": 8})
        t0 = now()
        sleep_until(t0 + 1.0)
        g.step("forward-right", check=False)
        sleep_until(t0 + 4.5)
        g.step("forward-right", check=False)
        sleep_until(t0 + 9.0)                 # no GET /test/state inside the stall
        time.sleep(0.8)                       # the main thread drains its queue
        g.flags("after the stall")
        L, s, evs = g.log(), st(), sink_events()
        stalled = "🧊 /test/stall: blocking" in L
        opened = "🧊 main thread silent" in L
        leaked_trace = re.search(r"⌨️trace ↓ key 109 pid [^\n]*failing open", L) is not None
        fk = fkeys_in(evs)
        queued = n(r"🎙️ recording started for", L) > 0 or bool(s.get("listening"))
        msg = (f"stall line={stalled}, 🧊 opened={opened}, trace ↓F10 failing open={leaked_trace}, sink "
               f"F-keys {brief(fk)}, the +1.0 s F10 acted after the stall={queued}")
        if not (stalled and opened):
            return g.done("FAIL", "the fail-open never opened — " + msg)
        if fk or leaked_trace:
            return g.done("BUG", msg)
        return g.done("PASS", msg)


@case("TG26", tags=("gesture", "stall"),
      expect="the canary during fail-open says the tap is alive (it is — it is failing open on purpose). "
             "Predicted defect: `alive:false` (misdiagnosis), and its V keyUp passes to the front app")
def tg26():
    """Canary during fail-open → alive:false."""
    with G("TG26") as g:
        post("/test/sink/clear")
        g.zero()
        post("/test/stall", {"seconds": 8})
        t0 = now()
        sleep_until(t0 + 4.5)
        code, r = post("/test/firewall", {})     # no "on": the canary alone
        sleep_until(t0 + 9.0)
        time.sleep(0.8)
        g.flags("after the stall")
        L = g.log()
        opened = "🧊 main thread silent" in L
        misdiag = "the tap did NOT see its own event" in L
        v_trace = re.search(r"⌨️trace ↑ key 9 pid [^\n]*failing open", L) is not None
        msg = (f"POST /test/firewall at +4.5 s → {code} alive={r.get('alive')} canaryMs={r.get('canaryMs')}; "
               f"🧊 opened={opened}; `did NOT see` line={misdiag}; trace ↑V failing open={v_trace} "
               "(the sink records keyDowns only, so the keyUp is read off the trace)")
        if not opened:
            return g.done("FAIL", "the fail-open never opened — " + msg)
        if r.get("alive") is False:
            return g.done("BUG", msg)
        if r.get("alive") is True:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


def tour(g):
    """The ten chords, each once, each made harmless: four at idle (🔽→ types a Return into the sink,
    🔼← and 🔽↓ find nothing, 🔼↓ is ignored), then a caret sentence (🔼) in which 🔼→ is refused by the
    dwell, 🔼↑ is refused on a caret sentence, 🔽↑ films, 🔽 is the shutter and 🔽← cancels it."""
    for name in ("back-right", "forward-left", "back-down", "forward-down"):
        g.step(name)
        time.sleep(0.6)
    g.step("forward-click")
    if not wait_listening(6):
        g.notes.append("the caret sentence never opened — the in-sentence half ran against idle")
    g.step("forward-right")
    time.sleep(0.4)
    for name in ("forward-up", "back-up", "back-click"):
        g.step(name)
        time.sleep(0.7)
    g.step("back-left")
    wait_for(lambda: not st().get("listening", True), 5, 0.1)


@case("TG28", tags=("gesture",),
      expect="every gesture's keyDown is in the key trace with its verdict (`↓ key N … SWALLOWED by …`). Predicted "
             "defect: blindness for all ten — zero `↓`, one `↑ (ours) passed` each")
def tg28():
    """Key-trace blindness for all ten gestures."""
    with G("TG28") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        tour(g)
        L = g.log()
        rows = []
        for name, k in KEYCODE.items():
            d = n(rf"⌨️trace ↓ key {k} pid", L)
            sw = n(rf"⌨️trace ↓ key {k} pid [^\n]*SWALLOWED", L)
            u = n(rf"⌨️trace ↑ key {k} pid \d+ \(ours\)[^\n]*passed", L)
            rows.append((name, k, d, sw, u))
        table = ", ".join(f"{nm} {FKEY[k]} ↓{d}/{sw}sw ↑{u}" for nm, k, d, sw, u in rows)
        blind = [r for r in rows if r[2] == 0 and r[4] >= 1]
        seen = [r for r in rows if r[3] >= 1]
        if len(blind) == len(rows):
            return g.done("BUG", "all ten blind — " + table)
        if len(seen) == len(rows):
            return g.done("PASS", table)
        return g.done("FAIL", table)


@case("TG29", tags=("gesture",),
      expect="`sessionFlags == []` within 300 ms after every gesture and after the app's own posters "
             "(`postReturn` via 🔽→ at idle; `postWisprHandsFree` / `postWisprCancel` when Wispr runs)")
def tg29():
    """Stale-modifier guard for every gesture and the three posters."""
    with G("TG29") as g:
        why = need_el()
        if why:
            return g.skip(why)
        g.zero()
        tour(g)
        wispr = "Wispr posters skipped (Wispr Flow not running — its chord would reach macOS, T-G42)"
        if wispr_running() and not st().get("wisprHearing"):
            def handsfree(label):
                t = now()
                post("/test/wispr-handsfree", {})     # plain: the relay's own post of fn ⌃ Space
                g.sent.append((label, t - g.t0))
                g.flags(label, t)
            handsfree("postWisprHandsFree (start)")
            if wait_for(lambda: st().get("wisprHearing"), 8, 0.2):
                m = log_mark()
                g.step("back-left")               # foreign Wispr sentence → postWisprCancel
                time.sleep(0.8)
                dismissed = "dismissing Wispr Flow's dictation" in log_since(m)
                closed = wait_for(lambda: not st().get("wisprHearing", True), 4, 0.2)
                if not closed:
                    handsfree("postWisprHandsFree (stop)")
                    closed = wispr_quiet(g, 8)
                wispr = (f"postWisprHandsFree exercised; postWisprCancel "
                         f"{'exercised' if dismissed else 'not reached (🔽← took the relay-cancel branch)'}; "
                         f"Wispr closed={bool(closed)}")
            else:
                wispr = "postWisprHandsFree posted but Wispr's microphone never opened — postWisprCancel not exercised"
        checks = len(g.sent)
        if g.stale:
            return g.done("FAIL", f"{len(g.stale)} of {checks} steps left a modifier held · {wispr}")
        return g.done("PASS", f"{checks} steps, every one bare within 300 ms · {wispr}")


@case("TG30", tags=("gesture",),
      expect="a `/test/gesture` 200 is backed by the tap's own log line (the installed build posts for real). "
             "Predicted defect on a debug build: 200 with no effect — so every assertion reads the log, never the 200")
def tg30():
    """Debug-build guard: the 200 alone proves nothing."""
    with G("TG30") as g:
        if not os.environ.get("HANDS_OFF"):
            raise RuntimeError("gesture outside hands-off")
        s = st()
        pid = s.get("pid")
        try:
            comm = subprocess.run(["/bin/ps", "-o", "comm=", "-p", str(pid)], capture_output=True,
                                  text=True, timeout=5).stdout.strip()
        except Exception as e:
            comm = f"? ({e})"
        m = log_mark()
        t = now()
        code, r = post("/test/gesture", {"name": "forward-down"})
        g.sent.append(("forward-down", t - g.t0))
        g.flags("forward-down", t)
        effect = wait_for(lambda: "☠️ kamikaze gesture with no sentence in flight — ignored" in log_since(m), 2, 0.05)
        up = re.search(r"⌨️trace ↑ key 101 pid \d+ \(ours\)", log_since(m)) is not None
        msg = f"HTTP {code} {r.get('posted')}; effect line={bool(effect)}; tap saw the keyUp={up}; relay binary {comm}"
        if code == 200 and effect:
            return g.done("PASS", msg)
        if code == 200 and not effect:
            return g.done("BUG", "200 with no effect — every gesture verdict of this run is suspect · " + msg)
        return g.done("FAIL", msg)


@case("TG36", tags=("gesture",),
      expect="undefined in the plan: 🔽→ with the *Rebind to…* panel up. Predicted: its Return activates the "
             "selected row (the witness is re-bound)")
def tg36():
    """🔽→ with the rebind panel up activates the selected row."""
    with G("TG36", sink=False) as g:
        why = need_el()
        if why:
            return g.skip(why)
        bind_witness()
        tty = WITNESS["tty"]
        unbind()                              # the witness is now an enabled history row
        time.sleep(0.5)
        post("/test/rebind-panel", {"query": tty})   # a tty only the witness's row carries: row 0
        time.sleep(1.0)
        m = log_mark()
        g.step("back-right")
        time.sleep(1.5)
        b = st().get("bound") or {}
        activated = bool(b) and str(b.get("tty", "")).endswith(tty)
        if not activated:
            post("/test/rebind-panel", {"query": ""})    # the row is a toggle: this closes it
        L = log_since(m)
        msg = (f"bound after 🔽→ = {b.get('tty') if b else None} (witness {tty}); "
               f"`🔽 → — Return` line={bool(STRAY_RETURN.search(L))}")
        if activated:
            return g.done("BUG", "the gesture's Return activated the panel's row — " + msg)
        return g.done("PASS", "the panel's row was not activated · " + msg)


@case("TG40", tags=("gesture", "audio"),
      expect="🔽 in the settle of a relay prompt says the words are in flight (or nothing). Predicted defect: "
             "the misleading `Back click ignored — finish the sentence you are dictating first` banner")
def tg40():
    """F6 in the settle → the misleading banner."""
    with G("TG40") as g:
        why = need_el() or need_audio()
        if why:
            return g.skip(why)
        bind_witness()
        g.key_sink()
        m = spoken(g)
        if m is None:
            return g.done("FAIL", "the microphone never opened")
        if not wait_stopped(m):
            return g.done("FAIL", "the F10 stop did not land")
        early = "📦 delivery:" in log_since(m)
        g.step("back-click")
        s_at = st()
        wait_delivery(m, 40)
        time.sleep(1.0)
        L = log_since(m)
        ir = L.find("back click refused — the relay's own engine is mid-sentence")
        idl = L.find("📦 delivery:")
        new_sentence = n(r"mic: recording through", L) > 1
        msg = (f"refused line={ir >= 0} (before the delivery={0 <= ir < idl if idl >= 0 else ir >= 0}), "
               f"state just after: listening={s_at.get('listening')} settling={s_at.get('settling')}, "
               f"a new sentence opened={new_sentence}")
        if early:
            return g.done("FAIL", "delivered before the back click — inconclusive · " + msg)
        if ir >= 0 and (idl < 0 or ir < idl):
            return g.done("BUG", msg)
        if ir < 0 and not new_sentence:
            return g.done("PASS", msg)
        return g.done("FAIL", msg)


@case("TG41", tags=("gesture",),
      expect="an engine switch mid-sentence on a cold local model is refused like any other: the gesture opened the "
             "microphone within 0.5 s, POST /engine is refused while it records, and the words arrive through the local "
             "model once it is up. Before (R7): the gesture was banked, the switch was accepted and the dictation "
             "opened on the new engine")
def tg41():
    """Engine switch while a cold-model sentence records."""
    with G("TG41") as g:
        why = need_el() or need_audio() or cold_whisper(g)
        if why:
            return g.skip(why)
        back_to = engine_id()
        bind_witness()
        tty = WITNESS["tty"]
        witness_clear()
        if not to_whisper(g):
            return g.done("FAIL", "POST /engine {id: whisper} was not taken")
        m, opened, dt, cold = cold_open(g, "forward-right")
        if not opened:
            return g.done("FAIL", "the gesture never opened the microphone (cold model)")
        accepted = set_engine(back_to)
        eng_after = engine_id()
        time.sleep(0.3)
        play(CLIP_EN)
        time.sleep(1.0)
        g.step("forward-right")
        landed = wait_for(lambda: "dictat" in witness_text().lower(), 120, 0.3)
        # `lastDelivery` is written after the keystrokes (batch 1): the words reach the witness first.
        wait_for(lambda: str((st().get("lastDelivery") or {}).get("to", "")).endswith(tty or "?"), 5, 0.1)
        s = st()
        d = s.get("lastDelivery") or {}
        banked = bool(BANKED.search(log_since(m)))
        msg = (f"mic {'opened %.2f s after the gesture' % dt} (model still loading={cold}); switch to {back_to} "
               f"mid-sentence accepted={accepted} (engine now {eng_after}); words {'landed' if landed else 'did NOT land'} "
               f"in the witness ({len(witness_text())} chars), to={d.get('to')} via={d.get('via')}; banked={banked}")
        if banked or accepted:
            return g.done("BUG", msg)
        if dt <= 0.5 and cold and not accepted and eng_after == "whisper" and landed and d.get("via") == "local-whisper" \
                and str(d.get("to", "")).endswith(tty or "?"):
            return g.done("PASS", msg)
        return g.done("FAIL", msg)
