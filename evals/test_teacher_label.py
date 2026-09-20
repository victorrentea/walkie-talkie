#!/usr/bin/env python3
"""The batch's rhythm, which is the half of it a service can see.

    python3 evals/test_teacher_label.py

The labeller presses Wispr's key a thousand times a night on Victor's own paid
account. The audio is his and the transcripts are his, so nothing here is hiding
anything — but a run that presses every 2.0 s for six hours is regular in a way
no person dictating could be, and regularity is the cheapest automation signal
there is. `gaps()` is what keeps the batch from producing one, so it is worth a
test: a constant would pass every other check in this repo silently.
"""

import os
import pathlib
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))

import teacher_label as tl  # noqa: E402


class Rhythm(unittest.TestCase):

    def sample(self, n=400, seed=7):
        gen = tl.gaps(random.Random(seed))
        return [next(gen) for _ in range(n)]

    def test_no_two_gaps_are_the_same(self):
        """A constant — the bug this file exists for — would collapse this set."""
        gaps = self.sample()
        self.assertGreater(len(set(gaps)), len(gaps) * 0.9)

    def test_every_gap_is_one_of_the_two_shapes(self):
        for g in self.sample():
            short = tl.GAP_MIN <= g <= tl.GAP_MAX
            long_ = tl.LONG_PAUSE_SEC[0] <= g <= tl.LONG_PAUSE_SEC[1]
            self.assertTrue(short or long_, "%.2fs is neither a gap nor a pause" % g)

    def test_the_long_pause_happens_about_as_often_as_it_claims(self):
        gaps = self.sample(n=600)
        longs = [g for g in gaps if g >= tl.LONG_PAUSE_SEC[0]]
        low, high = tl.LONG_PAUSE_EVERY
        self.assertTrue(len(gaps) / high * 0.6 <= len(longs) <= len(gaps) / low * 1.4,
                        "%d long pauses in %d samples" % (len(longs), len(gaps)))

    def test_two_runs_do_not_share_a_rhythm(self):
        """No seed in production: last night's pattern must not be tonight's."""
        a = [next(tl.gaps()) for _ in range(30)]
        b = [next(tl.gaps()) for _ in range(30)]
        self.assertNotEqual(a, b)

    def test_the_estimate_counts_the_pauses(self):
        """The batch prints hours up front; a mean that ignores the long pause lies."""
        self.assertGreater(tl.MEAN_GAP_SEC, (tl.GAP_MIN + tl.GAP_MAX) / 2)


class Lead(unittest.TestCase):

    def test_the_lead_clears_wisprs_startup(self):
        """Wispr needs about a second before it is listening; the lead covers it."""
        self.assertGreaterEqual(tl.rig.LEAD_SEC, 1.0)


class WallClockBudget(unittest.TestCase):
    """`--minutes` counts audio; a night counts hours. The two stopped agreeing
    when 3398 mic clips of 7.8 s each landed in the pool: 300 audio minutes of
    them is 2300 dictations and nearly twelve hours of wall clock."""

    def test_no_budget_never_stops(self):
        self.assertFalse(tl.out_of_time(started=0.0, budget_hours=None))
        self.assertFalse(tl.out_of_time(started=0.0, budget_hours=0))

    def test_a_spent_budget_stops(self):
        import time
        self.assertTrue(tl.out_of_time(started=time.monotonic() - 3 * 3600,
                                       budget_hours=2))

    def test_an_unspent_budget_does_not(self):
        import time
        self.assertFalse(tl.out_of_time(started=time.monotonic() - 600,
                                        budget_hours=7))


class Backoff(unittest.TestCase):
    """Five failures in a row is not proof of a dead rig. On 2026-09-20 it was Wispr
    answering `raw_transcript` with zero words after 357 dictations in 95 minutes —
    transcribing again two minutes later. The old rule threw away the five hours that
    were left; the ladder waits instead, and still stops for a rig that is really down."""

    def test_the_first_answer_to_a_streak_is_a_pause(self):
        self.assertEqual(tl.backoff_for(0), tl.BACKOFF_SEC[0])

    def test_the_pauses_get_longer(self):
        pauses = [tl.backoff_for(i) for i in range(len(tl.BACKOFF_SEC))]
        self.assertEqual(pauses, sorted(pauses))
        self.assertEqual(len(set(pauses)), len(pauses))

    def test_it_still_gives_up_in_the_end(self):
        self.assertIsNone(tl.backoff_for(len(tl.BACKOFF_SEC)))
        self.assertIsNone(tl.backoff_for(99))

    def test_the_ladder_is_shorter_than_a_night(self):
        """A night is seven hours; a ladder that outlasts it never reaches its own end."""
        self.assertLess(sum(tl.BACKOFF_SEC), 2 * 3600)


class Cooldown(unittest.TestCase):
    """Three blocked stretches in a row is the service saying no. The ladder already
    stops the run; this is what stops the *next* one. Without it, 2026-09-20 went
    give-up at 06:23, restart at 06:36, and another fifty minutes of dictating into an
    account that was refusing — the exact behaviour that gets an account banned."""

    def setUp(self):
        self._real = tl.COOLDOWN_FILE
        self._tmp = tempfile.mkdtemp()
        tl.COOLDOWN_FILE = pathlib.Path(self._tmp) / "cooldown"

    def tearDown(self):
        tl.COOLDOWN_FILE = self._real

    def test_no_file_means_free_to_run(self):
        self.assertEqual(tl.cooldown_left(), 0.0)

    def test_a_started_cooldown_blocks_the_next_run(self):
        tl.start_cooldown(hours=2)
        self.assertGreater(tl.cooldown_left(), 1.9)

    def test_it_expires_on_its_own(self):
        tl.start_cooldown(hours=-1)
        self.assertEqual(tl.cooldown_left(), 0.0)

    def test_a_run_that_worked_clears_it(self):
        tl.start_cooldown(hours=2)
        tl.clear_cooldown()
        self.assertEqual(tl.cooldown_left(), 0.0)

    def test_rubbish_on_disk_does_not_wedge_the_rig(self):
        """A half-written file must not become a permanent refusal to work."""
        tl.COOLDOWN_FILE.write_text("not a date")
        self.assertEqual(tl.cooldown_left(), 0.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
