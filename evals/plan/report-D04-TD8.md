# Test plan run — 2026-09-26 13:40

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD8 | **BUG** | 127 | a sentence open > 120 s with a wheel shot keeps its envelope; no bare screenshot message goes to A | orphan flush sent the shot alone mid-sentence — /test/area 200; flush line=at +120s; listening=True; dictationStartedAt 2026-09-26T10:40:45.714Z → None; screenshot rows=1 to=[None]; witness bytes=133 |
