/* ===========================================================================
   comets — cometele din Lagoon, singure, oglindite într-o apă pe care n-o
   desenăm noi (2026-09-20, seara)
   ---------------------------------------------------------------------------
   Victor, despre Water Dream: „apa rămâne blocată în 20% de jos ale ecranului,
   dar meteorii urmăresc mouse-ul — orbitează în jurul lui". Un preset MilkDrop
   e un singur cadru randat, fără straturi de desprins, deci hibridul: presetul
   (fata morgana) dă apa și cerul, fixate pe ecran; ACEST strat, deasupra, dă
   cometele care orbitează cursorul și oglindirea lor în bazin. Stratul e
   transparent: nu pictează cer, nu pictează apă — numai lumină (`lighter`),
   inclusiv reflexia, ca să se compună peste preset (sau peste desktop).

   Ce e păstrat din water.js cu motivul lui: felierea reflexiei cu o singură
   răsturnare în jurul liniei de apă și REFLECT_SQUASH (fără turtire doar
   ~220 px de deasupra liniei ar ajunge vreodată în apă); SKY_MARGIN consumat
   prin EȘANTIONARE (altfel apare o cusătură verticală la marginea bazinului).
   Cometele au razele împărțite la 2.5, ca toate efectele proprii din seara aia.

   Integrare: fără audio propriu și fără rAF propriu — pagina cheamă draw() o
   dată pe cadru, cu level/bass/treble și cu centrul (= cursorul real, în embed).
   =========================================================================== */
