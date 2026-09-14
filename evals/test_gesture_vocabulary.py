#!/usr/bin/env python3
"""**The vocabulary Victor dictated, asserted one sentence at a time.**

On 2026-09-14 he described the forward button in a single breath:

    "la apăsarea forward simplă începe dictarea, dar apoi dictarea aceea se
     poate duce în diverse locuri, în funcție de cum se termină gestul"

Every test below is one clause of that, and each carries his own words in its
docstring — in Romanian, because a translation of a spec is a second spec. The
strings the app *renders* are English and stay English; these are notes to the
next reader about what was actually asked for.

## Why this file exists at all

Before `docs/gestures.puml`, *what does 🔼 → do while unbound* was the emergent
behaviour of about twenty booleans spread across `AppDelegate`, `HotkeyTap` and
`WisprFlowSource` — `listening`, `speculative`, `settling`, `pasteMode`,
`latchedAtCaret`, `spawnPending`, `awaitingBind` — and the answer lived in a
four-clause boolean expression nobody had read since the day it was written.
Every rule in `.claude/rules/dictation-source.md` that cost a night is a missing
guard on one of those implicit states.

Writing it as a diagram makes the vocabulary *readable*. It does not make it
*asserted*. This file is the second half: the diagram says `🔼 forward-right`
with nothing bound is an internal transition, and this file is what notices the
day somebody, reasonably and in good faith, straightens that into an ordinary
arrow.

## The one that is load-bearing

    "dictarea nu se termină, ci așteaptă să se înțeleagă unde se trimite.
     De aia apare warning. Nu la început."

🔼 → with nothing bound **does not end the sentence**. It refuses, it warns, and
the microphone stays open until he says where the words go. Four separate claims
ride on that being an *internal* transition, and all four are asserted, because
three of them would survive the fourth breaking:

1. it stays inside `Listening` — the state, so the chip and the borrowed
   gestures are still the dictation's;
2. the transition is marked internal — so `Listening`'s `exit` never runs;
3. exactly one warning, and it is the *only* thing that happened;
4. **neither `resumeMusic` nor `stopDictation` fires** — which is what an
   ordinary self-transition would have done, silently. `A --> A` is a parse
   error in this grammar for precisely this reason, so the mistake has to be
   made as a real arrow to `Settling`, and that is the shape the `--self-test`
   fixture takes.

## And the one that is a scar

    Settling : 🔼 forward-click / sayInFlight

A click while the words are in flight is a **stop or nothing, never a new
dictation**. On 2026-09-13 a second 🔼 click landed inside the settle, where
`onPasteToggle` asked only about `listening`, and started a phantom dictation
whose `gestureSeen` disarmed the first sentence's swallow window — the sentence
was lost, invisibly, from outside the process. In this diagram that failure is
not guarded against; it is **unwriteable**, because `Settling` has no arrow out
on any forward gesture except `forward-left`. The test below asserts the absence,
which is the only way an absence stays true.

It all runs through `--simulate-gestures`, which exits before AppKit and before
`SingleInstance` — so this can run with the installed relay bound to a terminal
and Victor mid-sentence, and disturbs neither.

    evals/test_gesture_vocabulary.py              # every sentence
    evals/test_gesture_vocabulary.py --list       # …and print the scenarios
    evals/test_gesture_vocabulary.py --self-test  # prove the refusal check fails
                                                  # when the refusal is removed

Exit 0 when clean, 1 when a sentence is wrong, 2 when the harness itself broke —
no binary, or a diagram that yields no transitions and no substates, which means
this file has stopped reading the machine rather than the machine being right.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUML = ROOT / "docs" / "gestures.puml"
BINARY = ROOT / ".build" / "debug" / "WalkieTalkie"


def simulate(steps, world=None, puml=None, home=None, start=None):
    """Drive the headless machine. Returns its answer, or raises with the error."""
    script: dict = {"steps": steps}
    if world is not None:
        script["world"] = world
    if start is not None:
        script["from"] = start
    env = dict(os.environ)
    if puml is not None:
        env["WT_GESTURES_PUML"] = str(puml)
    args = [str(BINARY)]
    if home is not None:
        # Before `--simulate-gestures`, which exits inside the flag loop. It
        # keeps a fixture out of `gestures.last-good.puml`, which the installed
        # app falls back to when the real diagram will not parse.
        args += ["--home", home]
    args.append("--simulate-gestures")
    run = subprocess.run(args, input=json.dumps(script), capture_output=True,
                         text=True, env=env, cwd=str(ROOT))
    try:
        answer = json.loads(run.stdout)
    except json.JSONDecodeError:
        raise AssertionError(f"the simulator printed nothing parseable "
                             f"(exit {run.returncode}): {run.stderr.strip()[:400]}")
    if not answer.get("ok"):
        raise AssertionError(f"the machine refused the diagram: {answer.get('error')}")
    return answer


def substates_of(text: str, parent: str) -> set[str]:
    """The states declared inside `state <parent> … { … }`.

    Read from the diagram rather than listed here: the three destinations are
    what the composite means, and a fourth one added tomorrow should be covered
    by *staying inside Listening* without this file being edited.
    """
    out: set[str] = set()
    depth = 0
    inside = False
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("'"):
            continue
        if not inside:
            if s.startswith(f"state {parent}") and s.endswith("{"):
                inside, depth = True, 1
            continue
        if s.endswith("{"):
            depth += 1
        if s.startswith("state "):
            name = s[len("state "):].strip().rstrip("{").strip()
            if "<<" in name:
                name = name[:name.index("<<")].strip()
            if name:
                out.add(name.split()[0])
        if s.startswith("}"):
            depth -= 1
            if depth == 0:
                break
    return out


LISTENING = "Listening"
IN_LISTENING = substates_of(PUML.read_text(), LISTENING)

#: The two actions that must NOT run when 🔼 → refuses. `resumeMusic` is
#: `Listening`'s `exit` — the genuine edge `MusicBridge` is told about — and
#: `stopDictation` closes the microphone. Either one firing means the sentence
#: ended, which is the whole thing Victor said it must not do.
MUST_NOT_RUN_ON_A_REFUSAL = ("resumeMusic", "stopDictation")


def refusal_findings(answer: dict, substates: set[str]) -> list[str]:
    """**The load-bearing assertion, as data**, so `--self-test` can reuse it.

    Returns one complaint per broken claim. Empty means 🔼 → with nothing bound
    behaved the way he described it.
    """
    bad: list[str] = []
    refusal = answer["transitions"][-1] if answer["transitions"] else None
    if refusal is None or refusal["trigger"] != "forward-right":
        return ["the 🔼 → gesture reached no transition at all — it was refused "
                "outright rather than answered with a warning"]
    if answer["final"] not in substates:
        bad.append(f"it left Listening: the machine is in `{answer['final']}`, "
                   f"which is not one of {sorted(substates)}")
    if not refusal["internal"]:
        bad.append(f"the transition is not internal — it is "
                   f"`{refusal['from']} --> {refusal['to']}`, so Listening's exit ran")
    if len(answer["warnings"]) != 1:
        bad.append(f"{len(answer['warnings'])} warning(s), expected exactly one: "
                   f"{answer['warnings']}")
    for action in MUST_NOT_RUN_ON_A_REFUSAL:
        if action in refusal["actions"] or action in answer["actions"]:
            bad.append(f"`{action}` ran — the sentence ended, and it must not")
    return bad


class TheForwardButtonOpensASentence(unittest.TestCase):
    """The first clause: what a bare forward press does at rest."""

    def test_a_plain_forward_click_starts_a_dictation(self):
        """*"la apăsarea forward simplă începe dictarea"*

        And it enters `Listening` through a destination substate, never the
        composite itself — the parser refuses an arrow at a composite, because
        picking a substate silently is how a diagram starts lying.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0}])
        self.assertIn("openDictation", answer["actions"])
        self.assertIn(answer["final"], IN_LISTENING,
                      f"a forward click left the machine in `{answer['final']}`")
        self.assertIn("pauseMusic", answer["actions"],
                      "entering Listening must tell MusicBridge once")


