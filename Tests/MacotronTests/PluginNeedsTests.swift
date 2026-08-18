// PluginNeedsTests.swift — Semver pragma parse + host API compare
import Testing
@testable import MacotronEngine

@Suite("PluginNeeds Tests")
struct PluginNeedsTests {

    @Test("Missing pragma defaults to 1.0.0")
    func testMissingDefaultsTo100() {
        guard case .success(let version) = PluginNeeds.parse("macotron.log('hi')\n") else {
            Issue.record("expected success")
            return
        }
        #expect(version == SemVer(major: 1, minor: 0, patch: 0))
    }

    @Test("Short form 1.2 normalizes to 1.2.0")
    func testShortFormNormalizes() {
        guard case .success(let version) = PluginNeeds.parse("// @macotron needs 1.2\nmacotron.log(1)\n") else {
            Issue.record("expected success")
            return
        }
        #expect(version == SemVer(major: 1, minor: 2, patch: 0))
        #expect(version.description == "1.2.0")
    }

    @Test("Unmet needs fails compare")
    func testUnmetNeedsFailsCompare() {
        guard case .success(let needs) = PluginNeeds.parse("// @macotron needs 1.2\n") else {
            Issue.record("expected success")
            return
        }
        let host = SemVer(Engine.apiVersion)!
        #expect(needs > host)
        #expect(!(host >= needs))
        #expect(PluginNeeds.unmetMessage(needs: needs, host: host)
                == "Needs Macotron API 1.2 (this host is 1.0)")
    }

    @Test("Invalid pragma fails")
    func testInvalidPragmaFails() {
        let result = PluginNeeds.parse("// @macotron needs not-a-version\n")
        switch result {
        case .success:
            Issue.record("expected failure")
        case .failure(let error):
            #expect(error.message.contains("Invalid"))
        }
    }

    @Test("registerAllModules exposes version.api")
    @MainActor
    func testVersionApiExposed() {
        let engine = Engine()
        engine.registerAllModules()
        let (result, error) = engine.evaluate("macotron.version.api")
        #expect(error == nil)
        #expect(result == Engine.apiVersion)
    }
}
