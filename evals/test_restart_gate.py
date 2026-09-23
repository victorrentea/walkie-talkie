#!/usr/bin/env python3
"""Unit tests for `tools/restart_gate.py` — the gate `relay-restart.sh` waits on.

Fake clock, fabricated `/test/state` readings, nothing touches the running relay.
Run: `python3 evals/test_restart_gate.py`.
"""
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from restart_gate import Gate, busy_reasons  # noqa: E402

T0 = 1_800_000_000.0


def iso(t: float) -> str:
    return datetime.fromtimestamp(t, tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def idle(delivered_at=None, **extra):
    s = {"busy": False, "busyWhy": [], "lastDelivery": {"at": iso(delivered_at)} if delivered_at else None}
    s.update(extra)
    return s


def busy(*why, delivered_at=None):
    return {"busy": True, "busyWhy": list(why), "lastDelivery": {"at": iso(delivered_at)} if delivered_at else None}


class GateTest(unittest.TestCase):
    def test_idle_with_old_delivery_opens_at_once(self):
        self.assertTrue(Gate().observe(T0, idle(delivered_at=T0 - 60)).ready)

    def test_idle_with_no_history_opens_at_once(self):
        self.assertTrue(Gate().observe(T0, idle()).ready)

    def test_busy_never_opens(self):
        g = Gate()
        for i in range(120):
            v = g.observe(T0 + i, busy("microphone open"))
            self.assertFalse(v.ready)
        self.assertIn("microphone open", v.waiting_for)

    def test_waits_ten_seconds_after_a_fresh_delivery(self):
        g = Gate()
        delivered = T0 - 3
        self.assertFalse(g.observe(T0, idle(delivered_at=delivered)).ready)
        self.assertFalse(g.observe(T0 + 6.9, idle(delivered_at=delivered)).ready)
        self.assertTrue(g.observe(T0 + 7.0, idle(delivered_at=delivered)).ready)

    def test_ten_seconds_after_the_last_busy_poll(self):
        g = Gate()
        g.observe(T0, busy("transcribing"))
        # The words landed, but the delivery stamp is older than the last busy poll.
        for i in range(1, 10):
            self.assertFalse(g.observe(T0 + i, idle(delivered_at=T0 - 1)).ready, i)
        self.assertTrue(g.observe(T0 + 10, idle(delivered_at=T0 - 1)).ready)

    def test_new_activity_restarts_the_countdown(self):
        g = Gate()
        g.observe(T0, idle(delivered_at=T0))
        self.assertFalse(g.observe(T0 + 8, busy("dictating", "microphone open")).ready)
        self.assertFalse(g.observe(T0 + 12, idle(delivered_at=T0 + 11)).ready)
        self.assertFalse(g.observe(T0 + 20.9, idle(delivered_at=T0 + 11)).ready)
        self.assertTrue(g.observe(T0 + 21, idle(delivered_at=T0 + 11)).ready)

    def test_a_delivery_between_polls_is_seen(self):
        # A whole short sentence between two polls leaves only its delivery stamp behind.
        g = Gate()
        self.assertTrue(g.observe(T0, idle(delivered_at=T0 - 100)).ready)
        g2 = Gate()
        g2.observe(T0, idle(delivered_at=T0 - 100))
        self.assertFalse(g2.observe(T0 + 1, idle(delivered_at=T0 + 0.5)).ready)

    def test_a_dictation_start_counts_as_activity(self):
        g = Gate()
        self.assertFalse(g.observe(T0, idle(dictationStartedAt=iso(T0 - 2))).ready)

    def test_outbox_write_counts_as_activity(self):
        g = Gate()
        self.assertFalse(g.observe(T0, idle(), outbox_mtime=T0 - 4).ready)
        self.assertTrue(g.observe(T0 + 6, idle(), outbox_mtime=T0 - 4).ready)

    def test_unreachable_is_not_idle_until_a_minute(self):
        g = Gate()
        self.assertFalse(g.observe(T0, None).ready)
        self.assertFalse(g.observe(T0 + 59, {"ok": False, "error": "main thread"}).ready)
        v = g.observe(T0 + 60, None)
        self.assertTrue(v.ready)
        self.assertIn("wedged", v.note)

    def test_answering_again_resets_the_unreachable_clock(self):
        g = Gate()
        g.observe(T0, None)
        g.observe(T0 + 30, busy("transcribing"))
        self.assertFalse(g.observe(T0 + 61, None).ready)

    def test_stuck_listening_flag_is_let_go_after_30s(self):
        g = Gate()
        for i in range(30):
            self.assertFalse(g.observe(T0 + i, busy("dictating")).ready)
        v = g.observe(T0 + 30, busy("dictating"))
        self.assertFalse(v.ready)          # the flag is let go, then the quiet window runs
        self.assertIn("stuck flag", v.note)
        self.assertTrue(g.observe(T0 + 39, busy("dictating")).ready)

    def test_listening_with_a_microphone_is_never_stale(self):
        g = Gate()
        for i in range(200):
            self.assertFalse(g.observe(T0 + i, busy("dictating", "microphone open")).ready)


class OldBuildTest(unittest.TestCase):
    """A running build older than 2026-09-23 has no `busy`; the flags it has decide."""

    def test_idle_done(self):
        self.assertEqual(busy_reasons({"listening": False, "isRecording": False, "phase": "done"}), [])

    def test_wispr_capture_after_the_ring(self):
        # Measured live on 2026-09-23: phase `done`, listening false, Wispr's mic and capture still up.
        s = {"listening": False, "isRecording": True, "capturing": True, "phase": "done"}
        self.assertEqual(busy_reasons(s), ["microphone open", "Wispr sentence"])

    def test_every_flag(self):
        s = {"listening": True, "isRecording": True, "wisprHearing": True, "phase": "transcribing",
             "awaitingBind": True, "arrowsUp": True, "filming": True}
        self.assertEqual(busy_reasons(s), ["dictating", "microphone open", "Wispr sentence",
                                           "transcribing", "held for a bind", "delivering", "filming"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
