# Test plan run — 2026-09-26 16:19

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 8

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TD12 | **PASS** | 16 | a bind made while a quit is deferred survives the relaunch (restore binds B, not the A read before SIGTERM) | A=ttys017 B=ttys018; bound-tty before SIGTERM=['ttys017'], after the exit=['ttys018']; quit deferred=True; restore ttys018 /bind 200; bound after=ttys018 |
| TD13 | **PASS** | 5 | restoring a tmux binding (POST /bind {client tty}) binds the pane that was bound, not the active one | client ttys020; panes ['%3', '%4']; bind with %3 active → 200 %3; bound-tty='ttys020 %3'; restore with %4 active → 200 %3 |
| TG13 | **PASS** | 16 | 🔼→ over a bound clean sentence redirects it: `↪️ redirected` and `lastDelivery.to == terminal:…`. Predicted defect: the flash says so but the clean sentence still lands at the caret | redirect line=True, lastDelivery.to='terminal:ttys017' (bound ttys017), sink got 0 chars · sent back-click@3.562s forward-right@10.405s back-click@11.517s |
| TG18 | **PASS** | 12 | an unbound sentence bound during its upload goes to the terminal just bound. Predicted defect (§3.3): the chip said `bind to send`, the destination latched at mic close, `lastDelivery.to == caret` | chip at the start «Prompting → ￼... \| bind to send»; lastDelivery.to='terminal:ttys017' (bound ttys017 during the upload) · sent forward-right@2.990s forward-right@9.442s |
| TG19 | **PASS** | 6 | a rebind to B while A's prompt panel is held: the plan's documents imply A (the panel shows A). Predicted defect (R11): `commit` reads the target at commit time — delivered to B | panel up 29 ms, rebind at +0.029 s; lastDelivery.to='terminal:ttys017' (A=ttys017, B=ttys018); B's witness got 0 chars |
| TG20 | **PASS** | 13 | 🔽↓ F12 (unbind) in the settle → the words still land in the terminal latched at the close (Victor's Q2, 2026-09-26: an unbind after the latch does not hold the sentence); nothing held | unbound by F12=True; after it: to='terminal:ttys017', awaitingBind=False, bound=None; witness 231 chars · sent forward-right@3.236s forward-right@9.513s back-down@9.622s |
| TG36 | **PASS** | 4 | undefined in the plan: 🔽→ with the *Rebind to…* panel up. Predicted: its Return activates the selected row (the witness is re-bound) | the panel's row was not activated · bound after 🔽→ = None (witness ttys017); `🔽 → — Return` line=True · sent back-right@1.997s |
| TR24 | **PASS** | 18 | bind B during the settle → the words go where the latch said at the stop (A); R11 predicts they follow the bind | A (ttys017) 231 chars, B (ttys019) 0 chars, delivery to terminal:ttys017 |
