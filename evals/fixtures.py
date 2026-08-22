"""Real dictations, replayed.

Every fixture here is a message Victor actually spoke into the relay — pulled
out of `~/.wispr-relay/outbox.jsonl` with the screenshots it carried still on
disk. Nothing is synthesised: the whole question these evals exist to answer is
whether an agent can follow *his* pointing, and a made-up sequence would answer
it about a made-up habit.

Ground truth is the ordered list of what each frame shows. It is checkable
against the transcript itself, which is the point — he enumerates the things he
is pointing at, one clause per picture, so the transcript *is* the answer key.
"""

import os

# Where these frames live now. `Outbox.retireLegacyShots` moved the pre-Caches
# pile to the Trash on launch — deliberately to the Trash and not to `rm`,
# because outbox lines still name those files. These fixtures are the second
# thing that decision saved: the frames are still readable, so the evals still
# run. They go for good when Victor empties it, and `run.py` says so by skipping
# the fixture rather than failing.
SHOTS = next(
    (d for d in (os.path.expanduser("~/.wispr-relay/shots"),
                 os.path.expanduser("~/.Trash/shots"))
     if os.path.isdir(d)),
    os.path.expanduser("~/.wispr-relay/shots"))


def _p(name):
    return os.path.join(SHOTS, name)


FIXTURES = {
    # 2026-07-31T10:17:01Z — seven clauses, seven frames, one per sender.
    # The hardest thing an agent has to do with a relay message, and the most
    # common: line up "ăsta … ăsta … ăsta" with the pictures in the order they
    # were taken.
    "unsubscribe": {
        "text": ("Nu mai vreau să văd mail-uri ca ăsta de la Fan Courier. "
                 "Nici ca acesta de la Sesame. "
                 "Nici ca ăsta de la H&M. "
                 "Nici ca ăsta de la Shine. "
                 "Nici feedback pe Sezamo. "
                 "Nici ăsta de la Shakespeare School. "
                 "Dezabonează-te și de la The Zone Events."),
        "context": _p("shot-2026-07-31-13-15-31.jpg"),
        "shots": [
            _p("shot-2026-07-31-13-15-49.jpg"),
            _p("shot-2026-07-31-13-15-57.jpg"),
            _p("shot-2026-07-31-13-16-00.jpg"),
            _p("shot-2026-07-31-13-16-06.jpg"),
            _p("shot-2026-07-31-13-16-21.jpg"),
            _p("shot-2026-07-31-13-16-35.jpg"),
        ],
        # Seconds from the start of the dictation, context first. Taken from the
        # file mtimes against the 13:15:31 context frame.
        "offsets": [0, 18, 26, 29, 35, 50, 64],
        # No cursor was recorded in July — these predate the pointer tag.
        "cursors": [None] * 7,
        "question": ("Do not act on any of it. Answer with a JSON array of 7 strings and "
                     "nothing else: for each screenshot, in the order they were taken, "
                     "the name of the sender of the email that is OPEN in the reading "
                     "pane on the right."),
        "truth": ["fan courier", "sezamo", "h&m", "shein",
                  "sezamo", "shakespeare school", "dzone"],
        "n": 7,
    },

    # 2026-08-13T00:06:23Z — he asks the agent, in so many words, what he was
    # pointing at. This is the fixture that says whether the cursor coordinate
    # in the file name is worth anything.
    "pointed": {
        "text": ("So if I speak now, I think I shot here and I shot here. "
                 "Tell me: what words have I pointed out and a third one?"),
        "context": _p("shot-2026-08-13-03-06-02-cursor-21.0x51.3pct.jpg"),
        "shots": [
            _p("shot-2026-08-13-03-06-04-cursor-16.8x50.1pct.jpg"),
            _p("shot-2026-08-13-03-06-05-cursor-33.9x34.3pct.jpg"),
            _p("shot-2026-08-13-03-06-13-cursor-25.6x83.4pct.jpg"),
        ],
        "offsets": [0, 2, 3, 11],
        # x,y in the pixels of each 3456×2234 frame, top-left origin — the same
        # reading `ScreenCapture.tagCursor` writes into the name today.
        "cursors": [(725, 1146), (580, 1119), (1171, 766), (884, 1863)],
        "question": ("Do not act on any of it. Answer with a JSON array of 3 strings and "
                     "nothing else: for each of the three deliberate screenshots, in "
                     "order, quote the line of text the mouse pointer was sitting on."),
        # The first one was mis-read by hand when this fixture was built — a crop
        # around the pointer showed two candidate lines and the wrong one was
        # written down. Every variant then answered "DO NOT COPY TEXT TO/FROM
        # CODING AGENT" identically, fifteen runs out of fifteen, which is what
        # sent someone back to the pixels. Left recorded here because a fixture
        # whose key was wrong is exactly the failure an eval suite is for.
        "truth": ["do not copy text", "architecture/review", "limit offset"],
        "n": 3,
    },
}
