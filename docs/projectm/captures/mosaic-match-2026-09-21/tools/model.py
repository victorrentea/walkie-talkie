#!/usr/bin/env python3
"""Both engines' audio -> bass/mid/treb -> the Mosaic preset's beat logic (index, q27, p2),
replicated in numpy on the same 16 kHz clip, frame by frame at 30 fps.
  web:        halo.html audio() (newest 1024*16000/RATE samples, linear-interp to 1024, byte-quantised)
              -> butterchurn processAudio (no window, 1024-pt FFT, eq) -> Hz bands at RATE -> AudioLevels
  native-raw: ProjectMHalo.feed (newest 549 samples, handed over as 44.1 kHz) -> projectM PCM ring 576,
              2-tap damp, oldest 480, Hann, 1024-pt FFT, eq -> sixths bands -> Loudness
  native-rs:  same, but linearly upsampled 16k -> 44.1k first (WT_PM_RESAMPLE=1)
  native-bc:  hypothetical: projectM fed the resampled audio but analysed the butterchurn way
usage: model.py <wav> [seconds] [engineRate]"""
import sys, wave, numpy as np
A = sys.argv if __name__ == "__main__" else []
WAV = A[1] if len(A) > 1 else "/Users/victorrentea/workspace/walkie-talkie/assets/halo-voice.wav"; SEC = float(A[2]) if len(A) > 2 else 10.0; RATE = int(A[3]) if len(A) > 3 else 48000
FPS = 30; HOST = 16000
w = wave.open(WAV); clip = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
assert w.getframerate() == HOST
n = int(SEC * HOST); audio = np.array([clip[i % clip.size] for i in range(n)])   # ClipVoice: clip[int(produced*16000) % count]
EQ = -0.02 * np.log((512 - np.arange(512)) / 512.0)
def adjust(rate, dt): return rate ** (30.0 * dt)          # both engines: rate^(30/fps)

class Levels:  # butterchurn AudioLevels == projectM Loudness (same constants)
    def __init__(s): s.avg = np.ones(3); s.long = np.ones(3); s.val = np.ones(3); s.att = np.ones(3)
    def update(s, imm, dt, frame):
        for h in range(3):
            r = adjust(0.2 if imm[h] > s.avg[h] else 0.5, dt); s.avg[h] = s.avg[h] * r + imm[h] * (1 - r)
            r = adjust(0.9 if frame < 50 else 0.992, dt); s.long[h] = s.long[h] * r + imm[h] * (1 - r)
            if s.long[h] < 0.001: s.val[h] = 1; s.att[h] = 1
            else: s.val[h] = imm[h] / s.long[h]; s.att[h] = s.avg[h] / s.long[h]

class Web:
    def __init__(s, rate=RATE):
        s.lv = Levels(); s.frame = 0
        bw = rate / 1024
        st = [max(0, min(511, round(f / bw) - 1)) for f in (20, 320, 2800)]
        sp = [max(0, min(511, round(f / bw) - 1)) for f in (320, 2800, 11025)]
        s.bands = list(zip(st, sp)); s.need = max(2, round(1024 * HOST / rate))
    def step(s, ring, dt):
        v = ring[-s.need:]; x = np.arange(1024) * (s.need - 1) / 1023; j = np.floor(x).astype(int); f = x - j
        vv = v[j] * (1 - f) + v[np.minimum(j + 1, s.need - 1)] * f
        b = np.clip(np.round(128 + vv * 127), 0, 255) - 128
        spec = EQ * np.abs(np.fft.fft(b, 1024)[:512])
        imm = np.array([spec[a:z].sum() for a, z in s.bands])
        s.lv.update(imm, dt, s.frame); s.frame += 1
        return s.lv.val.copy(), s.lv.att.copy()

