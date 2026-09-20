#!/usr/bin/env python3
"""The two labels that survive every other check and still must not be trained on.

    python3 evals/test_corpus_export.py

An audit of the corpus on 2026-09-20 found **zero** canned recogniser phrases in
`teacher_text` and **56 in `final_text`** — which is this script's default label. A
sentence like *Nu uitați să vă abonați la canal!* is the worst possible training
example: right length, right language, correct grammar, and words nobody said. It
cannot be caught by looking at the label alone, only by knowing the phrase.

The second guard is arithmetic: a label that carries more words than its audio has
room for belongs to a different clip, or is a repetition loop.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))

import corpus_export as ce  # noqa: E402


class Canned(unittest.TestCase):

    def test_the_phrases_actually_found_in_this_corpus(self):
        for text in ("Nu uitați să vă abonați la canal!",
                     "Să vă mulțumim pentru vizionare!",
                     "Subtitrarea realizată de echipa Amara.org",
                     "Thanks for watching!",
                     "...și la rețeta următoare!"):
            self.assertTrue(ce.is_canned(text), text)

    def test_victors_own_sentences_survive(self):
        for text in ("subscripția personală de Claude Code costă mai puțin",
                     "Treci pe YAML, JSON-ul e urât",
                     "Deci dacă acum pornesc o conversație nouă",
                     "Run everything before the agent says it is done"):
            self.assertFalse(ce.is_canned(text), text)

    def test_subscribe_alone_is_not_enough(self):
        """The anchor exists because he really does talk about subscriptions."""
        self.assertFalse(ce.is_canned("my subscribe button"))
        self.assertTrue(ce.is_canned("like and subscribe"))


class SpeakingRate(unittest.TestCase):

    def test_the_fastest_real_label_is_kept(self):
        """5.98 w/s, Romanian spoken fast — the corpus maximum on 2026-09-20."""
        self.assertFalse(ce.too_fast(" ".join(["cuvânt"] * 26), 4.3))

    def test_a_label_too_long_for_its_audio_is_dropped(self):
        self.assertTrue(ce.too_fast(" ".join(["cuvânt"] * 30), 3.0))

    def test_a_missing_duration_never_drops_anything(self):
        """Unknown is not suspicious, and dividing by it is worse."""
        self.assertFalse(ce.too_fast("orice text", 0))
        self.assertFalse(ce.too_fast("orice text", None))


if __name__ == "__main__":
    unittest.main(verbosity=2)
