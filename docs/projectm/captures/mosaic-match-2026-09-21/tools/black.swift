// A black window over the whole main screen, below the halo (statusBar-1) and above everything else.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main!
let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
w.backgroundColor = .black; w.isOpaque = true; w.level = .floating; w.ignoresMouseEvents = true
w.collectionBehavior = [.canJoinAllSpaces, .stationary]
w.orderFrontRegardless()
app.run()
