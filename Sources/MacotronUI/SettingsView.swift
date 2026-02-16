// SettingsView.swift — SwiftUI settings panel for API keys, hotkey, preferences
import SwiftUI

/// Validation status for the API key
public enum ValidationStatus: Equatable {
    case idle
    case checking
    case valid
    case invalidKey(String)
    case modelUnavailable
}

/// A configurable option exposed by a module
public struct ModuleOption: Identifiable {
    public let id: String
    public let key: String
    public let label: String
    public let type: String       // "string", "boolean", "number", "keybinding"
    public let defaultValue: Any
    public var currentValue: Any

    public init(key: String, label: String, type: String, defaultValue: Any, currentValue: Any) {
        self.id = key
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.currentValue = currentValue
    }
}

/// Summary info for a single module
public struct ModuleSummary: Identifiable {
    public let id: String           // filename
    public let filename: String
    public let title: String        // from macotron.module() or fallback to filename
    public let description: String
    public let options: [ModuleOption]
    public let events: [String]
    public let hotkeys: [String]
    public let hasErrors: Bool
    public let errorMessage: String?

    public init(filename: String, title: String = "", description: String,
                options: [ModuleOption] = [], events: [String] = [],
                hotkeys: [String] = [], hasErrors: Bool = false, errorMessage: String? = nil) {
        self.id = filename
        self.filename = filename
        self.title = title.isEmpty ? String(filename.dropLast(3)) : title  // strip .js if no title
        self.description = description
        self.options = options
        self.events = events
        self.hotkeys = hotkeys
        self.hasErrors = hasErrors
        self.errorMessage = errorMessage
    }
}

// MARK: - Settings State

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var apiKey: String = ""
    @Published public var selectedProvider: String = "anthropic"
    @Published public var launcherHotkey: String = "cmd+space"
    @Published public var showDockIcon: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var showAPIKeyRequired: Bool = false
    @Published public var validationStatus: ValidationStatus = .idle
    @Published public var moduleSummaries: [ModuleSummary] = []
    @Published public var requestedTab: Int?

    /// Read/write closures set by AppDelegate
    public var readAPIKey: (() -> String?)?
    public var writeAPIKey: ((String) -> Void)?
    public var readProvider: (() -> String)?
    public var writeProvider: ((String) -> Void)?
    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var readShowDockIcon: (() -> Bool)?
    public var writeShowDockIcon: ((Bool) -> Void)?
    public var readShowMenuBarIcon: (() -> Bool)?
    public var writeShowMenuBarIcon: ((Bool) -> Void)?
    /// Async validation closure: (key, provider) -> ValidationStatus
    public var validateAPIKey: ((_ key: String, _ provider: String) async -> ValidationStatus)?
    /// Closure to load module summaries
    public var loadModuleSummaries: (() -> [ModuleSummary])?
    /// Closure to save a module option value
    public var saveModuleOption: ((_ filename: String, _ key: String, _ value: Any) -> Void)?
    /// Closure to delete a module; returns true on success
    public var deleteModule: ((_ filename: String) -> Bool)?
    public var configDirURL: URL?

    private var apiKeyDebounce: Task<Void, Never>?

    public init() {}

    public func load() {
        selectedProvider = readProvider?() ?? "anthropic"
        apiKey = readAPIKey?() ?? ""
        launcherHotkey = readHotkey?() ?? "cmd+space"
        showDockIcon = readShowDockIcon?() ?? true
        showMenuBarIcon = readShowMenuBarIcon?() ?? true
        validationStatus = .idle
        refreshModules()
    }

    public func refreshModules() {
        moduleSummaries = loadModuleSummaries?() ?? []
    }

    /// Debounced save + validate. Called on every keystroke; waits for typing to stop.
    public func debouncedSaveAPIKey() {
        apiKeyDebounce?.cancel()
        let key = apiKey
        let provider = selectedProvider

        // Don't save or validate empty keys
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationStatus = .idle
            return
        }

        apiKeyDebounce = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            guard !Task.isCancelled else { return }

            writeAPIKey?(key)
            showAPIKeyRequired = false
            validationStatus = .checking

            if let validate = validateAPIKey {
                let result = await validate(key, provider)
                guard !Task.isCancelled else { return }
                self.validationStatus = result
            }
        }
    }

    public func saveHotkey() {
        writeHotkey?(launcherHotkey)
    }

    public func switchProvider(_ provider: String) {
        selectedProvider = provider
        writeProvider?(provider)
        apiKey = readAPIKey?() ?? ""
        validationStatus = .idle
    }

    public func toggleDockIcon(_ value: Bool) {
        showDockIcon = value
        writeShowDockIcon?(value)
    }

    public func toggleMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        writeShowMenuBarIcon?(value)
    }
}

