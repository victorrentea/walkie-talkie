#!/usr/bin/env python3
"""T-D (delivery, binding, restart) and T-R 20-22 of docs/test-plan.md, §7.2 / §7.3.

Every case starts unbound with nothing held and ends the same way: a held sentence is released
into the witness tab (a `cat` into a file) and the binding dropped. The witness is the delivery
target; a case that needs a second one opens `wt-witness-B` (its own file) and closes it itself.

`/test/dictation` enters below the recogniser: it skips `deliver()` and goes straight to `send`
(the plan's T-D31 fidelity note), so an unbound one is *held*, never pasted at the caret.
Verdicts: PASS = what the plan expects · BUG = the plan's predicted defect · FAIL = neither ·
SKIP = needs audio / Claude Code / Codex / sleep / a relaunch, or the race was lost.

Tags: `tty` opens a Terminal tab (focus is stolen briefly), `slow` waits minutes, `spawn` starts
a real `claude` in a new window, `tmux` needs tmux, `relaunch` quits and relaunches the app
(runs only with WT_ALLOW_RELAUNCH=1)."""
import signal
import sys

from harness import *  # noqa: F401,F403  (the runner's API: post/get/state/witness_*/case/…)
import harness as _harness

_FIRST_CASE = len(CASES)
WITNESS_B = WORK + "/witness-B.txt"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# ---------------------------------------------------------------- small helpers

def _tok(case_id):
    return f"{case_id}-{int(time.time() * 1000) % 10**8}"

def _delivery():
    return state().get("lastDelivery") or {}

def _delivery_at():
    return _delivery().get("at")

def _wait_new_delivery(prev_at, timeout=20):
    """The next `lastDelivery` record after `prev_at` (commit time), or None."""
    return wait_for(lambda: (_delivery() if _delivery().get("at") not in (None, prev_at) else None),
                    timeout, 0.1)

def _iso_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

def _new_rows(n0):
    n = outbox_count() - n0
    return outbox_tail(n) if n > 0 else []

def _row_to(row):
    return ((row or {}).get("delivery") or {}).get("to")

def _bound_tty():
    b = state().get("bound")
    return (b or {}).get("tty") or None

def _hold_gap():
    """How long after `/test/dictation` returns a bind still lands inside the panel hold:
    1 s receipt under autosend, 4-7 s otherwise."""
    return 0.1 if state().get("autosend") else 1.0

def _read(path, mode="r"):
    try:
        with open(path, mode) as f:
            return f.read()
    except FileNotFoundError:
        return b"" if "b" in mode else ""

def _as_str(s):
    """A shell command, spelled as an AppleScript string literal's contents."""
    return s.replace("\\", "\\\\").replace('"', '\\"')

def open_tab(name, command):
    """A new Terminal window titled `name` running `command` (shell syntax); returns the short tty."""
    shell = "printf '\\e]0;%s\\a'; %s" % (name, command)
    tty = osa(f'tell application "Terminal" to set t to do script "{_as_str(shell)}"',
              'tell application "Terminal" to get tty of t')
    time.sleep(0.8)
    return tty.replace("/dev/", "")

def _kill_tty(tty):
    """Every process on that tty (the tab's own programs); the root-owned `login` refuses, fine."""
    if not tty:
        return
    out = subprocess.run(["ps", "-t", tty.replace("/dev/", ""), "-o", "pid="],
                         capture_output=True, text=True).stdout
    pids = [int(x) for x in out.split() if x.isdigit() and int(x) != os.getpid()]
    for sig in (signal.SIGHUP, signal.SIGKILL):
        for p in pids:
            try:
                os.kill(p, sig)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.3)

def close_tab(tty=None, name=None):
    """Kill what runs in it (so Terminal does not ask), then close the window by tty or name."""
    if tty:
        _kill_tty(tty)
        dev = "/dev/" + tty.replace("/dev/", "")
        osa('tell application "Terminal"',
            'repeat with w in windows',
            'try',
            'repeat with t in tabs of w',
            f'if tty of t is "{dev}" then',
            'close w',
            'return "closed"',
            'end if',
            'end repeat',
            'end try',
            'end repeat',
            'end tell')
    if name:
        osa(f'tell application "Terminal" to close (every window whose name contains "{name}") saving no')

def open_b():
    open(WITNESS_B, "w").close()
    return open_tab("wt-witness-B", "stty -echo; exec cat >> " + WITNESS_B)

def close_b(tty=None):
    close_tab(tty, "wt-witness-B")

def terminal_ttys():
    return set(re.findall(r"ttys\d+", osa('tell application "Terminal" to get tty of every tab of every window')))

def bind_tty(tty):
    return post("/bind", {"tty": tty.replace("/dev/", "")})

def _release_held():
    """Deliver a held sentence into the witness so nothing stays `awaitingBind`."""
    if not state().get("awaitingBind"):
        return True
    bind_witness()
    ok = wait_for(lambda: not state()["awaitingBind"], 15, 0.2)
    time.sleep(1.5)
    return bool(ok)

def _settle():
    """Nothing open, nothing held, nothing bound, Replace Wispr off."""
    try:
        s = state()
        if s.get("listening") or s.get("isRecording") or s.get("settling"):
            post("/test/cancel")
            time.sleep(0.6)
        if "prompt on screen" in (s.get("busyWhy") or []):
            wait_for(lambda: "prompt on screen" not in (state().get("busyWhy") or []), 10, 0.2)
        _release_held()
        post("/test/replace-wispr", {"on": False})
        unbind()
        wait_for(lambda: state().get("bound") is None, 5, 0.2)
    except Exception:
        pass

_fresh = _settle

def _log_excerpt(mark, pattern=r"📦 delivery|⌨️|⛔️|⏳|📍|✨|caret dictation|spawn dropped|unbound|🗑️", n=8):
    lines = [l for l in log_since(mark).splitlines() if re.search(pattern, l)]
    return " / ".join(l[-160:] for l in lines[-n:])


# ================================================================ T-D

@case("TD1", tags=("http",),
      expect="POST /bind {tty: ttys999} (no such tty) → 409; nothing bound, no sentence lost")
