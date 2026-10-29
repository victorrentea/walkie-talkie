#!/bin/bash
# **The weekly night run in the lab** (2026-09-27). Victor: *"vreau sa configurezi suita de teste de
# walkie sa ruleze in fiecare seara cand ai hdd extern conectat, dar max 1/sapt automat. sa fie rulata
# si de claude intr-o sesiune interactiva pornita noaptea la 2:00 si sa repari ce defecte gasesti,
# daca pica ceva. + trimite o rulare exploratorie sa se joace cu app. totul in VM."*
#
# **On demand only since 2026-09-29** (Victor: *"I will only run it on demand … it's a bit abusive"*
# — a scheduler must not hit external APIs): the LaunchAgent is unloaded and parked in
# `~/Library/LaunchAgents.disabled/`. Run `WT_NIGHT_FORCE=1 tools/wt-night.sh start` when he asks.
#
# As built: the LaunchAgent `tools/ro.victorrentea.wt-night.plist` called `start` every night at 02:00. `start`
# opens an interactive Claude Code session in a detached tmux (`wt-night`) whose brief is
# `evals/plan/vm/night/PROMPT.md`: VM up, deploy, the whole suite in the guest, fix, re-run,
# exploratory run, report, VM down. Docs: docs/vm-lab.md, section *Nightly*.
#
#   wt-night.sh gate     exit 0 only if tonight's run may start (prints why not)
#   wt-night.sh start    gate, stamp, then the Claude session in tmux `wt-night`
#   wt-night.sh smoke    tmux + claude with a one-word prompt; checks the pane, kills it. No stamp
#   wt-night.sh status   stamp age, the tmux session, the launcher log, the last report
#
# Env: WT_NIGHT_FORCE=1  skip the weekly age check and the 01–05 hour window (not the disk, not the
#                        running-session check) — `WT_NIGHT_FORCE=1 tools/wt-night.sh start` = tonight
#      WT_NIGHT_RC=0     start claude without `--remote-control` (if RC blocks or wants a login)
#
# Logs in ~/.walkie-talkie/night/. The stamp is beside the VM in $TART_HOME/night (internal disk since
# 2026-09-29; the external disk Vic is not used at all since 2026-10-30).
set -euo pipefail

REPO=/Users/victorrentea/workspace/walkie-talkie
export TART_HOME="${TART_HOME:-$HOME/tart}"   # internal disk only; the external disk is dropped (2026-10-30)
STAMP="$TART_HOME/night/last-run"
SESSION=wt-night
LOGDIR="$HOME/.walkie-talkie/night"
LOG="$LOGDIR/launcher.log"
PROMPT_FILE="$REPO/evals/plan/vm/night/PROMPT.md"
MAX_AGE=$(( 6 * 86400 + 12 * 3600 ))   # 6 d 12 h: a 02:00 job fires weekly despite clock drift
STALE_SESSION=$(( 20 * 3600 ))          # a wt-night tmux older than this is last week's, left open to read
# ~/.local/bin FIRST: the native Claude Code build, not npm/nvm (same as ~/workspace/claude-rc.sh)
NIGHT_PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$NIGHT_PATH"

mkdir -p "$LOGDIR"
log() { echo "$(date '+%F %T') [$1] $2" | tee -a "$LOG" >&2; }

session_age() {   # seconds since the wt-night tmux session was created; empty when there is none
  local c
  c="$(tmux display-message -p -t "=$SESSION:" '#{session_created}' 2>/dev/null || true)"
  [ -n "$c" ] && echo $(( $(date +%s) - c ))
  return 0
}

# gate [quiet] — exit 0 = go. Read-only.
cmd_gate() {
  if [ ! -d "$TART_HOME" ]; then
    log gate "refused: $TART_HOME is not there (the lab moved to the internal disk on 2026-09-29)"; return 1
  fi
  local age
  age="$(session_age)"
  if [ -n "$age" ] && [ "$age" -lt "$STALE_SESSION" ]; then
    log gate "refused: tmux session '$SESSION' exists (started $((age / 60)) min ago) — a night run is live; tmux attach -t $SESSION"
    return 1
  fi
  if [ "${WT_NIGHT_FORCE:-0}" != 1 ]; then
    local h
    h=$((10#$(date +%H)))
    if [ "$h" -lt 1 ] || [ "$h" -gt 5 ]; then
      log gate "refused: it is $(date +%H:%M), outside 01:00–05:59 (launchd fires a missed 02:00 at wake; a day-time VM boot is not wanted). WT_NIGHT_FORCE=1 overrides"
      return 1
    fi
    if [ -f "$STAMP" ]; then
      local since=$(( $(date +%s) - $(stat -f %m "$STAMP") ))
      if [ "$since" -lt "$MAX_AGE" ]; then
        log gate "refused: last automatic run $((since / 3600)) h ago ($(cat "$STAMP" 2>/dev/null)); weekly = ≥ $((MAX_AGE / 3600)) h. WT_NIGHT_FORCE=1 overrides"
        return 1
      fi
    fi
  fi
  [ -n "$age" ] && log gate "note: tmux '$SESSION' from $((age / 3600)) h ago is last run's — start renames it, keeps it"
  log gate "open: disk mounted, stamp $( [ -f "$STAMP" ] && echo "$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 3600 )) h old" || echo absent), force=${WT_NIGHT_FORCE:-0}"
  return 0
}

