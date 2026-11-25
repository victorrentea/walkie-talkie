#!/usr/bin/env python3
"""**Is it safe to restart Walkie Talkie right now?** The gate `relay-restart.sh` waits on.

Victor, 2026-09-23: *"Whenever you restart it, make sure it's not currently
dictating or transcribing. Make sure it's idle before you restart the app …
After the clean insert of the text [and submit], only then restart. Maybe,
granted, even 10 more seconds in case I routed the prompt to the wrong place,
and then only then restart."*

Victor, 2026-09-28 18:39, after a restart landed while he was dictating:
*"someone just restarted the walkie while I was dictating. that should never
happen (while dictating or transcribing). restart is only possible after 5 secs
of inactivity after the last insert of text."*

Victor, 2026-09-28 21:20: *"there should only be 5 seconds since the last ended
dictation for the walkie deploy to be authorized to happen."* — so the wait on
his hands (5 s since his last key, click or scroll, added at 18:39) is gone
again: his typing is not a dictation.

So the gate opens only when both of these hold:

1. **Nothing is dictating or transcribing, on any engine** — `GET
   /test/state.busy` (the app's `restartBlockers`: every microphone of its own,
   the recogniser, the local fallback, the sentence queue, the live caption, the
   prompt on screen, the words being typed, audio
   staged for Recover — and since 2026-09-28 **Wispr Flow's own microphone and a
   History row it is still working on**), plus the same Wispr checks made here,
   from `wisprLive` and from Wispr's `flow.sqlite` read directly, so an app
   installed before that fix is gated too. An older build without `busy` is read
   from the flags it does have.
2. **`QUIET_AFTER_DELIVERY` (5 s) since the last ended dictation** — the last
   poll that saw it busy, `lastDelivery.at`, `lastInsertAt` (a clipboard write,
   Wispr's newest finished row), a dictation start or stop, the outbox's mtime.
   Anything new restarts the countdown.

**No escape for an app that does
not answer** (2026-09-28): a frozen relay is still not a reason to cut into a
dictation. The gate waits, and after `UNREACHABLE_REFUSE` seconds refuses (exit
4) with a note for the operator; `--force` goes past that one refusal only, only
for a human at a terminal (it asks to type `force`), and still waits for Wispr
and for his hands. One escape stays: a `dictating` flag with no microphone, no
recogniser and no Wispr sentence behind it for 30 s (the
`/test/dictation/start` stuck flag of 2026-09-14).

**A harness run holds it too** (2026-09-28 21:26: an install asked for by Victor
landed between two sentences of a desk run — the relay came back on the run's
engine, bound to its witness tab, and the run was spoilt). `~/.walkie-talkie/
wispr-loop.lock` (`pid started`, the one runner lock on this Mac) with a live pid
keeps the gate closed; a dead pid's lock is ignored.

`wait` polls every second (the cadence, not the gate) and exits 0 when open,
3 at `--max-wait`, 4 when it refuses. `once` prints one reading as JSON. The
logic is `Gate`, unit-tested by `evals/test_restart_gate.py` with a fake clock.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))
import walkie_token  # noqa: E402 — the loopback's X-Walkie-Token (2026-11-25)
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

PORTS = (8917, 8918, 8919)
APP_EXEC = "/Applications/Walkie Talkie.app/Contents/MacOS/Walkie Talkie"

#: Victor, 2026-09-28 21:20: *"there should only be 5 seconds since the last
#: ended dictation"* — seconds after the last insert, dictation edge or busy
#: poll (it was 10 from 2026-09-23, *"even 10 more seconds in case I routed the
#: prompt to the wrong place"*).
QUIET_AFTER_DELIVERY = 5.0
#: A Wispr row still being worked on is a transcription in flight this long
#: after its gesture (p99 7.1 s, max 13.7 s; a row can stall for ever).
WISPR_ROW_FRESH = 60.0
#: `helpers/wispr_loop.py`'s BUSY_STATUSES; `""` is NULL — the row at its gesture.
#: `raw_transcript` is FINAL in Wispr's own code (batch 3, 2026-09-28): not busy.
WISPR_BUSY_STATUSES = ("", "processing", "recording", "transcribing")
#: A relay that has not answered for this long: refuse, never go ahead.
UNREACHABLE_REFUSE = 60.0
WISPR_DB = Path.home() / "Library/Application Support/Wispr Flow/flow.sqlite"


def runner_lock_reason(text: str | None, alive) -> str | None:
    """`harness.py`/`wispr_loop.py`'s lock, `pid started`: a reason to wait while
    the pid lives. `alive(pid) -> bool` is injected for the tests."""
    if not text:
        return None
    parts = text.split(None, 1)
    try:
        pid = int(parts[0])
    except (IndexError, ValueError):
        return None
    if not alive(pid):
        return None
    since = parts[1].strip() if len(parts) > 1 else "?"
    return f"a harness run holding the runner lock (pid {pid} since {since})"


def parse_iso(value) -> float | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def busy_reasons(state: dict) -> list[str]:
    """What is in flight, in the app's own words when it has them."""
    if "busy" in state:
        why = list(state.get("busyWhy") or (["busy"] if state["busy"] else []))
        if state.get("recoverable") and not any("Recover" in w for w in why):
            why.append("audio staged for Recover")
    else:
        # A build older than 2026-09-23: the same predicate, from the flags it has.
        why = []
        if state.get("listening") or state.get("speculative"):
            why.append("dictating")
        if state.get("isRecording"):
            why.append("microphone open")
        if state.get("wisprHearing") or state.get("capturing"):
            why.append("Wispr sentence")
        if state.get("settling") or state.get("phase") in ("warming", "listening", "transcribing"):
            why.append("transcribing")
        if state.get("awaitingBind"):
            why.append("held for a bind")
        if state.get("arrowsUp"):
            why.append("delivering")
        if state.get("filming"):
            why.append("filming")
        if state.get("recoverable"):
            why.append("audio staged for Recover")
    # Everything a build from before 2026-09-28 has the flags for but did not count.
    extra = []
    if state.get("fallingBack"):
        extra.append("local fallback transcribing")
    if any((x or {}).get("state") not in (None, "done") for x in state.get("sentences") or []):
        extra.append("a sentence in the queue")
    if (state.get("liveCaption") or {}).get("open"):
        extra.append("live caption open")
    live = state.get("wisprLive") or {}
    if live.get("micOpen"):
        extra.append("Wispr Flow's microphone open")
    if live.get("captureOpen") and "Wispr sentence" not in why:
        extra.append("Wispr sentence")
    for w in extra:
        if w not in why:
            why.append(w)
    return why


