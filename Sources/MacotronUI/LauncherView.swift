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

public struct LauncherView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var mode: LauncherMode = .search
    @State private var selectedIndex = 0

    private let classifier = NLClassifier()
    public var onExecuteCommand: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?

    public init(onExecuteCommand: ((String) -> Void)? = nil,
                onSearch: ((String) -> [SearchResult])? = nil) {
        self.onExecuteCommand = onExecuteCommand
        self.onSearch = onSearch
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
                // Chat mode placeholder
                VStack {
                    Text("AI chat mode")
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                }
                .frame(maxHeight: 400)
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

    private func execute() {
        if mode == .chat {
            onExecuteCommand?(query)
        } else if let result = results.first {
            executeResult(result)
        }
    }

    private func executeResult(_ result: SearchResult) {
        onExecuteCommand?(result.id)
    }
}

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
