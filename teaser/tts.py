#!/usr/bin/env python3
"""Voice lines for the teaser: one audio file per line of script.json, into audio/.

Two voices: the narrator (`who: "n"`) and the user dictating to Walkie (`who: "u"`).
Each clip is cached by a hash of (provider, model, voice, settings, text), so editing the
script re-synthesises only the lines that changed.

Providers, tried in order: ElevenLabs (key in ~/.walkie-talkie/elevenlabs.env), then
Fish Audio (~/.claude/fish-audio.env). A 401/403 from one (a key scoped to something
else) falls through to the next. Keys are read from those files only, never printed.

    python3 teaser/tts.py              # synthesise what is missing, print the manifest
    python3 teaser/tts.py --samples    # audio/samples/narrator-<name>.mp3, the s01 line
    python3 teaser/tts.py --voices     # list the ElevenLabs voices the key can use
"""
from __future__ import annotations
import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUDIO = HERE / "audio"
SCRIPT = HERE / "script.json"

ELEVEN_KEY_FILE = Path.home() / ".walkie-talkie" / "elevenlabs.env"
FISH_KEY_FILE = Path.home() / ".claude" / "fish-audio.env"

ELEVEN_MODEL = "eleven_multilingual_v2"
FISH_MODEL = "s2.1-pro-free"

# name -> per-provider voice. `settings` goes to ElevenLabs as voice_settings.
_EL_NARRATOR = {"stability": 0.45, "similarity_boost": 0.8, "style": 0.35,
                "use_speaker_boost": True}
VOICES = {
    # Narrator candidates (--samples renders all three). Fish ids are public catalogue
    # voices on fish.audio, none of them a clone of a named person.
    "adrian": {"fish": "bf322df2096a46f18c579d0baa36f41d", "fish_speed": 1.08,
               "eleven": "nPczCjzI2devNBz1zQrb", "settings": _EL_NARRATOR},
    "ethan": {"fish": "536d3a5e000945adb7038665781a4aca",
              "eleven": "JBFqnCBsd6RMkjVDRZzb", "settings": _EL_NARRATOR},
    "slax": {"fish": "c5f56a6cc2ec4fa8920cb4c5889a3fb7",
             "eleven": "pqHfZKP75CvOlQylNhV4", "settings": _EL_NARRATOR},
    # The user dictating: younger, brighter, conversational.
    "user": {"fish": "802e3bc2b27e49c2995d23ef70e6ac89",
             "eleven": "bIHbv24MWmeRgasZH58o",
             "settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.15,
                          "use_speaker_boost": True}},
}
NARRATOR_SAMPLES = ["ethan", "adrian", "slax"]
CAST = {"n": "ethan", "u": "user"}

_dead: set[str] = set()          # providers that refused (a key without the TTS permission)
REFUSED_FILE = AUDIO / ".refused.json"   # remembered for a day, so a rebuild does not re-ask
_loaded = False


def _refused() -> set[str]:
    global _loaded
    if not _loaded:
        _loaded = True
        try:
            d = json.loads(REFUSED_FILE.read_text())
            if time.time() - d["at"] < 86400:
                _dead.update(d["providers"])
        except (OSError, ValueError, KeyError):
            pass
    return _dead


def _key(path: Path) -> str:
    if not path.is_file():
        return ""
    m = re.search(r"^\s*(?:export\s+)?\w*KEY\w*\s*=\s*['\"]?([^'\"\s]+)", path.read_text(),
                  re.MULTILINE)
    return m.group(1) if m else ""


class Refused(Exception):
    """The provider would not do TTS with this key (or has no voice for this name)."""


def _http(req: urllib.request.Request, provider: str) -> bytes:
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return res.read()
    except urllib.error.HTTPError as e:
        detail = e.read()[:300].decode("utf-8", "replace")
        if e.code in (401, 402, 403):
            raise Refused(f"{provider}: HTTP {e.code} {detail}") from None
        raise RuntimeError(f"{provider}: HTTP {e.code} {detail}") from None


def _eleven(text: str, voice: dict) -> bytes:
    key = _key(ELEVEN_KEY_FILE)
    if not key or "eleven" not in voice:
        raise Refused("eleven: no key or no voice")
    body = {"text": text, "model_id": ELEVEN_MODEL, "voice_settings": voice["settings"]}
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice['eleven']}"
        "?output_format=mp3_44100_192",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json"})
    return _http(req, "eleven")


