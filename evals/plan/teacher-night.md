# Teacher-labelling night — runbook

Continue `helpers/teacher_label.py` (Wispr Flow as the teacher, clips played into Loopback
`🎓 TO Wispr`) under supervision. Written 2026-09-26 12:40 from a read-only preflight. Nothing
in this file has been run yet except the dry-runs and the checks quoted in §0.

Progress at writing (`python3 helpers/teacher_progress.py`): **34.8 % of the audio to label**
(8.15 h of 23.40 h), 1567 clips / 14.68 h left, **≈ 19.3 h of wall clock** at the measured pace.
Tonight's queue (`--all --min-seconds 3`, max 120 s): 1529 clips, 765 min of audio, ≈ 17.2 h.

## 0. Preflight, 2026-09-26 12:40 — two blockers, both Victor's hands only

| check | result |
|---|---|
| Wispr Flow running | **NO** — no process at all (`/bin/ps -ax`). Start it with `open "/Applications/Wispr Flow.app"`, **never `open -a "Wispr Flow"`** (the nested helper quits in ~100 ms) |
| Wispr's microphone (`config.json` → `overrideAudioDeviceId`) | **`DJI Mic Mini-B83BBE (Bluetooth)`**, not `🎓 TO Wispr`. Only Victor can change it: Wispr → Settings → Microphone → `🎓 TO Wispr`, then **close the Settings window** (it holds the mic open; the preflight refuses while it is up) |
| Loopback device present | yes, `🎓 TO Wispr` in `SwitchAudioSource -a -t input` and output, index 14 |
| pass-thru alive (440 Hz played into the device, recorded from it) | alive — 440 Hz share 100 %, RMS 0.212 |
| extra sources on the device (`teacher_label.extra_sources()`) | none — Pass-Thru only, no microphone mixed in |
| audio stack (`audio_stack_is_alive`) | ok |
| Accessibility for the framework `python3` | granted (checked from this process chain; the night run must be launched the same way) |
| cooldown (`~/.walkie-talkie/teacher-cooldown`) | expired (was until 2026-09-23 05:42) |
| `helpers/wispr_preflight.py --no-idle-check` (read-only: `ps`, `pgrep`, GETs, reads `config.json`) | exit 2 — the two ✗ above; relay ✓ 8917, installed build ✓, audio ✓, device ✓, hands-off ✓ |
| `~/.walkie-talkie/wispr-loop.lock` | absent |
| relay `GET /test/state` | `busy:false`, `phase:idle`, `lastFailure:null` |
| relay `GET /target` | `bound:false` — **must stay so all night** (§4, A3) |
| relay `GET /engine` | `eleven-live`, `wrapMode:off`, firewall on (`wrapWhy`: *the firewall drops Wispr's ⌘V … the History row is the delivery*) |
| front app | `Loopback` — not a safe sink, irrelevant: the gate brings TextEdit forward once the Mac is quiet |

**Pinning Wispr to `🎓 TO Wispr` silences Victor's own Wispr dictation** (the device is Pass-Thru
only now), so the pin is an evening step and the un-pin a morning step (§6).

## 1. How the batch works (what the code actually does)

- **Start:** `python3 helpers/teacher_label.py --all [--min-seconds 3] [--stop-after H]
  [--manifest F]`. Refuses when: no Loopback device, CoreAudio wedged, no Accessibility, cooldown
  in the future (`--ignore-cooldown`), a microphone enabled beside Pass-Thru
  (`--ignore-extra-sources`), cannot start the human watch. **It does not check Wispr's
  microphone** — only `wispr_preflight.py` does, and the batch never calls it. That gap is exactly
  what killed 22→23 Sep.
- **Env it reads:** `VOICE_CORPUS_DIR`, `WISPR_BATCH_GAP_MIN/MAX` (2.5/9 s), `WISPR_BATCH_GIVE_UP`
  (5), `WISPR_MAX_LABEL_LAG` (8) + `_PER_SEC` (0.7), `WISPR_SILENT_PEAK` (0.02),
  `WISPR_COOLDOWN_HOURS` (3), `TEACHER_QUIET_MINUTES` (5), `TEACHER_STATUS`, `TEACHER_LOG` (only
  echoed into the status file), and in `wispr_loopback`: `WISPR_PTT_KEYS` (54,61 = right ⌘⌥),
  `WISPR_LEAD_SECONDS` 1.3, `WISPR_TAIL_SECONDS` 0.5, `WISPR_RESULT_TIMEOUT` 45, `WISPR_PLAY_PEAK` 0.5.
- **What must be in front:** the allow-list `SAFE_SINKS = {TextEdit, Notes, Stickies, Wispr Flow,
  Finder}`, checked before **every** clip. A gated run does not refuse at start: after 5 min of
  quiet it activates TextEdit (a new document if none) and waits if that fails. Only
  `--ignore-human` refuses at start.
