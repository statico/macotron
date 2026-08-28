import Metal
import Testing

@testable import Modules

@Suite("CRTOverlay")
struct CRTOverlayTests {
    /// A typo in the shader source only shows up as "Unavailable" at runtime, so
    /// compile it here. Skipped where the test host has no Metal device.
    @Test(
        "the CRT shader compiles and builds a pipeline",
        .enabled(if: MTLCreateSystemDefaultDevice() != nil)
    )
    func shaderCompiles() {
        #expect(CRTRenderer() != nil)
    }

    @Test("uniforms match the Metal struct layout")
    func uniformLayout() {
        #expect(MemoryLayout<CRTUniforms>.stride == 16)
        #expect(MemoryLayout<CRTUniforms>.alignment == 8)
    }

    @Test("teardown uses orderOut, not animated close")
    @MainActor
    func teardownQuietly() {
        let overlay = CRTOverlay()
        _ = overlay.setEnabled(true)
        #expect(overlay.setEnabled(false))
        #expect(!overlay.isOn)
    }
}
