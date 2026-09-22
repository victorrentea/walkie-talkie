#!/usr/bin/env python3
"""Watch Wispr Flow's History rows fill in, column by column.

Read-only poll of `flow.sqlite` (WAL, so Wispr's writer is never blocked).
Prints one line per *change* to (status, asrText, pastedText, formattedText,
e2eLatency) of the newest rows — the only way to see, from outside Wispr,
whether `raw_transcript` is a row still arriving or a row already finished.

    tools/wispr-row-watch.py [--interval 0.2] [--rows 3]
"""
import argparse, os, sqlite3, sys, time

DB = os.path.expanduser("~/Library/Application Support/Wispr Flow/flow.sqlite")
COLS = ("status", "asrText", "pastedText", "formattedText")


def snapshot(con, rows):
    q = ("select rowid, coalesce(status,''), coalesce(asrText,''), coalesce(pastedText,''), "
         "coalesce(formattedText,''), coalesce(e2eLatency,0), coalesce(app,'') "
         f"from History order by rowid desc limit {rows}")
    return {r[0]: r[1:] for r in con.execute(q)}


def describe(v):
    status, asr, pasted, formatted, e2e, app = v
    return (f"status={status or '∅':<14} asr={len(asr):<5} pasted={len(pasted):<5} "
            f"formatted={len(formatted):<5} e2e={e2e:.0f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=float, default=0.2)
    ap.add_argument("--rows", type=int, default=3)
    a = ap.parse_args()
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    seen, t0 = {}, {}
    while True:
        try:
            now = snapshot(con, a.rows)
        except sqlite3.Error as e:  # Wispr checkpointing; try again next tick
            print(f"! {e}", flush=True); time.sleep(a.interval); continue
        for rowid, v in sorted(now.items()):
            if rowid not in seen:
                t0[rowid] = time.time()
                print(f"\n=== row {rowid} appeared ({v[5]}) ===", flush=True)
            elif seen[rowid] == v:
                continue
            print(f"{time.strftime('%H:%M:%S')} +{time.time()-t0[rowid]:6.2f}s row {rowid}  {describe(v)}",
                  flush=True)
            seen[rowid] = v
        time.sleep(a.interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
