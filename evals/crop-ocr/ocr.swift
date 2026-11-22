import Foundation
import Vision
import ImageIO

// Apple Vision OCR over a list of images, one JSON line per image and config.
//   swiftc -O evals/crop-ocr/ocr.swift -o /tmp/crop-ocr
//   /tmp/crop-ocr --langs                 # what this macOS recognises
//   /tmp/crop-ocr a.jpg b.jpg … > out/ocr.jsonl
// Configs: accurate (no language correction), accurate+lc (with), fast.
// The first request of a process loads the model (~100s of ms): one warm-up run
// per config on the first image is thrown away, as the app's would be after its first crop.

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

struct Config { let name: String; let level: VNRequestTextRecognitionLevel; let lc: Bool }
let configs = [Config(name: "accurate", level: .accurate, lc: false),
               Config(name: "accurate+lc", level: .accurate, lc: true),
               Config(name: "fast", level: .fast, lc: false)]

func run(_ cg: CGImage, _ c: Config) -> (ms: Double, lines: [[String: Any]]) {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = c.level
    req.usesLanguageCorrection = c.lc
    req.recognitionLanguages = ["en-US", "ro-RO"]
    let t0 = DispatchTime.now().uptimeNanoseconds
    try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    var lines: [[String: Any]] = []
    for o in req.results ?? [] {
        guard let top = o.topCandidates(1).first else { continue }
        let b = o.boundingBox   // normalised, origin bottom-left
        lines.append(["t": top.string, "c": Double(top.confidence),
                      "x": Double(b.minX), "y": Double(1 - b.maxY), "w": Double(b.width), "h": Double(b.height)])
    }
    return (ms, lines)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--langs" {
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
        let r = VNRecognizeTextRequest(); r.recognitionLevel = level
        let langs = (try? r.supportedRecognitionLanguages()) ?? []
        print(level == .accurate ? "accurate:" : "fast:", langs.joined(separator: " "))
    }
    exit(0)
}
var warmed = false
for path in args {
    let t0 = DispatchTime.now().uptimeNanoseconds
    guard let cg = load(path) else { FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!); continue }
    let decodeMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    if !warmed { for c in configs { let w = run(cg, c); FileHandle.standardError.write("warm-up \(c.name): \(Int(w.ms)) ms\n".data(using: .utf8)!) }; warmed = true }
    for c in configs {
        let r = run(cg, c)
        let row: [String: Any] = ["file": path, "config": c.name, "ms": r.ms, "decodeMs": decodeMs,
                                  "w": cg.width, "h": cg.height, "lines": r.lines]
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.withoutEscapingSlashes])
        print(String(data: data, encoding: .utf8)!)
    }
}
