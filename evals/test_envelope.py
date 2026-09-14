#!/usr/bin/env python3
"""The envelope's three lists, asserted against a running relay.

    python3 evals/test_envelope.py

`variants.py` next door measures what the *shots* clause costs in tokens against
real frames. This one is about **shape**: that the three things the envelope
enumerates — the frames, the highlights, the picked elements — all say when in
the dictation they happened, in the same clock, in the same `- ` list style, and
that a picked element carries what it said.

It runs against the **installed relay**, through the loopback routes, because
the clauses are private statics inside an AppKit app with no test target and the
half that has gone wrong historically is not the formatting but the plumbing:
whether the offset survives being read on one queue and rendered on another,
whether a highlight filed at the close of a dictation still has a zero to measure
against. A pure-Python re-implementation of `AppDelegate.selectionsClause` would
assert that this file agrees with itself.

**It refuses to run while Victor is talking**, and it puts his binding back. The
sentence it delivers goes to a tty nothing is listening on: the outbox line is
written at delivery and delivery to a tty with no tab comes back `targetGone`
without a keystroke reaching any window — which is the only way to get a real
envelope out of a relay that must not type into anything.

**It leaves the chip saying `Listening…`**, and that is not this file's doing:
`/test/dictation/start` opens a dictation the recogniser knows nothing about, and
`/test/dictation` enters *below* the recogniser, so nothing on either route ever
produces the microphone edge that takes the row down. `./relay-restart.sh` clears
it. The guard below therefore asks about the **microphone** — `isRecording`,
`settling`, `speculative` — and not about `listening`, or one run of this file
would lock out the next.
"""

import json
import os
import sys
import time
import unittest
import urllib.error
import urllib.request

PORTS = (8917, 8918, 8919)
OUTBOX = os.path.expanduser("~/.walkie-talkie/outbox.jsonl")
# A tty nothing is listening on. `deliver` re-resolves the target and finds no
# Terminal.app tab, so the words go nowhere and the relay unbinds itself.
NOWHERE = "ttys999"


