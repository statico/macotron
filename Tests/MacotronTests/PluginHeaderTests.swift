// PluginHeaderTests.swift — static title/description from macotron.plugin()
import Foundation
import Testing
@testable import MacotronEngine

@Suite("PluginHeader")
struct PluginHeaderTests {

    @Test("Reads title and description from macotron.plugin()")
    func parsesTitleAndDescription() {
        let source = """
        const opts = macotron.plugin({
            title: "Weather",
            description: "Current weather in the menu bar.",
            options: { location: { type: "string", label: "Location", default: "" } },
        });
        """
        let header = PluginHeader.parse(source)
        #expect(header.title == "Weather")
        #expect(header.description == "Current weather in the menu bar.")
    }

    @Test("Reads permissions without eval")
    func parsesPermissions() {
        let source = """
        macotron.plugin({
            title: "OCR",
            permissions: ["screenRecording", "accessibility"],
        });
        """
        let header = PluginHeader.parse(source)
        #expect(header.permissions == ["screenRecording", "accessibility"])
    }

    @Test("Accepts single-quoted strings")
    func parsesSingleQuotes() {
        let header = PluginHeader.parse("macotron.plugin({ title: 'Meetings', description: 'Next event.' });")
        #expect(header.title == "Meetings")
        #expect(header.description == "Next event.")
    }

    @Test("Returns nil when macotron.plugin() is missing")
    func missingPluginCall() {
        let header = PluginHeader.parse("const title = 'not a plugin';\n")
        #expect(header.title == nil)
        #expect(header.description == nil)
    }

    @Test("Reads only the start of a file")
    func parseFileDoesNotReadWholePlugin() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macotron-header-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appending(path: "demo-weather.js")
        let prefix = "macotron.plugin({ title: \"Weather\", description: \"Current weather.\" });\n"
        let padding = String(repeating: "x", count: 200_000)
        try (prefix + padding).write(to: file, atomically: true, encoding: .utf8)

        let header = PluginHeader.parse(file: file)
        #expect(header.title == "Weather")
        #expect(header.description == "Current weather.")
    }
}
