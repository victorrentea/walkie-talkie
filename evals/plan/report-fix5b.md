# Test plan run — 2026-09-26 18:10

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 5

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL29 | **PASS** | 19 | live socket drop mid-sentence (fault live:drop) → ≤ 1 'send failed' line (today ~11/s); batch still delivers | drop injected True, 0 'send failed' lines (~0.0/s over ~8 s), batch via elevenlabs-scribe |
| TL30 | **PASS** | 13 | live socket that never opens (live:never-open stands in for no key) → the band never opens, `pending` stays ≤ 64; the batch delivers (was: band open and empty the whole sentence, `pending` unbounded — §3.14, F13) | band open 0/26 samples, max words 0, socket {'connecting'}, pending [0] → [64], batch via elevenlabs-scribe |
| LC13 | **PASS** | 12 | live integration: band words > 0 while isRecording; the band closes when listening goes false | max band words while recording 9; after stop: listening false at 0.092 s, band closed at 0.092 s |
| B1 | **PASS** | 11 | first live caption word ≤ 2 s after speech starts in the recording (plan: ≤ 1.5 s) | first band word 1.67 s after the speech in the recording (onset 1.84 s into it); 2.52 s by the old clock (play() + 0.5); warm socket (open 6 s); chunks 35 |
| B3 | **PASS** | 19 | stop while a correction is in flight (500 after 4 s, then the real retry) → no update after close, no crash (pid unchanged), the sentence delivers | fault taken True, retry after close True, correction applied after close False, pid 96476 → 96476, delivered via elevenlabs-scribe (no discard line exists in the code) |
