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

@Suite("AIProviderFactory")
struct AIProviderFactoryTests {
    @Test("maps picker names")
    func names() {
        #expect(AIProviderFactory.create(name: "gemini").providerName == "gemini")
        #expect(AIProviderFactory.create(name: "anthropic").providerName == "claude")
        #expect(AIProviderFactory.create(name: "small").providerName == "local")
        #expect(AIProviderFactory.create(name: "gpu").providerName == "local")
    }
}