def td1():
    """A dead tty is accepted by bind(tty:) and a sentence released into it is lost with a receipt."""
    _fresh()
    try:
        code, r = post("/bind", {"tty": "ttys999"})
        if code == 409:
            return "PASS", f"409 {r.get('error')}"
        if code != 200:
            return "FAIL", f"/bind answered {code} {r}"
        bound = _bound_tty()
        mark, n0, prev = log_mark(), outbox_count(), _delivery_at()
        tok = _tok("TD1")
        post("/test/dictation", {"text": f"{tok} a sentence for a terminal that does not exist"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: log_has(mark, r"is gone|no Terminal\.app tab|refused"), 10, 0.2)
        time.sleep(0.5)
        s = state()
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        gone = log_has(mark, r"ttys999 is gone|no Terminal\.app tab on ttys999")
        facts = (f"/bind 200 (bound tty={bound}); lastDelivery.to={d.get('to')}; outbox rows={[_row_to(x) for x in rows]}; "
                 f"gone-line={gone}; bound after={s.get('bound')}; awaitingBind={s.get('awaitingBind')}")
        if rows and gone and s.get("bound") is None and not s.get("awaitingBind"):
            return "BUG", "dead tty bound, sentence lost with an outbox receipt — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        _settle()


@case("TD2", tags=("http", "tty"),
      expect="two sentences held while unbound → the bind delivers both (or says the first was replaced)")
def td2():
    """A second held sentence replaces the first silently; the bind delivers only BRAVO."""
    _fresh()
    try:
        witness_open(); witness_clear()
        mark = log_mark()
        a, b = _tok("ALFA"), _tok("BRAVO")
        prev = _delivery_at()
        post("/test/dictation", {"text": f"{a} first held sentence"})
        d1 = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: state()["awaitingBind"], 5, 0.1)
        post("/test/dictation", {"text": f"{b} second held sentence"})
        d2 = _wait_new_delivery(d1.get("at"), 15) or {}
        held_after_two = state()["awaitingBind"]
        bind_witness()
        wait_for(lambda: not state()["awaitingBind"], 15, 0.2)
        wait_for(lambda: b in witness_text(), 10, 0.2)
        time.sleep(2)
        text = witness_text()
        a_in, b_in = a in text, b in text
        holds = len(re.findall(r"nothing bound — holding", log_since(mark)))
        said = re.findall(r"[^\n]*(replac|dropped|discard)[^\n]*", log_since(mark))
        facts = (f"to1={d1.get('to')} to2={d2.get('to')} held-after-two={held_after_two}; hold lines={holds}; "
                 f"after bind: ALFA in witness={a_in}, BRAVO in witness={b_in}; replacement said in log={bool(said)}")
        if a_in and b_in:
            return "PASS", facts
        if b_in and not a_in:
            return "BUG", "first held sentence silently replaced — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        _settle()


@case("TD3", tags=("audio",), expect="unbound real sentence is held for a bind, not pasted at the caret")
def td3():
    """Needs a real spoken sentence (the latch at mic close); /test/dictation cannot reach it."""
    return "SKIP", "needs real audio: /test/dictation skips latchedAtCaret (see TD31); run with cases_audio"


@case("TD4", tags=("http", "tty"),
      expect="bind B during the hold of a sentence bound to A → words land in A (recipient fixed when the words arrived)")
def td4():
    """A bind during the panel hold changes the recipient (R11)."""
    _fresh()
    tb = None
    try:
        ta = witness_open(); witness_clear()
        tb = open_b()
        bind_witness()
        if _bound_tty() != ta:
            return "FAIL", f"could not bind A ({ta}): bound={state().get('bound')}"
        tok, gap = _tok("TD4"), _hold_gap()
        mark, prev = log_mark(), _delivery_at()
        post("/test/dictation", {"text": f"{tok} sentence spoken to A"})
        time.sleep(gap)
        code, _ = bind_tty(tb)
        t_bound = time.time()
        d = _wait_new_delivery(prev, 20) or {}
        wait_for(lambda: tok in witness_text() or tok in _read(WITNESS_B), 10, 0.2)
        time.sleep(1)
        in_a, in_b = tok in witness_text(), tok in _read(WITNESS_B)
        commit_at = _iso_ts(d.get("at") or "") or 0
        facts = (f"A={ta} B={tb} bind B → {code} at +{gap:.1f}s; commit {commit_at - t_bound:+.2f}s vs bind done; "
                 f"to={d.get('to')}; in A={in_a}, in B={in_b}")
        if commit_at and commit_at < t_bound:
            return "SKIP", "inconclusive — the commit happened before the bind finished: " + facts
        if in_a and not in_b:
            return "PASS", facts
        if in_b:
            return "BUG", "recipient changed during the hold — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        close_b(tb)
        _settle()


@case("TD5", tags=("http", "tty"),
      expect="a restore (POST /bind {tty}) during a caret dictation leaves it at the caret (pasteMode stays true)")
def td5():
    """Restores count as deliberate binds and take back the caret."""
    _fresh()
    try:
        tty = witness_open()
        post("/test/replace-wispr", {"on": True})
        time.sleep(0.4)
        post("/test/dictation/start", {})
        if not wait_for(lambda: (lambda s: s["pasteMode"] and s["listening"])(state()), 4, 0.1):
            s = state()
            return "FAIL", f"no caret dictation opened: pasteMode={s['pasteMode']} listening={s['listening']}"
        mark = log_mark()
        code, _ = bind_tty(tty)
        wait_for(lambda: log_has(mark, r"caret dictation redirected") or not state()["pasteMode"], 4, 0.1)
        time.sleep(0.5)
        s = state()
        redirected = log_has(mark, r"caret dictation redirected")
        facts = f"/bind {code}; pasteMode after={s['pasteMode']}; 'caret dictation redirected' logged={redirected}"
        if s["pasteMode"] and not redirected:
            return "PASS", facts
        if redirected and not s["pasteMode"]:
            return "BUG", "restore took the caret back — " + facts
        return "FAIL", facts
    finally:
        post("/test/cancel")
        time.sleep(0.4)
        post("/test/replace-wispr", {"on": False})
        _settle()


@case("TD6", tags=("http", "tty"),
      expect="a restore (POST /bind {tty}) during a spawn dictation keeps the spawn (spawnPending stays true)")
