import Foundation
import MacotronEngine

@MainActor
public final class LauncherSession: ObservableObject {
    public struct PendingArgs {
        public let commandId: String
        public let title: String
        public let arguments: [CommandArgumentSpec]

        public init(commandId: String, title: String, arguments: [CommandArgumentSpec]) {
            self.commandId = commandId
            self.title = title
            self.arguments = arguments
        }
    }

    @Published public var pendingArgs: PendingArgs?

    public init() {}
}