HANN = 0.5 + 0.5 * np.sin(np.arange(480) / 480 * 2 * np.pi - np.pi / 2)
class Native:
    def __init__(s, resample, bc=False):
        s.lv = Levels(); s.frame = 0; s.ring = np.zeros(576); s.start = 0; s.resample = resample; s.bc = bc
        if bc: s.web = Web(44100); s.big = np.zeros(1024)
    def push(s, x):
        for v in x: s.ring[s.start] = 128 * v; s.start = (s.start + 1) % 576
        if s.bc: s.big = np.concatenate([s.big, x])[-1024:]
    def step(s, ring, dt):
        tail = ring[-549:]
        if s.resample:
            step = HOST / 44100.0; out = int(549 / step); pos = np.arange(out) * step; k = pos.astype(int); f = pos - k
            tail = tail[k] * (1 - f) + tail[np.minimum(k + 1, 548)] * f
        s.push(tail)
        if s.bc:
            b = np.clip(np.round(128 + s.big * 127), 0, 255) - 128
            spec = EQ * np.abs(np.fft.fft(b, 1024)[:512]); imm = np.array([spec[a:z].sum() for a, z in s.web.bands])
        else:
            wf = np.array([s.ring[(s.start + i) % 576] for i in range(576)])
            d = wf.copy(); d[1:] = 0.5 * (wf[1:] + wf[:-1]); d[0] = wf[0]
            spec = EQ * np.abs(np.fft.fft(d[:480] * HANN, 1024)[:512])
            imm = np.array([spec[a:z].sum() for a, z in ((0, 85), (85, 170), (170, 255))])
        s.lv.update(imm, dt, s.frame); s.frame += 1
        return s.lv.val.copy(), s.lv.att.copy()

class Preset:  # martin - reflections on black tiles, per_frame
    def __init__(s): s.avg = 0; s.peak = 0; s.t0 = 0; s.index = 0; s.p1 = 0; s.p2 = 0; s.time = 0
    def step(s, bass, mid, treb, fps, dt):
        s.time += dt
        dec_med = 0.9 ** (30 / fps); dec_slow = 0.99 ** (30 / fps)
        beat = max(bass, mid, treb)
        s.avg = s.avg * dec_slow + beat * (1 - dec_slow)
        is_beat = int(beat > .5 + s.avg + s.peak and s.time > s.t0 + .2)
        s.t0 = is_beat * s.time + (1 - is_beat) * s.t0
        s.peak = is_beat * beat + (1 - is_beat) * s.peak * dec_med
        s.index = (s.index + is_beat) % 8
        k1 = is_beat * (s.index == 0); s.p1 = k1 * (s.p1 + 1) + (1 - k1) * s.p1
        s.p2 = dec_med * s.p2 + (1 - dec_med) * s.p1
        return is_beat, s.index, s.p2 * np.pi / 2, beat

def run(engine):
    pr = Preset(); rows = []
    for k in range(int(SEC * FPS)):
        t = (k + 1) / FPS; upto = int(t * HOST); ring = audio[max(0, upto - 2048):upto]
        if ring.size < 2048: ring = np.concatenate([np.zeros(2048 - ring.size), ring])
        (bass, mid, treb), att = engine.step(ring, 1 / FPS)
        is_beat, index, rott, beat = pr.step(bass, mid, treb, FPS, 1 / FPS)
        rows.append((t, bass, mid, treb, beat, is_beat, index, rott))
    return np.array(rows)

if __name__ == "__main__":
    R = {"web": run(Web()), "native-raw": run(Native(False)), "native-rs": run(Native(True)), "native-bc": run(Native(True, bc=True))}
    ref = R["web"]
    print(f"clip {clip.size / HOST:.2f} s looped to {SEC:.0f} s, {int(SEC * FPS)} frames, web engine rate {RATE}")
    for name, r in R.items():
        beats = r[r[:, 5] > 0, 0]
        same = (r[:, 6] == ref[:, 6]).mean()
        # beat-time agreement: a beat within ±2 frames of a reference beat
        rb = ref[ref[:, 5] > 0, 0]; hit = np.mean([np.min(np.abs(rb - b)) <= 2.5 / FPS for b in beats]) if beats.size and rb.size else 0
        print(f"{name:11s} beats {beats.size:3d} | index == web's on {same * 100:5.1f}% of frames | beats within 2 frames of a web beat {hit * 100:5.1f}% | "
              f"bass/mid/treb mean {r[:, 1].mean():.2f}/{r[:, 2].mean():.2f}/{r[:, 3].mean():.2f} max {r[:, 1].max():.1f}/{r[:, 2].max():.1f}/{r[:, 3].max():.1f}")
        print("   beats at:", " ".join(f"{b:.2f}" for b in beats))

