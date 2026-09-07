// Renders assets/walkie-bound.png into a full .iconset, inset to Apple's icon
// grid — the reason the app's own artwork cannot be used as the tile directly.
//
// Every icon in the Dock is drawn inside a grid Apple publishes with the HIG,
// and on a 1024 canvas the shapes are: rounded rectangle **824** wide (80.5%),
// circle **790** across (77.1%) — a circle is drawn smaller than the squircle
// it sits beside, because at equal width a disc reads as the larger object.
// Measured on this Mac rather than taken from the document: Finder's and
// Chrome's bodies are 80.5% of their canvas to the pixel (the 83.6% an alpha
// bounding box reports is their drop shadow bleeding), and Victor Addons —
// circular, like this one — is 77.0–78.1%.
//
// `walkie-bound.png` fills its canvas corner to corner (measured: 100%), because
// it is *also* the menu bar's icon, where it is drawn into a 19pt box that has
// no grid and must not be inset. So the padding belongs here, at .icns
// generation, and not in the artwork: one source of truth, two framings.
//
// Written in Swift rather than as a `sips` loop because `sips` cannot pad with
// transparency — `--padColor` takes an opaque RGB triple — and not in Python
// because CoreGraphics there needs PyObjC, which /usr/bin/python3 does not have.
// The Swift toolchain is already a hard dependency of build-app.sh.

import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

/// Apple's circular slot: 790 across a 1024 canvas.
let fill = 790.0 / 1024.0

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-appicon.swift <source.png> <iconset dir>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])

for (px, name) in sizes {
    // Rounded, not floored: at 16px the difference between 12 and 13 is a
    // percent of the tile, and the whole point here is a diameter.
    let side = (Double(px) * fill).rounded()
    let inset = ((Double(px) - side) / 2).rounded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: inset, y: inset, width: side, height: side),
                from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: outDir.appendingPathComponent("\(name).png"))
}
