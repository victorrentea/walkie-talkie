#!/usr/bin/env python3
"""Chrome's window title and frame, straight from the window server."""
import sys
from Quartz import (CGWindowListCopyWindowInfo, kCGWindowListOptionOnScreenOnly,
                    kCGNullWindowID)
want = sys.argv[1] if len(sys.argv) > 1 else "Chrome"
for w in CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID):
    if want.lower() in (w.get("kCGWindowOwnerName") or "").lower():
        b = w["kCGWindowBounds"]
        print(f'{w.get("kCGWindowName")!r} layer={w.get("kCGWindowLayer")} '
              f'x={b["X"]:.0f} y={b["Y"]:.0f} w={b["Width"]:.0f} h={b["Height"]:.0f}')
