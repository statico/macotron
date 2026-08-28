import AppKit
import ApplicationServices
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

    private func entry(_ app: String, _ title: String? = nil, _ bundleID: String? = nil) -> WindowRestore.Entry {
        WindowRestore.Entry(app: app, title: title, bundleID: bundleID)
    }

    /// One shape for every rule: build the windows on screen, build the saved
    /// entry, expect the id it should land on (or nil for no match).
    @Test("match picks the window each rule says it should", arguments: [
        // bundleID wins over app name, both when it matches and when it does not
        ([(Int32(1), "Safari", "Home", "com.apple.Safari"), (2, "Chrome", "Home", "com.google.Chrome")],
         ("Ignored", "Home", "com.google.Chrome"), Int32(2)),
        ([(Int32(1), "Safari", "Home", "com.apple.Safari")],
         ("Safari", "Home", "com.google.Chrome"), nil),
        // app name, case-insensitive, when a bundleID is missing on either side
        ([(Int32(3), "Notes", "Inbox", nil)], ("notes", nil, nil), Int32(3)),
        ([(Int32(4), "Mail", "Inbox", "com.apple.mail")], ("Mail", "Inbox", nil), Int32(4)),
        // exact title beats a prefix, prefix is used when nothing is exact
        ([(Int32(5), "Code", "README", nil), (6, "Code", "README.md — repo", nil)],
         ("Code", "README", nil), Int32(5)),
        ([(Int32(7), "Code", "Other", nil), (8, "Code", "README.md — repo", nil)],
         ("Code", "README", nil), Int32(8)),
        // title missing or absent falls back to that app's first window
        ([(Int32(9), "Preview", "A.pdf", nil), (10, "Preview", "B.pdf", nil)],
         ("Preview", "Missing", nil), Int32(9)),
        ([(Int32(11), "Terminal", "zsh", nil), (12, "Terminal", "bash", nil)],
         ("Terminal", nil, nil), Int32(11)),
        // unknown app matches nothing
        ([(Int32(13), "Finder", "Desktop", nil)], ("Music", nil, nil), nil),
    ] as [([(Int32, String, String, String?)], (String, String?, String?), Int32?)])
    func matches(
        _ windows: [(Int32, String, String, String?)],
        _ saved: (String, String?, String?),
        _ expected: Int32?
    ) {
        let id = WindowRestore.match(
            windows.map { win($0.0, app: $0.1, title: $0.2, bundleID: $0.3) },
            entry(saved.0, saved.1, saved.2)
        )
        #expect(id == expected)
    }
}

@Suite("WindowAX enumeration")
struct WindowAXEnumerateTests {
    /// Guards the one shared enumerator that window.getAll() and the restore
    /// snapshot both walk. It cannot compare against a second live walk --
    /// windows open and close between the two -- so it checks the property the
    /// consolidation could actually break: every app's windows arrive as
    /// contiguous indices from 0, which is what windowID() encodes.
    @Test("enumerate yields contiguous per-app indices from zero")
    func contiguousIndices() {
        var perApp: [pid_t: [Int]] = [:]
        WindowAX.enumerate { app, index, _ in
            perApp[app.processIdentifier, default: []].append(index)
        }
        for (pid, indices) in perApp {
            #expect(indices == Array(0..<indices.count))
            #expect(WindowAX.windowID(pid: pid, index: indices[0]) == Int32(pid) * 1000)
        }
    }
}
