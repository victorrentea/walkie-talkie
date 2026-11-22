#!/usr/bin/python3
"""The film's stand-in for the coding agent, run in the guest's Terminal tabs. DRAWN TO LOOK LIKE a Claude Code
session (banner, ❯ input box between two rules, ⏺ tool rows, the spinner) — it is NOT Claude: the lab guest has no
logged-in agent, and the teaser cuts the agent's wait anyway.

What is real: it reads what Walkie really delivers into the tab (typed, pasted, or as argv for a spawned session)
and shows it — his sentence and the envelope's rows. What is scripted: when the sentence matches a scene, that
scene's edit is applied to the demo site (state.json → the page restyles), and the ⏺ rows are canned text.

Environment:  AGENT_HISTORY=1  an earlier exchange already on screen (the hook's "your agent lives in your terminal")
              AGENT_STATUS=busy a session that is working from the start and stays so (the ⏳ row of the folder dialog)
              AGENT_DELAY=<s>   how long a task "works" (default 1.6)      AGENT_QUIET=1  the envelope's rows are not shown
"""
import json, os, re, select, sys, termios, textwrap, threading, time, tty

HOME = os.path.expanduser("~")
STATE = HOME + "/film/demo-site/state.json"
CWD = os.getcwd()
SHOWN = CWD.replace(HOME, "~")
QUIET = bool(os.environ.get("AGENT_QUIET"))
DELAY = float(os.environ.get("AGENT_DELAY", "1.6"))
LOG = open(HOME + "/film/agent.log", "a")
MOVE = re.compile(r"(\d+),(\d+)\D+\d+,\d+\)?\s*\[?(?:should move to the box|moved to)\s*\(?(\d+),(\d+)")   # short and long envelope
ROW = re.compile(r"^\s*(\[[^\]]*\]\s*)+$")                 # a line that is only bracketed clauses: the envelope's own
GREY = "\033[38;5;245m"
AREA = re.compile(r"✂️\s*(\d+),(\d+)\s*→\s*(\d+),(\d+)")
O, D, B, G, R = "\033[38;5;209m", "\033[2m", "\033[1m", "\033[38;5;114m", "\033[0m"
# sentence contains → (state change | "move" | "picture", the ⏺ tool row, its ⎿ row, the closing line)
RULES = [("header", {"header-dark": 1, "button-orange": 1}, "Update(style.css)", "Updated style.css with 4 additions and 2 removals",
          "The header is dark and the button you pointed at is orange."),
         ("move", "move", "Update(index.html)", "Updated index.html with 1 addition and 1 removal", "Moved it to where you dropped it."),
         ("picture", "picture", "Update(index.html)", "Updated index.html with 3 additions and 1 removal",
          "The picture is where you drew the box, and the typo is fixed."),
         ("flicker", {"flicker": 0, "menu-open": 1}, "Update(style.css)", "Updated style.css with 1 removal", "The menu stays still now."),
         ("loop", {"loop-fixed": 1}, "Update(src/main/java/shop/brewly/CartService.java)",
          "Updated CartService.java with 4 additions and 8 removals", "The loop is a stream now."),
         ("add a test", {}, "Write(tests/buttons.spec.js)", "Wrote 38 lines to tests/buttons.spec.js", "The test is in and passes."),
         ("rename", {}, "Update(src/orders.js)", "Updated 4 files with 9 additions and 9 removals", "Renamed to parseOrder everywhere, the tests too."),
         ("broken", {"card-fixed": 1}, "Update(style.css)", "Updated style.css with 5 additions and 6 removals", "The card is fixed."),
         ("", {}, "Bash(git show --stat HEAD)", "3 files changed, 41 insertions(+), 12 deletions(-)", None)]   # anything else (the spawned session's review)
