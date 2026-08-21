// CRTOverlay.swift — fullscreen CRT shader drawn over the desktop
import AppKit
import Metal
import QuartzCore

/// A click-through Metal overlay on every screen: scanlines, a phosphor grille,
/// vignette, and a rolling brightness bar.
///
/// ponytail: overlay only. Because this composites on top of the desktop it can
/// darken and tint, but it cannot warp or split the pixels underneath. Barrel
/// distortion and RGB fringing need the desktop as a texture, which means
/// ScreenCaptureKit and a Screen Recording prompt.
@MainActor
final class CRTOverlay {
    private var windows: [NSWindow] = []

    var isOn: Bool { !windows.isEmpty }

    /// Returns false when Metal is unavailable, so callers can report it.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled else {
            teardown()
            return true
        }
        if isOn { return true }
        guard let renderer = CRTRenderer() else { return false }
        // ponytail: windows match the screens present at toggle time — toggle
        // again after attaching a display to cover it.
        windows = NSScreen.screens.map { Self.makeWindow(screen: $0, renderer: renderer) }
        return isOn
    }

    func teardown() {
        let dying = windows
        windows.removeAll()
        for window in dying {
            (window.contentView as? CRTView)?.stop()
            // orderOut + drop the view — close() starts _NSWindowTransformAnimation
            // and crashes when CAMetalLayer is still presenting.
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    private static func makeWindow(screen: NSScreen, renderer: CRTRenderer) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = CRTView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            renderer: renderer
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        (window.contentView as? CRTView)?.start()
        return window
    }
}

/// GPU objects shared by every screen's view.
final class CRTRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: CRTShader.source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "crtVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "crtFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }
        self.device = device
        self.queue = queue
    }
}

struct CRTUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var scale: Float
}

private final class CRTView: NSView {
    private let renderer: CRTRenderer
    private var link: CADisplayLink?
    private let started = CACurrentMediaTime()

    init(frame: CGRect, renderer: CRTRenderer) {
        self.renderer = renderer
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        return layer
    }

    func start() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard let layer = layer as? CAMetalLayer else { return }
        let scale = window?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let drawable = layer.nextDrawable(),
              let buffer = renderer.queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var uniforms = CRTUniforms(
            resolution: SIMD2(Float(layer.drawableSize.width), Float(layer.drawableSize.height)),
            time: Float(CACurrentMediaTime() - started),
            scale: Float(scale)
        )
        encoder.setRenderPipelineState(renderer.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CRTUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

enum CRTShader {
    /// Compiled at runtime from this constant. Plugins pick an effect by name and
    /// never supply shader source, so nothing here is attacker-controlled.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float time;
        float scale;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut crtVertex(uint vid [[vertex_id]]) {
        float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        float2 p = corners[vid];
        VertexOut out;
        out.position = float4(p, 0, 1);
        out.uv = p * 0.5 + 0.5;
        return out;
    }

    fragment float4 crtFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        const float tau = 6.2831853;
        float2 px = in.uv * u.resolution;

        // Scanline pitch follows the backing scale so the lines stay visible on Retina.
        float pitch = max(2.0, 3.0 * u.scale);
        float scan = 0.5 + 0.5 * cos(tau * px.y / pitch);

        // A finer vertical triad reads as an aperture grille. Alpha is one channel,
        // so this darkens rather than tinting each phosphor stripe.
        float grille = 0.5 + 0.5 * cos(tau * px.x / (pitch * 0.5));

        float2 c = in.uv * 2.0 - 1.0;
        float vignette = smoothstep(0.55, 1.45, length(c * float2(1.0, 0.88)));

        // Mains hum: a soft bar rolling down, plus a faint flicker.
        float rolling = fract(in.uv.y + u.time * 0.12) - 0.5;
        float bar = exp(-rolling * rolling * 70.0);
        float flicker = 0.010 * sin(u.time * 110.0);

        float alpha = 0.26 * scan + 0.05 * grille + 0.34 * vignette - 0.05 * bar + flicker;
        alpha = clamp(alpha, 0.0, 0.85);

        // Dark green glass rather than ink, so the mask reads as phosphor.
        float3 tint = float3(0.015, 0.030, 0.020);
        return float4(tint * alpha, alpha);
    }
    """
}
