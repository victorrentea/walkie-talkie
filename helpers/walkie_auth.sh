# Sourced (bash or zsh). The loopback's `X-Walkie-Token` for `curl`, the shell twin of
# `helpers/walkie_token.py` (2026-11-25, the Fable review of the token gate):
#
#   curl -H @<(wt_auth "$port") "http://127.0.0.1:$port/test/state"
#
# - **Only to the app's own port.** `<home>/test-port` names the port the app bound
#   (`starting` until its listener is up); `wt_auth PORT` prints the header only when PORT
#   is that one, so a process squatting another of 8917–8919 is never handed the token.
#   No port file = an app from before it: 8917 alone.
# - **Never in argv.** `-H @<(…)` hands curl a file descriptor; the token goes through
#   builtins only (`printf`), so `ps` never shows it to another account.
# - The token is read before the port: the app writes `starting` there before a new
#   token, so the two always belong to the same launch. Re-read at every call.
#
# `wt_ports` lists where to ask: the app's port; nothing while it starts; 8917 when only a
# token exists; all three when neither file does (an app from before the gate — tokenless).
wt_home() { printf '%s' "${WALKIE_HOME:-$HOME/.walkie-talkie}"; }

wt_auth() {
  local h tok port
  h=$(wt_home)
  tok=$(cat "$h/test-token" 2>/dev/null) || tok=""
  [ -n "$tok" ] || return 0
  if [ -e "$h/test-port" ] || [ -L "$h/test-port" ]; then
    port=$(cat "$h/test-port" 2>/dev/null) || port=""
  else
    port=8917
  fi
  [ "$port" = "${1:-}" ] && printf 'X-Walkie-Token: %s\n' "$tok"
  return 0
}

wt_ports() {
  local h port
  h=$(wt_home)
  if [ -e "$h/test-port" ] || [ -L "$h/test-port" ]; then
    port=$(cat "$h/test-port" 2>/dev/null) || port=""
    case "$port" in 8917|8918|8919) echo "$port" ;; esac
  elif [ -s "$h/test-token" ]; then
    echo 8917
  else
    echo 8917 8918 8919
  fi
  return 0
}
