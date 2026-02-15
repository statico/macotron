// LauncherView.swift — SwiftUI root view for the launcher (search + chat)
import SwiftUI
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

    public enum ResultType {
        case app
        case file
        case command
        case snippet
        case action
    }

    public init(id: String, title: String, subtitle: String, icon: String, type: ResultType) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.type = type
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
    public var onSearch: ((String) -> [SearchResult])?
    public var onChat: (@Sendable (String) async -> String)?

    public init(
        onExecuteCommand: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onChat: (@Sendable (String) async -> String)? = nil
    ) {
        self.onExecuteCommand = onExecuteCommand
        self.onSearch = onSearch
        self.onChat = onChat
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 8) {
                Image(systemName: mode == .chat ? "bubble.left.fill" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3)

                TextField("Search or ask...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .onSubmit { execute() }
                    .disabled(isChatLoading)

                if mode == .chat {
                    Text("Chat")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("Search")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding()

            Divider()

            if mode == .chat {
                chatView
            } else {
                // Results list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, isSelected: index == selectedIndex)
                                .onTapGesture { executeResult(result) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
        }
        .onChange(of: query) { _, newValue in
            // Don't reclassify while loading a chat response
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
            .frame(maxHeight: 400)
            .onChange(of: chatMessages.count) { _, _ in
                // Scroll to bottom when new messages arrive
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

    // MARK: - Actions

    private func execute() {
        if mode == .chat {
            sendChatMessage()
        } else if let result = results.first {
            executeResult(result)
        }
    }

    private func sendChatMessage() {
        let message = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isChatLoading else { return }

        // Add user message to chat
        chatMessages.append(ChatMessage(role: .user, text: message))

        // Clear the input
        query = ""
        isChatLoading = true

        // Send to AI
        chatTask = Task {
            let responseText: String
            if let onChat {
                responseText = await onChat(message)
            } else {
                responseText = "Chat is not configured. Set an AI API key in your config."
            }

            chatMessages.append(ChatMessage(role: .assistant, text: responseText))
            isChatLoading = false
        }
    }

    private func executeResult(_ result: SearchResult) {
        onExecuteCommand?(result.id)
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
        HStack(spacing: 10) {
            Image(systemName: result.icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.body)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }
}
