#!/usr/bin/env python3
"""**What each side-button gesture does, as a table, checked against the source.**

Victor, 2026-09-23 (dictated):

    "The forward click should be transcribing, basically prompting, at the caret.
     There will be those metadata, the screenshot of the screen, the fact that is
     dictated, and any other feature, including prompting and picking pictures
     for an agent. Clicking the back button on the mouse starts a plain voice
     transcription with no sorts of prompting tweaks around it. It should be just
     clean voice that I had. The bound dictation is activated by forward click and
     moving the mouse to the right. Forward click and moving the mouse upwards
     starts a terminal in a new session."

    "If during a plain transcription … the back button ends it, there is no
     screenshot in a clean dictation. Enter is dispatched if I do a back click
     and move the mouse to my right."

    "Make the dictation [at the caret]. Hit Enter to trigger … if I am putting my
     [caret] into a Claude Code terminal prompt, it should already submit the
     prompt as it's actually a prompt."

The gesture map has been rewritten five times in two weeks and every rewrite
left a path behind that still did the previous thing (the back click that was
still a shutter, the forward click that still went to the bound terminal). So
the spec is a table here, and every row is checked against **the real Swift**:
the `case VK_Fn:` branch in `HotkeyTap.handle`, the `AppDelegate` callback it
raises, and the delivery that callback ends in. A row passes only if the chain
does what the row says.

    evals/test_gesture_spec.py              # check the tree
    evals/test_gesture_spec.py --self-test  # break each rule, prove it is caught

Exit 0 when every row holds, 1 when one does not (the message names the row, the
file and what to edit), 2 when the parser cannot find a branch at all — a test
that has stopped matching must not read as a pass.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SOURCES = Path(__file__).resolve().parent.parent / "Sources" / "WalkieTalkie"
FILES = ("HotkeyTap.swift", "AppDelegate.swift", "TerminalBinding.swift")


class ParseError(Exception):
    pass


# ── Extraction ─────────────────────────────────────────────────────────────

def _strip_comments(text: str) -> str:
    return "\n".join(line for line in text.splitlines()
                     if not line.lstrip().startswith("//"))


def _braced(text: str, start: int) -> str:
    """The body of the `{ … }` block whose opening brace is at or after `start`."""
    open_at = text.index("{", start)
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_at + 1:i]
    raise ParseError(f"unbalanced braces from offset {start}")


def gesture_case(src: dict, key: str) -> str:
    """`case VK_F7:` … up to the next `case VK_` / `default:` of the Logi switch."""
    text = _strip_comments(src["HotkeyTap.swift"])
    m = re.search(rf"^\s*case {key}:\s*$", text, re.MULTILINE)
    if not m:
        raise ParseError(f"no `case {key}:` in HotkeyTap.swift")
    end = re.search(r"^\s*(case VK_F\d+:|default:)", text[m.end():], re.MULTILINE)
    return text[m.end(): m.end() + (end.start() if end else len(text))]


def function(src: dict, file: str, name: str) -> str:
    text = _strip_comments(src[file])
    m = re.search(rf"func {re.escape(name)}\(", text)
    if not m:
        raise ParseError(f"no `func {name}(` in {file}")
    return _braced(text, m.end())


def closure(src: dict, assignment: str) -> str:
    """`hotkeys.onPasteToggle = { … }` in AppDelegate."""
    text = _strip_comments(src["AppDelegate.swift"])
    i = text.find(assignment + " = {")
    if i < 0:
        raise ParseError(f"no `{assignment} = {{` in AppDelegate.swift")
    return _braced(text, i)


def has(body: str, pattern: str) -> bool:
    return re.search(pattern, body, re.DOTALL) is not None


def before(body: str, first: str, then: str) -> bool:
    a, b = re.search(first, body, re.DOTALL), re.search(then, body, re.DOTALL)
    return bool(a and b and a.start() < b.start())


# ── The spec ───────────────────────────────────────────────────────────────
#
# (button, gesture) → destination · enrichment · submit, and the checks that
# make it true. Each check is (what it asserts, where to edit, predicate).

def spec(src: dict):
    ad = "AppDelegate.swift"
    return [
        {
            "row": ("🔼 forward", "click"),
            "does": "caret · PROMPT (context shot, [Dictated…], attachments) · Enter iff Claude Code prompt",
            "checks": [
                ("F7 raises onPasteToggle", "HotkeyTap `case VK_F7`",
                 lambda: has(gesture_case(src, "VK_F7"), r"onPasteToggle\?\(\)")),
                ("onPasteToggle starts a caret dictation", "AppDelegate `hotkeys.onPasteToggle`",
                 lambda: has(closure(src, "hotkeys.onPasteToggle"), r"startDictation\(paste: true\)")),
                ("startDictation(paste:) marks the sentence a caret PROMPT", "AppDelegate `startDictation`",
                 lambda: has(function(src, ad, "startDictation"), r"caretPrompt = paste")),
                ("the prompt takes the context shot at the press", "AppDelegate `dictationBegan`",
                 lambda: has(function(src, ad, "dictationBegan"),
                             r"if !cleanSentence, caretPrompt \|\|[^\n]*\{\s*if contextAtWheelRelease.*?captureContext\(\)")),
                ("the prompt's words are the full envelope", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"caretLine\(words: result\.text, full: prompt\)")),
                ("the full envelope is terminalLine (screen + [Dictated…])", "AppDelegate `caretLine`",
                 lambda: has(function(src, ad, "caretLine"),
                             r"if full \{.*?screen: screen.*?return Self\.terminalLine\(m\)")),
                ("terminalLine carries [Dictated in RO or EN]", "AppDelegate `terminalLine`",
                 lambda: has(function(src, ad, "terminalLine"), r"dictatedHint\(\)")),
                ("the prompt is delivered through the Claude Code check", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"if prompt \{\s*deliverCaretPrompt\(")),
                ("…which submits only into a detected Claude Code prompt, else pastes", "AppDelegate `deliverCaretPrompt`",
                 lambda: has(function(src, ad, "deliverCaretPrompt"),
                             r"frontClaudePromptTTY.*?submitPrompt.*?guard submitted.*?pasteText\(line")),
                ("detection: Terminal.app, a non-shell in front, a live Claude Code session file",
                 "TerminalBinding `frontClaudePromptTTY`",
                 lambda: all(has(function(src, "TerminalBinding.swift", "frontClaudePromptTTY"), p)
                             for p in (r'"com\.apple\.Terminal"', r"!isShell\(", r"publishedDirectory\(onTTY:"))),
                ("submitting is the bound terminal's own write (text + Return + review Return)",
                 "TerminalBinding `submitPrompt`",
                 lambda: has(function(src, "TerminalBinding.swift", "submitPrompt"), r"writeToTerminalApp\(")),
            ],
        },
        {
            "row": ("🔼 forward", "drag right"),
            "does": "BOUND terminal · prompt (the ⌘⌃D toggle)",
            "checks": [
                ("F10 raises onLocalToggle", "HotkeyTap `case VK_F10`",
                 lambda: has(gesture_case(src, "VK_F10"), r"onLocalToggle\?\(\)")),
                ("onLocalToggle is toggleDictation — no paste, no spawn", "AppDelegate `hotkeys.onLocalToggle`",
                 lambda: has(closure(src, "hotkeys.onLocalToggle"), r"toggleDictation\(\)")),
            ],
        },
        {
            "row": ("🔼 forward", "drag up"),
            "does": "NEW terminal + session · prompt",
            "checks": [
                ("F8 raises onGestureSpawn", "HotkeyTap `case VK_F8`",
                 lambda: has(gesture_case(src, "VK_F8"), r"onGestureSpawn\?\(\)")),
                ("onGestureSpawn starts a spawn dictation", "AppDelegate `hotkeys.onGestureSpawn`",
                 lambda: has(closure(src, "hotkeys.onGestureSpawn"), r"startDictation\(spawn: true\)")),
            ],
        },
        {
            "row": ("🔽 back", "click"),
            "does": "caret, even when bound · CLEAN (words only) · no Enter",
            "checks": [
                ("F6 posts Wispr's toggle and arms the back click", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"postWisprHandsFree\(\).*?setWisprArm\(closing \? 0 : CACurrentMediaTime\(\)\)")),
                ("the arm makes the sentence clean and aims it at the caret", "AppDelegate `noteCleanStart`",
                 lambda: has(function(src, ad, "noteCleanStart"),
                             r"hotkeys\.backStopsWispr.*?cleanSentence = true.*?pasteMode = true")),
                ("both Wispr begin callbacks latch it", "AppDelegate `wisprSource.didMaybeBegin` / `didBegin`",
                 lambda: has(closure(src, "wisprSource.didMaybeBegin"), r"noteCleanStart\(\)")
                         and has(closure(src, "wisprSource.didBegin"), r"noteCleanStart\(\)")),
                ("a clean sentence is latched to the caret whatever is bound", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"if pasteMode \|\| clean \{ latchedAtCaret = true \}")),
                ("its words are delivered alone", "AppDelegate `deliver` → `cleanLine`",
                 lambda: has(function(src, ad, "deliver"), r"clean \? cleanLine\(words: result\.text\)")
                         and has(function(src, ad, "cleanLine"), r"return words\s*$")),
                ("no marker splicing (a highlight inlined into the words)", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"result\.text = clean \? spokenText :")),
                ("no kamikaze word", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"if clean \{ kamikaze = false \}")),
                ("no Return unless 🔽 → asked for it", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"let submitClean = clean && submitAfterClean")),
            ],
        },
        {
            # Victor, 2026-09-25: "changing the transcription engine from wispr to
            # elevenlabs should change it as well for «clean dictation» = back
            # button click."
            "row": ("🔽 back", "click, Engine not Wispr"),
            "does": "the same CLEAN dictation, heard by the Engine (ElevenLabs / local), not Wispr",
            "checks": [
                ("the tap knows which Engine is live", "AppDelegate `wireDictationSource`",
                 lambda: has(function(src, ad, "wireDictationSource"),
                             r"hotkeys\.backUsesOwnEngine = source !== wisprSource")),
                ("F6 toggles the Engine's clean sentence instead of posting Wispr's chord",
                 "HotkeyTap `case VK_F6`",
                 lambda: before(gesture_case(src, "VK_F6"), r"if !wisprSentence, backUsesOwnEngine \{.*?onCleanToggle",
                                r"postWisprHandsFree")),
                ("the toggle starts a clean caret sentence, and stops only a clean one",
                 "AppDelegate `hotkeys.onCleanToggle`",
                 lambda: has(closure(src, "hotkeys.onCleanToggle"),
                             r"if self\.cleanSentence \{ self\.endDictation\(\) \}.*?startDictation\(paste: true, clean: true\)")),
                ("startDictation(clean:) makes it clean, not a caret prompt", "AppDelegate `startDictation`",
                 lambda: has(function(src, ad, "startDictation"),
                             r"caretPrompt = paste && !clean.*?cleanSentence = clean")),
                ("🔽 → stops it and submits", "HotkeyTap `case VK_F5`",
                 lambda: has(gesture_case(src, "VK_F5"),
                             r"if ownDictation, ownCleanSentence, !backStopsWispr \{.*?onBackSubmit\?\(\).*?onCleanToggle\?\(\)")),
            ],
        },
        {
            "row": ("🔽 back", "click during a plain dictation"),
            "does": "STOP it — never a shutter",
            "checks": [
                ("the stop is decided before the shutter", "HotkeyTap `case VK_F6`",
                 lambda: before(gesture_case(src, "VK_F6"), r"let wisprSentence = backStopsWispr",
                                r"onScreenshot")),
                ("a Wispr sentence is excluded from the shutter branch", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"), r"if !wisprSentence, !ownClean, dictating, ownDictation")),
                ("a clean sentence on the relay's own engine is excluded too", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"let ownClean = !wisprSentence && ownDictation && ownCleanSentence")),
            ],
        },
        {
            "row": ("🔽 back", "plain dictation, any moment"),
            "does": "NO screenshot — not at the start, not during, not at the end",
            "checks": [
                ("no context shot at the start", "AppDelegate `dictationBegan`",
                 lambda: has(function(src, ad, "dictationBegan"), r"if !cleanSentence, caretPrompt")),
                ("captureContext refuses while a clean sentence is open", "AppDelegate `captureContext`",
                 lambda: has(function(src, ad, "captureContext"), r"if hotkeys\.cleanSentenceOpen \{.*?return")),
                ("the ⌃⌥P shutter refuses too", "AppDelegate `plusOneShot`",
                 lambda: has(function(src, ad, "plusOneShot"), r"if hotkeys\.cleanSentenceOpen \{.*?return")),
                ("…whichever engine hears it (Wispr's arm, or the relay's own clean sentence)",
                 "HotkeyTap `cleanSentenceOpen`",
                 lambda: has(src["HotkeyTap.swift"],
                             r"var cleanSentenceOpen: Bool \{.*?ownDictationFlag && ownCleanSentenceFlag.*?own \|\| backStopsWispr")),
                ("no highlight probe either", "AppDelegate `dictationBegan`",
                 lambda: has(function(src, ad, "dictationBegan"), r"if !cleanSentence \{ probeRecentSelection\(\) \}")),
            ],
        },
        {
            "row": ("🔽 back", "drag right during a plain dictation"),
            "does": "STOP it, insert the clean words, then Enter",
            "checks": [
                ("F5 stops a plain sentence with the back click's own chord, before any Return",
                 "HotkeyTap `case VK_F5`",
                 lambda: before(gesture_case(src, "VK_F5"), r"if backStopsWispr \|\|.*?postWisprHandsFree\(\)",
                                r"Self\.postReturn\(\)")),
                ("…and asks for the Return after the words", "HotkeyTap `case VK_F5`",
                 lambda: has(gesture_case(src, "VK_F5"), r"onBackSubmit\?\(\).*?return nil")),
                ("the request is recorded for this sentence", "AppDelegate `hotkeys.onBackSubmit`",
                 lambda: has(closure(src, "hotkeys.onBackSubmit"), r"submitAfterClean = true")),
                ("the Return follows the paste", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"),
                             r"pasteText\(line, to: result\.focusPid\)\s*if submitClean \{ submitAfterCleanWords\(\) \}")),
                ("…and is this app's stamped Return", "AppDelegate `submitAfterCleanWords`",
                 lambda: has(function(src, ad, "submitAfterCleanWords"), r"HotkeyTap\.postReturn\(\)")),
            ],
        },
        {
            "row": ("🔽 back", "drag right, no plain dictation"),
            "does": "Return, and nothing else",
            "checks": [
                ("F5 falls through to postReturn", "HotkeyTap `case VK_F5`",
                 lambda: has(gesture_case(src, "VK_F5"), r"Self\.postReturn\(\)\s*return nil")),
            ],
        },
    ]


# ── Running ────────────────────────────────────────────────────────────────

def load() -> dict:
    return {name: (SOURCES / name).read_text() for name in FILES}


def run(src: dict, quiet: bool = False) -> tuple[int, list[str]]:
    failures: list[str] = []
    for row in spec(src):
        button, gesture = row["row"]
        for what, where, check in row["checks"]:
            try:
                ok = check()
            except ParseError as e:
                if not quiet:
                    print(f"✗ parser: {e}")
                return 2, [str(e)]
            if not ok:
                failures.append(f"{button} {gesture} — {what}  (edit: {where})")
        if not quiet:
            print(f"{'✓' if not any(f.startswith(f'{button} {gesture} ') for f in failures) else '✗'} "
                  f"{button:10} {gesture:38} → {row['does']}")
    return (1 if failures else 0), failures


def main(argv: list[str]) -> int:
    if "--self-test" in argv:
        return self_test()
    code, failures = run(load())
    if failures:
        print("\nThe gesture spec (2026-09-23) no longer holds:")
        for f in failures:
            print(f"  ✗ {f}")
    return code


# Each mutation is one rule broken the way it is most likely to break: the
# previous behaviour coming back.
MUTATIONS = [
    ("forward click back to the old caret envelope", "AppDelegate.swift",
     "caretLine(words: result.text, full: prompt)", "caretLine(words: result.text)"),
    ("forward click skips the context shot again", "AppDelegate.swift",
     "if !cleanSentence, caretPrompt || (!pasteMode && (isBound || spawnPending)) {",
     "if !pasteMode, isBound || spawnPending {"),
    ("forward click goes to the bound terminal", "HotkeyTap.swift",
     "a dictation at the caret\")\n                DispatchQueue.global().async { [weak self] in self?.onPasteToggle?() }",
     "a dictation at the caret\")\n                DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }"),
    ("Enter pressed without the Claude Code session check", "TerminalBinding.swift",
     "guard publishedDirectory(onTTY: device) != nil else { return nil }", ""),
    ("plain text follows the binding again", "AppDelegate.swift",
     "if pasteMode || clean { latchedAtCaret = true }", "if pasteMode { latchedAtCaret = true }"),
    ("plain text carries the attachments", "AppDelegate.swift",
     "clean ? cleanLine(words: result.text)", "clean ? caretLine(words: result.text)"),
    ("plain dictation takes a ⌃⌥P picture", "AppDelegate.swift",
     "        if hotkeys.backStopsWispr {\n            Log.info(\"📸 refused", "        if false {\n            Log.info(\"📸 refused"),
    ("back click is a shutter before it is a stop", "HotkeyTap.swift",
     "if !wisprSentence, dictating, ownDictation {", "if dictating, ownDictation {"),
    ("back + right is only Return again", "HotkeyTap.swift",
     "DispatchQueue.global().async { [weak self] in self?.onBackSubmit?() }", ""),
    ("plain dictation gets the kamikaze word", "AppDelegate.swift",
     "if clean { kamikaze = false }", ""),
]


def self_test() -> int:
    base = load()
    code, failures = run(base, quiet=True)
    if code != 0:
        print("self-test FAILED — the tree itself does not pass, so a mutation proves nothing:")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    missed = []
    for name, file, old, new in MUTATIONS:
        if old not in base[file]:
            print(f"self-test FAILED — mutation '{name}' no longer applies (text not found in {file})")
            return 1
        src = dict(base)
        src[file] = base[file].replace(old, new, 1)
        code, _ = run(src, quiet=True)
        print(f"{'✓' if code != 0 else '✗'} caught: {name}")
        if code == 0:
            missed.append(name)
    if missed:
        print(f"self-test FAILED — {len(missed)} mutation(s) not caught")
        return 1
    print(f"self-test ok — all {len(MUTATIONS)} broken rules are caught")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
