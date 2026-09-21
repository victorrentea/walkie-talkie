#!/usr/bin/env python3
"""The batch must get out of Victor's way, and get back in without a paste.

    python3 evals/test_human_gate.py

`teacher_label.Gate` is the half of the auto-suspend that has no hardware in it,
and it is the half where a mistake is expensive in a way nobody sees until the
morning: locks left standing over a suspended run, or — much worse — a run that
resumes while his own editor is in front and types a sentence of his own speech
into it.

The tap itself (`helpers/human_watch.py`) is not tested here. It was *measured*
on 2026-09-22 instead, which is the only way that question can be answered:
hardware events carry `kCGEventSourceUnixProcessID == 0` and everything posted
with `CGEventPost` carries the poster's pid, so the tap ignores its own batch's
keystrokes. `python3 helpers/human_watch.py` is the live readout.
"""

from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "helpers"))

os.environ.setdefault("TEACHER_STATUS", "/tmp/teacher-status-test.json")

import teacher_label as tl  # noqa: E402


class FakeWatch:
    """A `HumanWatch` whose clock the test moves by hand."""

    def __init__(self, since=999.0):
        self.since_human = since
        self.touched = 0

    def active_since(self, mark):
        return self.since_human < time.monotonic() - mark

    def touch(self):
        self.touched += 1
        self.since_human = 0.0


class FakeLocks:
    def __init__(self):
        self.up = False
        self.raised = 0
        self.released = 0

    def acquire(self):
        self.up = True
        self.raised += 1

    def release(self):
        self.up = False
        self.released += 1


class GateBehaviour(unittest.TestCase):
    def setUp(self):
        self.lines = []
        self.watch = FakeWatch()
        self.locks = FakeLocks()
        self.locks.acquire()
        self.fronts = []
        self.woken = 0
        # The front app is the one real thing the gate reaches for, so it is the
        # one thing stubbed: the test says what is in front at each reading.
        self._paste_sink = tl.rig.paste_sink
        self._wake = tl.wake_the_sink
        tl.rig.paste_sink = lambda: self.fronts.pop(0) if self.fronts else "TextEdit"
        tl.wake_the_sink = self._fake_wake

    def tearDown(self):
        tl.rig.paste_sink = self._paste_sink
        tl.wake_the_sink = self._wake

    def _fake_wake(self):
        self.woken += 1
        return self.fronts.pop(0) if self.fronts else "TextEdit"

    def gate(self, quiet=0.2):
        return tl.Gate(self.watch, self.locks, quiet, self.lines.append)

    def test_a_quiet_mac_is_not_suspended_at_all(self):
        gate = self.gate()
        self.assertEqual(gate.wait_for_quiet({}), 0.0)
        self.assertEqual(gate.suspensions, 0)
        self.assertTrue(self.locks.up)
        self.assertEqual(self.lines, [])

    def test_the_locks_come_down_while_he_is_using_his_mac(self):
        """🔒 over a man typing says *do not touch your own Mac* to his own Mac."""
        gate = self.gate()
        seen = []
        # Busy for the first three readings, then the Mac goes quiet. Each
        # reading records whether the locks were up at that moment.
        readings = [0.0, 0.1, 0.2, 99.0, 99.0]

        def scripted(_self):
            seen.append(self.locks.up)
            return readings.pop(0) if readings else 99.0

        type(self.watch).since_human = property(scripted)
        try:
            waited = gate.wait_for_quiet({})
        finally:
            del type(self.watch).since_human
        self.assertGreater(waited, 0)
        self.assertEqual(gate.suspensions, 1)
        # The first reading is the decision to suspend, made with the locks
        # still up; every reading after it happens inside the wait.
        self.assertTrue(seen[0])
        self.assertFalse(any(seen[1:]), "locks stayed up while he was typing")
        self.assertTrue(self.locks.up, "locks did not come back for the resume")
        self.assertTrue(any("⏸" in line for line in self.lines))
        self.assertTrue(any("▶️" in line for line in self.lines))

    def test_it_will_not_resume_into_his_own_editor(self):
        """The front app after a suspension is whatever he left there."""
        self.watch.since_human = 0.0
        gate = self.gate(quiet=0.05)
        # busy once, then quiet; front is his editor, TextEdit comes forward.
        readings = [0.0, 9.0, 9.0, 9.0, 9.0, 9.0]
        type(self.watch).since_human = property(
            lambda _self: readings.pop(0) if readings else 9.0)
        self.fronts = ["Code", "TextEdit"]
        try:
            gate.wait_for_quiet({})
        finally:
            del type(self.watch).since_human
        self.assertEqual(self.woken, 1, "TextEdit was never brought forward")
        self.assertTrue(any("resumed" in line for line in self.lines))

    def test_abort_fires_only_for_input_after_the_clip_started(self):
        gate = self.gate()
        started = time.monotonic()
        self.watch.since_human = 999.0
        self.assertFalse(gate.abort_predicate(started)())
        time.sleep(0.05)
        self.watch.since_human = 0.0          # he just touched it
        self.assertTrue(gate.abort_predicate(started)())


if __name__ == "__main__":
    unittest.main(verbosity=2)
