// SettingsView.swift — SwiftUI settings panel for API keys, hotkey, preferences
import SwiftUI

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var apiKey: String = ""
    @Published public var launcherHotkey: String = "cmd+space"
    @Published public var showAPIKeyRequired: Bool = false

    /// Read/write closures set by AppDelegate
    public var readAPIKey: (() -> String?)?
    public var writeAPIKey: ((String) -> Void)?
    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var configDirURL: URL?

    public init() {}

    public func load() {
        apiKey = readAPIKey?() ?? ""
        launcherHotkey = readHotkey?() ?? "cmd+space"
    }

    public func saveAPIKey() {
        writeAPIKey?(apiKey)
    }

    public func saveHotkey() {
        writeHotkey?(launcherHotkey)
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var apiKeyVisible = false

    public init(state: SettingsState) {
        self.state = state
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

                    // AI API Key
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI API Key")
                            .font(.headline)
                        Text("Anthropic (Claude) API key for chat and snippet auto-fix.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            if apiKeyVisible {
                                TextField("sk-ant-...", text: $state.apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("sk-ant-...", text: $state.apiKey)
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

                        HStack {
                            Button("Save API Key") {
                                state.saveAPIKey()
                                state.showAPIKeyRequired = false
                            }
                            .disabled(state.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                            if !state.apiKey.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text("Key stored in macOS Keychain")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Launcher Hotkey
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Launcher Hotkey")
                            .font(.headline)
                        Text("Global keyboard shortcut to toggle the launcher. Examples: cmd+space, ctrl+opt+l")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("cmd+space", text: $state.launcherHotkey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 200)

                            Button("Apply") {
                                state.saveHotkey()
                            }
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
                            Text(state.configDirURL?.path() ?? "~/Documents/Macotron")
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
        .frame(width: 520, height: state.showAPIKeyRequired ? 440 : 400)
        .onAppear {
            state.load()
        }
    }
}
