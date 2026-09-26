"""§7.4 LC — the subtitle band, driven only through `POST /test/live-caption` and read from
`state.liveCaption` (docs/test-plan.md). No microphone, no network: the band's own motion.

Constants (LiveCaptionBand.swift, 07:50 centred layout): marginRight 48, dropSlack 40, vMax 700,
ease 0.45, swap 1.0 (ghost 0.5), correctionFade 1.6, reflow 0.26, provisionalFloor 0.4, fadeIn 0.22 (opacity,
batch 5), eraser after
5.0 s idle (2.0 until 2026-09-26 14:20) at 260 pt/s with a 160 pt edge, letter by letter.

Centre of the visible text = anchor + (visibleStart + visibleWidth) / 2, visibleStart = max(0,
eraseFront + 80) while erasing (the band's `centredAnchor` takes max(shown[0], front + edge/2)),
else 0. `visibleWidth` (batch 5, 2026-09-26) is `shownWidth` with each appended word counted only as
far as it has faded in (`appear`, τ reflow): a word still invisible is not text on screen, and the
plan's "centre" and "end" are of the visible text. It equals `shownWidth` for a fresh line and at
rest; older builds without it fall back to `shownWidth`. Tolerances beyond the plan's numbers are written next to each assertion and every note
carries what was measured."""
import time
from harness import *

V_MAX, MARGIN, EDGE_HALF = 700.0, 48.0, 80.0
ERASE_AFTER = 5.0     # s: LiveCaptionBand.eraseAfter (also in state.liveCaption.eraseAfter)
JITTER = 0.03          # s: an HTTP read of /test/state is not the app's frame clock
WORDS = ("the quick brown fox jumps over a lazy dog while seven bright wizards quietly juggle heavy "
         "boxes of frozen pizza near an old harbour and nobody seems to notice anything unusual "
         "because everyone is busy watching small boats drift past the long grey pier at sunset "
         "under soft orange clouds that slowly fade into night").split()


# ---------------------------------------------------------------- helpers
def vwidth(s):
    return s.get("visibleWidth", s["shownWidth"])

def centre(s):
    front = s.get("eraseFront")
    start = max(0.0, front + EDGE_HALF) if front is not None else 0.0
    return s["anchor"] + (start + vwidth(s)) / 2

def mid(s):
    return s["bandWidth"] / 2

def fresh():
    """Band closed and faded (the 0.35 s fade's completion resets the ticker)."""
    caption_off()
    wait_for(lambda: not lc()["open"], 1.0, 0.05)
    time.sleep(0.45)

def show(text, partial="", gentle=False, words=None, timeout=1.0):
    """Push a caption and wait until the band reports it (the route hops to main)."""
    caption(text, partial, gentle)
    n = words if words is not None else len((text + " " + partial).split())
    return wait_for(lambda: (lambda s: s if s["words"] == n else None)(lc()), timeout, 0.02)

def drive(events, seconds, hz=20):
    """Fire `events` [(at, fn)] when due while sampling `lc()` at `hz`; returns (samples, fired_at)."""
    out, fired, t0, i = [], [], time.time(), 0
    while True:
        now = time.time() - t0
        while i < len(events) and events[i][0] <= now:
            events[i][1](); fired.append(round(time.time() - t0, 3)); i += 1
        if now >= seconds and i >= len(events):
            break
        s = lc(); s["t"] = round(time.time() - t0, 3); out.append(s)
        time.sleep(1.0 / hz)
    return out, fired

def sample_until(cond, timeout, hz=20):
    out, t0 = [], time.time()
    while time.time() - t0 < timeout:
        s = lc(); s["t"] = round(time.time() - t0, 3); out.append(s)
        if cond(s):
            break
        time.sleep(1.0 / hz)
    return out

def motion_faults(S, slack=2.0):
    """Anchor steps faster than vMax (a jump) and anchor increases, over pairs with no drop."""
    fast, up = [], []
    for a, b in zip(S, S[1:]):
        if a["words"] == 0 or b["dropped"] != a["dropped"]:
            continue
        dt = b["t"] - a["t"]
        d = b["anchor"] - a["anchor"]
        if abs(d) > V_MAX * (dt + JITTER) + slack:
            fast.append((b["t"], round(d, 1), round(dt, 3)))
        if d > slack:
            up.append((b["t"], round(d, 1)))
    return fast, up

