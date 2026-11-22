#!/usr/bin/python3
"""Draws the arrow pointer in the guest, because Virtualization.framework's VNC framebuffer carries no cursor.

A click-through, borderless window that follows the mouse at 120 Hz, above everything. `sharingType = none`,
so Walkie's own screenshots (and any in-guest capture) never see it — only the hypervisor's framebuffer does.
Guest only: /usr/bin/python3 fakecursor.py  (kill it to take the arrow away)
"""
import AppKit as A
from Foundation import NSTimer, NSMakeRect

app = A.NSApplication.sharedApplication()
app.setActivationPolicy_(A.NSApplicationActivationPolicyAccessory)
cur = A.NSCursor.arrowCursor(); img = cur.image(); hot = cur.hotSpot(); size = img.size()
win = A.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
    NSMakeRect(0, 0, size.width, size.height), A.NSWindowStyleMaskBorderless | A.NSWindowStyleMaskNonactivatingPanel,
    A.NSBackingStoreBuffered, False)
win.setOpaque_(False); win.setBackgroundColor_(A.NSColor.clearColor()); win.setHasShadow_(False)
win.setIgnoresMouseEvents_(True); win.setLevel_(2147483630)                 # above the screen saver and every overlay
win.setCollectionBehavior_(A.NSWindowCollectionBehaviorCanJoinAllSpaces | A.NSWindowCollectionBehaviorStationary
                           | A.NSWindowCollectionBehaviorFullScreenAuxiliary | A.NSWindowCollectionBehaviorIgnoresCycle)
win.setSharingType_(0)
view = A.NSImageView.alloc().initWithFrame_(NSMakeRect(0, 0, size.width, size.height)); view.setImage_(img)
win.setContentView_(view); win.orderFrontRegardless()


def tick(_):
    p = A.NSEvent.mouseLocation()
    win.setFrameOrigin_((p.x - hot.x, p.y - (size.height - hot.y)))
    win.orderFrontRegardless()


NSTimer.scheduledTimerWithTimeInterval_repeats_block_(1 / 120.0, True, tick)
app.run()