(function () {
'use strict';
const P = {
  WATER_Y:        0.80,   // linia de apă: fracțiune din înălțimea ferestrei (bazinul = 20% de jos)
  SKY_MARGIN:     56,     // px CSS de scenă randați în plus stânga/dreapta, pentru deplasarea feliilor
  SLICE_H:        3,      // px CSS per felie oglindită
  REFLECT_ALPHA:  0.85,   // luminozitatea reflexiei chiar sub linie
  REFLECT_FADE:   1.35,   // exp(-adâncime·FADE)
  REFLECT_SQUASH: 0.42,   // 1 px de apă oglindește 1/SQUASH px de cer
  RIPPLE_AMP: 9.0, RIPPLE_DEPTH_GAIN: 1.0, RIPPLE_MIN: 0.12,
  RIPPLE_F1: 0.055, RIPPLE_S1: 1.25, RIPPLE_F2: 0.017, RIPPLE_S2: 0.62, RIPPLE_AUDIO: 2.4,
  COMETS: [               // r = raza orbitei ca fracțiune din min(vw,vh)/2 — cele din Lagoon ÷ 2.5
    { r: 0.120, spd:  0.62, hue: 190, w: 3.4, tail: 1.05, phase: 0.0 },
    { r: 0.184, spd: -0.41, hue: 265, w: 2.8, tail: 0.85, phase: 2.1 },
    { r: 0.248, spd:  0.29, hue: 160, w: 2.2, tail: 0.70, phase: 4.0 },
    { r: 0.320, spd: -0.19, hue: 325, w: 1.7, tail: 0.55, phase: 5.4 },
  ],
  TAIL_SEGMENTS: 22, TAIL_AUDIO: 0.9, SPEED_AUDIO: 1.8, BRIGHT_AUDIO: 0.85,
  HEAD_R: 5.5, BASS_RADIUS: 0.10, TREBLE_FLICKER: 0.35,
};

const sky = document.createElement('canvas'), sctx = sky.getContext('2d');   // offscreen: tot ce se oglindește
let W = 0, H = 0, DPR = 0, waterY = 0, waterH = 0, M = 0;

function resize(cv, ctx, w, h, dpr) {
  if (W === w && H === h && DPR === dpr) return;
  W = w; H = h; DPR = dpr;
  waterY = Math.round(H * P.WATER_Y); waterH = H - waterY; M = P.SKY_MARGIN;
  sky.width = Math.round((W + 2 * M) * DPR); sky.height = Math.round(waterY * DPR);
  sctx.setTransform(DPR, 0, 0, DPR, M * DPR, 0);
}

// cv/ctx: pânza paginii (#full, transparentă), deja dimensionată; cx/cy: centrul în px CSS
function draw(cv, ctx, t, level, bass, treble, cx, cy, dpr) {
  resize(cv, ctx, innerWidth, innerHeight, dpr);
  sctx.setTransform(DPR, 0, 0, DPR, M * DPR, 0);
  sctx.clearRect(-M, 0, W + 2 * M, waterY);           // cer TRANSPARENT: numai cometele
  sctx.globalCompositeOperation = 'lighter';
  const unit = Math.min(W, H) * 0.5, speed = 1 + P.SPEED_AUDIO * level;
  sctx.lineCap = 'round';
  for (let i = 0; i < P.COMETS.length; i++) {
    const c = P.COMETS[i];
    const R = unit * c.r * (1 + P.BASS_RADIUS * bass * Math.sin(t * 0.7 + i));
    const ang = c.phase + t * c.spd * speed;
    const span = c.tail * (1 + P.TAIL_AUDIO * level) * Math.sign(c.spd);
    const flick = 1 + P.TREBLE_FLICKER * treble * Math.sin(t * 9.1 + i * 2.3);
    const bri = (1 + P.BRIGHT_AUDIO * level) * flick;
    const col = a => `hsla(${c.hue + 25 * level},100%,${62 + 12 * level}%,${a})`;
    let px = cx + Math.cos(ang) * R, py = cy + Math.sin(ang) * R;
    for (let j = 1; j <= P.TAIL_SEGMENTS; j++) {
      const f = j / P.TAIL_SEGMENTS, a2 = ang - span * f;
      const nx = cx + Math.cos(a2) * R, ny = cy + Math.sin(a2) * R, fade = (1 - f) * (1 - f);
      sctx.strokeStyle = col(Math.min(1, 0.55 * fade * bri));
      sctx.lineWidth = c.w * (0.25 + 0.75 * (1 - f));
      sctx.beginPath(); sctx.moveTo(px, py); sctx.lineTo(nx, ny); sctx.stroke();
      px = nx; py = ny;
    }
    const hx = cx + Math.cos(ang) * R, hy = cy + Math.sin(ang) * R, hr = P.HEAD_R * (1 + 0.6 * level);
    const g = sctx.createRadialGradient(hx, hy, 0, hx, hy, hr * 3);
    g.addColorStop(0, `hsla(${c.hue},100%,92%,${Math.min(1, 0.95 * bri)})`);
    g.addColorStop(0.3, col(Math.min(1, 0.55 * bri)));
    g.addColorStop(1, `hsla(${c.hue},100%,60%,0)`);
    sctx.fillStyle = g; sctx.beginPath(); sctx.arc(hx, hy, hr * 3, 0, 6.2832); sctx.fill();
  }
  // Cometele de deasupra liniei, pe ecran; cele intrate în bazin se văd doar ca reflexie
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 1;
  ctx.drawImage(sky, M * DPR, 0, W * DPR, waterY * DPR, 0, 0, W, waterY);
  // Reflexia: o răsturnare în jurul liniei, felii deplasate de undă, numai lumină
  const rip = 1 + P.RIPPLE_AUDIO * level;
  ctx.save();
  ctx.beginPath(); ctx.rect(0, waterY, W, waterH); ctx.clip();
  ctx.translate(0, waterY); ctx.scale(1, -1);
  const sh = P.SLICE_H, K = P.REFLECT_SQUASH, shSrc = sh / K;
  for (let d = 0; d < waterH; d += sh) {
    const sy = waterY - (d + sh) / K;
    if (sy < 0) break;
    const dn = d / waterH;
    const amp = P.RIPPLE_AMP * (P.RIPPLE_MIN + P.RIPPLE_DEPTH_GAIN * dn) * rip;
    const dx = amp * (Math.sin(d * P.RIPPLE_F1 - t * P.RIPPLE_S1) + 0.6 * Math.sin(d * P.RIPPLE_F2 + t * P.RIPPLE_S2 + 1.7));
    ctx.globalAlpha = P.REFLECT_ALPHA * Math.exp(-dn * P.REFLECT_FADE);
    const sx = (M - Math.max(-M, Math.min(M, dx))) * DPR;
    ctx.drawImage(sky, sx, sy * DPR, W * DPR, shSrc * DPR, 0, -(d + sh), W, sh);
  }
  ctx.restore();
  ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over';
}
window.cometsScene = { P, draw };
})();
