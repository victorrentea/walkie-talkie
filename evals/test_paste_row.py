#!/usr/bin/env python3
"""**The `⌘⇧P` reminder is an ordinary chip row, drawn like `☠️ Kamikaze`.**

Victor, 2026-09-23: *"It looks like now it has a border around it, with a
different font, which is wrong. I just want you to display yet another row in
the mouse tooltip. Technically, it's just like, for example, transcribing
Kamikaze … It should have the icon of the paste … the text should say 'Paste
again', and then the shortcuts, just like any text in the tooltip."*

Until that afternoon `PasteHint` drew its own window (`KeycapView`: a white
rounded outline round `⌘⇧P`, 15 pt medium). The row that replaced it is
`RelayWindow.pasteRow`, and this test keeps it the Kamikaze row's twin:

* both are built by the one constructor, `installEmojiRow` (face, size, ink,
  glyph), and the paste one says `📋` / `Paste again` / `PasteHint.keys`;
* **every other line that touches a Kamikaze view has a paste twin** — the
  layout through `layoutGlyphRow`, the height, the width, the halo and the
  white ink on the bare chip, the plain ink off it. That is the list a new row
  keeps getting left off (`overlay-chip.md`: three rows already), so it is
  checked mechanically rather than by eye;
* `PasteHint.swift` draws nothing: no window, no outline, no font of its own.

    ./evals/test_paste_row.py              # check the tree
    ./evals/test_paste_row.py --self-test  # prove it can fail
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"

KAMIKAZE_VIEW = re.compile(r"\bkamikaze(Row|Glyph|Info)\b")
# Lines that are about Kamikaze itself rather than about how a row is drawn.
KAMIKAZE_ONLY = ("labelWithString", "private let kamikaze", "installEmojiRow(kamikaze")
# What the old keycap window was made of. None of it may come back in PasteHint.
DRAWING = re.compile(r"\b(NSPanel|RelayPanel|NSWindow|NSBezierPath|KeycapView|NSFont\.|"
                     r"override func draw|\.stroke\(|orderFront|alphaValue)\b")


def code_lines(text: str) -> list[str]:
    return [" ".join(line.split()) for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("//")]


def check(relay: str, hint: str) -> list[str]:
    problems = []
    lines = code_lines(relay)
    body = set(lines)

    if not any(re.search(r'installEmojiRow\(kamikazeRow, glyph: kamikazeGlyph, '
                         r'label: kamikazeInfo, emoji: "☠️"\)', l) for l in lines):
        problems.append("the Kamikaze row is no longer built by `installEmojiRow` — "
                        "the reference the paste row is compared to has moved")
    if not any(re.search(r'installEmojiRow\(pasteRow, glyph: pasteGlyph, '
                         r'label: pasteInfo, emoji: "📋"\)', l) for l in lines):
        problems.append("the paste row is not built by `installEmojiRow(…, emoji: \"📋\")`")
    if not any('pasteInfo = NSTextField(labelWithString: "Paste again' in l
               and "PasteHint.keys" in l for l in lines):
        problems.append("the paste row does not say `Paste again` + `PasteHint.keys`")

    install = [l for l in lines if l.startswith("private func installEmojiRow")]
    if not install:
        problems.append("`installEmojiRow` is gone")
    else:
        start = lines.index(install[0])
        block = " ".join(lines[start:start + 12])
        for must in ("label.font = hintFont", "Glyphs.emoji(emoji, ink: iconInk)",
                     "label.textColor = .secondaryLabelColor"):
            if must not in block:
                problems.append(f"`installEmojiRow` no longer does `{must}`")

    twins = 0
    for line in lines:
        if not KAMIKAZE_VIEW.search(line) or any(k in line for k in KAMIKAZE_ONLY):
            continue
        if re.search(r"\bpaste(Row|Glyph|Info)\b", line):
            continue  # one line serving both rows is the same code path by construction
        twin = (line.replace("kamikazeRow", "pasteRow").replace("kamikazeGlyph", "pasteGlyph")
                    .replace("kamikazeInfo", "pasteInfo"))
        twins += 1
        if twin not in body:
            problems.append(f"the Kamikaze row does `{line}` and the paste row has no `{twin}`")
    if twins < 8:
        problems.append(f"only {twins} Kamikaze row lines found — the comparison has lost its reference")

    for line in code_lines(hint):
        if DRAWING.search(line):
            problems.append(f"PasteHint.swift draws something of its own again: `{line}`")
    if not any("setPasteHint(true)" in l for l in code_lines(hint)):
        problems.append("PasteHint no longer puts the chip's row up (`setPasteHint(true)`)")
    return problems


def self_test() -> int:
    relay = (SOURCES / "RelayWindow.swift").read_text()
    hint = (SOURCES / "PasteHint.swift").read_text()
    cases = {
        "the halo left off the paste row":
            (relay.replace("pasteInfo.shadow = Self.halo()", "", 1), hint),
        "a font of its own on the paste row":
            (relay.replace('installEmojiRow(pasteRow, glyph: pasteGlyph, label: pasteInfo, emoji: "📋")',
                           "pasteInfo.font = NSFont.systemFont(ofSize: 15, weight: .medium)"), hint),
        "the paste row laid out another way":
            (relay.replace("layoutGlyphRow(pasteRow, glyph: pasteGlyph, label: pasteInfo, width: innerWidth)",
                           "pasteRow.frame.size = NSSize(width: innerWidth, height: 30)"), hint),
        "a keycap window back in PasteHint":
            (relay, hint + "\nlet p = RelayPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)\n"),
    }
    for name, (r, h) in cases.items():
        if not check(r, h):
            print(f"self-test FAILED — {name} is not caught")
            return 1
    print(f"self-test ok — {len(cases)} mutations caught")
    return 0


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    problems = check((SOURCES / "RelayWindow.swift").read_text(),
                     (SOURCES / "PasteHint.swift").read_text())
    if problems:
        print("The paste row is not drawn like the Kamikaze row:")
        for problem in problems:
            print(f"  ✗ {problem}")
        return 1
    print("✓ `📋 Paste again ⌘⇧P` is built, laid out and inked exactly like `☠️ Kamikaze`")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
