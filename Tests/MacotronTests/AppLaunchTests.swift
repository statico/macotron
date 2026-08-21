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

    /// Synthetic layout, so this holds whether or not Xcode is installed here.
    @Test("apps nested inside an Xcode bundle are scanned")
    func nestedBundlesInXcode() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "macotron-nested-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let xcode = root.appending(path: "Xcode.app")
        for sub in ["Contents/Developer/Applications/Simulator.app", "Contents/Applications/Instruments.app"] {
            try fm.createDirectory(at: xcode.appending(path: sub), withIntermediateDirectories: true)
        }
        let other = root.appending(path: "TextEdit.app")
        try fm.createDirectory(at: other.appending(path: "Contents/Applications/Sneaky.app"), withIntermediateDirectories: true)

        let nested = AppCatalog.nestedBundles(in: xcode).map(\.lastPathComponent)
        #expect(nested.sorted() == ["Instruments.app", "Simulator.app"])
        #expect(AppCatalog.nestedBundles(in: other).isEmpty)
    }

    @Test(
        "the scan finds Simulator, which Xcode nests inside its own bundle",
        .enabled(if: FileManager.default.fileExists(atPath: "/Applications/Xcode.app"))
    )
    func scanFindsSimulator() {
        let nested = AppCatalog.nestedBundles(in: URL(fileURLWithPath: "/Applications/Xcode.app"))
        #expect(nested.contains { $0.lastPathComponent == "Simulator.app" })
        #expect(Bundle(url: URL(
            fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
        ))?.bundleIdentifier == "com.apple.iphonesimulator")
    }

    @Test("shortcut hides when the app is already frontmost")
    func hideIfFrontmost() {
        #expect(AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.Safari"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: "com.apple.finder"))
        #expect(!AppLaunch.shouldHide(bundleID: "com.apple.Safari", frontmost: nil))
        #expect(!AppLaunch.shouldHide(bundleID: "", frontmost: ""))
    }
}
