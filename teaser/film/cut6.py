#!/usr/bin/env python3
"""Round 6: export the takes in /tmp/teaser-raw to teaser/footage/<clip>.mp4 + <clip>.json (run by `round6.sh cut`).
The clip a take replaces is kept beside it as <clip>-r5.mp4 / .json. Times in the sidecar are seconds inside the
exported clip; rects are [x, y, w, h] in the clip's own pixels (1920x1080 = the guest's 960x540 pt screen at 2x).
    cut6.py [take …]        default: every take listed below"""
import json, os, re, subprocess, sys
RAW = "/tmp/teaser-raw"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "footage")
COMMON = ("Guest wt-lab at 960x540 HiDPI, filmed whole (no punch-in needed), light appearance, normal fonts and zoom; site at "
          "http://brewly.test (a hosts name). Pointer: human paths (curved, ease-out). Voice into the guest mic = macOS `say`, "
          "recognised by the local Whisper. The terminal's session is a stand-in drawn to look like Claude Code (film/agent.py): "
          "it shows the prompt Walkie really delivered and applies a scripted edit. ")
# take → (clip, seconds trimmed off the start, note)
TAKES = {
 "s01": ("s01-hook", 0.0, "Large terminal with the stand-in session, still until bind_start; real cmd-ctrl-B with the pointer on it (outline, the "
         "window flies into the pointer, the Walkie atom then rides the pointer: the app shows no session NAME there); the hand goes to the page "
         "strip left of the terminal and clicks: the browser covers the terminal."),
 "s02": ("s02-site", 3.2, "Two blue buttons. Real prompt to the bound terminal behind the browser (dust at the pointer, right edge). The pointer comes to "
         "rest on the SECOND button (See the plans) as 'this button' is said and the shutter (back button) is pressed there: [📸1] lands after "
         "'this button' in the prompt. Result: header dark, only that button orange (WHICH button is scripted in the stand-in, not read from "
         "the screenshot). Cost pill = the app's real pill with a made-up amount; the pointer goes onto it, which holds it at full opacity "
         "from pointer_on_pill to pointer_off_pill, then it fades over ~4 s."),
 "s03": ("s03-move", 3.2, "Starts from s02's page. Wheel box round the green badge (0.8 s drag, slows into the corner), shift locks it, the ghost rides the "
         "pointer up (1.15 s, slows in), a click drops it above the headline; the badge lands exactly in the dropped box (coordinates read by the "
         "stand-in from the prompt's own ✂️ … moved to … token). Pill as in s02. Then a real cmd-Tab (switcher visible from cmd_tab to "
         "search_page_front): Chrome with the image search comes forward and stays ~3 s."),
 "s04": ("s04-point", 1.0, "Starts on the image search (Chrome app window, no address bar; rebuilt results page from captured thumbnails). Right-click a picture, "
         "Copy Image (menu visible menu_open→copy_clicked; the copy flies into the chip), real cmd-Tab back to the site, a wheel box drawn in "
         "0.45 s over an empty area of the page (no placeholder there), then 'at your door by Thurdsay' selected by a visible 0.8 s drag (five words "
         "rather than one: the panel's own clock is words/3 s, min 4 — this is what keeps it up 6.9 s). The hand is on the atom the moment the words "
         "are ready: the prompt panel is on screen, untouched, from panel_open to prompt_sent (it sends itself when its countdown ends). Whisper "
         "wrote 'Use this picture. [copied] [crop] Here. And fix this text. [selection]'. The automatic context screenshot was switched off for "
         "this take only (with it the panel is taller than the 540 pt screen and the sentence scrolls out of view). Result: the copied picture "
         "appears in the drawn box (box read from the prompt's ✂️ token), Thurdsay → Thursday. Pill as in s02. The panel shows 'Mic: BlackHole 2ch' "
         "and 'Engine: Local Whisper Turbo'."),
 "s06": ("s06-review", 3.2, "Java diff page (drawn in the browser). The loop is selected by a 0.3 s drag WHILE 'I do not like this loop' is spoken "
         "(selection_start/end), then 'Use streams.'; the stand-in rewrites it to items.stream().filter(Item::active).mapToDouble(i -> i.price() * "
         "i.qty()).sum()."),
 "s07e": ("s07-modes-e", 3.2, "DARK appearance, the page as s04 left it, bound terminal fully hidden behind the browser. Prompt to it (right edge dust); at prompt_sent "
          "it is sent and a real cmd-Tab (switcher visible) brings the terminal forward: the prompt in the SHORT envelope ([📸0 auto] / the sentence / "
          "[dictated 💻 · 🎙️] / [📁=…]), a tool row and the spinner, working until the clip ends."),
 "s07a": ("s07-modes-a", 3.6, "Same desktop. Forward-up: top edge dust and the REAL folder dialog — api, brewly (under it the bound session, working: ✓ ⏳ brewly), docs, "
          "mobile-app, Workspace — brewly clicked at folder_picked. After the sentence a new Terminal window with the stand-in 'claude' opens (behind "
          "the browser; the script moves it to the usual place unseen), a real cmd-Tab shows it: the prompt in the short envelope, working. Long wait "
          "between dictation_ends and spawned (transcription + spawn): cut it."),
 "s07b": ("s07-modes-b", 3.8, "Same desktop. The wake is INJECTED (/test/wake at `wake`; the lab has no wake-word helper): the chip's 'Hey Claude — listening' row, top edge "
          "dust, the spoken sentence, then the spawned session brought forward by a real cmd-Tab (window placed by the script, unseen)."),
 "s07c": ("s07-modes-c", 3.6, "Same desktop, the terminal in front. Prompt at the caret: red pin on the caret, red frame round the window, bottom edge dust with pins; the "
          "words land in the session's input box at prompt_lands and are submitted by the app's own closing Return."),
 "s07d": ("s07-modes-d", 3.6, "Same browser, a chat page. Plain dictation: Mosaic tiles, red pin on the caret, red frame; chip Dictating → Transcribing → Redacting; the clean "
          "text lands at text_landed and stays still to the end of the clip. The redactor's far end is a scripted stand-in for `claude -p` "
          "(film/claude_p.py) reading the seeded vocabulary: fillers dropped, 'Resilience 4G' → 'Resilience4j'."),
}


