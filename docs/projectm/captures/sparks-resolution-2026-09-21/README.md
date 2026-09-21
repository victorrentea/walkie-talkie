# Sparks, 2026-09-21 evening — what "blurred points" turned out to be

Two different faults, one evening, both measured through the real panel.

## 1. `ruler-before-after.png` — the fractional resample

A 4-px grid of 1-device-pixel lines drawn into the engine's canvas by a patched
copy of `assets/milkdrop/`, photographed with `screencapture`, shown here at 3×
nearest. **Left**: the page CSS-scaled its canvas by the preset's `scale` on a
view the host had already scaled, so 3220 canvas px were resampled into 3000
device px — every line arrives split across two pixels with a drifting phase
(`39 40 104 176 · 39 39 167 112 · 39 39 230 49`). **Right**: 1:1
(`255 38 38 38 · 255 38 38 38`). Modulation depth 121 → 150 of 255.

## 2. `canvas-1610-3220-6440-same-10pct.png` — the fog

The **same 10 % of the canvas**, the same second of the same clip, rendered at
1610 / 3220 / 6440 canvas px (left to right). A chain-breaker spark is ~5 canvas
px at 1610, ~20 at 3220, ~56 at 6440: **the sparks grow faster than the canvas
does**. So "more resolution" makes this preset foggier, not finer, which is why
`Preset.renderScale` exists and why Sparks is the one preset that asks for less.

## 3. `screen-3220-vs-1610.png` — on his screen, at 1:1

Left 3220 (a wash of colour, the text under it unreadable), right 1610 (small
separate stars, the text readable). Same preset, same clip, same panel.
