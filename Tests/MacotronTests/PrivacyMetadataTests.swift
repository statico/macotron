import Foundation
import Testing
import UserNotifications
@testable import Modules

@Suite("Privacy metadata")
struct PrivacyMetadataTests {
    @Test("Info.plist explains screen capture")
    func screenCaptureUsage() throws {
        let root = try plist("Resources/Info.plist")
        let reason = root["NSScreenCaptureUsageDescription"] as? String
        #expect(reason?.isEmpty == false)
    }

    @Test("entitlements allow Apple events")
    func appleEvents() throws {
        let root = try plist("Resources/Macotron.entitlements")
        #expect(root["com.apple.security.automation.apple-events"] as? Bool == true)
    }
}

@Suite("Notify authorization deferral")
struct NotifyDeferralTests {
    @Test("delivery is gated on authorization status")
    func gating() {
        #expect(NotifyModule.deliveryDecision(for: .notDetermined) == .askFirst)
        #expect(NotifyModule.deliveryDecision(for: .denied) == .drop)
        #expect(NotifyModule.deliveryDecision(for: .authorized) == .deliver)
        #expect(NotifyModule.deliveryDecision(for: .provisional) == .deliver)
    }
}

private func plist(_ relative: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: relative)
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.xml
    return try #require(PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: &format
    ) as? [String: Any])
}
