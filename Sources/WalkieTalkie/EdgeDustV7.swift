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
        var edge: Float = 0             // 0 top, 1 right, 2 left (the ⚡ question's marks), 3 bottom (the caret's pins)
        var level: Float = 0            // his voice, 0…1
        var intensity: Float = 1        // 1 at rest … 2
        var scale: Float = 2            // pixels per point
        var seed: Float = 0
        var stop: Float = 1e9           // the time nothing new is born after (`drain`)
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
        uniforms.edge = edge == .top ? 0 : edge == .right ? 1 : edge == .left ? 2 : 3
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
        uniforms.stop = 1e9
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

    /// Nothing new from now on; what is on its way finishes its path (2026-11-21).
    /// The fire's field leaves the edge at 52 pt/s and is gone past ~1.5 × its height:
    /// ~2.6 s. A question mark runs its life out: up to 6.8 s, most far shorter. A caret
    /// pin crumbles where it is over ~2.4 s (a paste is quick; it does not walk on).
    func drain() -> TimeInterval {
        uniforms.stop = Float(CACurrentMediaTime() - began)
        return uniforms.edge > 2.5 ? 2.8 : uniforms.edge > 1.5 ? 6.8 : 2.6
    }

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
    float edge;       // 0 top, 1 right, 2 left: question marks, 3 bottom: map pins
    float level;      // voice 0..1
    float intensity;  // 1..2
    float scale;      // pixels per point
    float seed;
    float stop;       // nothing born after this time
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

static float v7_seg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// A question mark standing upright in its own points (x across, y up, the dot's foot
// near y = 0): the signed distance to its stroke, negative inside. Its cut varies like a
// typeface's (2026-11-20): `R` the hook's radius, `hw` the stroke's half-width, `open`
// where the hook's free end stops. R 15, hw 4.2, 170° is the first one drawn (2026-11-19),
// ~62 tall. Never slanted (Victor: *"nu mai de înclinat, doar schimbă fontul"*).
static float v7_qmark(float2 g, float R, float hw, float open) {
    float2 c = float2(0.0, 34.0 + R);
    float2 v = g - c;
    float ang = atan2(v.y, v.x);
    // The hook: from its free end on the left, over the top and down the right side to the bottom (−90°).
    float arc;
    if (ang >= -1.5708 && ang <= open) arc = abs(length(v) - R);
    else arc = min(length(g - (c + R * float2(cos(open), sin(open)))), length(g - (c + float2(0.0, -R))));
    float stem = v7_seg(g, float2(0.0, 34.0), float2(0.0, 25.0));
    // The dot well apart from the stem, or the grains run them into one line.
    float dotd = length(g - float2(0.0, 7.0)) - hw * 1.1;
    return min(min(arc, stem) - hw, dotd);
}

