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
import random
import sys
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
