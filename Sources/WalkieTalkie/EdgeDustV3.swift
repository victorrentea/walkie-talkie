import AppKit
import Metal
import QuartzCore

/// **Variant 3 of the prompt's edge: smoke out of a fragment shader** (2026-11-16).
/// Victor, of the glitter: *"nu arată a dust … să imite animația dust din jurul
/// mouse-ului dar liniară"* — the dust round the mouse is Smoke (`pmhalo.cpp`,
/// `kSmoke`): wisps of every colour, additive where they meet, always dissolving.
/// And of the first edge: *"să nu se miște pe edge nimic"*. So: no fluid, no
/// particles — a procedural field, drawn each frame by one fragment shader.
///
/// - **Wisps, not fog**: a domain-warped fBm (two warps deep), kept only where it
///   rises above a threshold (the gaps) and lit along its ridges (the tendrils).
///   Two such layers, each coloured by its own slow noise through a hue wheel
///   mixed towards Smoke's *rand + 0.2* softness; added, then held under white.
/// - **Nothing travels**: the noise is 3-D and only its third coordinate moves —
///   the picture changes in time, in place. No term of any coordinate grows along
///   the edge, so there is no net drift; wisps curl, form and dissolve where they are.
/// - **In points**: the shader works in (along, away) = points along the edge and
///   points from it, so the top strip and the right one are the same smoke, features
///   ~40–90 pt. Densest on the edge, gone `reach` points in (50–95, uneven along it).
/// - **Cheap**: one pixel per point (`contentsScale` 1 — smoke has no detail a
///   Retina pixel would show), 30 frames a second from a `Timer`, nothing after `stop`.
/// - **Voice**: RMS of the fed samples, attack 80 ms / release 600 ms; raises the
///   density (×1 → ×1.7), the reach and the speed of change (×1 → ×2.4). Silence
///   is the calm base. `setIntensity(2)` eases the gain to ×1.6 over ~0.25 s.
final class EdgeDustV3: EdgeDustPicture {
    static let title = "Shader smoke"

    /// Compiled at init from this string — no `.metal` file, no bundle resource.
    /// `Tests`: `scratchpad/v3/check.swift` cuts it out of this file between the two
    /// `// SHADER` marks and renders it offscreen.
    // SHADER-BEGIN
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct U {
        float2 size;     // the strip, in points
        float  edge;     // 0 = top (the screen's edge at y = size.y), 1 = right (at x = size.x)
        float  phase;    // the time the noise has lived, in its own seconds
        float  level;    // the voice, 0…1
        float  gain;     // 1 at rest, up to 1.6 for the swell
        float  seed;     // so two strips are not the same smoke
        float  pad;
    };

    struct V { float4 pos [[position]]; float2 p; };

    // One triangle over the whole target. `p` is in points with y UP, as the
    // strip's own (unflipped) bounds: NDC y = +1 is the top row of the drawable,
    // which a CAMetalLayer shows at the top of its layer.
    vertex V edge_vert(uint vid [[vertex_id]], constant U &u [[buffer(0)]]) {
        float2 c = float2(float((vid << 1) & 2), float(vid & 2));
        V o;
        o.pos = float4(c * 2.0 - 1.0, 0.0, 1.0);
        o.p = c * u.size;
        return o;
    }

    static float3 hash3(float3 p) {
        p = float3(dot(p, float3(127.1, 311.7, 74.7)),
                   dot(p, float3(269.5, 183.3, 246.1)),
                   dot(p, float3(113.5, 271.9, 124.6)));
        return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
    }

