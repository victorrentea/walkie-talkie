#!/usr/bin/env python3
"""The one thing in `helpers/wispr_loopback.py` that fails silently: the wait.

    python3 evals/test_wispr_loopback.py

Wispr inserts its History row when the key goes down and fills `asrText` in when
the network round-trip comes back. A wait that returns on "a new id appeared"
therefore reads a placeholder and reports silence for a clip that was
transcribed perfectly — which is what happened on 2026-09-19 with Wispr 1.6.897:
three clips out of three came back as *no transcript* while its own database
held `la Claude` and `Aqui testa, hã` for the same audio, written seconds later.

An overnight batch cannot notice this. It gives up after five consecutive
failures, so the bug does not show as a bad label — it shows as a night that
labelled nothing and a rig that looks broken.
"""

import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))

import wispr_loopback as lb  # noqa: E402


SCHEMA = """
CREATE TABLE History (
    transcriptEntityId TEXT PRIMARY KEY,
    timestamp TEXT,
    duration REAL,
    micDevice TEXT,
    asrText TEXT,
    formattedText TEXT,
    detectedLanguage TEXT
)
"""


class FakeWispr:
    """A History table that fills its transcript in after `fills_after` reads."""

    def __init__(self, fills_after, text="la Claude"):
        self.path = os.path.join(tempfile.mkdtemp(), "flow.sqlite")
        self.fills_after = fills_after
        self.text = text
        self.reads = 0
        db = sqlite3.connect(self.path)
        db.executescript(SCHEMA)
        db.execute("INSERT INTO History VALUES ('old', '2026-09-19 18:00:00', 3.0,"
                   " '🎓 TO Wispr (Virtual)', 'earlier clip', 'Earlier clip.', 'ro')")
        db.commit()
        db.close()

    def press(self):
        """Wispr's row at key-down: an id, a device, and no words yet."""
        db = sqlite3.connect(self.path)
        db.execute("INSERT INTO History VALUES ('new', '2026-09-19 18:05:00', 1.1,"
                   " '🎓 TO Wispr (Virtual)', '', '', 'ro')")
        db.commit()
        db.close()

    def open(self):
        self.reads += 1
        if self.reads > self.fills_after:
            db = sqlite3.connect(self.path)
            db.execute("UPDATE History SET asrText = ?, formattedText = ?"
                       " WHERE transcriptEntityId = 'new'", (self.text, self.text))
            db.commit()
            db.close()
        db = sqlite3.connect(self.path)
        db.row_factory = sqlite3.Row
        return db


class WaitForTranscript(unittest.TestCase):

    def setUp(self):
        self._real_open = lb._open_wispr

    def tearDown(self):
        lb._open_wispr = self._real_open

    def test_a_row_that_fills_in_later_is_still_the_transcript(self):
        fake = FakeWispr(fills_after=3)
        lb._open_wispr = fake.open
        fake.press()
        heard = lb.wait_for_new("old", timeout=5, poll=0.01)
        self.assertIsNotNone(heard, "the row was never read")
        self.assertEqual(heard.asr, "la Claude")
        self.assertEqual(heard.mic, "🎓 TO Wispr (Virtual)")

    def test_a_row_that_never_fills_in_fails_the_sample_not_the_night(self):
        """Wispr heard nothing. The wait ends on its own deadline, empty."""
        fake = FakeWispr(fills_after=10_000)
        lb._open_wispr = fake.open
        fake.press()
        heard = lb.wait_for_new("old", timeout=0.2, poll=0.01)
        self.assertIsNotNone(heard)
        self.assertEqual(heard.asr, "")

    def test_no_row_at_all_is_None(self):
        """The chord never reached Wispr — there is nothing to wait for."""
        fake = FakeWispr(fills_after=0)
        lb._open_wispr = fake.open
        self.assertIsNone(lb.wait_for_new("old", timeout=0.2, poll=0.01))

    def test_the_language_wispr_detected_comes_back_with_the_words(self):
        """A label in a language Victor does not speak is fluent, plausible and
        useless — the one thing that tells them apart is this column."""
        fake = FakeWispr(fills_after=1)
        lb._open_wispr = fake.open
        fake.press()
        heard = lb.wait_for_new("old", timeout=5, poll=0.01)
        self.assertEqual(heard.language, "ro")


class RunWindow(unittest.TestCase):
    """Every player announces its playback, so the harvester never files it as his.

    Only `teacher_label` used to; `wispr_probe` and every `wispr_loop` scenario played
    corpus clips and fixtures into Wispr unannounced (found by the Fable review,
    2026-11-25). The window lives in `play()` now."""

    def setUp(self):
        import json  # noqa: F401
        self._real = lb.RIG_RUNS
        lb.RIG_RUNS = tempfile.mkdtemp()
        lb.close_run_window()

    def tearDown(self):
        lb.close_run_window()
        lb.RIG_RUNS = self._real

    def read(self, path):
        import json
        with open(path) as fh:
            return json.load(fh)

    def test_a_touch_opens_a_window_that_names_this_process(self):
        lb.touch_run_window()
        run = self.read(lb._window)
        self.assertIsNone(run["to"])
        self.assertEqual(run["pid"], os.getpid())

    def test_closing_writes_the_end(self):
        lb.touch_run_window()
        path = lb._window
        lb.close_run_window()
        self.assertIsNotNone(self.read(path)["to"])
        self.assertIsNone(lb._window)

    def test_a_long_silence_closes_the_window_and_the_next_clip_opens_another(self):
        import time
        lb.touch_run_window()
        first = lb._window
        lb._window_touched = time.time() - lb.RUN_WINDOW_IDLE_SEC - 5
        lb.touch_run_window()
        self.assertNotEqual(lb._window, first)
        self.assertIsNotNone(self.read(first)["to"])

    def test_the_harvester_reads_it_as_the_rigs_own(self):
        import corpus_harvest as ch
        from datetime import datetime, timezone
        lb.touch_run_window()
        real, ch.RIG_RUNS = ch.RIG_RUNS, lb.RIG_RUNS
        try:
            now = datetime.now(timezone.utc)
            row = {"timestamp": now.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + " +00:00"}
            self.assertTrue(ch.is_the_rigs_own(row, ch.rig_windows()))
        finally:
            ch.RIG_RUNS = real


if __name__ == "__main__":
    unittest.main(verbosity=2)
