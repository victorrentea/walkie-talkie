#!/usr/bin/env python3
"""**There is one place that decides what a mouse gesture means, and it is not Swift.**

`docs/gestures.puml` is the gesture program. `GestureDiagram` parses it,
`GestureMachine` executes it. The whole value of that arrangement is that there
is exactly **one** transition table, and it is the file on disk — so this eval
guards the three ways a second one grows back.

Before 2026-09-14 the vocabulary lived in `HotkeyTap`'s `switch keyCode`, in
eight per-gesture callbacks on `AppDelegate`, and in about twenty booleans
between them. The answer to *what does 🔼 → do while unbound* was a four-clause
boolean expression at `AppDelegate.swift:2646`:

    let atCaret = pasteMode
        || (speculative && !listening)
        || (listening && !isBound && !spawnPending)
        || (settling && settlingAtCaret)

That is a state function written as an expression, and nearly every rule in
`.claude/rules/dictation-source.md` that cost a night is a missing guard on one
of the states it stands for. None of it announced itself; it was found by
symptoms, one night at a time.

So the three checks below, each against a way the old shape comes back:

1. **Policy creeping back into the tap.** The side-button branch must swallow,
   refuse autorepeat, name the gesture and fire it — and nothing else. It is one
   `if` away from growing "just this one case" again.
2. **A second set of callbacks.** `HotkeyTap` may declare exactly one gesture
   callback, and `AppDelegate` may assign exactly that one.
3. **The state function written as an expression.** While the `atCaret`
   expression exists anywhere in `Sources/`, the machine is not the source of
   truth — something is still deriving the state the machine owns. Its fourth
   clause, `settling && settlingAtCaret`, is exempt on purpose; see
   `ATCARET_FRAGMENTS` for why that one is a different fact.

And a fourth, which is about the other seam Victor named on the same day —
*"nu motorul de hackuire al lui Wispr Flow, care trebuie cu grijă decuplat
oricum și pus sub un strat, ca să poată jongla ușor între modelul local și
modelul remote"*: the registry may not reach a **concrete recogniser type**.

Exit 2 when a check finds nothing to look at — a parser that has stopped
matching must not read as a clean tree. `--list` prints what was found;
`--self-test` proves each check rejects the shape it is written against.
"""
from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"
HOTKEY_TAP = SOURCES / "HotkeyTap.swift"
APP_DELEGATE = SOURCES / "AppDelegate.swift"
ACTIONS = SOURCES / "GestureActions.swift"

# `postWisprHandsFree` is the one deliberate exception and it is not a leak: the
# action posts *Wispr Flow's own keyboard chord*, which is a key to post, not a
# recogniser to drive. What may not appear is a concrete recogniser TYPE — the
# thing that would make the registry care which engine is listening.
FORBIDDEN_TYPES = [
    "WisprFlowSource", "LocalWhisperSource", "WisprHistory", "WisprState",
    "WisprScratchpad", "WisprNotes", "WisprSink", "WisprWatch", "Transcriber",
]

# The clauses the machine replaced. Whitespace-insensitive, because it is the
# shape that matters and a reformat is not a fix.
#
# **`settling && settlingAtCaret` is deliberately NOT here**, and the carve-out is
# the point rather than a weakening. Three of the original four clauses were one
# question asked three ways — *is this sentence pointed at the caret* — and the
# machine answers it. The fourth is a different fact: once the microphone has
# closed the aim is **latched on the sentence**, and `Settling` deliberately does
# not carry a destination, because the aim by then belongs to the words in flight
# and not to the state. Putting it in the machine as well would be a second copy
# of a fact `deliver` already owns, which is the thing this file exists to stop.
ATCARET_FRAGMENTS = [
    r"speculative\s*&&\s*!\s*listening",
    r"listening\s*&&\s*!\s*isBound\s*&&\s*!\s*spawnPending",
]

