# Test plan run — 2026-09-26 14:14

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL1 | **BUG** | 130 | orphan flush 121 s after /test/area mid-sentence: dictationStartedAt stays non-null (today: null + 'releasing 1 shot(s)' while listening) | bound ttys020; area at t=0, flush seen at 120.1 s; at 121 s listening=True dictationStartedAt=None released=yes witness got 133 chars — envelope wiped while the sentence is still open; invariants ok |
