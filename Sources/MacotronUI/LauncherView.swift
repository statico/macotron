// LauncherView.swift — SwiftUI root view for the launcher (command / app search)
import SwiftUI
import AppKit
import MacotronEngine

@MainActor
public final class LauncherFrame: ObservableObject {
    @Published public var size: CGSize

    public init(size: CGSize = CGSize(width: 750, height: 48)) {
        self.size = size
    }
}

public struct SearchResult: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let type: ResultType
    public let nsImage: NSImage?
    public let commandArguments: [CommandArgumentSpec]
    public let shortcut: String
    public let kind: String
    public let isFavorite: Bool
    /// Where the row lives on disk, when it is a file: what Cmd-Return reveals.
    public let path: String
    /// Draws an orange warning badge in place of the favorite star.
    public let warning: Bool

    public enum ResultType {
        case app
        case command
        case plugin
    }

    public init(
        id: String, title: String, subtitle: String, type: ResultType,
        nsImage: NSImage? = nil,
        commandArguments: [CommandArgumentSpec] = [],
        shortcut: String = "",
        kind: String = "",
        isFavorite: Bool = false,
        path: String = "",
        warning: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.nsImage = nsImage
        self.commandArguments = commandArguments
        self.shortcut = shortcut
        self.kind = kind
        self.isFavorite = isFavorite
        self.path = path
        self.warning = warning
    }
}

extension SearchResult {
    /// One screenful, best match first.
    ///
    /// `late` names the rows a live provider answered a keystroke behind — file
    /// hits, mostly. They used to sort below everything, which put a contact who
    /// shares three letters with the query above the folder the user named, and
    /// pushed files off the end entirely whenever apps filled the list. So they
    /// are scored like everything else, and only lose ties: an app whose name
    /// was actually typed still leads a file that matches it just as well.
    public static func ranked(
        query: String,
        rows: [SearchResult],
        late: Set<String> = [],
        uses: [String: Int] = [:],
        limit: Int = 20
    ) -> [SearchResult] {
        // Score once per row rather than twice per comparison: sorting otherwise
        // re-runs the matcher O(n log n) times on every keystroke.
        let action: (ResultType) -> Bool = { $0 == .command || $0 == .plugin }
        let scored = rows.enumerated()
            .map { i, r in
                (r, (FuzzyMatch.best(query: query, targets: [r.title, r.subtitle]) ?? 0)
                    // What gets picked is evidence the matcher cannot see. The
                    // cap keeps a habit from drowning an exact match forever:
                    // five picks buys as much as typing the name's prefix.
                    + 8 * min(uses[r.id] ?? 0, 5)
                    - (late.contains(r.id) ? buried(r.path) : 0), i)
            }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                let aLate = late.contains(a.0.id), bLate = late.contains(b.0.id)
                if aLate != bLate { return bLate }
                if action(a.0.type) != action(b.0.type) { return action(a.0.type) }
                // Sorting is not stable, so the order the provider chose — which
                // is where the count of how often a file was opened lives — needs
                // saying out loud to survive a tie.
                return a.2 < b.2
            }
        return Array(scored.prefix(limit).map(\.0))
    }

    /// How far off the beaten track a file is. Names alone put the folder
    /// "Application" five levels inside a photo library above /Applications,
    /// because it is one letter shorter; the path is the only thing that knows
    /// which one the user meant.
    private static func buried(_ path: String) -> Int {
        path.isEmpty ? 0 : 4 * max(0, path.split(separator: "/").count - 1)
    }
}


public struct LauncherView: View {
    @ObservedObject private var prefs: LauncherPrefs
    @ObservedObject private var session: LauncherSession
    @ObservedObject private var windowFrame: LauncherFrame
    @State private var results: [SearchResult] = []
    @State private var appliedQuery = ""
    @State private var selectedIndex = 0
    @State private var argValues: [String: String] = [:]
    @State private var argError: String?
    @State private var isRecordingShortcut = false
    @FocusState private var focusedArg: String?

