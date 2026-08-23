import Foundation

public enum HostCommands {
    public static let showHotkeysID = "macotron.show-hotkeys"
    public static let openSettingsID = "macotron.settings"

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
    ]

    public static func definition(for id: String) -> Definition? {
        all.first { $0.id == id }
    }
}
