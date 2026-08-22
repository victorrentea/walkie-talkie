import Foundation
import Vision
import AppKit

// usage: ocr <image> [--fast] [--boxes]
let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first(where: { !$0.hasPrefix("--") }) else { exit(1) }
let fast = args.contains("--fast")
let boxes = args.contains("--boxes")

guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!); exit(2)
}

let t0 = Date()
let req = VNRecognizeTextRequest()
req.recognitionLevel = fast ? .fast : .accurate
req.usesLanguageCorrection = false
req.recognitionLanguages = ["en-US", "ro-RO"]
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([req])
let obs = req.results ?? []

// Group into visual lines by y, then order left-to-right — Vision returns
// observations in reading order already, but grouping keeps a row on one line.
var out: [String] = []
for o in obs {
    guard let top = o.topCandidates(1).first else { continue }
    if boxes {
        let b = o.boundingBox // normalized, origin bottom-left
        out.append(String(format: "%.3f,%.3f %@", b.minX, 1 - b.maxY, top.string))
    } else {
        out.append(top.string)
    }
}
let text = out.joined(separator: "\n")
print(text)
let el = Date().timeIntervalSince(t0)
FileHandle.standardError.write(String(format: "%@ px=%dx%d lines=%d chars=%d bytes=%d ms=%.0f\n",
    (path as NSString).lastPathComponent, cg.width, cg.height, out.count, text.count, text.utf8.count, el*1000).data(using: .utf8)!)
