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

**It used to leave the chip saying `Listening…`**, and that is still not this
file's doing: `/test/dictation/start` opens a dictation the recogniser knows
nothing about, and `/test/dictation` enters *below* the recogniser, so nothing on
either route ever produces the microphone edge that takes the row down. It is
this file's business to clean up after itself, though — `_put_the_relay_down` at
the bottom cancels on the way out, because a relay left `listening` refuses every
gesture Victor makes afterwards, silently. The guard below still asks about the
**microphone** — `isRecording`, `settling`, `speculative` — and not about
`listening`, or one run of this file would lock out the next.
"""

import atexit
import json
import os
import re
import subprocess
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


def _never_arrived():
    """**Raise, unless Wispr Flow is why** — then skip.

    `startDictation` refuses outright while Wispr Flow's microphone is open
    (*one engine at a time*), so with the labelling rig running in another
    session on this Mac a class can fail to get its sentence into the outbox for
    a reason that has nothing to do with what it asserts. Measured 2026-09-20:
    the same suite went red once and green twice inside two minutes, the red run
    with the refusal in the log.
    """
    log = os.path.expanduser("~/.walkie-talkie/relay.log")
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            tail = f.read()[-20000:]
    except OSError:
        tail = ""
    if "Wispr Flow's microphone is already open" in tail:
        raise unittest.SkipTest("Wispr Flow held the microphone — one engine at a time")
    raise AssertionError("the dictation never reached the outbox")


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
        _put_the_relay_down()

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
        _never_arrived()

    # ── the highlights ──────────────────────────────────────────────────────
    def test_selections_are_one_stamped_list(self):
        """Both highlights, each a bracket saying when, what and which app.

        **Rewritten 2026-09-20.** This class asserted the *prose* envelope —
        `text selected during dictation:` over a `- 00:03 in '…'` list — which
        Victor's template replaced on 2026-09-19. It went on failing for a day
        with nobody reading it, because the sentence never reached the outbox and
        the error said so instead. Now that it does, it may as well pin the shape
        that actually ships.
        """
        line = self.line["line"]
        self.assertIn('[selected at 0:03: "the twenty-two chars!!" from app ', line)
        self.assertIn('[selected at 0:06: "a second highlight" from app ', line)
        # Every shape this replaced, in order of retirement.
        self.assertNotIn("text selected during dictation:", line)
        self.assertNotIn("[selected 0:", line)

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
    def test_picks_are_one_row_each_keyed_by_their_token(self):
        """A pick is `[chrome-selection-N at m:ss: "…" = <selector> at <url>]`."""
        line = self.line["line"]
        self.assertIn('[chrome-selection-1 at 0:01: "1.299,00 lei" = '
                      'div#cart > span.price at https://shop.example/cart]', line)
        self.assertIn("[chrome-selection-2 at 0:05:", line)
        self.assertNotIn("elements picked in Chrome during dictation", line)

    def test_pick_carries_the_element_text_and_says_what_it_cut(self):
        """The row shows the head of it; the outbox keeps what was cut."""
        self.assertIn("The server returned an error. …", self.line["line"])
        picked = self.line["elements"][1]
        self.assertEqual(picked["textChars"], 3600)
        self.assertGreater(len(picked["text"]), 1900)
        self.assertLessEqual(len(picked["text"]), 2000)

    def test_pick_offsets_reach_the_outbox_as_numbers(self):
        """`m:ss` is for reading; anything comparing two picks wants seconds."""
        self.assertEqual([e["at"] for e in self.line["elements"]], [1, 5])

    # ── one clock ───────────────────────────────────────────────────────────
    def test_every_token_in_the_envelope_uses_one_clock(self):
        """One arithmetic for every stamp — `AppDelegate.clock(_:pad:)`.

        `m:ss` since the template: the frames stopped carrying `00:05` in their
        names on 2026-09-19, so the `mm:ss` the lists used to match is gone with
        them and there is one form left rather than two.
        """
        for stamp in ("at 0:03:", "at 0:01:", "at 0:05:", "at 0:06:"):
            self.assertIn(stamp, self.line["line"])


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class FrameList(unittest.TestCase):
    """The frames clause, after the 2026-09-14 tidy.

    Four things went at once and each was its own kind of waste: `oldest first`
    said what the names already show, the `[shot N]` legend explained a
    correspondence the file names now carry themselves (`shot-1-00:08`), the
    opening frame had a bracketed sentence of its own although it is picture 0 of
    the same enumeration, and the hint did not say which recogniser had heard
    him. This pins the shape so none of them creeps back.
    """

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        cls.marker = ("uite aici. Screenshot one. si mai jos. Screenshot 2. "
                      "si elementul picked element one. gata.")
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/dictation/start")
        time.sleep(1)
        # The app posts the real ⌃⌥⌘F6 chord; this file synthesises nothing.
        for _ in range(2):
            _post(BASE, "/test/gesture", {"name": "back-click"})
            time.sleep(2)
        _post(BASE, "/pick", {
            "path": "body > table > th", "tag": "th", "text": "Header1",
            "url": "https://interact.victorrentea.ro", "title": "Interact"})
        time.sleep(1)
        _post(BASE, "/test/dictation", {"text": cls.marker})
        for _ in range(10):
            time.sleep(1)
            entry = _last_line()
            if "uite aici" in (entry.get("text") or ""):
                cls.line = entry["line"]
                return
            _post(BASE, "/bind", {"tty": NOWHERE})
        _never_arrived()

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.previous:
                _post(BASE, "/bind", {"tty": cls.previous})
            else:
                _post(BASE, "/unbind")
        except Exception:
            pass

    def test_the_reference_names_the_file(self):
        """`📸1` in the words or in the footer names `screenshot-1-…`."""
        self.assertIn("📸1", self.line)
        self.assertRegex(self.line, r"screenshot-1(-\d+)?-800px\.jpg")
        # Every shape this replaced.
        self.assertNotIn("[shot 1]", self.line)
        self.assertNotIn("(screenshot: shot#01)", self.line)
        self.assertNotRegex(self.line, r"shot-\d\d:\d\d\(")

    def test_the_opening_frame_is_a_row_of_the_same_list(self):
        """Picture zero leads the words, and here it keeps a row of its own.

        `auto` on the token since 2026-09-20 — the frame he did not press for
        says so rather than being inferred from its position.
        """
        self.assertRegex(self.line, r"^\[📸0(🖱️@\d+:\d+)? auto\] ")
        self.assertRegex(self.line, r"\[📸0 = 📁/screenshot-0(-\d+)?-800px\.jpg")
        self.assertNotIn("[and shot", self.line)
        self.assertNotIn("[the screen when I started talking", self.line)
        self.assertNotIn("open only if the words need it:", self.line)

    def test_rows_that_carry_a_clock_are_never_folded(self):
        """**The other half of `FoldedFrameRows`** (2026-09-20).

        This route has no word timings, so every frame keeps its `at 0:0N` — and
        that offset is per-frame information no template can carry. The fold must
        therefore not happen here, and each frame must keep the row that holds
        its clock.
        """
        self.assertNotIn("[📸n = ", self.line)
        self.assertRegex(self.line, r"\[📸1 at \d+:\d+ = ")
        self.assertRegex(self.line, r"\[📸2 at \d+:\d+ = ")

    def test_what_was_said_twice_is_no_longer_said_at_all(self):
        self.assertNotIn("oldest first", self.line)
        self.assertNotIn("in my words is where I pressed the shutter", self.line)

    def test_a_picked_element_is_one_row_keyed_by_its_token(self):
        """`[chrome-selection-1 … = <selector> at <url>]`, and nothing else."""
        self.assertRegex(self.line, r"\[chrome-selection-1[^]]*= body > table > th at "
                                    r"https://interact\.victorrentea\.ro\]")
        # (`picked element one` can still be in the *words*: it is the retired
        # spoken marker's phrase and /test/dictation enters below the recogniser.)
        self.assertNotIn("element picked in Chrome during dictation", self.line)
        self.assertNotIn("selected DOM element", self.line)

    def test_the_hint_is_four_words_and_names_no_recogniser(self):
        """`[Dictated in RO or EN]`, and the engine is not in it (2026-09-19).

        The **negative** half is the one worth a test. This clause rides on every
        single dictation, so anything added to it is paid for on every sentence
        this relay ever sends — and the recogniser's name has already been put
        in once (2026-09-14) and taken back out once, for cost. Victor:
        *"Altfel ma costa rau."* Asserting the wording alone would let a
        well-meaning ` by Scribe (scribe_v2)` back in without a word.
        """
        self.assertIn("[Dictated in RO or EN]", self.line)
        self.assertNotIn("transcribed", self.line)
        self.assertNotIn("hallucinate", self.line)
        # The engine of the relay under test, whichever it is, must not appear.
        engine = _get(BASE, "/engine")
        for name in (engine.get("source"), engine.get("engine")):
            if name:
                self.assertNotIn(name, self.line)


@unittest.skip("spoken markers were retired 2026-09-18 — see the docstring")
class SelectionMarkers(unittest.TestCase):
    """A highlight named by a spoken marker lands **in** the sentence (2026-09-14).

    **Skipped since 2026-09-20, and not because it is broken.** It guards the
    *spoken* marker, which `ShotMarker.isEnabled` turned off on 2026-09-18 —
    Scribe heard `Pict element one` where `resolve` looks for `Pick`, and a
    mechanism that rests on a recogniser writing an injected phrase back exactly
    fails per engine, per language and per accent. So the words come back with no
    marker in them, nothing is inlined, and all four assertions fail for the one
    reason that is not a defect: the feature is off.

    It is kept rather than deleted because the mechanism is kept rather than
    deleted (`WT_SHOT_MARKERS=1`), and a harness cannot set an environment
    variable on an installed app that is already running — so running this class
    means relaunching the relay with the flag, by hand. What ships is the
    **timestamp** marker, and `evals/test_marker_place.py` guards that, green, in
    ten cases that need no microphone.

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
        _never_arrived()

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


