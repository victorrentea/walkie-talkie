#!/usr/bin/env python3
"""**Is Victor touching this Mac right now?** — a listen-only watch on real input.

`teacher_label.py` takes the keyboard for hours: it holds Wispr's push-to-talk
chord down and lets Wispr paste the transcript into whatever is in front. That is
fine at 3 a.m. and unacceptable at 3 p.m., so the batch suspends itself the moment
a human event arrives and stays down until the machine has been quiet for a while.
This module is the *moment a human event arrives* half.

## Why a tap and not the idle counter

The obvious call is
`CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, …)`,
and it is wrong here for one measured reason: **it counts our own keystrokes too.**
Probed 2026-09-22 — two synthetic Shift events posted with `CGEventPost` and the
counter read 0.02 s immediately after. A batch gated on it would suspend itself
after every clip it dictated and never run again.

The discriminator that does work, from the same probe:

| event | `kCGEventSourceUnixProcessID` | `kCGEventSourceStateID` |
|---|---|---|
| Victor's mouse and keyboard | **0** | 1 (`HIDSystemState`) |
| anything posted with `CGEventPost` (ours, Wispr's ⌘V) | the poster's pid | 0 |

So a listen-only tap that ignores every event carrying a source pid sees exactly
the hardware, which is exactly the question. Ignoring *all* synthetic events and
not merely our own is deliberate: Wispr's paste is not Victor either, and treating
it as activity would hold the batch down for ever.

## What it costs

A listen-only tap at `kCGHIDEventTap`, one callback that stores a timestamp. It
never swallows or modifies an event — `kCGEventTapOptionListenOnly` cannot, which
is the point: nothing typed on this Mac can be lost by a bug in here.

Accessibility is required for the tap, and `teacher_label.py` already refuses to
start without it, so a tap that will not create means something is wrong rather
than something is missing — `start()` returns False and the caller decides.

    watch = HumanWatch()
    watch.start()
    ...
    if watch.since_human < 300:
        ...          # somebody is at the keyboard

Run it directly to watch the number move:

    python3 helpers/human_watch.py
"""

from __future__ import annotations

import threading
import time

#: Events that mean a person. Mouse *movement* is in here on purpose: Victor
#: reaching for the mouse is the earliest warning there is, and it arrives before
#: the click that would put his own window in front of Wispr's paste.
_WANTED = (
    "kCGEventMouseMoved", "kCGEventLeftMouseDown", "kCGEventRightMouseDown",
    "kCGEventOtherMouseDown", "kCGEventLeftMouseDragged",
    "kCGEventRightMouseDragged", "kCGEventScrollWheel",
    "kCGEventKeyDown", "kCGEventFlagsChanged",
)


