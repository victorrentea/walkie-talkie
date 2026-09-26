# Test plan run — 2026-09-26 13:31

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 5 · FAIL 1 · PASS 4

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG8 | **BUG** | 14 | 🔼← F11 in the settle throws the sentence away. Predicted defect (§3.2, R2): `🗑️ Cancelled`, then the words are delivered anyway (`📦 delivery` after the cancel line) | cancelled, then delivered — cancel line=True, lastDelivery={'to': 'terminal:ttys012', 'at': '2026-09-26T10:31:55.823Z', 'kind': 'route', 'via': 'elevenlabs-scribe'}, witness got 81 chars · sent forward-right@3.558s forward-right@10.751s forward-left@10.859s |
| TG9 | **BUG** | 12 | F11 in the settle of a spawn sentence throws it away. Predicted defect: delivered anyway, and to the bound terminal / caret, not `spawn:` (the cancel cleared the spawn flag only) | cancel line=True, delivered after it=True, to='terminal:ttys012' · sent forward-up@2.289s forward-right@8.587s forward-left@8.702s |
| TG13 | **BUG** | 12 | 🔼→ over a bound clean sentence redirects it: `↪️ redirected` and `lastDelivery.to == terminal:…`. Predicted defect: the flash says so but the clean sentence still lands at the caret | redirect line=True, lastDelivery.to='caret' (bound ttys012), sink got 55 chars · sent back-click@3.239s forward-right@9.180s back-click@10.299s |
| TG18 | **BUG** | 11 | an unbound sentence bound during its upload goes to the terminal just bound. Predicted defect (§3.3): the chip said `bind to send`, the destination latched at mic close, `lastDelivery.to == caret` | chip at the start «Prompting → ￼... \| bind to send»; lastDelivery.to='caret' (bound ttys012 during the upload) · sent forward-right@2.913s forward-right@9.342s |
| TG20 | **PASS** | 15 | positive control: 🔽↓ F12 in the settle → `lastDelivery.to == held`, `awaitingBind`; the next bind delivers it to the terminal and clears `awaitingBind` | after F12: to='held', awaitingBind=True; after the bind: released=True, to='terminal:ttys012'; witness 229 chars · sent forward-right@3.610s forward-right@10.012s back-down@10.124s |
| TG40 | **BUG** | 13 | 🔽 in the settle of a relay prompt says the words are in flight (or nothing). Predicted defect: the misleading `Back click ignored — finish the sentence you are dictating first` banner | refused line=True (before the delivery=True), state just after: listening=False settling=True, a new sentence opened=False · sent forward-right@3.282s forward-right@9.713s back-click@9.823s |
| B2 | **PASS** | 14 | a VAD commit → '💬 live correction: … → scribe_v2', live.corrections ≥ 1, elevenCost.total grows, band corrections ≥ 0 | correction started True, applied True (0.81 s), live.corrections 1, cost 0.06177 → 0.06224, band corrections 0 words 11 |
| B3 | **FAIL** | 21 | stop while a correction is in flight (500 after 4 s, then the real retry) → no update after close, no crash (pid unchanged), the sentence delivers | no correction started within 10 s of the clip |
| B4 | **PASS** | 18 | correction failure (500 ×2, the call and its retry) → 'after 5 s' hold, cut unchanged, the next upload ≥ 5 s later covers the longer span | hold 5.36 s, cut after the failure 0, spans [6.6, 12.7] |
| B5 | **PASS** | 12 | elevenCost.total grows by (live s × 0.39 × (1 + 0.2 with keyterms) + batch s × 0.22)/3600 (±25 %) | Δ $0.001721 vs expected $0.001736 (recording 7.1 s, corrections 6.2 s, keyterms 50); label $0.07 → $0.07 |
