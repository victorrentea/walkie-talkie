#!/usr/bin/env python3
"""**Nothing this app draws may end up inside a picture it takes.**

Victor, 2026-09-14: *"Atunci când faci poză la ecran în timpul dictării, în poză
să nu apară decorațiunile puse de … Walkie-Talkie. Cercul de fulgere, săgețile
verticale sau bila galbenă care crește, bum, efectul de tap."* — the lightning
ring (`CaretHalo`), the marching arrow (`DropArrow`) and the tap ripple
(`CaptureFlash` → `CaptureEffects.tapRipple`).

They already are out of the picture, and that was re-measured the day he asked:

* every window this process owns reports `kCGWindowSharingState == 0` except its
  own menu bar strips, which are AppKit's;
* a panel put up beside them with `sharingType = .readOnly` **does** come back in
  the frame, and the same panel with `.none` does not (`screencapture -x -D`,
  both displays, macOS 15.7) — so the mechanism is honoured on this Mac and it is
  the mechanism doing the work, not luck;
* two real mid-dictation frames (13 and 14 Sep, taken with the halo riding every
  dictation since 2026-09-11) have no gold annulus at the recorded pointer.

So the fix he asked for — take the decorations down for the length of the
shutter and put them back — would buy nothing and cost something: the shutter's
own confirmation is drawn *at* the moment of the capture, and a decoration
blinking off around every frame is a flicker in front of a man mid-sentence.
What the request is really about is that the guarantee must not quietly lapse,
and a guarantee nobody can see is one that lapses silently. Hence a test.

**The rule this enforces**, stated so a reader can argue with it: *every window
this app puts on the screen sets `sharingType`, and the value mentions `.none`.*
A ternary is allowed — `CaretHalo` and `DropArrow` become capturable for a demo
(`WT_HALO_DEMO`) and `RelayWindow` for `RELAY_CAPTURABLE`, none of which is a
path a dictation can take — but a window with no `sharingType` line at all is a
decoration one screenshot away from being in Victor's prompt.

What it cannot check: what any *other* app draws on his screen. Victor Addons and
Victor Effects set no sharing type anywhere, so their overlays — the hands-off
🔒 corners, the amber frame, a banner, an effect playing from the tablet — do
land in these frames. That is deliberate there (an effect nobody can screen-share
is an effect that is not on the projector) and is not this repo's to change.

    ./evals/test_capture_decorations.py              # check the tree
    ./evals/test_capture_decorations.py --self-test  # prove it can fail
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"

# `let panel = NSPanel(`, `p = RelayPanel(`, `host = RelayPanel(` — every shape
# the tree actually uses, matched on the constructor rather than the variable so
# a rename cannot make a window invisible to this test.
CREATION = re.compile(r"=\s*(NSPanel|RelayPanel|NSWindow)\s*\(")
# The assignment, whatever the receiver is called. Its value is read **with the
# line after it**: the chip's is a ternary broken over two lines, and a value cut
# at the newline reads as a bare `ProcessInfo…environment[…] == "1"`.
SHARING = re.compile(r"\.sharingType\s*=\s*(.+)")


def check(path: Path) -> list[str]:
    """Count the windows a file makes against the `sharingType` lines it sets.

    Per file rather than per constructor because the tree splits the two idioms:
    `CaretHalo` configures its panel where it builds it, `RelayWindow` builds it
    in `init` and configures it in `configurePanel()` fifty lines away. A window
    added without its line moves the two counts apart either way, which is the
    thing worth catching; pinning it to the constructor would only have made the
    test argue about where a property is allowed to be set.
    """
    lines = [line for line in path.read_text().splitlines()
             if not line.lstrip().startswith("//")]
    made = [i for i, line in enumerate(lines) if CREATION.search(line)]
    if not made:
        return []
    assignments = [" ".join(lines[i : i + 2]).split("sharingType =", 1)[1].strip()
                   for i, line in enumerate(lines) if SHARING.search(line)]
    hidden = [value for value in assignments if ".none" in value]
    problems = []
    if len(hidden) < len(made):
        problems.append(
            f"{path.name} — {len(made)} window(s) made, {len(hidden)} hidden from screenshots"
            + (f"; `sharingType` says {assignments}" if assignments else "; no `sharingType` at all"))
    return problems


def scan(root: Path) -> list[str]:
    problems = []
    for path in sorted(root.glob("*.swift")):
        problems += check(path)
    return problems


def self_test() -> int:
    import tempfile

    bad = """
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.level = .floating
        panel.orderFrontRegardless()
    """
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "Leak.swift"
        path.write_text(bad)
        found = check(path)
        if len(found) != 1 or "0 hidden" not in found[0]:
            print("self-test FAILED — a bare panel is not caught")
            return 1
        # …and a second panel added beside a hidden one is caught too, which is
        # the way this actually goes wrong: a file that already sets the line
        # once and grows a window that does not.
        path.write_text(bad + "\n        panel.sharingType = .none\n" + bad)
        found = check(path)
    if len(found) != 1 or "2 window(s) made, 1 hidden" not in found[0]:
        print("self-test FAILED — a second unhidden panel is not caught")
        return 1
    print("self-test ok — a panel with no `sharingType` is caught, alone or beside a hidden one")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    problems = scan(SOURCES)
    if problems:
        print("Windows that could end up inside a screenshot:")
        for problem in problems:
            print(f"  ✗ {problem}")
        return 1
    print("✓ every window in Sources/WalkieTalkie sets `sharingType` to `.none`")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
