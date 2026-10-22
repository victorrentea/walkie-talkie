import sys, os, io, contextlib, json
sys.path.insert(0, "/Users/victorrentea/workspace/walkie-talkie/evals/chunked-decode")
import numpy as np
import chunked_decode as C
model = sys.argv[1]
n = int(sys.argv[2])
os.environ["RELAY_WHISPER_MODEL"] = model
sys.path.insert(0, "/Users/victorrentea/workspace/walkie-talkie/helpers")
stdin, stdout = sys.stdin, sys.stdout
sys.stdin, sys.stdout = io.StringIO(""), io.StringIO()
try:
    import whisper_helper as wh
finally:
    sys.stdin, sys.stdout = stdin, stdout
takes = C.select_takes()[:n]
stats = {"chunks": 0, "with_later": 0, "kept": 0, "dropped": 0}
for t in takes:
    x = C.read_wav(os.path.join(C.CORPUS, t["wav"]))
    v = C.voiced_hops(x)
    chunks, tail = C.plan(v, len(x) / C.SR, trigger=10.0, min_gap=0.9, min_chunk=8.0)
    pieces = chunks + ([tail] if tail else [])
    for (a, b, _) in pieces:
        i, j = int(round(a * C.SR)), int(round(b * C.SR))
        if j - i > 30 * C.SR: continue
        s = wh.mx.array(x[i:j]).astype(wh.mx.float32) / 32768.0
        lang = wh.pick_language(s)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            res = wh.mlx_whisper.transcribe(s, path_or_hf_repo=wh.MODEL, language=lang,
                initial_prompt=wh.VOCABULARY_RO if lang == "ro" else wh.VOCABULARY, verbose=False,
                condition_on_previous_text=False, word_timestamps=True, temperature=0.0)
        stats["chunks"] += 1
        later = [g for g in res["segments"] if g.get("seek", 0) != 0]
        if not later: continue
        stats["with_later"] += 1
        import copy
        r2 = copy.deepcopy(res); wh.first_window_only(r2, True, s)
        keptL = [g for g in r2["segments"] if g.get("seek", 0) != 0]
        print("  helper keeps", len(keptL), "of", len(later), "later segment(s):", [g["text"][:40] for g in keptL])
        stats["helper_kept"] = stats.get("helper_kept", 0) + len(keptL)
        meter = wh._voice_meter(s)
        last0 = [g for g in res["segments"] if g.get("seek", 0) == 0]
        lw = (last0[-1].get("words") or [{}])[-1] if last0 else {}
        print(f"{t['wav'][-26:]} [{a:.1f}-{b:.1f}] ({b-a:.1f}s) last word {lw.get('word','')!r}@{lw.get('start',0):.2f}-{lw.get('end',0):.2f}")
        for g in later:
            fe = max([x.get("end",0.0) for x in res["segments"] if x.get("seek",0)==0] or [0.0])
            vv = meter(max(g["start"], fe + 0.3), g["end"])
            k = vv >= 1.0
            stats["kept" if k else "dropped"] += 1
            print(f"    {'KEPT' if k else 'DROP'} [{g['start']:.2f}-{g['end']:.2f}] v={vv:.2f} {g['text'][:70]!r}")
print(json.dumps(stats))
