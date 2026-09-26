import AppKit
import Metal
import MetalKit
import QuartzCore
import SwiftUI

// Wave 16o-2 (D1): the glow as a Metal shader, compiled from source at launch.
// The Metal toolchain that would build a .metallib is not installed here, and
// Metal.framework's runtime compiler needs nothing extra.

public enum ScreenGlowShader {
    /// Compiles the source and builds the pipeline; the error text when it
    /// cannot, nil when it can. Nil too with no Metal device (CI).
    public static func compileError() -> String? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        do {
            _ = try ScreenGlowRenderer(device: device, pixelFormat: .bgra8Unorm)
            return nil
        } catch {
            return "\(error)"
        }
    }

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
        float2 size;
        float time;
        float rotation;
        float seed;
        float reach;
    };

    static float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    static float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = mix(hash(i), hash(i + float2(1.0, 0.0)), u.x);
        float b = mix(hash(i + float2(0.0, 1.0)), hash(i + float2(1.0, 1.0)), u.x);
        return mix(a, b, u.y);
    }

    fragment float4 glow_fragment(VOut in [[stage_in]],
                                  constant Uniforms &u [[buffer(0)]],
                                  constant float4 *colors [[buffer(1)]]) {
        float2 p = in.pos.xy;
        float2 s = u.size;
        // Square corners, as Incredible's: the distance to the nearest edge.
        float d = min(min(p.x, s.x - p.x), min(p.y, s.y - p.y));
        float2 c = p - s * 0.5;
        float angle = atan2(c.y, c.x);
        // Two travelling waves and slow noise move the inner edge.
        float wave = 0.5 * sin(angle * 6.0 + u.time * 0.9) + 0.35 * sin(angle * 11.0 - u.time * 1.3);
        float n = noise(float2(angle * 3.0 + u.seed, u.time * 0.25));
        float reach = u.reach * (1.0 + 0.18 * wave + 0.25 * (n - 0.5));
        float k = clamp(1.0 - d / max(reach, 1.0), 0.0, 1.0);
        float intensity = k * k;
        float wheel = fract((angle + u.rotation) / 6.28318530718) * 4.0;
        int i0 = int(floor(wheel)) % 4;
        int i1 = (i0 + 1) % 4;
        float3 col = mix(colors[i0].rgb, colors[i1].rgb, smoothstep(0.0, 1.0, fract(wheel)));
        return float4(col * intensity, intensity);
    }
    """
}

/// Draws the glow at full strength; the view's opacity carries the fades.
final class ScreenGlowRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var rotation: Float
        var seed: Float
        var reach: Float
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let colors: [SIMD4<Float>]
    private var start = CACurrentMediaTime()
    private var phase = Double.random(in: 0..<(2 * Double.pi))
    private var seed = Float.random(in: 0..<100)
    var animated = true
    var scale: CGFloat = 2

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
        self.colors = ScreenGlow.colors.map { swatch in
            let c = swatch.ns.usingColorSpace(.sRGB) ?? swatch.ns
            return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
        }
    }

    enum GlowError: Error { case noQueue }

    /// Incredible starts every activation from a new phase and noise seed.
    func reseed() {
        start = CACurrentMediaTime()
        phase = Double.random(in: 0..<(2 * Double.pi))
        seed = Float.random(in: 0..<100)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let time = animated ? CACurrentMediaTime() - start : 0
        var uniforms = Uniforms(
            size: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: Float(time),
            rotation: Float(ScreenGlow.rotation(at: time, phase: phase, animated: animated)),
            seed: seed, reach: Float(ScreenGlow.reach * scale))
        var palette = colors
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBytes(&palette, length: MemoryLayout<SIMD4<Float>>.stride * palette.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// The MTKView, paused whenever nothing is showing so an idle Mac spends no GPU.
struct ScreenGlowMetalView: NSViewRepresentable {
    let running: Bool
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
        view.isPaused = true
        view.enableSetNeedsDisplay = false
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
        renderer.animated = animated
        renderer.scale = view.window?.backingScaleFactor ?? 2
        if running, view.isPaused { renderer.reseed() }
        view.isPaused = !running
    }
}
