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
  teaching   (2026-11-13) voice-corpus/mic/<day>/*.wav — him teaching a room, the
             register that woke it 38 times in one workshop day while the dictation
             negatives said 0/h. Every 0.4 s window of the training days is encoded
             once (cached in santa/cache/) and mined: the ones the model likes go in.
  triggers   santa/triggers/*.wav — the audio around every live wake, kept by
             `helpers/wake_word.py`. The local Whisper says what was in it: "santa"
             → a real positive, anything else → a negative that already fooled it.

Held out: two voices and his own `VictorEval-*` takes (positives), every corpus
day ≥ --eval-from and the --teach-eval days (negatives),
scored STREAMING — a 2 s window every 0.4 s over continuous audio, a 2 s
refractory — because clip-by-clip scoring flatters a detector badly.

    ~/.walkie-talkie/wake/venv/bin/python3 -I evals/wake-word/train_whisper_wake.py
"""
import argparse
import glob
import os
import json
import random
import subprocess
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


def teach_files(days):
    return [w for d in days for w in sorted((CORPUS / "mic" / d).glob("*.wav"))]


def teach_days():
    root = CORPUS / "mic"
    return sorted(d for d in os.listdir(root) if d[:4].isdigit() and (root / d).is_dir()) if root.is_dir() else []


def featurize(enc, name, files, model):
    """Every 0.4 s window of `files`, encoded once: (features, clip index, seconds)."""
    cache = DATA / "cache" / f"{name}-{model}-{len(files)}.npz"
    if cache.exists():
        z = np.load(cache)
        return z["X"], z["clip"], float(z["secs"])
    X, clip, secs = [], [], 0.0
    for i, f in enumerate(files):
        au = load(f)
        secs += len(au) / RATE
        for w in windows(au, 0.4):
            X.append(enc(w)); clip.append(i)
        if i % 500 == 0:
            print(f"  {name}: {i}/{len(files)} clips", flush=True)
    X, clip = np.array(X, np.float32), np.array(clip, np.int32)
    cache.parent.mkdir(parents=True, exist_ok=True)
    np.savez(cache, X=X, clip=clip, secs=secs)
    return X, clip, secs


LABELLER = """
import sys, mlx_whisper
for f in sys.argv[2:]:
    t = mlx_whisper.transcribe(f, path_or_hf_repo=sys.argv[1], language="en")["text"].strip()
    open(f[:-4] + ".txt", "w").write(t)
    print(f, "|", t, flush=True)
"""


def triggers(label_python, label_model):
    """The live wakes' audio → (real positive windows, negative windows).
    A `.txt` beside each says what the local Whisper heard in it."""
    wavs = sorted((DATA / "triggers").glob("*.wav"))
    todo = [str(w) for w in wavs if not w.with_suffix(".txt").exists()]
    if todo and os.path.exists(label_python):
        subprocess.run([label_python, "-c", LABELLER, label_model] + todo, check=False)
    pos, neg = [], []
    for w in wavs:
        txt, meta = w.with_suffix(".txt"), w.with_suffix(".json")
        if not txt.exists():
            continue
        a = load(w)
        end = json.loads(meta.read_text()).get("window_end", len(a)) if meta.exists() else len(a)
        win = a[max(0, end - int(WIN * RATE)):end]
        (pos if "santa" in txt.read_text().lower() else neg).append(win)
    return pos, neg


def false_wakes(scores, clip, th):
    """Streaming count: a wake, then 5 strides (2 s) of refractory, per clip."""
    fw, last, cur = 0, -99, -1
    for i, (v, c) in enumerate(zip(scores, clip)):
        if c != cur:
            cur, last = c, -99
        if v >= th and i - last >= 5:
            fw += 1; last = i
    return fw


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", default="tiny")
    p.add_argument("--eval-from", default="2026-11-01", help="corpus days kept out of training")
    p.add_argument("--holdout", default="Ioana,Daniel,VictorEval")
    p.add_argument("--teach-eval", default="2026-09-14,2026-09-16,2026-09-17",
                   help="voice-corpus/mic days kept out of training (the rest train)")
    p.add_argument("--score-only", default="", help="an existing .npz: score it on the held-out sets, train nothing")
    p.add_argument("--label-python", default=str(HOME / "venv" / "bin" / "python3"))
    p.add_argument("--label-model", default="mlx-community/whisper-large-v3-turbo")
    p.add_argument("--eval-minutes", type=float, default=45)
    p.add_argument("--out", default=str(HOME / "wake" / "hey_santa_whisper.npz"))
    a = p.parse_args()
    rng = np.random.default_rng(0)
    random.seed(0)
    enc = Encoder(a.model)
    hold = set(a.holdout.split(","))
    eval_days = [d for d in a.teach_eval.split(",") if d]
    Xte, cte, ste = featurize(enc, "teach-eval", teach_files(eval_days), a.model)
    print(f"teaching, held out: {ste / 60:.0f} min, {len(Xte)} windows")

    if a.score_only:
        z = np.load(a.score_only)
        zs = ((Xte - z["mean"]) / z["scale"]) @ z["coef"] + float(z["intercept"])
        sc_ = 1 / (1 + np.exp(-zs))
        for th in (0.5, 0.6, 0.7, 0.8, 0.9, 0.95):
            fw = false_wakes(sc_, cte, th)
            print(f"  threshold {th:.2f}: false wakes {fw} ({fw / (ste / 3600):.1f}/h)")
        return

    Xtr, _, stt = featurize(enc, "teach-train", teach_files([d for d in teach_days() if d not in eval_days]), a.model)
    print(f"teaching, training: {stt / 60:.0f} min, {len(Xtr)} windows")

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
    real_pos, trig_neg = triggers(a.label_python, a.label_model)
    for w in real_pos:
        X.append(enc(w)); y.append(1); tag.append("live")
    for w in trig_neg:
        X.append(enc(w)); y.append(0); tag.append("trigger")
    print(f"live wakes: {len(real_pos)} said it, {len(trig_neg)} did not")
    first = rng.choice(len(Xtr), min(4000, len(Xtr)), replace=False) if len(Xtr) else []
    for i in first:
        X.append(Xtr[i]); y.append(0); tag.append("teach")
    print(f"negatives: {y.count(0)}")

    X, y = np.array(X), np.array(y)
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    def fit(X, y):
        sc = StandardScaler().fit(X)
        return sc, LogisticRegression(max_iter=5000, C=0.1, class_weight="balanced").fit(sc.transform(X), y)

    # Hard negatives: the speech windows it likes most, back in.
    pool = np.array([enc(w) for w in speech[1800:] + room[800:2400]], np.float32)
    if len(Xtr):
        pool = np.vstack([pool, np.delete(Xtr, first, axis=0)])
    for rnd in range(1, 9):
        sc, clf = fit(X, y)
        ps = clf.predict_proba(sc.transform(pool))[:, 1]
        top = np.argsort(-ps)[:600]
        top = top[ps[top] > 0.05]
        print(f"round {rnd}: {len(top)} hard negatives (worst {ps.max():.3f}, {int((ps >= 0.5).sum())} of {len(pool)} ≥ 0.5)", flush=True)
        if not len(top):
            break
        X = np.vstack([X, pool[top]]); y = np.r_[y, np.zeros(len(top))]
        pool = np.delete(pool, top, axis=0)
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
    pte = clf.predict_proba(sc.transform(Xte))[:, 1] if len(Xte) else np.zeros(0)
    print(f"teaching, held out: {ste / 60:.0f} min")
    for th in (0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98):
        fw = 0
        for s in peaks:
            last = -99
            for i, v in enumerate(s):
                if v >= th and i - last >= 5:
                    fw += 1; last = i
        ft = false_wakes(pte, cte, th)
        print(f"  threshold {th:.2f}: recall {np.mean(rec >= th):.0%}, false wakes: dictation {fw} ({fw / (secs / 3600):.1f}/h),"
              f" teaching {ft} ({ft / max(ste / 3600, 1e-9):.1f}/h)")

    np.savez(a.out, mean=sc.mean_.astype(np.float32), scale=sc.scale_.astype(np.float32),
             coef=clf.coef_[0].astype(np.float32), intercept=np.float32(clf.intercept_[0]),
             whisper_model=a.model, window_seconds=np.float32(WIN), keep_frames=np.int32(KEEP))
    print(f"\nwrote {a.out}")


if __name__ == "__main__":
    main()