def td6():
    """Restores count as deliberate binds and take back a spawn."""
    _fresh()
    try:
        tty = witness_open()
        post("/test/dictation/start", {})
        if not wait_for(lambda: state()["listening"], 4, 0.1):
            return "FAIL", "the test dictation never opened"
        post("/test/spawn-folders")
        if not wait_for(lambda: state()["spawnPending"], 3, 0.1):
            return "FAIL", "spawnPending never went up after /test/spawn-folders"
        mark = log_mark()
        code, _ = bind_tty(tty)
        wait_for(lambda: log_has(mark, r"spawn dropped") or not state()["spawnPending"], 4, 0.1)
        time.sleep(0.5)
        s = state()
        dropped = log_has(mark, r"spawn dropped")
        facts = f"/bind {code}; spawnPending after={s['spawnPending']}; '✨ spawn dropped' logged={dropped}"
        if s["spawnPending"] and not dropped:
            return "PASS", facts
        if dropped and not s["spawnPending"]:
            return "BUG", "restore took the spawn back — " + facts
        return "FAIL", facts
    finally:
        post("/test/cancel")  # clears spawnPending with the test-open dictation
        time.sleep(0.5)
        _settle()


@case("TD7", tags=("cc", "spawn"), expect="two spawns in a row → each sentence in its own window")
def td7():
    """Two real Claude Code spawns; words compared inside the sessions."""
    return "SKIP", "needs two live Claude Code sessions to read the prompts back ([TTY+CC])"


@case("TD8", tags=("http", "tty", "slow"),
      expect="a sentence open > 120 s with a wheel shot keeps its envelope; no bare screenshot message goes to A")
def td8():
    """The 120 s orphan flush fires mid-sentence (§3.6, R6)."""
    _fresh()
    try:
        witness_open(); witness_clear()
        bind_witness()
        n0, mark = outbox_count(), log_mark()
        post("/test/dictation/start", {})
        if not wait_for(lambda: state()["listening"], 4, 0.1):
            return "FAIL", "the test dictation never opened"
        code, area = post("/test/area", {})
        t_shot = time.time()
        started = state().get("dictationStartedAt")
        flushed = wait_for(lambda: log_has(mark, r"no transcript within \d+s — releasing"), 135, 1.0)
        t_flush = time.time() - t_shot
        time.sleep(3)
        s = state()
        rows = _new_rows(n0)
        shots = [x for x in rows if x.get("kind") == "screenshot"]
        facts = (f"/test/area {code}; flush line={'at +%.0fs' % t_flush if flushed else 'none in 135 s'}; "
                 f"listening={s['listening']}; dictationStartedAt {started} → {s.get('dictationStartedAt')}; "
                 f"screenshot rows={len(shots)} to={[_row_to(x) for x in shots]}; witness bytes={len(witness_text())}")
        if flushed and s["listening"] and shots:
            return "BUG", "orphan flush sent the shot alone mid-sentence — " + facts
        if not flushed and s["listening"] and not shots:
            return "PASS", facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        _settle()


@case("TD9", tags=("http", "slow"),
      expect="the 10-min ceiling ends a test-open dictation at ~600 s (control for TD8)")
def td9():
    """The dictation ceiling is unaffected by the orphan flush."""
    _fresh()
    try:
        mark = log_mark()
        post("/test/dictation/start", {})
        t0 = time.time()
        if not wait_for(lambda: state()["listening"], 4, 0.1):
            return "FAIL", "the test dictation never opened"
        ended = wait_for(lambda: not state()["listening"], 640, 1.0)
        dt = time.time() - t0
        line = log_has(mark, r"ten minutes — the ceiling")
        facts = f"listening dropped at +{dt:.0f}s; ceiling line={line}"
        if ended and line and 590 <= dt <= 620:
            return "PASS", facts
        return "FAIL", facts + " | " + _log_excerpt(mark, r"⏱️|🗑️|no transcript")
    finally:
        _settle()


@case("TD10", tags=("http",),
      expect="relay-restart.sh --dry-run --max-wait 20 with a sentence held for a bind → exit 3, 'held for a bind'")
def td10():
    """The restart gate waits for a held sentence."""
    _fresh()
    try:
        prev = _delivery_at()
        post("/test/dictation", {"text": _tok("TD10") + " a sentence held while the gate is asked"})
        d = _wait_new_delivery(prev, 15) or {}
        if not wait_for(lambda: state()["awaitingBind"], 5, 0.1):
            return "FAIL", f"nothing held (to={d.get('to')})"
        t0 = time.time()
        p = subprocess.run(["./relay-restart.sh", "--dry-run", "--max-wait", "20"], cwd=REPO,
                           capture_output=True, text=True, timeout=90)
        dt = time.time() - t0
        out = (p.stdout + p.stderr).strip()
        facts = f"exit {p.returncode} after {dt:.0f}s; output: {out[-300:]}"
        if p.returncode == 3 and "held for a bind" in out:
            return "PASS", facts
        return "FAIL", facts
    finally:
        _settle()


@case("TD11", tags=("http", "slow"),
      expect="gate escapes a stale `listening` (no mic, no recogniser) after ~30 s + 10 quiet s → exit 0, 'stuck flag'")
def td11():
    """Stale-flag escape of the restart gate (tools/restart_gate.py). --max-wait 60, not 20: the escape needs 30 s."""
    _fresh()
    try:
        post("/test/dictation/start", {})
        if not wait_for(lambda: state()["listening"], 4, 0.1):
            return "FAIL", "the test dictation never opened"
        time.sleep(1.5)
        why = state().get("busyWhy")
        t0 = time.time()
        p = subprocess.run(["./relay-restart.sh", "--dry-run", "--max-wait", "60"], cwd=REPO,
                           capture_output=True, text=True, timeout=120)
        dt = time.time() - t0
        out = (p.stdout + p.stderr).strip()
        facts = f"busyWhy before={why}; exit {p.returncode} after {dt:.0f}s; output: {out[-300:]}"
        if why != ["dictating"]:
            return "FAIL", "precondition: busyWhy should be only 'dictating' — " + facts
        if p.returncode == 0 and "stuck flag" in out and 28 <= dt <= 55:
            return "PASS", facts
        return "FAIL", facts
    finally:
        _settle()


@case("TD12", tags=("tty", "relaunch"),
      expect="a bind made while a quit is deferred survives the relaunch (restore binds B, not the A read before SIGTERM)")
