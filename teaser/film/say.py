#!/usr/bin/python3
"""Guest: play a WAV (48 kHz stereo) into BlackHole 2ch — the lab's microphone. No speaker anywhere.
    say.py <wav> [delay seconds]"""
import sys, time
import sounddevice as sd
from scipy.io import wavfile
rate, data = wavfile.read(sys.argv[1])
if len(sys.argv) > 2: time.sleep(float(sys.argv[2]))
idx = [i for i, d in enumerate(sd.query_devices()) if "BlackHole 2ch" in d["name"] and d["max_output_channels"] >= 2][0]
sd.play(data, rate, device=idx, blocking=True)
