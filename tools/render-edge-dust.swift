// Renders `EdgeDustV7`'s shader offline, to look at a strip without the app.
//
//   swift tools/render-edge-dust.swift <edge 0|1|2> <out.png> [level 0…1] [times…]
//
// Edge 0 = top, 1 = right, 2 = left (the ⚡ question's marks). The strip is drawn
// at 2× on a dark desk, one panel per time, side by side (a top strip: stacked).
// Reads the shader from Sources/WalkieTalkie/EdgeDustV7.swift between the
// `SHADER-BEGIN` / `SHADER-END` markers, so it always draws what the app draws.
import AppKit
import Metal

let args = CommandLine.arguments
let edge = Float(args.count > 1 ? args[1] : "2") ?? 2
let out = args.count > 2 ? args[2] : "/tmp/edge-dust.png"
let level = Float(args.count > 3 ? args[3] : "0.3") ?? 0.3
let times = args.count > 4 ? args[4...].compactMap(Float.init) : [1, 4, 8, 13]

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let file = try! String(contentsOf: here.appendingPathComponent("Sources/WalkieTalkie/EdgeDustV7.swift"), encoding: .utf8)
guard let b = file.range(of: "// SHADER-BEGIN"), let e = file.range(of: "// SHADER-END"),
      let open = file.range(of: "\"\"\"\n", range: b.upperBound..<e.lowerBound),
      let close = file.range(of: "\n\"\"\"", options: .backwards, range: open.upperBound..<e.lowerBound) else {
    fatalError("no shader between the markers")
}
let source = String(file[open.upperBound..<close.lowerBound])

struct U { var size: SIMD2<Float>; var time: Float; var edge: Float; var level: Float; var intensity: Float; var scale: Float; var seed: Float }

let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: source, options: nil)
let d = MTLRenderPipelineDescriptor()
d.vertexFunction = library.makeFunction(name: "v7_vertex")
d.fragmentFunction = library.makeFunction(name: "v7_fragment")
d.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try! device.makeRenderPipelineState(descriptor: d)
let queue = device.makeCommandQueue()!

let scale: Float = 2
let size: SIMD2<Float> = edge < 0.5 ? [900, 110] : edge < 1.5 ? [110, 700] : [240, 700]
let w = Int(size.x * scale), h = Int(size.y * scale)

func render(_ t: Float) -> [UInt8] {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .shared
    let tex = device.makeTexture(descriptor: td)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = tex
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    var u = U(size: size, time: t, edge: edge, level: level, intensity: 1, scale: scale, seed: 3.7)
    let buf = queue.makeCommandBuffer()!
    let enc = buf.makeRenderCommandEncoder(descriptor: pass)!
    enc.setRenderPipelineState(pipeline)
    enc.setFragmentBytes(&u, length: MemoryLayout<U>.stride, index: 0)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.endEncoding()
    buf.commit(); buf.waitUntilCompleted()
    var px = [UInt8](repeating: 0, count: w * h * 4)
    tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
    return px
}

// Premultiplied BGRA over a dark desk (#1c1c1e), panels side by side with a gap.
let gap = 24, bg: [Int] = [0x1e, 0x1c, 0x1c]
let horizontal = edge >= 0.5
let W = horizontal ? times.count * w + (times.count - 1) * gap : w
let H = horizontal ? h : times.count * h + (times.count - 1) * gap
var canvas = [UInt8](repeating: 0, count: W * H * 4)
for i in 0..<(W * H) { canvas[i * 4] = UInt8(bg[0]); canvas[i * 4 + 1] = UInt8(bg[1]); canvas[i * 4 + 2] = UInt8(bg[2]); canvas[i * 4 + 3] = 255 }
for (n, t) in times.enumerated() {
    let px = render(t)
    let ox = horizontal ? n * (w + gap) : 0, oy = horizontal ? 0 : n * (h + gap)
    for y in 0..<h { for x in 0..<w {
        let s = (y * w + x) * 4, o = ((y + oy) * W + (x + ox)) * 4
        let a = Int(px[s + 3])
        for c in 0..<3 { canvas[o + c] = UInt8(min(255, Int(px[s + c]) + bg[c] * (255 - a) / 255)) }
    } }
}
let ctx = CGContext(data: &canvas, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out, W, "x", H)
