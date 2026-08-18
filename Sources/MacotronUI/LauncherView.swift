// LauncherView.swift — SwiftUI root view for the launcher (command / app search)
import SwiftUI
import AppKit
import MacotronEngine

public struct SearchResult: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let type: ResultType
    public let nsImage: NSImage?
    public let commandArguments: [CommandArgumentSpec]

    public enum ResultType {
        case app
        case command
    }

    public init(
        id: String, title: String, subtitle: String, type: ResultType,
        nsImage: NSImage? = nil,
        commandArguments: [CommandArgumentSpec] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.nsImage = nsImage
        self.commandArguments = commandArguments
    }
}

public struct LauncherView: View {
    @ObservedObject private var prefs: LauncherPrefs
    @ObservedObject private var session: LauncherSession
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var selectedIndex = 0
    @State private var argValues: [String: String] = [:]
    @State private var argError: String?

    public var onExecuteCommand: ((String, [String: Any]) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onHeightChange: ((CGFloat) -> Void)?

    public init(
        prefs: LauncherPrefs = LauncherPrefs(),
        session: LauncherSession = LauncherSession(),
        onExecuteCommand: ((String, [String: Any]) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._prefs = ObservedObject(wrappedValue: prefs)
        self._session = ObservedObject(wrappedValue: session)
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

            if session.pendingArgs != nil {
                argumentForm
            } else {
                searchResultsView
            }

            if session.pendingArgs == nil && !query.isEmpty && !results.isEmpty {
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
        .onChange(of: session.pendingArgs?.commandId) { _, _ in
            if let pending = session.pendingArgs {
                prefill(pending.arguments)
            }
        }
        .background(KeyEventHandler(
            onArrowUp: { moveSelection(-1) },
            onArrowDown: { moveSelection(1) },
            onCmdReturn: { executeSelectedWithModifier() },
            onEscape: { handleEscape() }
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
        if let pending = session.pendingArgs {
            switch CommandArgumentResolver.resolve(specs: pending.arguments, raw: argValues) {
            case .success(let values):
                session.pendingArgs = nil
                onExecuteCommand?(pending.commandId, values)
            case .failure(.missingRequired(let name)):
                argError = "\(name) is required"
            case .failure(.invalidNumber(let name)):
                argError = "\(name) must be a number"
            case .failure(.invalidChoice(let name)):
                argError = "\(name) is not a valid choice"
            }
            return
        }
        if selectedIndex < results.count {
            executeResult(results[selectedIndex])
        }
    }

    private func executeSelectedWithModifier() {
        guard selectedIndex < results.count else { return }
        onRevealInFinder?(results[selectedIndex].id)
    }

    private func executeResult(_ result: SearchResult) {
        if result.type == .command, !result.commandArguments.isEmpty {
            session.pendingArgs = .init(
                commandId: result.id,
                title: result.title,
                arguments: result.commandArguments
            )
            prefill(result.commandArguments)
            query = ""
            results = []
            return
        }
        onExecuteCommand?(result.id, [:])
    }

    private func handleEscape() {
        if session.pendingArgs != nil {
            session.pendingArgs = nil
            argValues = [:]
            argError = nil
            query = ""
            results = onSearch?("") ?? []
            selectedIndex = 0
        }
    }

    private func prefill(_ specs: [CommandArgumentSpec]) {
        var seed: [String: String] = [:]
        for spec in specs {
            switch spec.defaultValue {
            case .string(let s): seed[spec.name] = s
            case .number(let n):
                seed[spec.name] = n.rounded() == n ? String(Int(n)) : String(n)
            case .bool(let b): seed[spec.name] = b ? "true" : "false"
            case .none: seed[spec.name] = ""
            }
        }
        argValues = seed
        argError = nil
    }

    @ViewBuilder
    private var argumentForm: some View {
        if let pending = session.pendingArgs {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.secondary)
                    Text(pending.title)
                        .font(.system(size: 14 * prefs.textScale, weight: .medium))
                    Spacer()
                    Text("esc")
                        .font(.system(size: 10, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(3)
                    Text("Back")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(pending.arguments, id: \.name) { spec in
                    argumentRow(spec)
                }

                if let argError {
                    Text(argError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func argumentRow(_ spec: CommandArgumentSpec) -> some View {
        switch spec.type {
        case "dropdown":
            Picker(spec.placeholder, selection: binding(for: spec.name)) {
                ForEach(spec.choices, id: \.value) { choice in
                    Text(choice.title).tag(choice.value)
                }
            }
            .labelsHidden()
        default:
            TextField(spec.placeholder, text: binding(for: spec.name))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { argValues[name] ?? "" },
            set: { argValues[name] = $0 }
        )
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
    var onEscape: (() -> Void)?

    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView()
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onCmdReturn = onCmdReturn
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onCmdReturn = onCmdReturn
        nsView.onEscape = onEscape
    }

    final class KeyEventNSView: NSView {
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onCmdReturn: (() -> Void)?
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command) && event.keyCode == 36 {
                onCmdReturn?()
                return
            }
            switch event.keyCode {
            case 126: onArrowUp?()
            case 125: onArrowDown?()
            case 53: onEscape?()
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
        case .command: return "terminal.fill"
        }
    }

    private func labelForType(_ type: SearchResult.ResultType) -> String {
        switch type {
        case .app: return "Application"
        case .command: return "Command"
        }
    }
}
