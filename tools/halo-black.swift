// A black window over the whole main screen, below the halo and above everything
// else. The halo's panel sits at `.statusBar - 1` (`CaretHalo.swift`), so
// `.floating` is comfortably under it and over the desktop.
//
// Promoted out of `docs/projectm/captures/mosaic-match-2026-09-21/tools/black.swift`
// on 2026-09-22, unchanged: Victor, on the Mosaic study — *"un efect foarte
// benefic a fost să înregistrezi efectul pe un fundal negru"*.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
w.backgroundColor = .black; w.isOpaque = true; w.level = .floating; w.ignoresMouseEvents = true
w.collectionBehavior = [.canJoinAllSpaces, .stationary]
w.orderFrontRegardless()
app.run()
