import AppKit
import Testing
@testable import Modules

@Suite("AppLaunch")
struct AppLaunchTests {
    @Test("unknown bundle id is not opened")
    func unknownBundle() {
        #expect(AppLaunch.open(bundleID: "io.statico.macotron.missing-app") == false)
    }

    @Test("Finder has a Launch Services URL")
    func finderURL() {
        #expect(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") != nil)
    }
}
