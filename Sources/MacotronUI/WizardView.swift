// WizardView.swift — First-run setup: pick plugins folder, grant permissions
import AppKit
import MacotronEngine
import SwiftUI

public enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case folder
    case catalog
    case permissions
    case ready
}

@MainActor
public final class WizardState: ObservableObject {
    /// The steps to show. First run shows all of them; a permissions-only run
    /// shows just the permissions step.
    @Published public var steps: [WizardStep] = WizardStep.allCases
    @Published public var stepIndex: Int = 0
    @Published public var pluginsURL: URL?

    public var pickFolder: (() -> URL?)?
    public var initWorkspace: ((URL) -> Bool)?
    public var onComplete: (() -> Void)?

    public init() {}

    public var currentStep: WizardStep {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : .welcome
    }

    public var isFirstStep: Bool { stepIndex == 0 }
    public var isLastStep: Bool { stepIndex >= steps.count - 1 }

    /// Start a full first-run walkthrough.
    public func startFullSetup() {
        steps = WizardStep.allCases
        stepIndex = 0
    }

    /// Start a short run that only asks for the missing permissions.
    public func startPermissionsOnly() {
        steps = [.permissions]
        stepIndex = 0
    }

    public func chooseFolder() {
        guard let url = pickFolder?() else { return }
        pluginsURL = url
    }

    public func finish() {
        onComplete?()
    }
}

public struct WizardView: View {
    @ObservedObject var state: WizardState
    @ObservedObject var permissions: SettingsState

    public init(state: WizardState, permissions: SettingsState) {
        self.state = state
        self.permissions = permissions
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.currentStep {
                case .welcome: welcomeStep
                case .folder: folderStep
                case .catalog: catalogStep
                case .permissions: permissionsStep
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .catalogInstaller(state: permissions)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !state.isFirstStep {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.stepIndex -= 1
                    }
                }
            }
            Spacer()
            if state.isLastStep {
                Button(finishLabel) {
                    state.finish()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") {
                    if state.currentStep == .folder, let url = state.pluginsURL {
                        guard state.initWorkspace?(url) == true else { return }
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.stepIndex += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.currentStep == .folder && state.pluginsURL == nil)
            }
        }
        .overlay {
            if state.steps.count > 1 {
                stepDots
            }
        }
        .padding(16)
    }

    private var finishLabel: String {
        state.currentStep == .permissions ? "Done" : "Open Macotron"
    }

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(state.steps.indices, id: \.self) { index in
                Circle()
                    .fill(index == state.stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        stepLayout {
            if let bannerURL = Bundle.main.url(forResource: "banner", withExtension: "png"),
               let nsImage = NSImage(contentsOf: bannerURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Welcome to Macotron")
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("Macotron is a thin macOS host for JavaScript plugins. Pick a folder for your plugins, then edit them with your favorite AI coding agent.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var folderStep: some View {
        stepLayout {
            stepHeader(
                icon: "folder",
                title: "Plugins Folder",
                subtitle: "Choose a directory Macotron will use for plugins. The app will create plugins/, settings.json, and agent docs there."
            )

            if let url = state.pluginsURL {
                Text(url.path(percentEncoded: false))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Text("No folder selected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button("Choose Folder…") {
                    state.chooseFolder()
                }

                if let url = state.pluginsURL {
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var catalogStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeader(
                icon: "puzzlepiece.extension",
                title: "Add Some Plugins",
                subtitle: "Here are some example plugins to get you started. You can add more later from Settings, or make your own."
            )
            .frame(maxWidth: .infinity)
            CatalogBrowser(
                plugins: permissions.catalogPlugins,
                installedNames: permissions.installedPluginNames,
                onAdd: { permissions.addBuiltIn($0) },
                onDetails: { permissions.beginInstall($0) },
                onAddAll: { permissions.addAllBuiltIn() }
            )
        }
        .padding(24)
    }

    private var permissionsStep: some View {
        let missing = permissions.missingPermissions

        return stepLayout {
            stepHeader(
                icon: missing.isEmpty ? "checkmark.shield" : "lock.shield",
                title: missing.isEmpty ? "Permissions Granted" : "Grant Permissions",
                subtitle: missing.isEmpty
                    ? "Macotron has everything it needs. You can change this later in System Settings."
                    : "Select the button on each row. Some open System Settings."
            )

            VStack(alignment: .leading, spacing: 14) {
                ForEach(permissions.requiredPermissions) { permission in
                    PermissionRow(
                        permission: permission,
                        granted: permissions.grantedPermissions.contains(permission),
                        onChange: { permissions.refreshPermissions() }
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.5))
            )

            if !missing.isEmpty {
                Text("This list updates on its own after you approve each item.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var readyStep: some View {
        stepLayout {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Open the launcher with your hotkey. Install more plugins from Settings. With Hot Reload off, Macotron keeps the last approved copy until you review a change.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    // MARK: - Shared layout

    private func stepLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 20) {
            Spacer()
            content()
            Spacer()
        }
        .padding(24)
    }

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }
}
