#!/usr/bin/env python3
"""**Is it safe to restart Walkie Talkie right now?** The gate `relay-restart.sh` waits on.

Victor, 2026-09-23: *"Whenever you restart it, make sure it's not currently
dictating or transcribing. Make sure it's idle before you restart the app …
After the clean insert of the text [and submit], only then restart. Maybe,
granted, even 10 more seconds in case I routed the prompt to the wrong place,
and then only then restart."*

So the gate opens only when both hold:

1. **Nothing is in flight** — `GET /test/state.busy` (the app's own
   `restartBlockers`: any engine's microphone, the recogniser answering, a Wispr
   sentence behind the firewall, the prompt on screen, a sentence held for a
   bind, the words still being typed). An older build without `busy` is read
   from the flags it does have.
2. **Ten quiet seconds** since the last activity — the last poll that saw it
   busy, the last delivery (`lastDelivery.at`), the last dictation start and the
   outbox's mtime. Anything new restarts the countdown.

Two escapes, both said out loud: a relay that has not answered for a minute
(wedged — nothing it holds can be delivered anyway), and a `dictating` flag with
no microphone, no recogniser and no Wispr sentence behind it for 30 s (the
`/test/dictation/start` stuck flag of 2026-09-14).

`wait` polls every second (the cadence, not the gate) and exits 0 when open,
3 at `--max-wait`. `once` prints one reading as JSON. The logic is `Gate`,
unit-tested by `evals/test_restart_gate.py` with a fake clock.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

PORTS = (8917, 8918, 8919)
APP_EXEC = "/Applications/Walkie Talkie.app/Contents/MacOS/Walkie Talkie"


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
        return list(state.get("busyWhy") or (["busy"] if state["busy"] else []))
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
    return why


def activity_marks(state: dict) -> list[float]:
    marks = [parse_iso((state.get("lastDelivery") or {}).get("at")),
             parse_iso(state.get("dictationStartedAt"))]
    return [m for m in marks if m is not None]


@dataclass
class Verdict:
    ready: bool
    waiting_for: str
    note: str = ""


class Gate:
    def __init__(self, quiet: float = 10.0, stale_flag: float = 30.0, unreachable: float = 60.0):
        self.quiet = quiet
        self.stale_flag = stale_flag
        self.unreachable = unreachable
        self.last_activity: float | None = None
        self.unreachable_since: float | None = None
        self.stale_since: float | None = None

    def _touch(self, t: float):
        if self.last_activity is None or t > self.last_activity:
            self.last_activity = t

    def observe(self, now: float, state: dict | None, outbox_mtime: float | None = None) -> Verdict:
        if outbox_mtime is not None:
            self._touch(outbox_mtime)
        # No answer, or the main thread did not answer in 2 s: not idle, not busy — unknown.
        if state is None or state.get("ok") is False:
            if self.unreachable_since is None:
                self.unreachable_since = now
            if now - self.unreachable_since >= self.unreachable:
                return Verdict(True, "", f"the relay has not answered for {int(now - self.unreachable_since)} s"
                                         " — wedged, nothing in it can be delivered; going ahead")
            return Verdict(False, "the relay to answer /test/state")
        self.unreachable_since = None
        for mark in activity_marks(state):
            self._touch(mark)
        why = busy_reasons(state)
        note = ""
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
            return Verdict(False, "the sentence in flight: " + ", ".join(why))
        if self.last_activity is not None:
            quiet_for = now - self.last_activity
            if quiet_for < self.quiet:
                return Verdict(False, f"{self.quiet:.0f} quiet seconds after the last delivery"
                                      f" ({quiet_for:.0f} s so far)", note)
        return Verdict(True, "", note)


# ---- the live side -------------------------------------------------------------

def home() -> Path:
    return Path(os.environ.get("WALKIE_HOME", Path.home() / ".walkie-talkie"))


def fetch_state() -> dict | None:
    for port in PORTS:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/test/state", timeout=3) as r:
                body = r.read()
            if body:
                return json.loads(body)
        except Exception:
            continue
    return None


def outbox_mtime() -> float | None:
    try:
        return (home() / "outbox.jsonl").stat().st_mtime
    except OSError:
        return None


def app_running() -> bool:
    return subprocess.run(["pgrep", "-f", APP_EXEC], capture_output=True).returncode == 0


def cmd_wait(args) -> int:
    gate = Gate(quiet=args.quiet)
    started = time.time()
    said, said_at, noted = None, 0.0, ""
    while True:
        now = time.time()
        if not app_running():
            print("the app is not running — nothing to wait for")
            return 0
        state = fetch_state()
        v = gate.observe(now, state, outbox_mtime())
        if v.note and v.note != noted:
            print("⚠️  " + v.note, flush=True)
            noted = v.note
        if v.ready:
            print(f"✅ idle, and quiet for {args.quiet:.0f} s — safe to restart"
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
    state = fetch_state()
    print(json.dumps({"running": app_running(), "answered": state is not None,
                      "busyWhy": busy_reasons(state) if state else None,
                      "lastDelivery": (state or {}).get("lastDelivery"),
                      "quitPending": (state or {}).get("quitPending"),
                      "pid": (state or {}).get("pid")}, ensure_ascii=False))
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    w = sub.add_parser("wait")
    w.add_argument("--quiet", type=float, default=10.0)
    w.add_argument("--max-wait", type=float, default=1800.0)
    w.set_defaults(func=cmd_wait)
    o = sub.add_parser("once")
    o.set_defaults(func=cmd_once)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
