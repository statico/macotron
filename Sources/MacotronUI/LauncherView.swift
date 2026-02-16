// LauncherView.swift — SwiftUI root view for the launcher (search + agent)
import SwiftUI
import AppKit
import MacotronEngine

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

/// Example prompts shown when the search field is empty
private let examplePrompts = [
    "set up keybindings to let me move windows",
    "use safari to open all youtube links",
    "show CPU and memory in the menu bar",
    "flash my USB light when my camera turns on",
    "warn me when CPU gets too hot",
    "take a screenshot and summarize it with AI",
]

public struct LauncherView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0
    @ObservedObject var agentState: AgentProgressState

    private let classifier = NLClassifier()
    public var onExecuteCommand: ((String) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onAgent: ((String) -> Void)?
    public var onStopAgent: (() -> Void)?

    public init(
        agentState: AgentProgressState,
        onExecuteCommand: ((String) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onAgent: ((String) -> Void)? = nil,
        onStopAgent: (() -> Void)? = nil
    ) {
        self.agentState = agentState
        self.onExecuteCommand = onExecuteCommand
        self.onRevealInFinder = onRevealInFinder
        self.onSearch = onSearch
        self.onAgent = onAgent
        self.onStopAgent = onStopAgent
    }

    public var body: some View {
        VStack(spacing: 0) {
            if agentState.isRunning {
                agentProgressInlineView
            } else {
                // Search input
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 20))
                        .frame(width: 24, height: 24)

                    TextField("Search or describe what you want...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .regular))
                        .frame(height: 24)
                        .onSubmit { execute() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)

                if query.isEmpty {
                    examplePromptsView
                } else {
                    searchResultsView
                }

                // Bottom bar with shortcuts
                if !query.isEmpty && !results.isEmpty {
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
        }
        .onChange(of: query) { _, newValue in
            let classification = classifier.classify(newValue)
            switch classification {
            case .naturalLang:
                // Don't show search results for natural language — will trigger agent on submit
                results = []
            case .search, .command:
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

    // MARK: - Agent Progress Inline View

    @ViewBuilder
    private var agentProgressInlineView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    // Topic
                    Text(agentState.topic)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    // Status line
                    HStack(spacing: 6) {
                        if agentState.isComplete {
                            Image(systemName: agentState.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(agentState.success ? .green : .red)
                                .font(.system(size: 14))
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if agentState.isComplete {
                            Text(agentState.statusText)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            ShinyText(text: agentState.statusText)
                        }
                    }
                }

                Spacer()

                // Stop button (only while running)
                if !agentState.isComplete {
                    Button {
                        onStopAgent?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop agent")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Example Prompts View

    @ViewBuilder
    private var examplePromptsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Try asking...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(examplePrompts, id: \.self) { prompt in
                    Button {
                        query = prompt
                        onAgent?(prompt)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue.opacity(0.7))
                                .frame(width: 20)
                            Text(prompt)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxHeight: 420)
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
        let classification = classifier.classify(query)
        if classification == .naturalLang {
            let command = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { return }
            query = ""
            onAgent?(command)
        } else if selectedIndex < results.count {
            executeResult(results[selectedIndex])
        }
    }

    private func executeSelectedWithModifier() {
        guard selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        onRevealInFinder?(result.id)
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
