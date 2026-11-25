#!/bin/bash
# Background review of commits pushed to main — started by tools/git-hooks/pre-push, never by hand
# (by hand is fine too: tools/review-push.sh <from-sha> <to-sha>).
#
# Pushes come in bursts (several sessions auto-push), so this debounces: it records the newest
# pushed sha as `pending`, waits, and one reviewer at a time covers everything from the last
# reviewed sha up to `pending`. A second push during a review is picked up by the running one.
#
# The review is read-only: a lean `claude -p` on the subscription (no API key), project CLAUDE.md
# and .claude/rules loaded, tools limited to reading and git inspection. The report lands in
# ~/.walkie-talkie/reviews/; a notification appears only when it has findings.
set -u
from=$1 to=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
dir="$HOME/.walkie-talkie/reviews"
mkdir -p "$dir"
log="$dir/review.log"
say() { echo "$(date '+%F %T') $*" >> "$log"; }

echo "$to" > "$dir/pending"
[ -s "$dir/last-reviewed" ] || echo "$from" > "$dir/last-reviewed"

# One reviewer at a time; mkdir is atomic. A stale lock (dead PID) is taken over.
lock="$dir/.lock"
if ! mkdir "$lock" 2>/dev/null; then
  pid=$(cat "$lock/pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    say "queued $to (reviewer $pid running)"; exit 0
  fi
  say "taking over stale lock of $pid"
fi
echo $$ > "$lock/pid"
trap 'rm -rf "$lock"' EXIT

cd "$repo" || exit 1
while :; do
  sleep "${WT_REVIEW_DEBOUNCE:-180}"          # let the burst of pushes settle
  target=$(cat "$dir/pending")
  base=$(cat "$dir/last-reviewed")
  [ "$base" = "$target" ] && break
  git cat-file -e "$target^{commit}" 2>/dev/null || { say "unknown $target"; break; }
  # A rewritten main (or a base we never saw) reviews only the newest commit.
  git merge-base --is-ancestor "$base" "$target" 2>/dev/null || base="$target~1"
  n=$(git rev-list --count "$base..$target")
  range="$base..$target"
  out="$dir/$(date '+%Y-%m-%d-%H%M')-$(git rev-parse --short "$target").md"
  say "reviewing $range ($n commits) → $out"

  prompt="You are an adversarial code reviewer. Review the commits in the range $range of this repo
($n commit(s); run \`git log --stat $range\` and \`git diff $range\` to see them). Read the surrounding
code and the callers you need, plus the .claude/rules/*.md files for the areas touched.

Report only real correctness bugs, regressions, races, leaks, crashes, security problems (the repo is
public: secrets, personal data, injection), and violations of CLAUDE.md or .claude/rules introduced by
these commits. Verify each one against the code before reporting it. Skip style and refactoring opinions.

Output Markdown only. First line: \`# Review of $range\`. If nothing survives verification, the second
line is exactly \`No findings.\` and nothing else. Otherwise one section per finding, most severe first:
file:line, severity (critical/important/minor), the commit that introduced it, the defect, a concrete
failure scenario, and a one-line fix."

  nice -n 10 claude -p "$prompt" \
    --model "${WT_REVIEW_MODEL:-opus}" --effort "${WT_REVIEW_EFFORT:-xhigh}" \
    --setting-sources project --strict-mcp-config --no-session-persistence \
    --allowedTools "Read" "Grep" "Glob" "Bash(git log:*)" "Bash(git diff:*)" "Bash(git show:*)" "Bash(git blame:*)" \
    --disallowedTools "Edit" "Write" "NotebookEdit" \
    > "$out" 2>> "$log"
  rc=$?
  say "done rc=$rc"
  [ $rc -eq 0 ] || break                      # leave last-reviewed alone: the next push retries
  echo "$target" > "$dir/last-reviewed"

  if ! grep -qx 'No findings.' "$out"; then
    count=$(grep -c '^## ' "$out")
    terminal-notifier -title "Walkie review" -message "$count finding(s) in $n commit(s) on main" \
      -open "file://$out" -group walkie-review >/dev/null 2>&1
  fi
done
