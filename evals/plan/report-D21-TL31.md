# Test plan run — 2026-09-26 14:33

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL31 | **BUG** | 67 | a hung helper must not wedge the app; today at 35 s: settling:false, phase:transcribing, busyWhy:[transcribing], --dry-run blocked | at 35 s: settling=False phase=transcribing/ busyWhy=['transcribing']; dry-run exit 3 in 21.0 s; after SIGCONT delivered=yes lastDelivery.to=terminal:ttys014 — a hung helper wedges phase, busy and the restart gate; invariants ok |
