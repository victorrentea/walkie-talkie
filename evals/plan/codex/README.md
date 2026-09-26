# Codex GUI scenarios S1–S6 (docs/test-plan.md §6.3)

The parts of the relay that only a GUI can reach: the menu rows (Engine, Mic, Autosend, Recover, Rebind to…), the
prompt panel's Send/Cancel, the Rebind panel, and a real ⌘⌃B from the keyboard. Codex (`codex exec`, computer use)
drives them; every step is checked against the loopback control surface (`/test/state`, `/engine`, `defaults`,
files), and the run stops at the first mismatch.

Each `S<n>.prompt` is self-contained: the preamble (no exploring, no screenshots, only the AX paths and Quartz
one-liners given, a check after every step, stop at the first mismatch, one JSON line `{step, evidence}` as the final
message), the steps with their EXPECT, and an ALWAYS block that puts the state back. `@B@` (the relay's base URL)
and `@W@` (the work dir, `$TMPDIR/wt-plan`) are placeholders the wrapper fills in, writing the result to
`$W/<S>.prompt`.

**Menu access, the same in every prompt.** The menu is opened by a real click on the status item, the Walkie Talkie
window named `Item-0` (its x read at runtime from `CGWindowListCopyWindowInfo`). Its rows are then reached as
`menu 1 of menu bar item 1 of MB of process "Walkie Talkie"`, where `MB` is `menu bar 2` when the process has two menu
bars, else `menu bar 1`. Rows are matched by name: `Autosend`, `Recover Dictation`, `Engine: …`, `Mic: …`,
`Rebind to…`. These rows are plain titles, not the gesture rows whose attributed titles carry a tab and a glyph.

## Running

Planned wrapper: `evals/plan/codex/run.sh <S>`. **It is not in the folder yet.** Writing it was refused in the
session that prepared these prompts, because it runs `codex exec --dangerously-bypass-approvals-and-sandbox`. It
needs Victor's go-ahead. What it would do: check that `busy` is false; open the witness Terminal tab(s) (the
`do script "printf …; stty -echo; exec cat >> file"` recipe from `evals/plan/looprun.sh`) under `hands-off run`;
bind them over `/bind`; fill in the placeholders; run `caffeinate -disu -t 900 &` and then Codex under
`~/bin/hands-off run "<one Romanian sentence>"`; kill caffeinate; restore the binding from before the run; stop
`cat` and close the witness windows; print the JSON line from `$W/codex-<S>.txt`.

| scenario | witness tabs | bound by the wrapper |
|---|---|---|
| S1, S2 | none | — |
| S3 | `wt-witness` → `$W/witness.txt`, tty in `$W/witness.tty` | yes |
| S4 | `wt-witness-A`, `wt-witness-B` → `$W/witness-A.txt`/`.tty`, `-B` | A, then B (1 s apart) |
| S5 | `wt-witness` | **no** (the scenario binds it with the real ⌘⌃B) |
| S6 | `wt-witness` | yes (the recovered sentence needs a terminal, never the caret) |

Preconditions: `busy` false and Victor not dictating (every scenario synthesises input, hence `hands-off`). S2 needs
Mic = Automatic. S3 needs Autosend on. S6 needs nothing recoverable (`recoverable` null), Gestures: Logi (it starts
the recording with `/test/gesture forward-right`), the Loopback device **🧪 WT Inject** with its pass-thru alive (run
the 440 Hz check first), and the corpus clip `2026-09-18/21-05-35-11l735.wav`.

## What each scenario proves, and the verdict to expect

