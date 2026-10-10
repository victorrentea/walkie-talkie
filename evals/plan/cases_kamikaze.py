#!/usr/bin/env python3
"""
T-K — 🔼 ↓ (kamikaze) from a sentence's start to the next one's (2026-10-10).

Victor: *"de la începutul unei dictări … până la începutul unei alte dictări, trebuie să pot să fac
semnul de kamikaze."* The flick lost at 17:26:32 fell after the 🔼 ↑ panel had gone and before the
spawned window was bound — `☠️ kamikaze gesture with no sentence in flight — ignored`. Every case
here aims the flick at one stretch between the words and the next sentence, and reads what the
witness `cat` (or the spawned session) received.

The flick goes in through `POST /test/gesture {"name": "forward-down", "direct": true}` —
`onGestureKamikaze` itself, no chord on the wire, so no `hands-off` is needed. His binding is put
back at the end of every case. TK4 spawns a real Claude Code session and runs only with
`WT_ALLOW_SPAWN=1`; the session is told `kamikaze` and closes its own window.
"""
import os, re, sys, time

_runner = sys.modules.get("__main__")
if _runner is not None and os.path.basename(getattr(_runner, "__file__", "") or "") == "harness.py":
    sys.modules["harness"] = _runner

from harness import *  # noqa: E402,F401,F403
from harness import (get, post, state, log_mark, log_since, wait_for, bind_witness, unbind,  # noqa: E402
                     witness_clear, witness_text, WORK, case, wait_idle, osa, close_tty_tab)

IGNORED = "☠️ kamikaze gesture with no sentence in flight — ignored"
QUEUED = "☠️ kamikaze — queued on the prompt on its way"
LANDED_QUEUED = "with a kamikaze queued on it while it travelled"
SENT_ALONE = "☠️ kamikaze — sent alone, after the prompt, to "
HELD_ON = "☠️ kamikaze — the sentence held for a bind closes its agent when done"


def flick():
    return post("/test/gesture", {"name": "forward-down", "direct": True})


def his_binding():
    try:
        t = get("/target") or {}
        return t.get("address") if t.get("bound") else None
    except Exception:
        return None


class K:
    """Idle first, his binding back at the end, nothing left held or on screen."""

    def __init__(self, cid):
        self.cid = cid

    def __enter__(self):
        wait_idle(120)
        self.tty0 = his_binding()
        self.mark = log_mark()
        return self

    def __exit__(self, *exc):
        try:
            if (state().get("prompt") or {}).get("held"):
                post("/test/prompt", {"do": "send"})
            if state().get("awaitingBind"):
                bind_witness()
            wait_for(lambda: not state().get("busy"), 15, 0.2)
        except Exception as e:
            print(f"    {self.cid} cleanup: {type(e).__name__}: {e}")
        if self.tty0:
            post("/bind", {"tty": self.tty0})
        else:
            unbind()
        return False


def panel_then_send(text):
    """`/test/dictation` into the binding → the panel → sent at once. True when the panel was seen."""
    post("/test/dictation", {"text": text})
    up = wait_for(lambda: (state().get("prompt") or {}).get("held"), 3, 0.02)
    if up:
        post("/test/prompt", {"do": "send"})
    return bool(up)


def witness_b():
    path = WORK + "/witness-k.txt"
    open(path, "w").close()
    script = f"printf '\\\\e]0;wt-witness-k\\\\a'; stty -echo; exec cat >> {path}"
    tty = osa(f'tell application "Terminal" to set t to do script "{script}"',
              'tell application "Terminal" to get tty of t').replace("/dev/", "")
    time.sleep(0.8)
    return tty, path


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except FileNotFoundError:
        return ""


def kamikaze_lines(text):
    """How many lines are the word alone — in the prompt (before its footer) or sent after it."""
    return sum(1 for ln in text.replace("\r", "\n").split("\n") if ln.strip().lower() == "kamikaze")


def ends_alone(text):
    """The word on a line of its own after the prompt — the delivered `kamikaze` + Return."""
    lines = [ln.strip() for ln in text.replace("\r", "\n").split("\n") if ln.strip()]
    return bool(lines) and lines[-1].lower() == "kamikaze"


@case("TK1", tags=("delivery",),
      expect="🔼↓ while a bound prompt is still being typed goes to THAT terminal, never to the terminal the "
             "previous prompt landed in. Predicted defect (before 2026-10-10): the standing offer for the "
             "older terminal takes it")
def tk1():
    """Flick during a bound delivery → the newest prompt's terminal."""
    with K("TK1") as k:
        bind_witness()
        witness_clear()
        if not panel_then_send("walkie-talkie TK1 first prompt, ignore it"):
            return "SKIP", "the prompt panel was never seen"
        wait_for(lambda: "TK1 first prompt" in witness_text(), 10, 0.1)
        b_tty, b_path = witness_b()
        try:
            post("/bind", {"tty": b_tty})
            m = log_mark()
            post("/test/dictation", {"text": "walkie-talkie TK1 second prompt, ignore it"})
            if not wait_for(lambda: (state().get("prompt") or {}).get("held"), 3, 0.02):
                return "SKIP", "the second panel was never seen"
            post("/test/prompt", {"do": "send"})
            flick()
            wait_for(lambda: ends_alone(read(b_path)) or ends_alone(witness_text()), 10, 0.1)
            time.sleep(1.0)
            L, a, b = log_since(m), witness_text(), read(b_path)
            branch = ("queued" if QUEUED in L else "offer" if SENT_ALONE in L else
                      "ignored" if IGNORED in L else "?")
            msg = (f"branch={branch}; A ends with kamikaze={ends_alone(a)}; B ends with kamikaze={ends_alone(b)}; "
                   f"B tail {b.strip()[-60:]!r}")
            if ends_alone(a):
                return "BUG", "the flick went to the OLDER terminal · " + msg
            if ends_alone(b) and b.count("kamikaze") == 1 and "second prompt" in b:
                return "PASS", msg
            return "FAIL", msg
        finally:
            close_tty_tab(b_tty)


