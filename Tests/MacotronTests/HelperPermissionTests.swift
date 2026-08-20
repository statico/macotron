import MacotronEngine
import Testing

@Suite("Helper permission")
@MainActor
struct HelperPermissionTests {
    @Test func settingsCallsItBackgroundHelper() {
        #expect(Permission.helper.title == "Background Helper")
        #expect(Permission.helper.reason == "Lets plugins control privileged features like fan control.")
    }

    @Test func parse() {
        #expect(Permissions.parse("helper") == .helper)
        #expect(Permissions.parse("fanControl") == nil)
    }

    @Test func helperIsNotAutoRequested() {
        #expect(Permission.helper.isAutoRequestable == false)
        #expect(Permission.accessibility.isAutoRequestable == true)
    }

    @Test func helperDoesNotBlockLaunch() {
        let missing = Permissions.missing(from: [.helper])
        #expect(missing.contains(where: \.isAutoRequestable) == false)
    }
}