def _fish(text: str, voice: dict) -> bytes:
    key = _key(FISH_KEY_FILE)
    if not key or "fish" not in voice:
        raise Refused("fish: no key or no voice")
    body = {"text": text, "reference_id": voice["fish"], "format": "mp3",
            "mp3_bitrate": 192, "sample_rate": 44100}
    if voice.get("fish_speed"):
        body["prosody"] = {"speed": voice["fish_speed"]}
    req = urllib.request.Request(
        "https://api.fish.audio/v1/tts", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                 "model": FISH_MODEL})
    return _http(req, "fish")


PROVIDERS = [("eleven", _eleven, ELEVEN_MODEL), ("fish", _fish, FISH_MODEL)]


def _cache_name(provider: str, model: str, voice: dict, text: str) -> str:
    spec = json.dumps({k: v for k, v in voice.items()
                       if k == provider or k.startswith(provider) or
                       (provider == "eleven" and k == "settings")}, sort_keys=True)
    return hashlib.sha256(f"{provider}|{model}|{spec}|{text}".encode()).hexdigest()[:16]


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True,
                         check=True).stdout
    return float(out.strip())


def speak(text: str, voice_name: str, out_dir: Path = AUDIO) -> tuple[Path, str]:
    """Path of the clip for `text` in that voice (synthesised if not cached) + provider."""
    voice = VOICES[voice_name]
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {provider: out_dir / f"{voice_name}-{_cache_name(provider, model, voice, text)}.mp3"
             for provider, _, model in PROVIDERS if provider in voice}
    for provider, path in paths.items():           # any cached clip wins, no network
        if path.is_file() and path.stat().st_size > 1000:
            return path, provider
    errors = []
    for provider, call, _ in PROVIDERS:
        if provider not in paths or provider in _refused():
            continue
        try:
            audio = call(text, voice)
        except Refused as e:
            _refused().add(provider)
            REFUSED_FILE.parent.mkdir(parents=True, exist_ok=True)
            REFUSED_FILE.write_text(json.dumps({"at": time.time(), "providers": sorted(_dead)}))
            errors.append(str(e))
            print(f"  [tts] {e} -> falling back", file=sys.stderr)
            continue
        if audio[:1] in (b"{", b"<"):
            raise RuntimeError(f"{provider}: not audio: {audio[:200]!r}")
        paths[provider].write_bytes(audio)
        print(f"  [tts] {provider}/{voice_name}: {text[:50]!r}", file=sys.stderr)
        return paths[provider], provider
    raise RuntimeError("no TTS provider worked: " + " | ".join(errors))


def ensure() -> list[dict]:
    """Every line of the script as {scene, i, who, text, file, dur, provider, voice}."""
    script = json.loads(SCRIPT.read_text())
    lines = []
    for scene in script["scenes"]:
        for i, line in enumerate(scene["lines"]):
            voice = CAST[line["who"]]
            path, provider = speak(line["text"], voice)
            lines.append({"scene": scene["id"], "i": i, "who": line["who"],
                          "text": line["text"], "file": str(path), "provider": provider,
                          "voice": voice, "dur": round(duration(path), 3),
                          **({"tag": line["tag"]} if line.get("tag") else {})})
    (AUDIO / "manifest.json").write_text(json.dumps(lines, indent=1, ensure_ascii=False))
    return lines


def samples() -> None:
    script = json.loads(SCRIPT.read_text())
    text = script["scenes"][0]["lines"][0]["text"]
    out = AUDIO / "samples"
    out.mkdir(parents=True, exist_ok=True)
    for name in NARRATOR_SAMPLES:
        path, provider = speak(text, name, out_dir=out / ".cache")
        dest = out / f"narrator-{name}.mp3"
        dest.write_bytes(path.read_bytes())
        print(f"{dest}  ({provider}, {duration(dest):.2f}s)")


def list_voices() -> None:
    key = _key(ELEVEN_KEY_FILE)
    req = urllib.request.Request("https://api.elevenlabs.io/v1/voices",
                                 headers={"xi-api-key": key})
    for v in json.loads(_http(req, "eleven"))["voices"]:
        lab = v.get("labels", {})
        print(v["voice_id"], v["name"], lab.get("gender"), lab.get("age"),
              lab.get("accent"), lab.get("descriptive") or lab.get("description"),
              lab.get("use_case"), sep=" | ")


if __name__ == "__main__":
    if "--voices" in sys.argv:
        list_voices()
    elif "--samples" in sys.argv:
        samples()
    else:
        for l in ensure():
            print(f"{l['scene']:11} {l['who']} {l['dur']:5.2f}s {l['provider']:6} {l['text']}")