@case("TK2", tags=("delivery",),
      expect="🔼↓ with the prompt held for a bind puts the word on that prompt; the bind delivers it with "
             "`kamikaze` on its last line. Predicted defect: ignored, or sent to the last prompted terminal")
def tk2():
    """Flick on a sentence held for a bind."""
    with K("TK2") as k:
        unbind()
        time.sleep(0.3)
        if not panel_then_send("walkie-talkie TK2 held prompt, ignore it"):
            return "SKIP", "the prompt panel was never seen"
        if not wait_for(lambda: state().get("awaitingBind"), 4, 0.05):
            return "FAIL", f"not held for a bind: busyWhy {state().get('busyWhy')}"
        m = log_mark()
        flick()
        time.sleep(0.4)
        witness_clear()
        bind_witness()
        wait_for(lambda: "TK2 held prompt" in witness_text(), 10, 0.1)
        time.sleep(1.0)
        L, w = log_since(m), witness_text()
        msg = f"marked={HELD_ON in L}; ignored={IGNORED in L}; witness tail {w.strip()[-60:]!r}"
        if HELD_ON in L and kamikaze_lines(w) == 1:
            return "PASS", msg
        if IGNORED in L or SENT_ALONE in L:
            return "BUG", msg
        return "FAIL", msg


@case("TK3", tags=("delivery",),
      expect="🔼↓ during a plain dictation (no kamikaze on plain words) is the last prompt's: the word "
             "goes alone to the terminal last prompted, and the plain sentence carries nothing. "
             "Predicted defect: the chip row toggles and the word is silently dropped at delivery")
def tk3():
    """Flick during a plain sentence → the standing offer."""
    with K("TK3") as k:
        bind_witness()
        witness_clear()
        if not panel_then_send("walkie-talkie TK3 prompt, ignore it"):
            return "SKIP", "the prompt panel was never seen"
        if not wait_for(lambda: "TK3 prompt" in witness_text(), 10, 0.1):
            return "FAIL", "the prompt never reached the witness"
        # The offer is armed when `deliver` answers (~4 s: its Return watch), not when `cat` has the words.
        if not wait_for(lambda: "☠️ kamikaze offered — the prompt landed in terminal:" in log_since(k.mark), 10, 0.1):
            return "FAIL", "no offer after the prompt landed"
        m = log_mark()
        post("/test/dictation/start", {"clean": True})
        if not wait_for(lambda: state().get("listening"), 3, 0.05):
            return "SKIP", "the plain sentence never opened"
        flick()
        wait_for(lambda: SENT_ALONE in log_since(m) and ends_alone(witness_text()), 8, 0.1)
        post("/test/cancel")
        L, w = log_since(m), witness_text()
        chip_row = "☠️ kamikaze — this sentence closes its agent" in L
        msg = f"sent alone={SENT_ALONE in L}; toggled the plain sentence={chip_row}; witness tail {w.strip()[-40:]!r}"
        if SENT_ALONE in L and ends_alone(w) and not chip_row:
            return "PASS", msg
        if chip_row:
            return "BUG", msg
        return "FAIL", msg


@case("TK4", tags=("delivery", "spawn"),
      expect="🔼↓ after the 🔼↑ panel went and before the new window is bound (the 17:26:32 hole) is queued "
             "on the spawn; the session gets `kamikaze` once it has its prompt. Opt-in: WT_ALLOW_SPAWN=1")
def tk4():
    """Flick between the spawn panel and the bind."""
    if os.environ.get("WT_ALLOW_SPAWN") != "1":
        return "SKIP", "spawns a real Claude Code session — WT_ALLOW_SPAWN=1"
    with K("TK4") as k:
        m = log_mark()
        post("/test/spawn", {"text": "walkie-talkie TK4: reply with the single word ok, nothing else"})
        if not wait_for(lambda: (state().get("prompt") or {}).get("held"), 4, 0.02):
            return "SKIP", "the spawn panel was never seen"
        post("/test/prompt", {"do": "send"})
        flick()
        done = wait_for(lambda: "☠️ kamikaze to the spawned session" in log_since(m)
                        or "☠️ kamikaze not sent" in log_since(m), 60, 0.5)
        L = log_since(m)
        msg = f"queued={QUEUED in L}; landed with it={LANDED_QUEUED in L}; ignored={IGNORED in L}"
        tty = re.search(r"✨ new Claude Code in .* on (ttys\d+)", L)
        if tty:
            msg += f"; spawned {tty.group(1)}"
        if QUEUED in L and "☠️ kamikaze to the spawned session" in L:
            return "PASS", msg
        if IGNORED in L:
            return "BUG", msg
        return "FAIL", msg + ("" if done else "; nothing within 60 s")
