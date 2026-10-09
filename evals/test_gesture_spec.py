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

Victor, 2026-09-28 (dictated) — the back button's two gestures swapped back,
superseding the 09-23 swap (268b111) for 🔽 and 🔽 →:

    "The plain transcription, the simple dictation with no prompting, should be
     started on the gesture with back key and move the mouse to the right, not
     just by pressing back key. The back key should result in an Enter key being
     pressed, unless I'm doing a dictation of a prompt, in which case it results
     in a screenshot being taken."

Victor, 2026-10-05 (dictated) — the bare click starts the plain dictation too,
and every plain dictation ends in a Return:

    "butonul de back de pe mouse, gestul de back simplu, ar trebui să pornească
     dictarea curată. Nu doar gestul de back cu swipe la dreapta … Iar după ce
     inserezi textul, să pui un Enter întotdeauna."

Victor, 2026-10-07 (dictated) — only the bare click's stop submits:

    "when I dictate cleanly with back mouse and swipe to right, that shortcut
     should just insert the text, not hit the enter. The same with the back mouse
     and drag the mouse down at the same time. … However, the normal back should
     insert dictation and hit enter."

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
FILES = ("HotkeyTap.swift", "AppDelegate.swift", "TerminalBinding.swift", "WisprFlowSource.swift")


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


