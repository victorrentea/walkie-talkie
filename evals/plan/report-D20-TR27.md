# Test plan run — 2026-09-26 14:31

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR27 | **PASS** | 41 | 50 start/cancel cycles within a second each: every start opens the mic, every cancel keeps its audio, no mic-<epoch>.wav collision or leftover, pid unchanged | 50/50 opened, 50/50 quiet after cancel, 50 'audio kept', 0 error line(s), 0 leftover mic-*.wav, 10 back-to-back starts in the same second, pid 75172→75172, 40 s |
