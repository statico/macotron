import Metal
import Testing

@testable import Modules

@Suite("CRTOverlay")
struct CRTOverlayTests {
    /// A typo in the shader source only shows up as "Unavailable" at runtime, so
    /// compile it here. Skipped where the test host has no Metal device.
    @Test("the CRT shader compiles and builds a pipeline")
    func shaderCompiles() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        #expect(CRTRenderer() != nil)
    }

    @Test("uniforms match the Metal struct layout")
    func uniformLayout() {
        #expect(MemoryLayout<CRTUniforms>.stride == 16)
        #expect(MemoryLayout<CRTUniforms>.alignment == 8)
    }
}
