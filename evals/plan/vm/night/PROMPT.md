# Night run — brief for the unattended Claude Code session

You were started by `tools/wt-night.sh start` (LaunchAgent `ro.victorrentea.wt-night`, 02:00) in tmux
`wt-night`, in `/Users/victorrentea/workspace/walkie-talkie`. Nobody is watching. Victor reads the
transcript in the morning (`tmux attach -t wt-night`, or Remote Control session `wt-night`). Job:
bring the Tart guest `wt-lab` up, deploy the app he runs, run the whole test suite **inside the
guest**, fix what fails when the fix is evident, re-run, commit, have one subagent play with the app
in the guest, leave a morning report, shut the VM down.

## 0. Rules (read twice)

- Work only in this repo. Before touching anything read: `CLAUDE.md`, `docs/vm-lab.md` (whole),
  `.claude/rules/desk-testing.md`, `docs/journal.md` (its *Contents* and *Superseded* lists, plus the
  last two dated `## ` sections at the end), and the previous night's report — the newest
  `evals/plan/vm/night/<YYYY-MM-DD>/report.md`, or `evals/plan/vm/night/report-vm-night.md` if none.
- `DATE=$(date +%F)` once, now; `OUT=evals/plan/vm/night/$DATE`; `SHOTS=~/tart/night/$DATE`
  (screenshots stay beside the VM, never in git). `export TART_HOME=~/tart` in every shell.
- **Nothing synthetic on the host.** No `osascript`/System Events, no `cliclick`, no audio, no windows
  on Victor's screen. Everything goes through `tools/vm-lab.sh {up,deploy,api,sh,shot,down}`, `tart exec`
  and SSH into the guest as `docs/vm-lab.md` documents. Never `vm-lab.sh look`, never Codex/Screen Sharing.
- **Clock.** Stop starting new work at 07:00; everything finished and the VM down by 07:45. (Started
  at another hour by `WT_NIGHT_FORCE=1`? Then start + 5 h and start + 5 h 45 min.) Every command gets a
  wall-clock cap (`timeout`, a `for` loop with a bound, or a background job you check); poll long steps
  at ≤ 10-minute intervals. A step that exceeds its cap twice is marked `CAPPED` in the report and skipped.