def plain_toggle(src: dict) -> str:
    """`HotkeyTap.plainToggle` — 🔽 →'s body, and the bare 🔽's at rest."""
    return function(src, "HotkeyTap.swift", "plainToggle")


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
                 lambda: has(closure(src, "hotkeys.onPasteToggle"), r"forwardClickToggle\(\)")
                 and has(function(src, "AppDelegate.swift", "forwardClickToggle"), r"startDictation\(paste: true\)")),
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
                 # `claudePromptOn(tty:)` holds the second half since 64943b8.
                 lambda: all(has(function(src, "TerminalBinding.swift", "frontClaudePromptTTY")
                                 + function(src, "TerminalBinding.swift", "claudePromptOn"), p)
                             for p in (r'"com\.apple\.Terminal"', r"!(isShell|refusesDelivery)\(", r"publishedDirectory\(onTTY:"))),
                ("submitting is the bound terminal's own write (text + Return + review Return)",
                 "TerminalBinding `submitPrompt`",
                 lambda: has(function(src, "TerminalBinding.swift", "submitPrompt"), r"writeToTerminalApp\(")),
            ],
        },
        {
            "row": ("🔼 forward", "drag right"),
            "does": "BOUND terminal · prompt; mid-sentence flips bound ⇄ caret (2026-10-05)",
            "checks": [
                ("F10 raises onForwardRight", "HotkeyTap `case VK_F10`",
                 lambda: has(gesture_case(src, "VK_F10"), r"onForwardRight\?\(\)")),
                ("onForwardRight is toggleDictation with the flip — no paste, no spawn", "AppDelegate `hotkeys.onForwardRight`",
                 lambda: has(closure(src, "hotkeys.onForwardRight"), r"toggleDictation\(flipsDestination: true\)")),
                ("⌘⌃D keeps its stop: onLocalToggle never flips", "AppDelegate `hotkeys.onLocalToggle`",
                 lambda: has(closure(src, "hotkeys.onLocalToggle"), r"toggleDictation\(\)")),
                ("a bound sentence goes to the caret, the caret one back", "AppDelegate `toggleDictation`",
                 lambda: all(has(function(src, ad, "toggleDictation"), p)
                             for p in (r"if flipsDestination, !pasteMode, !spawnPending, isBound \{\s*aimAtCaret\(\)",
                                       r"if pasteMode, isBound \{\s*aimAtBoundTerminal\(\)"))),
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
            "row": ("🔽 back", "drag right, nothing open"),
            "does": "caret, even when bound · CLEAN (words only) · Enter only at its stop",
            "checks": [
                ("F5 is the plain toggle", "HotkeyTap `case VK_F5`",
                 lambda: has(gesture_case(src, "VK_F5"), r"return plainToggle\(gesture, type, event\)")),
                ("the toggle posts Wispr's toggle and arms the plain sentence", "HotkeyTap `plainToggle`",
                 lambda: has(plain_toggle(src),
                             r"setWisprArm\(CACurrentMediaTime\(\)\)\s*Self\.postWisprHandsFree\(\)")),
                ("the toggle never presses Return itself, never takes a picture", "HotkeyTap `plainToggle`",
                 lambda: not has(plain_toggle(src), r"postReturn|onScreenshot")),
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
                ("no Return unless 🔽 asked for it", "AppDelegate `deliver`",
                 lambda: has(function(src, ad, "deliver"), r"let submitClean = clean && submitAfterClean")),
            ],
        },
        {
            # Victor, 2026-09-25: "changing the transcription engine from wispr to
            # elevenlabs should change it as well for «clean dictation»" — the
            # gesture is 🔽 → since 2026-09-28.
            "row": ("🔽 back", "drag right, Engine not Wispr"),
            "does": "the same CLEAN dictation, heard by the Engine (ElevenLabs / local), not Wispr",
            "checks": [
                ("the tap knows which Engine is live", "AppDelegate `wireDictationSource`",
                 lambda: has(function(src, ad, "wireDictationSource"),
                             r"hotkeys\.backUsesOwnEngine = source !== wisprSource")),
                ("the toggle starts the Engine's clean sentence instead of posting Wispr's chord",
                 "HotkeyTap `plainToggle`",
                 lambda: before(plain_toggle(src), r"if !wisprSentence, backUsesOwnEngine \{.*?onCleanToggle",
                                r"postWisprHandsFree")),
                ("the toggle starts a clean caret sentence, and stops only a clean one",
                 "AppDelegate `hotkeys.onCleanToggle`",
                 lambda: has(closure(src, "hotkeys.onCleanToggle"),
                             r"if self\.cleanSentence \{ self\.endDictation\(\) \}.*?startDictation\(paste: true, clean: true\)")),
                ("startDictation(clean:) makes it clean, not a caret prompt", "AppDelegate `startDictation`",
                 lambda: has(function(src, ad, "startDictation"),
                             r"caretPrompt = paste && !clean.*?cleanSentence = clean")),
                ("🔽 stops it and submits", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"if ownClean \{\s*if ownMicOpen \{.*?onBackSubmit\?\(\).*?onCleanToggle\?\(\)")),
            ],
        },
        {
            # Victor, 2026-09-25: "If I hold down the right command and the right
            # option, that should enable the clean dictation for as long as I hold
            # the two buttons."
            "row": ("⌘⌥ right", "held, whatever the Engine (Q9 step 2, 2026-09-28)"),
            "does": "the same CLEAN dictation for as long as the pair is held",
            "checks": [
                ("the pair goes to onCleanHold whatever the Engine, and is never swallowed",
                 "HotkeyTap flagsChanged branch",
                 lambda: has(_strip_comments(src["HotkeyTap.swift"]),
                             r"if !ownPost, pair != cleanPairDown \{.*?if pair \|\| was \{.*?onCleanHold\?\(pair \? \.press : \.release\).*?return Unmanaged\.passUnretained\(event\)")),
                ("the press starts a clean caret sentence", "AppDelegate `hotkeys.onCleanHold`",
                 lambda: has(closure(src, "hotkeys.onCleanHold"), r"case \.press:.*?startDictation\(paste: true, clean: true\)")),
                ("the release ends it", "AppDelegate `hotkeys.onCleanHold`",
                 lambda: has(closure(src, "hotkeys.onCleanHold"), r"case \.release, \.shortcut:.*?self\.endDictation\(\)")),
                ("a key under the pair throws it away", "HotkeyTap keyDown under the pair",
                 lambda: has(_strip_comments(src["HotkeyTap.swift"]),
                             r"if type == \.keyDown, enginePairHeld,.*?onCleanHold\?\(\.shortcut\)")),
                ("a Wispr ⌘V with no capture is never rescued into delivery (Q9 step 2, W17)", "WisprFlowSource `injected`",
                 lambda: not has(_strip_comments(function(src, "WisprFlowSource.swift", "injected")), r"rescueFromRow\(")),
            ],
        },
        {
            # Victor, 2026-10-05: "gestul de back simplu, ar trebui să pornească
            # dictarea curată" — Return at rest from 2026-09-28 until then.
            "row": ("🔽 back", "click, nothing open"),
            "does": "START the plain dictation — 🔽 →'s own toggle, no Return",
            "checks": [
                ("F6 falls through to the plain toggle", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"), r"return plainToggle\(gesture, type, event\)\s*$")),
                ("…and never presses Return at rest", "HotkeyTap `case VK_F6`",
                 lambda: not has(gesture_case(src, "VK_F6"), r"postReturn")),
            ],
        },
        {
            "row": ("🔽 back", "click while a prompt is dictating"),
            "does": "the SHUTTER — a picture, no Return",
            "checks": [
                ("F6 takes the picture while the relay's own prompt records", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"if !wisprSentence, !ownClean, dictating, ownDictation \{.*?onScreenshot\?\(cursor\).*?return swallow\(")),
                ("a prompt still in flight is refused, not given a Return", "HotkeyTap `case VK_F6`",
                 lambda: before(gesture_case(src, "VK_F6"), r"if ownDictation \{\s*refuseBackClick\(\)",
                                r"plainToggle\(")),
            ],
        },
        {
            "row": ("🔽 back", "click during a plain dictation"),
            "does": "STOP it, insert the clean words, then Enter — never a shutter",
            "checks": [
                ("the plain sentence is decided before the shutter", "HotkeyTap `case VK_F6`",
                 lambda: before(gesture_case(src, "VK_F6"), r"let wisprSentence = !promoted && \(backStopsWispr",
                                r"onScreenshot")),
                ("a Wispr sentence is excluded from the shutter branch", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"), r"if !wisprSentence, !ownClean, dictating, ownDictation")),
                ("a clean sentence on the relay's own engine is excluded too", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"let ownClean = !promoted && !wisprSentence && ownDictation && ownCleanSentence")),
                ("F6 stops a Wispr plain sentence with 🔽 →'s own stop, before the toggle",
                 "HotkeyTap `case VK_F6`",
                 lambda: before(gesture_case(src, "VK_F6"), r"if wisprSentence \{.*?postWisprRawStop\(\)",
                                r"plainToggle\(")),
                ("…and asks for the Return after the words", "HotkeyTap `case VK_F6`",
                 lambda: has(gesture_case(src, "VK_F6"),
                             r"postWisprRawStop\(\)\s*setWisprArm\(0\)\s*DispatchQueue\.global\(\)\.async \{ \[weak self\] in self\?\.onBackSubmit\?\(\) \}\s*return swallow\(")),
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
            # Victor, 2026-10-07: "swipe to right, that shortcut should just
            # insert the text, not hit the enter" — a Return 2026-10-05 → 10-07.
            "row": ("🔽 back", "drag right during a plain dictation"),
            "does": "STOP it, insert the clean words — NO Enter",
            "checks": [
                ("the stop is the same toggle, disarming the sentence", "HotkeyTap `plainToggle`",
                 lambda: has(plain_toggle(src), r"let closing = wisprSentence.*?if closing \{\s*postWisprRawStop\(\)\s*setWisprArm\(0\)")),
                ("…and a stop younger than 2 s is dropped (one slow flick)", "HotkeyTap `plainToggle`",
                 lambda: has(plain_toggle(src), r"lastPlainStartAt < Self\.gestureStopDwellSeconds")),
                ("the Engine's stop is the toggle alone", "HotkeyTap `plainToggle`",
                 lambda: has(plain_toggle(src), r"if !wisprSentence, backUsesOwnEngine \{.*?onCleanToggle\?\(\)")),
                ("no stop in the toggle asks for the Return", "HotkeyTap `plainToggle`",
                 lambda: not has(plain_toggle(src), r"onBackSubmit")),
            ],
        },
        {
            # Victor, 2026-10-07: "The same with the back mouse and drag the mouse
            # down … should just insert the text without hitting the enter."
            "row": ("🔽 back", "drag down during a plain dictation"),
            "does": "STOP it, insert the clean words — NO Enter; otherwise unbind",
            "checks": [
                ("F12 stops an open plain sentence with 🔽 →'s own toggle, before the unbind",
                 "HotkeyTap `case VK_F12`",
                 lambda: before(gesture_case(src, "VK_F12"),
                                r"if wisprSentence \|\| \(ownClean && ownMicOpen\) \{\s*return plainToggle\(gesture, type, event\)",
                                r"onGestureUnbind")),
                ("a plain sentence in flight is not unbound under it", "HotkeyTap `case VK_F12`",
                 lambda: before(gesture_case(src, "VK_F12"), r"if ownClean \{.*?return swallow\(", r"onGestureUnbind")),
                ("F12 never asks for the Return", "HotkeyTap `case VK_F12`",
                 lambda: not has(gesture_case(src, "VK_F12"), r"onBackSubmit|postReturn")),
                ("at rest it is still the unbind", "HotkeyTap `case VK_F12`",
                 lambda: has(gesture_case(src, "VK_F12"), r"onGestureUnbind\?\(\) \}\s*return swallow\(gesture, type, event\)\s*$")),
            ],
        },
        {
            # Victor, 2026-10-07: "the back button moved to the bottom … would open
            # up a very tiny input text right next to the cursor … submitted by
            # hitting enter … inserted into the dictation".
            "row": ("🔽 back", "drag down during a prompt"),
            "does": "open the typing box at the pointer; its text goes into the prompt",
            "checks": [
                ("a prompt on the relay's own engine opens the box, before the unbind",
                 "HotkeyTap `case VK_F12`",
                 lambda: before(gesture_case(src, "VK_F12"),
                                r"if !wisprSentence, ownDictation, ownMicOpen \{.*?onTypeIn\?\(cursor\)",
                                r"onGestureUnbind")),
                ("…and only after the plain sentence's own branches", "HotkeyTap `case VK_F12`",
                 lambda: before(gesture_case(src, "VK_F12"), r"return plainToggle\(", r"onTypeIn")),
            ],
        },
        {
            # Victor, 2026-10-09: "a quick fast mode … that will answer as fast as
            # it can … the key to bind it to. I think forward and left".
            "row": ("🔼 forward", "drag left"),
            "does": "mid-sentence: CANCEL it; at rest: a ⚡ QUICK QUESTION — clean words to the fast model, answer in the reply pop-up",
            "checks": [
                ("F11 raises the cancel, and only the cancel", "HotkeyTap `case VK_F11`",
                 lambda: has(gesture_case(src, "VK_F11"), r"onLocalCancel\?\(\)") and
                         not has(gesture_case(src, "VK_F11"), r"onForwardRight|onPasteToggle|onCleanToggle")),
                ("a cancel comes first; the question only when nothing was cancelled", "AppDelegate `onLocalCancel`",
                 lambda: before(closure(src, "hotkeys.onLocalCancel"),
                                r"if self\.cancelSentenceOrPanel\(.*?\) \{ return \}",
                                r"startDictation\(paste: true, clean: true, quick: true\)")),
                ("…an answer still coming is dropped before a new question opens", "AppDelegate `onLocalCancel`",
                 lambda: before(closure(src, "hotkeys.onLocalCancel"),
                                r"QuickAsk\.shared\.cancel\(\)", r"quick: true")),
                ("the words go to the quick model before any caret or terminal route", "AppDelegate `deliver`",
                 lambda: before(function(src, ad, "deliver"), r"if quick \{.*?askQuick\(result\.text\)",
                                r"if case \.alreadyInserted = result\.delivery")),
            ],
        },
        {
            # Victor, 2026-10-05: "If I do the gesture for back and swipe to the
            # left at any point, this means an Enter." A cancel until then.
            "row": ("🔽 back", "drag left, any moment"),
            "does": "Return — this app's stamped key, ungated, no cancel",
            "checks": [
                ("F3 posts the Return and is swallowed", "HotkeyTap `case VK_F3`",
                 lambda: has(gesture_case(src, "VK_F3"), r"Self\.postReturn\(\)\s*return swallow\(gesture, type, event\)\s*$")),
                ("…and cancels nothing, whatever is dictating", "HotkeyTap `case VK_F3`",
                 lambda: not has(gesture_case(src, "VK_F3"), r"onLocalCancel|postWisprCancel|ownDictation|wisprMicIsOpen")),
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
                 lambda: has(function(src, ad, "plusOneShot"), r"if refusesAttachment\(.*?\) \{ return \}")),
                ("…through the one door every attachment asks", "AppDelegate `refusesAttachment`",
                 lambda: has(function(src, ad, "refusesAttachment"), r"guard hotkeys\.cleanSentenceOpen else \{ return false \}")),
                # 2026-10-08: plain words attach nothing at all, not only pictures.
                ("no crop: the wheel drag does not arm", "HotkeyTap `areaDrag`",
                 lambda: has(src["HotkeyTap.swift"], r"guard dictating, bare, !promptHeld, !leftIsHeld, !rightIsHeld else \{ return false \}\s*(//[^\n]*\s*)*guard !cleanSentenceOpen else \{ return false \}")),
                ("…nor does the area shot", "AppDelegate `areaShot`",
                 lambda: has(function(src, ad, "areaShot"), r"refusesAttachment\(")),
                ("no ⌘⇧ pick, no highlight, no film, no typing box", "AppDelegate `record` / `fileSelection` / `toggleFilm` / `openTypeIn`",
                 lambda: all(has(function(src, ad, f), r"refusesAttachment\(")
                             for f in ("record", "fileSelection", "toggleFilm", "openTypeIn"))),
                ("the picker and the highlight watcher ride `attachable`, not `live`", "AppDelegate `syncBorrowedGestures`",
                 lambda: all(has(function(src, ad, "syncBorrowedGestures"), p)
                             for p in (r"let attachable = live && !hotkeys\.cleanSentenceOpen",
                                       r"picker\.dictating = attachable", r"syncSelectionWatch\(attachable\)"))),
                ("🔼 → / 🔼 ↑ turn it into a prompt: the tap is told", "AppDelegate `syncBorrowedGestures`",
                 lambda: before(function(src, ad, "syncBorrowedGestures"),
                                r"hotkeys\.relayPromptOpen = listening && !\(cleanSentence && !cleanRedirected\)",
                                r"let attachable")),
                ("…and a prompt is no longer clean to the tap", "HotkeyTap `cleanSentenceOpen`",
                 lambda: has(src["HotkeyTap.swift"], r"var cleanSentenceOpen: Bool \{.*?return !prompt && \(own \|\| plain \|\| backStopsWispr\)")),
                ("once attached, 🔼 → back to the caret stays a prompt", "AppDelegate `aimAtCaret`",
                 lambda: has(function(src, ad, "aimAtCaret"),
                             r"if hasAttachments \{.*?cleanSentence = false.*?caretPrompt = true.*?\} else \{\s*cleanRedirected = false")),
                ("…whichever engine hears it (Wispr's arm, or the relay's own clean sentence)",
                 "HotkeyTap `cleanSentenceOpen`",
                 lambda: has(src["HotkeyTap.swift"],
                             r"var cleanSentenceOpen: Bool \{.*?ownDictationFlag && ownCleanSentenceFlag.*?relayPlainOpenFlag.*?own \|\| plain \|\| backStopsWispr")),
                ("no highlight probe either", "AppDelegate `dictationBegan`",
                 lambda: has(function(src, ad, "dictationBegan"), r"if !cleanSentence \{ probeRecentSelection\(\) \}")),
            ],
        },
        {
            # Q10 (2026-09-26): IntelliJ's Step Into / Resume are bare F7 / F9.
            "row": ("⌨️ fn+F7/F9", "keyboard, not a button"),
            "does": "halo style −1/+1 only with the fn key down; bare F7/F9 pass to the front app",
            "checks": [
                ("the halo-step branch requires the tracked fn key", "HotkeyTap `onHaloStep` branch",
                 lambda: has(_strip_comments(src["HotkeyTap.swift"]),
                             r"if \(keyCode == VK_F7 \|\| keyCode == VK_F9\) && fnKeyHeld &&[^\n]*\{.*?onHaloStep\?\(step\)")),
                ("fnKeyHeld follows the fn key's own flagsChanged (keycode 63)", "HotkeyTap `.flagsChanged`",
                 lambda: has(_strip_comments(src["HotkeyTap.swift"]),
                             r"== VK_FUNCTION \{\s*fnKeyHeld = event\.flags\.contains\(\.maskSecondaryFn\)")),
            ],
        },
        {
            # Victor, 2026-09-28: "a local fallback that I can access during the
            # dictation, at any point, through a key combination displayed in the
            # tooltip". ⌘⌃L is Victor Addons' calendar, ⌘⌃W Wispr Flow's paste.
            "row": ("⌨️ ⌘⌃X", "keyboard, while recording or waiting"),
            "does": "the take goes to the local model now (via local-forced); idle: a flash; always swallowed",
            "checks": [
                ("⌘⌃X is swallowed, autorepeat included, and raises onLocalNow", "HotkeyTap keyDown branch",
                 lambda: has(_strip_comments(src["HotkeyTap.swift"]),
                             r"if keyCode == VK_X && cmd && ctrl && !opt \{\s*if event\.getIntegerValueField\(\.keyboardEventAutorepeat\) != 0 \{ return swallow\(.*?onLocalNow\?\(\).*?return swallow\(")),
                ("it is one of the app's own chords while frozen", "HotkeyTap `isOwnChordWhileFrozen`",
                 lambda: has(function(src, "HotkeyTap.swift", "isOwnChordWhileFrozen"), r"code == VK_X")),
                ("onLocalNow runs transcribeLocallyNow", "AppDelegate `hotkeys.onLocalNow`",
                 lambda: has(_strip_comments(src[ad]), r"hotkeys\.onLocalNow = \{[^\n]*transcribeLocallyNow\(")),
                ("…which hands the take to the local model, or flashes at rest", "AppDelegate `transcribeLocallyNow`",
                 lambda: has(function(src, ad, "transcribeLocallyNow"),
                             r"guard a\.available else \{.*?Nothing to transcribe locally.*?source\.handToLocal\(\)")),
                ("the local model's answer says local-forced", "AppDelegate `transcribeLocally`",
                 lambda: has(function(src, ad, "transcribeLocally"), r'via: forced \? \(byClock \? "local-auto" : "local-forced"\)')),
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
        print("\nThe gesture spec (2026-09-23, back button swapped back 2026-09-28, bare click plain 2026-10-05, 🔽 ← Return 2026-10-05, 🔽 → / 🔽 ↓ no Return 2026-10-07) no longer holds:")
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
    ("🔼 → stops a bound sentence again (before 2026-10-05)", "AppDelegate.swift",
     "if flipsDestination, !pasteMode, !spawnPending, isBound {", "if false {"),
    ("⌘⌃D flips the destination too, losing its stop", "AppDelegate.swift",
     "if self.toggleCoalescedByStall() { return }\n                self.toggleDictation()\n",
     "if self.toggleCoalescedByStall() { return }\n                self.toggleDictation(flipsDestination: true)\n"),
    ("Enter pressed without the Claude Code session check", "TerminalBinding.swift",
     "return publishedDirectory(onTTY: (tty as NSString).lastPathComponent) != nil", "return true"),
    ("plain text follows the binding again", "AppDelegate.swift",
     "if pasteMode || clean { latchedAtCaret = true }", "if pasteMode { latchedAtCaret = true }"),
    ("plain text carries the attachments", "AppDelegate.swift",
     "clean ? cleanLine(words: result.text)", "clean ? caretLine(words: result.text)"),
    ("plain dictation takes a ⌃⌥P picture", "AppDelegate.swift",
     "        if refusesAttachment(\"📸 the shutter\") { return }", ""),
    ("plain dictation attaches a highlight (2026-10-08)", "AppDelegate.swift",
     "        if refusesAttachment(\"👁 the highlight\") { return }", ""),
    ("a plain sentence turned prompt still refuses pictures (2026-10-08)", "HotkeyTap.swift",
     "return !prompt && (own || plain || backStopsWispr)", "return own || plain || backStopsWispr"),
    ("a plain Wispr sentence whose arm expired takes pictures again (2026-10-08)", "HotkeyTap.swift",
     "return !prompt && (own || plain || backStopsWispr)", "return !prompt && (own || backStopsWispr)"),
    ("back to the caret drops the attachments with the envelope (2026-10-08)", "AppDelegate.swift",
     "            if hasAttachments {", "            if false {"),
    ("back click is a shutter before it is a stop", "HotkeyTap.swift",
     "if !wisprSentence, !ownClean, dictating, ownDictation {", "if dictating, ownDictation {"),
    ("the back click stops a plain sentence without its Return", "HotkeyTap.swift",
     "                    setWisprArm(0)\n                    DispatchQueue.global().async { [weak self] in self?.onBackSubmit?() }",
     "                    setWisprArm(0)"),
    ("🔽 →'s Wispr stop presses Return again (2026-10-05 → 10-07)", "HotkeyTap.swift",
     "            postWisprRawStop()\n            setWisprArm(0)\n        } else {",
     "            postWisprRawStop()\n            setWisprArm(0)\n            DispatchQueue.global().async { [weak self] in self?.onBackSubmit?() }\n        } else {"),
    ("🔽 →'s Engine stop presses Return again (2026-10-05 → 10-07)", "HotkeyTap.swift",
     "DispatchQueue.global().async { [weak self] in self?.onCleanToggle?() }",
     "DispatchQueue.global().async { [weak self] in if stopping { self?.onBackSubmit?() }; self?.onCleanToggle?() }"),
    ("🔽 ↓ unbinds mid plain dictation (before 2026-10-07)", "HotkeyTap.swift",
     "                if wisprSentence || (ownClean && ownMicOpen) {\n                    return plainToggle(gesture, type, event)\n                }\n",
     ""),
    ("the toggle presses Return at the start", "HotkeyTap.swift",
     "            setWisprArm(CACurrentMediaTime())\n            Self.postWisprHandsFree()\n",
     "            setWisprArm(CACurrentMediaTime())\n            Self.postReturn()\n            Self.postWisprHandsFree()\n"),
    ("the bare back click is Return at rest again (the 09-28 mapping)", "HotkeyTap.swift",
     "                    refuseBackClick()\n                    return swallow(gesture, type, event)\n                }\n                return plainToggle(gesture, type, event)",
     "                    refuseBackClick()\n                    return swallow(gesture, type, event)\n                }\n                Self.postReturn()\n                return swallow(gesture, type, event)"),
    ("a prompt in flight starts a plain dictation instead of the refusal", "HotkeyTap.swift",
     "                if ownDictation {\n                    refuseBackClick()\n                    return swallow(gesture, type, event)\n                }\n                return plainToggle(gesture, type, event)",
     "                return plainToggle(gesture, type, event)"),
    ("🔽 → stops a plain sentence it opened a moment ago", "HotkeyTap.swift",
     "if wisprSentence || ownClean, f5Now - lastPlainStartAt < Self.gestureStopDwellSeconds {",
     "if false {"),
    ("the pair reads the app's own stamped flagsChanged as his release again (W1)", "HotkeyTap.swift",
     "if !ownPost, pair != cleanPairDown {", "if pair != cleanPairDown {"),
    ("held right ⌘⌥ no longer reaches onCleanHold", "HotkeyTap.swift",
     "                if pair || was {", "                if false {"),
    ("an unclaimed Wispr ⌘V is rescued again", "WisprFlowSource.swift",
     "                Log.info(\"🛡️ ⌘V from \\(process) with no capture open and no relay sentence to compare its row with — nothing delivered\")",
     "            rescueFromRow(after: process)"),
    ("plain dictation gets the kamikaze word", "AppDelegate.swift",
     "if clean { kamikaze = false }", ""),
    ("⌘⌃X passes to the front app on autorepeat (acted on twice)", "HotkeyTap.swift",
     "if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return swallow(\"⌘⌃X (autorepeat)\", type, event) }", ""),
    ("⌘⌃X stops the take the ordinary way (the cloud still gets it)", "AppDelegate.swift",
     "        guard source.handToLocal() else {", "        guard { endDictation(); return true }() else {"),
    ("🔽 ← cancels again (before 2026-10-05)", "HotkeyTap.swift",
     "                Self.postReturn()\n                return swallow(gesture, type, event)\n\n            // ⬆️ — dictate",
     "                DispatchQueue.global().async { [weak self] in self?.onLocalCancel?() }\n                return swallow(gesture, type, event)\n\n            // ⬆️ — dictate"),
    ("bare F7/F9 swallowed for the halo again (Q10)", "HotkeyTap.swift",
     "(keyCode == VK_F7 || keyCode == VK_F9) && fnKeyHeld && ", "(keyCode == VK_F7 || keyCode == VK_F9) && "),
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
    # **The mapping this spec was rewritten against must fail it** (2026-09-28):
    # the tap as it stood before the swap back — 🔽 the plain toggle, 🔽 → only
    # Return (268b111, 2026-09-23) — read out of git, the whole file, not a
    # one-line mutation.
    for commit, label in OLD_MAPPINGS:
        old = old_mapping_tap(commit)
        if old is None:
            print(f"self-test FAILED — cannot read HotkeyTap.swift at {commit} from git")
            return 1
        src = dict(base)
        src["HotkeyTap.swift"] = old
        code, _ = run(src, quiet=True)
        print(f"{'✓' if code != 0 else '✗'} caught: {label} ({commit})")
        if code == 0:
            missed.append(label)
    if missed:
        print(f"self-test FAILED — {len(missed)} mutation(s) not caught")
        return 1
    print(f"self-test ok — all {len(MUTATIONS)} broken rules and the {len(OLD_MAPPINGS)} old mappings are caught")
    return 0


# The last commit whose HotkeyTap still had each superseded mapping.
OLD_MAPPINGS = [
    ("c8d918b", "the 2026-09-23 mapping: 🔽 = plain toggle, 🔽 → = Return"),
    ("6efad93", "the 2026-09-28 mapping: 🔽 at rest = Return"),
    ("9b2aa72", "the 2026-10-05 mapping: 🔽 →'s stop presses Return, 🔽 ↓ unbinds mid-sentence"),
]


def old_mapping_tap(commit: str) -> str | None:
    import subprocess
    root = SOURCES.parent.parent
    try:
        return subprocess.run(["git", "-C", str(root), "show", f"{commit}:Sources/WalkieTalkie/HotkeyTap.swift"],
                              capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
