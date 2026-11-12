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

Re-run after any change to `AgentRules.text` (and raise `AgentRules.version`).
