import Testing
@testable import Modules

@Suite("NetworkRate")
struct NetworkRateTests {
    @Test("formats bytes/s compactly")
    func format() {
        #expect(NetworkRate.format(0) == "0")
        #expect(NetworkRate.format(80) == "80")
        #expect(NetworkRate.format(80_000) == "80K")
        #expect(NetworkRate.format(1_200_000) == "1.2M")
    }
}
