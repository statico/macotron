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
    @Published public var query = ""

    /// Bumped when results that already arrived are known to be stale — an
    /// async launcher provider answering after its keystroke, say.
    @Published public var revision = 0

    public init() {}

    public func refresh() {
        revision &+= 1
    }

    public func reset() {
        query = ""
        pendingArgs = nil
    }
}