def td12():
    """relay-restart.sh read bound-tty before SIGTERM; a bind during the deferred quit was overwritten (R15).
    Since 2026-09-26 an app being replaced leaves the binding it had *at quit* in bound-tty and the script
    reads it again once the process is gone — this case does what the script does (the file after the
    exit, the pre-SIGTERM read only as the fallback)."""
    if not os.environ.get("WT_ALLOW_RELAUNCH"):
        return "SKIP", "quits and relaunches the app — set WT_ALLOW_RELAUNCH=1 with Victor idle"
    _fresh()
    tb = None
    try:
        ta = witness_open()
        tb = open_b()
        bind_witness()
        time.sleep(0.8)
        read_before = _read(HOME + "/bound-tty").split()[:1]
        post("/test/dictation/start", {})
        wait_for(lambda: state()["listening"], 4, 0.1)
        pid = state()["pid"]
        open(HOME + "/.replacing", "a").close()
        os.utime(HOME + "/.replacing")
        os.kill(pid, signal.SIGTERM)
        deferred = wait_for(lambda: state().get("quitPending"), 5, 0.2)
        bind_tty(tb)
        time.sleep(0.5)
        post("/test/cancel")

        def gone():
            os.utime(HOME + "/.replacing")
            try:
                os.kill(pid, 0)
                return False
            except ProcessLookupError:
                return True
        if not wait_for(gone, 30, 0.5):
            return "FAIL", f"pid {pid} still alive 30 s after SIGTERM + cancel (deferred={bool(deferred)})"
        at_quit = _read(HOME + "/bound-tty").split()[:1]   # relay-restart.sh reads it here, before the launch
        subprocess.run(["open", "-g", "/Applications/Walkie Talkie.app"])
        up = wait_for(lambda: get("/up", 2).get("ok"), 60, 0.5)
        if not up:
            return "FAIL", "relaunched app did not answer on the harness port within 60 s"
        restore = (at_quit or read_before or [""])[0]
        code, _ = bind_tty(restore) if restore else (None, None)
        time.sleep(0.5)
        now = _bound_tty()
        facts = (f"A={ta} B={tb}; bound-tty before SIGTERM={read_before[:1]}, after the exit={at_quit}; "
                 f"quit deferred={bool(deferred)}; restore {restore} /bind {code}; bound after={now}")
        if now == tb:
            return "PASS", facts
        if now == ta:
            return "BUG", "the relaunch restored the stale A — " + facts
        return "FAIL", facts
    finally:
        close_b(tb)
        _settle()


@case("TD13", tags=("tty", "tmux"),
      expect="restoring a tmux binding (POST /bind {client tty}) binds the pane that was bound, not the active one")
def td13():
    """bound-tty held the tmux *client* tty; a restore re-resolved to whichever pane is active (R15).
    Since 2026-09-26 the line is `ttysNNN %N` and relay-restart.sh posts both — as this case does."""
    tmux = shutil.which("tmux") or next((p for p in ("/opt/homebrew/bin/tmux", "/usr/local/bin/tmux")
                                         if os.path.exists(p)), None)
    if not tmux:
        return "SKIP", "tmux not installed"
    _fresh()
    sess, tty = "wt-plan-td13", None
    tm = lambda *a: subprocess.run([tmux, *a], capture_output=True, text=True).stdout.strip()
    try:
        subprocess.run([tmux, "kill-session", "-t", sess], capture_output=True)
        subprocess.run([tmux, "new-session", "-d", "-s", sess, "-x", "160", "-y", "40"], check=True)
        subprocess.run([tmux, "split-window", "-t", sess], check=True)
        panes = tm("list-panes", "-t", sess, "-F", "#{pane_id}").split()
        if len(panes) != 2:
            return "FAIL", f"expected two panes, got {panes}"
        tty = open_tab("wt-witness-tmux", f"exec {tmux} attach -t {sess}")
        if not wait_for(lambda: ("/dev/" + tty) in tm("list-clients", "-F", "#{client_tty}").split(), 8, 0.2):
            return "FAIL", f"tmux client on {tty} never attached"
        first, second = panes
        tm("select-pane", "-t", first)
        time.sleep(0.3)
        c1, r1 = bind_tty(tty)
        time.sleep(0.8)
        published = _read(HOME + "/bound-tty").strip()
        tm("select-pane", "-t", second)
        time.sleep(0.3)
        words = published.split()
        c2, r2 = post("/bind", {"tty": words[0] if words else tty,
                                "pane": words[1] if len(words) > 1 else ""})
        time.sleep(0.5)
        facts = (f"client {tty}; panes {panes}; bind with {first} active → {c1} {r1.get('address')}; "
                 f"bound-tty='{published}'; restore with {second} active → {c2} {r2.get('address')}")
        if r1.get("address") != first:
            return "FAIL", "first bind did not pick the active pane — " + facts
        if r2.get("address") == first:
            return "PASS", facts
        if r2.get("address") == second:
            return "BUG", "restore picked the active pane — " + facts
        return "FAIL", facts
    finally:
        unbind()
        subprocess.run([tmux, "kill-session", "-t", sess], capture_output=True)
        time.sleep(0.5)
        close_tab(tty, "wt-witness-tmux")
        _settle()


_PTY_HOLDER = r'''
import os, sys, fcntl, termios, signal
m, s = os.openpty()
name = os.ttyname(s)
pid = os.fork()
if pid == 0:
    os.setsid()
    fcntl.ioctl(s, getattr(termios, "TIOCSCTTY", 0x20007461), 0)
    for fd in (0, 1, 2):
        os.dup2(s, fd)
    os.close(m)
    os.execvp("cat", ["cat"])
os.close(s)
signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))
print(name, flush=True)
out = open(sys.argv[1], "ab", buffering=0)
try:
    while True:
        b = os.read(m, 4096)
        if not b:
            break
        out.write(b)
except OSError:
    pass
finally:
    try:
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass
'''

@case("TD14", tags=("http",),
      expect="restoring a tty that is no Terminal.app tab (IDE-like pty) → /bind refuses (409); no sentence lost")