- **The locks:** it runs `~/bin/hands-off start` itself and `end` on exit, SIGINT, SIGTERM, and at
  every suspension. Do **not** wrap it in `hands-off run` (the old `teacher-night.sh` did): that
  puts up a 900 s lock of its own. Note `hands-off start` without a ttl expires after 120 s; from
  then on the addons' `SyntheticInputWatch` floor keeps 🔒 up while keys are being posted.
- **The gate:** any hardware input (source pid 0) → the clip in flight is cut (`⏸ cut short`, not
  a label), locks drop, `teacher-status.json` says `paused`; resumes after 5 min of quiet.
- **Runner lock: it does NOT take `~/.walkie-talkie/wispr-loop.lock`.** `evals/plan/harness.py`
  says *"the teacher-labelling batch takes it too"* — that is false today. See §7.
- **How it stops:** `--stop-after` hours reached (checked before each clip) · queue empty ·
  5 empty transcripts in a row → pause 5 / 15 / 30 min, and after the third → **gives up and writes
  a 3 h cooldown** · SIGINT/SIGTERM (handler: closes the rig-run window, drops the locks,
  `status=stopped`, exit 130).
- **How it resumes:** run the same command again. Each label is committed per clip, the queue is
  every unlabelled clip shortest-first, so it carries on from where it stopped. Clips that failed
  are not remembered — they are retried first every night.

## 2. Why 22→23 Sep produced nothing after 02:42

The process gave up and exited; nothing restarts it:

```
02:42:14  giving up after 5 failures and 3 pauses — standing down until 05:42 so this does not turn into a banned account
02:42:14  done: 0 labelled, 20 failed, 127 silent, 0 wrong language, 0 misrouted, 0 cut short, 180 min
02:42:14  suspended 3× for 110 min of that, waiting for the Mac
2026-09-23 02:42:14  finished: -7 labelled tonight, 1356 left, 2970 with teacher_text in total
2026-09-23 02:42:15  mail sent: Etichetarea n-a reușit nimic — 1356 clipuri rămase
```

**Root cause: Wispr's microphone was not `🎓 TO Wispr`.** All 21 Wispr `History` rows of that run
(2026-09-22 20:46–23:41 UTC) are `micDevice = Built-in mic (recommended)`, `status =
raw_transcript`, empty `asrText`; `relay.log` says `raw_transcript with nothing in it 8 s after the
microphone closed — Wispr heard no speech` for each. The last `🎓 TO Wispr` row is 2026-09-22
12:27 UTC; the night before, 554 rows through `🎓 TO Wispr`, 541 with text. So the clips were
played into a device Wispr was not listening to. It was not the clips: the same queue contains
loud, fresh ones (peak 0.47, 0.98) that failed just the same. (`-7` is the wrapper subtracting two
counts while Victor recorded new clips; count `teacher_at` instead.)

**The memory note's cure** (`feedback_teacher_progress_report.md`): supervise every **50 minutes**
(`ScheduleWakeup` 3000 s, under the 1 h prompt-cache TTL) — tail the night log + run
`teacher_progress.py` — because an hourly check would have caught it in the first minutes. It
diagnoses the cause as *short/silent clips*; the evidence above says the mic pin. The 50-min check
below therefore reads Wispr's `micDevice` directly.

## 3. Tonight: start

**Preconditions, in order (stop at the first red):**

1. Victor has left the Mac; the orchestrator's schedule says the test suite is not due.
2. Wispr running (`/usr/bin/pgrep -f "^/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"`).
3. `python3 helpers/wispr_preflight.py --no-idle-check` → exit 0 (mic row must say
   `Wispr microphone: 🎓 TO Wispr — the device this plays into`, or `unnamed` right after a re-pin).
4. `curl -s localhost:8917/target` → `"bound":false`. `curl -s localhost:8917/test/state` →
   `"busy":false`.
5. `~/.walkie-talkie/wispr-loop.lock` absent or its pid dead.
6. `cat ~/.walkie-talkie/teacher-cooldown` in the past (or absent).

