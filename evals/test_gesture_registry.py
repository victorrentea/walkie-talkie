#!/usr/bin/env python3
"""**The diagram and the registry are a bijection, and both directions cost
something.**

`docs/gestures.puml` names behaviour; `GestureActions.swift` implements it. The
two files are a seam, and a seam has two failure modes, not one.

**A name in the diagram that the registry does not answer** is caught at launch —
`GestureMachine.init` resolves every action and guard eagerly and refuses the
diagram whole, because a partial machine would answer some gestures and silently
drop others. `test_gesture_diagram.py` asserts that refusal happens. That
direction is covered twice over, and it is the cheap one.

**A registry entry no transition references** is caught by nothing at all. It
compiles, it resolves, it is simply never called — and it reads, to the next
person, as part of the vocabulary. That is worse than dead code in an ordinary
file, because this registry is *the list of what the mouse is allowed to ask
for*: `GestureActions.swift`'s own header calls the protocol "the answer to *what
does this refactor actually contain*". An entry nothing fires makes that answer
wrong. It also hides a rename: `warnNoWords` → `sayNoWords` leaves the old key
behind, the diagram calls the new one, everything is green, and the registry now
documents two behaviours where there is one.

So **there is no exemption list here, deliberately**. The moment one exists,
every dead entry acquires a plausible reason to be on it, and the check stops
meaning anything. An action worth keeping for later belongs in a comment or in
git history, not in a live registry.

The parse is in Python on purpose. Asking the Swift parser whether the Swift
registry agrees with the diagram it just loaded would be the program agreeing
with itself; two independent readings of the same two files is the only version
of this check that can catch a shared assumption.

    evals/test_gesture_registry.py              # both directions
    evals/test_gesture_registry.py --list       # …and print both sides
    evals/test_gesture_registry.py --self-test  # prove it rejects a broken pair

Exit 0 when the two agree, 1 when they do not, 2 when either parse found nothing
at all — a parser that has stopped matching must not read as a clean tree, and
an empty diagram side would make every registry entry "dead" while an empty
registry side would make every diagram name "missing". Both read as loud failures
of this file rather than of the repo.
"""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUML = ROOT / "docs" / "gestures.puml"
ACTIONS_SWIFT = ROOT / "Sources" / "WalkieTalkie" / "GestureActions.swift"

#: Decoration the app's parser skips. Mirrors `GestureDiagram.ignoredPrefixes`.
IGNORED = ("@startuml", "@enduml", "skinparam", "hide", "show", "title", "legend",
           "scale", "left to right", "top to bottom", "!", "caption", "header",
           "footer", "note ", "end note")


# ── the diagram side ────────────────────────────────────────────────────────

def _label_names(label: str) -> tuple[set[str], set[str]]:
    """`(actions, guards)` out of one `trigger [guard] / a, b` label."""
    actions: set[str] = set()
    guards: set[str] = set()
    head = label
    if "/" in head:
        head, tail = head.split("/", 1)
        actions = {a.strip() for a in tail.split(",") if a.strip()}
    if "[" in head and "]" in head:
        g = head[head.index("[") + 1:head.index("]")].strip()
        # `!` is the only operator the grammar has.
        if g.startswith("!"):
            g = g[1:].strip()
        if g:
            guards.add(g)
    return actions, guards


def diagram_names(text: str) -> tuple[set[str], set[str]]:
    """Every action and guard name `docs/gestures.puml` asks for.

    Reads the three places a name can appear: after `/` on an arrow's label,
    after `/` on an internal transition written as a description line, and on
    `entry /` / `exit /` lines — which is where `pauseMusic` and `resumeMusic`
    live and nowhere else.
    """
    actions: set[str] = set()
    guards: set[str] = set()
    depth = 0
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("'"):
            continue
        if depth > 0:                        # a `skinparam … {` body
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
            a, g = _label_names(rest.split(":", 1)[1])
        elif ":" in s:
            body = " ".join(s.split(":", 1)[1].split())
            if body.startswith("chip ") or body.startswith("note "):
                continue
            if body.startswith("entry /") or body.startswith("exit /"):
                a = {x.strip() for x in body.split("/", 1)[1].split(",") if x.strip()}
                g = set()
            else:
                a, g = _label_names(body)
        else:
            continue
        actions |= a
        guards |= g
    return actions, guards


# ── the registry side ───────────────────────────────────────────────────────

def _dictionary_literal(text: str, func: str) -> str:
    """The `[ … ]` a `static func <func>()` returns, by bracket matching.

    Bracket-matched rather than sliced between the two function names, so the
    two can be reordered in the file — and so a third registry added later does
    not silently fold into whichever slice it lands in.
    """
    at = text.index(f"static func {func}(")
    start = text.index("[", text.index("{", at))
    depth, i = 0, start
    while i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    raise ValueError(f"{func}() has no closing bracket")


#: A registry key: a quoted name followed by the dictionary's colon. Deliberately
#: anchored on the colon — the English warning strings beside the keys
#: (`"⚠️ nothing is bound — ⌘⌃B…"`) are arguments to `warn`, are followed by `)`,
#: and must not be read as entries.
KEY = re.compile(r'"([A-Za-z_]\w*)"\s*:')


def registry_names(text: str) -> tuple[set[str], set[str]]:
    """`(actions, guards)` implemented in `GestureActions.swift`."""
    return (set(KEY.findall(_dictionary_literal(text, "actions"))),
            set(KEY.findall(_dictionary_literal(text, "guards"))))


