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

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var apiKey: String = ""
    @Published public var selectedProvider: String = "anthropic"
    @Published public var launcherHotkey: String = "cmd+space"
    @Published public var showDockIcon: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var showAPIKeyRequired: Bool = false
    @Published public var validationStatus: ValidationStatus = .idle

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
    @State private var selectedTab: Int = 0

    public init(state: SettingsState) {
        self.state = state
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
            case 1: aiTab
            default: generalTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.load()
            if state.showAPIKeyRequired {
                selectedTab = 1
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tag: 0)
            tabButton(icon: "cpu", label: "AI", tag: 1)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
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
                    Text("An API key is required for chat and auto-fix.")
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
