#!/bin/bash
# Vendors the voice-halo page into assets/voice-halo from a PINNED tag (or commit) of the
# sibling checkout (~/workspace/voice-halo, github.com/victorrentea/voice-halo).
# The halo runs this page whole, in a web view (HaloPage.swift); a change on
# the page reaches the app by bumping TAG here and re-running this. The
# vendored copy is committed, so the app builds without the sibling repo.
set -euo pipefail
TAG="${VOICE_HALO_TAG:-bdf4ae8}"
SRC="${VOICE_HALO_REPO:-$HOME/workspace/voice-halo}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$DIR/assets/voice-halo"
if ! git -C "$SRC" rev-parse -q --verify "$TAG^{commit}" >/dev/null 2>&1; then
  echo "vendor-voice-halo: no tag $TAG in $SRC — keeping the committed copy ($(cat "$OUT/VERSION" 2>/dev/null || echo none))" >&2
  exit 0
fi
mkdir -p "$OUT"
git -C "$SRC" archive "$TAG" index.html water.js comets.js | tar -x -C "$OUT"
echo "$TAG $(git -C "$SRC" rev-parse --short "$TAG^{commit}")" > "$OUT/VERSION"
echo "vendor-voice-halo: assets/voice-halo ← $SRC @ $(cat "$OUT/VERSION")"
