#!/usr/bin/env python3
"""The same dictation, in three envelopes — and the file names each one implies.

One set of facts (`FACTS`), three renderings:

  `current` — what the app writes today: references in the words, a `- ` list of
              frames under them, a paragraph per clause.
  `victor`  — Victor's 2026-09-19 template: every attachment is a bracketed
              token *where he made it*, and the footer is a legend keyed by
              those tokens.
  `shrunk`  — the same, with the per-artifact legend rows replaced by one line
              stating the naming convention. Only the Chrome pick keeps a row,
              because a selector and a URL cannot be derived from a number.

Each variant also says what its files are called, so a run is staged with names
its own envelope refers to — otherwise the comparison measures whether a model
can guess a filename rather than whether it understood the symbols.
"""

FOLDER = "$WALKIE_SHOTS/2026-09-19-17-32-15"
RES = "3456x2234px"
AREA = (900, 345, 2594, 574)
MOUSE = {0: (1000, 800), 1: (2400, 1180), 2: (640, 430)}
SELECTED = "A subprocess per frame costs two hundred milliseconds on this machine"
SELECTED_APP = "Google Chrome"
ELEMENT_TEXT = "Notes on latency budgets"
ELEMENT_PATH = "div.wrap > h1"
ELEMENT_URL = "https://interact.victorrentea.ro/notes"
FILM_SECONDS = 5
WINDOW = "Google Chrome — Notes on latency budgets"

# The words, with a slot per attachment. The sentence is Romanian with English
# technical words in it, which is what he actually dictates.
PARTS = [
    "{s0}Uite pagina asta cu notițe.",
    "{s1}Linia asta e problema,",
    "{sel}și vreau să o rescriu mai scurt.",
    "{s2}Și mai jos, aici, la fel.",
    "{a3}În zona asta trebuie să apară un tabel.",
    "{el}Titlul rămâne cum e.",
    "{f_on}Uite cum se derulează,",
    "{f_off}gata.",
]

# What the canonical (new) names are; `current` renames them to today's shape.
CANONICAL = {
    "s0_small": "screenshot-0-800px.jpg", "s0_full": "screenshot-0-original.jpg",
    "s1_small": "screenshot-1-800px.jpg", "s1_full": "screenshot-1-original.jpg",
    "s2_small": "screenshot-2-800px.jpg", "s2_full": "screenshot-2-original.jpg",
    "a3_small": "screenshot-3-800px.jpg", "a3_full": "screenshot-3-original.jpg",
    "a3_cut": "screenshot-3.jpg",
    "film_sheet": "screencast-1-filmstrip.jpg",
    "film_f1_small": "screencast-1-frame-0.1s-800px.jpg",
    "film_f1_full": "screencast-1-frame-0.1s-original.jpg",
    "film_f2_small": "screencast-1-frame-2.5s-800px.jpg",
    "film_f2_full": "screencast-1-frame-2.5s-original.jpg",
}

TODAY = dict(CANONICAL, **{
    "s0_small": "shot#00(mouse-at-1000x800px)-small.jpg",
    "s0_full": "shot#00(mouse-at-1000x800px).jpg",
    "s1_small": "shot#01(mouse-at-2400x1180px)-small.jpg",
    "s1_full": "shot#01(mouse-at-2400x1180px).jpg",
    "s2_small": "shot#02(mouse-at-640x430px)-small.jpg",
    "s2_full": "shot#02(mouse-at-640x430px).jpg",
    "a3_small": "shot#03(area-900x345-to-2594x574px)-small.jpg",
    "a3_full": "shot#03(area-900x345-to-2594x574px).jpg",
    "a3_cut": "shot#03(area-900x345-to-2594x574px)-zoom.jpg",
    "film_sheet": "film-2026-09-19-17-33-02/sheet.jpg",
    "film_f1_small": "film-2026-09-19-17-33-02/frame-0001.jpg",
    "film_f1_full": "film-2026-09-19-17-33-02/frame-0001.jpg",
    "film_f2_small": "film-2026-09-19-17-33-02/frame-0013.jpg",
    "film_f2_full": "film-2026-09-19-17-33-02/frame-0013.jpg",
})


def _words(slots):
    return " ".join(part.format(**slots) for part in PARTS)


def _tokens(auto=False):
    x1, y1, x2, y2 = AREA
    return {
        "s0": f"[📸0🖱️@{MOUSE[0][0]}:{MOUSE[0][1]}{' auto' if auto else ''}] ",
        "s1": f"[📸1🖱️@{MOUSE[1][0]}:{MOUSE[1][1]}] ",
        "s2": f"[📸2🖱️@{MOUSE[2][0]}:{MOUSE[2][1]}] ",
        "sel": f'[selected: "{SELECTED}" from app {SELECTED_APP}] ',
        "a3": f"[📸3✂️{x1},{y1}→{x2},{y2}] ",
        "el": f"[chrome-selection-1: {ELEMENT_TEXT}] ",
        "f_on": "[🎦1⏺️] ",
        "f_off": f"[🎦1⏹️{FILM_SECONDS}s] ",
    }


def _tail(x1, y1, x2, y2):
    """The rows no collapsing touches — a rectangle, a selector and a film."""
    return [
        f"[📸3✂️ = user-selected area between corners (x,y) ({x1},{y1})→({x2},{y2}) "
        "at 📁/screenshot-3.jpg; also available -800px and -original.jpg]",
        f"[chrome-selection-1 = {ELEMENT_PATH} at {ELEMENT_URL}]",
        "[🎦1 = 📁/screencast-1-filmstrip.jpg, -frame-0.1s-800px.jpg and -original.jpg "
        f"at {RES}]",
    ]


