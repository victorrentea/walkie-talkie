# Test plan run — 2026-09-26 15:04

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

FAIL 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TL25 | **FAIL** | 1355 | 10-min ceiling on real audio at 600±1 s; record `via` (the 20 s request timeout on a 19 MB WAV) | ceiling at 600.2 s after the chord, delivered None s later via None; ElevenLabs upload 48.65 s; fallback False |