// MARK: - Settings View

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var selectedTab: Int

    public init(state: SettingsState, initialTab: Int = 0) {
        self.state = state
        self._selectedTab = State(initialValue: initialTab)
    }

    private var modelName: String {
        switch state.selectedProvider {
        case "openai": return "gpt-4o"
        default: return "claude-opus-4-6"
        }
    }

    private var configDirPath: String {
        state.configDirURL?.path ?? "~/Library/Application Support/Macotron"
    }

    private let labelWidth: CGFloat = 140

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 2)
                .padding(.bottom, 6)

            Divider()

            switch selectedTab {
            case 1: modulesTab
            case 2: aiTab
            case 3: aboutTab
            default: generalTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.load()
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            } else if state.showAPIKeyRequired {
                selectedTab = 2
            }
        }
        .onChange(of: state.requestedTab) {
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tag: 0)
            tabButton(icon: "puzzlepiece.extension", label: "Modules", tag: 1)
            tabButton(icon: "cpu", label: "AI", tag: 2)
            tabButton(icon: "info.circle", label: "About", tag: 3)
            Spacer()
        }
    }

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 70, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(spacing: 0) {
            formRow("Macotron Hotkey") {
                HotkeyRecorderView(combo: $state.launcherHotkey) {
                    state.saveHotkey()
                }
            }
            .zIndex(1)
            .padding(.top, 8)

            formDivider

            formRow("Dock Icon") {
                Toggle("Show Dock icon", isOn: Binding(
                    get: { state.showDockIcon },
                    set: { state.toggleDockIcon($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(!state.showMenuBarIcon)
            }

            formRow("Menu Bar Icon") {
                Toggle("Show in menu bar", isOn: Binding(
                    get: { state.showMenuBarIcon },
                    set: { state.toggleMenuBarIcon($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(!state.showDockIcon)
            }

            formDivider

            formRow("Config Directory") {
                HStack(spacing: 8) {
                    Text(configDirPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open in Finder") {
                        if let url = state.configDirURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }

            Spacer()
        }
    }

    // MARK: - AI Tab

    private var aiTab: some View {
        VStack(spacing: 0) {
            if state.showAPIKeyRequired {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("An API key is required for the agent and auto-fix.")
                        .font(.callout)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            formRow("Provider") {
                Picker("", selection: Binding(
                    get: { state.selectedProvider },
                    set: { state.switchProvider($0) }
                )) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI").tag("openai")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.top, 8)

            formDivider

            formRow("API Key") {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $state.apiKey)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .onChange(of: state.apiKey) {
                            state.debouncedSaveAPIKey()
                        }

                    validationStatusView
                }
            }

            Spacer()
        }
    }

    // MARK: - Modules Tab

    private var modulesTab: some View {
        VStack(spacing: 0) {
            if state.moduleSummaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No modules installed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Use the prompt panel to create automation modules.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(state.moduleSummaries) { summary in
                            ModuleSummaryRow(summary: summary, state: state)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear {
            state.refreshModules()
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            if let bannerURL = Bundle.main.url(forResource: "banner", withExtension: "png"),
               let nsImage = NSImage(contentsOf: bannerURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360)
            }

            Text("AI-powered macOS automation. Describe what you want in plain English — Macotron's coding agent writes the scripts, tests them, and gets out of your way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Link(destination: URL(string: "https://github.com/statico/macotron")!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("github.com/statico/macotron")
                }
                .font(.callout)
            }

            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Form Helpers

    private func formRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var formDivider: some View {
        Divider()
            .padding(.leading, 24 + labelWidth + 12)
            .padding(.vertical, 4)
    }

    // MARK: - Validation Status

    @ViewBuilder
    private var validationStatusView: some View {
        switch state.validationStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Validating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("API key valid — \(modelName) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .invalidKey(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        case .modelUnavailable:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Key valid but \(modelName) not available.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Module Summary Row

struct ModuleSummaryRow: View {
    let summary: ModuleSummary
    @ObservedObject var state: SettingsState
    @State private var isExpanded: Bool = false
    @State private var showDeleteAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Expand/collapse button (only if module has options)
                if !summary.options.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Title
                    Text(summary.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    // Filename
                    Text(summary.filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    // Description
                    if !summary.description.isEmpty {
                        Text(summary.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Error indicator
                    if summary.hasErrors {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(summary.errorMessage ?? "Module has errors")
                                .font(.system(size: 11))
                                .lineLimit(2)
                        }
                        .foregroundStyle(.red)
                    }

                    // Badges for events and hotkeys
                    if !summary.events.isEmpty || !summary.hotkeys.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(summary.hotkeys, id: \.self) { hotkey in
                                badge(text: hotkey, color: .blue)
                            }
                            ForEach(summary.events, id: \.self) { event in
                                badge(text: event, color: .purple)
                            }
                        }
                    }
                }

                Spacer()

                // Delete button
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete module")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            // Expanded options section
            if isExpanded && !summary.options.isEmpty {
                Divider()
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.options) { option in
                        ModuleOptionRow(
                            option: option,
                            filename: summary.filename,
                            state: state
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .alert("Delete Module?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if state.deleteModule?(summary.filename) == true {
                    state.refreshModules()
                }
            }
        } message: {
            Text("Are you sure you want to delete \(summary.title)? This cannot be undone.")
        }
    }

    @ViewBuilder
    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(3)
    }
}

// MARK: - Module Option Row

struct ModuleOptionRow: View {
    let option: ModuleOption
    let filename: String
    @ObservedObject var state: SettingsState

    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var numberValue: String = ""
    @State private var hotkeyValue: String = ""

    var body: some View {
        Group {
            switch option.type {
            case "boolean":
                Toggle(option.label, isOn: $boolValue)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .onAppear { boolValue = (option.currentValue as? Bool) ?? false }
                    .onChange(of: boolValue) {
                        state.saveModuleOption?(filename, option.key, boolValue)
                        state.refreshModules()
                    }

            case "number":
                HStack(spacing: 8) {
                    Text(option.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("", text: $numberValue)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onAppear { numberValue = "\(option.currentValue)" }
                        .onSubmit {
                            if let num = Double(numberValue) {
                                state.saveModuleOption?(filename, option.key, num)
                                state.refreshModules()
                            }
                        }
                }

            case "keybinding":
                HStack(spacing: 8) {
                    Text(option.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    HotkeyRecorderView(combo: $hotkeyValue) {
                        state.saveModuleOption?(filename, option.key, hotkeyValue)
                        state.refreshModules()
                    }
                    .onAppear { hotkeyValue = (option.currentValue as? String) ?? "" }
                }

            default: // "string" and any other type
                HStack(spacing: 8) {
                    Text(option.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("", text: $stringValue)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onAppear { stringValue = (option.currentValue as? String) ?? "" }
                        .onSubmit {
                            state.saveModuleOption?(filename, option.key, stringValue)
                            state.refreshModules()
                        }
                }
            }
        }
    }
}
