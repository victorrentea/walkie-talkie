/* ===========================================================================
   apă — comete oglindite în apa de jos
   ---------------------------------------------------------------------------
   Apă pe treimea de jos a ecranului, comete care orbitează în jurul centrului
   (adică în jurul cursorului), iar tot ce e deasupra liniei de apă se oglindește
   dedesubt, unduit. Stă în fișier separat fiindcă index.html e deja lung.

   Ce NU se atinge, oricât de inofensiv ar părea (fiecare a costat o iterație):

   · ORDINEA de desen — cer pe pânza offscreen → cerul pe ecran → gradientul apei
     → feliile de reflexie → tenta „multiply" de adâncime → licăr + linia de apă.
     Orice permutare strică fie reflexia, fie culoarea apei.
   · MODURILE de compunere — `lighter` pentru felii (cerul negru nu adaugă nimic,
     urcă doar lumina), `multiply` pentru tenta de adâncime, `source-over` la
     final, ca următorul cadru să nu moștenească altceva.
   · TRUCUL de oglindire — o singură răsturnare verticală în jurul liniei de apă
     (`translate(0,waterY); scale(1,-1)`) plus REFLECT_SQUASH. Fără turtire, doar
     cei ~220 px de deasupra liniei ar ajunge vreodată în apă și cometele n-ar
     atinge niciodată bazinul.
   · SKY_MARGIN se consumă EȘANTIONÂND în margine (`sx`), nu decalând destinația.
     Dacă decalezi destinația, felia se termină înainte de marginea bazinului și
     apare o cusătură verticală tăioasă exact acolo.

   Integrare: fără audio propriu și fără rAF propriu — pagina cheamă draw() o dată
   pe cadru cu level/bass/treble din analizorul ei și cu centrul deja calculat
   (centrul ecranului + „plimbarea"), ca vârful cursorului să stea în mijloc.
   =========================================================================== */
