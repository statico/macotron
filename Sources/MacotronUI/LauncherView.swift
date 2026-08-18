// LauncherView.swift — SwiftUI root view for the launcher (command / app search)
import SwiftUI
import AppKit

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
        case module
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

public struct LauncherView: View {
    @ObservedObject private var prefs: LauncherPrefs
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0

    public var onExecuteCommand: ((String) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onHeightChange: ((CGFloat) -> Void)?

    public init(
        prefs: LauncherPrefs = LauncherPrefs(),
        onExecuteCommand: ((String) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._prefs = ObservedObject(wrappedValue: prefs)
        self.onExecuteCommand = onExecuteCommand
        self.onRevealInFinder = onRevealInFinder
        self.onSearch = onSearch
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 20 * prefs.textScale))
                    .frame(width: 24, height: 24)

                TextField("Search commands and apps...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20 * prefs.textScale, weight: .regular))
                    .frame(height: 24)
                    .onSubmit { execute() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.5)

            searchResultsView

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
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: query) { _, newValue in
            results = onSearch?(newValue) ?? []
            selectedIndex = 0
        }
        .onAppear {
            results = onSearch?("") ?? []
        }
        .background(KeyEventHandler(
            onArrowUp: { moveSelection(-1) },
            onArrowDown: { moveSelection(1) },
            onCmdReturn: { executeSelectedWithModifier() }
        ))
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ViewHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(ViewHeightKey.self) { height in
            onHeightChange?(height)
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if results.isEmpty {
            Text(query.isEmpty ? "Type to search" : "No results")
                .font(.system(size: 12 * prefs.textScale))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, isSelected: index == selectedIndex,
                                      textScale: prefs.textScale)
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
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < results.count {
            selectedIndex = newIndex
        }
    }

    private func execute() {
        if selectedIndex < results.count {
            executeResult(results[selectedIndex])
        }
    }

    private func executeSelectedWithModifier() {
        guard selectedIndex < results.count else { return }
        onRevealInFinder?(results[selectedIndex].id)
    }

    private func executeResult(_ result: SearchResult) {
        onExecuteCommand?(result.id)
    }

    @ViewBuilder
    private func shortcutHint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(keySymbol(key))
                    .font(.system(size: 10 * prefs.textScale, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(3)
            }
            Text(label)
                .font(.system(size: 10 * prefs.textScale))
                .foregroundStyle(.secondary)
        }
    }

    private func keySymbol(_ key: String) -> String {
        switch key {
        case "cmd": return "\u{2318}"
        case "return": return "\u{23CE}"
        case "esc": return "\u{238B}"
        default: return key
        }
    }
}

private struct ViewHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
            if event.modifierFlags.contains(.command) && event.keyCode == 36 {
                onCmdReturn?()
                return
            }
            switch event.keyCode {
            case 126: onArrowUp?()
            case 125: onArrowDown?()
            default: super.keyDown(with: event)
            }
        }
    }
}

struct ResultRow: View {
    let result: SearchResult
    var isSelected: Bool = false
    var textScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 10) {
            if let nsImage = result.nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 20 * textScale, height: 20 * textScale)
                    .cornerRadius(4)
            } else {
                Image(systemName: iconForType(result.type))
                    .font(.system(size: 11 * textScale))
                    .frame(width: 20 * textScale, height: 20 * textScale)
                    .background(.quaternary)
                    .cornerRadius(4)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(result.title)
                    .font(.system(size: 13 * textScale, weight: .medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 12 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(labelForType(result.type))
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
        case .module: return "chevron.left.forwardslash.chevron.right"
        case .action: return "bolt.fill"
        }
    }

    private func labelForType(_ type: SearchResult.ResultType) -> String {
        switch type {
        case .app: return "Application"
        case .file: return "File"
        case .command: return "Command"
        case .module: return "Module"
        case .action: return "Action"
        }
    }
}
