import Foundation
import Testing

@testable import MacotronUI

@Suite("PluginAuthoring")
struct PluginAuthoringTests {
    @Test("agents run in the workdir, editors open it")
    func toolShapes() {
        #expect(PluginAuthoring.agents.allSatisfy { $0.isAgent })
        #expect(PluginAuthoring.editors.allSatisfy { !$0.isAgent && $0.app != nil })
        let ids = (PluginAuthoring.agents + PluginAuthoring.editors).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("a workdir with a space stays one shell argument")
    func quotesSpaces() {
        let script = PluginAuthoring.terminalScript(command: "claude", in: "/Users/me/My Macotron")
        #expect(script.contains("cd '/Users/me/My Macotron' && clear && claude"))
    }

    @Test("a single quote in the path cannot end the shell string")
    func quotesApostrophes() {
        #expect(PluginAuthoring.shellQuoted("/Users/alex's mac") == #"'/Users/alex'\''s mac'"#)
    }

    @Test("quotes and backslashes survive the AppleScript string")
    func escapesAppleScript() {
        #expect(PluginAuthoring.appleScriptQuoted(#"say "hi"\ok"#) == #"say \"hi\"\\ok"#)
    }
}
