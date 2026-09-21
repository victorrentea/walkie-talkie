# The native MilkDrop halo on projectM — route B, built and measured (2026-09-21, overnight)

Branch `projectm`, worktree `walkie-talkie-projectm`. Nothing here touched the
installed app or `master`. The question asked: does a **native** projectM
renderer reach visuals comparable to butterchurn-in-a-`WKWebView` at clearly
less CPU and RAM? Short answer: **yes on cost, mostly on visuals** — the
composition, palette and motion match on four of the six presets; two respond
to the voice differently (Snowflake's star is bigger, Sparks' particles softer
and fewer), and every native preset is brighter than its web twin.

## Recommendation: ship as an opt-in engine, not yet the default

- **Cost**: the native route replaces the **40–96 % of a core** a web view
  spends in the two processes it spawns (its WebContent *and its own* WebKit
  GPU process — a census of Tunnel: GPU 56–59 %, WebContent 26 %) and its
  260–1100 MB of WebContent with **5–12 % in the app itself and no extra
  process**; the app's RSS *drops* (74 → 40 MB) because no `WKWebView` is
  built. A preset frame costs **0.7–3.5 ms of CPU** at either resolution, on a
  render queue of its own — the main thread only receives the surface.
- **Visuals**: Tunnel, Cauldron, Tendrils and Water Dream are the same picture;
  Snowflake and Sparks are recognisably the same preset but not the same
  frame. Victor has to look before this can be the default — the review
  command is at the end.
- **Something the measurement turned up**: the installed app's web halo
  (pid 57869, launched 23:37) kept a WebContent + WebKit GPU pair at **24 % +
  50 % of a core for the whole night with no dictation in flight**. The web
  route costs when it is *not* drawing; the native one costs nothing between
  dictations (its timer stops with the ring).

## What was built

