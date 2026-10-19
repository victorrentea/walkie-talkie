#!/usr/bin/env python3
"""**One engine for every way to dictate, checked against the source.**

Victor, 2026-10-06 (dictated):

    "There are four ways to dictate, right? Bound, at caret, in a new terminal
     or clean dictation. I just started a new prompt for a new terminal, and what
     was used was the local model. The model that is used for transcribing should
     be the same for all four, always. Make sure in the code that this never
     drifts again."

That sentence went local because Wispr Flow was still finishing the take the
relay had handed to this Mac six seconds before, and ignored the start chord —
not because the new-session gesture picked another engine. The guarantee is
structural, and this file pins it:

1. Every gesture opens the microphone through `AppDelegate.startDictation`, and
   that function is the only caller of `source.start()` — one variable, one call.
2. No source is ever started by name (`wisprSource.start()` …): that would be a
   gesture choosing its own engine.
3. The engine is only ever swapped for a sentence by `borrowEngine`, and only
   for the hard failures listed in `BORROWS` — each one inside the shared start
   path or the right ⌘⌥ hold's pre-step, never in a gesture's own branch. A new
   borrow has to be added here, with its reason, or this fails.

Run: `python3 evals/test_one_engine.py` (exit 1 on a drift).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"

# The only reasons a sentence may run on another engine than the Engine row's.
BORROWS = {
    "right ⌘⌥ held on Engine = Wispr (Q21": "Wispr has no right ⌘⌥ + F19 hands-free shortcut",
    "Wispr Flow \\(down) — auto fallback": "Wispr Flow is not running or still starting",
    "Wispr Flow is still finishing row": "Wispr Flow is still on the take handed to this Mac",
    "Wispr Flow needs the internet": "no internet — Wispr transcribes in the cloud (2026-10-19)",
}


def functions(text: str) -> list[tuple[str, int, int]]:
    """(name, start, end) of every `func` in a Swift file, by brace matching."""
    out = []
    for m in re.finditer(r"\bfunc\s+(\w+)", text):
        i = text.find("{", m.end())
        if i < 0:
            continue
        depth, j = 0, i
        while j < len(text):
            c = text[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append((m.group(1), m.start(), j))
    return out


def enclosing(text: str, pos: int) -> str | None:
    best = None
    for name, a, b in functions(text):
        if a <= pos <= b and (best is None or a > best[1]):
            best = (name, a)
    return best[0] if best else None


def main(argv: list[str]) -> int:
    failures: list[str] = []
    app = (SOURCES / "AppDelegate.swift").read_text()

    starts = [m.start() for m in re.finditer(r"\bsource\.start\(\)", app)]
    if len(starts) != 1:
        failures.append(f"AppDelegate calls source.start() {len(starts)} times — it must be once, in startDictation")
    for p in starts:
        f = enclosing(app, p)
        if f != "startDictation":
            failures.append(f"source.start() is called from {f}, not startDictation")

    for path in sorted(SOURCES.glob("*.swift")):
        for m in re.finditer(r"\b(wisprSource|whisperSource|elevenSource|elevenLiveSource)\.start\(", path.read_text()):
            failures.append(f"{path.name}: {m.group(0)} — a source started by name picks its own engine")

    for m in re.finditer(r"borrowEngine\(\s*self\.whisperSource|borrowEngine\(\s*whisperSource|borrowEngine\(\s*(?!_)\w", app):
        line = app[m.start(): app.find("\n", m.start())]
        reason = next((k for k in BORROWS if k in line), None)
        if reason is None:
            failures.append(f"an unlisted engine borrow: {line.strip()}")
            continue
        f = enclosing(app, m.start())
        if f not in ("startDictation", "installHotkeys", "setupHotkeys") and "Q21" not in reason:
            failures.append(f"the borrow '{reason}' is in {f}, outside the shared start path")

    for f in failures:
        print("✗", f)
    if not failures:
        print(f"✓ one engine: source.start() once, in startDictation; {len(BORROWS)} listed hard-failure borrows")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
