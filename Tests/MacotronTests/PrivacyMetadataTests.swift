import Foundation
import Testing
@testable import MacotronEngine

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

@Suite("Automation permission")
@MainActor
struct AutomationPermissionTests {
    @Test func parseAndLabel() {
        #expect(Permissions.parse("automation") == .automation)
        #expect(Permission.automation.title == "Automation")
        #expect(Permission.automation.isAutoRequestable == false)
        #expect(Permissions.baseline.contains(.automation))
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
