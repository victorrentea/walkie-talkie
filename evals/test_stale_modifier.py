#!/usr/bin/env python3
"""**Every poster that stamps a modifier must put it back down.**

The rule is `area-crop.md`'s, and it has been paid for four times:

1. **2026-09-10 — `TerminalBinding.tap(key:command:)`.** Every Replace Wispr
   dictation, every ⌘⌃P and every blind paste left `0x00100000` in the session's
   modifier state. Found because a wheel drag silently refused to select an area
   straight after a caret dictation had pasted.
2. **2026-09-13 — `HotkeyTap.postGesture`.** `POST /test/gesture` posted
   `⌃⌥⌘F-key` down and up and nothing else, so every *wait for a bare wire* loop
   behind it ran to its 200 ms ceiling — and Wispr's Scratchpad chord went out as
   `⌃⌥⌘F18`, which it does not have bound, so it ran an ordinary dictation and
   pasted instead.
3. **2026-09-13 — `HotkeyTap.postScratchpad`.** Posted immediately rather than
   onto a bare wire, which is the same bug seen from the other end.
4. **2026-09-14 — `KeySimulator.simulateKeyPress`** (the ⌘C selection probe).
   The `keyUp` carried `.maskCommand` and nothing followed it, so after every
   probe the session believed ⌘ was held. The window server merges live modifier
   state back into a posted key, so letters arriving afterwards were delivered as
   **⌘ + letter** — against TextEdit, `q z j k w y v` are *quit*, *close the
   document*, *undo* and four edits.

Each time the symptom was something else failing, never the poster, and each time
it self-healed on Victor's next real keystroke — which is why nobody reported it
and why it had to be rediscovered. So it is a test rather than a paragraph.

**The rule this enforces**, stated so a reader can argue with it: *a function that
posts a key event with a modifier flag on it must also post a `flagsChanged` in
the same function, or address its events to a process with `postToPid`.* The
first puts the session's state back; the second never touches it.

    evals/test_stale_modifier.py            # scan HEAD's working tree
    evals/test_stale_modifier.py --list     # …and print every poster found
    evals/test_stale_modifier.py --self-test  # prove it fails on the 4th bug

Exit 0 when clean, 1 when a poster is dirty, 2 when the scan itself broke (no
posters found at all means the parser has stopped matching, which must not read
as a pass).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"

#: A non-empty `flags` assigned to an event that is about to be posted.
#:
#: Deliberately **not** a search for `.maskCommand` and friends: the fourth
#: occurrence took its flags as a **parameter** (`simulateKeyPress(keyCode:flags:)`)
#: and named no modifier at all, so a scanner looking for the literal would have
#: missed the very bug it was written for. What matters is *this function put
#: something on an event's flags and posted it*.
#: …and a lookahead cannot express "not empty", because the engine simply
#: backtracks the whitespace and tries again — `.flags = []` matched a
#: `(?!\[\])` guard by giving back the space in front of the bracket. So the
#: value is captured and compared, which is shorter to read as well.
ASSIGNS_FLAGS = re.compile(r"\.flags[ \t]*=[ \t]*(\S[^\n]*)", re.MULTILINE)


def stamps_a_modifier(body: str) -> bool:
    """Does this function put something other than nothing on an event's flags."""
    return any(value.strip().rstrip(";") != "[]" for value in ASSIGNS_FLAGS.findall(body))
#: The function posts key events into the session at all.
POSTS = re.compile(r"\.post\(tap:")
#: The two ways to be clean.
PUTS_BACK = re.compile(r"\.type\s*=\s*\.flagsChanged")
ADDRESSED = re.compile(r"\.postToPid\(")

FUNC = re.compile(r"^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|internal|private|fileprivate)[ \t]+)?"
                  r"(?:static[ \t]+)?(?:@discardableResult[ \t]+)?func[ \t]+(\w+)",
                  re.MULTILINE)