    // Gradient noise, about −0.7…0.7.
    static float gnoise(float3 p) {
        float3 i = floor(p), f = fract(p);
        float3 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        float a = dot(hash3(i + float3(0,0,0)), f - float3(0,0,0));
        float b = dot(hash3(i + float3(1,0,0)), f - float3(1,0,0));
        float c = dot(hash3(i + float3(0,1,0)), f - float3(0,1,0));
        float d = dot(hash3(i + float3(1,1,0)), f - float3(1,1,0));
        float e = dot(hash3(i + float3(0,0,1)), f - float3(0,0,1));
        float g = dot(hash3(i + float3(1,0,1)), f - float3(1,0,1));
        float h = dot(hash3(i + float3(0,1,1)), f - float3(0,1,1));
        float k = dot(hash3(i + float3(1,1,1)), f - float3(1,1,1));
        return mix(mix(mix(a, b, w.x), mix(c, d, w.x), w.y),
                   mix(mix(e, g, w.x), mix(h, k, w.x), w.y), w.z);
    }

    // Each octave turned (so no axis shows) and living at its own pace in time.
    static float fbm(float3 p, int octaves) {
        const float2x2 turn = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
        float s = 0.0, a = 0.5;
        for (int i = 0; i < octaves; i++) {
            s += a * gnoise(p);
            p.xy = turn * p.xy * 2.03 + 17.3;
            p.z = p.z * 1.31 + 4.7;
            a *= 0.5;
        }
        return s;
    }

    static float3 hue(float h) {
        return 0.5 + 0.5 * cos(6.2831853 * (h + float3(0.0, 0.33, 0.67)));
    }

    // One layer of smoke at `q` (in feature units): its density and its colour.
    static float4 layer(float2 q, float t, float off, float thresh) {
        float3 o = float3(off, off * 1.7, off * 0.37);
        float2 w1 = float2(fbm(float3(q * 0.8, t * 0.50) + o, 3),
                           fbm(float3(q * 0.8 + 5.2, t * 0.50 + 9.1) + o, 3));
        float2 w2 = float2(fbm(float3(q * 1.5 + 2.4 * w1 + 1.7, t * 0.80) + o, 3),
                           fbm(float3(q * 1.5 + 2.4 * w1 + 8.3, t * 0.80 + 2.8) + o, 3));
        float2 r = q + 1.5 * w1 + 0.7 * w2;
        float n = fbm(float3(r, t * 0.65) + o, 4);
        // the body: only where the field is high — the rest is gaps
        float body = smoothstep(thresh, thresh + 0.50, n);
        // the tendrils: the ridges of a finer field, dragged by the same warp
        float m = fbm(float3(r * 1.25 + 3.3, t * 0.9 + 1.3) + o, 3);
        float ridge = pow(saturate(1.0 - abs(m) * 2.4), 2.0);
        float dens = body * (0.60 + 0.75 * ridge) + 0.30 * ridge * smoothstep(thresh - 0.25, thresh + 0.2, n);
        // the colour: a slow field of its own, so neighbouring wisps differ
        float h = 1.6 * fbm(float3(q * 0.42 + 0.6 * w1 + 40.0, t * 0.22) + o, 2) + off * 0.071;
        float3 col = mix(float3(0.62), hue(h), 0.86);
        return float4(col, dens);
    }

