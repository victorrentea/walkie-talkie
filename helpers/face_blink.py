#!/usr/bin/env python3
"""How closed his eyes are, per camera frame — MediaPipe's blendshapes.

**Why not Vision** (2026-11-20, Victor's human-eval): Apple Vision's eye outline
does not follow the eyelid. With his eyes fully closed it read 0.92 of their
usual opening, so `FaceRead`'s 🥱 could never fire on closed eyes. MediaPipe's
Face Landmarker gives `eyeBlinkLeft/Right` (0 open … 1 shut), trained for this.

Run by `FaceBlink.swift` in its own venv (`~/.walkie-talkie/face/venv`), kept
alive across takes. Protocol, binary on stdin, one JSON line per frame out:

    in:  u32 seq, u32 n (big-endian), n bytes of JPEG
    out: {"seq": 7, "face": true, "blink": 0.81, "smile": 0.05, "jaw": 0.02}

One `{"ready": true}` line first, once the model is loaded. Frames are decoded
in memory and dropped; nothing is written to disk.
"""
import argparse
import json
import os
import struct
import sys

os.environ.setdefault("GLOG_minloglevel", "2")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import cv2  # noqa: E402
import mediapipe as mp  # noqa: E402
import numpy as np  # noqa: E402
from mediapipe.tasks.python import BaseOptions, vision  # noqa: E402


def read_exact(stream, n):
    data = b""
    while len(data) < n:
        chunk = stream.read(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    args = ap.parse_args()
    landmarker = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=args.model),
        output_face_blendshapes=True, num_faces=1, running_mode=vision.RunningMode.IMAGE))
    out = sys.stdout
    out.write(json.dumps({"ready": True}) + "\n")
    out.flush()
    stdin = sys.stdin.buffer
    while True:
        head = read_exact(stdin, 8)
        if head is None:
            return
        seq, n = struct.unpack(">II", head)
        jpeg = read_exact(stdin, n)
        if jpeg is None:
            return
        reply = {"seq": seq, "face": False}
        bgr = cv2.imdecode(np.frombuffer(jpeg, np.uint8), cv2.IMREAD_COLOR)
        if bgr is not None:
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            if result.face_blendshapes:
                s = {c.category_name: c.score for c in result.face_blendshapes[0]}
                reply = {"seq": seq, "face": True,
                         "blink": round((s["eyeBlinkLeft"] + s["eyeBlinkRight"]) / 2, 3),
                         "smile": round((s["mouthSmileLeft"] + s["mouthSmileRight"]) / 2, 3),
                         "jaw": round(s["jawOpen"], 3)}
        out.write(json.dumps(reply) + "\n")
        out.flush()


if __name__ == "__main__":
    main()
