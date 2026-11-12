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

Re-run after any change to `AgentRules.text` (and raise `AgentRules.version`).
