# Test plan run — 2026-09-26 13:25

Verdicts: **PASS** = the app does what the plan expects · **BUG** = the plan's prediction of a defect was confirmed · **FAIL** = neither the expectation nor the prediction · **SKIP** / **ERROR**.

BUG 3

| case | verdict | s | expectation | observed |
|---|---|---|---|---|
| TG3 | **BUG** | 7 | 🔼← F11 aborts a start banked on a cold local model. Predicted defect: no cancel line, and the microphone opens ~10 s later anyway (`recordWhenSourceReady` ignored by cancel) | the cancel was ignored and the banked start opened the microphone — cancel line=False; after the F11: opened in 2.0 s (F11 at +3.38 s) · sent forward-right@2.757s forward-left@3.377s · helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill) |
| TG4 | **BUG** | 9 | 🔽 click on a cold local model stays a clean dictation once the model is up (context shot skipped) and a second 🔽 click stops it. Predicted defect: the resumed start drops `clean` — a caret prompt with a context shot, and the second click is the shutter | the resumed start was a caret prompt — first click clean start=True; mic open 2.3 s later; context shot captured=True skipped=False; second click stop=False shutter=True · sent back-click@2.894s back-click@6.795s · helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill) |
| TG41 | **BUG** | 12 | an engine switch while a gesture is banked on the cold local model is refused, or drops the bank. Predicted defect (R7): accepted, and the dictation opens on the new engine when the 0.5 s poll fires (or `Wispr Flow is not running` flashes) | switch to eleven-live accepted=True; dictation opened 0.7 s after the switch on 'ElevenLabs Scribe + Live'; `Wispr Flow is not running` flash=False · sent forward-right@2.652s · helper SIGKILLed for a cold start (WT_COLD_WHISPER=kill) |
