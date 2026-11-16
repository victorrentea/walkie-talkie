import AppKit
import Metal
import MetalKit

/// **Variant 7 of the prompt's edge: a fire whose substance is dust**, drawn by one
/// fragment shader (Victor, 2026-11-16: *"un efect tip foc dar cu praf"*).
///
/// The screen's edge is the base of the fire. A fire field — fBm noise carried AWAY
/// from the edge, under a height that a slow noise along the edge raises and lowers
/// into separate tongues — is never shown as a gradient: it is the *density* of
/// three sheets of grains (cells of 2.6 / 3.6 / 5 pt, one soft dot each, with its
/// own place, size and twinkle), every sheet sliding away from the edge at its own
/// speed. A grain is lit where the density is above the cell's own threshold, so the
/// core is packed with specks and the tips break up into single flying grains. A
/// smooth glow of ~12 % binds it. Nothing scrolls along the edge: the tongues stand
/// where they are and only rise, fall and sway.
///
/// - **Colour**: a slow noise along the edge picks each tongue's hue from a ring of
///   five (rose, amber, green, sky, violet); paler at the base, deeper at the tips,
///   never white.
/// - **Points, not pixels**: the shader works in points (`size`, `scale`), with
///   `a` along the edge and `d` away from it, so the two strips have the same grains
///   and the same tongues (~40–80 pt tall at rest, ~50–90 pt wide).
/// - **Which side is the edge.** `MTKView`'s drawable is shown upright whatever the
///   view's flippedness: the fragment's `position` has its origin at the TOP LEFT of
///   what is seen, y down. So for `.top` the edge (`bounds.maxY`) is `position.y = 0`
///   and `d = y`; for `.right` the edge (`bounds.maxX`) is the last column and
///   `d = width − x`. No NDC or texture flip is involved: the triangle only covers
///   the target, the picture is computed from `position`.
/// - **Backing scale** (2× on the Retina): a 2.6 pt grain is 5 px there, a soft dot;
///   at 1× it would be a 2–3 px block. A top strip is 3456 × 220 px, a few ms of GPU
///   at 30 fps.
/// - **Voice**: the RMS of `feed`, attack ~80 ms, release ~600 ms, makes the tongues
///   taller (up to +80 %) and the dust denser. Silence is a low calm fire, never
///   nothing. `setIntensity(2)`: taller and denser again, eased over ~150 ms.
final class EdgeDustV7: NSObject, EdgeDustPicture, MTKViewDelegate {
    static let title = "Shader fire dust"

    private struct Uniforms {
        var size = SIMD2<Float>(0, 0)   // the strip, in points
        var time: Float = 0
        var edge: Float = 0             // 0 top, 1 right
        var level: Float = 0            // his voice, 0…1
        var intensity: Float = 1        // 1 at rest … 2
        var scale: Float = 2            // pixels per point
        var seed: Float = 0
    }

