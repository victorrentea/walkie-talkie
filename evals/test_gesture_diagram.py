#!/usr/bin/env python3
"""**The diagram is the program, so a diagram that will not load is a mouse that
does nothing.**

`docs/gestures.puml` is not documentation of the gesture vocabulary. It *is* the
gesture vocabulary: `GestureDiagram.swift` parses it at launch and
`GestureMachine.swift` executes it. That buys the thing twenty scattered booleans
could never give — one place to read *what does 🔼 → do while unbound* — and it
buys one new way to fail that a Swift table did not have: **the program is now a
text file that can be edited into something that does not parse, or that names an
action nothing implements, and neither is a compile error.**

So this file asks the three questions the compiler no longer asks:

1. **Does the checked-in diagram load, whole?** `GestureMachine.init` resolves
   every action and guard name eagerly and refuses the diagram entirely if one
   is missing — a partial diagram would answer some gestures and silently drop
   others, which is worse than answering none. `--simulate-gestures` exits 1 on
   exactly that refusal, so a rename in `GestureActions.swift` that forgot the
   diagram (or the reverse) fails here rather than at four in the afternoon with
   his hand on the mouse.
2. **Does PlantUML accept it?** The app's parser is deliberately more forgiving
   than PlantUML about decoration, so a file can execute perfectly and still not
   render. A vocabulary that cannot be drawn cannot be reviewed, and reviewing it
   is the entire justification for keeping it in this format.
3. **Is the committed picture the picture of this file?** This is the one that
   rots quietly. `docs/gestures.svg` is what a reader trusts; a stale one is
   worse than no picture at all, because it is confidently wrong. The same
   discipline `docs/overlay-states.html` carries, enforced the same way: re-render
   into a temp directory and byte-compare.

Note `@startuml gestures` — PlantUML names the output after the *diagram*, not
after the input file, so the render lands at `gestures.svg` whatever the .puml is
called. That is why the diff compares `gestures.svg` and not `<stem>.svg`.

    evals/test_gesture_diagram.py              # all three
    evals/test_gesture_diagram.py --list       # …and print what was parsed
    evals/test_gesture_diagram.py --self-test  # prove it rejects a broken diagram

Exit 0 when clean, 1 when a check fails, 2 when the scan itself broke — a .puml
that yields no states and no transitions means this file's own reading of it has
stopped matching, and a parser that has stopped matching must not read as a clean
tree.
"""

from __future__ import annotations

import filecmp
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUML = ROOT / "docs" / "gestures.puml"
SVG = ROOT / "docs" / "gestures.svg"
BINARY = ROOT / ".build" / "debug" / "WalkieTalkie"

#: Lines the app's own parser treats as decoration. Kept in step with
#: `GestureDiagram.ignoredPrefixes` — this file only has to be good enough to
#: answer *did anything match at all*.
IGNORED = ("@startuml", "@enduml", "skinparam", "hide", "show", "title", "legend",
           "scale", "left to right", "top to bottom", "!", "caption", "header",
           "footer", "note ", "end note", "[*]")


def scan(text: str) -> tuple[list[str], list[str]]:
    """`(states, transition lines)` — a deliberately shallow read of the .puml.

    Not a second parser: the real one is in Swift and is exercised by running the
    binary. This exists so *nothing matched* is distinguishable from *everything
    passed*, which is the only way the exit-2 rule can be honest.
    """
    states: list[str] = []
    transitions: list[str] = []
    depth = 0
    for raw in text.splitlines():
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
        if s == "}":
            continue
        if s.startswith("state "):
            body = s[len("state "):].strip().rstrip("{").strip()
            if "<<" in body:
                body = body[:body.index("<<")].strip()
            if body:
                states.append(body.split()[0])
            continue
        if "-->" in s or "->" in s:
            transitions.append(s)
        elif ":" in s:
            transitions.append(s)
    return states, transitions


def simulate(script: dict, puml: Path | None = None, home: str | None = None):
    """Run the headless machine. `(returncode, parsed answer or None)`.

    `--simulate-gestures` exits before AppKit and before `SingleInstance`, so
    this never disturbs the installed relay — it can run with Victor bound to a
    terminal and mid-sentence.
    """
    env = dict(os.environ)
    if puml is not None:
        env["WT_GESTURES_PUML"] = str(puml)
    args = [str(BINARY)]
    if home is not None:
        # `--home` must precede `--simulate-gestures`: the flag loop exits inside
        # the simulate case. It keeps a fixture out of `gestures.last-good.puml`,
        # which the installed app falls back to.
        args += ["--home", home]
    args.append("--simulate-gestures")
    run = subprocess.run(args, input=json.dumps(script), capture_output=True,
                         text=True, env=env, cwd=str(ROOT))
    try:
        return run.returncode, json.loads(run.stdout)
    except json.JSONDecodeError:
        return run.returncode, None