def slope(S, key="eraseFront"):
    """Median d(key)/dt over pairs where both are set and nothing was dropped between them."""
    v = [(b[key] - a[key]) / (b["t"] - a["t"]) for a, b in zip(S, S[1:])
         if a.get(key) is not None and b.get(key) is not None and a["dropped"] == b["dropped"] and b["t"] > a["t"]]
    v.sort()
    return v[len(v) // 2] if v else None

def verdict(fails, note):
    return ("PASS", note) if not fails else ("FAIL", "; ".join(fails) + " — " + note)


# ---------------------------------------------------------------- cases
@case("LC1", ("lc",), expect="first word centred: |centre − bandWidth/2| < 3, velocity 0, opacity 0 → 0.4 within 0.5 s, never anchor ≥ bandWidth − 5")
def lc1():
    """First word appears centred and fades in to the provisional floor."""
    fresh()
    caption("", "Hello")
    S = sample(1.4)
    S = [s for s in S if s["words"] >= 1]
    if not S:
        return "FAIL", "the band never showed the word"
    s0, bw = S[0], S[0]["bandWidth"]
    off = abs(centre(s0) - mid(s0))
    vmax = max(s["velocity"] for s in S)
    op0 = s0["opacity"][0]
    at05 = [s["opacity"][0] for s in S if s["t"] >= S[0]["t"] + 0.5]
    last = S[-1]["opacity"][0]
    edge = [s["anchor"] for s in S if s["anchor"] >= bw - 5]
    fails = []
    if off >= 3: fails.append(f"off centre by {off:.1f}")
    if vmax > 0.5: fails.append(f"velocity {vmax:.1f}")
    if op0 >= 0.1: fails.append(f"first opacity {op0}")
    # τ = fadeIn 0.22 (reflow 0.26 before batch 5) → 90 % of 0.4 at 0.5 s; asked: ≥ 0.32 at 0.5 s, 0.4 ± 0.03 at the end
    if not at05 or at05[0] < 0.32: fails.append(f"opacity at +0.5 s {at05[:1]}")
    if abs(last - 0.4) > 0.03: fails.append(f"settled opacity {last}")
    if edge: fails.append(f"{len(edge)} sample(s) with anchor ≥ bandWidth − 5")
    return verdict(fails, f"centre off {off:.2f} pt, max velocity {vmax:.1f}, opacity {op0} → {at05[:1]} at +0.5 s → {last}, bandWidth {bw:.0f}")


@case("LC2", ("lc",), expect="growth at 0.4 s/word for 20 s: centre ±80 until line > bandWidth − 96, then anchor + shownWidth ≤ bandWidth − 48 + 2; |Δanchor| ≤ 700·Δt + 2; anchor rises only by a drop")
def lc2():
    """Growth to the right: centred, then pinned inside the right margin, never jumping."""
    fresh()
    n = 50
    ev = [(0.4 * k, (lambda k=k: caption(" ".join((WORDS * 2)[:k + 1])))) for k in range(n)]
    S, _ = drive(ev, 0.4 * n + 0.5)
    S = [s for s in S if s["words"] > 0]
    bw = S[-1]["bandWidth"]
    wide, dev, over, t_wide = False, 0.0, [], None
    for s in S:
        if not wide and (s["lineWidth"] > bw - 96 or s["dropped"] > 0):
            wide, t_wide = True, s["t"]
        if not wide:
            dev = max(dev, abs(centre(s) - bw / 2))
        else:
            ex = s["anchor"] + vwidth(s) - (bw - MARGIN)
            if ex > 2:
                over.append(ex)
    fast, up = motion_faults(S)
    fails = []
    if dev > 80: fails.append(f"centre off by {dev:.0f} while narrow")
    if over: fails.append(f"{len(over)}/{len(S)} samples past the right margin (max {max(over):.0f} pt)")
    if fast: fails.append(f"{len(fast)} anchor step(s) over vMax, first {fast[0]}")
    if up: fails.append(f"{len(up)} anchor rise(s) without a drop, first {up[0]}")
    return verdict(fails, f"{len(S)} samples, wide from t={t_wide}, max centre offset {dev:.1f} pt while narrow, "
                          f"dropped {S[-1]['dropped']}, max velocity {max(s['velocity'] for s in S):.0f}")


@case("LC3", ("lc",), expect="pause: velocity → 0 within 1.5 s of the last word, centre unchanged until the eraser starts at 5.0 s")
def lc3():
    """A pause: the line comes to rest, then the eraser starts on time."""
    fresh()
    ev = [(0.4 * k, (lambda k=k: caption(" ".join(WORDS[:k + 1])))) for k in range(8)]
    S, fired = drive(ev, 0.4 * 7 + ERASE_AFTER + 1.0)
    t_last = fired[-1]
    er = [s for s in S if s["eraseFront"] is not None]
    t_er = er[0]["t"] if er else None
    rest = [s for s in S if s["t"] >= t_last + 1.5 and (t_er is None or s["t"] < t_er)]
    fails = []
    if t_er is None:
        fails.append("the eraser never started")
    elif not ERASE_AFTER - 0.1 <= t_er - t_last <= ERASE_AFTER + 0.3:
        fails.append(f"eraser started {t_er - t_last:.2f} s after the last word")
    # "→ 0": the ease is exponential (τ 0.45) and snaps only under 0.3 pt, so exactly 0 comes ~2.5 s
    # after the last word; asked: ≤ 10 pt/s (under 0.2 pt per 60 Hz frame) from +1.5 s.
    v = max((s["velocity"] for s in rest), default=0)
    drift = (max(centre(s) for s in rest) - min(centre(s) for s in rest)) if rest else 0
    zero = next((s["t"] - t_last for s in S if s["t"] > t_last and s["velocity"] == 0), None)
    if v > 10: fails.append(f"velocity {v:.1f} pt/s after +1.5 s")
    if drift > 4: fails.append(f"centre drifted {drift:.1f} pt before the eraser")
    if not rest: fails.append("no samples between +1.5 s and the eraser")
    return verdict(fails, f"eraser at +{(t_er - t_last) if t_er else float('nan'):.2f} s, max velocity {v:.1f} pt/s and centre drift "
                          f"{drift:.2f} pt in [+1.5 s, eraser), velocity exactly 0 from +{zero if zero is None else round(zero, 2)} s")


@case("LC4", ("lc",), expect="burst of 15 words: anchor eases, no step > 700·Δt, every sample velocity ≤ 700")
def lc4():
    """A burst: taken up elastically, never faster than vMax."""
    fresh()
    show("one two three")
    time.sleep(1.0)
    S, _ = drive([(0.0, lambda: caption("one two three " + " ".join(WORDS[:15])))], 3.0)
    vmax = max(s["velocity"] for s in S)
    fast, _ = motion_faults(S)
    fails = []
    if vmax > V_MAX + 1: fails.append(f"velocity {vmax:.0f}")
    if fast: fails.append(f"{len(fast)} step(s) over vMax, first {fast[0]}")
    return verdict(fails, f"max velocity {vmax:.0f} pt/s, {len(S)} samples, dropped {S[-1]['dropped']}")


@case("LC5", ("lc",), expect="\"fix the build today\" → \"fix it today\": corrections +1, ghosts [the, build] within 0.3 s, [] after 0.6 s, correcting [] after 2.7 s, reflowing > 0 then < 0.5 within 1.6 s, centre glides")
def lc5():
    """A correction that shortens the line: ghosts, swap, reflow, a glide."""
    fresh()
    show("fix the build today")
    time.sleep(1.2)
    c0 = lc()["corrections"]
    S, fired = drive([(0.0, lambda: caption("fix it today"))], 3.2)
    upd = [s for s in S if s["words"] == 3]
    if not upd:
        return "FAIL", "the correction never reached the band"
    tu = upd[0]["t"]
    early = [s["ghosts"] for s in S if tu <= s["t"] <= tu + 0.3]
    late_g = [s["ghosts"] for s in S if s["t"] >= tu + 0.6 and s["ghosts"]]
    late_c = [s["correcting"] for s in S if s["t"] >= tu + 2.7 and s["correcting"]]
    rf0 = max((s["reflowing"] for s in S if tu <= s["t"] <= tu + 0.3), default=0)
    rf16 = [s["reflowing"] for s in S if s["t"] >= tu + 1.6]
    jumps = [(b["t"], round(centre(b) - centre(a), 1)) for a, b in zip(upd, upd[1:])
             if abs(centre(b) - centre(a)) > V_MAX * (b["t"] - a["t"] + JITTER) + 5]
    dc = S[-1]["corrections"] - c0
    fails = []
    if dc != 1: fails.append(f"corrections +{dc}")
    if ["the", "build"] not in early: fails.append(f"ghosts within 0.3 s {early[:3]}")
    if late_g: fails.append(f"ghosts still {late_g[0]} after 0.6 s")
    if late_c: fails.append(f"correcting still {late_c[0]} after 2.7 s")
    if rf0 <= 0: fails.append("no reflow")
    if not rf16 or rf16[0] >= 0.5: fails.append(f"reflowing {rf16[:1]} at +1.6 s")
    if jumps: fails.append(f"centre stepped {jumps[:2]}")
    return verdict(fails, f"corrections +{dc}, ghosts {early[:1]}, reflowing {rf0:.1f} → {rf16[:1]} at +1.6 s, update seen {tu - fired[0]:.2f} s after the POST")


@case("LC6", ("lc",), expect="\"500\" → \"five hundred\": corrections +2, ghosts [\"500\"]")
def lc6():
    """A correction that lengthens the line."""
    fresh()
    show("I owe you 500 dollars")
    time.sleep(1.2)
    c0 = lc()["corrections"]
    S, _ = drive([(0.0, lambda: caption("I owe you five hundred dollars"))], 1.0)
    upd = [s for s in S if s["words"] == 6]
    if not upd:
        return "FAIL", "the correction never reached the band"
    early = [s["ghosts"] for s in upd if s["t"] <= upd[0]["t"] + 0.3]
    dc = S[-1]["corrections"] - c0
    fails = []
    if dc != 2: fails.append(f"corrections +{dc}")
    if ["500"] not in early: fails.append(f"ghosts {early[:3]}")
    return verdict(fails, f"corrections +{dc}, ghosts {early[:1]}")


@case("LC7", ("lc",), expect="revision past the dropped words: dropped 0, words 3, centred at once (velocity 0 on the first sample), ghosts []")
def lc7():
    """A revision that reaches back past what already left the band: a fresh centred line."""
    fresh()
    long = " ".join((WORDS * 2)[:30])
    show(long)
    if not wait_for(lambda: lc()["dropped"] >= 3, 4.0, 0.05):
        return "SKIP", f"the 30-word line never dropped 3 words (dropped {lc()['dropped']})"
    d0 = lc()["dropped"]
    caption("brand new line")
    S = sample(0.8)
    upd = [s for s in S if s["words"] == 3]
    if not upd:
        return "FAIL", "the revision never reached the band"
    s0 = upd[0]
    off = centre(s0) - mid(s0)
    fails = []
    if s0["dropped"] != 0: fails.append(f"dropped {s0['dropped']}")
    if s0["velocity"] > 0.5: fails.append(f"velocity {s0['velocity']:.0f} on the first sample")
    if abs(off) >= 3: fails.append(f"centre off by {off:.0f} pt on the first sample")
    if s0["ghosts"]: fails.append(f"ghosts {s0['ghosts']}")
    return verdict(fails, f"dropped before {d0}; first sample: dropped {s0['dropped']}, anchor {s0['anchor']:.0f}, "
                          f"velocity {s0['velocity']:.0f}, centre off {off:.0f}, corrections {s0['corrections']}")


@case("LC7b", ("lc",), expect="change only inside the dropped region: corrections unchanged, anchor continuous")
def lc7b():
    """A revision confined to words already gone: nothing visible happens."""
    fresh()
    words = (WORDS * 2)[:30]
    show(" ".join(words))
    if not wait_for(lambda: lc()["dropped"] >= 2, 4.0, 0.05):
        return "SKIP", "the 30-word line never dropped 2 words"
    time.sleep(0.5)
    c0 = lc()["corrections"]
    changed = ["THOSE"] + words[1:]
    S, _ = drive([(0.3, lambda: caption(" ".join(changed)))], 1.3)
    fast, up = motion_faults(S)
    dc = S[-1]["corrections"] - c0
    fails = []
    if dc: fails.append(f"corrections +{dc}")
    if fast or up: fails.append(f"anchor jumped {(fast + up)[:2]}")
    return verdict(fails, f"dropped {S[0]['dropped']} → {S[-1]['dropped']}, corrections +{dc}, anchor {S[0]['anchor']:.1f} → {S[-1]['anchor']:.1f}")


@case("LC8", ("lc",), expect="tail punctuation flicker and mid-line case/punctuation commits: corrections unchanged, ghosts []")
def lc8():
    """Punctuation and capitals are not corrections (LCS on case-folded stems)."""
    fresh()
    show("hello world how are you")
    time.sleep(0.8)
    c0 = lc()["corrections"]
    seq = [("hello world how are you.", ""), ("hello world how are you", ""), ("hello world how are you?", ""),
           ("hello world. How are you?", ""), ("Hello, world.", "How are you?"), ("Hello, world. How are you?", "")]
    ev = [(0.3 * i, (lambda t=t, p=p: caption(t, p))) for i, (t, p) in enumerate(seq)]
    S, _ = drive(ev, 0.3 * len(seq) + 0.8)
    ghosts = [s["ghosts"] for s in S if s["ghosts"]]
    dc = S[-1]["corrections"] - c0
    fails = []
    if dc: fails.append(f"corrections +{dc}")
    if ghosts: fails.append(f"ghosts {ghosts[0]}")
    return verdict(fails, f"{len(seq)} revisions, corrections +{dc}, {len(ghosts)} sample(s) with ghosts")


@case("LC9", ("lc",), expect="append-only ×30: corrections 0; each appended word's opacity starts < 0.1 and reaches its target within 0.6 s")
def lc9():
    """Appending is never a correction; each new word fades in."""
    fresh()
    starts, reach, t_add = {}, {}, {}
    t0 = time.time()
    for k in range(30):
        caption(" ".join(WORDS[:k + 1]))
        t_add[k] = time.time()
        end = t_add[k] + 0.3
        while time.time() < end:
            t_req = time.time(); s = lc(); now = (t_req + time.time()) / 2   # the app answered in between
            for i in list(t_add):
                vis = i - s["dropped"]
                if s["words"] <= i or not 0 <= vis < len(s["opacity"]):
                    continue
                op = s["opacity"][vis]
                if i not in starts:
                    starts[i] = op
                if i not in reach and op >= 0.9:        # 90 % of the committed target 1.0
                    reach[i] = now - t_add[i]
            time.sleep(0.03)
    tail, t_tail = [], time.time()
    while time.time() - t_tail < 1.0:   # the last words' fade-ins, each sample stamped when it was read
        t_req = time.time(); s = lc(); s["at"] = (t_req + time.time()) / 2
        tail.append(s); time.sleep(0.03)
    for s in tail:
        for i in t_add:
            vis = i - s["dropped"]
            # 2026-09-26 (batch 5): this used `time.time()` *after* the whole second of sampling, so the
            # last word always read ≈ 1.3 s (the "29: 1.39" of the first run) — the sample's own time now
            if i not in reach and s["words"] > i and 0 <= vis < len(s["opacity"]) and s["opacity"][vis] >= 0.9:
                reach[i] = s["at"] - t_add[i]
    corr = tail[-1]["corrections"]
    hot = {i: v for i, v in starts.items() if v >= 0.1}
    slow = {i: round(v, 2) for i, v in reach.items() if v > 0.65}
    missing = [i for i in t_add if i not in reach]
    fails = []
    if corr: fails.append(f"corrections {corr}")
    # read straight after the POST: one 60 Hz frame of τ 0.26 is 0.06, so < 0.1 is measurable
    if hot: fails.append(f"{len(hot)} word(s) started at ≥ 0.1, e.g. {list(hot.items())[:3]}")
    # τ fadeIn 0.22 puts 90 % at 0.51 s (0.26 put it at 0.60, on the limit); asked ≤ 0.65 s
    if slow: fails.append(f"{len(slow)} word(s) slower than 0.65 s to 90 %: {list(slow.items())[:3]}")
    if missing: fails.append(f"{len(missing)} word(s) never reached 90 %")
    worst = max(reach.values()) if reach else float("nan")
    return verdict(fails, f"corrections {corr}, start opacity max {max(starts.values()) if starts else 'n/a'}, "
                          f"slowest to 90 % {worst:.2f} s over {len(reach)}/{len(t_add)} words")


@case("LC10", ("lc",), expect="{on:false}: open flips at once, words 0 after 0.6 s; reopen within 0.15 s is not reset by the fade's completion")
def lc10():
    """Close, and close-then-reopen inside the fade."""
    fresh()
    show("one two three")
    time.sleep(0.4)
    caption_off()
    t = wait_for(lambda: not lc()["open"], 0.3, 0.01)
    time.sleep(0.6)
    a = lc()
    show("one two three")
    time.sleep(0.4)
    caption_off()
    time.sleep(0.1)
    caption("four five")
    time.sleep(0.7)
    b = lc()
    fails = []
    if not t: fails.append("open still true 0.3 s after {on:false}")
    if a["words"] != 0: fails.append(f"words {a['words']} 0.6 s after close")
    if not b["open"] or b["words"] != 2: fails.append(f"after reopen: open {b['open']}, words {b['words']}")
    return verdict(fails, f"after close: open {a['open']} words {a['words']}; after reopen at 0.1 s: open {b['open']} "
                          f"words {b['words']} (the panel's alpha is not in describe(): a fade that ends at 0 over a reopened band is invisible here)")


@case("LC11", ("lc",), expect="second display: the band on the screen under the pointer (needs G7 frame)")
def lc11():
    """Two displays — not observable yet."""
    return "SKIP", "needs G7 liveCaption.frame/screen"


@case("LC12", ("lc",), expect="RELAY_SHOOT never shows the band")
def lc12():
    """RELAY_SHOOT — needs a relaunch with the env var."""
    return "SKIP", "needs the app relaunched under RELAY_SHOOT (out of scope: no restarts from the runner)"


@case("LC14", ("lc",), expect="empty text while open: words 0, still open")
def lc14():
    """An empty sentence clears the line but keeps the band."""
    fresh()
    show("a b c")
    time.sleep(0.3)
    caption("")
    s = wait_for(lambda: (lambda x: x if x["words"] == 0 else None)(lc()), 1.0, 0.02)
    if not s:
        return "FAIL", f"words {lc()['words']} after an empty caption"
    return verdict([] if s["open"] else ["band closed"], f"words {s['words']}, open {s['open']}")


@case("LC15", ("lc",), expect="{text:\"a b c.\", partial:\"d e f\"}: committed 3, opacity ≈ [1,1,1,0.8,0.6,0.4] within 0.6 s; commit all → ≈ 1 within 0.8 s, corrections 0")
def lc15():
    """The provisional tail is drawn as a ramp and solidifies when committed."""
    fresh()
    target = [1, 1, 1, 0.8, 0.6, 0.4]
    S, _ = drive([(0.0, lambda: caption("a b c.", "d e f"))], 1.3)
    S = [s for s in S if s["words"] == 6]
    if not S:
        return "FAIL", "the band never showed 6 words"
    t0 = S[0]["t"]
    at06 = next((s for s in S if s["t"] >= t0 + 0.6), S[-1])
    end = S[-1]
    err06 = max(abs(a - b) for a, b in zip(at06["opacity"], target))
    errE = max(abs(a - b) for a, b in zip(end["opacity"], target))
    S2, _ = drive([(0.0, lambda: caption("a b c. d e f"))], 1.0)
    t1 = next((s["t"] for s in S2 if s["committed"] == 6), None)
    at08 = next((s for s in S2 if t1 is not None and s["t"] >= t1 + 0.8), S2[-1])
    fails = []
    if S[0]["committed"] != 3: fails.append(f"committed {S[0]['committed']}")
    if err06 > 0.1: fails.append(f"opacity {at06['opacity']} at +0.6 s")   # τ 0.26 → 90 % there
    if errE > 0.03: fails.append(f"settled opacity {end['opacity']}")
    if t1 is None: fails.append("the commit never reached the band")
    if min(at08["opacity"]) < 0.95: fails.append(f"opacity {at08['opacity']} 0.8 s after the commit")
    if S2[-1]["corrections"]: fails.append(f"corrections {S2[-1]['corrections']}")
    return verdict(fails, f"+0.6 s {at06['opacity']} (max err {err06:.2f}), settled {end['opacity']}; after commit +0.8 s {at08['opacity']}, "
                          f"corrections {S2[-1]['corrections']}")


@case("LC16", ("lc",), expect="eraser after 5 s at ≈260 pt/s; visible centre ±80 while dropped grows; a new word freezes the front; after a full wipe the next word is a fresh centred line with eraseFront null")
def lc16():
    """The eraser, the re-centring behind it, the freeze, and the fresh line after a full wipe."""
    fresh()
    w = WORDS[:6]
    ev = [(0.3 * k, (lambda k=k: caption(" ".join(w[:k + 1])))) for k in range(6)]
    S, fired = drive(ev, 0.3 * 5 + ERASE_AFTER + 2.5)
    fails, notes = [], []
    er = [s for s in S if s["eraseFront"] is not None]
    if not er:
        return "FAIL", "the eraser never started"
    t_er = er[0]["t"] - fired[-1]
    v = slope(er)
    notes.append(f"eraser at +{t_er:.2f} s, {v and round(v)} pt/s")
    if not ERASE_AFTER - 0.1 <= t_er <= ERASE_AFTER + 0.3: fails.append(f"eraser at +{t_er:.2f} s")
    if v is None or abs(v - 260) > 0.15 * 260: fails.append(f"front speed {v}")
    # the re-centring while words drop out on the left
    S2 = sample_until(lambda s: s["dropped"] >= 2, 8.0)
    off = [abs(centre(s) - mid(s)) for s in er + S2 if s["eraseFront"] is not None and s["eraseFront"] + EDGE_HALF > 0]
    notes.append(f"dropped {S2[-1]['dropped']}, visible-centre offset max {max(off) if off else 0:.0f} pt over {len(off)} samples")
    if S2[-1]["dropped"] < 1: fails.append("nothing dropped behind the eraser")
    if off and max(off) > 80: fails.append(f"visible centre off by {max(off):.0f}")
    # a new word freezes the front
    S3, _ = drive([(0.0, lambda: caption(" ".join(w + ["golf"])))], 1.5)
    rises = [round(b["eraseFront"] - a["eraseFront"], 1) for a, b in zip(S3, S3[1:])
             if a["eraseFront"] is not None and b["eraseFront"] is not None and a["dropped"] == b["dropped"]
             and b["eraseFront"] - a["eraseFront"] > 0.5]
    if rises: fails.append(f"front advanced after a new word: {rises[:3]}")
    if S3[-1]["eraseFront"] is None: fails.append("front vanished on a new word (should freeze in place)")
    # full wipe, then a fresh line
    done = wait_for(lambda: (lambda s: s if s["eraseFront"] is not None and s["eraseFront"] >= s["lineWidth"] else None)(lc()), 15, 0.05)
    if not done:
        fails.append("the eraser never wiped the whole line")
        return verdict(fails, "; ".join(notes))
    caption(" ".join(w + ["golf", "hotel"]))
    s0 = wait_for(lambda: (lambda s: s if s["words"] == 8 else None)(lc()), 1.0, 0.02)
    if not s0:
        fails.append("the word after the wipe never reached the band")
        return verdict(fails, "; ".join(notes))
    offc = centre(s0) - mid(s0)
    notes.append(f"fresh line: eraseFront {s0['eraseFront']}, centre off {offc:.1f}, velocity {s0['velocity']:.0f}")
    if s0["eraseFront"] is not None: fails.append(f"eraseFront {s0['eraseFront']:.0f} on the fresh line")
    if abs(offc) >= 3: fails.append(f"fresh line off centre by {offc:.0f}")
    if s0["velocity"] > 0.5: fails.append(f"fresh line moving at {s0['velocity']:.0f}")
    return verdict(fails, "; ".join(notes))


@case("LC17", ("lc",), expect="gentle correction: corrections +1, the eraser keeps sweeping (eraseFront still increasing)")
def lc17():
    """A batch correction behind him does not count as him speaking again."""
    fresh()
    show("we deploy on friday")
    if not wait_for(lambda: lc()["eraseFront"] is not None, ERASE_AFTER + 1.5, 0.05):
        return "FAIL", "the eraser never started"
    time.sleep(0.3)
    c0 = lc()["corrections"]
    S, _ = drive([(0.0, lambda: caption("we deploy on Monday", gentle=True))], 1.2)
    dc = S[-1]["corrections"] - c0
    v = slope(S)
    fails = []
    if dc != 1: fails.append(f"corrections +{dc}")
    if v is None or v < 150: fails.append(f"front speed after the gentle update {v}")
    return verdict(fails, f"corrections +{dc}, front {S[0]['eraseFront']} → {S[-1]['eraseFront']} ({v and round(v)} pt/s); the paler tint is not in describe()")


@case("LC18", ("lc",), expect="timing precision needs G8's server-side script/trace, two displays G7's frame")
def lc18():
    """Frame-accurate timing — not observable yet."""
    return "SKIP", "needs G8 (/test/live-caption script + trace)"
