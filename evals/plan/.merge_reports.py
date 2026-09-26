#!/usr/bin/env python3
"""Merge the per-batch reports of 2026-09-26 into report-2026-09-26.md (one row per case run)."""
import re, glob, os, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
# (file, phase label); later files supersede earlier rows of the same id unless listed in KEEP_BOTH
ORDER = [("report-A.md", "A"), ("report-A2.md", "A (new build)"), ("report-A3.md", "A"), ("report-A4-TR21.md", "A (re-run: delivery TR21 never ran)"),
         ("report-B1.md", "B"), ("report-B2.md", "B"), ("report-B3.md", "B"), ("report-B3b.md", "B (re-run after fix)"),
         ("report-B4.md", "B"),
         ("report-C1.md", "C"), ("report-C2.md", "C"), ("report-C3.md", "C"), ("report-C3b.md", "C (re-run)")]
ORDER += [(os.path.basename(p), "D") for p in sorted(glob.glob(HERE + "/report-D*.md"))]
KEEP_BOTH = {"B3"}                       # flaky: both runs are evidence
rows, order = {}, []
for fn, phase in ORDER:
    p = os.path.join(HERE, fn)
    if not os.path.exists(p):
        continue
    txt = open(p, encoding="utf-8").read()
    m = re.search(r"# Test plan run — (\d{4}-\d\d-\d\d \d\d:\d\d)", txt)
    t = datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M")
    for line in txt.splitlines():
        mm = re.match(r"\| (\S+) \| \*\*(\w+)\*\* \| (\d+) \| (.*)$", line)
        if not mm:
            continue
        cid, v, s, rest = mm.groups()
        key = cid
        if cid in KEEP_BOTH and cid in rows:
            key = cid + "#2"
        if key in rows and cid not in KEEP_BOTH:
            # a TR21/TR22 duplicate id from another module in the same file is a different case
            if rows[key][0] == fn:
                key = cid + "'"
        if key not in rows:
            order.append(key)
        rows[key] = (fn, phase, t.strftime("%H:%M"), cid, v, s, rest)
        t += datetime.timedelta(seconds=int(s))
counts = {}
for k in order:
    counts[rows[k][4]] = counts.get(rows[k][4], 0) + 1
out = ["# Test plan run — 2026-09-26 (merged: phases A–D)", "",
       "Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was "
       "confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.",
       "Phase A = routes only, B = gestures (hands-off), C = real audio through 🧪 WT Inject (hands-off), "
       "D = spawn/relaunch/slow, one at a time. Time = batch start + the preceding cases' durations (local, ≈). "
       "App pid 22498 for the first A batch, 11073 (commit 33cf539, 5 s eraser) from A2 on, 75172 after TD12's relaunch.", "",
       " · ".join(f"{k} {v}" for k, v in sorted(counts.items())), "",
       "| case | phase | time | verdict | s | expectation | observed | source |", "|---|---|---|---|---|---|---|---|"]
for k in order:
    fn, phase, hm, cid, v, s, rest = rows[k]
    rest = rest.rstrip()
    if rest.endswith("|"):
        rest = rest[:-1].rstrip()
    out.append(f"| {cid} | {phase} | {hm} | **{v}** | {s} | {rest} | {fn} |")
out += ["", "## Not run", "",
        "TL28, TD23 (sleep) · TD7, TD17, TD18 (real Claude Code) · TD28, TD30 (Codex) — skipped for good by the brief.", "",
        "## Verdicts to read with care", "",
        "- **TD20 FAIL** is the rig, not the app: its 4826-char panel unfolded under a stationary pointer, autosend paused "
        "(`autosend held — the pointer is on the panel`), nothing was delivered, and the relay stayed busy until ⎋ by hand.",
        "- **TL25 FAIL**: same trap. The settle gave up at 32.1 s, ElevenLabs answered at 48.65 s (5309 chars), the late panel "
        "paused under the pointer at 15:15:05 and was still up when the case ended; the case waited 600 s for a delivery line.",
        "- **TL17 PASS** did not meet its precondition: the helper was back up (ready/alive true) before Recover ran.",
        "- **B3** is flaky: run 1 saw no correction start in 10 s, run 2 PASSed (both rows kept).",
        "- **LC rows** are from the 13:08 re-run on pid 11073 (5 s eraser); the 12:40 run on pid 22498 had LC3 PASS at a 2 s eraser "
        "and the same four FAILs (LC2, LC7, LC9, LC16).",
        "- **TR21 / TR22** exist in two modules each (lifecycle and delivery); each appears twice, lifecycle row first."]
open(os.path.join(HERE, "report-2026-09-26.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
print(counts, len(order))