class AreaFrame(unittest.TestCase):
    """The wheel drag: a whole screen, and the region cut out of it unscaled.

    Since 2026-09-14 the drag sends the **display** with the rectangle in the
    file's name; since 2026-09-19 it sends the rectangle itself as well, at full
    size, because `evals/pointing-proof/` measured what the name alone costs — a
    reader with nothing highlighted names the framed sentence 21/28 from the
    800 px screen and 15/16 with the cut-out beside it.

    The gesture needs a held middle button and a moving hand, so this drives
    `POST /test/area`, which enters at `fileArea` — below the crop overlay and
    above everything that names, cuts, attaches and counts.
    """

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/dictation/start")
        time.sleep(1)
        cls.area = _post(BASE, "/test/area")
        assert cls.area.get("ok"), cls.area
        time.sleep(1)
        _post(BASE, "/test/dictation", {"text": "asta e zona pe care o arăt"})
        for _ in range(10):
            time.sleep(1)
            entry = _last_line()
            if "zona pe care o arăt" in (entry.get("text") or ""):
                cls.line = entry["line"]
                return
            _post(BASE, "/bind", {"tty": NOWHERE})
        _never_arrived()

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.previous:
                _post(BASE, "/bind", {"tty": cls.previous})
            else:
                _post(BASE, "/unbind")
        except Exception:
            pass

    @staticmethod
    def _size(path):
        """Pixels, off the file — `sips`, so this file needs no image library."""
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                             capture_output=True, text=True).stdout
        got = dict(line.strip().split(": ") for line in out.splitlines() if ": " in line)
        return int(got["pixelWidth"]), int(got["pixelHeight"])

    def test_the_area_is_a_token_with_its_corners(self):
        """`📸2✂️` and the four numbers — in the words, or in the footer's key."""
        self.assertRegex(self.line, r"📸\d+✂️")
        self.assertRegex(self.line, r"\(?\d+,\d+\)?→\(?\d+,\d+\)?")
        self.assertIn("user-selected area between corners", self.line)
        # Every shape this replaced.
        self.assertNotIn("area-928x877", self.line)
        self.assertNotIn("I am pointing at that region, not cropping to it", self.line)

    def test_the_row_offers_the_cut_out_first_and_the_screen_behind_it(self):
        row = [r for r in self.line.splitlines() if "✂️" in r][-1]
        self.assertRegex(row, r"at 📁/screenshot-\d+(-\d+)?\.jpg;")
        self.assertIn("full screen available at -800px and -original.jpg", row)

    def test_the_cut_out_matches_the_rectangle_and_is_not_scaled(self):
        zoom = self.area["zoom"]
        self.assertTrue(os.path.exists(zoom), zoom)
        box = re.search(r"\((\d+),(\d+)\)→\((\d+),(\d+)\)", self.line)
        x1, y1, x2, y2 = (int(g) for g in box.groups())
        self.assertEqual(self._size(zoom), (x2 - x1, y2 - y1))
        self.assertLessEqual(self._size(self.area["handed"])[0], 800)
        self.assertGreater(self._size(zoom)[0], 800)

    def test_the_folder_is_said_once_and_the_old_clause_is_gone(self):
        # `📁=` and not `=` (2026-09-20, Victor: the line that *defines* the
        # symbol every row below uses must carry it), and the path now ends in
        # this dictation's own folder inside the session's.
        self.assertRegex(self.line, r"\[📁=\$WALKIE_SHOTS/[\d-]+/[\d-]+\]")
        self.assertNotRegex(self.line, r"\[=\$WALKIE_SHOTS")
        self.assertNotIn("open only if the words need it", self.line)
        self.assertNotIn("≤800px wide", self.line)

    def test_one_drag_is_one_picture(self):
        """The chip counts frames; the 800px copy and the cut-out are siblings."""
        entry = _last_line()
        frames = [p for p in entry.get("paths", []) if p.endswith("-original.jpg")]
        self.assertEqual(len(frames), 1, entry.get("paths"))
        self.assertFalse(any("800px" in p for p in entry.get("paths", [])))


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class MovedArea(unittest.TestCase):
    """**The ⇧-drag: this box, moved to that one** (2026-09-24).

    Victor: *"the old shape will remain there, locked … and then an arrow
    should lay from the center of it to wherever the new shape … is."* One
    clean frame, the first box cut out, and both boxes in the token and the
    row — `POST /test/area` with a `to` box, below the overlay as `AreaFrame`.
    """

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        _post(BASE, "/bind", {"tty": NOWHERE})
        # A wall clock and word timings, so the token lands in the words (the
        # footer's key alone would not carry the corners).
        _post(BASE, "/test/dictation/start", {"clock": True})
        time.sleep(1)
        cls.area = _post(BASE, "/test/area", {"x": 200, "y": 300, "w": 300, "h": 150,
                                              "to": {"x": 700, "y": 400, "w": 200, "h": 100}})
        assert cls.area.get("ok"), cls.area
        time.sleep(1)
        words = [("mută", 0.1, 0.4), (" ", 0.4, 0.5), ("asta", 0.5, 0.8), (" ", 0.8, 1.6),
                 ("acolo", 1.6, 2.0)]
        _post(BASE, "/test/dictation", {"text": "mută asta acolo", "words": [
            {"text": t, "start": a, "end": b, "type": "spacing" if t == " " else "word"}
            for t, a, b in words]})
        for _ in range(10):
            time.sleep(1)
            entry = _last_line()
            if "acolo" in (entry.get("text") or "") and "mută" in (entry.get("text") or ""):
                cls.line = entry["line"]
                return
            _post(BASE, "/bind", {"tty": NOWHERE})
        _never_arrived()

    @classmethod
    def tearDownClass(cls):
        AreaFrame.tearDownClass.__func__(cls)

    def test_the_token_carries_both_boxes(self):
        self.assertRegex(self.line, r"📸\d+✂️\d+,\d+→\d+,\d+ moved to \d+,\d+→\d+,\d+\]")

    def test_the_row_says_which_way(self):
        row = [r for r in self.line.splitlines() if "MOVE" in r][-1]
        self.assertIn("should move to the box", row)
        self.assertRegex(row, r"the first box cut out at 📁/screenshot-\d+(-\d+)?\.jpg;")

    def test_the_cut_out_is_the_first_box(self):
        row = [r for r in self.line.splitlines() if "MOVE" in r][-1]
        x1, y1, x2, y2 = (int(g) for g in re.search(r"\((\d+),(\d+)\)→\((\d+),(\d+)\)", row).groups())
        self.assertEqual(AreaFrame._size(self.area["zoom"]), (x2 - x1, y2 - y1))
        # The source sits left of the destination on screen, so its x is smaller.
        to = re.search(r"should move to the box \((\d+),", row)
        self.assertLess(x1, int(to.group(1)))


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class FoldedFrameRows(unittest.TestCase):
    """**Three plain frames, one legend row** (2026-09-20).

    Victor, reading a footer whose rows differed by a single digit: *"Chiar e
    nevoie de astea? Nu inferă agentul singur că în loc de `1` trebuie să pună
    `2`?"* Measured in `evals/envelope-symbols/` over 36 runs and yes — so
    `artifactsClause` writes one `[📸n = 📁/screenshot-n-800px.jpg …]` where it
    used to write one row per frame.

    The rule has four conditions and this pins the two that can actually regress:
    it folds when the frames have nothing to tell apart, and it does **not** fold
    when a row carries a clock. That second half is `FrameList` below — the
    `/test/dictation` route has no word timings, so every row keeps its `at 0:0N`
    and the per-frame rows must survive.

    Word timings are what put the tokens in the sentence, so they are supplied
    here: `clock: true` gives the presses a ruler, and the `words` handed to
    `/test/dictation` are what `ShotMarker.place` measures them against.
    """

    @classmethod
    def setUpClass(cls):
        state = _get(BASE, "/test/state")
        if any(state.get(k) for k in ("isRecording", "settling", "speculative")):
            raise unittest.SkipTest("a real dictation is in flight — not touching it")
        target = _get(BASE, "/target")
        cls.previous = target.get("address") if target.get("bound") else None
        said = ("uite", "aici", "si", "mai", "jos", "si", "inca", "una", "gata")
        words, t = [], 0.4
        for w in said:
            words.append({"text": w, "start": t, "end": t + 0.35, "type": "word"})
            words.append({"text": " ", "start": t + 0.35, "end": t + 0.7,
                          "type": "spacing"})
            t += 0.7
        cls.text = " ".join(said)
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/dictation/start", {"clock": True})
        # Three shutter presses, spaced so each lands in a different gap.
        for _ in range(3):
            time.sleep(1.4)
            _post(BASE, "/test/gesture", {"name": "back-click"})
        time.sleep(1)
        _post(BASE, "/test/dictation", {"text": cls.text, "words": words})
        for _ in range(12):
            time.sleep(1)
            entry = _last_line()
            # The tokens are *in* the words by now, so the text does not start
            # with the plain sentence — match on a word only this run says.
            if "inca una gata" in (entry.get("text") or ""):
                cls.line = entry["line"]
                return
            _post(BASE, "/bind", {"tty": NOWHERE})
        _never_arrived()

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.previous:
                _post(BASE, "/bind", {"tty": cls.previous})
            else:
                _post(BASE, "/unbind")
        except Exception:
            pass
        _put_the_relay_down()

    def test_the_plain_frames_share_one_templated_row(self):
        rows = [r for r in self.line.splitlines() if r.startswith("[📸")]
        self.assertEqual(
            ["[📸n = " in r for r in rows].count(True), 1,
            "expected exactly one templated row:\n" + "\n".join(rows))
        for n in (0, 1, 2, 3):
            self.assertNotIn("[📸%d = " % n, self.line,
                             "frame %d kept a row of its own:\n%s" % (n, self.line))

    def test_the_templated_row_still_says_both_widths(self):
        row = [r for r in self.line.splitlines() if r.startswith("[📸n = ")][0]
        self.assertIn("📁/screenshot-n-800px.jpg", row)
        self.assertIn("at 800px width", row)
        self.assertIn("-original.jpg", row)
        # The resolution is the one fact a reader cannot derive from a number.
        self.assertRegex(row, r"-original\.jpg at \d+x\d+px\]$")

    def test_the_numbers_are_still_in_the_words(self):
        """Folding the rows may not cost the tokens — that is where `n` comes from.

        Four frames, not three: `/test/dictation/start` takes the context frame
        as 📸0 exactly as a real gesture does, so the three shutter presses are
        📸1, 📸2 and 📸3.
        """
        for n in (0, 1, 2, 3):
            self.assertIn("[📸%d" % n, self.line)

    def test_the_automatic_frame_says_so(self):
        """`auto` on 📸0 — five characters for the one thing readers guessed at."""
        self.assertRegex(self.line, r"^\[📸0🖱️@\d+:\d+ auto\]")
        # And only there: a frame he pressed for must not claim to be automatic.
        self.assertEqual(self.line.count(" auto]"), 1)