(function () {
'use strict';

/* ==========================================================================
   PARAMETER BLOCK  — everything tunable lives here, nothing else is magic.
   ========================================================================== */
const P = {
  /* ---- waterline -------------------------------------------------------- */
  WATER_Y:            0.80,  // waterline as a fraction of viewport height. Was 0.74; Victor
                             // asked for the pool to take only the bottom fifth. Shallower pool
                             // is safe for the reflection because REFLECT_SQUASH (0.42) means
                             // 169 px of water still mirror ~400 px of sky — the band the
                             // comets orbit in — so the pool never shows just empty sky.

  /* ---- reflection ------------------------------------------------------- */
  SKY_MARGIN:        56,     // CSS px of extra scene rendered off-screen left AND right.
                             // Ripple shifts each mirrored slice sideways; without a margin
                             // the shifted slice runs out of source and leaves a hard
                             // vertical seam at the edge of the pool. Must be >= the largest
                             // possible ripple offset (RIPPLE_AMP * 1.6 * (1+RIPPLE_AUDIO)).
  SLICE_H:            3,     // CSS px per mirrored slice. 2-4 is the sweet spot:
                             // smaller = smoother ripple but more drawImage calls
                             // (waterHeight/SLICE_H calls per frame, ~73 at 3px/844h).
  REFLECT_ALPHA:      1.00,  // brightness of the reflection right under the line
  REFLECT_FADE:       1.35,  // exp(-depth*FADE): how fast the mirror image dies with depth
  REFLECT_SQUASH:     0.42,  // perspective foreshortening: 1 CSS px of water depth mirrors
                             // 1/SQUASH px of sky. <1 is what makes a shallow-angle water
                             // view work -- at 1.0 only the 220px directly above the line
                             // would ever be visible, so the comets never reach the pool.
  TINT_TOP:    [232,240,255],// multiply-tint at the waterline (almost neutral)
  TINT_BOT:    [126,176,255],// multiply-tint at the bottom (strong blue shift)

  /* ---- ripples (the whole "it's water" illusion) ------------------------ */
  RIPPLE_AMP:         9.0,   // CSS px of horizontal slice offset at max depth, silence
  RIPPLE_DEPTH_GAIN:  1.0,   // how much more the deep slices wobble than the shallow ones
  RIPPLE_MIN:         0.12,  // wobble floor at the waterline (so the surface isn't glass)
  RIPPLE_F1:          0.055, // spatial frequency of wave 1 (per CSS px of depth)
  RIPPLE_S1:          1.25,  // temporal speed of wave 1 (rad/s)
  RIPPLE_F2:          0.017, // wave 2: long, slow swell that de-synchronises wave 1
  RIPPLE_S2:          0.62,
  RIPPLE_AUDIO:       2.4,   // extra ripple amplitude at level=1 (x1 -> x3.4)

  /* ---- comets ----------------------------------------------------------- */
  COMETS: [                  // r = orbit radius as a fraction of min(vw,vh)/2
    { r:0.30, spd: 0.62, hue:190, w:3.4, tail:1.05, phase:0.0  },
    { r:0.46, spd:-0.41, hue:265, w:2.8, tail:0.85, phase:2.1  },
    { r:0.62, spd: 0.29, hue:160, w:2.2, tail:0.70, phase:4.0  },
    { r:0.80, spd:-0.19, hue:325, w:1.7, tail:0.55, phase:5.4  }
  ],
  TAIL_SEGMENTS:     22,     // segments per tail; alpha^2 taper. 22 reads smooth at 390px
  TAIL_AUDIO:         0.9,   // tail lengthens by this fraction of its span at level=1
  SPEED_AUDIO:        1.8,   // orbital speed multiplier added at level=1 (idle stays 1.0)
  BRIGHT_AUDIO:       0.85,  // extra brightness at level=1
  HEAD_R:             5.5,   // CSS px radius of the comet head glow core
  BASS_RADIUS:        0.10,  // orbit radius breathes by this fraction on bass
  TREBLE_FLICKER:     0.35,  // per-comet brightness jitter driven by treble

  /* ---- centre (the mouse cursor lives here) ----------------------------- */
  CENTER_CLEAR_R:    26,     // CSS px kept clear so a drawn cursor stays legible
  CENTER_HALO_R:     92,     // outer radius of the halo ring around the clear zone
  CENTER_FOLLOW:      0.10,  // prototype only: lerp of the centre chasing the pointer.
                             // In Voice Halo the page IMPOSES the centre (viewport centre
                             // + "plimbare"), so it is snapped, not chased -- a lerp here
                             // would leave the drawn cursor trailing behind its own halo.

  /* ---- sky / background ------------------------------------------------- */
  STARS:            110,     // static stars above the line (they reflect too)
  BG_TOP:      [  6, 10, 24],
  BG_BOT:      [  3,  5, 12],
  WATER_TOP:   [  8, 16, 34], // water body colour just below the line
  WATER_BOT:   [  2,  4, 11],

  /* ---- audio ------------------------------------------------------------
     The prototype had its own analyser; the host page drives level/bass/treble
     instead, so FFT / SMOOTH_* / LEVEL_GAIN live in index.html now. */
};

/* ==========================================================================
   canvas plumbing
   ========================================================================== */
const sky  = document.createElement('canvas');     // offscreen: everything ABOVE the line
const sctx = sky.getContext('2d');

let W = 0, H = 0, DPR = 0, waterY = 0, waterH = 0, M = 0, stars = [];
const rgb = (a, al) => `rgba(${a[0]},${a[1]},${a[2]},${al})`;

function resize(cv, ctx, w, h, dpr) {
  if (W === w && H === h && DPR === dpr) return;
  W = w; H = h; DPR = dpr;
  waterY = Math.round(H * P.WATER_Y);
  waterH = H - waterY;
  M = P.SKY_MARGIN;
  cv.style.width = W + 'px'; cv.style.height = H + 'px';
  cv.width  = Math.round(W * DPR);        cv.height  = Math.round(H * DPR);
  sky.width = Math.round((W + 2 * M) * DPR); sky.height = Math.round(waterY * DPR);
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  sctx.setTransform(DPR, 0, 0, DPR, M * DPR, 0);   // sky is in viewport coords, shifted by M
  stars = [];
  for (let i = 0; i < P.STARS; i++)
    stars.push({ x: -M + Math.random() * (W + 2 * M), y: Math.random() * waterY,
                 r: 0.4 + Math.random() * 1.2, a: 0.22 + Math.random() * 0.7,
                 tw: Math.random() * 6.28 });
}

/* ==========================================================================
   THE DRAW FUNCTION
   t: seconds (monotonic). level/bass/treble: 0..1-ish, already smoothed by the
   page. cx/cy: the orbit centre in CSS px — the page puts the cursor there.
   ========================================================================== */
function draw(cv, ctx, t, level, bass, treble, cx, cy, dpr) {
  resize(cv, ctx, innerWidth, innerHeight, dpr);
  const center = { x: cx, y: cy };

  /* ---------- 1. the sky (offscreen), i.e. everything that will reflect --- */
  const g = sctx.createLinearGradient(0, 0, 0, waterY);
  g.addColorStop(0, rgb(P.BG_TOP, 1)); g.addColorStop(1, rgb(P.BG_BOT, 1));
  sctx.globalCompositeOperation = 'source-over';
  sctx.fillStyle = g; sctx.fillRect(-M, 0, W + 2 * M, waterY);

  sctx.globalCompositeOperation = 'lighter';
  for (const s of stars) {
    const a = s.a * (0.65 + 0.35 * Math.sin(t * 0.8 + s.tw));
    sctx.fillStyle = `rgba(200,220,255,${a})`;
    sctx.beginPath(); sctx.arc(s.x, s.y, s.r, 0, 6.2832); sctx.fill();
  }

  // centre halo: a soft ring whose inner edge ramps up only past CENTER_CLEAR_R, so the
  // cursor sits on untouched background. Ramped, not punched -- a hard hole reads as a
  // black disc against the glow.
  const HR = P.CENTER_HALO_R * (1 + 0.5 * bass);
  const cf = Math.min(0.85, P.CENTER_CLEAR_R / HR);
  const hg = sctx.createRadialGradient(center.x, center.y, 0, center.x, center.y, HR);
  hg.addColorStop(0, 'rgba(90,150,255,0)');
  hg.addColorStop(cf, 'rgba(90,150,255,0)');
  hg.addColorStop(Math.min(0.98, cf + 0.26), `rgba(110,175,255,${0.11 + 0.24 * level})`);
  hg.addColorStop(1, 'rgba(60,90,200,0)');
  sctx.fillStyle = hg;
  sctx.beginPath(); sctx.arc(center.x, center.y, HR, 0, 6.2832); sctx.fill();

  // comets
  const unit  = Math.min(W, H) * 0.5;
  const speed = 1 + P.SPEED_AUDIO * level;
  sctx.lineCap = 'round';
  for (let i = 0; i < P.COMETS.length; i++) {
    const c = P.COMETS[i];
    const R = unit * c.r * (1 + P.BASS_RADIUS * bass * Math.sin(t * 0.7 + i));
    const ang  = c.phase + t * c.spd * speed;
    const span = c.tail * (1 + P.TAIL_AUDIO * level) * Math.sign(c.spd);
    const flick = 1 + P.TREBLE_FLICKER * treble * Math.sin(t * 9.1 + i * 2.3);
    const bri  = (1 + P.BRIGHT_AUDIO * level) * flick;
    const col  = (a) => `hsla(${c.hue + 25 * level},100%,${62 + 12 * level}%,${a})`;

    let px = center.x + Math.cos(ang) * R, py = center.y + Math.sin(ang) * R;
    for (let j = 1; j <= P.TAIL_SEGMENTS; j++) {
      const f  = j / P.TAIL_SEGMENTS;
      const a2 = ang - span * f;
      const nx = center.x + Math.cos(a2) * R, ny = center.y + Math.sin(a2) * R;
      const fade = (1 - f) * (1 - f);
      sctx.strokeStyle = col(Math.min(1, 0.55 * fade * bri));
      sctx.lineWidth   = c.w * (0.25 + 0.75 * (1 - f));
      sctx.beginPath(); sctx.moveTo(px, py); sctx.lineTo(nx, ny); sctx.stroke();
      px = nx; py = ny;
    }
    // head
    const hx = center.x + Math.cos(ang) * R, hy = center.y + Math.sin(ang) * R;
    const hr = P.HEAD_R * (1 + 0.6 * level);
    const hgd = sctx.createRadialGradient(hx, hy, 0, hx, hy, hr * 3);
    hgd.addColorStop(0,   `hsla(${c.hue},100%,92%,${Math.min(1, 0.95 * bri)})`);
    hgd.addColorStop(0.3, col(Math.min(1, 0.55 * bri)));
    hgd.addColorStop(1,   `hsla(${c.hue},100%,60%,0)`);
    sctx.fillStyle = hgd;
    sctx.beginPath(); sctx.arc(hx, hy, hr * 3, 0, 6.2832); sctx.fill();
  }

  /* ---------- 2. blit the sky ------------------------------------------- */
  ctx.globalCompositeOperation = 'source-over'; ctx.globalAlpha = 1;
  ctx.drawImage(sky, M * DPR, 0, W * DPR, waterY * DPR, 0, 0, W, waterY);

  /* ---------- 3. water body --------------------------------------------- */
  const wg = ctx.createLinearGradient(0, waterY, 0, H);
  wg.addColorStop(0, rgb(P.WATER_TOP, 1)); wg.addColorStop(1, rgb(P.WATER_BOT, 1));
  ctx.fillStyle = wg; ctx.fillRect(0, waterY, W, waterH);

  /* ---------- 4. the reflection ------------------------------------------
     One global vertical flip about the waterline: a pixel drawn at y ends up
     at 2*waterY - y. So a slice of the sky at rows [sy, sy+h) lands at exactly
     its mirrored depth when we draw it at the SAME y under the flip. Each
     slice is shifted horizontally by the ripple -> wobble for free.
     Composite 'lighter': black sky adds nothing, only the glow floats up. */
  const rip = 1 + P.RIPPLE_AUDIO * level;
  ctx.save();
  ctx.beginPath(); ctx.rect(0, waterY, W, waterH); ctx.clip();
  ctx.translate(0, waterY); ctx.scale(1, -1);   // y drawn at -k lands k px BELOW the line
  ctx.globalCompositeOperation = 'lighter';
  const sh = P.SLICE_H, K = P.REFLECT_SQUASH, shSrc = sh / K;
  for (let d = 0; d < waterH; d += sh) {
    const sy = waterY - (d + sh) / K;
    if (sy < 0) break;
    const dn = d / waterH;                                   // 0 at surface, 1 at bottom
    const amp = P.RIPPLE_AMP * (P.RIPPLE_MIN + P.RIPPLE_DEPTH_GAIN * dn) * rip;
    const dx = amp * ( Math.sin(d * P.RIPPLE_F1 - t * P.RIPPLE_S1)
                     + 0.6 * Math.sin(d * P.RIPPLE_F2 + t * P.RIPPLE_S2 + 1.7) );
    ctx.globalAlpha = P.REFLECT_ALPHA * Math.exp(-dn * P.REFLECT_FADE);
    // shift by sampling further into the margin: pure translation, never a seam
    const sx = (M - Math.max(-M, Math.min(M, dx))) * DPR;
    ctx.drawImage(sky, sx, sy * DPR, W * DPR, shSrc * DPR,  0, -(d + sh), W, sh);
  }
  ctx.restore();
  ctx.globalAlpha = 1;

  /* ---------- 5. blue shift with depth (one multiply rect) --------------- */
  ctx.save();
  ctx.beginPath(); ctx.rect(0, waterY, W, waterH); ctx.clip();
  ctx.globalCompositeOperation = 'multiply';
  const tg = ctx.createLinearGradient(0, waterY, 0, H);
  tg.addColorStop(0, rgb(P.TINT_TOP, 1)); tg.addColorStop(1, rgb(P.TINT_BOT, 1));
  ctx.fillStyle = tg; ctx.fillRect(0, waterY, W, waterH);
  ctx.restore();

  /* ---------- 6. surface: specular streaks + the waterline itself -------- */
  ctx.globalCompositeOperation = 'lighter';
  for (let k = 0; k < 7; k++) {
    const y  = waterY + 2 + k * 3.1;
    const ph = t * (0.7 + k * 0.23) + k * 1.9;
    const x  = (Math.sin(ph) * 0.5 + 0.5) * W;
    const w  = (34 + 26 * Math.sin(ph * 1.7)) * (1 + level);
    const lg = ctx.createLinearGradient(x - w, 0, x + w, 0);
    lg.addColorStop(0, 'rgba(150,200,255,0)');
    lg.addColorStop(0.5, `rgba(170,215,255,${(0.10 + 0.18 * level) * (1 - k / 8)})`);
    lg.addColorStop(1, 'rgba(150,200,255,0)');
    ctx.fillStyle = lg; ctx.fillRect(x - w, y, 2 * w, 1.4);
  }
  const ll = ctx.createLinearGradient(0, 0, W, 0);
  ll.addColorStop(0, 'rgba(120,180,255,0.10)');
  ll.addColorStop(Math.min(0.95, Math.max(0.05, center.x / W)),
                  `rgba(190,225,255,${0.55 + 0.35 * level})`);
  ll.addColorStop(1, 'rgba(120,180,255,0.10)');
  ctx.fillStyle = ll; ctx.fillRect(0, waterY - 0.5, W, 1.6);
  ctx.fillStyle = `rgba(120,170,255,${0.10 + 0.10 * level})`;
  ctx.fillRect(0, waterY - 3, W, 6);
  ctx.globalCompositeOperation = 'source-over';
}

window.waterScene = { P, draw };
})();