def td14():
    """A pty owned by no Terminal tab (what an IDE terminal is) is bound; the first delivery says
    'no Terminal.app tab on', unbinds, and the sentence is gone with a receipt."""
    _fresh()
    holder = None
    try:
        path = WORK + "/ptyhold.py"
        with open(path, "w") as f:
            f.write(_PTY_HOLDER)
        holder = subprocess.Popen([sys.executable, path, WORK + "/pty-drain.bin"],
                                  stdout=subprocess.PIPE, text=True)
        tty = (holder.stdout.readline() or "").strip().replace("/dev/", "")
        if not tty.startswith("ttys"):
            return "FAIL", f"pty helper gave no tty: {tty!r}"
        time.sleep(0.3)
        fg = subprocess.run(["ps", "-t", tty, "-o", "stat=,comm="], capture_output=True, text=True).stdout.strip()
        code, r = bind_tty(tty)
        if code == 409:
            return "PASS", f"409 for {tty} ({r.get('error')}); ps: {fg}"
        mark, n0, prev = log_mark(), outbox_count(), _delivery_at()
        tok = _tok("TD14")
        post("/test/dictation", {"text": f"{tok} sentence for an IDE-like pty"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: log_has(mark, r"no Terminal\.app tab on|is gone|refused"), 10, 0.2)
        time.sleep(0.5)
        s = state()
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        no_tab = log_has(mark, r"no Terminal\.app tab on " + tty)
        facts = (f"/bind {tty} → {code} ({r.get('address')}); ps: {fg}; to={d.get('to')}; rows={[_row_to(x) for x in rows]}; "
                 f"'no Terminal.app tab' logged={no_tab}; bound after={s.get('bound')}; awaitingBind={s.get('awaitingBind')}")
        if no_tab and rows and s.get("bound") is None and not s.get("awaitingBind"):
            return "BUG", "bound a pty with no tab; sentence lost with a receipt — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        if holder:
            holder.terminate()
            try:
                holder.wait(3)
            except Exception:
                holder.kill()
        _settle()


@case("TD15", tags=("tty",),
      expect="a shell behind `script -q /dev/null zsh` is refused by the guard; `touch` does not run")
def td15():
    """Shell-guard bypass: the foreground on the tab's tty is `script`, the shell is one pty down."""
    _fresh()
    flag = WORK + "/td15-flag"
    tty = None
    try:
        if os.path.exists(flag):
            os.remove(flag)
        tty = open_tab("wt-witness-script", "exec script -q /dev/null /bin/zsh -f")
        time.sleep(1.0)
        code, _ = bind_tty(tty)
        mark, n0, prev = log_mark(), outbox_count(), _delivery_at()
        post("/test/dictation", {"text": f"touch {flag}"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: log_has(mark, r"⛔️|delivered to the bound terminal|unbound"), 10, 0.2)
        time.sleep(2.5)
        ran = os.path.exists(flag)
        refused = log_has(mark, r"⛔️")
        fg = re.findall(r"foreground=(\S+)", log_since(mark))
        facts = (f"tab {tty} bind {code}; guard saw foreground={fg}; refused={refused}; to={d.get('to')}; "
                 f"rows={len(_new_rows(n0))}; touch ran={ran}")
        if refused and not ran:
            return "PASS", facts
        if ran:
            return "BUG", "the sentence was executed by the shell behind `script` — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        unbind()
        close_tab(tty, "wt-witness-script")
        _settle()


@case("TD16", tags=("tty",),
      expect="a sentence starting with q sent into `less` does not reach the shell underneath; `touch` does not run")
def td16():
    """Pager escape: `less` takes the q and quits, zsh runs the rest of the sentence."""
    _fresh()
    flag = WORK + "/td16-flag"
    tty = None
    try:
        if os.path.exists(flag):
            os.remove(flag)
        tty = open_tab("wt-witness-less", "seq 1 5000 | command less")
        time.sleep(1.5)
        code, _ = bind_tty(tty)
        mark, prev = log_mark(), _delivery_at()
        post("/test/dictation", {"text": f"quick check; touch {flag}"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: log_has(mark, r"⛔️|delivered to the bound terminal|unbound"), 10, 0.2)
        time.sleep(2.5)
        ran = os.path.exists(flag)
        fg = re.findall(r"foreground=(\S+)", log_since(mark))
        facts = f"tab {tty} bind {code}; guard saw foreground={fg}; to={d.get('to')}; touch ran={ran}"
        if not fg or fg[0] != "less":
            return "FAIL", "precondition: the guard did not see `less` in front — " + facts
        if ran:
            return "BUG", "q quit less and zsh ran the rest — " + facts
        return "PASS", facts
    finally:
        unbind()
        close_tab(tty, "wt-witness-less")
        _settle()


@case("TD17", tags=("cc",), expect="a Claude Code permission dialog does not take a dictated '2 no stop' as an answer")
def td17():
    return "SKIP", "needs a live Claude Code (haiku) session with a pending permission dialog ([CC])"


@case("TD18", tags=("cc",), expect="a 400-char envelope into Claude Code gets the third Return and is submitted")
def td18():
    return "SKIP", "needs a live Claude Code session to show 'press Enter to send' ([CC])"


@case("TD19", tags=("tty",),
      expect="a 40-char sentence containing 'press Enter to send' into a plain reader gets no third Return")
def td19():
    """Review read-back false positive: the echo of the sentence itself matches the review hint."""
    _fresh()
    path, tty = WORK + "/witness-echo.txt", None
    try:
        open(path, "w").close()
        tty = open_tab("wt-witness-echo", "exec cat >> " + path)  # echo on: the tab shows what it got
        code, _ = bind_tty(tty)
        mark, prev = log_mark(), _delivery_at()
        post("/test/dictation", {"text": "TD19 so press Enter to send it now"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: log_has(mark, r"delivered to the bound terminal|⛔️|unbound"), 10, 0.2)
        time.sleep(1.0)
        third = log_has(mark, r"a third Return")
        data = _read(path)
        facts = f"tab {tty} bind {code}; to={d.get('to')}; third Return logged={third}; newlines in file={data.count(chr(10))}"
        if not log_has(mark, r"delivered to the bound terminal"):
            return "FAIL", "not delivered — " + facts + " | " + _log_excerpt(mark)
        if third:
            return "BUG", "a third Return went to a tab that never asked — " + facts
        return "PASS", facts
    finally:
        unbind()
        close_tab(tty, "wt-witness-echo")
        _settle()


_RAW_READER = r'''
import os, sys, time, tty
tty.setraw(0)
out = open(sys.argv[1], "ab", buffering=0)
log = open(sys.argv[2], "a")
while True:
    b = os.read(0, 65536)
    if not b:
        break
    out.write(b)
    log.write("%.3f %d\n" % (time.time(), len(b)))
    log.flush()
'''

@case("TD20", tags=("tty",),
      expect="5000 chars with quotes/$(date)/backticks/^C/ESC[201~ arrive intact: 2-3 CR, control bytes stripped, no expansion")
def td20():
    """Raw bytes through `do script` into a raw-mode reader that logs read boundaries (R18)."""
    _fresh()
    raw, chunks, tty = WORK + "/raw.bin", WORK + "/raw.chunks", None
    try:
        reader = WORK + "/rawreader.py"
        with open(reader, "w") as f:
            f.write(_RAW_READER)
        open(raw, "w").close(); open(chunks, "w").close()
        tty = open_tab("wt-witness-raw", f"exec '{sys.executable}' '{reader}' '{raw}' '{chunks}'")
        time.sleep(0.8)
        code, _ = bind_tty(tty)
        unit = 'He said "yes" and \'no\' then $(date) and `whoami` ok. '
        body = unit * (4800 // len(unit))
        mid = len(body) // 2
        text = "TD20-BEGIN " + body[:mid] + "\u0003 ctrl-c here \u001b[201~ paste-end here " + body[mid:] + " TD20-END"
        mark, prev = log_mark(), _delivery_at()
        post("/test/dictation", {"text": text})
        d = _wait_new_delivery(prev, 20) or {}
        wait_for(lambda: log_has(mark, r"delivered to the bound terminal|⛔️|unbound|delivery failed"), 20, 0.2)
        time.sleep(2.0)
        data = _read(raw, "rb")
        reads = [l for l in _read(chunks).splitlines() if l.strip()]
        cr = data.count(b"\r")
        etx, esc = b"\x03" in data, b"\x1b[201~" in data
        literal = b"$(date)" in data and b"`whoami`" in data and b'"yes"' in data
        whole = b"TD20-BEGIN" in data and b"TD20-END" in data
        facts = (f"sent {len(text)} chars; to={d.get('to')}; arrived {len(data)} bytes in {len(reads)} reads "
                 f"({', '.join(l.split()[1] for l in reads[:8])}); CR={cr}; ^C raw={etx}; ESC[201~ raw={esc}; "
                 f"literals intact={literal}; begin+end={whole}")
        if not whole:
            return "FAIL", "the sentence did not arrive whole — " + facts + " | " + _log_excerpt(mark)
        if etx or esc:
            return "BUG", "control bytes reached the tty raw — " + facts
        if 2 <= cr <= 3 and literal:
            return "PASS", facts
        return "FAIL", facts
    finally:
        unbind()
        close_tab(tty, "wt-witness-raw")
        _settle()


@case("TD21", tags=("http", "tty"),
      expect="a bound tab closed and its tty reused by a new tab within 10 s → the binding does not move to the stranger")
def td21():
    """tty reuse: the liveness check sees processes on the tty and keeps a binding to a new tab (R12)."""
    _fresh()
    try:
        t1 = witness_open()
        bind_witness()
        if _bound_tty() != t1:
            return "FAIL", f"could not bind the first witness {t1}"
        witness_close()
        t_close = time.time()
        t2 = witness_open()  # a new tab, file cleared
        time.sleep(max(0, 11 - (time.time() - t_close)))
        s = state()
        still = (s.get("bound") or {}).get("tty")
        if t2 != t1:
            return "SKIP", f"tty not reused ({t1} → {t2}); after 11 s bound={still}"
        tok, prev, mark = _tok("TD21"), _delivery_at(), log_mark()
        post("/test/dictation", {"text": f"{tok} for the tab that was closed"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: tok in witness_text(), 8, 0.2)
        landed = tok in witness_text()
        facts = f"tty {t1} reused by the new tab; bound after 11 s={still}; to={d.get('to')}; landed in the new tab={landed}"
        if still == t1 and landed:
            return "BUG", "binding silently moved to the new tab — " + facts
        if still is None and not landed:
            return "PASS", facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        _settle()


def _td22(offset):
    _fresh()
    try:
        witness_open(); witness_clear()
        tok, prev, mark, n0 = _tok("TD22"), _delivery_at(), log_mark(), outbox_count()
        post("/test/dictation", {"text": f"{tok} held across the five-minute boundary"})
        d = _wait_new_delivery(prev, 15) or {}
        if d.get("to") != "held":
            return "FAIL", f"not held: to={d.get('to')}"
        t_hold = _iso_ts(d["at"])
        time.sleep(max(0, t_hold + offset - time.time()))
        t_post = time.time() - t_hold
        bind_witness()
        t_done = time.time() - t_hold
        time.sleep(6)
        s = state()
        delivered = tok in witness_text()
        expired = log_has(mark, r"held dictation expired")
        released = log_has(mark, r"bound — sending the sentence that was waiting")
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        facts = (f"bind posted at +{t_post:.2f}s, done +{t_done:.2f}s; released={released} expired={expired} "
                 f"delivered={delivered} rows={len(rows)} awaitingBind={s['awaitingBind']}")
        if delivered != expired and not s["awaitingBind"] and (delivered == bool(rows)):
            return "PASS", facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        _settle()

@case("TD22-298.5", tags=("http", "tty", "slow"),
      expect="bind at 298.5 s after the hold → exactly one outcome (delivered xor expired), nothing left held")
def td22a():
    """Expiry vs bind boundary, just before 300 s."""
    return _td22(298.5)

@case("TD22-299.5", tags=("http", "tty", "slow"),
      expect="bind at 299.5 s after the hold → exactly one outcome (delivered xor expired), nothing left held")
def td22b():
    """Expiry vs bind boundary, inside the bind's own latency."""
    return _td22(299.5)

@case("TD22-300.2", tags=("http", "tty", "slow"),
      expect="bind at 300.2 s after the hold → exactly one outcome (delivered xor expired), nothing left held")
def td22c():
    """Expiry vs bind boundary, just after 300 s."""
    return _td22(300.2)


@case("TD23", tags=("sleep",), expect="a held sentence does not outlive its 5 min across a sleep")
def td23():
    return "SKIP", "needs a real sleep (pmset) — [SLEEP]"


@case("TD24", tags=("audio",), expect="busy never flickers false between the first busy and the panel (R14)")
def td24():
    return "SKIP", "needs a real spoken sentence (deliver → endSettling → send one turn later) — [AUDIO]"


_SPAWN = {}

def _spawn_probe():
    """One real spawn, sampled every 20 ms: busy, bound tty, outbox rows. Shared by TD25 and TR22."""
    if _SPAWN:
        return _SPAWN
    _fresh()
    before = terminal_ttys()
    n0, mark = outbox_count(), log_mark()
    text = "TD25 spawn probe from the walkie-talkie test plan: reply with the single word ok and do nothing else."
    t0 = time.time()
    post("/test/spawn", {"text": text})
    samples, t_bound = [], None
    while time.time() - t0 < 60:
        # **The outbox first, then the state** (2026-09-26): read the other way round, a row written
        # a few ms after the state read (i.e. after the bind, as it should be) was counted in a sample
        # whose `bound` predates it, and TR22 reported a receipt 10 ms "before" the window.
        rows_now = outbox_count() - n0
        try:
            s = state()
        except Exception:
            time.sleep(0.02)
            continue
        b = (s.get("bound") or {}).get("tty")
        samples.append((round(time.time() - t0, 3), s["busy"], b, rows_now, tuple(s.get("busyWhy") or [])))
        if b and t_bound is None:
            t_bound = samples[-1][0]      # the sample's own clock, the one TR22 compares a row's against
        if t_bound is not None and time.time() - t0 > t_bound + 1.0:
            break
        time.sleep(0.02)
    new_tty = (state().get("bound") or {}).get("tty")
    spawned = sorted((terminal_ttys() - before) | ({new_tty} if new_tty else set()))
    rows = _new_rows(n0)
    _SPAWN.update(samples=samples, t_bound=t_bound, tty=new_tty, spawned=spawned, rows=rows,
                  log=_log_excerpt(mark, r"✨|📍|📦|spawn"))
    unbind()
    for t in spawned:
        close_tab(t)
    _settle()
    return _SPAWN


@case("TD25", tags=("spawn", "tty"),
      expect="busy stays true from the spawn's first busy until the new window is bound (spawn is a restart blocker)")
def td25():
    """`busy` goes false before `bound.tty` is the new tty (R14 for spawns)."""
    p = _spawn_probe()
    smp = p["samples"]
    first_busy = next((i for i, x in enumerate(smp) if x[1]), None)
    if first_busy is None:
        return "FAIL", f"never busy; {len(smp)} samples; {p['log']}"
    if p["t_bound"] is None:
        return "FAIL", f"never bound in 60 s; spawned ttys={p['spawned']}; {p['log']}"
    gaps = [x for x in smp[first_busy:] if not x[1] and not x[2]]
    facts = (f"{len(smp)} samples; first busy +{smp[first_busy][0]}s {smp[first_busy][4]}; bound {p['tty']} at "
             f"+{p['t_bound']:.2f}s; idle-while-unbound samples={len(gaps)}"
             + (f" from +{gaps[0][0]}s to +{gaps[-1][0]}s" if gaps else ""))
    if gaps:
        return "BUG", "busy false before the spawned window was bound — " + facts
    return "PASS", facts


@case("TD26", tags=("audio",), expect="a fallback finishing after a caret sentence opened does not steal its flags")
def td26():
    return "SKIP", "needs a real sentence in the settle with no key — [AUDIO]"


@case("TD27", tags=("audio",), expect="Recover does not pick up the area/spawn of the sentence opened after it")
def td27():
    return "SKIP", "needs a cancelled real recording to recover — [AUDIO]"


@case("TD28", tags=("codex",), expect="Active Terminals pick on a closed tab is refused, sentence kept")
def td28():
    return "SKIP", "needs a GUI pick in the spawn menu — [CODEX]"


@case("TD29", tags=("http", "tty"),
      expect="unbind during the hold of a sentence bound to A → words land in A, nothing held for a later B")
def td29():
    """An unbind during the hold turns the sentence into `awaitingBind`; the next bind (B) gets it (R11)."""
    _fresh()
    tb = None
    try:
        ta = witness_open(); witness_clear()
        bind_witness()
        if _bound_tty() != ta:
            return "FAIL", f"could not bind A ({ta})"
        tok, gap = _tok("TD29"), _hold_gap()
        mark, prev = log_mark(), _delivery_at()
        post("/test/dictation", {"text": f"{tok} sentence spoken to A"})
        time.sleep(gap)
        unbind()
        t_unbound = time.time()
        d = _wait_new_delivery(prev, 20) or {}
        commit_at = _iso_ts(d.get("at") or "") or 0
        time.sleep(1.0)
        held = state()["awaitingBind"]
        in_a = tok in witness_text()
        in_b = False
        if held:
            tb = open_b()
            bind_tty(tb)
            wait_for(lambda: tok in _read(WITNESS_B), 10, 0.2)
            in_b = tok in _read(WITNESS_B)
        facts = (f"unbind at +{gap:.1f}s; commit {commit_at - t_unbound:+.2f}s vs unbind done; to={d.get('to')}; "
                 f"held={held}; in A={in_a}; in B after binding it={in_b}")
        if commit_at and commit_at < t_unbound and not held:
            return "SKIP", "inconclusive — the commit happened before the unbind: " + facts
        if in_a and not held:
            return "PASS", facts
        if held and in_b:
            return "BUG", "sentence for A held by the unbind and delivered to B — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        close_b(tb)
        _settle()


@case("TD30", tags=("codex",), expect="⌘⇧P during the panel hold pastes the sentence on screen, not the previous one")
def td30():
    return "SKIP", "needs a real ⌘⇧P during the hold — [CODEX/keys]"


@case("TD31", tags=("http", "tty"),
      expect="/test/dictation unbound → lastDelivery.to=='held', awaitingBind, no outbox row; a bind then delivers it")
def td31():
    """Test-route fidelity: /test/dictation reaches the hold; real speech would latch the caret (TD3)."""
    _fresh()
    try:
        witness_open(); witness_clear()
        tok, prev, n0 = _tok("TD31"), _delivery_at(), outbox_count()
        post("/test/dictation", {"text": f"{tok} unbound test sentence"})
        d = _wait_new_delivery(prev, 15) or {}
        wait_for(lambda: state()["awaitingBind"], 3, 0.1)
        s = state()
        held_rows = len(_new_rows(n0))
        bind_witness()
        wait_for(lambda: tok in witness_text(), 10, 0.2)
        time.sleep(0.5)
        s2 = state()
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        d2 = s2.get("lastDelivery") or {}
        agree = bool(rows) and _row_to(rows[-1]) == d2.get("to")
        facts = (f"to={d.get('to')} awaitingBind={s['awaitingBind']} rows while held={held_rows}; after bind: "
                 f"to={d2.get('to')} rows={[_row_to(x) for x in rows]} outbox agrees with lastDelivery={agree} "
                 f"awaitingBind={s2['awaitingBind']}")
        if d.get("to") == "held" and s["awaitingBind"] and held_rows == 0 and tok in witness_text() and agree:
            return "PASS", facts + " (real unbound speech is held the same way since 2026-09-26 — TG18)"
        return "FAIL", facts
    finally:
        _settle()


# ================================================================ T-R 20-22

@case("TR20", tags=("http", "tty", "gesture"),
      expect="terminal closed mid-sentence → the sentence is pasted at the caret (Victor's Q4, 2026-09-26), "
             "no 'delivered' row for the dead tty")
def tr20():
    """Tab closed while the dictation is open; the words arrive for a dead binding (§3.11).
    Since Q4 they are pasted at the caret — caught by the relay's own sink window, made key first,
    which is why this case needs hands-off (the sink takes the front)."""
    _fresh()
    tb = None
    try:
        post("/test/sink", {"on": True})
        time.sleep(0.3)
        tb = open_b()
        bind_tty(tb)
        if _bound_tty() != tb:
            return "FAIL", f"could not bind B ({tb})"
        post("/test/dictation/start", {})
        if not wait_for(lambda: state()["listening"], 4, 0.1):
            return "FAIL", "the test dictation never opened"
        close_b(tb)
        time.sleep(0.8)
        post("/test/sink", {"key": True})
        time.sleep(0.3)
        post("/test/sink/clear")
        tok, mark, n0, prev = _tok("TR20"), log_mark(), outbox_count(), _delivery_at()
        post("/test/dictation", {"text": f"{tok} words for a tab that was closed"})
        d = _wait_new_delivery(prev, 20) or {}
        wait_for(lambda: log_has(mark, r"is gone|no Terminal\.app tab|⛔️|delivered to the bound"), 10, 0.2)
        time.sleep(0.8)
        s = state()
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        gone = log_has(mark, r"is gone|no Terminal\.app tab")
        in_sink = tok in (get("/test/sink").get("text") or "")
        facts = (f"B={tb} closed while listening; to={d.get('to')}; rows={[_row_to(x) for x in rows]}; gone logged={gone}; "
                 f"bound after={s.get('bound')}; awaitingBind={s['awaitingBind']}; pasted into the sink={in_sink}")
        if d.get("to") == "caret" and in_sink and not any(_row_to(x) == "terminal:" + tb for x in rows):
            return "PASS", facts
        if gone and any(_row_to(x) == "terminal:" + tb for x in rows) and not s["awaitingBind"]:
            return "BUG", "delivered-row for a dead tty, sentence lost — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        close_b(tb)
        post("/test/sink", {"restore": True})
        time.sleep(0.2)
        post("/test/sink", {"on": False})
        _settle()


@case("TR21", tags=("http", "tty"),
      expect="bound tab back at a shell prompt → ⛔️ refused, no outbox delivery row, binding kept")
def tr21():
    """Agent exited to the shell: the guard refuses, but the outbox row is already written (§3.11)."""
    _fresh()
    tb = None
    try:
        tb = open_tab("wt-witness-B", "exec /bin/zsh -f")
        time.sleep(0.8)
        bind_tty(tb)
        tok, mark, n0, prev = _tok("TR21"), log_mark(), outbox_count(), _delivery_at()
        post("/test/dictation", {"text": f"{tok} guard probe words"})
        d = _wait_new_delivery(prev, 20) or {}
        wait_for(lambda: log_has(mark, r"⛔️|delivered to the bound|is gone"), 10, 0.2)
        time.sleep(0.5)
        s = state()
        rows = [x for x in _new_rows(n0) if tok in (x.get("text") or "")]
        refused = log_has(mark, r"⛔️ .* refused")
        delivered = log_has(mark, r"delivered to the bound terminal")
        facts = (f"B={tb}; refused={refused}; delivered={delivered}; to={d.get('to')}; rows={[_row_to(x) for x in rows]}; "
                 f"bound after={(s.get('bound') or {}).get('tty')}")
        if delivered:
            return "FAIL", "the shell received the sentence — " + facts
        if refused and not rows:
            return "PASS", facts
        if refused and rows:
            return "BUG", "refused, yet the outbox has a delivery row — " + facts
        return "FAIL", facts + " | " + _log_excerpt(mark)
    finally:
        unbind()
        close_tab(tb, "wt-witness-B")
        _settle()


@case("TR22", tags=("spawn", "tty"),
      expect="no `spawn:` receipt before the new window exists (and a failed spawn re-offers the sentence)")
def tr22():
    """The spawn: row is written at commit, before SpawnTerminal runs. The failure half (re-offer)
    has no desk injection; this measures the receipt's timing on a real spawn (shared with TD25)."""
    p = _spawn_probe()
    spawn_rows = [x for x in p["rows"] if str(_row_to(x) or "").startswith("spawn:")]
    t_row = next((x[0] for x in p["samples"] if x[3] >= 1), None)
    facts = (f"spawn rows={[_row_to(x) for x in spawn_rows]}; first outbox row at "
             f"{'+%.2fs' % t_row if t_row is not None else 'never'}; bound {p['tty']} at "
             f"{'+%.2fs' % p['t_bound'] if p['t_bound'] is not None else 'never'}; failure/re-offer not injectable")
    if not spawn_rows:
        return "FAIL", facts + " | " + p["log"]
    if p["t_bound"] is None or (t_row is not None and t_row < p["t_bound"]):
        return "BUG", "receipt written before the window existed — " + facts
    return "PASS", facts


# ---------------------------------------------------------------- run as a script
# `evals/plan/harness.py` runs as `__main__`, so `from harness import *` above loaded a second copy
# of it under the name `harness`: the cases above registered into that copy's CASES, and the
# witness tab lives in that copy's WITNESS. Hand both to the running copy so `main()` sees these
# cases and `witness_close()` at the end of the run closes the tab they opened. A no-op when the
# runner imports `harness` itself.
_main = sys.modules.get("__main__")
if _main is not None and _main is not _harness and isinstance(getattr(_main, "CASES", None), list):
    _main.CASES.extend(CASES[_FIRST_CASE:])
    _main.WITNESS = WITNESS
