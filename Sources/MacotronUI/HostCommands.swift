import Foundation

public enum HostCommands {
    public static let showHotkeysID = "macotron.show-hotkeys"
    public static let openSettingsID = "macotron.settings"
    public static let openPluginsID = "macotron.plugins"
    public static let quitID = "macotron.quit"
    public static let resetRankingID = "macotron.reset-ranking"
    /// Deliberately absent from `all`: the launcher only offers this row while a
    /// required permission is actually missing.
    public static let fixPermissionsID = "macotron.fix-permissions"

    public struct Definition: Equatable, Sendable {
        public let id: String
        public let name: String
        public let description: String

        public init(id: String, name: String, description: String) {
            self.id = id
            self.name = name
            self.description = description
        }
    }

    public static let all: [Definition] = [
        Definition(
            id: showHotkeysID,
            name: "Show Hotkeys",
            description: "List every keyboard shortcut bound in Macotron"
        ),
        Definition(
            id: openSettingsID,
            name: "Macotron Settings",
            description: "Open Macotron's own settings window"
        ),
        Definition(
            id: openPluginsID,
            name: "Macotron Plugins",
            description: "Open the Plugins tab in Macotron's settings"
        ),
        Definition(
            id: quitID,
            name: "Quit Macotron",
            description: "Stop Macotron, its hotkeys, and its plugins"
        ),
        Definition(
            id: resetRankingID,
            name: "Reset Launcher Ranking",
            description: "Forget which results are picked most often"
        ),
    ]

    public static func definition(for id: String) -> Definition? {
        all.first { $0.id == id }
    }
}