def compare(puml: str, swift: str) -> dict[str, set[str]]:
    """The four ways the two files can disagree."""
    d_actions, d_guards = diagram_names(puml)
    r_actions, r_guards = registry_names(swift)
    return {
        "missing actions": d_actions - r_actions,
        "missing guards": d_guards - r_guards,
        "dead actions": r_actions - d_actions,
        "dead guards": r_guards - d_guards,
    }


DIAGRAM_ACTIONS, DIAGRAM_GUARDS = diagram_names(PUML.read_text())
REGISTRY_ACTIONS, REGISTRY_GUARDS = registry_names(ACTIONS_SWIFT.read_text())


class TheDiagramIsAnswered(unittest.TestCase):
    """Nothing the diagram asks for is missing from the registry."""

    def test_every_action_the_diagram_names_is_implemented(self):
        missing = DIAGRAM_ACTIONS - REGISTRY_ACTIONS
        self.assertFalse(missing, f"docs/gestures.puml names {sorted(missing)}, "
                                  f"which GestureActions.actions() does not implement — "
                                  f"the machine refuses the whole diagram at launch")

    def test_every_guard_the_diagram_names_is_implemented(self):
        missing = DIAGRAM_GUARDS - REGISTRY_GUARDS
        self.assertFalse(missing, f"docs/gestures.puml names guard(s) {sorted(missing)}, "
                                  f"which GestureActions.guards() does not implement")


class TheRegistryIsAllUsed(unittest.TestCase):
    """And nothing in the registry is unreachable. No exemption list."""

    def test_no_action_is_dead_code(self):
        """An action no transition fires is a vocabulary entry that is not one.

        This is the direction the compiler and the launch check both miss. A
        rename that left the old key behind lands here and nowhere else.
        """
        dead = REGISTRY_ACTIONS - DIAGRAM_ACTIONS
        self.assertFalse(dead, f"GestureActions.actions() implements {sorted(dead)}, "
                               f"which no transition in docs/gestures.puml references. "
                               f"Delete it, or give it an arrow — there is no "
                               f"exemption list on purpose")

    def test_no_guard_is_dead_code(self):
        dead = REGISTRY_GUARDS - DIAGRAM_GUARDS
        self.assertFalse(dead, f"GestureActions.guards() implements {sorted(dead)}, "
                               f"which no transition in docs/gestures.puml asks for")


def self_test() -> int:
    """**Prove both directions can fail**, on a pair deliberately broken each way.

    A guard nobody has watched fail is a guard nobody knows the shape of — and
    this one has two shapes, so both are watched. The first fixture renames an
    action in the diagram only (the registry now has an orphan *and* the diagram
    an unanswered name); the second adds a registry entry no arrow mentions,
    which is the failure that has no other witness anywhere in the build.
    """
    puml, swift = PUML.read_text(), ACTIONS_SWIFT.read_text()

    if not DIAGRAM_ACTIONS or not REGISTRY_ACTIONS:
        print("✗ nothing parsed — see the exit-2 rule", file=sys.stderr)
        return 2

    victim = sorted(DIAGRAM_ACTIONS & REGISTRY_ACTIONS)[0]
    broken = compare(puml.replace(f"/ {victim}", f"/ {victim}Renamed"), swift)
    if f"{victim}Renamed" not in broken["missing actions"]:
        print(f"✗ the check does NOT notice `{victim}Renamed` missing from the registry",
              file=sys.stderr)
        return 1
    print(f"✓ a diagram naming `{victim}Renamed` is rejected as unimplemented")

    dead_swift = swift.replace('"openDictation":',
                               '"anActionNoArrowFires": { _ in }, \n            "openDictation":')
    broken = compare(puml, dead_swift)
    if "anActionNoArrowFires" not in broken["dead actions"]:
        print("✗ the check does NOT notice a registry entry no transition references — "
              "which is the direction nothing else in the build is watching",
              file=sys.stderr)
        return 1
    print("✓ a registry entry no arrow fires is rejected as dead code")

    still = {k: v for k, v in compare(puml, swift).items() if v}
    if still:
        print(f"✗ …and the real pair does not agree: {still}", file=sys.stderr)
        return 1
    print("✓ and the checked-in pair agrees in both directions")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    if not DIAGRAM_ACTIONS or not REGISTRY_ACTIONS:
        print(f"✗ parsed {len(DIAGRAM_ACTIONS)} action(s) out of {PUML.name} and "
              f"{len(REGISTRY_ACTIONS)} out of {ACTIONS_SWIFT.name} — one of the two "
              f"parsers has stopped matching, which is not the same as a clean tree",
              file=sys.stderr)
        return 2

    if "--list" in argv:
        names = sorted(DIAGRAM_ACTIONS | REGISTRY_ACTIONS)
        print(f"{len(names)} action name(s) — `puml` names it, `swift` implements it")
        for name in names:
            mark = ("puml " if name in DIAGRAM_ACTIONS else "     ") + \
                   ("swift" if name in REGISTRY_ACTIONS else "     ")
            print(f"  {mark}  {name}")
        print(f"\nguards")
        for name in sorted(DIAGRAM_GUARDS | REGISTRY_GUARDS):
            mark = ("puml " if name in DIAGRAM_GUARDS else "     ") + \
                   ("swift" if name in REGISTRY_GUARDS else "     ")
            print(f"  {mark}  {name}")
        return 0

    result = unittest.main(argv=[argv[0] if argv else sys.argv[0]],
                           exit=False, verbosity=2).result
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
