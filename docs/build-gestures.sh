#!/usr/bin/env bash
#
# Render docs/gestures.puml to docs/gestures.svg.
#
# Run this after ANY change to the diagram — that is the rule, and it is the
# same rule docs/shoot-overlay-states.sh carries for the overlay. The picture is
# how the vocabulary is reviewed; a stale one is worse than none, because it is
# the thing a reader trusts. evals/test_gesture_diagram.py --render re-renders
# into a temp directory and fails on a diff, so a forgotten run fails the build.
#
# Never hand-edit docs/gestures.svg.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v plantuml >/dev/null 2>&1 || {
  echo "plantuml is not installed — brew install plantuml" >&2
  exit 1
}

plantuml -tsvg -nometadata -o "$PWD/docs" docs/gestures.puml
echo "→ docs/gestures.svg"
