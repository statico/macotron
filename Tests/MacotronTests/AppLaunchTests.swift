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

    @Test("shortcut hides when the app is already frontmost")
    func hideIfFrontmost() {
        #expect(AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.Safari"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.finder"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: nil))
        #expect(!AppLaunch.shouldHide(bundleID: "", frontmost: ""))
    }
}
