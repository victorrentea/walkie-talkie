import AppKit
import ObjectiveC

/// **Everything this app draws is in a Teams/Zoom share; nothing it draws is in
/// its own pictures** (2026-11-20, Victor: *"every thing that Walkie Talkie draws
/// should be visible in Zoom and Teams screen share"* — the folder menu of a new
/// session was *"too mysterious otherwise"*, and the edge dust *"we worked so hard
/// … and they don't see it"*).
///
/// Until that day almost every window was `sharingType = .none`, which hid it
/// from every capture — the room's included. Rewriting forty call sites would be
/// forty chances to miss one, so the rule is caught at the source, the way
/// `Offstage` catches frames:
///
/// - **`setSharingType:` is swizzled**: a `.none` asked for outside the
///   shutter's picture is written as `.readOnly`. Every existing `.none` /
///   `capturable ? … : .none` keeps compiling and means *out of my own shots*.
/// - **`ReplyPanel.outOfShot` takes every window of the process to `.none`** for
///   the length of the shutter's `screencapture` (and the film's frame grab, the
///   ripple's frame), then back to `.readOnly` — the reply pop-up's mechanism
///   since 2026-10-12, widened from one window to all of them. A viewer of the
///   share sees them gone for the ~0.2 s of a shot.
/// - `WT_SHARE_ALL=0` puts the old behaviour back (every `.none` honoured).
enum RoomShare {
    static let on = ProcessInfo.processInfo.environment["WT_SHARE_ALL"] != "0"

    /// From `main.swift`, before the first window.
    static func install() {
        guard on,
              let a = class_getInstanceMethod(NSWindow.self, #selector(setter: NSWindow.sharingType)),
              let b = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.wt_setSharingType(_:)))
        else { return }
        method_exchangeImplementations(a, b)
    }

    /// Main thread, from `outOfShot`: every window out of the picture about to be
    /// taken (`taking`), or back in the share once it is.
    static func shot(_ taking: Bool) {
        guard on else { return }
        for w in NSApp.windows { w.sharingType = taking ? .none : .readOnly }
    }
}

extension NSWindow {
    // After the exchange `wt_setSharingType` calls the original setter.
    @objc fileprivate func wt_setSharingType(_ type: NSWindow.SharingType) {
        wt_setSharingType(type == .none && !ReplyPanel.inShot ? .readOnly : type)
    }
}
