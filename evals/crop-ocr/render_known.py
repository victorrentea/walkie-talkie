#!/usr/bin/env python3
"""Code, terminal output and Romanian prose rendered to JPEGs with known text — the strata his own
crops of the last day barely hold, and the only ones where the truth is exact rather than a
stronger model's reading. Retina-sized (2 px per point) unless the name says 1x. Nothing private:
the text is below. Writes out/known/*.jpg + out/known.jsonl; then scores Vision (and Haiku with
--haiku) by CER against the truth, and lists the characters each got wrong.

    python3 evals/crop-ocr/render_known.py --ocr <path to the built ocr binary> [--haiku]
"""
import argparse, collections, json, pathlib, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import score

OUT = pathlib.Path(__file__).parent / "out"
MENLO, HELV = "/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Helvetica.ttc"
SAMPLES = {
    "java": (MENLO, 24, "dark", """public Optional<OwnerDto> findById(@PathVariable int ownerId) {
    return ownerRepository.findById(ownerId).map(o -> mapper.toDto(o, 0L));
}
private static final int MAX_PAGE_SIZE = 100; // l1 vs I1 vs |1
if (page < 0 || size > MAX_PAGE_SIZE) throw new IllegalArgumentException("page=" + page);"""),
    "shell": (MENLO, 24, "dark", """$ git log --oneline -3
a3f09c1 fix(owners): O(n) lookup -> HashMap, rn=0x1F
9d0b7e2 chore: bump spring-boot 3.5.6 -> 3.5.7
$ curl -s 'http://localhost:8080/api/owners?page=0&size=20' | jq '.[0].id'
ls ~/.walkie-talkie/outbox.jsonl /private/tmp/claude-501/x_y-z.log"""),
    "json": (MENLO, 24, "light", """{"id": 1085, "token": "sk_live_O0oIl1", "ok": true,
 "at": "2026-11-22T12:31:10.313Z", "tags": ["a_b", "c-d", "e.f"],
 "ratio": 0.0625, "path": "src/main/java/org/x/Owner.java:42"}"""),
    "trace": (MENLO, 22, "dark", """java.lang.NullPointerException: Cannot invoke "Visit.getVet()" because "v" is null
    at org.springframework.samples.petclinic.rest.VisitRestController.list(VisitRestController.java:87)
    at java.base/jdk.internal.reflect.DirectMethodHandleAccessor.invoke(DirectMethodHandleAccessor.java:103)
Caused by: org.hibernate.LazyInitializationException: could not initialize proxy [Vet#12] - no Session"""),
    "java-1x": (MENLO, 12, "dark", """public Optional<OwnerDto> findById(@PathVariable int ownerId) {
    return ownerRepository.findById(ownerId).map(o -> mapper.toDto(o, 0L));
}"""),
    "shell-small": (MENLO, 18, "dark", """$ ./relay-restart.sh --build && tail -n 20 ~/.walkie-talkie/relay.log
[14:27:49.118] mic: closed - Elgato Wave XLR: 412 buffers, peak 18233, 0 tap restart(s), 26.4 s
error: no such module 'VictorMacKit' (Package.swift:17:9)"""),
    "romanian": (HELV, 28, "light", """Șterge rândul ăsta și pune în loc numărul de înscrieri.
Țara, vârsta și orașul rămân așa; câmpul „Observații” se mută în dreapta.
În ședință am hotărât să păstrăm și butonul „Înapoi”, fără umbră."""),
    "romanian-small": (HELV, 18, "light", """Dacă însă știi că așa trebuie, lasă-l neschimbat și spune-mi de ce.
Mâine dimineață îți trimit și fișierul cu țintele pe săptămâna viitoare."""),
}


def render():
    d = OUT / "known"; d.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, (font, px, theme, text) in SAMPLES.items():
        f = ImageFont.truetype(font, px)
        bg, fg = ((30, 30, 30), (220, 220, 220)) if theme == "dark" else ((255, 255, 255), (20, 20, 20))
        lines = text.split("\n")
        w = int(max(f.getlength(l) for l in lines)) + 40
        h = int(len(lines) * px * 1.35) + 30
        im = Image.new("RGB", (w, h), bg)
        dr = ImageDraw.Draw(im)
        for i, l in enumerate(lines):
            dr.text((20, 15 + i * px * 1.35), l, font=f, fill=fg)
        p = d / f"{name}.jpg"
        im.save(p, quality=80)
        rows.append({"id": name, "file": str(p), "w": w, "h": h, "px": px, "text": text})
    with open(OUT / "known.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return rows


def diff_chars(ref, got):
    """Character substitutions only, from a cheap alignment of equal-length words."""
    c = collections.Counter()
    for a, b in zip(ref.split(), got.split()):
        if len(a) == len(b):
            for x, y in zip(a, b):
                if x != y:
                    c[f"{x}→{y}"] += 1
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ocr", required=True)
    ap.add_argument("--haiku", action="store_true")
    a = ap.parse_args()
    rows = render()
    got = collections.defaultdict(dict)
    for l in subprocess.run([a.ocr] + [r["file"] for r in rows], capture_output=True, text=True).stdout.splitlines():
        r = json.loads(l)
        got[r["config"]][pathlib.Path(r["file"]).stem] = ("\n".join(x["t"] for x in r["lines"]), r["ms"])
    if a.haiku:
        empty = tempfile.mkdtemp()
        for r in rows:
            cmd = ["claude", "-p", f"Read the image {r['file']} and reply with only the text in it, verbatim, line by line.",
                   "--model", "haiku", "--output-format", "json", "--allowedTools", "Read", "--add-dir", str(OUT / "known"),
                   "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--setting-sources", ""]
            d = json.loads(subprocess.run(cmd, cwd=empty, capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL).stdout)
            t = (d.get("result") or "").strip().strip("`").strip()
            got["haiku"][r["id"]] = (t, d.get("duration_ms"))
    names = [n for n in ("accurate", "accurate+lc", "fast", "haiku") if n in got]
    print("| sample | font px | chars | " + " | ".join(f"{n} CER · ms" for n in names) + " |")
    print("|---|---|---|" + "---|" * len(names))
    subs = collections.defaultdict(collections.Counter)
    for r in rows:
        R = score.norm(r["text"])
        cells = []
        for n in names:
            t, ms = got[n].get(r["id"], ("", 0))
            C = score.norm(t)
            cells.append(f"{100*score.lev(R, C)/len(R):.1f}% · {ms:.0f}")
            subs[n].update(diff_chars(R, C))
        print(f"| {r['id']} | {r['px']} | {len(R)} | " + " | ".join(cells) + " |")
    for n in names:
        print(n, "substitutions:", dict(subs[n].most_common(14)))
    with open(OUT / "known-read.json", "w") as f:
        json.dump({n: {k: v[0] for k, v in d.items()} for n, d in got.items()}, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