    private let view: MTKView
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var uniforms = Uniforms()
    private var began = CACurrentMediaTime()
    private var lastFrame = CACurrentMediaTime()
    private var level: Float = 0
    private var wantedIntensity: Float = 1
    private var running = false

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            Log.error("🌫️ shader fire dust: no Metal device")
            return nil
        }
        let format = MTLPixelFormat.bgra8Unorm
        do {
            let library = try device.makeLibrary(source: edgeDustV7Shader, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "v7_vertex")
            d.fragmentFunction = library.makeFunction(name: "v7_fragment")
            d.colorAttachments[0].pixelFormat = format
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            Log.error("🌫️ shader fire dust: the shader does not compile — \(error)")
            return nil
        }
        self.queue = queue
        view = MTKView(frame: strip.bounds, device: device)
        uniforms.edge = edge == .top ? 0 : 1
        uniforms.seed = Float.random(in: 0..<64)
        super.init()
        view.colorPixelFormat = format
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        (view.layer as? CAMetalLayer)?.isOpaque = false
        view.autoresizingMask = [.width, .height]
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.delegate = self
        strip.addSubview(view)
    }

    func start() {
        guard !running else { return }
        running = true
        // A fresh clock for every sentence: the shader's `time` stays small, and a
        // `float` keeps its sub-point precision in `d − speed·time`.
        began = CACurrentMediaTime()
        lastFrame = began
        uniforms.intensity = 1
        view.isPaused = false
    }

    func stop() {
        running = false
        view.isPaused = true
        view.releaseDrawables()
    }

    func feed(_ samples: [Float]) {
        var sum: Float = 0
        for v in samples { sum += v * v }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        let want = min(max((rms - 0.012) * 7, 0), 1)
        // 30 calls a second: attack ~80 ms, release ~600 ms.
        let dt: Float = 1.0 / 30
        level += (want - level) * (1 - exp(-dt / (want > level ? 0.08 : 0.6)))
    }

    func setIntensity(_ k: CGFloat) { wantedIntensity = Float(min(max(k, 0), 3)) }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard running, view.bounds.width > 0, view.drawableSize.width > 0,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastFrame, 0), 0.1))
        lastFrame = now
        uniforms.intensity += (wantedIntensity - uniforms.intensity) * (1 - exp(-dt / 0.15))
        uniforms.level = level
        uniforms.time = Float(now - began)
        uniforms.size = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        uniforms.scale = Float(view.drawableSize.width / view.bounds.width)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// The whole picture. Compiled at init; the offline check (a script that renders it
