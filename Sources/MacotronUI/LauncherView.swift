// LauncherView.swift — SwiftUI root view for the launcher (search + chat)
import SwiftUI
import AppKit
import MacotronEngine

public enum LauncherMode {
    case search
    case chat
}

public struct SearchResult: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let type: ResultType
    public let nsImage: NSImage?
    public let appURL: URL?

    public enum ResultType {
        case app
        case file
        case command
        case snippet
        case action
    }

    public init(
        id: String, title: String, subtitle: String, icon: String, type: ResultType,
        nsImage: NSImage? = nil, appURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.type = type
        self.nsImage = nsImage
        self.appURL = appURL
    }
}

/// A single message in the chat conversation
public struct ChatMessage: Identifiable {
    public let id = UUID()
    public let role: Role
    public let text: String

    public enum Role {
        case user
        case assistant
        case error
    }
}

public struct LauncherView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var mode: LauncherMode = .search
    @State private var selectedIndex = 0
    @State private var chatMessages: [ChatMessage] = []
    @State private var isChatLoading = false
    @State private var chatTask: Task<Void, Never>?

    private let classifier = NLClassifier()
    public var onExecuteCommand: ((String) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onChat: (@Sendable (String) async -> String)?

    public init(
        onExecuteCommand: ((String) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onChat: (@Sendable (String) async -> String)? = nil
    ) {
        self.onExecuteCommand = onExecuteCommand
        self.onRevealInFinder = onRevealInFinder
        self.onSearch = onSearch
        self.onChat = onChat
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 10) {
                Image(systemName: mode == .chat ? "bubble.left.fill" : "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.title2)
                    .frame(width: 24)

                TextField("Search apps, commands, or ask a question...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .onSubmit { execute() }
                    .disabled(isChatLoading)

                if mode == .chat {
                    Text("Chat")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            if mode == .chat {
                chatView
            } else {
                searchResultsView
            }

            // Bottom bar with shortcuts
            if mode == .search && !results.isEmpty {
                Divider().opacity(0.5)
                HStack(spacing: 16) {
                    shortcutHint(keys: ["return"], label: "Open")
                    shortcutHint(keys: ["cmd", "return"], label: "Reveal in Finder")
                    Spacer()
                    shortcutHint(keys: ["esc"], label: "Close")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .onChange(of: query) { _, newValue in
            guard !isChatLoading else { return }

            let classification = classifier.classify(newValue)
            switch classification {
            case .naturalLang:
                mode = .chat
            case .search, .command:
                mode = .search
                results = onSearch?(newValue) ?? []
                selectedIndex = 0
            }
        }
        .background(KeyEventHandler(
            onArrowUp: { moveSelection(-1) },
            onArrowDown: { moveSelection(1) },
            onCmdReturn: { executeSelectedWithModifier() }
        ))
    }

    // MARK: - Search Results View

    @ViewBuilder
    private var searchResultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == selectedIndex)
                            .id(result.id)
                            .onTapGesture { executeResult(result) }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 420)
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex < results.count {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(results[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Chat View

    @ViewBuilder
    private var chatView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if chatMessages.isEmpty && !isChatLoading {
                        Text("Ask me to create snippets, manage your config, or explain what your snippets do.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }

                    ForEach(chatMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isChatLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .id("loading")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 420)
            .onChange(of: chatMessages.count) { _, _ in
                if let lastMsg = chatMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isChatLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Keyboard Navigation

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < results.count {
            selectedIndex = newIndex
        }
    }

    // MARK: - Actions

    private func execute() {
        if mode == .chat {
            sendChatMessage()
        } else if selectedIndex < results.count {
            executeResult(results[selectedIndex])
        }
    }

    private func executeSelectedWithModifier() {
        guard selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        onRevealInFinder?(result.id)
    }

    private func sendChatMessage() {
        let message = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isChatLoading else { return }

        chatMessages.append(ChatMessage(role: .user, text: message))
        query = ""
        isChatLoading = true

        chatTask = Task {
            let responseText: String
            if let onChat {
                responseText = await onChat(message)
            } else {
                responseText = "Chat is not configured. Set an AI API key in Settings."
            }

            chatMessages.append(ChatMessage(role: .assistant, text: responseText))
            isChatLoading = false
        }
    }

    private func executeResult(_ result: SearchResult) {
        onExecuteCommand?(result.id)
    }

    // MARK: - Shortcut Hint

    @ViewBuilder
    private func shortcutHint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(keySymbol(key))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(3)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func keySymbol(_ key: String) -> String {
        switch key {
        case "cmd": return "\u{2318}"
        case "return": return "\u{23CE}"
        case "esc": return "\u{238B}"
        case "shift": return "\u{21E7}"
        case "opt": return "\u{2325}"
        case "ctrl": return "\u{2303}"
        default: return key
        }
    }
}

// MARK: - Key Event Handler (for arrow keys and Cmd+Enter)

struct KeyEventHandler: NSViewRepresentable {
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onCmdReturn: () -> Void

    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView()
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onCmdReturn = onCmdReturn
        return view
    }

    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onCmdReturn = onCmdReturn
    }

    final class KeyEventNSView: NSView {
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onCmdReturn: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command) && event.keyCode == 36 { // Cmd+Return
                onCmdReturn?()
                return
            }
            switch event.keyCode {
            case 126: // Up arrow
                onArrowUp?()
            case 125: // Down arrow
                onArrowDown?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                if message.role != .user {
                    HStack(spacing: 4) {
                        Image(systemName: message.role == .error ? "exclamationmark.triangle" : "sparkle")
                            .font(.caption2)
                        Text(message.role == .error ? "Error" : "Macotron")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(message.role == .error ? .red : .secondary)
                }

                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(bubbleBackground)
                    .cornerRadius(10)
            }

            if message.role != .user {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.2)
        case .assistant:
            Color.secondary.opacity(0.1)
        case .error:
            Color.red.opacity(0.1)
        }
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let result: SearchResult
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // App icon or SF Symbol
            if let nsImage = result.nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(7)
            } else {
                Image(systemName: iconForType(result.type))
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .background(.quaternary)
                    .cornerRadius(7)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Type badge
            Text(labelForType(result.type))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func iconForType(_ type: SearchResult.ResultType) -> String {
        switch type {
        case .app: return "app.fill"
        case .file: return "doc.fill"
        case .command: return "terminal.fill"
        case .snippet: return "chevron.left.forwardslash.chevron.right"
        case .action: return "bolt.fill"
        }
    }

    private func labelForType(_ type: SearchResult.ResultType) -> String {
        switch type {
        case .app: return "Application"
        case .file: return "File"
        case .command: return "Command"
        case .snippet: return "Snippet"
        case .action: return "Action"
        }
    }
}
