#!/usr/bin/env python3
"""Table of out/behave.jsonl per variant. `python3 evals/crop-ocr/behave_report.py [--answers]`"""
import collections, json, pathlib, statistics, sys

rows = [json.loads(l) for l in open(pathlib.Path(__file__).parent / "out" / "behave.jsonl")]
by = collections.defaultdict(list)
for r in rows:
    by[r["variant"]].append(r)
print("| variant | runs | opened the picture | turns med | wall med (s) | input tokens med (all requests) | output med | cost med | verbatim CER mean · exact | prompt chars med |")
print("|---|---|---|---|---|---|---|---|---|---|")
for v in ("pic", "text+pic", "text", "text-first"):
    R = by[v]
    if not R:
        continue
    vb = [r for r in R if "cer" in r]
    print(f"| {v} | {len(R)} | {sum(r['opened'] for r in R)}/{len(R)} | {statistics.median(r['turns'] for r in R)} | "
          f"{statistics.median(r['wall'] for r in R):.1f} | {statistics.median(r['total_in'] for r in R):,.0f} | "
          f"{statistics.median(r['out'] for r in R):.0f} | ${statistics.median(r['cost'] for r in R):.3f} | "
          f"{100*statistics.mean(r['cer'] for r in vb):.1f}% · {sum(r['cer'] == 0 for r in vb)}/{len(vb)} | "
          f"{statistics.median(r['prompt_chars'] for r in R):.0f} |")
for v in ("text+pic", "text", "text-first"):
    no = [r for r in by[v] if not r["opened"] and "cer" in r]
    yes = [r for r in by[v] if r["opened"] and "cer" in r]
    print(f"{v}: verbatim, picture NOT opened: {len(no)} runs, exact {sum(r['cer']==0 for r in no)}, with an error where OCR had one: "
          f"{sum(r['cer']>0 and r['ocr_cer']>0 for r in no)}; opened: {len(yes)} runs, exact {sum(r['cer']==0 for r in yes)}")
if "--answers" in sys.argv:                                    # private text: for the terminal only
    for r in rows:
        print(r["case"][-22:], r["variant"], r["ask"], r["opened"], repr(r["answer"][:160]))
