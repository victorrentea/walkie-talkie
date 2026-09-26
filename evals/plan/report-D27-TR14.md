# Test plan run — 2026-09-26 14:46

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR14 | **PASS** | 30 | helper killed mid-decode → .failed with the audio, app alive, helper restarts, the next sentence delivers | failed line True, recoverable True, app pid 75172 → 75172, helper pid 59997 → 6199 alive True, next sentence via local-fallback |
