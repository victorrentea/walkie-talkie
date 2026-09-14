#!/usr/bin/env python3
"""**The picture on the arrow must agree with the word the parser reads.**

`GestureDiagram` takes the **last** whitespace-separated token of a trigger
clause and throws the rest away. That is a deliberate and good decision — it is
what lets the diagram be a readable picture (`🔼 →`, `🔽 ←`) and an executable
program at the same time, instead of making the file choose. The parser's own
comment says so: *"the 🔼 / 🔽 / arrow in front is a glyph for the reader."*

The price is that **everything in front of the trigger is unchecked by
construction**. A line reading

    Listening --> Settling : 🔽 ← forward-right / stopDictation

parses, resolves, renders, and runs `forward-right` — while the picture beside
it tells a reader that the *back* button, pushed *left*, ends the sentence. The
diagram is the thing Victor reviews the vocabulary in, so a diagram whose glyphs
lie is worse than one with no glyphs at all: the failure is silent, it is in the
reviewable artefact, and the executable half stays green throughout. Nothing else
in the build looks at those characters. This file is the only reader they have.

So the rule, stated so it can be argued with: **a `forward-*` trigger is drawn
🔼, a `back-*` trigger is drawn 🔽, a `key-*` trigger is drawn ⌨**, and the
expectation is derived from `HotkeyTap.gestureVocabulary` rather than from a
table here — a second table is the drift this whole state-machine change exists
to remove.

The same parse answers a second question, and it is the one with teeth: **can
the mouse actually make this gesture?** A bare trigger has to be a name
`HotkeyTap` can produce, or the diagram has invented a button. Two sources count,
because there are two ways the tap names a gesture:

- **`gestureVocabulary`** — the ten side-button rows, each a keycode Options+
  sends.
- **the names the tap builds out of physics** — `forward-bind` is not a row at
  all. It is `forward-click` with the left button genuinely held, judged by
  `leftIsHeld` against the window server, because a clock and an I/O round trip
  could not live inside a diagram guard. The tap decides *which word* the gesture
  is and the diagram decides what the word does. So the names it assigns are read
  out of its own source rather than listed here, which is the same rule as
  above: no second table.

`key-*` triggers are exempt from the vocabulary check and only from it — they are
keyboard chords (⌘⌃D), not mouse gestures, and there is no mouse row to find.

    evals/test_gesture_glyphs.py              # glyphs and vocabulary
    evals/test_gesture_glyphs.py --list       # …and print every trigger found
    evals/test_gesture_glyphs.py --self-test  # prove it rejects a lying glyph

Exit 0 when clean, 1 when a glyph lies or a gesture is invented, 2 when either
parse found nothing — no triggers in the diagram, or no rows in
`gestureVocabulary`, means this file has stopped matching, and a parser that has
stopped matching must not read as a clean tree.
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUML = ROOT / "docs" / "gestures.puml"
HOTKEY_SWIFT = ROOT / "Sources" / "WalkieTalkie" / "HotkeyTap.swift"

#: What each family of gesture is drawn as. The 🔼 / 🔽 are the two side buttons
#: as Victor speaks about them ("🔼 click", "🔽 →"); ⌨ is the keyboard, which has
#: no button to draw.
GLYPH_FOR_FAMILY = {"forward": "🔼", "back": "🔽", "key": "⌨"}

IGNORED = ("@startuml", "@enduml", "skinparam", "hide", "show", "title", "legend",
           "scale", "left to right", "top to bottom", "!", "caption", "header",
           "footer", "note ", "end note")

#: A `gestureVocabulary` row: `("forward-click", Self.VK_F7, "⌃⌥⌘F7", "…")`.
#: Anchored on the keycode — a qualified one, because the table says `Self.VK_F7`
#: — so a tuple of four strings elsewhere in the file cannot be mistaken for one.
VOCABULARY_ROW = re.compile(r'\(\s*"([a-z][a-z0-9-]*)"\s*,\s*((?:\w+\.)?VK_\w+)\s*,')

#: The names `HotkeyTap.triggerNames` adds on top of the ten rows — the words the
#: tap coins itself. `forward-bind` is F7 with the left button genuinely held,
#: `key-dictate` is ⌘⌃D; neither is a row, both are gestures the diagram may use.
TRIGGER_NAMES_EXTRAS = re.compile(
    r'static var triggerNames[^\n]*?gestureNames\s*\+\s*\[([^\]]*)\]')

#: A gesture name the tap **builds** inside `handle` — `gesture = "forward-bind"`
#: after `leftIsHeld`. Read from the tap's source for the same reason the rows
#: are: a list here would be a second table to keep in step.
TAP_ASSIGNED = re.compile(r'\bgesture\s*=\s*"([a-z][a-z0-9-]*)"')


def mouse_vocabulary(text: str) -> tuple[dict[str, str], set[str]]:
    """`({name: keycode}, {names the tap coins})` out of `HotkeyTap.swift`.

    Two sources, because `HotkeyTap` names a gesture two ways: a keycode row that
    Options+ sends, and a word it decides on from physics no guard could ask
    about. `triggerNames` is the tap's own statement of the union and is read
    rather than re-derived.
    """
    coined = set(TAP_ASSIGNED.findall(text))
    extras = TRIGGER_NAMES_EXTRAS.search(text)
    if extras:
        coined |= set(re.findall(r'"([a-z][a-z0-9-]*)"', extras.group(1)))
    return dict(VOCABULARY_ROW.findall(text)), coined


class Trigger:
    """One trigger clause as it is written, and as the parser reads it."""

    def __init__(self, line_no: int, line: str, clause: str):
        self.line_no = line_no
        self.line = line
        tokens = clause.split()
        self.tokens = tokens
        self.name = tokens[-1] if tokens else ""
        #: Everything in front of the trigger — what the reader sees and the
        #: parser discards.
        self.decoration = tokens[:-1]

    @property
    def is_event(self) -> bool:
        """`@bindArrived` — the world answering, not his hand. No button to draw."""
        return self.name.startswith("@")

    @property
    def family(self) -> str:
        return self.name.split("-", 1)[0] if "-" in self.name else ""

    @property
    def expected_glyph(self) -> str | None:
        return GLYPH_FOR_FAMILY.get(self.family)

    def __repr__(self):
        return f"gestures.puml:{self.line_no}: {self.line.strip()}"


def triggers(text: str) -> list[Trigger]:
    """Every trigger clause in the diagram, arrows and internal lines alike."""
    out: list[Trigger] = []
    depth = 0
    for i, raw in enumerate(text.splitlines(), start=1):
        s = raw.strip()
        if not s or s.startswith("'"):
            continue
        if depth > 0:
            depth += 1 if s.endswith("{") else (-1 if s.startswith("}") else 0)
            continue
        low = s.lower()
        if any(low.startswith(p) for p in IGNORED):
            if s.endswith("{"):
                depth = 1
            continue
        if s == "}" or s.startswith("state ") or s.startswith("[*]"):
            continue
        if "-->" in s or "->" in s:
            arrow = "-->" if "-->" in s else "->"
            rest = s.split(arrow, 1)[1]
            if ":" not in rest:
                continue
            label = rest.split(":", 1)[1]
        elif ":" in s:
            label = " ".join(s.split(":", 1)[1].split())
            if (label.startswith("chip ") or label.startswith("note ")
                    or label.startswith("entry /") or label.startswith("exit /")):
                continue
        else:
            continue
        # The trigger clause is everything before the guard and before the
        # actions — exactly the slice `GestureDiagram.transition` takes the last
        # token of.
        clause = label.split("/", 1)[0]
        clause = clause.split("[", 1)[0]
        if clause.strip():
            out.append(Trigger(i, s, clause))
    return out


TRIGGERS = triggers(PUML.read_text())
VOCABULARY, TAP_NAMES = mouse_vocabulary(HOTKEY_SWIFT.read_text())
MAKEABLE = set(VOCABULARY) | TAP_NAMES


def wrong_glyphs(found: list[Trigger]) -> list[str]:
    """Every decorated trigger whose picture disagrees with its word."""
    bad = []
    for t in found:
        if t.is_event or not t.decoration:
            continue
        want = t.expected_glyph
        if want is None:
            bad.append(f"{t!r} — `{t.name}` is in no known family "
                       f"({', '.join(sorted(GLYPH_FOR_FAMILY))})")
        elif t.decoration[0] != want:
            bad.append(f"{t!r} — drawn `{t.decoration[0]}`, but `{t.name}` is a "
                       f"`{t.family}-*` gesture and is drawn `{want}`")
    return bad


def invented_gestures(found: list[Trigger], makeable: set[str]) -> list[str]:
    """Every bare trigger the mouse cannot produce."""
    bad = []
    for t in found:
        if t.is_event or t.family == "key":
            continue
        if t.name not in makeable:
            bad.append(f"{t!r} — `{t.name}` is in neither "
                       f"HotkeyTap.gestureVocabulary nor any name the tap assigns")
    return bad


class TheGlyphAgreesWithTheTrigger(unittest.TestCase):
    """What the arrow shows is what the parser will run."""

    def test_every_decorated_trigger_carries_the_right_glyph(self):
        """🔼 forward, 🔽 back, ⌨ key — derived from the family, not from a list.

        A label may read `🔼 ←` and do `forward-right`: only the glyph is
        checked, because the arrow after it is Victor's own shorthand for the
        wheel direction and carries no separate claim.
        """
        bad = wrong_glyphs(TRIGGERS)
        self.assertFalse(bad, "the picture disagrees with the program:\n  "
                              + "\n  ".join(bad))

    def test_the_glyph_is_the_first_token(self):
        """The decoration is read left to right, so the button comes first.

        Asserted separately because `wrong_glyphs` could be satisfied by a glyph
        anywhere in the decoration, and `← 🔼 forward-right` reads as the arrow
        being the button.
        """
        for t in TRIGGERS:
            if t.is_event or not t.decoration:
                continue
            for extra in t.decoration[1:]:
                self.assertNotIn(extra, GLYPH_FOR_FAMILY.values(),
                                 f"{t!r} — a second button glyph after the first")


class TheMouseCanMakeIt(unittest.TestCase):
    """The diagram may not invent a gesture the hardware does not send."""

    def test_every_bare_trigger_is_a_gesture_hotkeytap_produces(self):
        """`gestureVocabulary`, plus the names the tap builds out of physics.

        `forward-bind` is the second kind: `forward-click` with the left button
        held, decided by `leftIsHeld` against the window server rather than by a
        guard, because a diagram that has to do I/O is not simulatable.
        """
        bad = invented_gestures(TRIGGERS, MAKEABLE)
        self.assertFalse(bad, "the diagram invents a gesture:\n  " + "\n  ".join(bad))

    def test_key_triggers_are_named_as_keyboard_chords(self):
        """The one exemption is narrow, and it is spelled in the name."""
        for t in TRIGGERS:
            if t.is_event or t.name in MAKEABLE:
                continue
            self.assertTrue(t.name.startswith("key-"),
                            f"{t!r} — not a mouse gesture and not named `key-*`")


def self_test() -> int:
    """**Prove both checks can fail**, on a diagram broken each way.

    The first fixture draws a `back-*` trigger with the forward button's glyph —
    the silent failure this file exists for, since the parser reads the word and
    ignores the picture entirely. The second invents `forward-sideways`, a
    gesture no Logi button sends.
    """
    text = PUML.read_text()
    if not TRIGGERS or not VOCABULARY:
        print("✗ nothing parsed — see the exit-2 rule", file=sys.stderr)
        return 2

    lying = text.replace("🔽 back-click", "🔼 back-click")
    if lying == text:
        print("✗ the fixture could not be built — no `🔽 back-click` in the diagram",
              file=sys.stderr)
        return 2
    bad = wrong_glyphs(triggers(lying))
    if not bad:
        print("✗ a `back-click` drawn 🔼 was ACCEPTED — the glyph check proves nothing",
              file=sys.stderr)
        return 1
    print(f"✓ a back gesture drawn with the forward glyph is rejected ({len(bad)} line(s))")

    invented = text.replace("🔼 forward-up /", "🔼 forward-sideways /")
    if invented == text:
        print("✗ the fixture could not be built — no `🔼 forward-up /` in the diagram",
              file=sys.stderr)
        return 2
    bad = invented_gestures(triggers(invented), MAKEABLE)
    if not bad:
        print("✗ `forward-sideways` was ACCEPTED — the vocabulary check proves nothing",
              file=sys.stderr)
        return 1
    print(f"✓ a gesture the mouse cannot make is rejected ({len(bad)} line(s))")

    still = wrong_glyphs(TRIGGERS) + invented_gestures(TRIGGERS, MAKEABLE)
    if still:
        print(f"✗ …and the checked-in diagram is rejected too:\n  "
              + "\n  ".join(still), file=sys.stderr)
        return 1
    print("✓ and accepts docs/gestures.puml")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    if not TRIGGERS or not VOCABULARY:
        print(f"✗ parsed {len(TRIGGERS)} trigger(s) out of {PUML.name} and "
              f"{len(VOCABULARY)} gestureVocabulary row(s) out of {HOTKEY_SWIFT.name} "
              f"— one of the two parsers has stopped matching, which is not the same "
              f"as a clean tree", file=sys.stderr)
        return 2

    if "--list" in argv:
        print(f"HotkeyTap.gestureVocabulary — {len(VOCABULARY)} row(s)")
        for name, key in sorted(VOCABULARY.items()):
            print(f"  {GLYPH_FOR_FAMILY.get(name.split('-')[0], '?')}  {name:<15} {key}")
        print(f"built by the tap: {', '.join(sorted(TAP_NAMES)) or '(none)'}")
        print(f"\ndocs/gestures.puml — {len(TRIGGERS)} trigger clause(s)")
        for t in TRIGGERS:
            kind = "event" if t.is_event else ("key  " if t.family == "key" else "mouse")
            drawn = t.decoration[0] if t.decoration else "—"
            print(f"  {kind}  {drawn:<3} {t.name:<16} line {t.line_no}")
        return 0

    result = unittest.main(argv=[argv[0] if argv else sys.argv[0]],
                           exit=False, verbosity=2).result
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