def wispr_row_reasons(row: dict | None, now: float) -> list[str]:
    """A Wispr History row still being worked on, gestured less than a minute ago."""
    if not row or row.get("status") not in WISPR_BUSY_STATUSES or row.get("started_at") is None:
        return []
    age = now - row["started_at"]
    if -30 < age < WISPR_ROW_FRESH:
        status = row["status"]
        return ["Wispr Flow transcribing (row %s%s, %.0f s old)"
                % (row.get("id"), " " + status if status else "", max(0.0, age))]
    return []


def activity_marks(state: dict) -> list[float]:
    marks = [parse_iso((state.get("lastDelivery") or {}).get("at")),
             parse_iso(state.get("dictationStartedAt")),
             parse_iso(state.get("lastInsertAt")),
             parse_iso(state.get("lastDictationEdgeAt"))]
    return [m for m in marks if m is not None]


@dataclass
class Verdict:
    ready: bool
    waiting_for: str
    note: str = ""
    refused: bool = False


class Gate:
    def __init__(self, quiet: float = QUIET_AFTER_DELIVERY, stale_flag: float = 30.0,
                 unreachable: float = UNREACHABLE_REFUSE, force: bool = False):
        self.quiet = quiet
        self.stale_flag = stale_flag
        self.unreachable = unreachable
        self.force = force
        self.last_activity: float | None = None
        self.last_input: float | None = None
        self.unreachable_since: float | None = None
        self.stale_since: float | None = None

    def _touch(self, t: float):
        if self.last_activity is None or t > self.last_activity:
            self.last_activity = t

    def _input(self, t: float | None):
        if t is not None and (self.last_input is None or t > self.last_input):
            self.last_input = t

    def observe(self, now: float, state: dict | None, outbox_mtime: float | None = None,
                wispr_row: dict | None = None, input_at: float | None = None) -> Verdict:
        if outbox_mtime is not None:
            self._touch(outbox_mtime)
        self._input(input_at)
        row_why = wispr_row_reasons(wispr_row, now)
        if wispr_row and wispr_row.get("finished_at") is not None and not row_why:
            self._touch(wispr_row["finished_at"])
        note = ""
        # No answer, or the main thread did not answer in 2 s: not idle, not busy — unknown.
        if state is None or state.get("ok") is False:
            if self.unreachable_since is None:
                self.unreachable_since = now
            silent = now - self.unreachable_since
            if silent < self.unreachable:
                return Verdict(False, "the relay to answer /test/state")
            if not self.force:
                return Verdict(False, "the relay to answer /test/state",
                               f"the relay has not answered for {int(silent)} s — refusing: a frozen app is"
                               " still not a reason to cut into a dictation. Look at it (Activity Monitor,"
                               " relay.log); a human who has may run ./relay-restart.sh --force",
                               refused=True)
            note = f"the relay has not answered for {int(silent)} s — going past that on --force"
            why = list(row_why)
        else:
            self.unreachable_since = None
            for mark in activity_marks(state):
                self._touch(mark)
            self._input(parse_iso(state.get("lastInputAt")))
            why = busy_reasons(state)
            for w in row_why:
                if not any(x.startswith("Wispr Flow transcribing") for x in why):
                    why.append(w)
        if why == ["dictating"]:
            # A flag with nothing behind it — see the module docstring.
            if self.stale_since is None:
                self.stale_since = now
            if now - self.stale_since >= self.stale_flag:
                why = []
                note = "`listening` is still up with no microphone and no recogniser behind it — a stuck flag, not a sentence"
        else:
            self.stale_since = None
        if why:
            self._touch(now)
            return Verdict(False, "the sentence in flight: " + ", ".join(why), note)
        if self.last_activity is not None:
            quiet_for = now - self.last_activity
            if quiet_for < self.quiet:
                return Verdict(False, f"{self.quiet:.0f} quiet seconds after the last insert"
                                      f" ({quiet_for:.0f} s so far)", note)
        # `last_input` is read for `once` and the logs only: since 21:20 his hands
        # do not hold the gate — typing is not a dictation.
        return Verdict(True, "", note)