# The eight that carried the policy. `onGesture` is the one that replaced them.
RETIRED_CALLBACKS = [
    "onPasteToggle", "onGestureBind", "onGestureUnbind", "onGestureSpawn",
    "onLocalCancel", "onLocalToggle", "onWheelDictate", "onWheelDoubleSpawn",
    "onWheelIdleDoubleSpawn",
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_comments(text: str) -> str:
    """Comments legitimately name the retired callbacks — they are the record of
    why a gesture means what it means, and this repo keeps that. Only code is
    checked."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def gesture_branch(text: str) -> str | None:
    """The body of the `if useLogiGestures && ctrl && opt && cmd` branch, by
    brace matching from the opening `{`."""
    m = re.search(r"if useLogiGestures\s*&&\s*ctrl\s*&&\s*opt\s*&&\s*cmd", text)
    if not m:
        return None
    i = text.index("{", m.end())
    depth, j = 0, i
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
        j += 1
    return None


def declared_gesture_callbacks(text: str) -> list[str]:
    names = re.findall(r"\bvar\s+(on[A-Z]\w*)\s*:\s*\(\(", text)
    return sorted(n for n in names if n in RETIRED_CALLBACKS or n == "onGesture")


class TheTapOnlyNamesGestures(unittest.TestCase):
    """The tap swallows, refuses autorepeat, names the gesture, fires. No policy."""

    def setUp(self) -> None:
        self.body = gesture_branch(strip_comments(read(HOTKEY_TAP)))
        if self.body is None:
            print("✗ the side-button branch was not found in HotkeyTap.swift — "
                  "nothing was asserted, which is not the same as a clean tree",
                  file=sys.stderr)
            raise SystemExit(2)

    def test_it_fires_rather_than_deciding(self) -> None:
        self.assertIn("fire(", self.body,
                      "the side-button branch no longer hands the gesture to the machine")

    def test_no_dispatch_and_no_per_gesture_case(self) -> None:
        """A `case VK_F…` or a `DispatchQueue` here is policy coming back."""
        self.assertNotIn("DispatchQueue", self.body,
                         "the tap is dispatching work again — that belongs to an action "
                         "in GestureActions, reached through the diagram")
        self.assertIsNone(re.search(r"\bcase\s+Self\.VK_F", self.body),
                          "a per-gesture `case` is back in the tap; what a gesture means "
                          "belongs in docs/gestures.puml")

    def test_the_one_piece_of_physics_is_still_there(self) -> None:
        """`leftIsHeld` is the exception and must survive: it is a window-server
        round trip that could not live in a guard, so the tap coins the WORD."""
        self.assertIn("leftIsHeld", self.body)
        self.assertIn("forward-bind", self.body)


class OneCallbackOnly(unittest.TestCase):
    def test_hotkeytap_declares_only_onGesture(self) -> None:
        found = declared_gesture_callbacks(read(HOTKEY_TAP))
        if not found:
            print("✗ no gesture callback found in HotkeyTap.swift — nothing was "
                  "asserted", file=sys.stderr)
            raise SystemExit(2)
        self.assertEqual(found, ["onGesture"],
                         f"HotkeyTap declares gesture callbacks beside onGesture: {found}")

    def test_appdelegate_assigns_only_onGesture(self) -> None:
        code = strip_comments(read(APP_DELEGATE))
        assigned = sorted(set(re.findall(r"hotkeys\.(on[A-Z]\w*)\s*=", code)))
        if not assigned:
            print("✗ AppDelegate assigns no hotkey callbacks at all — nothing was "
                  "asserted", file=sys.stderr)
            raise SystemExit(2)
        back = sorted(n for n in assigned if n in RETIRED_CALLBACKS)
        self.assertEqual(back, [],
                         f"AppDelegate is wiring retired gesture callbacks again: {back}")
        self.assertIn("onGesture", assigned,
                      "AppDelegate never wires onGesture — the machine is fed by nothing")


class TheStateFunctionIsNotAnExpression(unittest.TestCase):
    def test_the_atCaret_expression_is_gone(self) -> None:
        code = strip_comments("\n".join(read(p) for p in sorted(SOURCES.glob("*.swift"))))
        if not code.strip():
            print("✗ read no Swift at all — nothing was asserted", file=sys.stderr)
            raise SystemExit(2)
        back = [f for f in ATCARET_FRAGMENTS if re.search(f, code)]
        self.assertEqual(back, [], (
            "the destination is being re-derived as a boolean expression again "
            f"({back}). It is a state now — ask the machine with isIn(\"AtCaret\")."
        ))


class TheRegistryCannotSeeARecogniser(unittest.TestCase):
    def test_no_concrete_recogniser_type(self) -> None:
        code = strip_comments(read(ACTIONS))
        if "GestureWorld" not in code:
            print("✗ GestureActions.swift does not look like the registry — nothing "
                  "was asserted", file=sys.stderr)
            raise SystemExit(2)
        leaks = [t for t in FORBIDDEN_TYPES if t in code]
        self.assertEqual(leaks, [], (
            f"the gesture registry reaches a recogniser type ({leaks}). It speaks "
            "DictationSource only — which engine is listening is the Engine menu "
            "row's business."
        ))


def listing() -> int:
    body = gesture_branch(strip_comments(read(HOTKEY_TAP))) or ""
    print(f"HotkeyTap gesture callbacks : {declared_gesture_callbacks(read(HOTKEY_TAP))}")
    print(f"side-button branch          : {len(body.splitlines())} lines, "
          f"fire(): {'yes' if 'fire(' in body else 'NO'}")
    print(f"AppDelegate assigns         : "
          f"{sorted(set(re.findall(r'hotkeys[.](on[A-Z]\\w*)\\s*=', strip_comments(read(APP_DELEGATE)))))}")
    print(f"recogniser types in registry: "
          f"{[t for t in FORBIDDEN_TYPES if t in strip_comments(read(ACTIONS))] or 'none'}")
    return 0


def self_test() -> int:
    """Each check, against the shape it was written against."""
    failures = []

    tap_with_policy = """
    if useLogiGestures && ctrl && opt && cmd {
        switch keyCode {
        case Self.VK_F10:
            DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
            return nil
        }
    }
    """
    body = gesture_branch(tap_with_policy)
    if body is None or "DispatchQueue" not in body or not re.search(r"\bcase\s+Self\.VK_F", body):
        failures.append("the tap check would not have rejected the pre-2026-09-14 switch")

    if declared_gesture_callbacks("var onPasteToggle: (() -> Void)?\nvar onGesture: ((String) -> Void)?") \
            == ["onGesture"]:
        failures.append("the callback check would not have seen onPasteToggle")

    old = ("let atCaret = pasteMode || (speculative && !listening) "
           "|| (listening && !isBound && !spawnPending) || (settling && settlingAtCaret)")
    if not [f for f in ATCARET_FRAGMENTS if re.search(f, old)]:
        failures.append("the atCaret check would not have matched the expression it replaced")

    if not [t for t in FORBIDDEN_TYPES if t in "let s = WisprFlowSource()"]:
        failures.append("the seam check would not have seen a WisprFlowSource")

    for line in failures:
        print(f"✗ {line}", file=sys.stderr)
    if failures:
        return 1
    print("✓ all four checks reject the shape they are written against")
    return 0


if __name__ == "__main__":
    if "--list" in sys.argv:
        raise SystemExit(listing())
    if "--self-test" in sys.argv:
        raise SystemExit(self_test())
    unittest.main(argv=[sys.argv[0], "-v"])