- A permission prompt you cannot get answered (auto mode's classifier refused a call) is not to be
  worked around with variants: note it in the report and move on.
- **Never**: `pkill`/`kill`/`open` the host app (only `./relay-restart.sh`); `git stash`, `git checkout
  <path>`, `git reset` (other sessions leave uncommitted work here); two harness drivers at once — in
  the guest **one driver at a time**: a phase, a re-run or the exploratory agent, never two; audio on
  the host speakers. The host lock `~/.walkie-talkie/wispr-loop.lock` is for host runs; you take no host
  lock unless you build/restart the host app.
- If another Claude session in `~/workspace` shows `busy` in ListAgents and is editing walkie-talkie
  files you are about to touch, message it before editing; idle sessions are never messaged.
- **Local engine first.** Desk tests prefer the local model: the harness sets `whisper` as the engine
  at start, and only the ElevenLabs-specific cases (live captions, corrections, final uploads on the
  eleven engines) switch to an eleven engine and restore it afterwards. Do not set the guest's engine
  to an eleven engine yourself.
- **ElevenLabs credit cap.** On 26 Sep one host test day spent 46 % of the month's 10 000 credits,
  and the quota ran out that night. So the ElevenLabs cases run only when **≥ 3 000 credits** remain;
  otherwise they are SKIP with the reason `credit cap`, and never counted as defects. The harness
  enforces it (`WT_ELEVEN_MIN_CREDITS`, default 3000, being added alongside a fake realtime server —
  check `grep -n 'WT_ELEVEN_MIN_CREDITS\|fake' evals/plan/harness.py`). If the harness does not have it
  yet and credits are < 3000, drop `LC13,B1,B2,B3,B4,B5,TL12,TL16,TL29` from the ID lists yourself and
  list them as SKIP `credit cap` (they are the nine that failed on the quota on 26 Sep; add any case
  whose code calls `/engine` with an `eleven` id).

## 1. Pre-flight — cap 5 min

- `git status --short`, `git log --oneline -3`. Dirty tree: do not stash; note the files and work on top
  (commit only your own paths).
- Credits: month-to-date usage from the endpoint that works with our key (`/v1/user/subscription`
  refuses it: `missing_permissions user_read`):
  ```sh
  set -a; . ~/.walkie-talkie/elevenlabs.env; set +a
  S=$(( $(date -j -u -f %Y-%m-%d-%H%M%S "$(date -u +%Y-%m)-01-000000" +%s) * 1000 )); E=$(( $(date +%s) * 1000 ))
  curl -s -m 20 -H "xi-api-key: $ELEVENLABS_API_KEY" \
    "https://api.elevenlabs.io/v1/usage/character-stats?start_unix=$S&end_unix=$E&breakdown_type=model" \
    | python3 -c 'import json,sys; u=json.load(sys.stdin)["usage"]; t=sum(map(sum,u.values())); print(f"used {t:.0f} left {10000-t:.0f}")'
  ```
  (assumes the plan renews on the 1st, UTC; if the journal says otherwise, use that date). Record
  `left` as *credits before*. Never print the key.

## 2. VM up — cap 20 min

`tools/vm-lab.sh up` in the background with `timeout 1200`; poll. The agent never answers →
`tools/vm-lab.sh down`, one retry; still nothing → write the report (what failed, the tail of
`$TART_HOME/wt-lab.log`), VM down, stop.
SSH: `KH="-o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile=$SHOTS/known_hosts -o StrictHostKeyChecking=accept-new"`,
`IP=$(tart ip wt-lab)` (`mkdir -p $SHOTS` first).

## 3. Deploy — cap 15 min

- The app is the installed `/Applications/Walkie Talkie.app` (the build Victor runs). If
  `codesign --verify --strict` passes on it (it did on 27 Sep; `.warmup.wav` no longer in the bundle),
  use `tools/vm-lab.sh deploy`; otherwise the tar-over-SSH recipe in `docs/vm-lab.md` (*Traps*,
  `codesign`). Launch with `open`, never by the binary path.
- `~/.walkie-talkie/elevenlabs.env` into the guest's `~/.walkie-talkie/` over SSH, `chmod 600`.
- Repo mirror, exactly as documented:
  `COPYFILE_DISABLE=1 tar -cf - --exclude __pycache__ --exclude evals/work --exclude evals/plan/vm relay-restart.sh safe-restart.sh tools/restart_gate.py helpers evals | ssh $KH admin@$IP 'tar -C ~/wt-lab -xf -'`
  then `scp $KH evals/plan/vm/night/run-phase.sh evals/plan/vm/night/run-d.sh admin@$IP:wt-lab/`, and
  move the guest's previous results aside: `ssh … 'mv ~/wt-lab/night ~/wt-lab/night-$(date +%s) 2>/dev/null; mkdir -p ~/wt-lab/night'`
  (the scripts append to their logs).
- Check: `tools/vm-lab.sh api test/state` answers; `tools/vm-lab.sh api engine` shows the source
  (`whisper` expected once the harness has set it; record what it says before phase A).

## 4. Suite — cap 2 h 30 min

The same four phases and IDs as the 26/27 Sep run (measured: A 8 min, B 7.5, C 10, D 96). Launch each
through `tart exec` (the Automation grant belongs to `tart-guest-agent`; never via SSH), detached,
then poll `~/wt-lab/night/run-<phase>.log` over SSH for `PHASEDONE` every ≤ 10 min:

```sh
tart exec wt-lab sh -c "WT_ELEVEN_MIN_CREDITS=3000 nohup bash ~/wt-lab/run-phase.sh A 1200 '<IDS>' >/dev/null 2>&1 </dev/null & echo launched"
```

| phase | cap | IDs |
|---|---|---|
| A | 1200 | LC1,LC2,LC3,LC4,LC5,LC6,LC7,LC7b,LC8,LC9,LC10,LC11,LC12,LC14,LC15,LC16,LC17,LC18,TL2,TL3,TL4,TL6,TL7,TL23,TL27,TL33,TR17,TR21,TR28,TD1,TD2,TD4,TD5,TD6,TD10,TD13,TD14,TD15,TD16,TD19,TD20,TD21,TD29,TD31,TG19,TG21,TG22,TG23,TG24 |
| B | 1800 | TL15,TL17,TL18,TL21,TL22,TR4,TR18,TR19,TR20,TG1,TG2,TG3,TG4,TG6,TG7,TG10,TG11,TG14,TG15,TG16,TG17,TG25,TG26,TG28,TG29,TG30,TG36,TG41 |
| C | 2400 | TD3,TD24,TD26,TD27,TG8,TG9,TG12,TG13,TG18,TG20,TG40,TL10,TL11,TL12,TL13,TL14,TL16,TL29,TL30,TL32,TR9,TR13,TR23,TR24,TR25,LC13,B1,B2,B3,B4,B5 |
| D | `run-d.sh 7200 900` + IDs | TD25 TR22 TD12 TL1 TD8 TD11 TL26 TL5 TL31 TR27 TD22-298.5 TD22-299.5 TD22-300.2 TL8 TL9 TR10 TR11 TR12 TR14 TR15 TD9 TL24 TL25 |

D: `tart exec wt-lab sh -c "WT_ELEVEN_MIN_CREDITS=3000 nohup bash ~/wt-lab/run-d.sh 7200 900 TD25 TR22 … >/dev/null 2>&1 </dev/null & echo launched"`.
If `tart exec` hangs past 120 s, the child usually runs anyway — check the log over SSH before relaunching.
After each phase `scp` `report-vm-*.md` and `run-*.log` into `$OUT/`. If the clock says D cannot
finish before 06:15, cut its ID list from the end and say so.

Merge: `python3 evals/plan/vm/night/merge.py $OUT > $OUT/merged.md` (baseline = the previous dated
night, else the 26/27 Sep run). Causes per case go into `$OUT/notes.json` (`{"ID": "note", "_lab_only": [ids
whose verdict moved for a cause outside the app]}`), then re-run the merge.

## 5. Triage — cap 30 min

Every non-PASS gets one class: **credit cap/quota** · **guest speed/config** (cold model off the HDD,
frame pacing, autosend default, no Wispr, no second display — see the 26/27 Sep notes in
`.night_notes.json`) · **flaky** (re-run once in phase `X1` via `run-phase.sh X1 900 '<ids>'`; passes
→ flaky) · **defect**. For a defect, search `docs/journal.md` for the decision behind the behaviour.
- Evident fix (a regression against a documented behaviour, a crash, a wrong string, a test that
  contradicts the journal's latest rule) → fix loop.
- Anything else → **do not guess**. Write it as `Q<n>` in the report: what happens today, the two
  candidate behaviours, the trade-off (Victor, 26 Sep: *"Oriunde nu e evident ce și cum trebuie să
  corectezi … nu ezita să mă întrebi."*).

## 6. Fix loop — cap 1 h 30 min, at most 3 iterations

Edit → `swift build` → install on the host with `./relay-restart.sh --build --max-wait 900` (the idle
gate; Victor is asleep — exit 3 after 15 min means someone is dictating, exit 4 means the host app has
not answered for a minute and the gate refuses to restart it blind (2026-09-28): either way abort the
install, leave the fix uncommitted, note it; never `--force`, that flag is a human's) → redeploy to the guest (§3, app only) → re-run only the affected IDs as
`X<n>`. Keep the fix only if its IDs pass and nothing else in the re-run broke. Commit each fix
separately on the current branch, `git add` by path, message naming the case IDs, ending with

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: <contents of ~/.walkie-talkie/night/session-url — omit the line if the file is missing>
```

then `git push`. Rules from `CLAUDE.md` still hold (English-only UI, overlay changes need
`./docs/shoot-overlay-states.sh`, the rule file for the area first).

## 7. Exploratory run — cap 45 min

Runs when the guest is free: after the suite, while you triage and edit on the host; any redeploy or
re-run waits until it has handed back. Spawn **one** subagent (model Opus, description suffixed
` / Opus`) with this brief, filled in:

> Play with Walkie Talkie inside the Tart guest `wt-lab` (TART_HOME=~/tart), for at most
> 40 minutes, looking for anything odd. Real guest-side input only, through `tools/vm-lab.sh api|sh|shot`
> and `tart exec wt-lab …`: `/test/gesture`, `/test/dictation`, `/test/cancel`, `/test/recover`,
> `/bind`/`/unbind`, `/test/rebind-panel`, `/engine`, `/test/autosend`, `/test/whisper {"kill":true}`,
> `osascript` System Events inside the guest (if it is refused for lack of Accessibility, say so and use
> the routes), the menu through the AX paths in `evals/plan/codex/README.md`, corpus clips played into
> `BlackHole 2ch` in the guest (`~/wt-lab/voice-corpus/`), a restart of the guest app (`pkill` + `open` is
> fine in the guest only). An unscripted sequence of ≥ 25 actions mixing bind/unbind, dictations,
> cancel, ⌘V of the last sentence (the clipboard holds it — Q17; ⌘⇧P is gone), the rebind panel, engine switches (local engine by default; an eleven engine only
> if ≥ 3000 credits remain), autosend, killing the helper, restart. After each action:
> `GET /test/state` and `tools/vm-lab.sh shot $SHOTS/x-<nn>.png`. Look for a stuck chip, a wrong row, a
> crash (`~/.walkie-talkie/hangs/`, `~/Library/Logs/DiagnosticReports/`, errors in `relay.log`), a state
> field that contradicts the screen. Never touch the host: no host `osascript`, no Screen Sharing, no
> Codex, no audio on the host, no edits to the repo except the report. Write `$OUT/exploratory.md`: a
> numbered action log (action, state excerpt, screenshot path), then findings `X1`, `X2`… each with
> the evidence. Hand back the findings list.

Its findings go through §5 like the suite's.

## 8. Wrap-up — cap 15 min

- `tools/vm-lab.sh down` (it shuts down over SSH); confirm `tart list` shows `wt-lab` `stopped`.
- Credits again (§1) → *credits after*.
- `$OUT/report.md`: a plain-language verdict paragraph; counts BUG/FAIL/PASS/SKIP and the moved
  verdicts with their cause (from `merged.md`, the table itself below); fixes committed (hashes + IDs);
  questions `Q1…`; exploratory findings `X1…` and what became of them; time per phase; credits
  before/after; anything `CAPPED`.
- A dated entry at the end of `docs/journal.md`, in its format (`## Night run <DATE>: …`, a few
  paragraphs, numbers kept); add it to the journal's *Contents* list if the recent entries are there.
- Commit `$OUT/` and the journal by path, same trailers; `git push`.
- `echo "$DATE  PASS=<n> FAIL=<n> BUG=<n> SKIP=<n>  $(git rev-parse --short HEAD)  $OUT/report.md" >> ~/.walkie-talkie/night/history.log`
- **Do not exit.** Leave the session open so Victor can read it; your last message is the report path.
