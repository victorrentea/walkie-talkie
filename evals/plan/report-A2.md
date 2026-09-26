# Test plan run — 2026-09-26 13:08

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 2 · FAIL 4 · PASS 12 · SKIP 4

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| LC1 | **PASS** | 2 | first word centred: \|centre − bandWidth/2\| < 3, velocity 0, opacity 0 → 0.4 within 0.5 s, never anchor ≥ bandWidth − 5 | centre off 0.00 pt, max velocity 0.0, opacity 0 → [0.35] at +0.5 s → 0.4, bandWidth 1728 |
| LC2 | **FAIL** | 21 | growth at 0.4 s/word for 20 s: centre ±80 until line > bandWidth − 96, then anchor + shownWidth ≤ bandWidth − 48 + 2; \|Δanchor\| ≤ 700·Δt + 2; anchor rises only by a drop | centre off by 109 while narrow; 212/308 samples past the right margin (max 271 pt) — 308 samples, wide from t=6.462, max centre offset 108.5 pt while narrow, dropped 32, max velocity 608 |
| LC3 | **PASS** | 9 | pause: velocity → 0 within 1.5 s of the last word, centre unchanged until the eraser starts at 5.0 s | eraser at +5.05 s, max velocity 4.2 pt/s and centre drift 1.89 pt in [+1.5 s, eraser), velocity exactly 0 from +2.4 s |
| LC4 | **PASS** | 5 | burst of 15 words: anchor eases, no step > 700·Δt, every sample velocity ≤ 700 | max velocity 700 pt/s, 32 samples, dropped 0 |
| LC5 | **PASS** | 5 | "fix the build today" → "fix it today": corrections +1, ghosts [the, build] within 0.3 s, [] after 0.6 s, correcting [] after 2.7 s, reflowing > 0 then < 0.5 within 1.6 s, centre glides | corrections +1, ghosts [['the', 'build']], reflowing 129.8 → [0] at +1.6 s, update seen 0.01 s after the POST |
| LC6 | **PASS** | 3 | "500" → "five hundred": corrections +2, ghosts ["500"] | corrections +2, ghosts [['500']] |
| LC7 | **FAIL** | 1 | revision past the dropped words: dropped 0, words 3, centred at once (velocity 0 on the first sample), ghosts [] | centre off by -802 pt on the first sample — dropped before 13; first sample: dropped 0, anchor -69, velocity 0, centre off -802, corrections 3 |
| LC7b | **PASS** | 2 | change only inside the dropped region: corrections unchanged, anchor continuous | dropped 13 → 13, corrections +0, anchor -69.5 → -69.5 |
| LC8 | **PASS** | 4 | tail punctuation flicker and mid-line case/punctuation commits: corrections unchanged, ghosts [] | 6 revisions, corrections +0, 0 sample(s) with ghosts |
| LC9 | **FAIL** | 11 | append-only ×30: corrections 0; each appended word's opacity starts < 0.1 and reaches its target within 0.6 s | 2 word(s) slower than 0.65 s to 90 %: [(2, 0.65), (29, 1.39)] — corrections 0, start opacity max 0.05, slowest to 90 % 1.39 s over 30/30 words |
| LC10 | **PASS** | 3 | {on:false}: open flips at once, words 0 after 0.6 s; reopen within 0.15 s is not reset by the fade's completion | after close: open False words 0; after reopen at 0.1 s: open True words 2 (the panel's alpha is not in describe(): a fade that ends at 0 over a reopened band is invisible here) |
| LC11 | **SKIP** | 0 | second display: the band on the screen under the pointer (needs G7 frame) | needs G7 liveCaption.frame/screen |
| LC12 | **SKIP** | 0 | RELAY_SHOOT never shows the band | needs the app relaunched under RELAY_SHOOT (out of scope: no restarts from the runner) |
| LC14 | **PASS** | 1 | empty text while open: words 0, still open | words 0, open True |
| LC15 | **PASS** | 3 | {text:"a b c.", partial:"d e f"}: committed 3, opacity ≈ [1,1,1,0.8,0.6,0.4] within 0.6 s; commit all → ≈ 1 within 0.8 s, corrections 0 | +0.6 s [0.9, 0.9, 0.9, 0.72, 0.54, 0.36] (max err 0.10), settled [0.99, 0.99, 0.99, 0.79, 0.59, 0.4]; after commit +0.8 s [1, 1, 1, 0.99, 0.98, 0.97], corrections 0 |
| LC16 | **FAIL** | 17 | eraser after 5 s at ≈260 pt/s; visible centre ±80 while dropped grows; a new word freezes the front; after a full wipe the next word is a fresh centred line with eraseFront null | fresh line moving at 109 — eraser at +5.03 s, 262 pt/s; dropped 2, visible-centre offset max 52 pt over 15 samples; fresh line: eraseFront None, centre off 0.0, velocity 109 |
| LC17 | **PASS** | 7 | gentle correction: corrections +1, the eraser keeps sweeping (eraseFront still increasing) | corrections +1, front -749.0261869278038 → -455.0527777586831 (261 pt/s); the paler tint is not in describe() |
| LC18 | **SKIP** | 0 | timing precision needs G8's server-side script/trace, two displays G7's frame | needs G8 (/test/live-caption script + trace) |
| TD21 | **SKIP** | 13 | a bound tab closed and its tty reused by a new tab within 10 s → the binding does not move to the stranger | tty not reused (ttys003 → ttys005); after 11 s bound=ttys003 |
| TD29 | **BUG** | 5 | unbind during the hold of a sentence bound to A → words land in A, nothing held for a later B | sentence for A held by the unbind and delivered to B — unbind at +0.1s; commit +0.90s vs unbind done; to=held; held=True; in A=False; in B after binding it=True |
| TD31 | **PASS** | 2 | /test/dictation unbound → lastDelivery.to=='held', awaitingBind, no outbox row; a bind then delivers it | to=held awaitingBind=True rows while held=0; after bind: to=terminal:ttys005 rows=['terminal:ttys005'] outbox agrees with lastDelivery=True awaitingBind=False (the route never reaches latchedAtCaret — real unbound speech is TD3) |
| TR20 | **BUG** | 7 | terminal closed mid-sentence → the sentence is held (or pasted), no 'delivered' row for the dead tty | delivered-row for a dead tty, sentence lost — B=ttys006 closed while listening; to=terminal:ttys006; rows=['terminal:ttys006']; gone logged=True; bound after=None; awaitingBind=False |
