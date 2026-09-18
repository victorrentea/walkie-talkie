#!/usr/bin/env bash
# Send one WAV to Gemini and print what came back, beside what is already on disk.
#
# `tools/eleven-test.sh`'s twin, and the same argument: a recogniser you can only
# reach through a dictation is a recogniser you cannot debug. This one answers
# *is the key right, does this model hear his Romanian, does the prompt keep the
# English words in English, and what does it cost in wall-clock seconds* — none
# of which should need a microphone or a running app.
#
#   tools/gemini-test.sh <file.wav> [model]
#   tools/gemini-test.sh --corpus [n] [model]     # the n newest corpus samples
#   tools/gemini-test.sh --corpus 10 --compare    # with and without the vocabulary
#
# `--compare` is the one that earned this file: it runs each sample **twice**,
# once with the terms from vocab.txt in the prompt and once without, and prints
# the two readings one above the other. That is how *"preluat automat de Cloud
# Code"* versus *"… de Claude Code"* was found, and it is the only way to know
# whether the list is doing anything on **his** voice rather than on an example.
#
# Models worth putting in the second argument (per hour of audio):
#   gemini-3.8-flash        ~$0.09   the default — newest stable Flash
#   gemini-3.5-flash-lite   ~$0.035  six times cheaper than Scribe v2
#   gemini-3.5-transcribe    $0.18   Google's purpose-built speech model
#
# The key is read the way the app reads it: GEMINI_API_KEY (or GOOGLE_API_KEY)
# from the environment, else ~/.walkie-talkie/gemini.env.

set -uo pipefail

HOME_DIR="${WALKIE_HOME:-$HOME/.walkie-talkie}"
ENV_FILE="$HOME_DIR/gemini.env"

key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
if [ -z "$key" ] && [ -f "$ENV_FILE" ]; then
    key=$(sed -n -E 's/^[[:space:]]*(GEMINI|GOOGLE)_API_KEY[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" \
          | head -1 | tr -d '"' | tr -d "'" | tr -d '[:space:]')
fi
if [ -z "$key" ]; then
    echo "no API key." >&2
    echo "  get one at https://aistudio.google.com/apikey (there is a free tier)," >&2
    echo "  then put   GEMINI_API_KEY=…   in $ENV_FILE" >&2
    exit 2
fi
export GEMINI_API_KEY="$key"

python3 - "$@" <<'PY'
import base64, json, os, sys, time, urllib.request, wave

KEY = os.environ["GEMINI_API_KEY"]
HOME = os.path.expanduser(os.environ.get("WALKIE_HOME", "~/.walkie-talkie"))
CORPUS = os.path.join(HOME, "voice-corpus")

args = [a for a in sys.argv[1:] if a != "--compare"]
COMPARE = "--compare" in sys.argv[1:]
MODEL = next((a for a in args if a.startswith("gemini-")),
             os.environ.get("WT_GEMINI_MODEL", "gemini-3.8-flash"))


def vocab_terms(limit=1500):
    """The same file the app puts in the prompt — his copy first, the checked-in
    starter second. `sounds_like` is dropped: it tells an acoustic model what a
    word sounds like, and handing a language model two misspellings would teach
    it two misspellings."""
    here = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "vocab.txt")
    for path in (os.path.join(HOME, "vocab.txt"),
                 os.path.join(HOME, "speechmatics-vocab.txt"), here, "tools/vocab.txt"):
        if os.path.exists(path):
            break
    else:
        return ""
    line = ""
    for raw in open(path, encoding="utf-8"):
        row = raw.strip()
        if not row or row.startswith("#"):
            continue
        term = row.split(":", 1)[0].strip()
        if not term:
            continue
        nxt = term if not line else line + ", " + term
        if len(nxt) > limit:
            break
        line = nxt
    return line


BASE_PROMPT = """Transcrie cuvânt cu cuvânt ce se aude în înregistrare.

Vorbitorul dictează în română cu termeni tehnici în engleză. Păstrează termenii \
englezești scriși corect în engleză — nu îi traduce și nu îi scrie fonetic.

Reguli stricte:
- Redă exact ce s-a spus. NU rezuma, NU scurta, NU repara fraze neterminate. \
Dacă vorbitorul se repetă sau se bâlbâie, scrie repetiția.
- Răspunde DOAR cu transcrierea. Fără introduceri, fără ghilimele, fără \
comentarii despre calitatea audio.
- Dacă nu se aude nicio vorbă, răspunde cu un rând gol."""


