#!/usr/bin/env python3
"""Builds demo-site/gimages/index.html — a stand-in results page for the "copy a picture" scene — from
demo-site/gimages/items.json (the result list captured from a real image search: src, w, h, x, y, alt) and the
thumbnails fetched into demo-site/gimages/img/<n>.jpg. The captured content is third-party and git-ignored;
only this script is committed. The header is a plain rebuild (wordmark, query box, tabs, a Sign in button):
nothing of anybody's account is on the page.   gimages.py   (run from teaser/)"""
import json, html
d = json.load(open("demo-site/gimages/items.json"))
cols = sorted({it["x"] for it in d["items"]})[:3]                # the first three columns fit the small window
cells = "".join(
    f'<figure style="left:{it["x"]}px;top:{it["y"] - 233 + 128}px;width:{it["w"]}px">'
    f'<img src="img/{i}.jpg" width="{it["w"]}" height="{it["h"]}" alt="{html.escape(it["alt"])}">'
    f'<figcaption>{html.escape(it["alt"][:34])}</figcaption></figure>'
    for i, it in enumerate(d["items"]) if it["x"] in cols)
open("demo-site/gimages/index.html", "w").write(f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>coffee cup - Google Search</title>
<style>
*{{box-sizing:border-box;margin:0}} body{{font:14px arial,sans-serif;background:#fff;color:#202124;overflow-x:hidden}}
#page{{width:782px;transform-origin:0 0;position:relative}}
header{{display:flex;align-items:center;gap:26px;padding:22px 25px 12px}}
.logo{{font:500 30px 'Product Sans',arial,sans-serif;letter-spacing:-1.5px}}
.box{{flex:1;height:46px;border-radius:24px;box-shadow:0 2px 5px 1px rgba(64,60,67,.16);border:1px solid #dfe1e5;padding:0 22px;font-size:16px;display:flex;align-items:center}}
.in{{background:#0b57d0;color:#fff;border-radius:20px;padding:10px 22px;font-weight:500}}
nav{{display:flex;gap:26px;padding:6px 25px 0 150px;border-bottom:1px solid #dadce0;color:#5f6368;height:34px}}
nav b{{color:#202124;border-bottom:3px solid #202124;font-weight:500}}
figure{{position:absolute}} img{{display:block;border-radius:12px;object-fit:cover}}
figcaption{{font-size:12px;color:#5f6368;padding:5px 2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
</style></head><body><div id="page">
<header><div class="logo"><span style="color:#4285f4">G</span><span style="color:#ea4335">o</span><span style="color:#fbbc05">o</span><span style="color:#4285f4">g</span><span style="color:#34a853">l</span><span style="color:#ea4335">e</span></div>
<div class="box">coffee cup</div><div class="in">Sign in</div></header>
<nav><span>AI Mode</span><span>All</span><b>Images</b><span>Videos</span><span>Shopping</span><span>News</span><span>More</span></nav>
{cells}</div>
<script>const fit=()=>document.getElementById('page').style.transform='scale('+innerWidth/782+')';fit();onresize=fit</script>
</body></html>""")
print("built", len(d["items"]), "items")