    fragment float4 edge_frag(V in [[stage_in]], constant U &u [[buffer(0)]]) {
        // (along, away): points along the edge, points from it — the same smoke
        // whichever edge this is.
        float along = mix(in.p.x, in.p.y, u.edge);
        float away  = mix(u.size.y - in.p.y, u.size.x - in.p.x, u.edge);
        float t = u.phase;
        float2 q = float2(along, away * 0.8) / 78.0 + float2(u.seed, 0.0);

        // how far in the smoke gets here: uneven along the edge, breathing slowly
        float lick = gnoise(float3(along / 120.0 + u.seed, 3.7, t * 0.35))
                   + 0.5 * gnoise(float3(along / 47.0 + u.seed, 9.2, t * 0.5));
        float reach = (96.0 + 34.0 * lick) * (1.0 + 0.18 * u.level);
        float f = saturate(1.0 - away / max(reach, 1.0));
        float fall = f * f * (3.0 - 2.0 * f);
        fall *= 0.62 + 0.38 * exp(-away / 30.0);

        float thresh = -0.06 - 0.10 * u.level;
        float4 a = layer(q, t, 0.0, thresh);
        float4 b = layer(q * 1.13 + 31.7, t * 1.1 + 5.0, 23.0, thresh + 0.03);
        float3 rgb = a.rgb * a.a + b.rgb * b.a * 0.85;
        // a glow right on the edge, of the local colour, so the line itself is lit
        rgb += mix(a.rgb, b.rgb, 0.5) * 0.30 * exp(-away / 7.0) * (0.6 + 0.4 * (a.a + b.a));

        rgb *= fall * u.gain * (0.95 + 0.55 * u.level);
        // never white: bright overlaps keep their hue
        float top = max(rgb.r, max(rgb.g, rgb.b));
        rgb *= 1.0 / max(1.0, top / 0.92);
        float alpha = saturate(max(rgb.r, max(rgb.g, rgb.b)) * 1.08);
        // premultiplied: colour added over what the alpha leaves of the desktop
        return float4(min(rgb, float3(alpha)), alpha);
    }
    """
    // SHADER-END

    struct Uniforms {
        var size: SIMD2<Float> = .zero
        var edge: Float = 0
        var phase: Float = 0
        var level: Float = 0
        var gain: Float = 1
        var seed: Float = 0
        var pad: Float = 0
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let metal = CAMetalLayer()
    private var uniforms = Uniforms()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// The loudness last fed, 0…1, and where the picture has got to following it.
    private var heard: Float = 0
    private var level: Float = 0
    private var wantedGain: Float = 1
    private var gain: Float = 1

    static let fps: Double = 30
    /// Noise-seconds per second at rest: a wisp reshapes over several seconds.
    static let restSpeed: Float = 0.06

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            Log.error("🌫️ shader smoke: no Metal device")
            return nil
        }
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "edge_vert")
            d.fragmentFunction = library.makeFunction(name: "edge_frag")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            Log.error("🌫️ shader smoke: the shader does not compile — \(error)")
            return nil
        }
        self.device = device
        self.queue = queue

        let box = strip.bounds
        metal.device = device
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.isOpaque = false
        metal.backgroundColor = nil
        metal.frame = box
        // One pixel per point: the smoke is soft, and it is a quarter of the work.
        metal.contentsScale = 1
        metal.drawableSize = CGSize(width: max(1, box.width.rounded()), height: max(1, box.height.rounded()))
        metal.magnificationFilter = .linear
        metal.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        strip.layer?.addSublayer(metal)

        uniforms.size = SIMD2(Float(box.width), Float(box.height))
        uniforms.edge = edge == .top ? 0 : 1
        // Its own smoke on each edge and on each showing; the phase starts anywhere.
        uniforms.seed = Float.random(in: 0..<50)
        uniforms.phase = Float.random(in: 0..<100)
    }

    deinit { timer?.invalidate() }

    func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        draw()
        let t = Timer(timeInterval: 1 / Self.fps, repeats: true) { [weak self] _ in self?.tick() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        heard = 0; level = 0
    }

    func feed(_ samples: [Float]) {
        guard !samples.isEmpty else { heard = 0; return }
        var sum: Float = 0
        for v in samples { sum += v * v }
        let rms = (sum / Float(samples.count)).squareRoot()
        // Speech comes in at an RMS of about 0.05–0.2 (`CaretHalo.lift`): 0.2 is "loud".
        heard = min(1, rms * 5)
    }

    func setIntensity(_ k: CGFloat) {
        wantedGain = Float(1 + 0.6 * (min(max(k, 1), 2) - 1))
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = Float(min(max(now - lastTick, 0), 0.1))
        lastTick = now
        // attack 80 ms, release 600 ms
        level += (heard - level) * (1 - exp(-dt / (heard > level ? 0.08 : 0.6)))
        gain += (wantedGain - gain) * (1 - exp(-dt / 0.12))
        // Louder: it changes faster — in place, the phase is time, not distance.
        uniforms.phase += dt * Self.restSpeed * (1 + 1.4 * level)
        draw()
    }

    private func draw() {
        uniforms.level = level
        uniforms.gain = gain
        guard let drawable = metal.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        var u = uniforms
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
