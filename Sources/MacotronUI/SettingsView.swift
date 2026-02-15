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
    @Published public var showAPIKeyRequired: Bool = false
    @Published public var validationStatus: ValidationStatus = .idle

    /// Read/write closures set by AppDelegate
    public var readAPIKey: (() -> String?)?
    public var writeAPIKey: ((String) -> Void)?
    public var readProvider: (() -> String)?
    public var writeProvider: ((String) -> Void)?
    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    /// Async validation closure: (key, provider) -> ValidationStatus
    public var validateAPIKey: ((_ key: String, _ provider: String) async -> ValidationStatus)?
    public var configDirURL: URL?

    public init() {}

    public func load() {
        selectedProvider = readProvider?() ?? "anthropic"
        apiKey = readAPIKey?() ?? ""
        launcherHotkey = readHotkey?() ?? "cmd+space"
        validationStatus = .idle
    }

    public func saveAPIKey() {
        writeAPIKey?(apiKey)
        // Run validation async
        let key = apiKey
        let provider = selectedProvider
        validationStatus = .checking
        Task {
            if let validate = validateAPIKey {
                let result = await validate(key, provider)
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
        // Reload the API key for the new provider
        apiKey = readAPIKey?() ?? ""
        validationStatus = .idle
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var apiKeyVisible = false

    public init(state: SettingsState) {
        self.state = state
    }

    private var providerDisplayName: String {
        switch state.selectedProvider {
        case "openai": return "OpenAI"
        default: return "Anthropic"
        }
    }

    private var modelName: String {
        switch state.selectedProvider {
        case "openai": return "gpt-4o"
        default: return "claude-opus-4-6"
        }
    }

    private var apiKeyPlaceholder: String {
        switch state.selectedProvider {
        case "openai": return "sk-..."
        default: return "sk-ant-..."
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Macotron Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // API Key warning
                    if state.showAPIKeyRequired {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("An AI API key is required for chat and auto-fix features.")
                                .font(.callout)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // AI Provider
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI Provider")
                            .font(.headline)
                        Text("Macotron selects the best model for each provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Provider", selection: Binding(
                            get: { state.selectedProvider },
                            set: { state.switchProvider($0) }
                        )) {
                            Text("Anthropic").tag("anthropic")
                            Text("OpenAI").tag("openai")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)

                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Model: \(modelName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // AI API Key
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(providerDisplayName) API Key")
                            .font(.headline)
                        Text("Used for chat and snippet auto-fix.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if apiKeyVisible {
                                TextField(apiKeyPlaceholder, text: $state.apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField(apiKeyPlaceholder, text: $state.apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }
                            Button {
                                apiKeyVisible.toggle()
                            } label: {
                                Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack(spacing: 6) {
                            Button("Save API Key") {
                                state.saveAPIKey()
                                state.showAPIKeyRequired = false
                            }
                            .disabled(state.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                            validationStatusView
                        }
                    }

                    Divider()

                    // Launcher Hotkey
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Launcher Hotkey")
                            .font(.headline)
                        Text("Click to record a new global keyboard shortcut.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HotkeyRecorderView(combo: $state.launcherHotkey) {
                            state.saveHotkey()
                        }
                    }

                    Divider()

                    // Config Directory
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Config Directory")
                            .font(.headline)
                        Text("Snippets, commands, and configuration files are stored here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text(state.configDirURL?.path() ?? "~/Library/Application Support/Macotron")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button("Open in Finder") {
                                if let url = state.configDirURL {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 520, height: state.showAPIKeyRequired ? 480 : 440)
        .onAppear {
            state.load()
        }
    }

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
                Text("Key valid — \(modelName) available")
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
                Text("Key valid but \(modelName) not available. Update Macotron to use the latest models.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