# launch <tmux-session> <rc-name> <prompt-file>
launch() {
  local sess=$1 rc_name=$2 pfile=$3 rc="" inner
  [ "${WT_NIGHT_RC:-1}" = 0 ] || rc="--remote-control $rc_name"
  command -v claude >/dev/null || { log launch "no claude on PATH ($PATH)"; return 1; }
  # As claude-rc.sh: through a login zsh, PATH re-exported inside it (the tmux server's environment
  # is whatever the first tmux client had). Auto mode: the classifier decides, risky calls surface
  # as a prompt over Remote Control. The prompt goes in as the first user message.
  inner="export PATH=\"$NIGHT_PATH\" TART_HOME=\"$TART_HOME\"; claude --permission-mode auto --name $rc_name $rc \"\$(cat '$pfile')\"; rc=\$?; echo; echo \"[wt-night] claude exited rc=\$rc at \$(date '+%F %T')\"; exec zsh -il"
  tmux new-session -d -s "$sess" -c "$REPO" -x 220 -y 60 /bin/zsh -lc "$inner"
  log launch "tmux '$sess' started: claude --permission-mode auto --name $rc_name ${rc:-(no RC)} < $(basename "$pfile")"
}

cmd_start() {
  log start "---- start (pid $$, by ${XPC_SERVICE_NAME:-a shell})"
  cmd_gate || return 1
  local age
  age="$(session_age)"
  if [ -n "$age" ]; then
    local old="$SESSION-$(date -r $(( $(date +%s) - age )) +%Y%m%d-%H%M)"
    tmux rename-session -t "=$SESSION" "$old"
    log start "last run's tmux renamed to '$old' (still there to read; tmux kill-session -t $old)"
  fi
  mkdir -p "$(dirname "$STAMP")"
  date '+%F %T' > "$STAMP"
  log start "stamp written: $STAMP"
  launch "$SESSION" "$SESSION" "$PROMPT_FILE"
  log start "watch: tmux attach -t $SESSION (detach: Ctrl-B D) · Remote Control session '$SESSION'"
  # The session's own claude.ai URL, for the Claude-Session trailer of its commits (PROMPT.md reads
  # the file). Claude prints it in the pane once Remote Control is up.
  rm -f "$LOGDIR/session-url"
  ( for _ in $(seq 1 60); do
      sleep 2
      u="$(tmux capture-pane -p -t "=$SESSION:" 2>/dev/null | grep -Eo 'https://claude\.ai/code/session_[A-Za-z0-9]+' | head -1 || true)"
      if [ -n "$u" ]; then echo "$u" > "$LOGDIR/session-url"; log start "session URL: $u"; exit 0; fi
    done; log start "no session URL in the pane after 120 s (RC off or offline?)" ) &
}

cmd_smoke() {
  log smoke "---- smoke"
  if tmux has-session -t "=$SESSION" 2>/dev/null; then
    log smoke "refused: tmux '$SESSION' exists — not killing a live night run"; return 1
  fi
  local p
  p="$(mktemp -t wt-night-smoke)"
  # A session cannot /exit itself (a slash command in the model's reply is text, not a command),
  # so the smoke reads the pane and kills the session.
  echo "Reply with the single word OK. Do not run any tool." > "$p"
  launch "$SESSION" "$SESSION-smoke" "$p"
  local pane="" ok=0
  for _ in $(seq 1 45); do
    sleep 2
    pane="$(tmux capture-pane -p -t "=$SESSION:" 2>/dev/null || true)"
    if printf '%s\n' "$pane" | grep -Eq '⏺ *OK\b'; then ok=1; break; fi
  done
  printf '%s\n' "$pane" | grep -v '^[[:space:]]*$' | tail -25 | sed 's/^/  pane│ /' | tee -a "$LOG" >&2
  tmux kill-session -t "=$SESSION" 2>/dev/null || true
  rm -f "$p"
  if [ $ok = 1 ]; then log smoke "PASS: claude answered OK in tmux; session killed"; return 0; fi
  log smoke "FAIL: no '⏺ OK' in the pane within 90 s (pane above); session killed"; return 1
}

cmd_status() {
  if [ -f "$STAMP" ]; then
    local since=$(( $(date +%s) - $(stat -f %m "$STAMP") ))
    echo "stamp:    $STAMP = $(cat "$STAMP") ($((since / 3600)) h ago; next automatic run once ≥ $((MAX_AGE / 3600)) h)"
  elif [ -d "$TART_HOME" ]; then
    echo "stamp:    none — the next 02:00 runs"
  else
    echo "stamp:    unknown — $TART_HOME not mounted"
  fi
  local age
  age="$(session_age)"
  if [ -n "$age" ]; then echo "tmux:     '$SESSION' alive, $((age / 60)) min old — tmux attach -t $SESSION"
  else echo "tmux:     no '$SESSION' session"; fi
  tmux ls 2>/dev/null | grep "^$SESSION-" | sed 's/^/          kept: /' || true
  echo "launchd:  $(launchctl print "gui/$(id -u)/ro.victorrentea.wt-night" 2>/dev/null | grep -m1 -E '^\s*state =' | xargs || echo 'ro.victorrentea.wt-night not loaded')"
  local rep
  rep="$(ls -1d "$REPO"/evals/plan/vm/night/20*/report.md 2>/dev/null | tail -1 || true)"
  echo "report:   ${rep:-none yet (the 26/27 Sep run is evals/plan/vm/night/report-vm-night.md)}"
  [ -f "$LOGDIR/history.log" ] && { echo "history:"; tail -3 "$LOGDIR/history.log" | sed 's/^/          /'; }
  echo "log:      $LOG"
  [ -f "$LOG" ] && tail -8 "$LOG" | sed 's/^/          /'
  return 0
}

case "${1:-}" in
  gate) cmd_gate ;;
  start) cmd_start ;;
  smoke) cmd_smoke ;;
  status) cmd_status ;;
  *) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