@unittest.skipIf(BASE is None, "no relay is listening on 8917-8919")
class MicrophoneAfterACancel(unittest.TestCase):
    """**A cancelled dictation must not swallow the next one** (2026-09-20).

    `MicRecorder.start(to:)` opened with `guard !isRecording else { return nil }`
    and nil, there, means *the microphone is open*. So any session still open
    when the next gesture landed — a `cancel()` whose recogniser had nothing to
    cancel, or a `stop()` still tearing the device down on its own queue three
    seconds later — was answered as a success: the source logged `recording
    started`, the halo went up, the file it named was never opened, and the
    upload of an empty WAV timed out 33 s later with the transcript lost. Nothing
    in `relay.log` said why; the failure was the silent `nil` itself.

    What is asserted here is the one observable that separates the two worlds:
    `mic: recording through …`, the line `start(to:)` only reaches when it has
    actually opened the device. Once per dictation, so a second dictation that
    does not log it recorded nothing — which is precisely the bug.

    **That this assertion discriminates was not argued, it was observed.** The
    pre-fix build produced exactly this sequence in `relay.log` — a cancel at
    10:40:23, then:

        10:40:26 🎙️ recording started for ElevenLabs — mic-1789890026.wav
        10:41:16 🎙️ recording started for ElevenLabs — mic-1789890076.wav

    with **no `mic: recording through …` between or after either**, and both
    sentences lost 33 s later to `timed out waiting for the text`. The mutation
    for this test is in the log of the morning it was written.

    It never speaks: the first dictation is opened for its side effect and thrown
    away, and the second is closed the same way. That makes it safe to run beside
    anything else on this Mac, unlike `evals/envelope-live/`, which needs the
    microphone to itself.
    """

    LOG = os.path.expanduser("~/.walkie-talkie/relay.log")

    def _log_lines(self, since):
        with open(self.LOG, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()[since:]

    def _log_length(self):
        with open(self.LOG, encoding="utf-8", errors="replace") as f:
            return len(f.read().splitlines())

    def _skip_if_wispr_took_it(self, since):
        """**One engine at a time is a refusal, not a failure of this test.**

        `startDictation` refuses outright while Wispr Flow's microphone is open,
        and on this Mac that happens whenever the labelling rig in another
        session is between clips — so the dictation never opens the device for a
        reason that has nothing to do with what is being asserted. Measured: the
        test went red once and green twice in the same minute, with the refusal
        in the log each red time. Skipping keeps the signal honest.
        """
        refused = [l for l in self._log_lines(since)
                   if "Wispr Flow's microphone is already open" in l]
        if refused:
            self.skipTest("Wispr Flow held the microphone — one engine at a time")

    def _idle(self, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            s = _get(BASE, "/test/state")
            if not (s["listening"] or s["settling"] or s["isRecording"]):
                return True
            time.sleep(0.5)
        return False

    def setUp(self):
        s = _get(BASE, "/test/state")
        if s["isRecording"] or s["settling"] or s["speculative"]:
            self.skipTest("Victor is talking — not taking the microphone from him")
        # **A `listening` left by the classes above is cleared here, not waited
        # out.** They open dictations through `/test/dictation/start`, which the
        # recogniser never hears about, so nothing downstream ever takes the flag
        # back down — and this class is precisely the one that cannot start a
        # dictation while it is up. The guard above is what keeps that safe: a
        # microphone that is genuinely recording, settling or speculating belongs
        # to Victor and this file skips rather than touching it.
        if not self._idle(timeout=2):
            _post(BASE, "/test/cancel")
        self.assertTrue(self._idle(), "the relay would not go idle before the test")

    def tearDown(self):
        _post(BASE, "/test/cancel")
        self._idle()

    def test_the_dictation_after_a_cancel_still_opens_the_device(self):
        mark = self._log_length()
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/gesture", {"name": "forward-right"})
        time.sleep(2)
        self._skip_if_wispr_took_it(mark)
        opened = [l for l in self._log_lines(mark) if "mic: recording through" in l]
        self.assertEqual(len(opened), 1,
                         "the first dictation did not open the microphone:\n"
                         + "\n".join(self._log_lines(mark)))

        # **The cancel, and the next gesture on its heels with nothing in
        # between** — the shape that used to be answered with a silent nil.
        # `cancel()` tears the device down on `audioQueue`, so the gap here is
        # the whole experiment: sleep a second and the teardown wins the race and
        # the old code passes too. The assertion is the *outcome* either way — a
        # dictation that opened the device — because that is what has to hold
        # whichever side of the race wins, and a test written against the
        # pre-emption log line would go quiet the day the race stops happening.
        mark = self._log_length()
        _post(BASE, "/test/cancel")
        _post(BASE, "/bind", {"tty": NOWHERE})
        _post(BASE, "/test/gesture", {"name": "forward-right"})
        time.sleep(2)
        self._skip_if_wispr_took_it(mark)
        after = self._log_lines(mark)
        opened = [l for l in after if "mic: recording through" in l]
        self.assertEqual(len(opened), 1,
                         "the dictation after a cancel recorded into a file the "
                         "device was never attached to:\n" + "\n".join(after))


def _put_the_relay_down():
    """**Close the dictation this file opened**, whatever happened above.

    The docstring at the top used to say the chip is left reading `Listening…`
    and that `./relay-restart.sh` clears it. That was true and it was not
    harmless: `listening` is the first thing `startDictation` guards on, and it
    returns **silently** when it is set — so a relay left in that state refuses
    every 🔼→ Victor makes, posts the chord, logs nothing, and looks broken with
    no way to tell why. Measured on 2026-09-20: a run of this file at 10:18 left
    it set, and the gesture was dead until 10:39 when a cancel was sent by hand.

    A harness is allowed to leave a mess in its own files. It is not allowed to
    leave the app unusable for the person whose Mac it is running on.
    """
    if BASE is None:
        return
    state = _get(BASE, "/test/state") or {}
    if state.get("listening") or state.get("settling") or state.get("isRecording"):
        _post(BASE, "/test/cancel")


if __name__ == "__main__":
    if BASE is None:
        print("no relay on %s — start Walkie Talkie first" % (PORTS,), file=sys.stderr)
    atexit.register(_put_the_relay_down)
    unittest.main(verbosity=2)
