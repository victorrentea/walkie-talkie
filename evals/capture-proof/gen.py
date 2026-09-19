#!/usr/bin/env python3
"""Write one standalone scene file per (paragraph, word, occurrence).

Baked in rather than passed as a query string: `open -a "Google Chrome" file:…`
goes through LaunchServices, which resolves the URL to a plain path and drops
everything after the `?` — the selection silently never happened.
"""
import json, pathlib, sys

base = pathlib.Path("page.html").read_text()

def scene(name, para, word, nth=1):
    s = base.replace("  const q = new URLSearchParams(location.search);\n"
                     "  const para = q.get('p') || 'p1';\n"
                     "  const word = q.get('w');\n"
                     "  const nth  = parseInt(q.get('n') || '1', 10);\n",
                     f"  const para = {json.dumps(para)};\n"
                     f"  const word = {json.dumps(word)};\n"
                     f"  const nth  = {nth};\n")
    assert "const word = " in s and "URLSearchParams" not in s, "patch missed"
    out = pathlib.Path(f"scene-{name}.html")
    out.write_text(s)
    return out

if __name__ == "__main__":
    for spec in sys.argv[1:]:
        name, para, word, nth = spec.split(":")
        print(scene(name, para, word, int(nth)))
