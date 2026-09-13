#!/usr/bin/env python3
"""The pure half of `helpers/wispr_loop.py`, with no relay behind it.

    python3 evals/test_wispr_loop.py

Three things in that module can be wrong **quietly**, which is the only reason
this file exists:

1. **The similarity floor.** Too low and a run passes on a transcript that is
   not the clip; too high and a working channel goes red on a comma.
2. **The log parsing.** `relay.log` timestamps have second resolution and the
   milliseconds live inside the sentences, so every interval in the table is
   arithmetic over numbers pulled out with a regex. A regex that stops matching
   reports *not measured*, which reads like a broken relay.
3. **The timing arithmetic**, including the case with no measurement in it at
   all — a chord Wispr ignored never had a recording to end, and that is
   precisely the run the harness was written to catch.

Every fixture below is copied verbatim out of `~/.walkie-talkie/relay.log`,
including the two incidents of 2026-09-13.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "helpers"))

import wispr_loop as wl  # noqa: E402


# ── real log excerpts ────────────────────────────────────────────────────────
# The happy path with a ⌘V: Wispr pasted and the tap took it (2026-09-13 14:55).
CMD_V_RUN = """\
09-13 14:55:25 [relay] ⚡ the relay asked for a dictation — opening the dictation on the gesture
09-13 14:55:25 [relay] wispr flow opened the microphone
09-13 14:55:25 [relay] ⚡ mic edge confirms the ring 412 ms after the gesture
09-13 14:55:42 [relay] wispr flow closed the microphone
09-13 14:55:42 [relay] probe: synthetic key 9 flags 0x20100000 from pid 4904 (Wispr Flow)
09-13 14:55:42 [relay] ⌘V from Wispr Flow — 294 ms after the microphone closed (taken)
09-13 14:55:42 [relay] 🗣️ wispr transcript via Wispr's ⌘V — 184 chars, 299 ms after the microphone closed
09-13 14:55:42 [relay] ⚡ ring down: pasting at the caret — 303 ms after the recording ended
"""

# The invisible insertion: no ⌘V at all, Wispr's own History row ended the
# settle (2026-09-12 22:46).
HISTORY_RUN = """\
09-12 22:45:56 [relay] wispr flow opened the microphone
09-12 22:46:03 [relay] wispr flow closed the microphone
09-12 22:46:04 [relay] wispr history: formatted 151 ms after the microphone closed (Wispr's own e2e 470 ms) — giving the ⌘V 1.0 s
09-12 22:46:05 [relay] wispr history: no ⌘V and no pasteboard after formatted — Wispr inserted it into com.apple.Terminal by a route the tap cannot see
09-12 22:46:05 [relay] 🗣️ wispr transcript via Wispr's History row — 97 chars, 1201 ms after the microphone closed
09-12 22:46:05 [relay] ⚡ ring down: Wispr Flow inserted it at the caret, with no ⌘V — 1205 ms after the recording ended
"""

# Incident 1, verbatim: the sentence was over before Wispr opened a microphone,
# so the ring burned the whole 12 s `speculativeGrace`.
INCIDENT_ONE = """\
09-13 18:18:04 [relay] ⚡ the relay asked for a dictation — opening the dictation on the gesture
09-13 18:18:04 [relay] ◯ caret halo on — the microphone is open, and these words go wherever the caret is
09-13 18:18:07 [relay] 🎙️ forward button — a dictation at the caret
09-13 18:18:16 [relay] ⚡ ring down: no microphone within 12 s of the hotkey — Wispr ignored the chord
09-13 18:18:16 [relay] dictation abandoned (the source returned nothing) — dropping what it had gathered
"""


class Words(unittest.TestCase):
    def test_punctuation_and_case_do_not_count(self):
        self.assertEqual(wl.normalise("Commit, and PUSH the fix."), "commit and push the fix")
        self.assertEqual(wl.similarity("Commit and push the fix.", "commit and push the fix"), 1.0)

    def test_wispr_reformatting_still_clears_the_floor(self):
        """The same sentence, re-punctuated and re-cased by the formatting pass."""
        said = "Let's run a bunch of experiments for you to figure out how you can detect when Wispr Flow finishes the transcription."
        again = "Lets run a bunch of experiments, for you to figure out how you can detect when Wispr flow finishes the transcription"
        self.assertGreaterEqual(wl.similarity(said, again), wl.SIMILARITY_FLOOR)

    def test_a_different_sentence_does_not(self):
        self.assertLess(wl.similarity("Commit and push the fix.",
                                      "Open the pull request and ask for a review"),
                        wl.SIMILARITY_FLOOR)

    def test_the_empty_transcript_is_not_a_match(self):
        """A sink that stayed empty must score zero, not be excused as 'both blank'."""
        self.assertEqual(wl.similarity("", "Commit and push the fix."), 0.0)

    def test_whitespace_only_differences(self):
        self.assertEqual(wl.similarity("a  b\nc", "a b c"), 1.0)


class LogParsing(unittest.TestCase):
    def test_lines_without_the_relay_prefix_are_ignored(self):
        lines = wl.parse_log("not a log line\n" + CMD_V_RUN, year=2026)
        self.assertEqual(len(lines), 8)
        self.assertTrue(lines[0].text.startswith("⚡ the relay asked"))

    def test_the_timestamp_gets_this_year(self):
        line = wl.parse_log("09-13 14:55:25 [relay] hello", year=2026)[0]
        self.assertEqual((line.at.year, line.at.month, line.at.day), (2026, 9, 13))
        self.assertEqual((line.at.hour, line.at.minute, line.at.second), (14, 55, 25))

    def test_a_line_from_the_far_future_rolls_back_a_year(self):
        """New Year's Eve: a December line read in January is last year's."""
        from datetime import datetime
        line = wl.parse_log("12-31 23:59:00 [relay] hello", year=datetime.now().year)[0]
        self.assertLessEqual((line.at - datetime.now()).days, 180)


class TimingArithmetic(unittest.TestCase):
    def test_the_cmd_v_path(self):
        t = wl.read_timings(wl.parse_log(CMD_V_RUN, year=2026))
        self.assertEqual(t.gesture_to_mic_open_ms, 412)
        self.assertEqual(t.done_ms, 294)
        self.assertEqual(t.done_source, "⌘V from Wispr Flow")
        self.assertEqual(t.delivery_ms, 299)
        self.assertEqual(t.delivery_chars, 184)
        self.assertEqual(t.ring_down_ms, 303)
        self.assertFalse(t.ring_down_estimated)
        self.assertEqual(t.done_to_ring_down_ms, 9)
        self.assertEqual(t.done_to_delivery_ms, 5)
        self.assertEqual(t.probes, ["key 9 flags 0x20100000 from Wispr Flow"])

    def test_the_history_path_wins_over_the_cmd_v_line(self):
        """`formatted` is the completion signal; a ⌘V offset is only the stand-in."""
        t = wl.read_timings(wl.parse_log(HISTORY_RUN, year=2026))
        self.assertEqual(t.done_ms, 151)
        self.assertIn("History", t.done_source)
        self.assertEqual(t.ring_down_ms, 1205)
        self.assertEqual(t.done_to_ring_down_ms, 1054)
        self.assertTrue(t.done_to_ring_down_ms <= wl.RING_DOWN_BUDGET_MS)

    def test_the_gesture_to_mic_open_falls_back_to_the_wall_clock(self):
        blob = ("09-13 10:00:00 [relay] ⚡ the relay asked for a dictation — opening the dictation on the gesture\n"
                "09-13 10:00:06 [relay] wispr flow opened the microphone\n")
        t = wl.read_timings(wl.parse_log(blob, year=2026))
        self.assertEqual(t.gesture_to_mic_open_ms, 6000)

    def test_incident_one_is_measured_and_named_not_crashed_on(self):
        """The run the harness exists for: no microphone, no 'ms after the recording ended'."""
        t = wl.read_timings(wl.parse_log(INCIDENT_ONE, year=2026))
        self.assertIsNone(t.done_ms)                       # Wispr never finished anything
        self.assertIsNone(t.done_to_ring_down_ms)          # so there is no gap to report
        self.assertTrue(t.ring_down_estimated)
        self.assertEqual(t.ring_down_ms, 12000)            # off the wall clock, against the gesture
        self.assertIn("ignored the chord", t.ring_down_reason)

    def test_the_reason_survives_the_em_dash_in_its_own_text(self):
        """Both ring-down shapes carry an em dash; the measured one must win."""
        t = wl.read_timings(wl.parse_log(CMD_V_RUN, year=2026))
        self.assertEqual(t.ring_down_reason, "pasting at the caret")
        t = wl.read_timings(wl.parse_log(INCIDENT_ONE, year=2026))
        self.assertEqual(t.ring_down_reason,
                         "no microphone within 12 s of the hotkey — Wispr ignored the chord")

    def test_nothing_at_all(self):
        t = wl.read_timings([])
        self.assertIsNone(t.done_to_ring_down_ms)
        self.assertIn("not measured", wl.timing_table(t))


class Assertions(unittest.TestCase):
    def test_a_ring_that_is_late_goes_red_with_the_gap_on_it(self):
        result = wl.Result(scenario="caret-short")
        wl._assert_ring(result, wl.read_timings(wl.parse_log(INCIDENT_ONE, year=2026)))
        self.assertFalse(result.passed)
        self.assertTrue(any("ignored the chord" in c.measured for c in result.checks))

    def test_a_ring_inside_the_budget_is_green(self):
        result = wl.Result(scenario="caret-long")
        wl._assert_ring(result, wl.read_timings(wl.parse_log(HISTORY_RUN, year=2026)))
        self.assertTrue(result.passed, [c.render() for c in result.checks])

    def test_a_result_with_no_checks_has_not_passed(self):
        """An empty run must never read as green — that is how a crash looks."""
        self.assertFalse(wl.Result(scenario="nothing").passed)


class Arrival(unittest.TestCase):
    """`StableText` — the rule the primitive's wait rests on.

    Wispr inserts some sentences in more than one event (a paste, then a
    trailing space). Reading the sink the instant the first event lands scores a
    half-written sentence as a bad transcript, which is exactly the kind of
    failure that looks like a broken channel and is not.
    """

    def test_text_must_stop_changing_before_it_counts(self):
        stable = wl.StableText(stable_ms=300)
        self.assertFalse(stable.observe("Commit and", 0.0))
        self.assertFalse(stable.observe("Commit and", 0.2))     # only 200 ms so far
        self.assertFalse(stable.observe("Commit and push", 0.3))  # changed — clock restarts
        self.assertFalse(stable.observe("Commit and push", 0.5))
        self.assertTrue(stable.observe("Commit and push", 0.61))

    def test_an_empty_sink_never_counts_as_settled(self):
        stable = wl.StableText(stable_ms=300)
        for t in (0.0, 0.5, 1.0, 5.0):
            self.assertFalse(stable.observe("", t))

    def test_the_first_observation_is_never_enough(self):
        """However long the caller waited before asking, one sample is not stability."""
        self.assertFalse(wl.StableText(stable_ms=0).observe("hello", 99.0))
        self.assertTrue(wl.StableText(stable_ms=0).observe("hello", 99.0) is False)

    def test_the_chord_s_own_keystroke_is_not_a_transcript(self):
        """Verbatim from 2026-09-13 19:26: the rig read its own chord back as `"tu"`."""
        sink = {"text": "tu", "events": [
            {"route": "keyDown", "chars": 1, "text": "t"},
            {"route": "keyDown", "chars": 1, "text": "u"}]}
        text, events = wl.sink_arrival(sink)
        self.assertEqual(text, "")
        self.assertEqual(events, [])

    def test_a_real_delivery_still_counts(self):
        sink = {"text": "x" + "Commit and push the fix.", "events": [
            {"route": "keyDown", "chars": 1, "text": "x"},
            {"route": "paste", "chars": 24, "text": "Commit and push the fix."}]}
        text, events = wl.sink_arrival(sink)
        self.assertEqual(text, "Commit and push the fix.")
        self.assertEqual(len(events), 1)

    def test_a_one_character_paste_is_wispr_not_us(self):
        """Only `keyDown` is ours. A short paste is still a delivery."""
        text, events = wl.sink_arrival({"events": [{"route": "paste", "chars": 1, "text": "A"}]})
        self.assertEqual(text, "A")

    def test_typed_delivery_of_real_length_counts(self):
        text, _ = wl.sink_arrival({"events": [{"route": "typed", "chars": 9, "text": "hello you"}]})
        self.assertEqual(text, "hello you")

    def test_wispr_s_own_dead_ends_are_named(self):
        """A dismissed dictation must end the wait, not burn the timeout."""
        for status in ("dismissed", "empty", "no_audio", "error"):
            self.assertIn(status, wl.DEAD_STATUSES)
        self.assertNotIn("formatted", wl.DEAD_STATUSES)


class Fixtures(unittest.TestCase):
    def test_every_scenario_resolves_to_a_clip_that_is_on_disk(self):
        for name in wl.SCENARIOS:
            entry = wl.fixture_for(name)
            self.assertTrue(os.path.exists(entry["wav"]), "%s: %s" % (name, entry["wav"]))
            self.assertTrue(entry.get("transcript"), "%s has no transcript" % name)

    def test_the_clips_are_the_lengths_the_scenarios_need(self):
        import wave
        short = wl.fixture_for("caret-short")
        long_ = wl.fixture_for("caret-long")
        for entry, low, high in ((short, 1.5, 3.6), (long_, 14.0, 26.0)):
            with wave.open(entry["wav"]) as handle:
                seconds = handle.getnframes() / float(handle.getframerate())
                self.assertEqual(handle.getsampwidth(), 2, "16-bit PCM only")
            self.assertTrue(low <= seconds <= high, "%s is %.1fs" % (entry["wav"], seconds))

    def test_wav_overrides_drop_a_transcript_that_is_no_longer_the_answer(self):
        """`--wav` without `--transcript` must not silently keep the old clip's words."""
        entry = wl.fixture_for("caret-short", wav=wl.fixture_for("caret-long")["wav"])
        self.assertNotIn("transcript", entry)


if __name__ == "__main__":
    unittest.main(verbosity=2)