def functions(text: str):
    """Yield `(name, body)` for every `func` in a Swift file, by brace matching.

    Nested `func`s are yielded too and their bodies are contained in the parent's,
    which is what we want: a local `modifier(_:leaving:)` helper putting the flags
    back counts for the function that defines it.
    """
    for match in FUNC.finditer(text):
        brace = text.find("{", match.end())
        if brace < 0:
            continue
        depth, i, n = 0, brace, len(text)
        while i < n:
            c = text[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield match.group(1), text[brace:i + 1]


#: `let up = CGEvent(… keyDown: false)` — the release event, by the name it is
#: bound to.
RELEASE = re.compile(r"let[ \t]+(\w+)[ \t]*=[ \t]*CGEvent\([^)]*keyDown:[ \t]*false", re.DOTALL)
#: What a `flagsChanged` event was created with, so the *virtual key* can be
#: checked — a `flagsChanged` is a modifier transition and carries a modifier's
#: keycode; one carrying the letter being typed is not applied at all.
FLAGS_EVENT = re.compile(r"let[ \t]+(\w+)[ \t]*=[ \t]*CGEvent\([^)]*virtualKey:[ \t]*([A-Za-z0-9_.]+)")
MODIFIER_KEYS = {"VK_COMMAND", "VK_CONTROL", "VK_FN", "VK_OPTION", "VK_SHIFT",
                 "55", "54", "56", "57", "58", "59", "60", "61", "62", "63",
                 "0x37", "0x36", "0x38", "0x3B", "0x3A", "0x3F"}


def release_carries_modifier(body: str) -> str | None:
    """**A key-up that carries a modifier is what leaves the session holding it.**

    `CGEventSource.flagsState` reports whatever the last event's flags said, so a
    release stamped with ⌘ is a keyboard the window server believes is still
    holding ⌘ — regardless of anything posted afterwards. This is the check that
    would have caught the fifth occurrence, where a trailing `flagsChanged` was
    present and the release was still carrying the modifier.
    """
    for match in RELEASE.finditer(body):
        name = match.group(1)
        for value in re.findall(rf"\b{re.escape(name)}\?\.flags[ \t]*=[ \t]*([^\n]+)"
                                rf"|\b{re.escape(name)}\.flags[ \t]*=[ \t]*([^\n]+)", body):
            text = (value[0] or value[1]).strip().rstrip(";")
            if text and text != "[]":
                return f"its key-up carries `{text}`"
    return None


def clearing_event_is_a_modifier(body: str) -> str | None:
    """**A `flagsChanged` must carry a modifier's keycode**, not the typed key's.

    The fifth occurrence posted its clearing event with `virtualKey: keyCode` —
    the **C** of ⌘C. A modifier transition announced on a letter key is not one,
    the window server does not apply it, and the clear silently did nothing.
    """
    named = dict((m.group(1), m.group(2)) for m in FLAGS_EVENT.finditer(body))
    for name, key in named.items():
        if not re.search(rf"\b{re.escape(name)}\.type[ \t]*=[ \t]*\.flagsChanged", body):
            continue
        # **Exactly a modifier constant, or the `key` parameter of the local
        # `modifier(_:leaving:)` helpers.** Deliberately not a prefix match:
        # `keyCode` starts with `key` and is the *letter being typed*, which is
        # how the fifth occurrence slipped past this check on its first draft.
        if key in MODIFIER_KEYS or key == "key":
            return None                      # at least one honest clear
        # A function that announces its transitions through the local
        # `modifier(_:leaving:)` helper is clean by construction — the helper
        # takes the modifier's keycode as its argument. Checked here because a
        # textual scan cannot tell two `let e = …` bindings in one function
        # apart, and `emitScratchpad` has exactly that shadowing.
        if re.search(r"\bmodifier\(", body):
            return None
        return f"its `flagsChanged` carries `{key}`, which is not a modifier key"
    return None


def scan(name: str, text: str):
    """`(posters, offenders)` for one file's source."""
    posters, offenders = [], []
    for func, body in functions(text):
        if not POSTS.search(body) or not stamps_a_modifier(body):
            continue
        why: str | None = None
        if not (PUTS_BACK.search(body) or ADDRESSED.search(body)):
            why = "it never puts the modifier back"
        else:
            # **A key-up carrying a modifier is only survivable when a real
            # modifier transition follows it.** `flagsState` reports the last
            # event's flags, so releasing with ⌘ stamped sets the session to
            # ⌘-down; what rescues it is a `flagsChanged` on a *modifier's*
            # keycode. One announced on the letter being typed is not a modifier
            # transition at all, the window server does not apply it, and the
            # clear silently does nothing — which is the fifth occurrence.
            release = release_carries_modifier(body)
            clearing = clearing_event_is_a_modifier(body)
            if release and clearing:
                why = f"{release}, and {clearing}"
        posters.append((f"{name}.{func}", why is None))
        if why:
            offenders.append(f"{name}.{func} — {why}")
    return posters, offenders


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()

    posters, offenders = [], []
    for path in sorted(SOURCES.glob("*.swift")):
        p, o = scan(path.stem, path.read_text())
        posters += p
        offenders += o

    if "--list" in argv or offenders:
        for func, clean in posters:
            print(f"  {'ok  ' if clean else 'DIRTY'}  {func}")

    if not posters:
        print("✗ no key posters found at all — the scanner has stopped matching, "
              "which is not the same as a clean tree", file=sys.stderr)
        return 2

    if offenders:
        print(f"\n✗ {len(offenders)} poster(s) stamp a modifier and never put it back:",
              file=sys.stderr)
        for func in offenders:
            print(f"    {func}", file=sys.stderr)
        print("\n  Release the modifier with a `flagsChanged` carrying the state the\n"
              "  keyboard is left in, or post to a pid. See area-crop.md, "
              "'The stale-⌘ bug'.", file=sys.stderr)
        return 1

    print(f"✓ {len(posters)} key poster(s), every one of them puts the modifier back")
    return 0


def self_test() -> int:
    """**Prove the test can fail**, against the fourth occurrence itself.

    A guard nobody has watched fail is a guard nobody knows the shape of, so this
    reads `SelectionCapture.swift` as it stood *before* `fc74df6` and asserts that
    the scan rejects it.
    """
    # Two occurrences of the same bug in the same function, four builds apart:
    # `fc74df6~1` posted nothing after the ⌘-stamped key-up at all, and `2cc4ff1`
    # posted a `flagsChanged` announced on the **C** key, which is not a modifier
    # transition and did nothing. The scan must reject both.
    for commit, what in (("fc74df6~1", "stamped ⌘ on a key-up and posted nothing after"),
                         ("2cc4ff1", "cleared the flags on the typed key, not on a modifier")):
        before = subprocess.run(
            ["git", "show", f"{commit}:Sources/WalkieTalkie/SelectionCapture.swift"],
            cwd=SOURCES.parent.parent, capture_output=True, text=True)
        if before.returncode != 0:
            print(f"✗ cannot read {commit}: {before.stderr.strip()}", file=sys.stderr)
            return 2
        _, offenders = scan("SelectionCapture", before.stdout)
        if not any(o.startswith("SelectionCapture.simulateKeyPress") for o in offenders):
            print(f"✗ the scan does NOT reject {commit}, where `simulateKeyPress` {what}",
                  file=sys.stderr)
            return 1
        print(f"✓ the scan rejects `simulateKeyPress` at {commit} — it {what}")

    _, still = scan("SelectionCapture",
                    (SOURCES / "SelectionCapture.swift").read_text())
    if still:
        print(f"✗ …and still rejects it at HEAD: {still}", file=sys.stderr)
        return 1
    print("✓ and accepts it at HEAD")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
