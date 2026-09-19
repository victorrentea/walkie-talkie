#!/usr/bin/env python3
"""Read or move the pointer, in screen points (top-left origin)."""
import sys
from Quartz import (CGWarpMouseCursorPosition, CGEventCreate, CGEventGetLocation,
                    CGAssociateMouseAndMouseCursorPosition)
if len(sys.argv) == 3:
    x, y = float(sys.argv[1]), float(sys.argv[2])
    CGWarpMouseCursorPosition((x, y))
    CGAssociateMouseAndMouseCursorPosition(True)
p = CGEventGetLocation(CGEventCreate(None))
print(f"{p.x:.0f} {p.y:.0f}")
