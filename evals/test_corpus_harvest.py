#!/usr/bin/env python3
"""The corpus must not eat its own tail.

    python3 evals/test_corpus_harvest.py

The rig plays a corpus clip into Wispr; Wispr records it and keeps the recording; and
`corpus_harvest.py` — whose whole job is to rescue recordings before Wispr prunes them
— took it as a new dictation. Measured 2026-09-20: **1239 rows, 118 minutes, 1056 of
them word-for-word a label the rig had just written**, every one a padded copy of audio
already in the corpus, and every one of them would have been trained on twice.

Victor caught it from the outside, without a query: *"Eu nu am vorbit nimic de ieri în
microfon. Să nu înregistrezi ce redai tot tu."*

Nothing in the harvester could have noticed: the rows are real Wispr rows, with real
audio, a real transcript, and the same virtual microphone his own dictations use.
"""

import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))

import corpus_harvest as ch  # noqa: E402


class RigWindows(unittest.TestCase):

    def setUp(self):
        self._real = ch.RIG_RUNS
        ch.RIG_RUNS = tempfile.mkdtemp()

    def tearDown(self):
        ch.RIG_RUNS = self._real

    def write(self, name, start, end):
        with open(os.path.join(ch.RIG_RUNS, name), "w") as fh:
            json.dump({"from": start.isoformat(),
                       "to": end.isoformat() if end else None}, fh)

    def row(self, when):
        return {"timestamp": when.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + " +00:00"}

    def test_a_row_recorded_during_a_run_is_ours(self):
        now = datetime.now(timezone.utc)
        self.write("run.json", now - timedelta(hours=2), now - timedelta(minutes=30))
        self.assertTrue(ch.is_the_rigs_own(self.row(now - timedelta(hours=1)),
                                           ch.rig_windows()))

    def test_a_dictation_before_the_run_is_his(self):
        now = datetime.now(timezone.utc)
        self.write("run.json", now - timedelta(hours=2), now - timedelta(minutes=30))
        self.assertFalse(ch.is_the_rigs_own(self.row(now - timedelta(hours=5)),
                                            ch.rig_windows()))

    def test_a_dictation_well_after_the_run_is_his(self):
        now = datetime.now(timezone.utc)
        self.write("run.json", now - timedelta(hours=5), now - timedelta(hours=4))
        self.assertFalse(ch.is_the_rigs_own(self.row(now), ch.rig_windows()))

    def test_an_unclosed_window_means_still_running(self):
        """A run killed before it could write its end must not open the gates."""
        now = datetime.now(timezone.utc)
        self.write("run.json", now - timedelta(minutes=10), None)
        self.assertTrue(ch.is_the_rigs_own(self.row(now - timedelta(minutes=1)),
                                           ch.rig_windows()))

    def test_the_tail_of_the_last_clip_is_still_ours(self):
        """Wispr writes its row at the key press and finishes seconds later, so a
        window ending at the last chord would let the last clip through."""
        now = datetime.now(timezone.utc)
        end = now - timedelta(seconds=30)
        self.write("run.json", now - timedelta(hours=1), end)
        self.assertTrue(ch.is_the_rigs_own(self.row(end + timedelta(seconds=20)),
                                           ch.rig_windows()))

    def test_no_windows_at_all_keeps_everything(self):
        """With no rig runs on record the harvester behaves exactly as before."""
        self.assertFalse(ch.is_the_rigs_own(self.row(datetime.now(timezone.utc)), []))

    def test_rubbish_on_disk_is_ignored_rather_than_fatal(self):
        with open(os.path.join(ch.RIG_RUNS, "broken.json"), "w") as fh:
            fh.write("{not json")
        self.assertEqual(ch.rig_windows(), [])


class UnclosedWindows(unittest.TestCase):
    """An end that was never written must not stop the harvest for ever.

    2026-09-20: one labelling run died without closing its window, and every Wispr
    recording for the next two months was read as the rig's own playback and left in
    Wispr until it pruned them (found by the Fable review, 2026-11-25)."""

    def setUp(self):
        self._real = ch.RIG_RUNS
        ch.RIG_RUNS = tempfile.mkdtemp()

    def tearDown(self):
        ch.RIG_RUNS = self._real

    def write(self, start, pid=None, touched=None):
        path = os.path.join(ch.RIG_RUNS, "run.json")
        run = {"from": start.isoformat(), "to": None}
        if pid is not None:
            run["pid"] = pid
        with open(path, "w") as fh:
            json.dump(run, fh)
        if touched is not None:
            os.utime(path, (touched.timestamp(), touched.timestamp()))

    def row(self, when):
        return {"timestamp": when.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + " +00:00"}

    def dead_pid(self):
        import subprocess
        p = subprocess.Popen(["true"])
        p.wait()
        return p.pid

    def test_a_live_player_that_touched_it_recently_is_still_running(self):
        now = datetime.now(timezone.utc)
        self.write(now - timedelta(hours=1), pid=os.getpid(),
                   touched=now - timedelta(minutes=1))
        self.assertTrue(ch.is_the_rigs_own(self.row(now), ch.rig_windows()))

    def test_a_dead_player_ended_at_its_last_touch(self):
        now = datetime.now(timezone.utc)
        self.write(now - timedelta(days=60), pid=self.dead_pid(),
                   touched=now - timedelta(days=59))
        windows = ch.rig_windows()
        self.assertFalse(ch.is_the_rigs_own(self.row(now), windows))
        self.assertTrue(ch.is_the_rigs_own(self.row(now - timedelta(days=59, minutes=5)),
                                           windows))

    def test_a_live_but_idle_player_ended_at_its_last_touch(self):
        """A recycled pid, or a player that stopped playing long ago."""
        now = datetime.now(timezone.utc)
        self.write(now - timedelta(hours=5), pid=os.getpid(),
                   touched=now - timedelta(hours=4))
        self.assertFalse(ch.is_the_rigs_own(self.row(now), ch.rig_windows()))

    def test_a_window_with_no_process_is_believed_for_a_day_at_most(self):
        """The September file: no pid, no end."""
        now = datetime.now(timezone.utc)
        self.write(now - timedelta(days=60))
        windows = ch.rig_windows()
        self.assertFalse(ch.is_the_rigs_own(self.row(now - timedelta(days=30)), windows))
        self.assertTrue(ch.is_the_rigs_own(self.row(now - timedelta(days=60) + timedelta(hours=2)),
                                           windows))

    def test_a_key_pressed_just_before_the_window_is_still_ours(self):
        now = datetime.now(timezone.utc)
        start = now - timedelta(minutes=10)
        self.write(start, pid=os.getpid(), touched=now)
        self.assertTrue(ch.is_the_rigs_own(self.row(start - timedelta(seconds=5)),
                                           ch.rig_windows()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