# ---- the live side -------------------------------------------------------------

def home() -> Path:
    return Path(os.environ.get("WALKIE_HOME", Path.home() / ".walkie-talkie"))


def is_installed_app(state: dict, installed: set[int]) -> bool:
    """**Is this `/test/state` the installed app's?** (Fable review, 2026-11-25) A
    `.build/debug` instance (a photo run, a halo demo, a `--home` test) that binds
    8917 while the installed app relaunches on 8918 used to be read as *the*
    relay — its idle state let a restart through while he dictated into the
    installed one. With no installed app found, or a state without a pid, any
    answer still counts, as before."""
    pid = state.get("pid")
    return not installed or not isinstance(pid, int) or pid in installed


def installed_pids() -> set[int]:
    out = subprocess.run(["pgrep", "-f", APP_EXEC], capture_output=True, text=True).stdout
    return {int(p) for p in out.split() if p.isdigit()}


def fetch_state() -> dict | None:
    installed = installed_pids()
    for port in PORTS:
        try:
            # The token is read at every ask: across a relaunch the file changes.
            req = urllib.request.Request(f"http://127.0.0.1:{port}/test/state",
                                         headers=walkie_token.headers(home_dir=str(home())))
            with urllib.request.urlopen(req, timeout=3) as r:
                body = r.read()
            if body:
                state = json.loads(body)
                if is_installed_app(state, installed):
                    return state
        except Exception:
            continue
    return None


