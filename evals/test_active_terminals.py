#!/usr/bin/env python3
"""**`✨ Workspace` is the spawn menu's last row, never hidden, and it holds every
session no pinned row claims.**

`Active terminals` was the last row from 2026-11-03 (the first since 2026-09-23)
and is gone since 2026-11-20 (Victor: *"vreau să se distrugă aia cu Active
Terminals sub meniu. N-are sens. Totul ar trebui să fie sub workspace"*).

`SpawnFolderMenu.build` lays the menu out **bottom-up** (Cocoa's y grows
upwards), so *last on screen* means *first row added*. This test parses the
Swift source and holds it to that, plus the things the feature's promises
rest on:

* `build` adds `addWorkspaceRow` before every other row and the header —
  unconditionally, at the function's own indentation (its empty state is
  `workspaceEmptyLabel`, drawn dimmed);
* `addActiveRow` is gone, and `regroup` hands the leftovers to Workspace
  (`grouped(…, rest: workspacePath)`);
* a session pick (`choice.tty`) goes to `redirectSpawn`, never to a spawn;
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
            if re.search(r"\b(add|addHeader|addSeparator|addActiveRow|addWorkspaceRow)\(", l)]
    if not adds or "addWorkspaceRow(" not in adds[0][1]:
        problems.append("`addWorkspaceRow` is not the first row `build` adds — bottom-up, "
                        "that means *✨ Workspace* is not the last row on screen")
    if "addActiveRow(" in menu:
        problems.append("*Active terminals* is back (`addActiveRow`) — it went on 2026-11-20")
    ws = [l for l in build if "addWorkspaceRow(" in l]
    if len(ws) != 1:
        problems.append(f"`build` adds *Workspace* {len(ws)} times, expected once")
    else:
        indent = len(ws[0]) - len(ws[0].lstrip())
        body_indent = min(len(l) - len(l.lstrip()) for l in build[1:-1])
        bare = re.match(r"\s*(_|y) = addWorkspaceRow\(", ws[0])
        if indent != body_indent or not bare:
            problems.append("`addWorkspaceRow` is conditional in `build` — the row must be drawn "
                            "even with nothing behind it (dimmed), never hidden")
    regroup = " ".join(code(function_body(menu, "private static func regroup()")))
    if "rest: workspacePath" not in regroup:
        problems.append("`regroup` no longer hands the sessions no pinned row claims to *Workspace*")
    if not any("addHeader(header" in l for _, l in adds):
        problems.append("the `Start Claude in…` header is gone from `build`")

    offer = " ".join(code(function_body(delegate, "private func offerSpawnFolders()")))
    if not re.search(r"if let tty = choice\.tty \{\s*self\.redirectSpawn\(toTTY: tty\)", offer):
        problems.append("a submenu pick no longer goes to `redirectSpawn(toTTY:)`")
    if "self.spawnPending else { return }" not in offer:
        problems.append("a late pick (after the words were sent) is no longer refused")

    commit = " ".join(code(function_body(delegate, "private func commit(_ m: Message)")))
    if not re.search(r"!isBound \|\| spawnPickInFlight != nil", commit):
        problems.append("`commit` does not hold the sentence while a session "
                        "pick is still binding — the words could reach the old terminal")
    return problems


def main() -> int:
    menu = (SOURCES / "SpawnFolderMenu.swift").read_text()
    delegate = (SOURCES / "AppDelegate.swift").read_text()
    if "--self-test" in sys.argv:
        broken = menu.replace("        y = addWorkspaceRow(at: y, size: size, to: root)\n", "", 1)
        broken = broken.replace("        _ = addHeader(header, at: y, size: size, to: root)\n",
                                "        y = addHeader(header, at: y, size: size, to: root)\n"
                                "        _ = addWorkspaceRow(at: y, size: size, to: root)\n", 1)
        hidden = menu.replace("        y = addWorkspaceRow(at: y, size: size, to: root)\n",
                              "        if workspace?.isEmpty == false { y = addWorkspaceRow(at: y, size: size, to: root) }\n", 1)
        back = menu.replace("        y = addWorkspaceRow(at: y, size: size, to: root)\n",
                            "        y = addActiveRow(at: y, size: size, to: root)\n"
                            "        y = addWorkspaceRow(at: y, size: size, to: root)\n", 1)
        orphans = menu.replace("rest: workspacePath", "rest: nil", 1)
        leaky = delegate.replace("!isBound || spawnPickInFlight != nil", "!isBound", 1)
        cases = {"row moved to the top": (broken, delegate),
                 "row hidden when empty": (hidden, delegate),
                 "Active terminals back": (back, delegate),
                 "leftovers not under Workspace": (orphans, delegate),
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
        print("ok: ✨ Workspace is the last row, holds the leftover sessions, and a session pick binds")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
