import Testing
import AI
@testable import MacotronEngine
@testable import Modules

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

/// The JS-facing half of `macotron.ai`: four factories, and the option
/// parsing plus promise plumbing behind chat/stream. Dry run settles both
/// promises with a stub, so this exercises the whole path without a network
/// call — which is the only part of it a test can reach.
@MainActor
@Suite("AI module bindings")
struct AIModuleBindingTests {
    private func engine() -> Engine {
        let engine = Engine()
        engine.dryRun = true
        engine.addModule(AIModule())
        engine.registerAllModules()
        return engine
    }

    @Test("every factory stamps its own provider and carries apiKey/model")
    func factories() {
        let (result, error) = engine().evaluate("""
            const keyed = macotron.ai.claude({ apiKey: 'k', model: 'm' });
            [macotron.ai.claude()._provider,
             macotron.ai.anthropic()._provider,
             macotron.ai.openai()._provider,
             macotron.ai.gemini()._provider,
             macotron.ai.local()._provider,
             keyed._apiKey,
             keyed._model,
             String(macotron.ai.claude()._apiKey),
             String(macotron.ai.local({ apiKey: 'k' })._apiKey)].join('|')
            """)
        #expect(error == nil)
        #expect(result == "claude|claude|openai|gemini|local|k|m|undefined|undefined")
    }

    @Test("chat resolves the dry-run stub, with and without options")
    func chatDryRun() {
        let engine = self.engine()
        let (_, error) = engine.evaluate("""
            globalThis.out = 'pending';
            macotron.ai.claude().chat('hi').then(
              t => { globalThis.out = 'plain:' + JSON.stringify(t); },
              e => { globalThis.out = 'rejected:' + e; }
            );
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "plain:\"\"")

        // An options object must be read without throwing, and a message array
        // must parse the same way a bare string does.
        let (_, optError) = engine.evaluate("""
            globalThis.out = 'pending';
            macotron.ai.openai().chat(
              [{ role: 'user', content: 'hi' }],
              { model: 'm', maxTokens: 10, temperature: 0.1, system: 's' }
            ).then(t => { globalThis.out = 'opts:' + JSON.stringify(t); });
            """)
        #expect(optError == nil)
        let (optResult, _) = engine.evaluate("globalThis.out")
        #expect(optResult == "opts:\"\"")
    }

    @Test("stream resolves the stub and never calls onChunk in dry run")
    func streamDryRun() {
        let engine = self.engine()
        let (_, error) = engine.evaluate("""
            globalThis.chunks = 0;
            globalThis.out = 'pending';
            macotron.ai.gemini().stream('hi', {
              onChunk: () => { globalThis.chunks += 1; },
            }).then(t => { globalThis.out = JSON.stringify(t); });
            """)
        #expect(error == nil)
        let (result, _) = engine.evaluate("globalThis.out")
        #expect(result == "\"\"")
        let (chunks, _) = engine.evaluate("String(globalThis.chunks)")
        #expect(chunks == "0")
    }

    @Test("an unknown provider throws rather than resolving")
    func unknownProvider() {
        let engine = self.engine()
        let (_, error) = engine.evaluate("""
            const c = macotron.ai.claude();
            c._provider = 'nope';
            c.chat('hi');
            """)
        #expect(error?.contains("Unknown AI provider") == true)
    }

    @Test("chat rejects a message list it cannot parse")
    func badMessages() {
        let engine = self.engine()
        let (_, error) = engine.evaluate("macotron.ai.claude().chat([])")
        #expect(error != nil)
    }
}