def prompt(with_vocab=True):
    terms = vocab_terms() if with_vocab else ""
    if terms:
        return BASE_PROMPT + f"\n\nTermeni care apar des și trebuie scriși așa: {terms}."
    return BASE_PROMPT


def transcribe(path, with_vocab=True):
    audio = open(path, "rb").read()
    body = {"contents": [{"parts": [
        {"text": prompt(with_vocab)},
        {"inline_data": {"mime_type": "audio/wav",
                         "data": base64.b64encode(audio).decode()}}]}],
        "generationConfig": {"maxOutputTokens": 8192}}
    if "transcribe" not in MODEL:
        body["generationConfig"]["thinking_config"] = {
            "thinking_level": os.environ.get("WT_GEMINI_THINKING", "LOW")}

    url = ("https://generativelanguage.googleapis.com/v1beta/models/"
           f"{MODEL}:generateContent")
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"x-goog-api-key": KEY,
                                          "Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            reply = json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read()[:400].decode(errors="replace")
        # A 400 is either the key or a field the model does not take — and they
        # want opposite fixes, so the hint has to tell them apart. The app makes
        # the same distinction before deciding whether to retry.
        hint = ""
        if e.code == 400:
            hint = ("  (the key is not valid)" if "API key not valid" in detail
                    else "  (try WT_GEMINI_THINKING= or another model)")
        return f"!! HTTP {e.code}{hint}: {detail}", time.time() - t0
    except Exception as e:
        return f"!! {e}", time.time() - t0

    elapsed = time.time() - t0
    if "promptFeedback" in reply and reply["promptFeedback"].get("blockReason"):
        return f"!! blocked: {reply['promptFeedback']['blockReason']}", elapsed
    cand = (reply.get("candidates") or [{}])[0]
    parts = (cand.get("content") or {}).get("parts") or []
    text = "".join(p.get("text", "") for p in parts).strip()
    if cand.get("finishReason", "STOP") != "STOP":
        text += f"   [finishReason={cand['finishReason']}]"
    return text, elapsed


def seconds(path):
    with wave.open(path) as w:
        return w.getnframes() / w.getframerate()


def one(path):
    secs = seconds(path)
    txt = path[:-4] + ".txt"
    on_disk = open(txt, encoding="utf-8").read().strip().replace("\n", " ") \
        if os.path.exists(txt) else "(no transcript)"
    print(f"── {os.path.basename(path)}  ({secs:.1f}s)")
    print(f"   pe disc     : {on_disk}")
    if COMPARE:
        bare, el = transcribe(path, with_vocab=False)
        print(f"   fără vocab  : {bare}   [{el:.2f}s]")
    text, el = transcribe(path, with_vocab=True)
    print(f"   {'cu vocab    ' if COMPARE else 'gemini      '}: {text}   [{el:.2f}s]")
    # The guard the app applies, printed here so the threshold can be judged
    # against real output rather than against the docstring that set it.
    if secs >= 3 and text and not text.startswith("!!"):
        print(f"   {len(text)/secs:.1f} chars per wall second")
    print()


if args and args[0] == "--corpus":
    n = int(args[1]) if len(args) > 1 and args[1].isdigit() else 5
    found = [os.path.join(root, f)
             for root, _, files in os.walk(CORPUS) for f in files if f.endswith(".wav")]
    wavs = sorted(found, key=os.path.getmtime, reverse=True)[:n]
    terms = vocab_terms()
    print(f"{MODEL} — the {len(wavs)} newest corpus samples"
          + (f", {terms.count(',') + 1} terms in the prompt" if terms else ", no vocabulary")
          + ("  (with and without the vocabulary)" if COMPARE else "") + "\n")
    for wav in wavs:
        one(wav)
    sys.exit(0)

wav = args[0] if args else ""
if not wav or not os.path.isfile(wav):
    sys.exit("usage: gemini-test.sh <file.wav> [model]\n"
             "       gemini-test.sh --corpus [n] [model] [--compare]")
print(f"{MODEL} — {os.path.basename(wav)}\n")
one(wav)
PY