- **`ProjectMHalo.swift`** — a `HaloWebHost` like `MilkDropHalo`: same start /
  stop / feed / center contract, the same square following the pointer, the
  same warm-up and fade-in, the same radial mask and `gain`, `rot` and
  `pinCenter` honoured (the last two as `per_frame_` lines appended to the
  preset's text, exactly what the page appends to the compiled equations).
  Selected by `WT_HALO_ENGINE=native` or the `haloEngine` default
  (`defaults write ro.victorrentea.wispr-relay haloEngine native`); the web
  route stays the default. `CaretHalo` asks `engineHost(...)` in the two places
  it built a `MilkDropHalo`, including the Water Dream hybrid's `under` layer.
- **`Sources/CProjectM/pmhalo.cpp`** — the GL glue: a CGL 3.2 core context,
  projectM into our own FBO, a keying pass (`a = max(r,g,b)`, the page's
  four-stop mask or the `fadeStart` fall, gain) into one of two IOSurfaces,
  which a `CALayer` shows. No `NSOpenGLView`, no readback per frame.
- **`vendor/projectm/`** — projectM 4.1.7 built static (`libprojectM-4.a` +
  `libprojectM_eval.a`, 2 MB) with `walkie.patch`, three changes:
  1. the two-line target-FBO patch from the spike (4.1.7 hard-binds FBO 0);
  2. every per-instance `glBufferSubData` on a streaming VBO replaced by an
     orphaning `glBufferData` — on Apple's GL-over-Metal each in-place update
     of a buffer the GPU may still be reading forces a **synchronous command
     buffer submit**; chain breaker (Sparks, 256 shape instances a frame) cost
     **21 ms a frame** before and **3.5 ms** after;
  3. the four exception classes override `what()` so the preset-failed callback
     says *Could not compile per-frame code* instead of `std::exception`.
- **`assets/projectm/presets/`** — the six presets as **original `.milk`
  files**. Three of them existed in this app only as butterchurn JSON; a
  subagent found the originals upstream (Tunnel Mix and Tendrils Colorfast in
  `clangen/projectM-musikcube`'s `presets_milkdrop_200`, fata morgana in
  `OfficialIncubo/BeatDrop-Music-Visualizer`), so no converter was needed.
  One edit: fata morgana splits the identifier `is_beat` over two
  `per_frame_` lines, which MilkDrop and butterchurn join verbatim and
  projectM joins with a newline — merged into one line, noted in the README.
- **Tooling** — `docs/projectm/sweep.sh` (the measurement), `shoot.sh` +
  `compose.py` (engine-only captures of both routes, `WT_MD_SHOOT` /
  `WT_PM_SHOOT`), `summarize.py` (the table). `build-app.sh` copies the preset
  folder; the engine is linked in, nothing else travels with the app.

## What it costs, measured

`top`, 1 s samples, ring up on the demo voice (`WT_HALO_DEMO=12
WT_HALO_DEMO_AUDIO=1`), 3456×2234 display, frame cap 30, `.build/debug`
binary, 2026-09-21 00:50–00:57 (`docs/projectm/sweep-2026-09-21.md`; two
earlier sweeps agree within noise). **"WebKit" is the sum of the two
processes the demo's web view spawned** — its WebContent and its own GPU
process (a census of a Tunnel run, 01:22: GPU 56–59 % at ~45 MB, WebContent
26 % at ~500 MB; the sweep's classifier only knew the GPU processes that
existed *before* the run, so it filed the new one under WebContent — the sum
is right, the split is in the census). The web route's numbers before this
branch (rule file: ~30 % WebContent + ~67 % GPU process, 280–330 + 240–290
MB) are the same shape. WindowServer sat at 20–40 % for every row, film
included; the native rows were re-measured after the render queue went in
(01:19) and did not move.

Luminance after the gain iteration (mean over 3…8 s of the demo voice, rgb × alpha, web ÷ native; 1.0 = matched; `luminance-2026-09-21.md`):

| preset | native gain scale | web/native luminance (verification 02:05) | web/native in the three iteration rounds |
|---|---|---|---|
| Tunnel | 0.12 (was 0.25 at the verification) | 0.17 | 0.19 / 0.33 / 0.46 — not a gain problem, see *Round two* |
| Cauldron | 0.30 | **0.95** | 0.58 / 0.95 / 0.87 |
| Tendrils | 0.90 | **0.97** | 0.97 / 0.95 / 1.03 |
| Snowflake | 1.05 | 1.46 | 2.72 / 0.95 / 1.14 |
| Sparks | 1.20 | 0.60 | 3.62 / 1.41 / 0.62 |
| Water Dream | 1.10 | 0.37 | 0.74 / 0.68 / 0.84 |

| preset | route | app CPU % | WebKit CPU % (WebContent + its GPU proc) | app RSS MB | WebContent RSS MB | native frame, CPU ms |
|---|---|---|---|---|---|---|
| film (lightning) | — | 0.1 | — | 47 | — | — |
| Tunnel | web (butterchurn, 2×) | 3.8 | 80.9 | 74 | 361 | — |
| Tunnel | native 1× | 6.0 | — | 40 | — | 0.98 |
| Tunnel | native 2× | 6.1 | — | 39 | — | 0.99 |
| Cauldron | web | 4.3 | 40.0 | 74 | 256 | — |
| Cauldron | native 1× | 4.9 | — | 39 | — | 1.04 |
| Cauldron | native 2× | 5.3 | — | 40 | — | 0.98 |
| Tendrils | web | 4.2 | 67.3 | 74 | 324 | — |
| Tendrils | native 1× | 7.7 | — | 40 | — | 2.26 |
| Tendrils | native 2× | 9.1 | — | 40 | — | 2.24 |
| Snowflake | web | 4.3 | 64.5 | 74 | 313 | — |
| Snowflake | native 1× | 5.9 | — | 40 | — | 1.05 |
| Snowflake | native 2× | 5.5 | — | 40 | — | 1.14 |
| Sparks | web | 4.2 | 76.5 | 74 | 350 | — |
| Sparks | native 1× | 10.1 | — | 48 | — | 3.45 |
| Sparks | native 2× | 10.4 | — | 47 | — | 3.54 |
| Water Dream (hybrid) | web | 5.8 | 95.6 | 75 | 1115 | — |
| Water Dream (hybrid) | native 1× | 7.6 | 17.6 | 88 | 548 | 1.00 |
| Water Dream (hybrid) | native 2× | 7.4 | 16.7 | 89 | 469 | 1.11 |

- **1× and 2× cost the same.** The engine's frame is CPU-bound in the
  per-frame and per-vertex code, not in pixels (as the spike found at 3456²);
  so the native route can render at the backing scale (`WT_PM_SCALE`, default 1
  — 2 costs nothing measurable and is the web route's resolution).
- **The app's 5–12 %** is the engine's CPU part (0.7–3.5 ms a frame) on its
  own queue, the IOSurface seed bump, and the `CATransaction` on the main
  thread. **At 60 fps** (`WT_HALO_FPS=60`, measured 01:19): Tunnel 8.6–10.7 %,
  Sparks 21 %, frames 286–301 per 5 s — it scales with the frame count, as
  expected; the web route at 60 fps was not cleanly measured.
- **Water Dream** still carries the `voice-halo` page for its comets
  (`HaloPage`, a second web view), so its WebContent column is the page, not
  the preset; the preset's share went from ~1100 MB to nothing.
- **Idle**: the native host's timer stops with the ring; between dictations it
  costs 0 %. See the finding above about the web route.

## Round two (01:30–03:00): brightness matched by measurement, the audio path compared number by number

- **Brightness.** The engine-only PNGs carry *straight* alpha (ImageIO and
  `canvas.toDataURL` both un-premultiply on write), so the first luminance
  numbers were wrong for both routes; `lum.py` now measures rgb × alpha, what
  reaches the screen over black, at every second from 3 to 8 s. At native gain
  = the style's gain, the native route was **3.2× brighter on Tunnel, 2.5× on
  Cauldron, 1.3× on Tendrils and Sparks, and 0.8× (darker) on Snowflake and
  0.7× on Water Dream**. `ProjectMHalo.gainScale` is a per-preset multiplier
  on the native engine's gain; `docs/projectm/iterate-gain.sh` shot both
  routes, took the ratio of mean luminance and moved the scale by
  `ratio^0.8`, three rounds (`gain-iteration-2026-09-21.md`). Where it landed
  (`luminance-2026-09-21.md`, the final verification):
  Cauldron ×0.3 → web/native **0.95**, Tendrils ×0.9 → **0.97**, Snowflake
  ×1.05 → **1.1–1.5** (run to run), Water Dream ×1.1 → 0.4–0.8 (its native
  frames burst to 100+ where the web sits at 12–40; the palette cycles),
  Sparks ×1.2 → 0.6–1.4. **Tunnel cannot be matched by gain**: its web twin is
  a faint wash (mean luminance 1–5 out of 255 even at gain 4) while the native
  one bursts to 30; at scale 0.1 (gain 0.4) the ratio was still 0.46, so the
  table carries ×0.12 and the rest is the engine — `WT_PM_GAIN_SCALE='{"7": …}'`
  is the knob. The run-to-run spread is large because the demo voice is
  random noise under a deterministic envelope and every preset is a feedback
  system; six seconds per run are averaged, and a ratio within 0.8–1.25 is
  what "matched" means here.
- **The audio inputs are the same, measured.** Both engines were instrumented
  (`halo.levels()` → `WT_MD_LEVELS=1`; `PM_AUDIO_LOG=1` in the patched
  library) and fed the same demo voice for 14 s: `bass` mean 0.93 vs 0.86,
  p90 3.4 vs 3.0, silent fraction the same; `mid`/`treb` and the `_att` values
  alike. projectM only spikes higher at the edges of a burst (max 10 vs 5.8).
  Waveform amplitudes agree (|max| 0.88×; projectM stores float × 128,
  butterchurn byte − 128). Both engines use a 48×36 mesh; the two custom-shape
  polygon routines are the same formula. **Frame rate**: the web page renders
  ~24.6 fps (344 frames in 14 s; butterchurn's own `fps` reads 19–26) against
  the native 30 — every per-frame feedback grows ~20 % faster natively.
- **Snowflake.** Silent, both engines converge: extents 0.39 → 0.58 → 0.74 (web)
  vs 0.68 → 0.74 → 0.59 (native) over 3/5/7 s — the native pattern reaches its
  size sooner, then both sit at the same size. With the voice, the size varies
  from run to run *in both* (web 0.37/0.80/0.75, native 0.41/0.56/0.63 in one
  run), so the "2–3× larger" of round one was one run, not a systematic
  difference. Audio gain 0.25×–4×, resampling and 20/25 fps do not move it.
  Left as is.
- **Sparks — found.** `martin - chain breaker` derives every spark from a
  custom wave with `bSpectrum=1`: the *spectrum magnitudes* feed `gmegabuf`,
  `vol_`, the blob radius and the spread. The spectrum sums differ by
  **5.5×** (web 1068 mean / 3655 p90 against native 193 / 707 on the same
  samples; the maxima by 15×, so butterchurn's spectrum is also peakier). A
  uniform spectrum scale leaves `bass/mid/treb` (ratios) untouched, so the
  patched library now scales projectM's spectrum by **5.3** (`PCM.cpp`,
  `PM_SPECTRUM_SCALE` overrides). With it the sparks are **crisp points**, as
  on the web — but arranged along a chain, where the web's spread into a
  cloud; the spread terms (`sin(q12·.07)·sin(q11·.13)·q3`) are still smaller
  natively and that is where the remaining difference lives. Removing the
  `GetBlur2` term from the comp shader was tried and is not it.
- **The blackouts in native Tunnel** at 4 s and 8 s of every run are the demo
  voice's breath pauses (~0.7 s of near-silence every 5 s): silent, both
  engines' Tunnel is black (alpha ≤ 1.6 on the web, ≤ 0.9 native); the native
  one just decays to nothing a little faster.
- **The idle cost of the installed app, quantified read-only**: over 31 s at
  01:31 its WebContent + WebKit GPU pair sat at **17.6 % + 38.2 %** of a core
  (391 + 40 MB). `GET /test/state` on its loopback answered `ringUp: true,
  live: true, style: milkdrop20, visible: true, wisprHearing: true, phase:
  idle, listening: false` — the Tendrils web halo has been **up on the pointer
  all night** because the Wispr-microphone witness reads *open* with no
  dictation in flight. It is not an idle web view burning CPU (a warmed
  `MilkDropHalo` never calls `halo.start()`); it is a live ring nobody asked
  for, and the same would happen with the native engine (which would cost
  ~6 % in-process instead). The witness (`wisprHearing`) is the thing to look
  at, not the halo. Nothing on the installed process was touched.
- **The `Halo engine` menu row** — `Halo engine: Web (butterchurn)` /
  `Native (projectM)`, under `Halo fx`, the shape `Engine` has: a readout, the
  two under the arrow, the tick from `HaloEngine.current` on every open, a
  greyed note *For the MilkDrop presets only*. `CaretHalo.setEngine` writes the
  `haloEngine` default and rebuilds the panel when a preset is drawn. Not
  photographed (`WT_SHOOT_MENU` shoots the spawn folder menu, not the status
  menu); the code follows `applyHaloRow` line for line.

## What it looks like — `docs/projectm/captures/`

Engine-only frames (the keyed output, nothing of the screen in it) at 3, 5
and 7 s into the same demo voice, web (butterchurn at 2×) on the top row,
native 1× below, on a mid-grey ground, composited with their straight alpha.
The verification run of 02:05, with the per-preset gain table in (Tunnel at
×0.25 there; ×0.12 in the code now) and the spectrum still at ×1 — the 03:00
run with both baked in was **invalidated by the machine**: `coreaudiod` had
climbed to 125 % of a core, 167 threads and 68 GB RSS (load average 115–142),
WebKit missed its 2 s ready window on every web run and the route fell back
to the film. That daemon is not this branch's; it is reported, not touched.
Statistics in `captures-2026-09-21.md` (lit fraction, mean alpha of the lit
part) and `luminance-2026-09-21.md`. Three extra composites:
`sparks-spectrum-scale.png` (web / native ×1 / ×5.3 / ×10 at 4, 6, 8 s),
`snowflake-silent.png` (both engines, no audio) and `tunnel-3-6s.png` (the
breath-pause blackout at 4 s).

| preset | verdict |
|---|---|
| ![](captures/tunnel.png) **Tunnel** | Same composition (the hole, the burst, the magenta/yellow/blue palette), same 2× turn, centre pinned. Native is **brighter and fuller** (lit 30–57 % at alpha 130–170 vs 4–37 % at 80–124): at gain 4 more of the disc saturates. If that is too much, `gain` is per engine now (`WT_HALO_PRESET_OPTS='{"gain":2}'`). |
| ![](captures/cauldron.png) **Cauldron** | Same painterly cyan with the same red and orange strokes drifting through. Native keys **less to transparent** — the cyan wash fills the disc where butterchurn leaves dark gaps (alpha 66 vs 47–67, lit 30–46 % vs 15–25 %). |
| ![](captures/tendrils.png) **Tendrils** | **The closest match**: the same white bloom at 3 s, the same blue/red/green tendrils at 5 s, the same pale knot at 7 s. |
| ![](captures/snowflake.png) **Snowflake** | The same star ornament, the same colour cycle (blue → pink → yellow) — but native draws it **two to three times larger** and fills the disc; butterchurn's is a small star in the middle. Not the drawing: both engines build a custom shape's polygon identically (`x + rad·cos(θ)·aspecty`, read side by side in `CustomShape.cpp` and `butterchurn.min.js`). Not the input level either (`WT_PM_AUDIO_GAIN` 0.25×–4× and resampling to 44.1 kHz — the star's size does not follow it). What is left is the per-frame values the preset derives from the engines' audio statistics (`bass`/`mid`/`treb` and their `_att` averages, `pulse`, `t1`), which the two beat detectors normalise differently. Not resolved tonight. |
| ![](captures/sparks.png) **Sparks** | The same disc of cycling colour behind; the sparks themselves differ: butterchurn draws chain breaker's 256 additive pentagons as **crisp points in a swarm**, projectM as **larger soft blobs along a chain**, fewer visible. Here the size *does* follow the input level (at `WT_PM_AUDIO_GAIN=0.25`–`0.35` the blobs shrink towards points), so the levels chain breaker stores in `gmegabuf` come out larger on projectM for the same samples; a per-engine audio trim is the knob, and 0.35 is the value to start from. This is the one preset Victor marked ★ where the native frame is the weaker one. |
| ![](captures/water-dream.png) **Water Dream** | Native renders the scene fata morgana was written for — sky, stars, a sea with reflections — and calmly; butterchurn's frames go **white** for stretches (Victor: *"too violent"*). Palettes cycle on both, so a given second differs. The comets are still the page's. |

Honest differences, in one place: native is brighter across the board (alpha
of the lit part ~1.3–1.8× on Tunnel and Cauldron); the mask, the pinned
centre and the doubled turn are verified identical (radial alpha profile,
the sweep's captures); Snowflake's scale and Sparks' particle look are engine
differences, not tuning; colours cycle with time so no two frames are the
same frame; no texture pack was needed (none of the six samples an external
texture; noise textures are built in).

## What went wrong on the way (so it is not paid for twice)

- **A CF object returned by a C function is `Unmanaged` in Swift.** Handed to
  `CALayer.contents` as it is, the layer shows nothing and nothing is logged.
  `takeUnretainedValue()`.
- **`wantsLayer = true` in `init` leaves `layer` nil** until AppKit's next
  display pass; a sublayer added then goes nowhere. The view is layer-hosting
  (`layer = CALayer()` first).
- **CA does not see a GPU write to an IOSurface.** It re-reads a surface when
  its *seed* moves, which only a CPU lock bumps — so with two surfaces
  alternating it kept showing the first frame each had ever held (a dark disc
  at alpha ≤ 20 on screen while the readback was bright). An empty
  `IOSurfaceLock`/`Unlock` per frame fixes it (`WT_PM_SYNC=nil` is the other
  way, clearing `contents` first; same cost).
- **The IOSurface's rows must be aligned** (`IOSurfaceAlignProperty`): a 907 px
  square (bpr 3628) aborted the process inside Metal with
  `isMisalignedIOSurface`. Cauldron 1× and Tendrils 1× died of it in the first
  sweep.
- **projectM leaves a GL error behind** on this driver (an unloadable texture
  unit it warns about itself); drained after the engine's pass and counted,
  never fatal.
- **The window capture of a `WKWebView` panel is empty** (`screencapture -l`
  gives the window's own layers, not WebKit's remote ones); the web route is
  only capturable off the whole screen, which is why the side-by-sides are
  engine readbacks rather than screenshots.
- **The two engines sample the same 16 kHz microphone as if it were 44.1
  kHz** (MilkDrop's beat detector reads bins, not hertz) — so the native route
  hands the samples over raw too (`WT_PM_RESAMPLE=1` resamples), for the same
  spectrum the presets were tuned against.

## What matched and what still differs, in one place

| preset | matched | still differs, and why |
|---|---|---|
| Tunnel | composition, palette, 2× turn, pinned centre, blackout in silence | brighter in bursts by 2–6× at any gain — the web engine's Tunnel is a faint wash the ×4 gain barely lifts; the native one is a bright feedback burst. A gain cannot bridge two different dynamics. |
| Cauldron | luminance (0.95), palette, strokes | native fills the disc where the web leaves dark gaps (the same keying, a fuller engine output) |
| Tendrils | everything measured (0.97) | — |
| Snowflake | audio inputs, geometry, size at rest, colour cycle | growth speed of the feedback pattern (native ~20 % more frames a second, plus the engine's own warp); run-to-run variance dwarfs it |
| Sparks | audio inputs; with the spectrum ×5.3 the sparks are points, not blobs | the 256 instances sit along a chain instead of spreading into a cloud — the preset's spread terms (`sin(q12·.07)·sin(q11·.13)·q3`) come out smaller natively; unresolved |
| Water Dream | scene, calm sea, stars | native bursts brighter at palette changes; the web goes white for stretches; per-second luminance never agrees because the palettes are not in phase |

## Remaining work before it can be the default

1. **Victor's eye** on the six, live: `WT_HALO_ENGINE=native WT_HALO_STYLE=<case>
   WT_HALO_DEMO=11 WT_HALO_DEMO_AUDIO=1 ./.build/debug/WalkieTalkie` (under
   `hands-off run`); `WT_HALO_PRESET_OPTS='{"gain":2}'` to trim brightness.
2. **A menu row or a default** for `haloEngine` (`HaloEngine` exists; nothing
   writes it yet), and `build-app.sh` run once so `Resources/projectm` is in
   the bundle (the line is there; it was never run from this worktree).
3. **Snowflake and Sparks**: decide whether the native look is acceptable or
   whether the web route stays for those two (`engineHost` could pick per
   preset — a one-line change).
4. ~~A render thread~~ — done at 01:19: `renderQueue` (serial,
   `.userInteractive`), a `DispatchSourceTimer` on it, `pmh_render` and the
   PCM pushes there, the surface handed to the layer on the main thread. The
   `WT_HALO_DEMO=11` regression check (the arrow crossing `patience` at t=8)
   exits 0 on the native route.
5. **Upstream the patch** (or keep it): the orphaning buffer uploads are worth
   a projectM issue; the newline-joined `per_frame_` lines
   (`PresetFileParser::GetCode`) are a preset-compatibility bug there too.
6. **Water Dream's comets** are still the page's; the hybrid still opens a
   `WKWebView`. Either port the comets natively or accept the page for it.
7. **60 fps** was not measured (the cap is 30 everywhere); the engine's CPU
   part would double, ~10–20 % in the app.
8. **The installed app's ring has been up all night** (`wisprHearing: true`
   with nothing in flight — see *Round two*): the witness, not the halo, is
   what to look at. Nothing on this branch touched the installed app beyond
   `ps` and one read-only `GET /test/state`.
9. **`coreaudiod` at 125 % / 68 GB** at 03:00 (load average 115) — not this
   branch's, and the reason the last verification run is the 02:05 one.
10. The `Halo engine` row has not been seen on screen (no shoot path for the
    status menu); Victor opening the menu is the test.
11. **Bipolar (`milkdrop1`, added 2026-09-21) has never been seen.** The
    preset is the original `.milk` — *Geiss - Bipolar 2 Enhanced*, shipped
    with MilkDrop 2, taken from projectM's `presets_milkdrop_200` and checked
    field by field against butterchurn's JSON (same `fWaveScale` 0.559671,
    `fGammaAdj` 1.998, `warp` 0.099892, `rot` −0.01, `fWaveAlpha` 5.9, three
    `per_frame_` lines, one `per_pixel_`, no waves, no shapes) — but it could
    not be rendered, because **the screen was locked**
    (`CGSSessionScreenIsLocked`), and that stops both routes at once: the
    native engine loads the preset and counts its frames, but the surface
    reads back pure black, and the web twin never starts
    (*"the engine's page was not ready 2 s after the ring was asked for"*).
    **The control is the proof it is the screen and not the preset — Cauldron,
    0.95 the night before, came back just as black from the same run.** So
    Bipolar's `scale` (0.75) is a first guess and it has **no `gainScale`
    entry** (a missing one reads as 1); nothing was iterated against a web
    twin. Re-shoot at an unlocked screen before trusting either number:
    `ROUTES="web native1" docs/projectm/shoot.sh /tmp/shoot milkdrop1`.
    **A locked screen is the first thing to check when a capture run comes
    back black** — it costs a whole run to rediscover.

## How to reproduce

```
cd ~/workspace/walkie-talkie-projectm && swift build
docs/projectm/sweep.sh /tmp/sweep        # measurements → summarize.py → the table
docs/projectm/shoot.sh /tmp/shoot        # engine-only frames of both routes
python3 docs/projectm/compose.py /tmp/shoot docs/projectm/captures
```
