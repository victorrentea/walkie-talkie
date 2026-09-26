#!/bin/bash
# **The lab: a macOS guest to run the live tests in, off Victor's screen** (2026-09-25).
#
# Victor: *"I would like to test the features such as binding to terminals, binding
# to visual code and IntelliJ, drag, cut, move, all the features, but that if you
# test live on my machine, you'll distract me. Is there any way I could install
# Mac OS on a VM on this machine?"*
#
# A Tart VM (Apple's Virtualization.framework) runs headless. Synthetic mouse and
# keyboard events posted inside it stay inside it: no 🔒 on his screen, no cursor
# taken. Look at it only when you want to, over Screen Sharing (`vm-lab.sh look`).
#
#   vm-lab.sh up              start `wt-lab` headless (created from `wt-base` if missing)
#   vm-lab.sh deploy [app]    copy the app (default: the installed build) in and launch it
#   vm-lab.sh api <path> [json]   GET, or POST the json, to the app's control port in the guest
#   vm-lab.sh sh <cmd…>       run a command in the guest, as `admin`, in its login session
#   vm-lab.sh shot [out.png]  the guest's screen, copied out
#   vm-lab.sh look            open Screen Sharing on the guest (admin / admin)
#   vm-lab.sh down            shut it down
#   vm-lab.sh reset           throw `wt-lab` away; the next `up` clones a clean one
#
# **Tart is pinned to 2.34.0** (installed from the GitHub release into /Applications/tart.app,
# linked as /opt/homebrew/bin/tart): 2.35+ need a newer Swift runtime than macOS 15 ships
# (`libswiftCompatibilitySpan.dylib` not found), and the brew tap's formula does not parse.
# **The guest can be no newer than the host**, hence Sequoia.
#
# The privacy grants (Accessibility, Screen Recording, microphone) are the guest's own,
# ticked once by hand over `look`, then kept in `wt-base` — `reset` does not lose them
# once they are there (see `bake`).
set -euo pipefail

# **Everything Tart stores lives on the external disk "Vic"** (2026-09-26, Victor: *"e important să
# nu se stocheze pe discul meu mult … totul să fie cât de mult se poate pe acel hard extern"*): the
# internal disk had 88 GiB free against a 25 GB base image plus clones. `TART_HOME` is the one knob
# Tart offers (OCI cache, IPSW cache, VMs, tmp all live under it); the volume is APFS, which the
# sparse disk images need. Refuse to run without it rather than silently fill the internal disk.
export TART_HOME="${TART_HOME:-/Volumes/Vic/tart}"
[ -d "$TART_HOME" ] || { echo "❌ $TART_HOME is not there — is the external disk Vic mounted?" >&2; exit 1; }

VM="${WT_LAB_VM:-wt-lab}"
BASE="${WT_LAB_BASE:-wt-base}"
IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
APP="Walkie Talkie"
LOG="$TART_HOME/$VM.log"

die() { echo "❌ $*" >&2; exit 1; }
state() { tart list --format json | python3 -c "
import json,sys
for v in json.load(sys.stdin):
    if v['Name']=='$1': print(v['State']); break"; }
g() { tart exec "$VM" "$@"; }

wait_agent() {
  for _ in $(seq 1 900); do   # the boot is off a USB spinning disk: ~580 s measured, 1146 s the first time
    g true 2>/dev/null && return 0
    sleep 1
  done
  die "$VM: the guest agent never answered (log: $LOG)"
}

cmd_up() {
  if [ -z "$(state "$BASE")" ]; then
    echo "↓ $BASE is not there — pulling $IMAGE (~25 GB)"
    tart clone "$IMAGE" "$BASE"
  fi
  if [ -z "$(state "$VM")" ]; then
    tart clone "$BASE" "$VM"
    tart set "$VM" --cpu 4 --memory 8192
  fi
  if [ "$(state "$VM")" != "running" ]; then
    # A `tart stop` (the plug) leaves control.sock behind; the next `tart run` then fails to
    # bind it ("Address already in use", only in the log) and `tart exec` never answers.
    rm -f "$TART_HOME/vms/$VM/control.sock"
    # --no-audio: Tart's default sound device passes the guest through to the HOST's speakers
    # and microphone (a mic prompt for tart on Victor's screen, his room in the guest's input).
    # --no-clipboard: the default shares the pasteboard both ways, and the app pastes with ⌘V.
    nohup tart run "$VM" --no-graphics --no-audio --no-clipboard >"$LOG" 2>&1 &
    disown
  fi
  wait_agent
  echo "✅ $VM up at $(tart ip "$VM")"
}

cmd_deploy() {
  local src="${1:-/Applications/$APP.app}"
  [ -d "$src" ] || die "no app at $src"
  codesign --verify --strict "$src" || die "$src does not verify — the grants key on its signature"
  g pkill -x "$APP" 2>/dev/null || true
  g sudo rm -rf "/Applications/$APP.app"
  # tar keeps the signature and the bundle's xattrs; the guest's grants stay attached.
  tar -C "$(dirname "$src")" -cf - "$(basename "$src")" | tart exec -i "$VM" sudo tar -C /Applications -xf -
  g sudo chown -R admin:staff "/Applications/$(basename "$src")"
  g open "/Applications/$(basename "$src")"
  for _ in $(seq 1 30); do
    cmd_api test/state >/dev/null 2>&1 && { echo "✅ $APP answering in $VM"; return 0; }
    sleep 1
  done
  die "$APP launched but its control port never answered"
}

cmd_api() {
  local path="${1:?path}" body="${2:-}" port
  for port in 8917 8918 8919; do
    if [ -n "$body" ]; then
      g curl -fsS -m 30 -X POST "http://127.0.0.1:$port/$path" -d "$body" && return 0
    else
      g curl -fsS -m 30 "http://127.0.0.1:$port/$path" && return 0
    fi
  done
  return 1
}

cmd_shot() {
  local out="${1:-$TART_HOME/$VM-screen.png}"
  g screencapture -x /tmp/vm-lab-shot.png
  g cat /tmp/vm-lab-shot.png >"$out"
  echo "$out"
}

cmd_look() { open "vnc://admin:admin@$(tart ip "$VM")"; }

# `tart stop` alone is a pulled plug: SIGINT → `VZVirtualMachine.stop()`, no guest shutdown (Tart
# 2.34 Run.swift/VM.swift, found 2026-09-26). Shut the guest down first, then reap the process.
cmd_down() {
  [ "$(state "$VM")" = "running" ] || return 0
  g sudo shutdown -h now >/dev/null 2>&1 || true
  for _ in $(seq 1 600); do [ "$(state "$VM")" = "running" ] || return 0; sleep 1; done   # 64 s to >300 s measured on the USB disk
  tart stop "$VM" 2>/dev/null || true
}

cmd_reset() { cmd_down; tart delete "$VM" 2>/dev/null || true; echo "🗑  $VM gone; next \`up\` clones $BASE"; }

# Fold the grants ticked in `wt-lab` back into the base, so every clean clone has them.
cmd_bake() {
  cmd_down
  tart delete "$BASE"
  tart clone "$VM" "$BASE"
  echo "✅ $BASE now carries $VM's state"
}

case "${1:-}" in
  up) cmd_up ;;
  deploy) shift; cmd_deploy "$@" ;;
  api) shift; cmd_api "$@" ;;
  sh) shift; g "$@" ;;
  shot) shift; cmd_shot "$@" ;;
  look) cmd_look ;;
  down) cmd_down ;;
  reset) cmd_reset ;;
  bake) cmd_bake ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