| | proves | expected verdict |
|---|---|---|
| **S1** Engine | A pick in the `Engine: …` submenu switches the engine (`/engine.engine`). A pick made while a sentence is open (`/test/dictation/start`) is **refused**: the engine stays and `listening` stays true (`AppDelegate.setEngine`'s guard; the tick comes from the app, not the click). The same pick goes through after `/test/cancel`. It flips between `eleven-live` and `eleven`, so the local model is never loaded. | `done`. The refusal only flashes and writes no log line, so the proof is `/engine` not moving. |
| **S2** Mic | The AX tree shows `Automatic — …` plus the five devices in ladder order. A row is enabled exactly when its device is in `/engine.mic.available`, and every greyed row says `— not connected`. The rows match `/engine.mic.rows`. **A click on a greyed row does nothing** (`micSubmenu.autoenablesItems = false`). Picking `MacBook Pro Microphone` writes `mac` to `~/.walkie-talkie/mic/choice`, and `Automatic` writes `auto` back. | `done`. S2.2 is skipped when every device is plugged in. |
| **S3** Autosend + panel | The `Autosend` row toggles the `autosend` default (`defaults read ro.victorrentea.wispr-relay autosend` 1 → 0 → 1) and `state.autosend` along with it. With Autosend off, a 24-word test sentence gets the full 7 s hold. **Cancel** (116×28, bottom-right, 12 pt pad) stops delivery: nothing reaches the witness or the outbox after 9 s. **Send** (≥128×28, 8 pt left of Cancel) delivers within 1.5 s of the click, well before the countdown, with `lastDelivery.to == terminal:<witness tty>`. | `done`. The panel is invisible to screenshots (`sharingType = .none`), so it is found as the Walkie Talkie window with sharing state 0 that is at least 250×90 pt, at the visible top-left (24, menu bar + 24). |
| **S4** Rebind to… | With history B (just unbound), A, …, the row opens `RebindPanel` (660×411 pt) at the pointer. **↓ then ⏎** binds A, which proves ↓ moved off row 0. On a second opening, row 0 is A, bound and greyed: **⏎ does nothing** and the panel stays up. **⎋** closes it. | `done`. If S4.1's ORDER does not show B then A, stop: the history is not what the steps assume. |
| **S5** real ⌘⌃B | `key code 11 using {command down, control down}` with the witness tab in front binds its tty. A second press 1.5 s later unbinds it (log: `⌘⌃B on the bound target — unbinding`). **`sessionFlags == []` 300 ms after each press**, and no Ctrl-B byte reaches `cat` (the tap swallows the chord). | `done` for the toggle. A non-empty `sessionFlags` would be a stale-modifier leak from System Events' synthetic flags, which is the class of bug the check is there for. Two presses 150 ms apart (T-G37, R22) are a different case and not in S5. |
| **S6** Recover | `Recover Dictation` is greyed with nothing kept. A real recording through the Loopback, cancelled, leaves `recoverable` with the clip in it (RMS > 0.005), and the row turns live. A click logs `↩️ recovering`. | **Expected to fail at S6.4** while test-plan §3 item 9 stands: Recover always uses the local model and never loads it, so with Engine = ElevenLabs it ends with `the recovered audio produced no transcript` / "No words detected". A pass means `↩️ recovered N chars` and the clip's words in the witness. |

## Manual cleanup if Codex stops midway

Every prompt ends with an ALWAYS block, and the wrapper restores the binding and closes the witnesses on exit. If the
run was killed before either could act, do this by hand (`B=http://127.0.0.1:8917`, or whichever of 8917–8919
answers `/up`):

- **Menu or panel left open**: `osascript -e 'tell application "System Events" to key code 53'` (⎋), once per level.
- **Autosend back to 1**: `defaults read ro.victorrentea.wispr-relay autosend`. If it reads 0 (or
  `curl -s $B/test/state` says `"autosend":false`), click **Autosend** in the 🤖 menu once. Do not use
  `defaults write`: the running app keeps its own copy and would not see the change (`POST /test/autosend` is gap G6,
  not built yet).
- **Mic back to auto**: `curl -s -X POST $B/test/mic -H 'content-type: application/json' -d '{"id":"auto"}'`. Then
  check that `~/.walkie-talkie/mic/choice` reads `auto`. Also clear the S6 override:
  `… /test/mic -d '{"device":null}'`, then check that `/engine` shows `mic.override` null.
- **Engine**: `curl -s -X POST $B/engine -H 'content-type: application/json' -d '{"id":"<the engine you had>"}'`
  (S1 prints `ENG0` in its evidence).
- **A sentence left open**: when `/test/state` shows `listening` or `isRecording` true,
  `curl -s -X POST $B/test/cancel -d '{}'`. Never leave `awaitingBind` true.
- **Unbind**: `curl -s -X POST $B/unbind -d '{}'`, or rebind your own terminal:
  `… /bind -d '{"tty":"ttysNNN"}'`.
- **Witness windows**: `pkill -x cat -t ttysNNN` for each tty in `$W/*.tty`, then
  `osascript -e 'tell application "Terminal" to close (every window whose name contains "wt-witness")'`.
- **Locks and sleep**: `~/bin/hands-off end` if the 🔒 are still up. `pkill -f "caffeinate -disu -t 900"`.