```sh
cd /Users/victorrentea/workspace/walkie-talkie
S=~/.walkie-talkie; D=$(date +%Y%m%d); LOG=$S/teacher-night-$D.log; L=$S/wispr-loop.lock
if [ -f "$L" ] && kill -0 "$(cut -d' ' -f1 "$L")" 2>/dev/null; then echo "REFUSE — runner lock: $(cat "$L")"; exit 1; fi
H=$(python3 -c "import datetime as d;n=d.datetime.now();t=n.replace(hour=7,minute=0,second=0,microsecond=0);t+=d.timedelta(days=int(t<=n));print(round((t-n).total_seconds()/3600,2))")
open -g -a TextEdit "$S/wispr-paste-target.txt"          # -g: opened, not brought forward; the gate activates it
date -u +%Y-%m-%dT%H:%M:%S > "$S/teacher-night.started-utc"
echo "$(date '+%F %T')  [runbook] start, --stop-after ${H}h" >> "$LOG"
TEACHER_LOG="$LOG" nohup python3 -u helpers/teacher_label.py --all --min-seconds 3 \
    --stop-after "$H" --manifest "$S/teacher-night-$D.jsonl" >> "$LOG" 2>&1 &
PID=$!
echo "$PID $(date '+%Y-%m-%d %H:%M:%S')" > "$L"          # interim runner lock — drop this line once §7 lands
echo "$PID" > "$S/teacher-night.pid"; echo "$LOG" > "$S/teacher-night.logpath"; echo 0 > "$S/teacher-night.mark"
caffeinate -dis -w "$PID" &                              # display/idle/system awake for exactly the batch's life
```

