#!/bin/bash
# GUEST ONLY (pushed to ~/film by setup.sh, run through `tart exec`): end processes by EXACT name, one PID at a time.
#   gkill.sh [-9] <exact process name>...        e.g.  gkill.sh -9 Terminal    ·    sudo gkill.sh login
# Never run this on the host: there, only a PID you started yourself is ever killed.
sig=TERM; [ "$1" = -9 ] && { sig=KILL; shift; }
[ "$(sysctl -n kern.hv_vmm_present)" = 1 ] || { echo "not a VM — refusing"; exit 1; }
for name in "$@"; do for pid in $(/usr/bin/pgrep -x "$name"); do kill -$sig "$pid" 2>/dev/null; done; done
true