    public var onExecuteCommand: ((String, [String: Any]) -> Void)?
    public var onRevealInFinder: ((String) -> Void)?
    public var onSearch: ((String) -> [SearchResult])?
    public var onAssignShortcut: ((String, String, String) -> Void)?
    public var onToggleFavorite: ((String) -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onHeightChange: ((CGFloat) -> Void)?

    public init(
        prefs: LauncherPrefs = LauncherPrefs(),
        session: LauncherSession = LauncherSession(),
        windowFrame: LauncherFrame = LauncherFrame(),
        onExecuteCommand: ((String, [String: Any]) -> Void)? = nil,
        onRevealInFinder: ((String) -> Void)? = nil,
        onSearch: ((String) -> [SearchResult])? = nil,
        onAssignShortcut: ((String, String, String) -> Void)? = nil,
        onToggleFavorite: ((String) -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._prefs = ObservedObject(wrappedValue: prefs)
        self._session = ObservedObject(wrappedValue: session)
        self._windowFrame = ObservedObject(wrappedValue: windowFrame)
        self.onExecuteCommand = onExecuteCommand
        self.onRevealInFinder = onRevealInFinder
        self.onSearch = onSearch
        self.onAssignShortcut = onAssignShortcut
        self.onToggleFavorite = onToggleFavorite
        self.onOpenSettings = onOpenSettings
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            if session.pendingArgs == nil {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 20 * prefs.textScale))
                        .frame(width: 24, height: 24)

                    LauncherQueryField(text: $session.query, fontSize: 20 * prefs.textScale, onSubmit: execute)
                        .frame(height: 24)
                }
                .padding(.horizontal, 16)
                .frame(height: LauncherPlacement.searchBarHeight(showingList: !queryIsEmpty || !results.isEmpty))
                .layoutPriority(1)

                if !queryIsEmpty || !results.isEmpty {
                    Divider().opacity(0.5)
                }
            }

            if session.pendingArgs != nil {
                argumentForm
            } else if !queryIsEmpty || !results.isEmpty {
                searchResultsView
                    .frame(minHeight: 0, maxHeight: .infinity)
            }

