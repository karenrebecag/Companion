import AppKit
import Metal
import MetalKit
import QuartzCore
import SwiftUI

// Wave 16o-2 (D1): the glow as a Metal shader, compiled from source at launch.
// The Metal toolchain that would build a .metallib is not installed here, and
// Metal.framework's runtime compiler needs nothing extra.

package enum ScreenGlowShader {
    /// Compiles the source and builds the pipeline; the error text when it
    /// cannot, nil when it can. Nil too with no Metal device (CI).
    package static func compileError() -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            _ = try ScreenGlowRenderer(device: device, pixelFormat: .bgra8Unorm)
            return nil
        } catch {
            return "\(error)"
        }
    }

    // The math of Incredible's "gl-waves" fragment shader, rewritten for Metal.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; };

    // One triangle that covers the screen.
    vertex VOut glow_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    struct Uniforms {
        float2 res;
        float time;
        float phase;
        float seed;
        float fill;
        float dim;
        float reach;
    };

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float vnoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), u.x),
                   mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), u.x),
                   u.y) * 2.0 - 1.0;
    }

    static float fbm(float2 p) {
        float v = 0.0;
        float a = 0.55;
        for (int i = 0; i < 3; i++) {
            v += a * vnoise(p);
            p = p * 2.03 + 17.7;
            a *= 0.5;
        }
        return v;
    }

    // Square corners: the light comes out of the edge itself.
    static float insideDistance(float2 p, float2 c) {
        float2 q = abs(p - c) - c;
        return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
    }

    static float3 palette(float t) {
        t = fract(t);
        float3 azure = float3(0.110, 0.412, 0.941);
        float3 teal = float3(0.039, 0.706, 0.686);
        float3 violet = float3(0.549, 0.275, 0.902);
        float3 cyan = float3(0.078, 0.588, 0.863);
        if (t < 0.25) return mix(azure, teal, t * 4.0);
        if (t < 0.5) return mix(teal, violet, (t - 0.25) * 4.0);
        if (t < 0.75) return mix(violet, cyan, (t - 0.5) * 4.0);
        return mix(cyan, azure, (t - 0.75) * 4.0);
    }

    // Full at the edge, easing off inward over `reach`.
    static float profile(float d, float reach) {
        float e = 1.0 - clamp(d / reach, 0.0, 1.0);
        return e * e * (3.0 - 2.0 * e);
    }

    // Two travelling sines along a diagonal and slow noise ruffle the inner tail.
    static float displacement(float2 p, constant Uniforms &u) {
        float along = p.x + p.y * 0.35;
        return sin(along * 0.016 - u.time * 1.5) * 8.0
             + sin(along * 0.041 + u.time * 0.9 + u.seed) * 5.0
             + fbm(p * 0.007 + float2(u.time * 0.08, 0.0) + u.seed) * 7.0;
    }

    fragment float4 glow_fragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        // Incredible's canvas has its origin bottom-left and the whole glow is turned
        // 180 degrees on screen; from Metal's top-left origin that is x mirrored.
        float2 p = float2(u.res.x - in.pos.x, in.pos.y);
        float2 c = u.res * 0.5;
        float a = profile(max(insideDistance(p, c), 0.0), u.reach + displacement(p, u) * 2.0);
        float ang = atan2(p.y - c.y, p.x - c.x) * 0.15915494 + 0.5;
        float3 col = palette(ang + u.phase + u.time * 0.014);
        float alpha = a * 0.5 * u.dim * u.fill;
        return float4(col * alpha, alpha);
    }
    """
}

/// Steps the fill and dim every frame, as Incredible does, and draws while there is light.
final class ScreenGlowRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var res: SIMD2<Float>
        var time: Float
        var phase: Float
        var seed: Float
        var fill: Float
        var dim: Float
        var reach: Float
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    // The shader's clock: seconds since the renderer was made, so a Float keeps it precise.
    private let born = CACurrentMediaTime()
    private var lastFrame: CFTimeInterval?
    private var envelope = ScreenGlow.Envelope.start(.off)
    private var phase = ScreenGlow.phase(random: .random(in: 0..<1))
    var animated = true
    /// Incredible starts every activation from a new palette phase.
    var mode = ScreenGlow.Mode.off {
        didSet {
            if oldValue == .off, mode != .off { phase = ScreenGlow.phase(random: .random(in: 0..<1)) }
        }
    }

    /// Throws when the compile fails: the glow is decoration, so the caller
    /// logs it and listening goes on without it.
    init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws {
        guard let queue = device.makeCommandQueue() else { throw GlowError.noQueue }
        let library = try device.makeLibrary(source: ScreenGlowShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "glow_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "glow_fragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        self.queue = queue
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    enum GlowError: Error { case noQueue }

    /// A paused view resumes from now: the gap is not a long frame. It only pauses once
    /// off and drained, where Incredible's fill has reached zero, so no trace carries over.
    func resume() {
        lastFrame = nil
        envelope = ScreenGlow.Envelope(fill: 0, dim: envelope.dim)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let elapsed = lastFrame.map { (now - $0) * 1000 } ?? 0
        lastFrame = now
        envelope = envelope.step(mode, ms: elapsed)
        // Read per frame: a window that moves to another display changes it without a SwiftUI update.
        let density = ScreenGlow.density(backing: view.window?.backingScaleFactor ?? ScreenGlow.densityCap)
        let canvas = CGSize(width: (view.bounds.width * density).rounded(),
                            height: (view.bounds.height * density).rounded())
        if view.drawableSize != canvas { view.drawableSize = canvas }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // The pass clears; below a trace of fill the frame stays clear, as Incredible's.
        if envelope.fill > 0.001 {
            var uniforms = Uniforms(
                res: SIMD2(Float(canvas.width), Float(canvas.height)),
                time: animated ? Float(now - born) : 0, phase: Float(phase), seed: ScreenGlow.seed,
                fill: Float(envelope.fill), dim: Float(envelope.dim), reach: Float(ScreenGlow.reach))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// The MTKView, paused whenever nothing is showing so an idle Mac spends no GPU.
struct ScreenGlowMetalView: NSViewRepresentable {
    let running: Bool
    let mode: ScreenGlow.Mode
    let animated: Bool
    let onFailure: (String) -> Void

    final class Coordinator { var renderer: ScreenGlowRenderer? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.framebufferOnly = true
        // The renderer sizes the drawable at Incredible's capped density; the layer stretches it.
        view.autoResizeDrawable = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        // Without Metal nothing is drawn, as Incredible draws nothing without WebGL.
        guard let device = view.device else {
            onFailure("screen glow: no Metal device")
            return view
        }
        do {
            let renderer = try ScreenGlowRenderer(device: device, pixelFormat: view.colorPixelFormat)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            onFailure("screen glow: shader failed: \(error)")
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.mode = mode
        renderer.animated = animated
        if running, view.isPaused { renderer.resume() }
        view.isPaused = !running
    }
}