def export(take):
    clip, trim, note = TAKES[take]
    src = f"{RAW}/{take}.mp4"
    for ext in ("mp4", "json"):                               # keep the round-5 clip until this one is verified
        old, kept = f"{OUT}/{clip}.{ext}", f"{OUT}/{clip}-r5.{ext}"
        if os.path.exists(old) and not os.path.exists(kept): os.rename(old, kept)
    subprocess.run(["nice", "-n", "5", "ffmpeg", "-loglevel", "error", "-y", "-ss", str(trim), "-i", src, "-an", "-r", "30", "-c:v", "libx264",
                    "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart", f"{OUT}/{clip}.mp4"], check=True)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f"{OUT}/{clip}.mp4"],
                               capture_output=True, text=True).stdout)
    d = {"note": COMMON.replace("light appearance", "dark appearance") + note if take.startswith("s07") else COMMON + note,
         "size": [1920, 1080], "points_to_pixels": 2, "duration": round(dur, 2), "round": 6}
    marks = sorted(((float(t), n) for n, t in (l.split() for l in open(f"{RAW}/{take}.marks"))))
    d["events"] = {n: round(t - trim, 2) for t, n in marks}
    if os.path.exists(f"{RAW}/{take}.rects"):
        for line in open(f"{RAW}/{take}.rects"):
            name, _, val = line.partition(" ")
            if name == "pill" and val.strip().startswith("{"): d["cost_pill_rect"] = json.loads(val)["rect_px"]
        if "cost_pill_rect" in d:
            e = d["events"]; d["cost_pill_visible"] = {"from": e["cost_pill"], "full_opacity_until": e["pointer_off_pill"], "gone_by": round(e["pointer_off_pill"] + 4, 1)}
    extra = f"{RAW}/{take}.extra.json"
    if os.path.exists(extra): d.update(json.load(open(extra)))
    json.dump(d, open(f"{OUT}/{clip}.json", "w"), indent=1, ensure_ascii=False)
    print(clip, round(dur, 1), "s")


for t in sys.argv[1:] or TAKES: export(t)
