#!/usr/bin/env python3
"""Three typical dictations, rendered by the running relay — the whole envelope.

Victor asked to see the new template *"real randat"*, for a few typical cases,
preferably from synthesised speech laid over real gestures.

What is real here, and what is not:

- **The words and their timings are real.** macOS's Romanian voice speaks each
  sentence into a WAV and that WAV goes to **ElevenLabs Scribe** — the engine he
  is moving to — which answers with the transcript and `words[]`, every word
  with a `start` in seconds. Nothing about the text or the clock is invented.
- **The gestures are real**, and so is everything they produce: `POST /test/area`
  drags a box and writes the three files, `/test/selection` files a highlight,
  `/pick` files a Chrome element. The frames on disk are this Mac's screen.
- **The envelope is rendered by the relay**, not by this script: the words plus
  the timings go in through `POST /test/dictation {"text": …, "words": […]}`,
  so `ShotMarker.place` puts each token where its press fell and
  `artifactsClause` writes the footer. What comes out of `outbox.jsonl` is what
  an agent would have received.
- **The microphone is not in the loop.** It could not be: CoreAudio on this Mac
  is wedged tonight — every `AVAudioEngine` input bind hangs in `mach_msg` and
  never returns — so the clip is transcribed by handing Scribe the file instead
  of playing it at the microphone. That is the fallback Victor named himself
  (*"măcar să-i dai wav-ul"*).

    ./samples.py            # all three
    ./samples.py area       # one
"""
import json, pathlib, subprocess, sys, time, urllib.request

BASE = "http://127.0.0.1:8917"
NOWHERE = "ttys999"
OUTBOX = pathlib.Path.home() / ".walkie-talkie" / "outbox.jsonl"
KEY = None
for line in (pathlib.Path.home() / ".walkie-talkie" / "elevenlabs.env").read_text().splitlines():
    if line.startswith("ELEVENLABS_API_KEY="):
        KEY = line.split("=", 1)[1].strip()

# Each scenario: what the voice says, and what he does at which second of it.
# The pauses (`[[slnc ms]]`) are where the gestures land — that is where he
# presses, and a token reads best in a gap.
SCENARIOS = {
    "area": {
        "why": "he shows the screen and points at a region — the commonest one",
        "say": "Uite ce am pe ecran acum. [[slnc 900]] În zona asta [[slnc 1100]] "
               "vreau să apară un buton nou, la fel ca celelalte.",
        "do": [(3.1, "area", {"x": 380, "y": 520, "w": 760, "h": 240})],
    },
    "selection": {
        "why": "a highlight he makes while talking, in another app",
        "say": "Linia asta e problema. [[slnc 1100]] Hai să o rescriem mai simplu, "
               "fără stream.",
        "do": [(2.0, "selection", {"text": "public Order placeOrder(Cart cart) {"})],
    },
    "element": {
        "why": "an element picked in Chrome, mid-sentence",
        "say": "Butonul ăsta [[slnc 1100]] trebuie să fie verde, nu albastru.",
        "do": [(1.4, "element", {"path": "div.toolbar > button.primary", "tag": "button",
                                 "text": "Salvează", "title": "Orders",
                                 "url": "https://petclinic.victorrentea.ro/orders"})],
    },
}


def post(path, obj=None):
    req = urllib.request.Request(BASE + path, data=json.dumps(obj or {}).encode(),
                                 method="POST")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return json.loads(r.read() or b"{}")
    except Exception as e:
        return {"error": str(e)}


def speak(text, wav):
    """macOS's Romanian voice — ElevenLabs' own TTS is not reachable with this
    key (`missing_permissions: text_to_speech`), and Scribe does not mind."""
    aiff = wav.with_suffix(".aiff")
    subprocess.run(["say", "-v", "Ioana", "-o", str(aiff), text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                    str(aiff), str(wav)], check=True, capture_output=True)
    aiff.unlink()
    return wav


def scribe(wav):
    """The engine he is moving to, asked for the timings that make this work."""
    boundary = "----wt"
    body = bytearray()
    for name, value in (("model_id", "scribe_v2"), ("timestamps_granularity", "word")):
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
    body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
             f"filename=\"{wav.name}\"\r\nContent-Type: audio/wav\r\n\r\n").encode()
    body += wav.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request("https://api.elevenlabs.io/v1/speech-to-text", data=bytes(body),
                                 headers={"xi-api-key": KEY,
                                          "Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=90) as r:
        out = json.loads(r.read())
    words = [{"text": w["text"], "start": w.get("start", 0), "end": w.get("end", 0),
              "type": w.get("type", "word")} for w in out.get("words", [])]
    return out.get("text", ""), words


def run(name):
    scene = SCENARIOS[name]
    wav = speak(scene["say"], pathlib.Path(f"/tmp/wt-sample-{name}.wav"))
    text, words = scribe(wav)
    spoken = sum(1 for w in words if w["type"] == "word")
    print(f"  Scribe: {spoken} words, {words[-1]['end']:.1f}s — “{text}”")

    before = len(OUTBOX.read_text().splitlines())
    post("/bind", {"tty": NOWHERE})
    post("/test/dictation/start", {"clock": True})
    time.sleep(0.6)
    opened = time.monotonic()
    for at, action, arg in scene["do"]:
        # The gesture is made at the second of the clip it belongs to: the app
        # measures the press against the moment the dictation opened, so waiting
        # here is what puts the cue at `at` seconds into the words.
        while time.monotonic() - opened < at:
            time.sleep(0.05)
        post({"area": "/test/area", "selection": "/test/selection",
              "element": "/pick"}[action], arg)
    time.sleep(0.6)
    post("/test/dictation", {"text": text, "words": words})
    for _ in range(20):
        time.sleep(1)
        lines = OUTBOX.read_text().splitlines()
        if len(lines) > before:
            return json.loads(lines[-1])
        post("/bind", {"tty": NOWHERE})
    return {"error": "the dictation never reached the outbox"}


if __name__ == "__main__":
    for name in (sys.argv[1:] or list(SCENARIOS)):
        print(f"\n═══════════ {name} — {SCENARIOS[name]['why']} ═══════════")
        entry = run(name)
        print("\n" + (entry.get("line") or entry.get("error") or str(entry)))
    post("/unbind")
