#!/usr/bin/env python3
"""**`Active Terminals` is the spawn menu's first row, and it is never hidden.**

Victor, 2026-09-23: *"In the project pop-up … when I open a new terminal, I
want the first option to be a menu that says 'Recent', or 'Active Terminals',
and then when I hover over it, a submenu opens that lets me bind this prompt to
that terminal."*

`SpawnFolderMenu.build` lays the menu out **bottom-up** (Cocoa's y grows
upwards), so *first on screen* means *last row added*. This test parses the
Swift source and holds it to that, plus the three things the feature's promises
rest on:

* `build` adds `addActiveRow` after every other row, the header and the line —
  and unconditionally, at the function's own indentation, so an empty list
  cannot take the row away (the empty state is `ActiveTerminals.emptyLabel`,
  drawn dimmed: a row that comes and goes moves every folder under it);
* `ActiveRow.draw` says `emptyLabel` when there is nothing to offer;
* a submenu pick (`choice.tty`) goes to `redirectSpawn`, never to a spawn;
* `commit` holds a sentence while a pick is still binding
  (`spawnPickInFlight`), so the words cannot reach the terminal bound before.

The listing itself (sessions → rows, disambiguation, tick) is a pure function
with its own `swift test` (`ActiveTerminalsTests`).

    ./evals/test_active_terminals.py              # check the tree
    ./evals/test_active_terminals.py --self-test  # prove it can fail
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"


def function_body(text: str, signature: str) -> list[str]:
    """The raw lines of one Swift function, from its signature to its closing brace."""
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if signature in l), None)
    if start is None:
        return []
    depth, body = 0, []
    for line in lines[start:]:
        body.append(line)
        depth += line.count("{") - line.count("}")
        if depth == 0 and len(body) > 1:
            break
    return body


def code(lines: list[str]) -> list[str]:
    return [l for l in lines if l.strip() and not l.lstrip().startswith("//")]


def check(menu: str, delegate: str) -> list[str]:
    problems = []

    build = code(function_body(menu, "private static func build(size: NSSize) -> NSView"))
    if not build:
        return ["`SpawnFolderMenu.build(size:)` is gone"]
    adds = [(i, l) for i, l in enumerate(build)
            if re.search(r"\b(add|addHeader|addSeparator|addActiveRow)\(", l)]
    if not adds or "addActiveRow(" not in adds[-1][1]:
        problems.append("`addActiveRow` is not the last row `build` adds — bottom-up, "
                        "that means *Active Terminals* is not the first row on screen")
    active = [l for l in build if "addActiveRow(" in l]
    if len(active) != 1:
        problems.append(f"`build` adds *Active Terminals* {len(active)} times, expected once")
    else:
        indent = len(active[0]) - len(active[0].lstrip())
        body_indent = min(len(l) - len(l.lstrip()) for l in build[1:-1])
        bare = re.match(r"\s*(_|y) = addActiveRow\(", active[0])
        if indent != body_indent or not bare:
            problems.append("`addActiveRow` is conditional in `build` — the row must be drawn "
                            "even with nothing behind it (dimmed, `emptyLabel`), never hidden")
    if not any("addHeader(header" in l for _, l in adds):
        problems.append("the `Start Claude in…` header is gone from `build`")

    draw = " ".join(code(function_body(menu.split("final class ActiveRow")[-1],
                                       "override func draw(_ dirtyRect: NSRect)")))
    if "ActiveTerminals.emptyLabel" not in draw:
        problems.append("`ActiveRow.draw` no longer says `ActiveTerminals.emptyLabel` "
                        "when there is nothing to offer")

    offer = " ".join(code(function_body(delegate, "private func offerSpawnFolders()")))
    if not re.search(r"if let tty = choice\.tty \{\s*self\.redirectSpawn\(toTTY: tty\)", offer):
        problems.append("a submenu pick no longer goes to `redirectSpawn(toTTY:)`")
    if "self.spawnPending else { return }" not in offer:
        problems.append("a late pick (after the words were sent) is no longer refused")

    commit = " ".join(code(function_body(delegate, "private func commit(_ m: Message)")))
    if not re.search(r"!isBound \|\| spawnPickInFlight != nil", commit):
        problems.append("`commit` does not hold the sentence while an *Active Terminals* "
                        "pick is still binding — the words could reach the old terminal")
    return problems


def main() -> int:
    menu = (SOURCES / "SpawnFolderMenu.swift").read_text()
    delegate = (SOURCES / "AppDelegate.swift").read_text()
    if "--self-test" in sys.argv:
        broken = menu.replace("        _ = addActiveRow(at: y, size: size, to: root)\n", "", 1)
        broken = broken.replace("        var y = pad\n",
                                "        var y = pad\n        y = addActiveRow(at: y, size: size, to: root)\n", 1)
        hidden = menu.replace("        _ = addActiveRow(at: y, size: size, to: root)\n",
                              "        if active?.isEmpty == false { _ = addActiveRow(at: y, size: size, to: root) }\n", 1)
        leaky = delegate.replace("!isBound || spawnPickInFlight != nil", "!isBound", 1)
        cases = {"row moved to the bottom": (broken, delegate),
                 "row hidden when empty": (hidden, delegate),
                 "no hold during the pick": (menu, leaky)}
        ok = True
        for name, (m, d) in cases.items():
            found = check(m, d)
            print(f"{'caught' if found else 'MISSED'}: {name}" + (f" — {found[0]}" if found else ""))
            ok &= bool(found)
        clean = check(menu, delegate)
        print("tree: " + ("clean" if not clean else f"{len(clean)} problem(s)"))
        return 0 if ok and not clean else 1
    problems = check(menu, delegate)
    for p in problems:
        print(f"FAIL: {p}")
    if not problems:
        print("ok: Active Terminals is the first row, drawn even when empty, and its pick binds")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