/// to PNGs) reads it from this file between the two marker lines — keep them.
// SHADER-BEGIN
private let edgeDustV7Shader = """
#include <metal_stdlib>
using namespace metal;

struct V7U {
    float2 size;      // strip, points
    float time;
    float edge;       // 0 top, 1 right
    float level;      // voice 0..1
    float intensity;  // 1..2
    float scale;      // pixels per point
    float seed;
};

struct V7Out { float4 pos [[position]]; };

vertex V7Out v7_vertex(uint vid [[vertex_id]]) {
    V7Out o;
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

static float v7_h(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float v7_n(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(v7_h(i), v7_h(i + float2(1, 0)), f.x),
               mix(v7_h(i + float2(0, 1)), v7_h(i + float2(1, 1)), f.x), f.y);
}

static float v7_fbm(float2 p) {
    float s = 0.0, w = 0.5;
    for (int i = 0; i < 3; i++) { s += w * v7_n(p); p = p * 2.03 + 17.1; w *= 0.5; }
    return s / 0.875;
}

// A ring of five soft, saturated hues; x in turns.
static float3 v7_palette(float x) {
    const float3 c[5] = {
        float3(1.00, 0.40, 0.62),   // rose
        float3(1.00, 0.70, 0.28),   // amber
        float3(0.42, 0.92, 0.52),   // green
        float3(0.36, 0.72, 1.00),   // sky
        float3(0.70, 0.48, 1.00)    // violet
    };
    float k = fract(x) * 5.0;
    int i = int(floor(k));
    float f = k - float(i);
    f = f * f * (3.0 - 2.0 * f);
    return mix(c[i % 5], c[(i + 1) % 5], f);
}

fragment float4 v7_fragment(V7Out in [[stage_in]], constant V7U &u [[buffer(0)]]) {
    // Points; origin at the top left of what is seen, y down.
    float2 p = in.pos.xy / u.scale;
    float a, d;                       // along the edge, away from it
    if (u.edge < 0.5) { a = p.x; d = p.y; } else { a = p.y; d = u.size.x - p.x; }
    a += u.seed * 97.0;
    float t = u.time;
    float k = clamp(u.intensity - 1.0, 0.0, 1.5);
    float grow = 1.0 + 0.8 * u.level + 0.6 * k;

    // The tongues sway a little, more the further from their base.
    float sway = (v7_n(float2(a / 60.0, d / 38.0 - t * 0.6)) - 0.5) * 34.0 * smoothstep(0.0, 60.0, d);
    float as = a + sway;

    // How far the fire reaches here: a slow noise along the edge, breathing in time.
    float n = v7_n(float2(as / 36.0, t * 0.42 + 7.0));
    float n2 = v7_n(float2(as / 13.0, t * 1.1 + 3.0));
    float tongue = smoothstep(0.18, 0.86, n);
    float h = (14.0 + 62.0 * tongue * tongue + 9.0 * n2) * grow;

    // The fire field, carried away from the edge.
    float f = v7_fbm(float2(as / 17.0, (d - 52.0 * t) / 34.0));
    float rel = d / h;
    // Full at the base, eaten by the field towards the tip: a ragged, wispy outline.
    float core = 1.0 - smoothstep(0.0, 1.0, rel);
    float dens = clamp(core * (0.50 + 1.0 * f) + (f - 0.52) * 1.5 * smoothstep(0.1, 0.7, rel) * (1.0 - smoothstep(0.9, 1.5, rel)), 0.0, 1.0);
    // Embers that have left the flame: thin, patchy, further out.
    float stray = smoothstep(0.55, 0.85, f) * (0.3 + 0.7 * tongue) * (1.0 - smoothstep(0.9, 2.4, rel)) * 0.30;
    dens = max(dens, stray);
    dens *= 0.80 + 0.20 * u.level + 0.25 * k;

    // Each tongue its own hue; paler at the base, deeper at the tip.
    float hue = v7_n(float2(as / 150.0, t * 0.05 + 11.0)) * 2.0 + u.seed;
    float heat = exp(-d / (0.30 * h + 4.0));

    float3 sum = float3(0.0);
    const float cell[3]  = { 2.6, 3.6, 5.0 };
    const float speed[3] = { 40.0, 29.0, 19.0 };
    const float gain[3]  = { 1.02, 1.2, 0.96 };
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 q = float2(a, d - speed[i] * t) / cell[i] + fi * 31.7;
        float row = floor(q.y);
        // Each row of grains drifts sideways by a fraction of a cell, at its own pace.
        float r0 = v7_h(float2(row, 5.0 + fi));
        q.x += 0.45 * sin(t * (0.6 + 1.3 * r0) + r0 * 6.2832) + r0 * 13.0;
        float2 id = floor(q), fr = fract(q);
        float r1 = v7_h(id + float2(1.7, 9.2) * (fi + 1.0));
        float r2 = v7_h(id + float2(8.3, 2.8) * (fi + 1.0));
        float r3 = v7_h(id + float2(4.1, 6.6) * (fi + 1.0));
        float r4 = v7_h(id + float2(3.9, 7.4) * (fi + 1.0));
        float rad = mix(0.20, 0.40, r4);
        float2 c = 0.5 + (float2(r2, r3) - 0.5) * 2.0 * (0.5 - rad);
        float dotv = smoothstep(rad, rad * 0.25, length(fr - c));
        // Lit where the fire is denser than this grain's own threshold.
        float lit = smoothstep(r1 * 1.3, r1 * 1.3 + 0.12, dens);
        float twinkle = 0.55 + 0.45 * sin(t * (2.5 + 5.0 * r2) + r3 * 6.2832);
        float3 col = v7_palette(hue + (r4 - 0.5) * 0.16);
        col = mix(col * col * 0.95, mix(col, float3(1.0), 0.30), heat);
        sum += col * dotv * lit * twinkle * gain[i];
    }

    // A faint smooth glow under the dust, to bind it.
    float3 base = v7_palette(hue);
    base = mix(base * base, mix(base, float3(1.0), 0.2), heat);
    float3 rgb = sum * 0.95 + base * dens * dens * 0.12;
    rgb = 1.0 - exp(-rgb * 1.15);
    // Premultiplied. Alpha close to the grain's own brightness: on a dark desk that
    // is as good as additive, on a white page the grain keeps its colour instead of
    // washing out to white (at 0.5 it was invisible there).
    float alpha = clamp(max(rgb.r, max(rgb.g, rgb.b)) * 0.85, 0.0, 1.0);
    return float4(rgb, alpha);
}
"""
// SHADER-END
