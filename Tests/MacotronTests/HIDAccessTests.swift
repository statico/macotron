import Testing
@testable import MacotronEngine

@Suite("HIDAccess Tests")
struct HIDAccessTests {
    @Test("Granted is IOHIDAccessType 0, not a Bool true")
    func testGrantedIsZero() {
        #expect(HIDAccess.isGranted(0) == true)
        #expect(HIDAccess.isGranted(1) == false)
        #expect(HIDAccess.isGranted(2) == false)
    }
}