class HumanWatch:
    """Seconds since the last event that came from hardware.

    Thread-safe to read, cheap to read, and never blocks: the tap thread writes
    one float, the caller reads it.
    """

    def __init__(self):
        self._last = None          #: monotonic timestamp of the last human event
        self._lock = threading.Lock()
        self._thread = None
        self._runloop = None
        self._tap = None
        self.failed = None         #: why `start()` returned False, for the log

    # ── the reading ──────────────────────────────────────────────────────────
    @property
    def since_human(self) -> float:
        """Seconds since the last hardware event; `inf` if none has been seen.

        `inf` only until `start()` seeds it — see `_seed_from_system`. A watch
        that answered `inf` for its own first minutes would tell a batch the Mac
        is quiet at the very moment somebody has just launched it.
        """
        with self._lock:
            last = self._last
        return float("inf") if last is None else time.monotonic() - last

    def active_since(self, mark: float) -> bool:
        """Has a hardware event arrived since `mark` (a `time.monotonic()`)?

        The exact form of the question a clip in flight wants — *did he touch it
        after I started playing this* — rather than the approximate
        `since_human < something`, which has to guess how long the clip has run.
        """
        with self._lock:
            last = self._last
        return last is not None and last >= mark

    def touch(self):
        """Mark now as human — for tests, and for a caller that knows better."""
        with self._lock:
            self._last = time.monotonic()

    # ── the tap ──────────────────────────────────────────────────────────────
    def start(self) -> bool:
        if self._thread is not None:
            return True
        ready = threading.Event()
        self._thread = threading.Thread(
            target=self._run, args=(ready,), name="human-watch", daemon=True)
        self._thread.start()
        ready.wait(timeout=5)
        return self.failed is None

    def stop(self):
        loop = self._runloop
        if loop is not None:
            from CoreFoundation import CFRunLoopStop
            CFRunLoopStop(loop)
        self._thread = None

    def _seed_from_system(self, Quartz):
        """Start from the system's own idle counter, not from ignorance.

        A tap only sees what arrives after it, so a fresh watch believes the Mac
        has been quiet for ever — and a batch launched by a man who has just
        typed its command would start dictating into his keyboard seconds later.
        Measured 2026-09-22: the run restarted at 02:22:10 was labelling by
        02:22:23, eleven seconds after Victor sent the message that started it.

        `CGEventSourceSecondsSinceLastEventType` is the counter this module
        exists to avoid, because it counts our own posted keystrokes — but at
        this instant nothing has been posted yet, so it is exactly right once:
        as the seed, and never again. A Mac genuinely untouched since boot is
        still reported as idle for hours, so the honest case keeps working.
        """
        try:
            idle = Quartz.CGEventSourceSecondsSinceLastEventType(
                Quartz.kCGEventSourceStateHIDSystemState, Quartz.kCGAnyInputEventType)
        except Exception:  # noqa: BLE001 — a seed is not worth failing over
            idle = 0.0
        with self._lock:
            if self._last is None:
                self._last = time.monotonic() - max(0.0, float(idle))

    def _run(self, ready):
        try:
            import Quartz
            from CoreFoundation import (CFRunLoopAddSource, CFRunLoopGetCurrent,
                                        CFRunLoopRun, kCFRunLoopCommonModes)
        except ImportError as exc:  # noqa: BLE001
            self.failed = f"pyobjc is not importable here ({exc})"
            ready.set()
            return

        mask = 0
        for name in _WANTED:
            mask |= Quartz.CGEventMaskBit(getattr(Quartz, name))

        def callback(proxy, etype, event, refcon):
            # A tap the system switched off answers nothing for the rest of the
            # night, and the night is the whole point — so put it back on.
            if etype in (Quartz.kCGEventTapDisabledByTimeout,
                         Quartz.kCGEventTapDisabledByUserInput):
                Quartz.CGEventTapEnable(self._tap, True)
                return event
            pid = Quartz.CGEventGetIntegerValueField(
                event, Quartz.kCGEventSourceUnixProcessID)
            if pid == 0:
                with self._lock:
                    self._last = time.monotonic()
            return event

        self._seed_from_system(Quartz)
        self._tap = Quartz.CGEventTapCreate(
            Quartz.kCGHIDEventTap, Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionListenOnly, mask, callback, None)
        if self._tap is None:
            self.failed = ("the event tap was refused — Accessibility is not "
                           "granted to this interpreter")
            ready.set()
            return

        source = Quartz.CFMachPortCreateRunLoopSource(None, self._tap, 0)
        self._runloop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(self._runloop, source, kCFRunLoopCommonModes)
        Quartz.CGEventTapEnable(self._tap, True)
        ready.set()
        CFRunLoopRun()


def main():
    watch = HumanWatch()
    if not watch.start():
        raise SystemExit(watch.failed)
    print("watching real input — move the mouse or type (Ctrl-C to stop)")
    try:
        while True:
            since = watch.since_human
            print(f"\rquiet for {since:7.1f}s" if since != float("inf")
                  else "\rno human event yet", end="", flush=True)
            time.sleep(0.25)
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
