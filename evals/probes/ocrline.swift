import Foundation
import Vision
import AppKit

// usage: ocrline <image> <x> <y>   (pixels, top-left origin, in that image)
let a = Array(CommandLine.arguments.dropFirst())
guard a.count >= 3, let px = Double(a[1]), let py = Double(a[2]),
      let img = NSImage(contentsOfFile: a[0]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
let W = Double(cg.width), H = Double(cg.height)
let nx = px / W, ny = py / H     // top-left normalized

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
let t0 = Date()
try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
let obs = req.results ?? []

struct Hit { let s: String; let d: Double; let box: CGRect }
var hits: [Hit] = []
for o in obs {
    guard let c = o.topCandidates(1).first else { continue }
    let b = o.boundingBox
    let r = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height) // top-left
    // distance from point to the row's rectangle, y weighted heavier: a line is wide
    let dy = max(0, max(r.minY - ny, ny - r.maxY))
    let dx = max(0, max(r.minX - nx, nx - r.maxX))
    hits.append(Hit(s: c.string, d: dy * 3 + dx, box: r))
}
hits.sort { $0.d < $1.d }
for h in hits.prefix(3) {
    print(String(format: "%.4f  %@", h.d, h.s))
}
FileHandle.standardError.write(String(format: "ms=%.0f best=%d chars\n", Date().timeIntervalSince(t0)*1000, hits.first?.s.count ?? 0).data(using: .utf8)!)
