#!/usr/bin/env python3
"""Train a wake word on Whisper's encoder (2026-11-12, "hey santa").

The idea (not the code) is greg1232/hey-claude's, after it measured
openWakeWord's frozen CNN as the ceiling on real voices: a 2 s window through
Whisper tiny's encoder, mean+max over time, a logistic regression on top.

His data, not a household's:
  positives  ~/.walkie-talkie/wake/santa/pos/*.wav  (synthetic: 14 `say` voices ×
             3 rates × 3 pitches; plus real/*.wav once he records some) placed at
             six offsets into 2 s of HIS room tone
  room       2 s windows of his own quiet microphone, cut from the voice corpus
  speech     2 s windows of his own dictations (the corpus) — the negative that
             matters: without it the model learns "somebody is talking"
  adversarial  santa/adv/*.wav ("Santa Claude", "hey Sandra", "Fanta", …)

Held out: two voices (positives) and every corpus day ≥ --eval-from (negatives),
scored STREAMING — a 2 s window every 0.4 s over continuous audio, a 2 s
refractory — because clip-by-clip scoring flatters a detector badly.

    ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/train_whisper_wake.py
"""
import argparse
import glob
import os
import random
import wave
from pathlib import Path

import numpy as np

RATE = 16000
WIN = 2.0
KEEP = int(WIN * 50)
HOME = Path.home() / ".walkie-talkie"
DATA = HOME / "wake" / "santa"
CORPUS = HOME / "voice-corpus"


def load(path):
    with wave.open(str(path)) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
        if w.getnchannels() > 1:
            a = a[::w.getnchannels()]
        return a