            if session.pendingArgs == nil && !results.isEmpty {
                Divider().opacity(0.5)
                if isRecordingShortcut, selectedIndex < results.count {
                    HStack(spacing: 16) {
                        Text("Press a shortcut for \(results[selectedIndex].title)")
                            .font(.system(size: 10 * prefs.textScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        shortcutHint(keys: ["esc"], label: "Cancel")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: LauncherPlacement.footerHeight(scale: prefs.textScale))
                    .layoutPriority(1)
                } else {
                    HStack(spacing: 16) {
                        shortcutHint(keys: ["return"], label: "Open")
                        shortcutHint(keys: ["cmd", "return"], label: "Reveal in Finder")
                        shortcutHint(keys: ["cmd", "K"], label: "Set shortcut")
                        if selectedIndex < results.count {
                            shortcutHint(
                                keys: ["cmd", "S"],
                                label: results[selectedIndex].isFavorite ? "Unfavorite" : "Favorite"
                            )
                        }
                        shortcutHint(keys: ["cmd", ";"], label: "Settings")
                        Spacer()
                        shortcutHint(keys: ["esc"], label: "Close")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: LauncherPlacement.footerHeight(scale: prefs.textScale))
                    .layoutPriority(1)
                }
            }
        }
        .frame(width: windowFrame.size.width, height: windowFrame.size.height, alignment: .top)
        .clipped()
        .task(id: SearchKey(query: session.query, revision: session.revision)) {
            if let delay = Self.searchDelay(query: session.query, applied: appliedQuery) {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            applySearch(session.query)
        }
        .onAppear {
            onHeightChange?(desiredHeight)
        }
        .onChange(of: session.pendingArgs?.commandId) { _, _ in
            if let pending = session.pendingArgs {
                prefill(pending.arguments)
                DispatchQueue.main.async {
                    focusedArg = pending.arguments.first?.name
                }
            } else {
                focusedArg = nil
            }
            onHeightChange?(desiredHeight)
        }
        .background {
            KeyEventHandler(
                onArrowUp: { moveSelection(-1) },
                onArrowDown: { moveSelection(1) },
                onCmdReturn: { executeSelectedWithModifier() },
                onCmdK: { beginShortcutRecording() },
                onCmdS: { toggleSelectedFavorite() },
                onCmdSemicolon: { onOpenSettings?() },
                onEscape: { handleEscape() },
                onRecordedCombo: { saveRecordedShortcut($0) },
                onClearShortcut: { saveRecordedShortcut("") },
                interceptListKeys: session.pendingArgs == nil && !isRecordingShortcut,
                isRecording: isRecordingShortcut
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: desiredHeight) { _, height in
            onHeightChange?(height)
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if results.isEmpty {
            Text("No results")
                .font(.system(size: 12 * prefs.textScale))
                .foregroundStyle(.tertiary)
                .frame(
                    maxWidth: .infinity,
                    minHeight: LauncherPlacement.emptyStateHeight(scale: prefs.textScale)
                )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LauncherPlacement.rowSpacing) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, isSelected: index == selectedIndex,
                                      textScale: prefs.textScale)
                                .id(result.id)
                                .onTapGesture { executeResult(result) }
                        }
                    }
                    .padding(.vertical, LauncherPlacement.listPadding / 2)
                    .padding(.horizontal, 6)
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selectedIndex) { _, newIndex in
                    // No anchor: scroll only far enough to bring the row into
                    // view. Anchoring pins the selection to one edge and moves
                    // the list under it on every keypress.
                    if newIndex < results.count {
                        proxy.scrollTo(results[newIndex].id)
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
        let result = results[selectedIndex]
        onRevealInFinder?(result.path.isEmpty ? result.id : result.path)
    }

    private func executeResult(_ result: SearchResult) {
        if result.type == .command, !result.commandArguments.isEmpty {
            session.pendingArgs = .init(
                commandId: result.id,
                title: result.title,
                arguments: result.commandArguments
            )
            prefill(result.commandArguments)
            session.query = ""
            results = []
            return
        }
        onExecuteCommand?(result.id, [:])
    }

    private func handleEscape() -> Bool {
        if isRecordingShortcut {
            isRecordingShortcut = false
            return true
        }
        guard session.pendingArgs != nil else { return false }
        session.pendingArgs = nil
        argValues = [:]
        argError = nil
        session.query = ""
        results = []
        selectedIndex = 0
        return true
    }

    private var queryIsEmpty: Bool {
        session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Host size comes from the panel. Extra rows scroll inside the list.
    private var desiredHeight: CGFloat {
        LauncherPlacement.panelHeight(
            resultCount: results.count,
            queryEmpty: queryIsEmpty,
            argumentCount: session.pendingArgs.map(\.arguments.count),
            textScale: prefs.textScale,
            visible: LauncherPlacement.currentVisible()
        )
    }

    /// What `.task(id:)` watches: a keystroke or a late provider answer both
    /// have to re-run the search, and the sleep below cancels with the old one.
    private struct SearchKey: Equatable {
        let query: String
        let revision: Int
    }

    /// nil runs the search now. Typing waits, so a fast typist searches once
    /// instead of once per letter; opening the launcher and the first letter
    /// after it must not, or the launcher feels asleep. A refresh of the query
    /// already on screen is not typing either.
    static func searchDelay(query: String, applied: String) -> Duration? {
        guard !applied.isEmpty, query != applied else { return nil }
        return .milliseconds(80)
    }

    private func applySearch(_ query: String) {
        let rows = onSearch?(query) ?? []
        selectedIndex = Self.preservedSelection(
            query: query, applied: appliedQuery,
            selected: selectedIndex, old: results, new: rows)
        results = rows
        appliedQuery = query
        isRecordingShortcut = false
    }

    /// A refresh of the query already on screen — a late provider answer, the
    /// watchdog — must not steal the row the user arrowed to. A new query, or a
    /// selection still resting on the top row, starts back at the top.
    static func preservedSelection(query: String, applied: String, selected: Int,
                                   old: [SearchResult], new: [SearchResult]) -> Int {
        guard query == applied, selected > 0, selected < old.count,
              let idx = new.firstIndex(where: { $0.id == old[selected].id })
        else { return 0 }
        return idx
    }

    private func beginShortcutRecording() {
        guard session.pendingArgs == nil, selectedIndex < results.count else { return }
        isRecordingShortcut = true
    }

    private func toggleSelectedFavorite() {
        guard session.pendingArgs == nil, selectedIndex < results.count else { return }
        let id = results[selectedIndex].id
        onToggleFavorite?(id)
        applySearch(session.query)
        if let idx = results.firstIndex(where: { $0.id == id }) {
            selectedIndex = idx
        } else if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }

    private func saveRecordedShortcut(_ combo: String) {
        guard selectedIndex < results.count else {
            isRecordingShortcut = false
            return
        }
        let id = results[selectedIndex].id
        onAssignShortcut?(id, combo, results[selectedIndex].title)
        isRecordingShortcut = false
        applySearch(session.query)
        if let idx = results.firstIndex(where: { $0.id == id }) {
            selectedIndex = idx
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
            .onAppear {
                focusedArg = pending.arguments.first?.name
            }
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
            .pickerStyle(.segmented)
            .focused($focusedArg, equals: spec.name)
        default:
            TextField(spec.placeholder, text: binding(for: spec.name))
                .textFieldStyle(.roundedBorder)
                .focused($focusedArg, equals: spec.name)
                .onSubmit { execute() }
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
            ForEach(KeyCombo.glyphs(keys.joined(separator: "+")), id: \.self) { key in
                Text(key)
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

}

/// AppKit field so window resizes don't kill the field editor (SwiftUI TextField does).
private struct LauncherQueryField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search commands and apps..."
        field.font = .systemFont(ofSize: fontSize)
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        field.font = .systemFont(ofSize: fontSize)
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

struct KeyEventHandler: NSViewRepresentable {
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onCmdReturn: () -> Void
    var onCmdK: () -> Void
    var onCmdS: (() -> Void)?
    var onCmdSemicolon: (() -> Void)?
    var onEscape: (() -> Bool)?
    var onRecordedCombo: ((String) -> Void)?
    var onClearShortcut: (() -> Void)?
    var interceptListKeys: Bool = true
    var isRecording: Bool = false

    func makeNSView(context: Context) -> KeyEventNSView {
        let view = KeyEventNSView()
        view.onKey = consume
        return view
    }

    func updateNSView(_ nsView: KeyEventNSView, context: Context) {
        nsView.onKey = consume
    }

    /// cmd+<key> shortcuts, keyed by the unmodified character.
    private var cmdKeys: [String: () -> Void] {
        ["k": onCmdK, "s": { onCmdS?() }, ";": { onCmdSemicolon?() }]
    }

    /// True swallows the event; false lets it reach the search field.
    func consume(_ event: NSEvent) -> Bool {
        if isRecording {
            if event.keyCode == 53 { return onEscape?() ?? true }
            if event.keyCode == 51 || event.keyCode == 117 {
                onClearShortcut?()
            } else if let combo = KeyCombo.combo(from: event) {
                onRecordedCombo?(combo)
            }
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased()
        if interceptListKeys {
            if flags.contains(.command), event.keyCode == 36 {
                onCmdReturn()
                return true
            }
            if flags.contains(.command), flags.isDisjoint(with: [.shift, .option, .control]),
               let action = chars.flatMap({ cmdKeys[$0] }) {
                action()
                return true
            }
            // Emacs-style list navigation.
            if flags.contains(.control), !flags.contains(.command), chars == "p" || chars == "n" {
                if chars == "p" { onArrowUp() } else { onArrowDown() }
                return true
            }
        }
        switch event.keyCode {
        case 126 where interceptListKeys: onArrowUp(); return true
        case 125 where interceptListKeys: onArrowDown(); return true
        case 53: return onEscape?() ?? false
        default: return false
        }
    }

    final class KeyEventNSView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window == self.window else { return event }
                return self.onKey?(event) == true ? nil : event
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
                    .renderingMode(nsImage.isTemplate ? .template : .original)
                    .foregroundStyle(.primary)
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
                if result.warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9 * textScale))
                        .foregroundStyle(.orange)
                } else if result.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9 * textScale))
                        .foregroundStyle(.yellow)
                }
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 12 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !result.shortcut.isEmpty {
                HStack(spacing: 2) {
                    ForEach(KeyCombo.glyphs(result.shortcut), id: \.self) { part in
                        Text(part)
                            .font(.system(size: 10 * textScale, weight: .medium, design: .rounded))
                    }
                }
                .foregroundStyle(.tertiary)
            } else {
                Text(labelForType(result.type))
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: LauncherPlacement.rowHeight(scale: textScale), alignment: .leading)
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
        case .plugin: return "square.grid.2x2.fill"
        }
    }

    private func labelForType(_ type: SearchResult.ResultType) -> String {
        switch type {
        case .app: return "Application"
        case .command: return "Command"
        case .plugin: return result.kind.isEmpty ? "Plugin" : result.kind
        }
    }
}

public final class PinnedHostingView<Content: View>: NSHostingView<Content> {
    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public override func layout() {
        super.layout()
        pinToSuperview()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(superview?.bounds.size ?? newSize)
    }

    private func pinToSuperview() {
        guard let s = superview, frame != s.bounds else { return }
        frame = s.bounds
    }
}
