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

    @Test("search path includes Finder and Keychain Access")
    func catalogIncludesFinderAndKeychain() {
        let dirs = AppCatalog.searchDirectories()
        #expect(dirs.contains { $0.path == "/System/Library/CoreServices/Applications" })
        #expect(AppCatalog.extraApps.contains { $0.lastPathComponent == "Finder.app" })
        #expect(FileManager.default.fileExists(
            atPath: "/System/Library/CoreServices/Applications/Keychain Access.app"
        ))
        #expect(FileManager.default.fileExists(
            atPath: "/System/Library/CoreServices/Finder.app"
        ))
    }

    @Test("the scan finds Safari, a hidden symlink into the Cryptexes volume")
    func scanFindsSafari() {
        let apps = AppCatalog.appBundles(in: URL(fileURLWithPath: "/Applications"))
        #expect(apps.contains { $0.lastPathComponent == "Safari.app" })
        #expect(Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))?
            .bundleIdentifier == "com.apple.Safari")
    }

    @Test("shortcut hides when the app is already frontmost")
    func hideIfFrontmost() {
        #expect(AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.Safari"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.finder"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: nil))
        #expect(!AppLaunch.shouldHide(bundleID: "", frontmost: ""))
    }
}