// One mark: the one of cell `cell` (S points long), its density at (a, d).
//
// **A journey, not a swing** (2026-11-20, second pass — Victor: *"din pixelii care apar în
// partea stângă să se alcătuiască semne de întrebare … și care apoi fac fade out, dispărând
// punctele lor, pe măsură ce se află pe centru"*, all gone by ~240 pt in). Each cell runs lives
// one after another on its own clock (`life` 4.6–6.8 s): a mark is born at the edge, a third of
// it past it, out of loose dust; it forms while it walks in (first quarter of its life), then
// loses its grains one by one as it goes on (its density falls, so the grains drop out by their
// own thresholds, never a uniform alpha), gone before `gone` points in. The next life of the
// same cell is a new mark: its own cut, size and place along the edge.
static float v7_mark(float cell, float S, float a, float d, float t, float level, float k, float seed, float f, float stop) {
    const float pace = 1.15;
    const float gone = 232.0;
    float c1 = v7_h(float2(cell, 1.9)), c2 = v7_h(float2(cell, 4.4));
    float life = 4.6 + 2.2 * c2;
    float clock = t / life + c1 + seed * 0.13;
    float n = floor(clock), pp = clock - n;          // which life, how far through it
    // Born after the edge was told to go: never drawn (the ones already walking finish).
    if ((n - c1 - seed * 0.13) * life > stop) return 0.0;
    float2 id = float2(cell, n * 1.37 + 0.5);
    float h1 = v7_h(id + float2(0.0, 3.3)), h2 = v7_h(id + float2(0.0, 8.1)), h3 = v7_h(id + float2(0.0, 5.7));
    // Its cut, one of five, like five typefaces: the first one drawn, a heavy round, a
    // hairline, a condensed, a wide light one with the hook open further.
    int cut = int(floor(v7_h(id + float2(0.0, 2.9)) * 5.0));
    const float cR[5]    = { 15.0, 16.5, 14.0, 12.5, 17.0 };
    const float cHw[5]   = { 4.2,  5.8,  2.7,  3.6,  3.1 };
    const float cOpen[5] = { 2.97, 3.05, 2.9,  2.7,  3.3 };
    float R = cR[cut], hw = cHw[cut], open = cOpen[cut];
    float sc = mix(1.45, 2.35, h2) * (1.0 + 0.12 * level + 0.12 * k);
    float halfW = (R + hw) * sc;
    float top = 34.0 + 2.0 * R + hw;
    float mid = (7.0 - 1.1 * hw + top) * 0.5;
    float bob = sin(pace * t * (0.30 + 0.20 * h3) + h1 * 6.2832) * 8.0;
    // In from the edge, easing out: its axis from a third of it hidden to `gone` − its half.
    float walk = 1.0 - (1.0 - pp) * (1.0 - pp) * 0.35 - 0.65 * (1.0 - pp);
    float cx = mix(-0.35 * halfW, gone - halfW * 0.9, walk);
    float la = a - (cell + 0.5) * S + (h1 - 0.5) * 30.0 + bob;
    // Upright: the glyph's x runs away from the edge, its y up the screen (a runs down).
    float2 g = float2((d - cx) / sc, mid - la / sc);
    // A little breath in the strokes, so the dots never sit still.
    g += (float2(v7_n(float2(a / 11.0, t * 0.7)), v7_n(float2(d / 11.0 + 5.0, t * 0.7))) - 0.5) * 3.0;
    float sd = v7_qmark(g, R, hw, open) * sc;
    float shape = 1.0 - smoothstep(-1.5, 2.0, sd);
    float near = 1.0 - smoothstep(0.0, 12.0, sd);
    float form = smoothstep(0.0, 0.26, pp);
    // Its grains go from the middle of its life, the last of them before `gone`.
    float fade = (1.0 - smoothstep(0.30, 0.92, pp)) * (1.0 - smoothstep(gone - 90.0, gone, d));
    float formed = shape * (0.80 + 0.30 * f);
    float loose = near * smoothstep(0.55, 0.85, f) * 0.55;
    return mix(loose, max(formed, loose * 0.5), form) * fade;
}

// **The ⚡ question's edge** (2026-11-19; upright, larger, walking in since 2026-11-20): the
// left edge, its grains drawing question marks standing upright, one every 170 pt along
// the edge, each in one of five cuts and its own size (~90–175 pt tall). Each is born of the
// dust at the edge, walks in while it forms, and loses its grains on the way, gone by ~230 pt;
// then the next one. The voice makes them a little larger. A thin bed of dust runs along the
// edge under them.
static float v7_marks(float a, float d, float t, float level, float k, float seed, float stop) {
    // A tall mark spills past its cell: its neighbour on the nearer side is drawn too.
    const float S = 170.0;
    float cellA = floor(a / S);
    float other = (a - cellA * S) < S * 0.5 ? cellA - 1.0 : cellA + 1.0;
    float f = v7_fbm(float2(a / 15.0, (d - 14.0 * t) / 26.0));
    float dens = max(v7_mark(cellA, S, a, d, t, level, k, seed, f, stop), v7_mark(other, S, a, d, t, level, k, seed, f, stop));
    float bed = (1.0 - smoothstep(0.0, 14.0, d)) * (0.20 + 0.45 * f) * (0.8 + 0.4 * level);
    // The bed's dust lifts off the edge like the fire's (14 pt/s, its own drift).
    bed *= smoothstep(-4.0, 4.0, d - max(t - stop, 0.0) * 14.0);
    return clamp(max(dens, bed), 0.0, 1.0);
}

