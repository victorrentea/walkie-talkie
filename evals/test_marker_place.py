#!/usr/bin/env python3
"""The timestamp marker's seams, asserted against a running relay.

    python3 evals/test_marker_place.py

`ShotMarker.place` puts a screenshot reference, a highlight or a picked element
into the transcript **at the second he pressed**, using the word timings the
recogniser returned. The mechanism is arithmetic and the arithmetic is easy; what
is not easy, and what every previous marker attempt got wrong somewhere, is the
**seam** — the gap in front of the insertion, the space after it, two markers on
one word, a marker past the last word, a highlight whose own indentation must
survive being quoted into the middle of a sentence.

None of that is eyeballable. So it is driven through `POST /test/shot-marker`,
where `words` stands in for what Scribe returned and `cues` for the presses:

    {"words": [{"text": "label", "start": 15.0, "end": 15.6, "type": "word"}, …],
     "cues":  [{"kind": "shot", "index": 1, "at": 15.7}],
     "available": [1]}

It touches nothing in the running relay — no dictation, no microphone, no
delivery — so it is safe to run while Victor is working. The **other** half, that
a press really does land on the recording's own clock, is not fakeable and is not
here: it is `⏱️ marker cue: … at N.NNs into the recording` in `relay.log`, filed
by `reserveMarkerLocked` against `MicRecorder.offset(of:)`.

The last case is the guard that matters most: the **spoken** path
(`ShotMarker.resolve`, retired but not deleted) must go on working untouched, so
that `WT_SHOT_MARKERS=1` is still a way back.
"""

import json
import sys
import unittest
import urllib.request

PORTS = (8917, 8918, 8919)


def _find_relay():
    for port in PORTS:
        try:
            base = "http://localhost:%d" % port
            with urllib.request.urlopen(base + "/up", timeout=2) as r:
                if json.loads(r.read().decode()).get("ok"):
                    return base
        except Exception:
            continue
    return None


BASE = _find_relay()


def marker(**body):
    req = urllib.request.Request(
        BASE + "/test/shot-marker",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read().decode())["text"]


def tokens(*words):
    """`words[]` as Scribe returns it: alternating word and `spacing` entries.

    300 ms a word, 100 ms a gap — so word *n* starts at 0.4n and the gap in
    front of it runs 0.4n-0.1 … 0.4n. Every `at` below is picked against that.
    """
    out, t = [], 0.0
    for i, w in enumerate(words):
        out.append({"text": w, "start": round(t, 2), "end": round(t + 0.3, 2),
                    "type": "word"})
        t += 0.3
        if i < len(words) - 1:
            out.append({"text": " ", "start": round(t, 2), "end": round(t + 0.1, 2),
                        "type": "spacing"})
            t += 0.1
    return out


# pune 0.0 · asta 0.4 · sub 0.8 · un 1.2 · strat 1.6
WORDS = tokens("pune", "asta", "sub", "un", "strat")


@unittest.skipIf(BASE is None, "no relay listening on %s" % (PORTS,))
class Seams(unittest.TestCase):

    def test_it_lands_in_the_gap_he_left(self):
        """The ordinary case: pressed between two words."""
        self.assertEqual(
            marker(words=WORDS, available=[1],
                   cues=[{"kind": "shot", "index": 1, "at": 0.75}]),
            "pune asta (screenshot: shot#01) sub un strat")

    def test_a_press_inside_a_word_still_lands_between_two(self):
        """0.72 is inside `asta`'s own gap, not on a boundary — and the
        insertion must still not cut a word, which is the single failure the
        spliced marker could never avoid (`pus sub un-` / `Strat`)."""
        self.assertEqual(
            marker(words=WORDS, available=[1],
                   cues=[{"kind": "shot", "index": 1, "at": 0.72}]),
            "pune asta (screenshot: shot#01) sub un strat")

    def test_before_the_first_word_and_after_the_last(self):
        """A press before he started talking belongs at the front; one after he
        stopped belongs at the end. Neither leaves a stray space."""
        self.assertEqual(
            marker(words=WORDS, available=[1],
                   cues=[{"kind": "shot", "index": 1, "at": 0.0}]),
            "(screenshot: shot#01) pune asta sub un strat")
        self.assertEqual(
            marker(words=WORDS, available=[1],
                   cues=[{"kind": "shot", "index": 1, "at": 99.0}]),
            "pune asta sub un strat (screenshot: shot#01)")

    def test_two_presses_on_one_word_are_one_space_apart(self):
        """Two pictures a third of a second apart: both references, no double
        space between them — the seam nothing tidies, because an insertion is
        delivered byte for byte."""
        self.assertEqual(
            marker(words=WORDS, available=[1, 2],
                   cues=[{"kind": "shot", "index": 1, "at": 0.75},
                         {"kind": "shot", "index": 2, "at": 0.76}]),
            "pune asta (screenshot: shot#01) (screenshot: shot#02) sub un strat")

    def test_cues_are_placed_in_time_order_not_arrival_order(self):
        """They arrive in whatever order the gestures finished filing in."""
        self.assertEqual(
            marker(words=WORDS, available=[1, 2],
                   cues=[{"kind": "shot", "index": 2, "at": 1.15},
                         {"kind": "shot", "index": 1, "at": 0.35}]),
            "pune (screenshot: shot#01) asta sub (screenshot: shot#02) un strat")

    def test_a_cue_with_nothing_behind_it_costs_nothing(self):
        """A capture that failed leaves a number with no picture. The sentence
        goes through untouched — the relay never guesses."""
        self.assertEqual(
            marker(words=WORDS, available=[],
                   cues=[{"kind": "shot", "index": 1, "at": 0.75}]),
            "pune asta sub un strat")

    def test_a_highlight_keeps_its_own_whitespace(self):
        """The seams are tidied, the insertion is not: four lines of Java must
        arrive with their indentation."""
        self.assertEqual(
            marker(words=WORDS, selections={"1": "if (a) {\n    b();\n}"},
                   cues=[{"kind": "selection", "index": 1, "at": 0.75}]),
            'pune asta (selected text: "if (a) {\n    b();\n}") sub un strat')

    def test_a_picked_element_is_described_in_full(self):
        self.assertEqual(
            marker(words=WORDS, elements={"1": "button#save 'Save'"},
                   cues=[{"kind": "element", "index": 1, "at": 0.75}]),
            "pune asta (button#save 'Save') sub un strat")

    def test_the_corpus_copy_is_his_words(self):
        """`inline: false` is what is filed beside the audio. Nothing was put
        into that audio, so nothing is put into the transcript either."""
        self.assertEqual(
            marker(words=WORDS, available=[1], inline=False,
                   cues=[{"kind": "shot", "index": 1, "at": 0.75}]),
            "pune asta sub un strat")

    def test_the_spoken_path_still_works(self):
        """Retired, not deleted — `WT_SHOT_MARKERS=1` must remain a way back."""
        self.assertEqual(
            marker(text="pune asta screenshot one sub un strat", available=[1]),
            "pune asta (screenshot: shot#01) sub un strat")


if __name__ == "__main__":
    if BASE is None:
        print("no relay listening on %s — start Walkie Talkie first" % (PORTS,))
        sys.exit(1)
    print("relay at", BASE)
    unittest.main(verbosity=2)