class TheSentenceCanBeAimedMidFlight(unittest.TestCase):
    """The second clause: where it is pointed can change while he is talking."""

    def test_forward_bind_binds_the_terminal_under_the_mouse(self):
        """*"dacă pe drum fac gestul de forward în jos, asta leagă dictarea de
        terminalul de sub mouse."*

        🔼 ↓ is the left button held 0.3 s and then the forward click. `HotkeyTap`
        judges the chord against the window server and fires `forward-bind`; the
        diagram only decides what that word means, which is why the physics is
        not a guard.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-bind", "atMs": 2000}])
        self.assertIn("bindFrontmost", answer["actions"])
        self.assertEqual(answer["final"], "ToBound")
        self.assertNotIn("stopDictation", answer["actions"],
                         "binding mid-sentence must not end it")


class TheGestureThatEndsItNamesWhereItGoes(unittest.TestCase):
    """*"dictarea aceea se poate duce în diverse locuri, în funcție de cum se
    termină gestul."*"""

    def test_a_plain_click_pours_the_words_at_the_caret(self):
        """*"dacă fac un click simplu pe forward, îmi varsă textul la caret"*

        🔼 click says *caret* outright whatever is bound — the vocabulary Victor
        fixed on 2026-09-12 — so the aim is asserted with a terminal bound, which
        is the case that could silently go the other way.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-click", "atMs": 3000}],
                          world={"bound": True})
        ending = answer["transitions"][-1]
        self.assertEqual(ending["trigger"], "forward-click")
        self.assertEqual(ending["to"], "Settling")
        for action in ("stopDictation", "aimAtCaret"):
            self.assertIn(action, ending["actions"] + answer["actions"],
                          f"ending with a plain click must run `{action}`")
        self.assertNotIn("aimAtBound", ending["actions"],
                         "a plain click is the caret even with a terminal bound")

    def test_forward_up_opens_the_folder_menu(self):
        """*"forward cu up deschide meniul de foldere"*

        `aimAtSpawn` arms the spawn **and** offers the menu, both — a spawn with
        no folder picked is a spawn into `~/workspace`, and the menu is how he
        says otherwise.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-up", "atMs": 3000}])
        ending = answer["transitions"][-1]
        self.assertEqual(ending["trigger"], "forward-up")
        self.assertIn("aimAtSpawn", ending["actions"])
        self.assertEqual(ending["to"], "Settling")

    def test_forward_right_with_a_terminal_bound_ends_the_sentence(self):
        """The mirror of the refusal: with somewhere to send it, 🔼 → delivers.

        Asserted beside the refusal on purpose. A check that only ever watched
        the unbound case would pass just as happily on a 🔼 → that did nothing at
        all, which is the opposite failure and every bit as bad.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-right", "atMs": 4000}],
                          world={"bound": True})
        ending = answer["transitions"][-1]
        self.assertFalse(ending["internal"],
                         "with a terminal bound, 🔼 → must leave Listening")
        self.assertEqual(ending["to"], "Settling")
        self.assertEqual(answer["warnings"], [],
                         "there is somewhere to send it — nothing to warn about")
        for action in ("resumeMusic", "stopDictation", "aimAtBound"):
            self.assertIn(action, answer["actions"],
                          f"ending at the bound terminal must run `{action}`")

    def test_forward_left_cancels_from_every_destination(self):
        """🔼 ← cancels *either* — written on the composite, so it means all three.

        Run from each substate rather than from one, because the point of
        declaring it on `Listening` is that it does not have to be repeated; a
        destination that grew its own `forward-left` would shadow this and only
        a per-destination run would notice.
        """
        entries = {
            "AtCaret": [{"fire": "forward-click"}],
            "ToBound": [{"fire": "forward-click"}, {"fire": "forward-bind"}],
            "ToSpawn": [{"fire": "forward-up"}],
        }
        for where, steps in entries.items():
            with self.subTest(destination=where):
                opened = simulate(steps)
                self.assertEqual(opened["final"], where)
                answer = simulate(steps + [{"fire": "forward-left", "atMs": 9000}])
                self.assertEqual(answer["final"], "Idle")
                self.assertIn("cancelDictation", answer["actions"])
                self.assertIn("resumeMusic", answer["actions"],
                              "leaving Listening must give the music back")


class TheRefusalThatKeepsTheMicrophoneOpen(unittest.TestCase):
    """*"dacă nu e nimic bindat, dictarea nu se termină, ci așteaptă să se
    înțeleagă unde se trimite. De aia apare warning. Nu la început."*"""

    def test_forward_right_with_nothing_bound_waits_warns_and_holds_the_line(self):
        """All four claims at once, because three survive the fourth breaking.

        Stays in `Listening`; the transition is **internal**, so the composite's
        `exit` never runs; exactly one warning; and neither `resumeMusic` nor
        `stopDictation` fires. An ordinary self-transition would satisfy the
        first and quietly break the rest — which is why `A --> A` is a parse
        error in this grammar rather than a discouraged style.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-right", "atMs": 5000}],
                          world={"bound": False})
        bad = refusal_findings(answer, IN_LISTENING)
        self.assertFalse(bad, "🔼 → with nothing bound ended the sentence:\n  "
                              + "\n  ".join(bad))

    def test_the_warning_comes_at_the_end_and_not_at_the_start(self):
        """*"Nu la început."* — opening a dictation unbound warns about nothing.

        The hold is five minutes long and the bind may arrive at any point in it;
        a warning fired at the chord would be a complaint about a state he is
        allowed to be in.
        """
        answer = simulate([{"fire": "forward-click", "atMs": 0}],
                          world={"bound": False})
        self.assertEqual(answer["warnings"], [],
                         "opening a dictation with nothing bound must not warn")


class NothingStartsWhileTheWordsAreInFlight(unittest.TestCase):
    """The 2026-09-13 phantom dictation, made unwriteable rather than guarded."""

    def _settled(self, extra):
        return simulate([{"fire": "forward-click", "atMs": 0},
                         {"fire": "forward-click", "atMs": 3000}] + extra,
                        world={"bound": True})

    def test_a_forward_gesture_during_settling_never_opens_a_dictation(self):
        """A click here is a stop or nothing — and there is nothing to stop.

        On 2026-09-13 a second 🔼 click landed inside the settle, where
        `onPasteToggle` asked only about `listening`, and opened a phantom
        dictation whose `gestureSeen` disarmed the first sentence's swallow
        window; the sentence went into Word with the relay blind to it. Here
        `Settling` has no arrow out on any forward gesture but `forward-left`,
        so there is no diagram in which it can happen — this test asserts the
        absence, which is the only way an absence stays true.
        """
        for gesture in ("forward-click", "forward-right", "forward-up"):
            with self.subTest(gesture=gesture):
                answer = self._settled([{"fire": gesture, "atMs": 4000}])
                self.assertEqual(answer["final"], "Settling",
                                 f"`{gesture}` moved the machine out of Settling")
                during = answer["transitions"][-1]
                self.assertTrue(during["internal"],
                                f"`{gesture}` during the settle is not internal")
                self.assertEqual(during["actions"], ["sayInFlight"],
                                 f"`{gesture}` during the settle did more than say so")
                self.assertEqual(answer["actions"].count("openDictation"), 1,
                                 "a second dictation was opened while the words "
                                 "were still in flight — the 2026-09-13 failure")

    def test_a_gesture_settling_has_no_answer_for_is_refused_not_improvised(self):
        """`refused` is the answer to *why did nothing happen*.

        Before this machine that question had no answer anywhere in the app. A
        gesture with no arrow must land there rather than fall through to the
        parent — `Settling` is not inside `Listening`, so nothing above it can
        answer on its behalf.
        """
        answer = self._settled([{"fire": "back-right", "atMs": 4000}])
        self.assertEqual(answer["final"], "Settling")
        self.assertIn("back-right", answer["refused"])
        self.assertNotIn("postWisprHandsFree", answer["actions"],
                         "Settling must not borrow Listening's answer")


class TheWorldCanOpenAndCloseOneToo(unittest.TestCase):
    """**The machine must follow dictations no gesture started.**

    Every case here was a real defect found in review on 2026-09-14, and each one
    parked the machine somewhere reality was not. They are worth a test class of
    their own because none of them is reachable from the mouse: they are the
    menu, the loopback, Wispr Flow's own keyboard chord, the overlay's ✕, and a
    `source.start()` that refused — the paths a diagram written from the gestures
    outwards does not think about.
    """

    def test_a_dictation_the_world_started_is_followed(self) -> None:
        """Menu *Start Dictation*, `/test/dictation/start`, Wispr's own chord, and
        the diagram's own `🔽 → / postWisprHandsFree` all open a microphone with no
        gesture. The machine used to sit in `Idle` through all of it — no music
        pause — and then refuse `@delivered` when the words came back."""
        a = simulate([{"fire": "@micOpened"}])
        self.assertNotEqual(a["final"], "Idle",
                            "the machine ignored a microphone the world opened")
        self.assertIn("pauseMusic", a["actions"],
                      "the music was not paused for a dictation the world started")

    def test_and_followed_to_the_right_destination(self) -> None:
        a = simulate([{"fire": "@micOpened"}], world={"bound": True})
        self.assertEqual(a["final"], "ToBound")

    def test_a_dictation_the_world_ended_reaches_the_settle(self) -> None:
        """Menu *End Dictation*, or Wispr's own chord pressed a second time. With
        no arrow on `@micConfirmedShut` the machine stayed in `Listening` while the
        words were in flight and refused `@delivered` for ever."""
        a = simulate([{"fire": "@micOpened"},
                      {"fire": "@micConfirmedShut"},
                      {"fire": "@delivered"}])
        self.assertEqual(a["final"], "Idle")
        self.assertEqual(a["refused"], [],
                         "a dictation the world opened and closed was not followed")

    def test_a_cancel_from_outside_gives_the_music_back(self) -> None:
        """The overlay's ✕, the menu's *Cancel Dictation*, `POST /test/cancel` and
        Wispr's own ⌃Escape all reach `dictationEnded(.cancelled)` and nothing
        else. Without `@idle` the machine stayed in `Listening`, `exit /
        resumeMusic` never ran, and his music did not come back."""
        a = simulate([{"fire": "forward-click"},
                      {"fire": "@micOpened"},
                      {"fire": "@idle"}])
        self.assertEqual(a["final"], "Idle")
        self.assertEqual(a["actions"].count("pauseMusic"),
                         a["actions"].count("resumeMusic"),
                         "the music was paused and never resumed")

    def test_the_music_is_paused_and_resumed_exactly_once_per_sentence(self) -> None:
        a = simulate([{"fire": "forward-click"}, {"fire": "@micOpened"},
                      {"fire": "forward-click"}, {"fire": "@micConfirmedShut"},
                      {"fire": "@delivered"}])
        self.assertEqual(a["actions"].count("pauseMusic"), 1)
        self.assertEqual(a["actions"].count("resumeMusic"), 1)


class TheHoldIsNotAState(unittest.TestCase):
    """**A resting state that eats the mouse is worse than the hold it models.**

    `HeldForBind` was a state for one build. It answered no gesture at all, so for
    up to five minutes after an unbound sentence landed every mouse gesture *and*
    the back button's Return were swallowed by the tap and refused by the diagram.
    The five-minute hold is a property of a `Message` waiting for a bind, not of
    the mouse, and it lives beside the machine now.
    """

    def test_an_unbound_sentence_returns_the_machine_to_idle(self) -> None:
        a = simulate([{"fire": "forward-click"}, {"fire": "@micOpened"},
                      {"fire": "forward-click"}, {"fire": "@held"}])
        self.assertEqual(a["final"], "Idle")

    def test_and_the_next_gesture_still_works(self) -> None:
        a = simulate([{"fire": "forward-click"}, {"fire": "@micOpened"},
                      {"fire": "forward-click"}, {"fire": "@held"},
                      {"fire": "forward-click"}])
        self.assertEqual(a["refused"], [],
                         "a gesture after a held sentence was refused — the mouse "
                         "is dead for the length of the hold again")
        self.assertIn("openDictation", a["actions"])


class DisconnectOutranksASentence(unittest.TestCase):
    """*"stop, this is going to the wrong place"* — 🔽 ↓ existed only in `Idle`
    until review caught it, though `.claude/rules/mouse-gestures.md` has said
    since 2026-09-06 that it outranks a held prompt and a running dictation."""

    def test_unbind_works_mid_sentence(self) -> None:
        a = simulate([{"fire": "forward-right"}, {"fire": "@micOpened"},
                      {"fire": "back-down"}], world={"bound": True})
        self.assertIn("unbind", a["actions"])
        self.assertEqual(a["refused"], [])

    def test_a_bind_still_reaches_the_words_during_the_settle(self) -> None:
        """It worked one state either side of `Settling` and not in it."""
        a = simulate([{"fire": "forward-click"}, {"fire": "@micOpened"},
                      {"fire": "forward-click"}, {"fire": "forward-bind"}])
        self.assertIn("bindFrontmost", a["actions"])


class TheWheelConvertsRatherThanEnding(unittest.TestCase):
    """The wheel clicked twice turns the dictation into a spawn (2026-09-05).

    Mapped onto `forward-up` it hit the arrow that *ends* a sentence, so the
    second click a third of a second behind the first stopped a recording shorter
    than `MicRecorder.minimumDuration` — dropped as a misfire, no spawn, no words.
    """

    def test_the_second_click_reaims_and_keeps_the_microphone(self) -> None:
        a = simulate([{"fire": "key-dictate"}, {"fire": "@micOpened"},
                      {"fire": "wheel-double"}])
        self.assertEqual(a["final"], "ToSpawn")
        self.assertNotIn("stopDictation", a["actions"],
                         "the wheel's double click ended the sentence instead of "
                         "converting it")


def self_test() -> int:
    """**Prove the load-bearing check can fail**, by removing the refusal.

    A guard nobody has watched fail is a guard nobody knows the shape of. The
    fixture straightens `Listening : 🔼 forward-right / warnNothingBound` — the
    internal transition — into an ordinary arrow to `Settling`, which is exactly
    the tidy-up a reader who had not read Victor's sentence would make. It
    parses, it resolves, it renders, and the microphone closes on a sentence with
    nowhere to go.
    """
    if not BINARY.exists():
        print("✗ no ./.build/debug/WalkieTalkie — run `swift build` first", file=sys.stderr)
        return 2

    text = PUML.read_text()
    refusal = "Listening : 🔼 forward-right / warnNothingBound"
    if refusal not in text:
        print(f"✗ the fixture could not be built — `{refusal}` is not in the diagram; "
              f"either the refusal is gone or this file has stopped matching",
              file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "no-refusal.puml"
        bad.write_text(text.replace(
            refusal,
            "Listening --> Settling : 🔼 forward-right / aimAtCaret, stopDictation"))
        answer = simulate([{"fire": "forward-click", "atMs": 0},
                           {"fire": "forward-right", "atMs": 5000}],
                          world={"bound": False}, puml=bad,
                          home=str(Path(tmp) / "home"))
        findings = refusal_findings(answer, IN_LISTENING)
        if not findings:
            print("✗ a diagram that ENDS the sentence with nothing bound was "
                  "ACCEPTED — the refusal check proves nothing", file=sys.stderr)
            return 1
        print("✓ a 🔼 → that ends an unaimed sentence is rejected:")
        for line in findings:
            print(f"    {line}")

    answer = simulate([{"fire": "forward-click", "atMs": 0},
                       {"fire": "forward-right", "atMs": 5000}],
                      world={"bound": False})
    findings = refusal_findings(answer, IN_LISTENING)
    if findings:
        print("✗ …and the checked-in diagram is rejected too:\n  "
              + "\n  ".join(findings), file=sys.stderr)
        return 1
    print("✓ and accepts docs/gestures.puml — the microphone stays open, one warning")
    return 0


#: What `--list` prints: one row per sentence of the vocabulary, in his order.
SCENARIOS = [
    ("forward-click from Idle", "la apăsarea forward simplă începe dictarea"),
    ("forward-bind mid-dictation", "leagă dictarea de terminalul de sub mouse"),
    ("forward-click while listening", "îmi varsă textul la caret"),
    ("forward-up while listening", "deschide meniul de foldere"),
    ("forward-right, nothing bound", "dictarea nu se termină, ci așteaptă"),
    ("forward-right, bound", "the mirror — it does end, and aims at the terminal"),
    ("forward-left, any destination", "cancel either"),
    ("any forward gesture in Settling", "a stop or nothing, never a new dictation"),
]


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    if not BINARY.exists():
        print(f"✗ {BINARY} does not exist — run `swift build` first. Nothing was "
              f"asserted, which is not the same as a clean tree", file=sys.stderr)
        return 2
    if not IN_LISTENING:
        print(f"✗ no substates parsed inside `state {LISTENING}` in {PUML.name} — "
              f"this file has stopped reading the diagram, which is not the same "
              f"as a clean tree", file=sys.stderr)
        return 2
    try:
        probe = simulate([{"fire": "forward-click", "atMs": 0}])
    except AssertionError as error:
        print(f"✗ the machine will not run at all: {error}", file=sys.stderr)
        return 2
    if not probe["transitions"]:
        print("✗ a forward click produced no transitions at all — the machine has "
              "stopped matching, which is not the same as a clean tree", file=sys.stderr)
        return 2

    if "--list" in argv:
        print(f"{PUML.relative_to(ROOT)} — Listening holds "
              f"{', '.join(sorted(IN_LISTENING))}")
        print(f"origin: {probe['origin']}\n")
        for name, said in SCENARIOS:
            print(f"  {name:<34} {said}")
        return 0

    result = unittest.main(argv=[argv[0] if argv else sys.argv[0]],
                           exit=False, verbosity=2).result
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
