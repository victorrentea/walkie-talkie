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
from restart_gate import QUIET_AFTER_DELIVERY, Gate, busy_reasons, is_installed_app, runner_lock_reason  # noqa: E402

T0 = 1_800_000_000.0


def iso(t: float) -> str:
    return datetime.fromtimestamp(t, tz=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def idle(delivered_at=None, **extra):
    s = {"busy": False, "busyWhy": [], "lastDelivery": {"at": iso(delivered_at)} if delivered_at else None}
    s.update(extra)
    return s


def row(status, started, finished=None, rowid=17893):
    """Wispr's newest History row, as `wispr_newest_row` reads it."""
    return {"id": rowid, "status": status, "started_at": started, "finished_at": finished}


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

    def test_audio_staged_for_recover_keeps_it_closed(self):
        # TL18 (batch 6): a restart wipes cancelled/ — from the app's busyWhy, and from
        # `recoverable` alone for a build that does not count it yet.
        staged = {"path": "/x/cancelled-12-00-00.wav", "duration": 5.8}
        for s in (busy("audio staged for Recover (280 s left)"), idle(recoverable=staged)):
            g = Gate()
            v = g.observe(T0, s)
            self.assertFalse(v.ready)
            self.assertIn("Recover", v.waiting_for)
        # …and once it is gone, the five quiet seconds start from the last poll that saw it.
        g = Gate()
        g.observe(T0, idle(recoverable=staged))
        self.assertFalse(g.observe(T0 + 4, idle(recoverable=None)).ready)
        self.assertTrue(g.observe(T0 + 5, idle(recoverable=None)).ready)

    def test_waits_five_seconds_after_a_fresh_delivery(self):
        # 2026-09-28 21:20: *"only 5 seconds since the last ended dictation"* (it was 10).
        g = Gate()
        delivered = T0 - 3
        self.assertFalse(g.observe(T0, idle(delivered_at=delivered)).ready)
        self.assertFalse(g.observe(T0 + 1.9, idle(delivered_at=delivered)).ready)
        self.assertTrue(g.observe(T0 + 2.0, idle(delivered_at=delivered)).ready)

    def test_five_seconds_after_the_last_busy_poll(self):
        g = Gate()
        g.observe(T0, busy("transcribing"))
        # The words landed, but the delivery stamp is older than the last busy poll.
        for i in range(1, 5):
            self.assertFalse(g.observe(T0 + i, idle(delivered_at=T0 - 1)).ready, i)
        self.assertTrue(g.observe(T0 + 5, idle(delivered_at=T0 - 1)).ready)

    def test_new_activity_restarts_the_countdown(self):
        g = Gate()
        g.observe(T0, idle(delivered_at=T0))
        self.assertFalse(g.observe(T0 + 3, busy("dictating", "microphone open")).ready)
        self.assertFalse(g.observe(T0 + 12, idle(delivered_at=T0 + 11)).ready)
        self.assertFalse(g.observe(T0 + 15.9, idle(delivered_at=T0 + 11)).ready)
        self.assertTrue(g.observe(T0 + 16, idle(delivered_at=T0 + 11)).ready)

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

    def test_unreachable_is_never_idle_and_is_refused_after_a_minute(self):
        # 2026-09-28: the old "wedged for a minute → go ahead" escape is gone.
        g = Gate()
        self.assertFalse(g.observe(T0, None).ready)
        v = g.observe(T0 + 59, {"ok": False, "error": "main thread"})
        self.assertFalse(v.ready)
        self.assertFalse(v.refused)
        v = g.observe(T0 + 70, None)
        self.assertFalse(v.ready)
        self.assertTrue(v.refused)
        self.assertIn("refusing", v.note)
        self.assertIn("--force", v.note)

    def test_force_goes_past_unreachable_but_not_past_wispr(self):
        g = Gate(force=True)
        g.observe(T0, None)
        v = g.observe(T0 + 70, None, wispr_row=row("", T0 + 60))
        self.assertFalse(v.ready)
        self.assertFalse(v.refused)
        self.assertIn("Wispr Flow transcribing", v.waiting_for)
        self.assertFalse(g.observe(T0 + 65, None, wispr_row=row("formatted", T0 + 60, finished=T0 + 62)).ready)
        self.assertTrue(g.observe(T0 + 90, None, wispr_row=row("formatted", T0 + 60, finished=T0 + 62)).ready)

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


class DictatingOnAnyEngineTest(unittest.TestCase):
    """2026-09-28 18:39 — the restart over his dictation. Victor: *"restart is only
    possible after 5 secs of inactivity after the last insert of text."*"""

    def test_constants_are_his(self):
        # 21:20 the same day: *"only 5 seconds since the last ended dictation"*.
        self.assertEqual(QUIET_AFTER_DELIVERY, 5.0)

    def test_wispr_microphone_open_is_not_safe(self):
        # A build from before the fix: busy false, only wisprLive says it.
        v = Gate().observe(T0, idle(wisprLive={"micOpen": True}))
        self.assertFalse(v.ready)
        self.assertIn("Wispr Flow's microphone open", v.waiting_for)

    def test_wispr_row_processing_20s_old_is_not_safe(self):
        for status in ("", "processing"):
            v = Gate().observe(T0, idle(), wispr_row=row(status, T0 - 20))
            self.assertFalse(v.ready, status)
            self.assertIn("Wispr Flow transcribing (row 17893", v.waiting_for)
        # `raw_transcript` is final in Wispr's own code (batch 3, 2026-09-28): a finished row.
        self.assertTrue(Gate().observe(T0, idle(), wispr_row=row("raw_transcript", T0 - 20, finished=T0 - 19)).ready)

    def test_a_stalled_wispr_row_ages_out_after_a_minute(self):
        self.assertTrue(Gate().observe(T0, idle(), wispr_row=row("", T0 - 61)).ready)

    def test_a_wispr_row_just_finished_is_an_insert(self):
        g = Gate()
        self.assertFalse(g.observe(T0, idle(), wispr_row=row("formatted", T0 - 8, finished=T0 - 4)).ready)
        self.assertTrue(g.observe(T0 + 6, idle(), wispr_row=row("formatted", T0 - 8, finished=T0 - 4)).ready)

    def test_the_app_saying_wispr_is_not_said_twice(self):
        s = busy("Wispr Flow transcribing (row 17893, 3 s old)")
        v = Gate().observe(T0, s, wispr_row=row("", T0 - 3))
        self.assertEqual(v.waiting_for.count("Wispr Flow transcribing"), 1)

    def test_his_hands_do_not_hold_the_gate(self):
        # 21:20: typing is not a dictation — a key 0.4 s ago with nothing dictating is safe.
        self.assertTrue(Gate().observe(T0, idle(delivered_at=T0 - 600), input_at=T0 - 0.4).ready)
        self.assertTrue(Gate().observe(T0, idle(lastInputAt=iso(T0 - 0.4))).ready)

    def test_delivery_12s_ago_nothing_open_is_safe(self):
        s = idle(delivered_at=T0 - 12, lastInputAt=iso(T0 - 6),
                 wisprLive={"micOpen": False, "captureOpen": False}, liveCaption={"open": False},
                 sentences=[], fallingBack=False)
        self.assertTrue(Gate().observe(T0, s, wispr_row=row("formatted", T0 - 300, finished=T0 - 296),
                                       input_at=T0 - 6).ready)

    def test_an_insert_restarts_five_seconds(self):
        g = Gate()
        self.assertFalse(g.observe(T0, idle(lastInsertAt=iso(T0 - 4)), input_at=T0 - 100).ready)
        self.assertTrue(g.observe(T0 + 1, idle(lastInsertAt=iso(T0 - 4)), input_at=T0 - 100).ready)

    def test_a_dictation_edge_counts(self):
        self.assertFalse(Gate().observe(T0, idle(lastDictationEdgeAt=iso(T0 - 2))).ready)

    def test_relay_states_a_build_before_the_fix_did_not_count(self):
        for extra, word in (({"fallingBack": True}, "local fallback"),
                            ({"sentences": [{"id": 3, "state": "transcribing"}]}, "sentence in the queue"),
                            ({"liveCaption": {"open": True}}, "live caption open"),
                            ({"wisprLive": {"captureOpen": True}}, "Wispr sentence")):
            v = Gate().observe(T0, idle(**extra))
            self.assertFalse(v.ready, extra)
            self.assertIn(word, v.waiting_for)
        self.assertTrue(Gate().observe(T0, idle(sentences=[{"id": 3, "state": "done"}])).ready)

    def test_incident_2026_09_28_1839(self):
        # What the gate saw: busy false, the last delivery 83 s old — and a Wispr
        # sentence of his own (chord 61+60) in flight, invisible to the relay's
        # `busy` of that build. Now the row in Wispr's own file holds the gate,
        # and its finish is an ended dictation the five seconds count from.
        s = idle(delivered_at=T0 - 83)
        self.assertTrue(Gate().observe(T0, s).ready)                                  # the old reading
        g = Gate()
        self.assertFalse(g.observe(T0, s, wispr_row=row("", T0 - 3)).ready)           # his sentence
        self.assertFalse(g.observe(T0 + 6, s, wispr_row=row("formatted", T0 - 3, finished=T0 + 4)).ready)
        self.assertTrue(g.observe(T0 + 9, s, wispr_row=row("formatted", T0 - 3, finished=T0 + 4)).ready)


class RunnerLockTest(unittest.TestCase):
    """2026-09-28 21:26 — an install landed between two sentences of a desk run."""

    def test_live_runner_holds_the_gate(self):
        r = runner_lock_reason("96221 2026-09-28T21:20:03\n", alive=lambda pid: pid == 96221)
        self.assertIn("runner lock", r)
        self.assertIn("96221", r)

    def test_dead_runner_does_not(self):
        self.assertIsNone(runner_lock_reason("96221 2026-09-28T21:20:03\n", alive=lambda pid: False))
        self.assertIsNone(runner_lock_reason("", alive=lambda pid: True))
        self.assertIsNone(runner_lock_reason("garbage", alive=lambda pid: True))


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


class WhichRelayTest(unittest.TestCase):
    """A debug instance on a lower port is not the installed app (Fable review, 2026-11-25)."""

    def test_a_debug_instance_is_not_the_installed_app(self):
        self.assertFalse(is_installed_app(idle(pid=900), {501}))

    def test_the_installed_app_is_believed(self):
        self.assertTrue(is_installed_app(idle(pid=501), {501}))

    def test_no_installed_app_or_no_pid_believes_any_answer(self):
        self.assertTrue(is_installed_app(idle(pid=900), set()))
        self.assertTrue(is_installed_app(idle(), {501}))


if __name__ == "__main__":
    unittest.main(verbosity=1)
