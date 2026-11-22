#!/usr/bin/python3
"""The film's stand-in for the coding agent, run in the guest's bound Terminal tab (hidden behind the site).

NOT Claude: the lab guest has no logged-in agent, and the teaser cuts the agent's wait anyway. It reads what
Walkie really delivers into the tab and, when a prompt's words match a scene, applies that scene's scripted
edit to the demo site (state.json → the page restyles). So in the footage the page changes because the
dictated prompt arrived, about a second later.
"""
import json, os, re, sys, time
STATE = os.path.expanduser("~/film/demo-site/state.json")
MOVE = re.compile(r"corners \(x,y\) \((\d+),(\d+)\).*?should move to the box \((\d+),(\d+)\)")
RULES = [("header", {"header-dark": 1, "button-orange": 1}),
         ("user-drawn move", None),                          # the ✂️ row of a moved area: its real coordinates
         ("picture", {"picture": 1, "typo-fixed": 1}),
         ("flicker", {"flicker": 0, "menu-open": 1}),
         ("loop", {"loop-fixed": 1}),
         ("broken", {"card-fixed": 1})]
LOG = open(os.path.expanduser("~/film/agent.log"), "a")
print("\033[2J\033[H\033[1m✻ demo agent\033[0m  " + os.getcwd().replace(os.path.expanduser("~"), "~") + "\n")
first = [l for l in (sys.argv[-1] if len(sys.argv) > 1 else "").splitlines() if l.strip() and not l.startswith("[")]
first = first[0] if first else ""                       # a spawned session gets its first prompt as an argument
if first:
    print("\033[1m❯\033[0m " + first + "\n\n  ⏺ On it …\n")
else:
    print("  Waiting for a prompt…\n")
while True:
    sys.stdout.write("\033[1m❯\033[0m "); sys.stdout.flush()
    line = sys.stdin.readline()
    if not line: break
    LOG.write(line); LOG.flush()
    low = line.lower()
    for words, change in RULES:
        # only his own words count — the envelope's bracketed rows mention pictures and files too
        if words in low and (change is None or not low.lstrip("❯ ").startswith("[")):
            print("\n  ⏺ Editing site/style.css …"); sys.stdout.flush()
            time.sleep(float(os.environ.get("AGENT_DELAY", "1.2")))
            try: state = json.load(open(STATE))
            except Exception: state = {}
            if change is None:                               # screenshot pixels (2x) → screen points; the page does the rest
                m = MOVE.search(line)
                if not m: continue
                sx, sy, dx, dy = (int(v) / 2 for v in m.groups())
                change = {"moved": {"fromX": sx, "fromY": sy, "toX": dx, "toY": dy}}
            state.update(change)
            tmp = STATE + ".tmp"; json.dump(state, open(tmp, "w")); os.replace(tmp, STATE)
            print("  ⏺ Done.\n"); break
