import MacotronEngine
import Testing

@Suite("Fan permission")
@MainActor
struct FanPermissionTests {
    @Test func settingsCallsItBackgroundHelper() {
        #expect(Permission.fanControl.title == "Background Helper")
        #expect(Permission.fanControl.reason == "Lets plugins control privileged features like fan control.")
    }

    @Test func aliases() {
        #expect(Permissions.parse("fan") == .fanControl)
        #expect(Permissions.parse("fan-control") == .fanControl)
        #expect(Permissions.parse("fanControl") == .fanControl)
    }

    @Test func helperIsNotAutoRequested() {
        #expect(Permission.fanControl.isAutoRequestable == false)
        #expect(Permission.accessibility.isAutoRequestable == true)
    }

    @Test func helperDoesNotBlockLaunch() {
        let missing = Permissions.missing(from: [.fanControl])
        #expect(missing.contains(where: \.isAutoRequestable) == false)
    }
}
