import Foundation
import Testing
@testable import AI

@Suite("GeminiAPI")
struct GeminiAPITests {
    @Test("reads candidate text")
    func parse() {
        let data = Data("""
        {"candidates":[{"content":{"parts":[{"text":"Hello"},{"text":" world"}]}}]}
        """.utf8)
        #expect(GeminiAPI.text(from: data) == "Hello world")
    }
}

