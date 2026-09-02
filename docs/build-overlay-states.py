#!/usr/bin/env python3
"""Build docs/overlay-states.html out of the manifest OverlayStates just shot.

The page is generated rather than written so it cannot drift: the states, their
order, the sections and every word of prose come from `OverlayStates.swift`, and
this file only decides how they are laid out. Add a state there and it appears
here; change what a state looks like and the picture changes on the next run.

Run through `docs/shoot-overlay-states.sh`, which takes the photographs first.
"""

import html
import json
import pathlib
import re
import subprocess
import datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATES = ROOT / "docs" / "states"
OUT = ROOT / "docs" / "overlay-states.html"


def inline(text):
    """`code`, **bold**, *italic* — the three marks the notes actually use."""
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", out)
    return out


SHAPES = {
    "chip": ("chip", "bare text beside the cursor — no blur, no shadow, no ✕"),
    "flash": ("flash", "a message in the chip for a few seconds — bare like the chip, no blur, no border"),
    "panel": ("panel", "top-left of the screen, blurred, full opacity, ✕ on hover"),
    "none": ("no window", "nothing on screen"),
}


def card(state):
    slug = state["slug"]
    shape, shape_hint = SHAPES[state["shape"]]
    alpha = state["alpha"]
    bits = [
        f'<span class="tag tag-{state["shape"]}" title="{html.escape(shape_hint)}">{shape}</span>',
    ]
    if state["shape"] != "none":
        bits.append(f'<span class="tag">alpha {alpha:.2f}</span>')
        bits.append(f'<span class="tag">{state["width"]}×{state["height"]} pt</span>')

    if state.get("image"):
        art = (
            f'<div class="shot"><img src="states/{state["image"]}" '
            f'width="{state["width"]}" height="{state["height"]}" '
            f'style="opacity:{alpha}" alt="{html.escape(state["title"])}"></div>'
        )
    else:
        art = '<div class="shot empty"><span>no window on screen</span></div>'

    return f"""      <section class="card" id="{slug}">
        <header>
          <h3>{html.escape(state['title'])}</h3>
          <div class="tags">{''.join(bits)}</div>
        </header>
        {art}
        <p class="when">{inline(state['when'])}</p>
        <p class="note">{inline(state['note'])}</p>
        <code class="slug">{slug}</code>
      </section>"""


