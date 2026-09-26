# Test plan run — 2026-09-26 16:59

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

PASS 2

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG4 | **PASS** | 17 | 🔽 click on a cold local model opens the microphone within 0.5 s as a clean dictation (context shot skipped), the second 🔽 click stops it, and the words arrive at the caret once the model is up. Before: the click was banked, the resumed start was a caret prompt with a context shot, and the second click was the shutter | mic opened 0.34 s after the click (model still loading=True); clean start=True; context shot captured=False skipped=False; second click stop=True shutter=False; words landed: to=caret via=local-whisper, sink got 55 chars · sent back-click@3.587s back-click@11.338s · helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill) |
| TG41 | **PASS** | 17 | an engine switch mid-sentence on a cold local model is refused like any other: the gesture opened the microphone within 0.5 s, POST /engine is refused while it records, and the words arrive through the local model once it is up. Before (R7): the gesture was banked, the switch was accepted and the dictation opened on the new engine | mic opened 0.17 s after the gesture (model still loading=True); switch to eleven-live mid-sentence accepted=False (engine now whisper); words landed in the witness (231 chars), to=terminal:ttys022 via=local-whisper; banked=False · sent forward-right@4.348s forward-right@10.931s · helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill) |