def runner_lock_path() -> Path:
    return home() / "wispr-loop.lock"


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def ancestors() -> set[int]:
    """This process's parents up to launchd — the harness's own restart (TX13,
    2026-09-28 wave 3) must not wait on the harness's own lock."""
    out, pid = set(), os.getpid()
    for _ in range(64):
        try:
            ppid = int(subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                                      capture_output=True, text=True).stdout.strip() or 0)
        except ValueError:
            break
        if ppid <= 1:
            break
        out.add(ppid)
        pid = ppid
    return out


def runner_lock_live() -> str | None:
    try:
        text = runner_lock_path().read_text()
    except OSError:
        return None
    mine = ancestors()
    return runner_lock_reason(text, lambda pid: pid not in mine and pid_alive(pid))


def outbox_mtime() -> float | None:
    try:
        return (home() / "outbox.jsonl").stat().st_mtime
    except OSError:
        return None


def app_running() -> bool:
    return subprocess.run(["pgrep", "-f", APP_EXEC], capture_output=True).returncode == 0


def bundle_replaced_under_app() -> str | None:
    """**Was the bundle swapped under the running process?** (2026-09-28) A bundle
    replaced on disk no longer matches the running code signature, and the app's
    AppleEvents to Terminal are refused — every bind fails — until it restarts.
    `relay-restart.sh --build` stages and swaps only after the quit now; this is
    here so the class is seen when anything else does it."""
    try:
        pid = subprocess.run(["pgrep", "-f", APP_EXEC], capture_output=True, text=True).stdout.split()[0]
        lstart = subprocess.run(["ps", "-o", "lstart=", "-p", pid], capture_output=True, text=True).stdout.strip()
        started = time.mktime(time.strptime(" ".join(lstart.split()), "%a %b %d %H:%M:%S %Y"))
        built = os.stat(APP_EXEC).st_mtime
    except (IndexError, ValueError, OSError):
        return None
    if built > started + 2:
        return (f"bundle already replaced under the running app (pid {pid} started"
                f" {time.strftime('%H:%M:%S', time.localtime(started))}, executable on disk from"
                f" {time.strftime('%H:%M:%S', time.localtime(built))}) — restart as soon as the gate allows;"
                " until then its AppleEvents (binds) may be refused")
    return None


def wispr_newest_row(state: dict | None) -> dict | None:
    """Wispr's newest History row, read-only, straight from its file — so any
    build is gated on it, and so is an app that does not answer. The app's
    `wisprLive.db` names the fake a lab run points it at."""
    db_path = ((state or {}).get("wisprLive") or {}).get("db") or os.environ.get("WT_WISPR_DB") or str(WISPR_DB)
    if not os.path.exists(db_path):
        return None
    try:
        db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=1)
        try:
            cols = {r[1] for r in db.execute("pragma table_info(History)")}
            dur = "coalesce(duration, 0)" if "duration" in cols else "0"
            row = db.execute("select rowid, coalesce(status, ''), (julianday(timestamp) - 2440587.5) * 86400,"
                             f" coalesce(e2eLatency, 0), {dur} from History order by rowid desc limit 1").fetchone()
        finally:
            db.close()
    except sqlite3.Error:
        return None
    if not row or row[2] is None:
        return None
    rowid, status, started, e2e_ms, duration = row
    finished = None if status in WISPR_BUSY_STATUSES else started + (duration or 0) + (e2e_ms or 0) / 1000.0
    return {"id": rowid, "status": status, "started_at": started, "finished_at": finished}


#: Every event type that is his hands — never a mouse that only moves.
_INPUT_TYPES = (10, 11, 12,          # key down / up, modifiers
                1, 2, 3, 4, 25, 26,  # left, right, other button down / up
                6, 7, 27,            # drags (a button is held)
                22)                  # the wheel


