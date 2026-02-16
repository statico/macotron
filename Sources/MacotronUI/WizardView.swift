// WizardView.swift — First-run setup wizard (Welcome → Permissions → AI Provider → Ready)
import SwiftUI

public enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case permissions
    case aiProvider
    case ready
}

@MainActor
public final class WizardState: ObservableObject {
    @Published public var currentStep: WizardStep = .welcome
    @Published public var selectedProvider: String = "anthropic"
    @Published public var apiKey: String = ""
    @Published public var validationStatus: ValidationStatus = .idle

    // Permission statuses (refreshed on step change)
    @Published public var accessibilityGranted: Bool = false
    @Published public var inputMonitoringGranted: Bool = false
    @Published public var screenRecordingGranted: Bool = false

    /// When true, only show the permissions step and close on Next/Skip
    public var permissionsOnly: Bool = false

    // Closures wired by AppDelegate
    public var writeAPIKey: ((String) -> Void)?
    public var writeProvider: ((String) -> Void)?
    public var validateAPIKey: ((_ key: String, _ provider: String) async -> ValidationStatus)?
    public var checkAccessibility: (() -> Bool)?
    public var checkInputMonitoring: (() -> Bool)?
    public var checkScreenRecording: (() -> Bool)?
    public var requestAccessibility: (() -> Void)?
    public var requestInputMonitoring: (() -> Void)?
    public var requestScreenRecording: (() -> Void)?
    public var onComplete: (() -> Void)?

    private var validationTask: Task<Void, Never>?

    public init() {}

    public func refreshPermissions() {
        accessibilityGranted = checkAccessibility?() ?? false
        inputMonitoringGranted = checkInputMonitoring?() ?? false
        screenRecordingGranted = checkScreenRecording?() ?? false
    }

    public func debouncedValidate() {
        validationTask?.cancel()
        let key = apiKey
        let provider = selectedProvider

        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationStatus = .idle
            return
        }

        validationTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            validationStatus = .checking
            if let validate = validateAPIKey {
                let result = await validate(key, provider)
                guard !Task.isCancelled else { return }
                validationStatus = result
            }
        }
    }

    public func saveAndComplete() {
        writeProvider?(selectedProvider)
        if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            writeAPIKey?(apiKey)
        }
        onComplete?()
    }
}

// MARK: - Wizard View

public struct WizardView: View {
    @ObservedObject var state: WizardState

    public init(state: WizardState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch state.currentStep {
                case .welcome: welcomeStep
                case .permissions: permissionsStep
                case .aiProvider: aiProviderStep
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation bar
            HStack {
                if state.currentStep != .welcome && !state.permissionsOnly {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if let prev = WizardStep(rawValue: state.currentStep.rawValue - 1) {
                                state.currentStep = prev
                            }
                        }
                    }
                }

                Spacer()

                if state.currentStep == .permissions {
                    Button("Skip") {
                        advance()
                    }
                    .foregroundStyle(.secondary)
                }

                if state.currentStep == .ready {
                    Button("Open Macotron") {
                        state.saveAndComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") {
                        advance()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private func advance() {
        // In permissions-only mode, close after the permissions step
        if state.permissionsOnly && state.currentStep == .permissions {
            state.onComplete?()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            if let next = WizardStep(rawValue: state.currentStep.rawValue + 1) {
                state.currentStep = next
                if next == .permissions {
                    state.refreshPermissions()
                }
            }
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            if let bannerURL = Bundle.main.url(forResource: "banner", withExtension: "png"),
               let nsImage = NSImage(contentsOf: bannerURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Welcome to Macotron")
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("AI-powered macOS automation. Describe what you want, and Macotron writes the scripts for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 8) {
                exampleRow(icon: "rectangle.split.2x1", text: "Set up keyboard shortcuts to tile windows")
                exampleRow(icon: "safari", text: "Route YouTube links to Safari automatically")
                exampleRow(icon: "chart.bar", text: "Show CPU and memory in the menu bar")
                exampleRow(icon: "lightbulb.fill", text: "Flash your USB light when the camera turns on")
                exampleRow(icon: "bell.fill", text: "Get notified when CPU temperature gets too high")
                exampleRow(icon: "doc.text.magnifyingglass", text: "Take a screenshot and summarize it with AI")

                Text("and lots more...")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.leading, 34)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private func exampleRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions Step

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Permissions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Macotron works best with these permissions. You can enable them now or later.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Window management and global hotkeys",
                    granted: state.accessibilityGranted,
                    action: "openAccessibilitySettings"
                )
                permissionRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    description: "Register global keyboard shortcuts",
                    granted: state.inputMonitoringGranted,
                    action: "openInputMonitoringSettings"
                )
                permissionRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "Screen Recording",
                    description: "Take screenshots for AI analysis",
                    granted: state.screenRecordingGranted,
                    action: "openScreenRecordingSettings"
                )
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private func permissionRow(
        icon: String, title: String, description: String,
        granted: Bool, action: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings") {
                    openPermissionSettings(action)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    private func openPermissionSettings(_ action: String) {
        switch action {
        case "openAccessibilitySettings":
            // AXIsProcessTrustedWithOptions with prompt adds the app to the list AND opens settings
            state.requestAccessibility?()
        case "openInputMonitoringSettings":
            state.requestInputMonitoring?()
        case "openScreenRecordingSettings":
            // CGRequestScreenCaptureAccess adds the app to the list AND shows a prompt
            state.requestScreenRecording?()
        default:
            return
        }

        // Refresh permissions after a delay (user may grant in System Settings)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            state.refreshPermissions()
        }
    }

    // MARK: - AI Provider Step

    private var aiProviderStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("AI Provider")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Macotron uses AI to write automation scripts. Enter your API key to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 12) {
                // Provider picker
                HStack(spacing: 12) {
                    Text("Provider")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)

                    Picker("", selection: $state.selectedProvider) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .onChange(of: state.selectedProvider) {
                        state.validationStatus = .idle
                    }
                }

                // API key input
                HStack(alignment: .top, spacing: 12) {
                    Text("API Key")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: $state.apiKey)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 50)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                            .onChange(of: state.apiKey) {
                                state.debouncedValidate()
                            }

                        wizardValidationStatus
                    }
                }
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private var wizardValidationStatus: some View {
        switch state.validationStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Validating...").font(.caption).foregroundStyle(.secondary)
            }
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text("API key valid").font(.caption).foregroundStyle(.secondary)
            }
        case .invalidKey(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        case .modelUnavailable:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text("Key valid but preferred model unavailable").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Ready Step

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Open the prompt panel with your hotkey and describe what you want to automate. Macotron will handle the rest.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .padding(24)
    }
}