- Log: `~/.walkie-talkie/teacher-night-<YYYYMMDD of the start>.log` (one file per start date; a
  run past midnight keeps writing the start date's file).
- `--min-seconds 3`: sub-3 s taps come back empty from Wispr and only burn the give-up streak.
- `caffeinate -w` rather than `caffeinate … python3`: a TERM to the pid then reaches Python's
  handler, not caffeinate. `-u` dropped on purpose — without `-t` it lasts 5 s anyway.
- First output within ~5 s: `N sample(s) to label …`, `device: 🎓 TO Wispr`, `paste sink: …`,
  `suspends while this Mac is in use …`. Then either `⏸ suspended …` (Mac not quiet yet) or clips.
- **Report at start** (§5).

## 4. Every 50 minutes

```sh
cd /Users/victorrentea/workspace/walkie-talkie
S=~/.walkie-talkie; G=/usr/bin/grep; LOG=$(cat $S/teacher-night.logpath); PID=$(cat $S/teacher-night.pid)
kill -0 "$PID" 2>/dev/null && echo "alive $PID" || echo "DEAD $PID"
cat $S/teacher-status.json
N0=$(cat $S/teacher-night.mark); wc -l < "$LOG" | tr -d ' ' > $S/teacher-night.mark
tail -n +$((N0+1)) "$LOG" > $S/teacher-window.txt; W=$S/teacher-window.txt
echo "ok $($G -c ' ✓ ' $W) · empty $($G -c 'no transcript' $W) · late $($G -c 'behind the clip' $W) · reused $($G -c 'already used' $W) · lang $($G -cE 'Wispr heard|letters Romanian' $W) · cut $($G -c 'cut short' $W) · suspended $($G -c 'suspended —' $W) · backoff $($G -c 'pausing' $W) · gave-up $($G -c 'giving up' $W) · traceback $($G -c 'Traceback' $W)"
tail -n 5 $W
sqlite3 "file:$HOME/Library/Application Support/Wispr Flow/flow.sqlite?mode=ro" \
  "SELECT micDevice, status, COUNT(*), SUM(length(asrText)>0) FROM History WHERE timestamp > datetime('now','-50 minutes') GROUP BY 1,2;
   SELECT 'stuck', COUNT(*) FROM History WHERE timestamp BETWEEN datetime('now','-50 minutes') AND datetime('now','-2 minutes') AND COALESCE(status,'') IN ('','recording','processing');"
sqlite3 -readonly $S/voice-corpus/corpus.db \
  "SELECT 'tonight', COUNT(*), ROUND(SUM(seconds)/60,1) || ' min' FROM samples WHERE teacher_at >= '$(cat $S/teacher-night.started-utc)'"
curl -s -m 3 localhost:8917/target; echo
curl -s -m 3 localhost:8917/test/state | python3 -c "import sys,json;d=json.load(sys.stdin);print({k:d.get(k) for k in ('busy','phase','lastFailure')})"
cat $S/wispr-loop.lock 2>/dev/null || echo "no lock file"
python3 helpers/teacher_progress.py
```

`grep` is `/usr/bin/grep` on purpose: in this shell `grep`/`rg` are zsh shims.
`busy:true` on the relay is **normal** mid-clip — the relay rides every right-⌘⌥ chord as *Victor's
own Wispr dictation* and delivers the words at the caret (TextEdit).

**Stop at once (`kill -TERM`, §5) when:**

| # | signal | why |
|---|---|---|
| A1 | any row in the window with a non-empty `micDevice` ≠ `🎓 TO Wispr (Virtual)` while the status was `running` (empty = a row Wispr never named, e.g. a dismissed one) | the 22→23 failure; every clip after it is wasted and the ladder ends in a 3 h cooldown |
| A2 | 0 `✓` in the window with the status `running` for ≥ 20 min of it | nothing is being learnt; run the §3 preconditions + the 440 Hz pass-thru test before restarting |
| A3 | `GET /target` → `"bound":true` | the firewall routes a Wispr chord's words to the **bound terminal** (`hand-started-bound`, 2026-09-22): corpus sentences typed into a live session |
| A4 | the lock file holds a live pid that is not ours | the test suite started anyway — two processes posting keys at one Wispr |
| A5 | `late + reused` > 25 % of attempts (`ok + empty + late + reused + lang`) | the off-by-one regime (21 Sep 02:12–05:02 dropped 242 labels this way) |
| A6 | `lang` > 10 % of attempts | channel contamination — re-check `extra_sources()` |
| A7 | `stuck` ≥ 3 and `ok` = 0 | Wispr/network wedged (`processing` rows); the ladder would only burn the night |
| A8 | `DEAD` while the status file says `running`/`paused` | a crash (SIGBUS killed the 21 Sep run at 05:02). Report; restart **once** with §3 if the preconditions are still green |

**Early warning, not an abort:** the first `N failures in a row — pausing 5 min` → run A1's query
now. Mic right and Wispr running → let the ladder work (a five-in-a-row blank that recovered two
minutes later is measured, 2026-09-21). Mic wrong → A1.
**Not a problem:** `state: paused` — someone is at the Mac; report *paused since* and keep waiting.
`⌀ silent` lines — nothing was asked of Wispr.

## 5. Stop, and what to report

```sh
kill -TERM "$(cat ~/.walkie-talkie/teacher-night.pid)"
```

The handler closes the rig-run window, drops the 🔒, writes `teacher-status.json`
`state: stopped, reason: signal`, exits 130; `caffeinate -w` ends with it. Verify: pid gone,
status `stopped`, `~/bin/hands-off state` inactive. **Never `kill -9` mid-clip**: it can leave
right ⌘ + right ⌥ held (Wispr recording, every key a shortcut) — if it happened, one physical
press of each clears it. The stale lock file is harmless (dead pid) but may be removed.

**At every start, pause, stop and 50-min check**, from `teacher_progress.py`, never improvised:

> **X % of the audio to label is labelled** (`din audio-ul de etichetat`), ≈ **Y h of clock left**
> (`≈ … h de ceas`). This window: N ✓ (M min of audio), E empty, L late/reused, S suspensions.
> Status: running / paused since HH:MM / stopped (reason).

Percent of audio DURATION, not of clips — the clip share (53.8 % today) is the flattering one.

## 6. Morning

1. `--stop-after` ends it at 07:00 by itself; else §5.
2. Final report (§5), plus `tonight` from the corpus query.
3. **Victor: Wispr → Settings → Microphone → back to his microphone** — `🎓 TO Wispr` is Pass-Thru
   only, so his next Wispr dictation would record silence.
4. `rm -f ~/.walkie-talkie/wispr-loop.lock` if it still names the dead pid.

## 7. The runner lock

The batch must not start while `wispr-loop.lock` is held by a live pid, and must hold it while
running. **It does neither today.** §3 covers it from the shell (refuse + write the Python pid);
the proper fix is five lines in `teacher_label.main`, reusing `wispr_loop`'s own functions
(import is clean, 0.14 s). **Proposed, not applied:**

```python
# helpers/teacher_label.py, in main(), right after `if not todo: return 0`
    import atexit, wispr_loop  # noqa: E401 — the one runner lock on this Mac
    got, detail = wispr_loop.take_runner_lock()
    if not got:
        raise SystemExit("another runner is dictating on this Mac — " + detail)
    atexit.register(wispr_loop.release_runner_lock)
```

`atexit` covers the normal end, every later `SystemExit` preflight refusal, and the SIGINT/SIGTERM
handler (its `sys.exit(130)` unwinds through the interpreter's exit). A SIGKILL leaves a dead pid,
which `_lock_holder` already ignores. After it lands, drop the `echo … > "$L"` line from §3. The
lock is check-then-write, not atomic — fine for two processes started minutes apart, not a mutex.

## 8. Things that will look wrong and are not

- The relay draws its ring, pauses Chrome tabs and files a `wispr-flow` decode sample on every
  clip — it takes the batch's right-⌘⌥ for Victor's own dictation. Harmless at night; the
  `decode-rate.jsonl` samples for `wispr-flow` are the batch's.
- `teacher_progress.py` counts **38 clips / 1.92 h over 120 s** as "left", but `--max-seconds`
  defaults to 120, so they are never dictated; with the defaults the percentage tops out near 89 %.
  The longest is 377 s. `--max-seconds 400` would take them, but Wispr has not been tried on a
  clip that long here: try a few with `--min-seconds 120 --max-seconds 400 --limit 3` on a
  supervised run first.
