#!/usr/bin/env python3
"""A review copy of the teaser with the scene's name burned in, top-left.

    python3 teaser/label.py            # out/teaser-vN.mp4 -> out/teaser-vN-labels.mp4

Victor names what to change by scene ("scena 4"), so the review copy says which scene is on
screen. Reads the cut list build.py leaves in its work folder; the film itself is untouched.
"""
import json, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw
import build

NAMES = {"s01": "1 · hook", "s02": "2 · site", "s03": "3 · move", "s04": "4 · point",
         "s05": "5 · film", "s06": "6 · code review", "s07": "7 · destinations",
         "s08": "8 · question", "s09": "9 · cost", "s10": "10 · end"}
SUB = {"e": "7e · session in the back", "a": "7a · new session", "b": "7b · wake word",
       "c": "7c · at the cursor", "d": "7d · clean dictation"}


def spans() -> list[tuple[float, float, str]]:
    cuts = json.loads((build.WORK / "cutlist.json").read_text())
    out: list[tuple[float, float, str]] = []
    for c in cuts:
        clip = c["clip"]
        name = SUB[clip[-1]] if clip.startswith("s07-modes-") else NAMES[c["scene"][:3]]
        if out and out[-1][2] == name and abs(out[-1][1] - c["from"]) < 0.05:
            out[-1] = (out[-1][0], c["to"], name)
        else:
            out.append((c["from"], c["to"], name))
    return out


def png(text: str, path: Path) -> None:
    f = build.font(40, "Bold")
    w = int(f.getlength(text)) + 48
    im = Image.new("RGBA", (build.W, build.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((28, 28, 28 + w, 28 + 64), 16, fill=(0, 0, 0, 200))
    d.text((52, 60), text, font=f, fill=(255, 214, 10, 255), anchor="lm")
    im.save(path)


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else build.FINAL
    dst = src.with_name(src.stem + "-labels.mp4")
    sp = spans()
    dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                "format=duration", "-of", "csv=p=0", str(src)]).strip())
    sp.append((sp[-1][1], dur, NAMES["s10"]))
    inputs, chains, last = ["-i", str(src)], [], "0:v"
    for i, (a, b, name) in enumerate(sp):
        p = build.WORK / f"label-{i}.png"
        png(name, p)
        inputs += ["-i", str(p)]
        chains.append(f"[{last}][{i + 1}:v]overlay=0:0:enable='between(t,{a:.3f},{b:.3f})'[l{i}]")
        last = f"l{i}"
    subprocess.run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex", ";".join(chains),
                    "-map", f"[{last}]", "-map", "0:a", "-c:v", "libx264", "-preset", "medium",
                    "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "copy", "-movflags", "+faststart",
                    str(dst)], check=True)
    print(dst, f"{len(sp)} labels")


if __name__ == "__main__":
    main()
