# Test plan run — 2026-09-26 13:11

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 1 · SKIP 4

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG19 | **BUG** | 6 | a rebind to B while A's prompt panel is held: the plan's documents imply A (the panel shows A). Predicted defect (R11): `commit` reads the target at commit time — delivered to B | panel up 14 ms, rebind at +0.014 s; lastDelivery.to='terminal:ttys007' (A=ttys006, B=ttys007); B's witness got 80 chars |
| TG21 | **SKIP** | 0 | adopted Wispr sentence: 🔽← → `nothing to cancel`, Wispr keeps listening | T-G21: adopted hand-started Wispr sentences (`/test/wispr-handsfree {hand: true}`) are out of scope for this suite (Wispr Flow is out of scope of the plan) — not automated here |
| TG22 | **SKIP** | 0 | adopted Wispr sentence: 🔽 → shutter | T-G22: adopted hand-started Wispr sentences (`/test/wispr-handsfree {hand: true}`) are out of scope for this suite (Wispr Flow is out of scope of the plan) — not automated here |
| TG23 | **SKIP** | 0 | adopted Wispr sentence: 🔽→ → keycode 36 in the sink while `wisprHearing` | T-G23: adopted hand-started Wispr sentences (`/test/wispr-handsfree {hand: true}`) are out of scope for this suite (Wispr Flow is out of scope of the plan) — not automated here |
| TG24 | **SKIP** | 0 | adopted Wispr sentence: 🔼 / 🔼→ → nothing | T-G24: adopted hand-started Wispr sentences (`/test/wispr-handsfree {hand: true}`) are out of scope for this suite (Wispr Flow is out of scope of the plan) — not automated here |
