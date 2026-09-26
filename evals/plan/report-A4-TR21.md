# Test plan run — 2026-09-26 14:30

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 2

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR21 | **BUG** | 3 | agent exited to the shell → '⛔️ refused', no delivery row in the outbox, still pastable (plan §3.11: today the row is written at commit) | guarded=True; refused=True; typed into zsh=False; outbox rows +1; lastDelivery.to=terminal:ttys014 — a refused sentence left a delivery receipt |
| TR21 | **BUG** | 5 | bound tab back at a shell prompt → ⛔️ refused, no outbox delivery row, binding kept | refused, yet the outbox has a delivery row — B=ttys014; refused=True; delivered=False; to=terminal:ttys014; rows=['terminal:ttys014']; bound after=ttys014 |