// iq's exact signed distance to a triangle.
static float v7_tri(float2 p, float2 p0, float2 p1, float2 p2) {
    float2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    float2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// **The caret's map pin**, `Glyphs.mapPinShape` in a 1-tall box (x across, y up, the tip
// at the origin): a head of radius 0.348 on the tangents to the tip, a hole of 0.196 in
// it. Negative inside the red, positive in the hole and outside.
static float v7_pin(float2 g) {
    const float R = 0.348;
    float2 c = float2(0.0, 1.0 - R);
    float phi = acos(R / c.y);
    float2 tr = c + R * float2(cos(-1.5708 + phi), sin(-1.5708 + phi));
    float body = min(length(g - c) - R, v7_tri(g, float2(0.0, 0.0), tr, float2(-tr.x, tr.y)));
    return max(body, -(length(g - c) - 0.196));
}

// One pin: the one of cell `cell` (S points long), its density at (a, d).
//
// **From time to time the dust makes the caret's pin** (2026-11-22, Victor: *"când vine de
// jos, mi-ar plăcea ca punctele care vin să alcătuiască, din când în când, forme care seamănă
// cu pinul acela roșu … ca să înțeleg că e promptare pe caret"*). The question marks' journey
// (`v7_mark`), upright with its tip down: born at the edge with a third of it below it, it
// forms while it rises, then loses its grains on the way, gone by `gone`. Not every life of a
// cell is a pin — about three in five — so they come now and then, never in a row. A life
// already under way when the edge comes up is drawn only if it is still forming: the first
// pins rise from the edge, none is found standing in the middle. Drained, a pin that is out
// crumbles where it stands (`stop`): a paste lands in a second, it does not wait for them.
static float v7_pin_life(float cell, float S, float a, float d, float t, float level, float k, float seed, float f, float stop) {
    const float gone = 232.0;
    float c1 = v7_h(float2(cell, 2.3)), c2 = v7_h(float2(cell, 6.1));
    float life = 5.0 + 2.0 * c2;
    float clock = t / life + c1 + seed * 0.11;
    float n = floor(clock), pp = clock - n;
    float born = (n - c1 - seed * 0.11) * life;
    if (born > stop || born < -0.35 * life) return 0.0;
    float2 id = float2(cell, n * 1.37 + 0.5);
    if (v7_h(id + float2(0.0, 7.7)) > 0.6) return 0.0;
    float h1 = v7_h(id + float2(0.0, 3.3)), h2 = v7_h(id + float2(0.0, 8.1)), h3 = v7_h(id + float2(0.0, 5.7));
    float H = mix(95.0, 140.0, h2) * (1.0 + 0.10 * level + 0.12 * k);
    float walk = 1.0 - (1.0 - pp) * (1.0 - pp) * 0.35 - 0.65 * (1.0 - pp);
    float tip = mix(-0.35 * H, gone - 1.02 * H, walk);
    float sway = sin(t * (0.35 + 0.20 * h3) + h1 * 6.2832) * 6.0;
    float la = a - (cell + 0.5) * S - (h1 - 0.5) * 80.0 - sway;
    float2 g = float2(la, d - tip);
    g += (float2(v7_n(float2(a / 11.0, t * 0.7)), v7_n(float2(d / 11.0 + 5.0, t * 0.7))) - 0.5) * 3.0;
    float sd = v7_pin(g / H) * H;
    float shape = 1.0 - smoothstep(-1.5, 2.0, sd);
    float near = 1.0 - smoothstep(0.0, 12.0, sd);
    float form = smoothstep(0.0, 0.26, pp);
    float fade = (1.0 - smoothstep(0.34, 0.92, pp)) * (1.0 - smoothstep(gone - 70.0, gone, d));
    fade *= 1.0 - smoothstep(stop + 0.2, stop + 2.4, t);
    float formed = shape * (0.85 + 0.30 * f);
    float loose = near * smoothstep(0.55, 0.85, f) * 0.55;
    return mix(loose, max(formed, loose * 0.5), form) * fade;
}

static float v7_pins(float a, float d, float t, float level, float k, float seed, float stop) {
    const float S = 320.0;
    float f = v7_fbm(float2(a / 15.0, (d - 30.0 * t) / 26.0));
    return clamp(v7_pin_life(floor(a / S), S, a, d, t, level, k, seed, f, stop), 0.0, 1.0);
}

fragment float4 v7_fragment(V7Out in [[stage_in]], constant V7U &u [[buffer(0)]]) {
    // Points; origin at the top left of what is seen, y down.
    float2 p = in.pos.xy / u.scale;
    float a, d;                       // along the edge, away from it
    bool marks = u.edge > 1.5 && u.edge < 2.5;
    bool pins = u.edge > 2.5;
    if (u.edge < 0.5) { a = p.x; d = p.y; }
    else if (pins) { a = p.x; d = u.size.y - p.y; }
    else if (!marks) { a = p.y; d = u.size.x - p.x; } else { a = p.y; d = p.x; }
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
    float h = (14.0 + 62.0 * tongue * tongue + 9.0 * n2) * grow * 0.8;   // −30 %, then +15 % with everything else (Victor, 2026-11-16)

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
    // **Drained** (2026-11-21, Victor: *"să nu facă fade, ci pur și simplu să nu mai vină
    // altele, iar cele care au venit deja să-și continue traiectoria până dispar"*): what
    // the edge gave off after `stop` is not there, so the fire lifts off its base at the
    // field's own 52 pt/s and dies out at its tips as it always does.
    dens *= smoothstep(-6.0, 6.0, d - max(t - u.stop, 0.0) * 52.0);
    if (marks) { dens = v7_marks(a, d, t, u.level, k, u.seed, u.stop); h = 70.0; }
    // The caret's bottom edge: the same fire, and now and then a red pin made of its grains.
    // Its strip is deeper (the pins walk to ~230 pt), so the fire's own fade — the mask's on
    // the 110 pt edges, from 30 % of the depth — is drawn here (`fireFade`).
    float pinW = 0.0, fireFade = 1.0;
    if (pins) {
        float pd = v7_pins(a, d, t, u.level, k, u.seed, u.stop);
        pinW = smoothstep(0.08, 0.40, pd);
        fireFade = 1.0 - smoothstep(33.0, 110.0, d);
        dens = max(dens * fireFade, pd);
    }

    // Each tongue its own hue; paler at the base, deeper at the tip.
    float hue = v7_n(float2(as / 150.0, t * 0.05 + 11.0)) * 2.0 + u.seed;
    float heat = exp(-d / (0.30 * h + 4.0));
    // Finer, slower grains for the marks: a 9 pt stroke has to read as a line of dots.
    float fine = marks ? 0.62 : 1.0;
    float slow = marks ? 0.25 : 1.0;

    float3 sum = float3(0.0);
    const float cell[3]  = { 4.5, 6.2, 8.6 };
    const float speed[3] = { 40.0, 29.0, 19.0 };
    const float gain[3]  = { 1.53, 1.8, 1.44 };
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 q = float2(a, d - speed[i] * slow * t) / (cell[i] * fine) + fi * 31.7;
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
        // A pin's grains are its red (`NSColor.systemRed`), a touch lighter or deeper each.
        col = mix(col, mix(float3(1.0, 0.20, 0.17), float3(1.0, 0.42, 0.34), r4), pinW);
        col = mix(col * col * 0.95, mix(col, float3(1.0), 0.30), heat);
        sum += col * dotv * lit * twinkle * gain[i];
    }

    // A faint smooth glow under the dust, to bind it.
    float3 base = mix(v7_palette(hue), float3(1.0, 0.20, 0.17), pinW);
    base = mix(base * base, mix(base, float3(1.0), 0.2), heat);
    float3 rgb = sum * 0.95 + base * dens * dens * 0.12;
    rgb = 1.0 - exp(-rgb * 1.15);
    // Premultiplied. Alpha close to the grain's own brightness: on a dark desk that
    // is as good as additive, on a white page the grain keeps its colour instead of
    // washing out to white (at 0.5 it was invisible there).
    float alpha = clamp(max(rgb.r, max(rgb.g, rgb.b)) * 0.85, 0.0, 1.0);
    // The bottom's fire fades out with the depth as the mask does on the other edges.
    float keep = pins ? max(1.0 - smoothstep(0.0, 1.0, (d - 33.0) / 77.0), pinW) : 1.0;
    return float4(rgb, alpha) * keep;
}
"""
// SHADER-END