def seconds_since_human_input() -> float | None:
    """The HID system's own clock (`CGEventSourceSecondsSinceLastEventType`,
    hardware events only), through ctypes — no app, no permission needed."""
    try:
        cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        f = cg.CGEventSourceSecondsSinceLastEventType
        f.restype, f.argtypes = ctypes.c_double, [ctypes.c_int32, ctypes.c_uint32]
        return min(f(1, t) for t in _INPUT_TYPES)   # 1 = kCGEventSourceStateHIDSystemState
    except Exception:
        return None


def observe_live(gate: Gate, now: float) -> tuple[Verdict, dict | None]:
    state = fetch_state()
    idle = seconds_since_human_input()
    return gate.observe(now, state, outbox_mtime(), wispr_newest_row(state),
                        None if idle is None else now - idle), state


def confirm_force() -> bool:
    """`--force` is a human's, at a terminal, and never an agent's."""
    if not sys.stdin.isatty():
        print("⛔️ --force is for a human at a terminal (stdin is not one) — nothing was restarted", flush=True)
        return False
    try:
        answer = input("The relay does not answer. Restarting it may cut a dictation in flight."
                       " Type `force` to go ahead once he is not dictating: ")
    except EOFError:
        return False
    return answer.strip() == "force"


def cmd_wait(args) -> int:
    if args.force and not confirm_force():
        return 4
    gate = Gate(quiet=max(args.quiet, QUIET_AFTER_DELIVERY), force=args.force)
    started = time.time()
    replaced = bundle_replaced_under_app()
    if replaced:
        print("⚠️  " + replaced, flush=True)
    said, said_at, noted = None, 0.0, ""
    while True:
        now = time.time()
        if not app_running():
            print("the app is not running — nothing to wait for")
            return 0
        v, _ = observe_live(gate, now)
        if (run := runner_lock_live()) and not v.refused:
            v = Verdict(False, run, v.note)
        if v.note and v.note != noted:
            print(("⛔️ " if v.refused else "⚠️  ") + v.note, flush=True)
            noted = v.note
        if v.refused:
            print("⛔️ refused — nothing was restarted", flush=True)
            return 4
        if v.ready:
            print(f"✅ nothing dictating or transcribing on any engine, {gate.quiet:.0f} s since the"
                  f" last ended dictation — safe to restart"
                  f" (waited {int(now - started)} s)", flush=True)
            return 0
        if now - started >= args.max_wait:
            print(f"⛔️ still waiting for {v.waiting_for} after {int(now - started)} s"
                  f" — gave up (--max-wait {int(args.max_wait)}); nothing was restarted", flush=True)
            return 3
        # Say what it is waiting for when that changes, and every 30 s otherwise.
        key = v.waiting_for.split(" (")[0]
        if key != said or now - said_at >= 30:
            print(f"⏳ waiting for {v.waiting_for}", flush=True)
            said, said_at = key, now
        time.sleep(1)


def cmd_once(_args) -> int:
    now = time.time()
    state = fetch_state()
    row = wispr_newest_row(state)
    idle = seconds_since_human_input()
    why = (busy_reasons(state) if state else []) + wispr_row_reasons(row, now)
    if run := runner_lock_live():
        why.append(run)
    print(json.dumps({"running": app_running(), "answered": state is not None,
                      "busyWhy": why if state else (why or None),
                      "lastDelivery": (state or {}).get("lastDelivery"),
                      "lastInsertAt": (state or {}).get("lastInsertAt"),
                      "lastInputAt": (state or {}).get("lastInputAt"),
                      "secondsSinceHumanInput": None if idle is None else round(idle, 1),
                      "wisprRow": row,
                      "bundleReplacedUnderApp": bundle_replaced_under_app(),
                      "quitPending": (state or {}).get("quitPending"),
                      "pid": (state or {}).get("pid")}, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("wait")
    w.add_argument("--quiet", type=float, default=QUIET_AFTER_DELIVERY,
                   help="seconds after the last ended dictation (never below 5)")
    w.add_argument("--max-wait", type=float, default=1800.0)
    w.add_argument("--force", action="store_true",
                   help="a human's: go past an app that has not answered for 60 s (asks to type `force`)")
    w.set_defaults(func=cmd_wait)
    o = sub.add_parser("once")
    o.set_defaults(func=cmd_once)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