class TheDiagramLoads(unittest.TestCase):
    """Every action and guard name in the diagram resolves in the registry."""

    def setUp(self):
        if not BINARY.exists():
            self.skipTest("no ./.build/debug/WalkieTalkie — run `swift build` first")

    def test_the_checked_in_diagram_runs_a_gesture(self):
        """A trivial script through the real diagram, and `ok` means *all* of it.

        `GestureMachine.init` resolves the whole registry before the machine is
        usable, so `ok: true` here is the assertion that no name in
        `docs/gestures.puml` is missing from `GestureActions.swift`.
        """
        code, answer = simulate({"world": {"bound": False},
                                 "steps": [{"fire": "forward-click", "atMs": 0}]})
        self.assertIsNotNone(answer, "the simulator printed nothing parseable")
        self.assertTrue(answer.get("ok"), answer.get("error"))
        self.assertEqual(code, 0)

    def test_it_is_the_repo_diagram_that_was_loaded(self):
        """A green run against `gestures.last-good.puml` would prove nothing.

        `loadDiagram` falls back to the last diagram that worked when the file on
        disk will not parse. That is right for the app — a typo should cost a
        warning, not the afternoon — and it is exactly what would let this test
        pass over a broken checked-in file, so `origin` is asserted.
        """
        code, answer = simulate({"steps": []})
        self.assertEqual(code, 0)
        self.assertEqual(answer["origin"], str(PUML))


class PlantUMLAcceptsIt(unittest.TestCase):
    """The app's parser is more forgiving than the renderer. Ask the renderer."""

    def setUp(self):
        if shutil.which("plantuml") is None:
            self.skipTest("plantuml is not installed — brew install plantuml")

    def test_checkonly(self):
        run = subprocess.run(["plantuml", "-checkonly", str(PUML)],
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 0,
                         f"plantuml refuses the diagram:\n{run.stdout}{run.stderr}")


class ThePictureIsOfThisFile(unittest.TestCase):
    """Re-render and byte-compare. A stale picture is confidently wrong."""

    def setUp(self):
        if shutil.which("plantuml") is None:
            self.skipTest("plantuml is not installed — brew install plantuml")
        if not SVG.exists():
            self.fail(f"{SVG} is missing — run ./docs/build-gestures.sh")

    def test_the_svg_is_a_render_of_the_current_puml(self):
        """Byte-for-byte, with the same flags `docs/build-gestures.sh` uses.

        `@startuml gestures` names the output after the diagram, so the render is
        `gestures.svg` regardless of the input file's name.
        """
        with tempfile.TemporaryDirectory() as tmp:
            run = subprocess.run(
                ["plantuml", "-tsvg", "-nometadata", "-o", tmp, str(PUML)],
                capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            fresh = Path(tmp) / "gestures.svg"
            self.assertTrue(fresh.exists(),
                            f"plantuml wrote no gestures.svg — it wrote "
                            f"{sorted(p.name for p in Path(tmp).iterdir())}")
            self.assertTrue(
                filecmp.cmp(fresh, SVG, shallow=False),
                "docs/gestures.svg is not a render of docs/gestures.puml — "
                "the picture a reader trusts disagrees with the program that "
                "runs. Run ./docs/build-gestures.sh and commit the result; "
                "never hand-edit the SVG.")


def self_test() -> int:
    """**Prove the check can fail**, on a diagram that names an action nothing
    implements.

    A guard nobody has watched fail is a guard nobody knows the shape of. The
    fixture is the real diagram with `openDictation` renamed — the exact shape of
    a rename in `GestureActions.swift` that forgot the .puml — and the machine
    must refuse it whole rather than answer the other gestures and drop that one.
    """
    if not BINARY.exists():
        print("✗ no ./.build/debug/WalkieTalkie — run `swift build` first", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "unresolvable.puml"
        bad.write_text(PUML.read_text().replace("openDictation", "openDictationX"))
        code, answer = simulate({"steps": [{"fire": "forward-click"}]},
                                puml=bad, home=str(Path(tmp) / "home"))
        if code != 1 or (answer or {}).get("ok") is not False:
            print(f"✗ a diagram naming `openDictationX` was ACCEPTED (exit {code}) — "
                  f"the load check proves nothing", file=sys.stderr)
            return 1
        print(f"✓ a diagram naming an unimplemented action is refused: "
              f"{answer.get('error')}")

    code, answer = simulate({"steps": [{"fire": "forward-click"}]})
    if code != 0:
        print(f"✗ …and the checked-in diagram is refused too (exit {code}): "
              f"{(answer or {}).get('error')}", file=sys.stderr)
        return 1
    print("✓ and accepts docs/gestures.puml")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    states, transitions = scan(PUML.read_text())
    if not states or not transitions:
        print(f"✗ {PUML} yielded {len(states)} states and {len(transitions)} "
              f"transition lines — this file's reading of the diagram has stopped "
              f"matching, which is not the same as a clean tree", file=sys.stderr)
        return 2

    if "--list" in argv:
        print(f"{PUML.relative_to(ROOT)} — {len(states)} states, "
              f"{len(transitions)} transition/description lines")
        for name in states:
            print(f"  state  {name}")
        for line in transitions:
            print(f"  line   {line}")
        print(f"\nplantuml: {shutil.which('plantuml') or 'NOT INSTALLED'}")
        print(f"binary:   {BINARY if BINARY.exists() else 'NOT BUILT — swift build'}")
        return 0

    result = unittest.main(argv=[argv[0] if argv else sys.argv[0]],
                           exit=False, verbosity=2).result
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