def victor():
    """**The baseline: what the app writes today.** One legend row per frame."""
    x1, y1, x2, y2 = AREA
    words = _words(_tokens())
    footer = "\n".join([
        "[Dictated in RO or EN]",
        f"[📁={FOLDER}]",
        f"[📸0 = 📁/screenshot-0-800px.jpg at 800px width, or -original.jpg at {RES}]",
        f"[📸1 = 📁/screenshot-1-800px.jpg at 800px width, or -original.jpg at {RES}]",
        f"[📸2 = 📁/screenshot-2-800px.jpg at 800px width, or -original.jpg at {RES}]",
        *_tail(x1, y1, x2, y2),
    ])
    return words + "\n\n" + footer, CANONICAL


def onerow():
    """**Victor's question, 2026-09-20**, and the only thing it changes.

    *"Chiar e nevoie de astea? Nu inferă agentul singur că în loc de `1` trebuie
    să pună `2`?"* — the three plain-frame rows differ by one digit and nothing
    else, so they become one row with `n` where the digit was. Everything else is
    `victor` byte for byte: the same words, the same tokens, the same folder line
    and the same three rows for the things a number cannot give you (a rectangle,
    a CSS selector, a film's frame names).
    """
    x1, y1, x2, y2 = AREA
    words = _words(_tokens())
    footer = "\n".join([
        "[Dictated in RO or EN]",
        f"[📁={FOLDER}]",
        f"[📸n = 📁/screenshot-n-800px.jpg at 800px width, or -original.jpg at {RES}]",
        *_tail(x1, y1, x2, y2),
    ])
    return words + "\n\n" + footer, CANONICAL


def onerow_auto():
    """`onerow`, plus the five characters both models asked for in the last run.

    The one question the footer never states is *which frame was automatic* — 📸0
    simply has no gesture behind it, and every run answered it correctly by
    inference and then said in `unclear` that it had guessed. If collapsing the
    rows costs that inference, ` auto` on the token buys it back outright; if it
    does not, this arm says what the marker is worth on its own.
    """
    x1, y1, x2, y2 = AREA
    words = _words(_tokens(auto=True))
    footer = "\n".join([
        "[Dictated in RO or EN]",
        f"[📁={FOLDER}]",
        f"[📸n = 📁/screenshot-n-800px.jpg at 800px width, or -original.jpg at {RES}]",
        *_tail(x1, y1, x2, y2),
    ])
    return words + "\n\n" + footer, CANONICAL


def shrunk():
    """One legend line for the convention, one row for what cannot be derived."""
    words, names = victor()
    words = words.split("\n\n")[0]
    footer = "\n".join([
        "[Dictated in RO or EN]",
        f"[📁={FOLDER} — 📸n is screenshot-n-800px.jpg (800px wide) and "
        f"-original.jpg ({RES}); a ✂️ one also has screenshot-n.jpg, that region "
        "alone, unscaled. 🎦n is screencast-n-filmstrip.jpg and "
        "-frame-<seconds>s-800px.jpg / -original.jpg]",
        f"[chrome-selection-1 = {ELEMENT_PATH} at {ELEMENT_URL}]",
    ])
    return words + "\n\n" + footer, names


def current():
    """Today's envelope, with the same facts — the control."""
    n = TODAY
    words = _words({
        "s0": "", "s1": "(screenshot: shot#01) ", "s2": "(screenshot: shot#02) ",
        "sel": f'(selected text: "{SELECTED}") ',
        "a3": "(screenshot: shot#03) ",
        "el": f'(selected DOM element: {ELEMENT_PATH}, with text: "{ELEMENT_TEXT}" '
              f'in page "{ELEMENT_URL}") ',
        "f_on": "", "f_off": "",
    })
    footer = "\n".join([
        "[this text dictated and transcribed in RO or EN by ElevenLabs Scribe]",
        f"[Focused window: {WINDOW}]",
        f"[screenshots are in {FOLDER}/ open only if the words need it:",
        f"- {n['s0_small']} in '{WINDOW}'",
        f"- {n['s1_small']} in '{WINDOW}'",
        f"- {n['s2_small']} in '{WINDOW}'",
        f"- {n['a3_small']} in '{WINDOW}'",
        f"  - {n['a3_cut']} — the region itself, cut out of that frame, unscaled",
        "Each is ≤800px wide; drop the -small for the full-resolution original. "
        "A `-zoom` is the exception: it is not scaled at all. A name with "
        "`area-x1xy1-to-x2xy2px` in it is a whole screen with a rectangle I dragged "
        "on it, in the pixels of the full-resolution frame, top-left origin — I am "
        "pointing at that region, not cropping to it. Its `-zoom` is that rectangle "
        "cut out at full size: the screen says where, the zoom says what.]",
        f"[Screen recording: {FILM_SECONDS}.0s at 5 fps, 25 frames. Look at "
        f"{FOLDER}/film-2026-09-19-17-33-02/sheet.jpg — every frame, thumbnailed and "
        "labelled `#n  m:ss.t`. The full-resolution frames are "
        f"{FOLDER}/film-2026-09-19-17-33-02/frame-NNNN.jpg, numbered as on the sheet: "
        "open one when the sheet shows something worth reading.]",
    ])
    return words + "\n\n" + footer, TODAY


VARIANTS = {"current": current, "victor": victor, "shrunk": shrunk,
            "onerow": onerow, "onerow_auto": onerow_auto}

if __name__ == "__main__":
    import sys
    for name in (sys.argv[1:] or VARIANTS):
        text, _ = VARIANTS[name]()
        print(f"───────── {name} ({len(text)} chars) ─────────\n{text}\n")
