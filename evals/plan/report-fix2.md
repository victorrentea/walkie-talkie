# Test plan run — 2026-09-26 16:18

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 7 · SKIP 1

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR22 | **SKIP** | 0 | a spawn that fails re-offers the sentence; no spawn: receipt before the window exists | no route or fault switch fails a spawn (SpawnTerminal has no test hook) — needs a new gap |
| TD4 | **PASS** | 6 | bind B during the hold of a sentence bound to A → words land in A (recipient fixed when the words arrived) | A=ttys016 B=ttys017 bind B → 200 at +0.1s; commit +1.25s vs bind done; to=terminal:ttys016; in A=True, in B=False |
| TD5 | **PASS** | 7 | a restore (POST /bind {tty}) during a caret dictation leaves it at the caret (pasteMode stays true) | /bind 200; pasteMode after=True; 'caret dictation redirected' logged=False |
| TD6 | **PASS** | 6 | a restore (POST /bind {tty}) during a spawn dictation keeps the spawn (spawnPending stays true) | /bind 200; spawnPending after=True; '✨ spawn dropped' logged=False |
| TD25 | **PASS** | 8 | busy stays true from the spawn's first busy until the new window is bound (spawn is a restart blocker) | 157 samples; first busy +0.019s ('prompt on screen',); bound ttys017 at +5.49s; idle-while-unbound samples=0 |
| TD29 | **PASS** | 3 | unbind during the hold of a sentence bound to A → words land in A, nothing held for a later B | unbind at +0.1s; commit +1.50s vs unbind done; to=terminal:ttys016; held=False; in A=True; in B after binding it=False |
| TD31 | **PASS** | 2 | /test/dictation unbound → lastDelivery.to=='held', awaitingBind, no outbox row; a bind then delivers it | to=held awaitingBind=True rows while held=0; after bind: to=terminal:ttys016 rows=['terminal:ttys016'] outbox agrees with lastDelivery=True awaitingBind=False (real unbound speech is held the same way since 2026-09-26 — TG18) |
| TR22 | **PASS** | 0 | no `spawn:` receipt before the new window exists (and a failed spawn re-offers the sentence) | spawn rows=['spawn:/Users/victorrentea/workspace']; first outbox row at +5.53s; bound ttys017 at +5.49s; failure/re-offer not injectable |