def main():
    states = json.loads((STATES / "states.json").read_text())
    groups = []
    for state in states:
        if not groups or groups[-1][0] != state["group"]:
            groups.append((state["group"], []))
        groups[-1][1].append(state)

    try:
        stamp = subprocess.run(["git", "log", "-1", "--format=%h · %ad", "--date=format:%d %b %Y"],
                               cwd=ROOT, capture_output=True, text=True).stdout.strip()
    except Exception:
        stamp = ""
    built = datetime.datetime.now().strftime("%d %b %Y, %H:%M")

    nav = " ".join(f'<a href="#{html.escape(name)}">{html.escape(name)}</a>' for name, _ in groups)
    body = []
    for name, items in groups:
        body.append(f'    <h2 id="{html.escape(name)}">{html.escape(name)}</h2>')
        body.append('    <div class="grid">')
        body.extend(card(s) for s in items)
        body.append("    </div>")

    OUT.write_text(PAGE.format(
        nav=nav,
        body="\n".join(body),
        count=len(states),
        stamp=html.escape(stamp),
        built=built,
    ))
    print(f"→ {OUT.relative_to(ROOT)} ({len(states)} states)")


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Walkie Talkie — every state of the overlay</title>
<style>
  :root {{
    --ink: #e8e8ea; --dim: #9a9aa4; --line: #2c2c33;
    --bg: #16161a; --card: #1d1d22;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 0 24px 96px;
    background: var(--bg); color: var(--ink);
    font: 15px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  }}
  header.page {{ max-width: 760px; margin: 0 auto; padding: 56px 0 8px; }}
  h1 {{ font-size: 30px; letter-spacing: -0.02em; margin: 0 0 6px; }}
  .sub {{ color: var(--dim); margin: 0 0 22px; }}
  .rule {{
    border: 1px solid var(--line); border-left: 3px solid #d9803a;
    border-radius: 8px; padding: 14px 16px; background: #1b1b20; margin: 22px 0;
  }}
  .rule b {{ color: #f0a868; }}
  nav {{ max-width: 760px; margin: 0 auto 8px; display: flex; gap: 14px; flex-wrap: wrap; }}
  nav a {{ color: var(--dim); text-decoration: none; border-bottom: 1px solid transparent; }}
  nav a:hover {{ color: var(--ink); border-color: var(--line); }}
  h2 {{
    max-width: 1180px; margin: 46px auto 14px; font-size: 13px; letter-spacing: 0.14em;
    text-transform: uppercase; color: var(--dim); border-bottom: 1px solid var(--line);
    padding-bottom: 8px;
  }}
  .grid {{
    max-width: 1180px; margin: 0 auto;
    display: grid; gap: 18px;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
  }}
  .card {{
    background: var(--card); border: 1px solid var(--line); border-radius: 12px;
    padding: 16px; display: flex; flex-direction: column;
  }}
  .card header {{ display: flex; flex-wrap: wrap; gap: 8px; align-items: baseline; }}
  h3 {{ font-size: 16px; margin: 0; flex: 1 1 auto; }}
  .tags {{ display: flex; gap: 6px; flex-wrap: wrap; }}
  .tag {{
    font-size: 11px; color: var(--dim); border: 1px solid var(--line);
    border-radius: 20px; padding: 1px 8px; white-space: nowrap;
  }}
  .tag-chip {{ color: #8fd3a8; border-color: #2f4a3a; }}
  .tag-flash {{ color: #e8c06a; border-color: #4d4128; }}
  .tag-panel {{ color: #8fb8e8; border-color: #2c3f56; }}
  .tag-none {{ color: #8a8a94; border-style: dashed; }}
  /* The backdrop is the point: the chip is white text with a halo, drawn over
     whatever Victor happens to be working on. Two of them, switchable, because
     legibility over a dark editor says nothing about legibility over a page. */
  .shot {{
    margin: 14px 0 12px; padding: 20px; border-radius: 10px; min-height: 96px;
    display: flex; align-items: center; justify-content: center;
    background-color: #24242a;
    background-image:
      linear-gradient(90deg, rgba(255,255,255,.06) 0 34%, transparent 34%),
      linear-gradient(90deg, rgba(255,255,255,.05) 0 21%, transparent 21%),
      linear-gradient(90deg, rgba(255,255,255,.06) 0 46%, transparent 46%),
      linear-gradient(90deg, rgba(255,255,255,.04) 0 28%, transparent 28%);
    background-repeat: no-repeat;
    background-position: 24px 22px, 24px 44px, 24px 66px, 24px 88px;
    background-size: 100% 7px;
  }}
  body.light .shot {{
    background-color: #f2f1ee;
    background-image:
      linear-gradient(90deg, rgba(0,0,0,.10) 0 34%, transparent 34%),
      linear-gradient(90deg, rgba(0,0,0,.08) 0 21%, transparent 21%),
      linear-gradient(90deg, rgba(0,0,0,.10) 0 46%, transparent 46%),
      linear-gradient(90deg, rgba(0,0,0,.07) 0 28%, transparent 28%);
  }}
  .shot img {{ display: block; max-width: 100%; height: auto; }}
  .shot.empty {{
    border: 1px dashed var(--line); background: none; color: var(--dim);
    font-size: 13px; font-style: italic;
  }}
  .when {{ margin: 0 0 8px; color: var(--ink); }}
  .when::before {{ content: "When  "; color: var(--dim); letter-spacing: .08em; font-size: 11px; text-transform: uppercase; }}
  .note {{ margin: 0 0 10px; color: var(--dim); }}
  .slug {{ margin-top: auto; font-size: 11px; color: #6a6a74; }}
  code {{ font: 12.5px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
          background: rgba(255,255,255,.06); border-radius: 4px; padding: 1px 5px; }}
  .toggle {{
    position: fixed; right: 20px; bottom: 20px; z-index: 5;
    background: #2a2a31; color: var(--ink); border: 1px solid var(--line);
    border-radius: 20px; padding: 8px 16px; font: inherit; font-size: 13px; cursor: pointer;
  }}
  .toggle:hover {{ background: #34343d; }}
  footer {{ max-width: 760px; margin: 60px auto 0; color: #6a6a74; font-size: 13px; }}
  a {{ color: #8fb8e8; }}
</style>
</head>
<body>
<header class="page">
  <h1>Every state of the overlay</h1>
  <p class="sub">
    All {count} states the Walkie&nbsp;Talkie chip and panel can be in — what each one
    is, and the moment it is on screen. The pictures are the real views drawing
    themselves, not mockups.
  </p>
  <p>
    No screen capture can contain this window (<code>sharingType</code>, and
    <code>RELAY_CAPTURABLE=1</code> stopped buying it back on macOS&nbsp;15), so
    every shot here is <code>RelayWindow.snapshot</code> — the view rendering into a
    bitmap. Two things that costs: a panel's <b>blur is missing</b>, because the
    window server draws it and not the view, and the window's <b>alpha</b> is applied
    here in CSS rather than being in the pixels. The chip has no blur at all, so it
    comes out exactly as Victor sees it, over whatever is underneath — hence the
    backdrop switch at the bottom right.
  </p>
  <div class="rule">
    <b>The rule.</b> Any change to the overlay — a new row, a reworded string, a
    state that appears or disappears — is not finished until this page is rebuilt:
    <code>./docs/shoot-overlay-states.sh</code>. A new state means a new entry in
    <code>Sources/WalkieTalkie/OverlayStates.swift</code>, which is where every word
    on this page comes from; the page itself is generated and must never be edited
    by hand.
  </div>
</header>
<nav>{nav}</nav>
{body}
<footer>
  Generated from <code>OverlayStates.swift</code> · repo at {stamp} · built {built}
</footer>
<button class="toggle" onclick="document.body.classList.toggle('light')">Backdrop: dark / light</button>
</body>
</html>
"""


if __name__ == "__main__":
    main()
