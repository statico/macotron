import Foundation
import Testing
@testable import Modules

@Suite("SharePath")
struct SharePathTests {
    @Test func expandsTilde() {
        let expanded = SharePath.expand("~/Desktop/note.txt")
        #expect(!expanded.hasPrefix("~"))
        #expect(expanded.hasPrefix(NSHomeDirectory()))
        #expect(expanded.hasSuffix("/Desktop/note.txt"))
    }

    @Test func leavesAbsolutePaths() {
        #expect(SharePath.expand("/tmp/a") == "/tmp/a")
    }
}
