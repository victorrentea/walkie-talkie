# Lab night runs

- **The files at this level are the first full night run, 26/27 Sep 2026** (`report-vm-night.md`, built by
  `.merge_night.py` + `.night_notes.json` against the host's regression run). They stay as they are.
- **Every later run goes under `<YYYY-MM-DD>/`**: `report.md` (the morning report), `merged.md`, the
  per-phase `report-vm-*.md` / `run-*.log`, `notes.json`, `exploratory.md`. Screenshots stay beside the
  VM, `~/tart/night/<date>/` (on the external disk until 2026-10-30).
- `PROMPT.md` — the brief the night's Claude Code session runs. `merge.py RUN_DIR [BASE_DIR]` — one
  night against the previous one. `run-phase.sh` / `run-d.sh` — copied into the guest's `~/wt-lab/`.
- Launched by `tools/wt-night.sh start` from the LaunchAgent `tools/ro.victorrentea.wt-night.plist`
  (02:00, weekly gate). How it works, how to force, watch or disable it: `docs/vm-lab.md`, *Nightly*.
