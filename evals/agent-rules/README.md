# agent-rules — do the agents still act once the instructions left the envelope?

`python3 evals/agent-rules/run.py` — real headless sessions of Claude Code, Codex CLI and
Copilot CLI, each in an empty folder, reading the global rules `AgentRules.install()` wrote.
Six dictated sentences (three questions, one in Romanian; a task; a statement; a misheard
"cloud code"), `short` (data only) and `long` (the old envelope). Scored on what the agent ran:
`WALKIE_EVAL_LOG` makes `walkie-reply` / `walkie-dict` record the call instead of acting.

## 2026-11-12, rules v1 — 96 runs, 0 harness errors

| harness | short (rules installed) | long (old envelope) |
|---|---|---|
| Claude Code | 18/18 | 12/12 |
| Codex CLI | 18/18 | 12/12 |
| Copilot CLI | 18/18 | 12/12 |
| Copilot, `--no-custom-instructions` (negative control) | 2/6 | — |

The control fails all three questions and the misheard term and passes only the two cases that
expect nothing — the rules, not the model's guess, are what produces the calls. Claude's 30 runs
reported $7.19; Codex and Copilot ran on their subscriptions.

## 2026-11-12, rules v2 — 91 runs, 0 harness errors

The short envelope is now `[dictated 💻 · 🎤]` + `[📁=…]`, and a seventh case asks what is on the
screen — answerable only by opening `screenshot-0-800px.jpg` from the rule alone.

| harness | short (rules v2) | long (old envelope) |
|---|---|---|
| Claude Code | 21/21 | 7/7 |
| Codex CLI | 21/21 | 7/7 |
| Copilot CLI | 21/21 | 7/7 |
| Copilot, `--no-custom-instructions` (negative control) | 2/7 | — |

The screenshot case: 9/9 short across the three ("Terminal"); the control did not answer it.
Claude's 28 runs reported $6.69.

## 2026-11-13, rules v3 — areas and moves are their token alone

Three cases more, on `fixture-v3/` (copied to `$WALKIE_SHOTS/eval-agent-rules-v3` at start): a box
inlined in the words (`[📸1✂️1085,85→1350,130]`, no row), the same box as a bare footer row (Wispr),
and a `moved to` box. Only the rules say the cut-out is `screenshot-1.jpg` ("Claude Code v2.1.322").

| harness | short (rules v3) | long (old envelope) |
|---|---|---|
| Claude Code | 20/20 | 10/10 |
| Codex CLI | 20/20 | 10/10 |
| Copilot CLI | 22/30 (reply/dict first in the text; 11/20 with them last) | 10/10 |
| Copilot, `--no-custom-instructions` | 2/10 | — |

Copilot reads every box right (9/9 open `screenshot-1.jpg` or answer "right") but on the three
picture questions skips `walkie-reply` 8 times in 9. **Not v3's doing**: the same three cases with
the v2 envelope (short footer + the old long area row) score **1/9** on Copilot too
(`out-v2base-copilot`). Moving the two action bullets above the legend took the v2 cases back from
11/20 to 21/21. Claude's 30 runs reported $14.34 (first full run lost to a relative `--out`: the
helpers could not write `WALKIE_EVAL_LOG` — `--out` is made absolute now).

Re-run after any change to `AgentRules.text` (and raise `AgentRules.version`).
