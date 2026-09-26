# Test plan run — 2026-09-26 14:41

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

FAIL 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR10 | **FAIL** | 11 | fallback with a cold model (helper SIGKILLed first) → delivered before fallbackCeiling (180 s) | delivered 0.0 s after stop via None, 'did not come up' False, helper now alive False pid None |