def _post(base, path, obj=None, timeout=5):
    data = json.dumps(obj).encode() if obj is not None else b""
    req = urllib.request.Request(base + path, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _get(base, path, timeout=5):
    with urllib.request.urlopen(base + path, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _find_relay():
    for port in PORTS:
        try:
            base = "http://localhost:%d" % port
            if _get(base, "/up", timeout=2).get("ok"):
                return base
        except Exception:
            continue
    return None


def _last_line():
    with open(OUTBOX, encoding="utf-8") as f:
        return json.loads(f.read().strip().split("\n")[-1])


BASE = _find_relay()


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class EnvelopeShape(unittest.TestCase):
    """One fabricated dictation carrying two highlights and two picks."""

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        # Whatever he was bound to goes back at the end. A test that leaves the
        # relay pointed somewhere else is a test that eats the next sentence.
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        cls.marker = "envelope shape check %d" % int(time.time())
        cls.line = cls._run()

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.previous:
                _post(BASE, "/bind", {"tty": cls.previous})
            else:
                _post(BASE, "/unbind")
        except Exception:
            pass
        print("\n  (the chip is left saying Listening… — ./relay-restart.sh clears it)")

    @classmethod
    def _run(cls):
        _post(BASE, "/test/dictation/start")
        time.sleep(1)
        _post(BASE, "/pick", {
            "path": "div#cart > span.price", "tag": "span", "text": "1.299,00 lei",
            "url": "https://shop.example/cart", "title": "Cart — Shop"})
        time.sleep(2)
        _post(BASE, "/test/selection", {"text": "the twenty-two chars!!"})
        time.sleep(2)
        long = "The server returned an error. " * 120
        _post(BASE, "/pick", {
            "path": "div.alert > p.message", "tag": "p",
            "text": long[:2000], "textChars": len(long),
            "url": "https://shop.example/cart", "title": "Cart — Shop",
            "move": {"from": {"x": 120, "y": 340}, "to": {"x": 500, "y": 205}}})
        time.sleep(1)
        _post(BASE, "/test/selection", {"text": "a second highlight"})
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/dictation", {"text": cls.marker})

        # **Bind again until the line appears.** With nothing bound the sentence
        # is *held* rather than dropped (`holdsForBind`) and no outbox line is
        # written — and the bogus tty unbinds itself the moment delivery finds no
        # tab behind it, so a sentence that arrived a beat late is waiting for a
        # bind that is already gone. Each re-bind releases whatever is waiting.
        for _ in range(10):
            time.sleep(1)
            entry = _last_line()
            if entry.get("text") == cls.marker:
                return entry
            _post(BASE, "/bind", {"tty": NOWHERE})
        raise AssertionError("the dictation never reached the outbox")

    # ── the highlights ──────────────────────────────────────────────────────
    def test_selections_are_one_stamped_list(self):
        """Both highlights, in one `- ` list, each saying when and where."""
        self.assertIn("text selected during dictation:", self.line["line"])
        self.assertIn('- 00:03 in ', self.line["line"])
        self.assertIn('"the twenty-two chars!!"', self.line["line"])
        self.assertIn('"a second highlight"', self.line["line"])
        # The pre-2026-09-13 shapes are gone, both of them.
        self.assertNotIn("[selected:", self.line["line"])
        self.assertNotIn("[selected 0:", self.line["line"])

    def test_frozen_selection_keeps_its_key_and_gains_its_offset(self):
        """`selection` still carries the first one; the offset rides beside it."""
        self.assertEqual(self.line["selection"], "the twenty-two chars!!")
        self.assertEqual(self.line["selectionAt"], 3)
        self.assertTrue(self.line["selectionIn"])

    def test_extra_selection_carries_both_clocks(self):
        extra = self.line["selections"][0]
        self.assertEqual(extra["text"], "a second highlight")
        self.assertEqual(extra["at"], "0:06")        # unchanged, `m:ss`
        self.assertEqual(extra["seconds"], 6)        # added 2026-09-13

    # ── the picks ───────────────────────────────────────────────────────────
    def test_picks_are_a_list_with_the_page_factored_out(self):
        line = self.line["line"]
        self.assertIn("elements picked in Chrome during dictation, "
                      "on 'https://shop.example/cart' (Cart — Shop), oldest first:", line)
        self.assertIn('- 00:01 div#cart > span.price: "1.299,00 lei"', line)
        self.assertIn("moved from 120,340 to 500,205 (top-left, page coordinates)", line)

    def test_pick_carries_the_element_text_and_says_what_it_cut(self):
        line = self.line["line"]
        self.assertIn("… (truncated, 3600 chars)", line)
        picked = self.line["elements"][1]
        self.assertEqual(picked["textChars"], 3600)
        self.assertGreater(len(picked["text"]), 1900)
        self.assertLessEqual(len(picked["text"]), 2000)

    def test_pick_offsets_reach_the_outbox_as_numbers(self):
        """`m:ss` is for reading; anything comparing two picks wants seconds."""
        self.assertEqual([e["at"] for e in self.line["elements"]], [1, 5])

    # ── one clock ───────────────────────────────────────────────────────────
    def test_every_list_in_the_envelope_uses_mm_ss(self):
        """The frames are named `shot-00:05`; the other two lists match them."""
        for stamp in ("- 00:03 ", "- 00:01 ", "- 00:05 "):
            self.assertIn(stamp, self.line["line"])


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class SelectionMarkers(unittest.TestCase):
    """A highlight named by a spoken marker lands **in** the sentence (2026-09-14).

    The other one is the control: it was filed the same way, its marker was never
    said back by the "recogniser", and it therefore keeps the line under the
    words that every highlight had before today. Victor's fallback is that
    absence, so the test is as much about the second highlight as the first.

    `/test/dictation` enters below the recogniser, which is exactly what makes
    this assertable: the fabricated transcript is what Wispr *would* have
    returned with the marker in it, and nothing else in the path is faked.
    """

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        cls.first = "the subject he was talking about %d" % int(time.time())
        cls.second = "the paragraph he pointed at later"
        cls.line = cls._run()

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.previous:
                _post(BASE, "/bind", {"tty": cls.previous})
            else:
                _post(BASE, "/unbind")
        except Exception:
            pass

    @classmethod
    def _run(cls):
        _post(BASE, "/test/dictation/start")
        time.sleep(1)
        # Marker one: the frozen slot is empty at the start of a fabricated
        # dictation, so this is the `fillsTheBlank` case — a subject arriving
        # mid-sentence, and it is marked like any other.
        _post(BASE, "/test/selection", {"text": cls.first})
        time.sleep(2)
        _post(BASE, "/test/selection", {"text": cls.second})   # marker two
        time.sleep(1)
        # What Wispr would hand back: his sentence with the second marker in it,
        # promoted to its own paragraph the way the formatter does.
        cls.marker = "uite ce zici de asta\n\nSelected text two.\n\nmerge?"
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/dictation", {"text": cls.marker})
        for _ in range(10):
            time.sleep(1)
            entry = _last_line()
            if entry.get("selection") == cls.first:
                return entry
            _post(BASE, "/bind", {"tty": NOWHERE})
        raise AssertionError("the dictation never reached the outbox")

    def test_the_marked_highlight_is_quoted_inside_the_sentence(self):
        words = self.line["line"].split("\n\n")[0]
        self.assertIn('"%s"' % self.second, words)
        # …and the marker itself is gone, in every form it could have survived in.
        self.assertNotIn("Selected text", words)
        self.assertNotIn("[selection", words)

    def test_the_marked_highlight_is_not_repeated_under_the_words(self):
        """Inline *or* listed, never both — that is what makes it readable."""
        listed = self.line["line"].split("text selected during dictation:")[-1]
        self.assertNotIn(self.second, listed)

    def test_the_unmarked_highlight_keeps_its_line(self):
        """The fallback, and it is chosen by the marker's absence."""
        self.assertIn("text selected during dictation:", self.line["line"])
        listed = self.line["line"].split("text selected during dictation:")[-1]
        self.assertIn('"%s"' % self.first, listed)

    def test_the_outbox_says_which_marker_and_whether_it_landed(self):
        extra = self.line["selections"][0]
        self.assertEqual(extra["text"], self.second)
        self.assertEqual(extra["marker"], 2)
        self.assertTrue(extra["inlined"])
        # The whole text is still in the outbox even when it was inlined clamped.
        self.assertEqual(self.line["selection"], self.first)


if __name__ == "__main__":
    if BASE is None:
        print("no relay on %s — start Walkie Talkie first" % (PORTS,), file=sys.stderr)
    unittest.main(verbosity=2)
