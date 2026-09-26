# Test plan run — 2026-09-26 15:44

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 7

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TR21 | **PASS** | 4 | agent exited to the shell → '⛔️ refused', no delivery row in the outbox, still pastable (plan §3.11: today the row is written at commit) | guarded=True; refused=True; typed into zsh=False; outbox rows +0; lastDelivery.to=None |
| TD1 | **PASS** | 0 | POST /bind {tty: ttys999} (no such tty) → 409; nothing bound, no sentence lost | 409 no terminal on ttys999 |
| TD2 | **PASS** | 7 | two sentences held while unbound → the bind delivers both (or says the first was replaced) | to1=held to2=held held-after-two=True; hold lines=2; after bind: ALFA in witness=True, BRAVO in witness=True; replacement said in log=False |
| TD14 | **PASS** | 1 | restoring a tty that is no Terminal.app tab (IDE-like pty) → /bind refuses (409); no sentence lost | 409 for ttys014 (no terminal on ttys014); ps: Ss+  cat |
| TD15 | **PASS** | 21 | a shell behind `script -q /dev/null zsh` is refused by the guard; `touch` does not run | tab ttys014 bind 200; guard saw foreground=['script']; refused=True; to=None; rows=0; touch ran=False |
| TD16 | **PASS** | 21 | a sentence starting with q sent into `less` does not reach the shell underneath; `touch` does not run | tab ttys013 bind 200; guard saw foreground=['less']; to=None; touch ran=False |
| TR21 | **PASS** | 24 | bound tab back at a shell prompt → ⛔️ refused, no outbox delivery row, binding kept | B=ttys013; refused=True; delivered=False; to=None; rows=[]; bound after=ttys013 |
