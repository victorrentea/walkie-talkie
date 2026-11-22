// Lists the guest display's modes, or switches to one: dispmode [width height [hidpi 0|1]]
import CoreGraphics
import Foundation
let d = CGMainDisplayID()
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode]) ?? []
let a = CommandLine.arguments
if a.count >= 3, let w = Int(a[1]), let h = Int(a[2]) {
    let hidpi = a.count > 3 ? a[3] == "1" : false
    guard let m = modes.first(where: { $0.width == w && $0.height == h && ($0.pixelWidth > $0.width) == hidpi }) else {
        print("no such mode"); exit(1)
    }
    var cfg: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&cfg)
    CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
    print("set:", CGCompleteDisplayConfiguration(cfg, .permanently) == .success)
} else {
    let cur = CGDisplayCopyDisplayMode(d)!
    print("current \(cur.width)x\(cur.height) px \(cur.pixelWidth)x\(cur.pixelHeight)")
    for m in modes { print("\(m.width)x\(m.height) px \(m.pixelWidth)x\(m.pixelHeight) @\(m.refreshRate)") }
}