def trim(a):
    f = a[: len(a) // 160 * 160].reshape(-1, 160).astype(np.float64)
    if not f.size:
        return a
    e = np.sqrt((f ** 2).mean(1))
    loud = np.where(e > max(e.max() * 0.1, 60))[0]
    return a[loud[0] * 160:(loud[-1] + 1) * 160] if len(loud) else a


class Encoder:
    def __init__(self, size):
        from faster_whisper import WhisperModel
        self.m = WhisperModel(size, device="cpu", compute_type="int8", cpu_threads=6)
        self.fx = self.m.feature_extractor

    def __call__(self, a):
        want = int(WIN * RATE)
        a = np.pad(a, (max(0, want - len(a)), 0))[-want:]
        mel = self.fx(a.astype(np.float32) / 32768.0)[..., : self.fx.nb_max_frames]
        out = np.array(self.m.encode(mel))[0][:KEEP]
        return np.concatenate([out.mean(0), out.max(0)]).astype(np.float32)


def place(phrase, bg, offset, rng):
    want = int(WIN * RATE)
    w = bg[:want].astype(np.float32).copy()
    if len(w) < want:
        w = np.pad(w, (0, want - len(w)))
    phrase = phrase[:want]
    start = int(offset * max(1, want - len(phrase)))
    end = min(want, start + len(phrase))
    w[start:end] += phrase[: end - start] * rng.uniform(0.5, 1.3)
    return np.clip(w, -32768, 32767).astype(np.int16)


def corpus_files(days_from=None, days_to=None):
    out = []
    for day in sorted(os.listdir(CORPUS)):
        if not day[:4].isdigit() or not (CORPUS / day).is_dir():
            continue
        if days_from and day < days_from:
            continue
        if days_to and day >= days_to:
            continue
        for wav in sorted((CORPUS / day).glob("*.wav")):
            txt = wav.with_suffix(".txt")
            if txt.exists() and "santa" in txt.read_text(errors="ignore").lower():
                continue  # never a negative that might say it
            out.append(wav)
    return out


def windows(a, step=0.4):
    n, s = int(WIN * RATE), int(step * RATE)
    return [a[i:i + n] for i in range(0, max(1, len(a) - n), s)]


def rms(a):
    return float(np.sqrt(np.mean(a.astype(np.float64) ** 2))) if len(a) else 0.0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default="tiny")
    p.add_argument("--eval-from", default="2026-11-01", help="corpus days kept out of training")
    p.add_argument("--holdout", default="Ioana,Daniel")
    p.add_argument("--eval-minutes", type=float, default=45)
    p.add_argument("--out", default=str(HOME / "wake" / "hey_santa_whisper.npz"))
    a = p.parse_args()
    rng = np.random.default_rng(0)
    random.seed(0)
    enc = Encoder(a.model)
    hold = set(a.holdout.split(","))

    train_files = corpus_files(days_to=a.eval_from)
    random.shuffle(train_files)
    print(f"corpus: {len(train_files)} training clips before {a.eval_from}")

    # His room: the quiet 2 s windows of his own recordings.
    room = []
    for f in train_files[:1500]:
        for w in windows(load(f), 1.0):
            if len(w) == int(WIN * RATE) and rms(w) < 120:
                room.append(w)
        if len(room) >= 3000:
            break
    random.shuffle(room)
    print(f"room windows: {len(room)}")

    def bg():
        return room[rng.integers(len(room))]

    X, y, tag = [], [], []
    pos = sorted(glob.glob(str(DATA / "pos" / "*.wav"))) + sorted(glob.glob(str(DATA / "real" / "*.wav")))
    test_pos = []
    for f in pos:
        voice = Path(f).name.split("-")[0]
        phrase = trim(load(f))
        if voice in hold:
            test_pos.append(phrase)
            continue
        for i in range(6):
            X.append(enc(place(phrase, bg(), i / 5, rng))); y.append(1); tag.append("pos")
    print(f"positives: {y.count(1)} windows ({len(pos) - len(test_pos)} clips), {len(test_pos)} held out")

    for w in room[:800]:
        X.append(enc(w)); y.append(0); tag.append("room")
    speech = []
    for f in train_files[1500:]:
        ws = [w for w in windows(load(f), 1.3) if len(w) == int(WIN * RATE) and rms(w) >= 120]
        speech += random.sample(ws, min(2, len(ws)))
        if len(speech) >= 2500:
            break
    for w in speech[:1800]:
        X.append(enc(w)); y.append(0); tag.append("speech")
    for f in sorted(glob.glob(str(DATA / "adv" / "*.wav"))):
        ph = trim(load(f))
        for i in (0.2, 0.8):
            X.append(enc(place(ph, bg(), i, rng))); y.append(0); tag.append("adv")
    print(f"negatives: {y.count(0)}")

    X, y = np.array(X), np.array(y)
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    def fit(X, y):
        sc = StandardScaler().fit(X)
        return sc, LogisticRegression(max_iter=5000, C=0.1, class_weight="balanced").fit(sc.transform(X), y)

    # Hard negatives: the speech windows it likes most, back in.
    extra = speech[1800:] + room[800:2400]
    for rnd in (1, 2):
        sc, clf = fit(X, y)
        cand = [(float(clf.predict_proba(sc.transform(v[None]))[0, 1]), v) for v in (enc(w) for w in extra)]
        cand.sort(key=lambda c: -c[0])
        hard = [v for s, v in cand[:300] if s > 0.05]
        print(f"round {rnd}: {len(hard)} hard negatives (worst {cand[0][0]:.3f})")
        if not hard:
            break
        X = np.vstack([X, hard]); y = np.r_[y, np.zeros(len(hard))]
    sc, clf = fit(X, y)

    def score(v):
        return float(clf.predict_proba(sc.transform(v[None]))[0, 1])

    # Recall on voices it never met, in his room.
    rec = np.array([max(score(enc(place(ph, bg(), off, rng))) for off in (0.3, 0.7)) for ph in test_pos])
    # Streaming false wakes over held-out days of his speech.
    ev = corpus_files(days_from=a.eval_from)
    random.shuffle(ev)
    secs, peaks = 0.0, []
    for f in ev:
        au = load(f)
        secs += len(au) / RATE
        s = [score(enc(w)) for w in windows(au, 0.4)]
        peaks.append(s)
        if secs >= a.eval_minutes * 60:
            break
    print(f"\nheld-out voices {sorted(hold)}: {len(rec)} clips; held-out speech: {secs / 60:.0f} min, {len(peaks)} clips")
    for th in (0.5, 0.7, 0.8, 0.9, 0.95, 0.98):
        fw = 0
        for s in peaks:
            last = -99
            for i, v in enumerate(s):
                if v >= th and i - last >= 5:
                    fw += 1; last = i
        print(f"  threshold {th:.2f}: recall {np.mean(rec >= th):.0%}, false wakes {fw} ({fw / (secs / 3600):.1f}/h)")

    np.savez(a.out, mean=sc.mean_.astype(np.float32), scale=sc.scale_.astype(np.float32),
             coef=clf.coef_[0].astype(np.float32), intercept=np.float32(clf.intercept_[0]),
             whisper_model=a.model, window_seconds=np.float32(WIN), keep_frames=np.int32(KEEP))
    print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
