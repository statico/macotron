import MacotronEngine
import Testing

@Suite("Permission declarations")
@MainActor
struct HelperPermissionTests {
    /// Every alias a plugin may declare, with the case it maps to and how that
    /// case shows up in Settings.
    @Test(arguments: [
        ("helper", Permission.helper, "Background Helper", false),
        ("automation", .automation, "Automation", false),
        ("applescript", .automation, "Automation", false),
        ("accessibility", .accessibility, "Accessibility", true),
        ("camera", .camera, "Camera", true),
        ("webcam", .camera, "Camera", true),
        ("qr", .camera, "Camera", true),
    ])
    func alias(name: String, permission: Permission, title: String, isAutoRequestable: Bool) {
        #expect(Permissions.parse(name) == permission)
        #expect(permission.title == title)
        #expect(permission.isAutoRequestable == isAutoRequestable)
    }

    @Test func unknownAliasIsRejected() {
        #expect(Permissions.parse("fanControl") == nil)
    }

    @Test func helperExplainsItself() {
        #expect(Permission.helper.reason == "Lets plugins control privileged features like fan control.")
    }

    @Test func automationIsAlwaysRequired() {
        #expect(Permissions.baseline.contains(.automation))
    }

    @Test func helperDoesNotBlockLaunch() {
        let missing = Permissions.missing(from: [.helper])
        #expect(missing.contains(where: \.isAutoRequestable) == false)
    }
}
