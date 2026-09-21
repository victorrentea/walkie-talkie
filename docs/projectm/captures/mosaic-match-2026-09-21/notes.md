# Mosaic: native projectM against butterchurn, video against video (2026-09-21 evening)

Everything here is a 30 fps screen recording of the demo ring (`WT_HALO_DEMO=11`) on a
black full-screen backdrop, pointer warped to the centre of the built-in display, the same
16 kHz clip looped every run (`WT_HALO_DEMO_AUDIO=clip`, new — `assets/halo-voice.wav`;
`DemoVoice` draws fresh noise each run and is not comparable across runs). Recorded under
`hands-off`. Tools in `tools/` (`record.sh` records, `analyze.py` + `pairs.py` +
`aggregates.py` measure, `index2.py` reads the beat index out of the logs, `model.py`
replicates both audio pipelines in numpy). Runs: web1–7 (butterchurn, this app's host page),
native1–2 (projectM as shipped: raw 16 kHz samples declared 44.1 kHz), rs1 (`WT_PM_RESAMPLE=1`),
bc1–2 (a rebuilt engine with butterchurn's FFT and Hz bands, `PM_BC_AUDIO=1`), srgb/nosrgb
(the IOSurface tagged sRGB or not).

**Reference.** The published page (`voice-halo`, effect #17) lets butterchurn sample its own
AnalyserNode; this app's host page injects resampled bytes (`403044b`). The two now agree on
what the audio is, so the app's web route is what was matched; `~/workspace/voice-halo` is
three commits ahead of the vendored copy, none of them audio.

## What the numbers say

| metric (`pairs.txt`, 240 frames from first lit frame, 15/12/12 pairs) | web vs web | native vs web | bc vs web | rs vs web |
|---|---|---|---|---|
| mean per-frame abs luminance difference | **10.33** | 11.39 | 11.35 | 11.91 |
| correlation of the mean-luminance series | 0.89 | 0.61 | 0.59 | 0.32 |

| beat index `q23` (`q27 = q23+1`, the tile-lattice period), 2–10 s (`beat-index.txt`) | web vs web | native vs web |
|---|---|---|
| beats within 100 ms of one of the other's | 50–91 % | 36–91 % |
| frames with the same index | **1–82 %** | 0–22 % |
| native vs native (same engine, two runs) | — | 100 % / 98 % |

The web engine does not reproduce **itself** on the beat index: same clip, same code, two
runs land on the same index 1 % of the time in one pair and 82 % in another. `model.py`
shows why — butterchurn's 1024-sample unwindowed FFT of byte-quantised samples flips a beat
on a 0.5 ms shift of the frame phase (`selfnoise` in `model-beats.txt`: 23 % same-index at
8 samples of shift), and one flipped beat re-labels every later index. projectM's Hann-windowed
480-sample FFT is stable to 16 ms of shift. So "pixel-perfect comparable" is unreachable in
principle for this preset, on either side of the fence: **the native route is as close to a
web run as another web run is** on the per-frame image difference (11.4 vs 10.3), and no
audio-path variant (raw, resampled, butterchurn-style analysis) moves that number.

## What was actually different, and what closes it

1. **Colour (fixed, `pmhalo.cpp`).** Over the lit part, saturation was web 107–122 against
   native 148–152 on *every* run — while the engines' own readbacks agree (web 132, native
   123). The IOSurface was untagged, so Core Animation showed it in the display's P3 space.
   Tagged sRGB: 118 / 121 (`colour-tag.txt`, `side-by-side-colour-tag.mp4`); the untagged
   control in the same session stayed at 150. `WT_PM_COLORSPACE=none` reverts.
2. **Beat magnitude (fixed, `ProjectMHalo.resample` now on).** The raw feed was justified by
   the web route feeding raw samples too; since `403044b` it does not. `q22` — the preset's
   beat peak, the alpha of its white `wave_0` dots — averaged 2.5 raw, 1.2–1.5 web, 1.4
   resampled, 1.7 with the butterchurn-style analysis. Resampling matches; the deeper
   `PM_BC_AUDIO` patch buys nothing on top (`walkie-audio-time.patch`, kept for the record,
   **not proposed**). The spectrum's level changes with the feed (sum 214 raw, 48 resampled,
   112–124 web): `PM_SPECTRUM_SCALE` moves 5.3 → 12.7 with it so spectrum-driven waves land on
   the web's level. None of the six presets draws one, but it is a global knob — look at the
   other native presets once.
3. **`speed` (needs the library patch).** Mosaic carries `speed: 0.6`, which only the web route
   honoured; that alone keeps `webOnly`. The `TimeKeeper` hunk in `walkie-audio-time.patch`
   adds `PM_TIME_SCALE`, `ProjectMHalo` sets it from `Preset.speed`; verified: at 0.02× the
   engine's `time` advanced 0.04 s over 60 frames, at 1× 2.0 s. It also slows the beat
   detector's averaging, exactly as `render({elapsedTime})` does in butterchurn.
4. **Resolution** was already fixed (`824390d`); tile period on screen agrees (median 118–184
   px at 540-px analysis size on both routes, both chaotic in the same way).

## The crash on the way (19:43–19:46)

An intermediate rebuild of `libprojectM-4.a` sat in `vendor/projectm/lib/` for about three
minutes with `AudioBufferSamples` changed 576 → 1024 (an experiment to give the FFT
butterchurn's window; abandoned for a separate 1024-sample history). `WaveformAligner`
sizes its octave tables from that constant and its `Align(std::array<float,1024>&)` frame is
what the four `.ips` reports show. Another session ran `build-app.sh` in that window and
shipped it. The engine that ended up in the tree afterwards (sha `bf78195d…`) is all-576 and
soaked 12 s on Tunnel and on Mosaic without a fault; the committed engine is back in
`vendor/` now and the debug binary is relinked against it. The proposed source changes do not
need a rebuilt engine except for item 3.

## Files

- `side-by-side.mp4`: web5 | native1 (raw) | bc1 | rs1, 10 s, same clip.
- `side-by-side-colour-tag.mp4`: web7 | native tagged sRGB | native untagged.
- `sheet-all-runs.png`, `timeline-all-runs.png`, `silent-web-vs-native.png` (both engines are
  black in silence; the native one draws a faint lattice from frame 57).
- `pairs.txt`, `aggregates.txt`, `colour-tag.txt`, `beat-index.txt`, `model-beats.txt`.
- `proposed-app.diff`: the app-side diff; `walkie-audio-time.patch`: the library side.