HISTORY = [("u", "scaffold a landing page for Brewly, a coffee subscription"),
           ("a", "I'll set up the page: a header, a hero with two buttons, and three feature cards."),
           ("t", "Write(index.html)", "Wrote 64 lines to index.html"),
           ("t", "Write(style.css)", "Wrote 71 lines to style.css"),
           ("a", "The landing page is up at http://brewly.test, ready for your feedback.")]

body = list(HISTORY) if os.environ.get("AGENT_HISTORY") else []
typed = ""                    # what sits in the input box
spin = None                   # (verb, since) while "working"
lock = threading.Lock()


def publish(status):
    """What a real Claude Code session leaves on disk and Walkie reads: the status line's per-session folder
    (~/.claude/cwd/.last-<pid>) and the session's state (~/.claude/sessions/<pid>.json) — so the folder dialog lists
    this tab under its project, with the ⏳ while it is working."""
    try:
        for d in ("cwd", "sessions"): os.makedirs(HOME + "/.claude/" + d, exist_ok=True)
        open(HOME + "/.claude/cwd/.last-%d" % os.getpid(), "w").write(CWD)
        json.dump({"sessionId": "film-%d" % os.getpid(), "cwd": CWD, "status": status, "kind": "interactive"},
                  open(HOME + "/.claude/sessions/%d.json" % os.getpid(), "w"))
    except OSError: pass


def beat():
    """What the walkie-inbox mod does in a real session: say every 2 s that this tty holds the agent rules, so
    Walkie sends the SHORT envelope (data only) instead of repeating the instructions."""
    try: name = os.path.basename(os.ttyname(0))
    except OSError: return
    d = HOME + "/.walkie-talkie/inbox/" + name; os.makedirs(d, exist_ok=True)
    while True:
        json.dump({"at": int(time.time() * 1000), "rules": 3}, open(d + "/.alive.tmp", "w")); os.replace(d + "/.alive.tmp", d + "/.alive")
        time.sleep(2)


def wrap(text, width, first, rest):
    out = []
    for i, para in enumerate(text.split("\n")):
        lines = textwrap.wrap(para, max(10, width - len(first))) or [""]
        out += [(first if not out else rest) + l for l in lines]
    return out


def render():
    with lock:
        cols, rows = os.get_terminal_size()
        w = min(cols - 1, 110)
        inner = max(30, len(SHOWN) + 10)
        L = [O + "╭" + "─" * inner + "╮" + R,
             O + "│ ✻ " + R + B + "Welcome to Claude Code!".ljust(inner - 3) + R + O + "│" + R,
             O + "│" + R + D + ("   Opus 5.5 · Claude Max").ljust(inner) + R + O + "│" + R,
             O + "│" + R + D + ("   cwd: " + SHOWN).ljust(inner) + R + O + "│" + R,
             O + "╰" + "─" * inner + "╯" + R, ""]
        for item in body:
            if item[0] == "u":                               # the prompt as it was injected: his words bold, the envelope's rows grey
                for l in item[1].split("\n"):
                    if not l.strip(): continue
                    if ROW.match(l):
                        if not QUIET: L += [GREY + x + R for x in wrap(l, w - 2, "  ", "  ")]
                    else:
                        for x in wrap(l, w - 2, "> ", "  "): L.append("\033[48;5;236m" + B + x + " " + R)   # ">" — a "❯" row reads to Walkie as a sentence still unsent
            elif item[0] == "a": L += wrap(item[1], w, "⏺ ", "  ")
            elif item[0] == "t": L += [G + "⏺" + R + " " + B + item[1] + R, D + "  ⎿  " + item[2] + R]
            L.append("")
        if spin:
            s = int(time.time() - spin[1])
            L += [O + "✢✳✶✻✽✻✶✳"[int(time.time() * 6) % 8] + " " + spin[0] + "…" + R + D + " (%ds · esc to interrupt)" % s + R, ""]
        box = wrap(typed, w - 2, "❯ ", "  ") if typed else ["❯ "]
        tail = [D + "─" * w + R] + box + [D + "─" * w + R, D + "  ? for shortcuts" + R]
        L = L[max(0, len(L) - (rows - len(tail))):]
        sys.stdout.write("\033[?25l\033[H\033[2J" + "\r\n".join(L + tail))
        up = 2 + (len(box) - 1) * 0                         # the caret: at the end of the box's last line
        sys.stdout.write("\033[%dA\r\033[%dC\033[?25h" % (2, len(box[-1])))
        sys.stdout.flush()


