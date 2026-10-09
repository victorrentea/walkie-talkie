# ⚡ Quick question — how fast, measured (2026-10-09)

Victor: *"a dumb mode or a quick fast mode to this walkie-talkie that will answer as fast as it
can"* — on his subscription, so through `claude -p`, not the API. `bench.py` asks six general
questions (EN + RO) three ways; low effort, no tools. Medians, 6 questions each, this Mac:

| how | first word | whole answer |
|---|---|---|
| `cold` haiku — a fresh `claude -p` per question (exit included) | 1.40 s | 2.51 s |
| `cold` opus | 1.53 s | 3.12 s |
| `warm` haiku, **Claude Code's own prompt** (`--default`, ~104k input tokens) | 1.52 s | 3.15 s |
| `warm` haiku, **lean** (QuickAsk's flags, ~700 tokens) | **0.62 s** | **1.15 s** |
| `warm` opus, lean | 0.58 s | 1.70 s |
| **`app`** — the installed relay, `POST /test/quick` (haiku, lean, warm) | **0.55 s** (max 0.67) | **1.03 s** (max 1.41) |

All six `app` answers were right, in the question's language.

- **The process, not the model, is most of the wait.** A cold `claude -p` spends ~2 s starting
  and ~2 s exiting around a ~1.5 s answer (first measurement, default prompt: 5.4–9 s whole). One
  already started answers in ~0.6 s whichever model it runs — Opus at low effort reaches its
  first word as fast as Haiku; Haiku finishes a paragraph ~0.5 s sooner.
- **The lean prompt matters as much as keeping it warm.** Claude Code's own system prompt, tool
  list and CLAUDE.md are ~104k input tokens; a fresh process pays for them on every question
  (1.52 s vs 0.62 s to the first word). `--system-prompt`, `--tools ""`, `--strict-mcp-config`,
  `--setting-sources ""` bring it to ~700.
- **One process per question**, so no history piles up over the day (Victor: *"a conversation
  history over the day … will make it slower after a while"*); the next is started the moment one
  has answered. The waiting process holds ~230 MB.
- **`--bare` cannot be used**: it skips the subscription's login (`Not logged in`).

Re-run: `evals/quick-ask/bench.py warm haiku`, `… app` (opens a reply pop-up per question).
