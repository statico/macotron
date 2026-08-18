import Testing
import AI

@Suite("AIChatMessages")
struct AIChatMessageTests {
    @Test("normalizes user and assistant roles")
    func normalizesRoles() throws {
        let result = try AIChatMessages.normalize([
            AIChatMessage(role: "User", content: "hi"),
            AIChatMessage(role: "ASSISTANT", content: "hello"),
        ])
        #expect(result == [
            .user("hi"),
            .assistant("hello"),
        ])
    }

    @Test("rejects invalid role")
    func rejectsInvalidRole() {
        #expect(throws: AIChatMessageError.invalidRole("system")) {
            try AIChatMessages.normalize([AIChatMessage(role: "system", content: "x")])
        }
    }

    @Test("rejects empty content and empty array")
    func rejectsEmpty() {
        #expect(throws: AIChatMessageError.emptyMessages) {
            try AIChatMessages.normalize([])
        }
        #expect(throws: AIChatMessageError.emptyContent) {
            try AIChatMessages.normalize([.user("")])
        }
    }
}