def work(message, spawned=False):
    """His prompt has landed: show it, "work" for a moment, apply the scene's scripted change, say done."""
    global spin
    LOG.write(message + "\n---\n"); LOG.flush()
    lines = message.split("\n")
    said = re.sub(r"\[[^\]]*\]", " ", " ".join(l for l in lines if not ROW.match(l))).lower()
    body.append(("u", message))
    words, change, tool, did, done = next(r for r in RULES if r[0] in said)
    spin = ("Brewing", time.time()); publish("busy"); render()
    end = time.time() + (3600 if spawned else DELAY)       # a spawned session keeps working for as long as it is filmed
    shown = False
    while time.time() < end:
        if not shown and time.time() > spin[1] + min(0.9, DELAY * 0.4):
            body.append(("t", tool, did)); shown = True
        render(); time.sleep(0.12)
    try: state = json.load(open(STATE))
    except Exception: state = {}
    if change == "move":                                     # screenshot pixels (2x) → screen points; the page does the rest
        m = MOVE.search(message)
        change = {"moved": dict(zip(("fromX", "fromY", "toX", "toY"), (int(v) / 2 for v in m.groups())))} if m else {}
    elif change == "picture":                                # the box he drew, from the prompt's own ✂️ token (pixels, 2x)
        m = AREA.search(message); change = {"picture": 1, "typo-fixed": 1}
        if m:
            x0, y0, x1, y1 = (int(v) / 2 for v in m.groups()); change["artBox"] = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
    state.update(change)
    json.dump(state, open(STATE + ".tmp", "w")); os.replace(STATE + ".tmp", STATE)
    body.append(("a", done or "Done.")); spin = None; publish("idle"); render()


def main():
    global typed, spin
    threading.Thread(target=beat, daemon=True).start()
    first = sys.argv[-1] if len(sys.argv) > 1 else ""        # a spawned session gets its first prompt as an argument
    fd = sys.stdin.fileno(); old = termios.tcgetattr(fd); tty.setcbreak(fd)
    sys.stdout.write("\033[?2004h")                          # bracketed paste, as Claude Code asks for
    busy = os.environ.get("AGENT_STATUS") == "busy"
    publish("busy" if busy else "idle")
    if busy: spin = ("Brewing", time.time() - 47)
    try:
        if first: work(first, spawned=True)
        render()
        pasting = False; pending = None                      # pending: when a ⏎ arrived (more lines may follow at once)
        while True:
            ready = select.select([fd], [], [], 0.15)[0]
            if not ready:
                if pending and time.time() - pending > 0.45:
                    message, typed, pending = typed.strip("\n"), "", None
                    if message.strip(): work(message)
                    render()
                elif spin: render()
                continue
            data = os.read(fd, 65536).decode("utf-8", "replace")
            if not data: break
            for part in re.split(r"(\x1b\[20[01]~)", data):
                if part == "\x1b[200~": pasting = True; continue
                if part == "\x1b[201~": pasting = False; continue
                part = re.sub(r"\x1b\[[0-9;?]*[A-Za-z~]", "", part)
                for ch in part:
                    if ch in "\r\n":
                        typed += "\n"
                        if not pasting: pending = time.time()
                    elif ch == "\x7f": typed = typed[:-1]
                    elif ch >= " " or ch == "\t": typed += ch; pending = pending and time.time()
            render()
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        for f in ("/.claude/cwd/.last-%d", "/.claude/sessions/%d.json"):
            try: os.remove(HOME + f % os.getpid())
            except OSError: pass


main()
