# Test plan run — 2026-09-26 14:02

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD22-299.5 | **PASS** | 308 | bind at 299.5 s after the hold → exactly one outcome (delivered xor expired), nothing left held | bind posted at +299.50s, done +299.74s; released=True expired=False delivered=True rows=1 awaitingBind=False |
