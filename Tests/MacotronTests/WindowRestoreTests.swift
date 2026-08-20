import Testing
@testable import Modules

@Suite("WindowRestore")
struct WindowRestoreTests {
    private func win(
        _ id: Int32,
        app: String,
        title: String,
        bundleID: String? = nil
    ) -> WindowRestore.Window {
        WindowRestore.Window(id: id, app: app, title: title, bundleID: bundleID)
    }

    @Test("bundleID match when both present")
    func bundleIDMatch() {
        let windows = [
            win(1, app: "Safari", title: "Home", bundleID: "com.apple.Safari"),
            win(2, app: "Chrome", title: "Home", bundleID: "com.google.Chrome"),
        ]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Ignored", title: "Home", bundleID: "com.google.Chrome")
        )
        #expect(id == 2)
    }

    @Test("bundleID mismatch ignores app name")
    func bundleIDMismatch() {
        let windows = [win(1, app: "Safari", title: "Home", bundleID: "com.apple.Safari")]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Safari", title: "Home", bundleID: "com.google.Chrome")
        )
        #expect(id == nil)
    }

    @Test("app name is case-insensitive when bundleID is missing")
    func appNameCaseInsensitive() {
        let windows = [win(3, app: "Notes", title: "Inbox")]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "notes", title: nil, bundleID: nil)
        )
        #expect(id == 3)
    }

    @Test("missing bundleID on either side falls back to app name")
    func bundleIDFallback() {
        let windows = [win(4, app: "Mail", title: "Inbox", bundleID: "com.apple.mail")]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Mail", title: "Inbox", bundleID: nil)
        )
        #expect(id == 4)
    }

    @Test("title exact match")
    func titleExact() {
        let windows = [
            win(5, app: "Code", title: "README"),
            win(6, app: "Code", title: "README.md — repo"),
        ]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Code", title: "README", bundleID: nil)
        )
        #expect(id == 5)
    }

    @Test("title prefix when no exact")
    func titlePrefix() {
        let windows = [
            win(7, app: "Code", title: "Other"),
            win(8, app: "Code", title: "README.md — repo"),
        ]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Code", title: "README", bundleID: nil)
        )
        #expect(id == 8)
    }

    @Test("first window of that app when title misses")
    func firstWindowOfApp() {
        let windows = [
            win(9, app: "Preview", title: "A.pdf"),
            win(10, app: "Preview", title: "B.pdf"),
        ]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Preview", title: "Missing", bundleID: nil)
        )
        #expect(id == 9)
    }

    @Test("first window of that app when title omitted")
    func firstWindowNoTitle() {
        let windows = [
            win(11, app: "Terminal", title: "zsh"),
            win(12, app: "Terminal", title: "bash"),
        ]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Terminal", title: nil, bundleID: nil)
        )
        #expect(id == 11)
    }

    @Test("no match when app is unknown")
    func noMatch() {
        let windows = [win(13, app: "Finder", title: "Desktop")]
        let id = WindowRestore.match(
            windows,
            WindowRestore.Entry(app: "Music", title: nil, bundleID: nil)
        )
        #expect(id == nil)
    }
}
