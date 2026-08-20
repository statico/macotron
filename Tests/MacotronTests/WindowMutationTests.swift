import Testing
@testable import Modules

@Suite("WindowMutation")
struct WindowMutationTests {
    @Test("enhanced UI is restored when mutation fails")
    func disablesEnhancedUI() {
        var enhancedUI = true
        var observedDuringMutation = true

        let result = WindowMutation.perform(
            enhancedUI: enhancedUI,
            setEnhancedUI: { enhancedUI = $0 },
            mutate: {
                observedDuringMutation = enhancedUI
                return false
            }
        )

        #expect(!result)
        #expect(!observedDuringMutation)
        #expect(enhancedUI)
    }

    @Test("frame mutation applies size, position, then size")
    func frameOrder() {
        var operations: [String] = []

        let result = WindowMutation.applyFrame(
            setSize: {
                operations.append("size")
                return true
            },
            setPosition: {
                operations.append("position")
                return true
            }
        )

        #expect(result)
        #expect(operations == ["size", "position", "size"])
    }

    @Test("enhanced UI remains disabled when originally disabled")
    func preservesDisabledEnhancedUI() {
        var assignments: [Bool] = []

        _ = WindowMutation.perform(
            enhancedUI: false,
            setEnhancedUI: { assignments.append($0) },
            mutate: { false }
        )

        #expect(assignments.isEmpty)
    }
}
