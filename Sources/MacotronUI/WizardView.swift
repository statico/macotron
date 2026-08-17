// WizardView.swift — First-run setup: pick plugins folder
import AppKit
import SwiftUI

public enum WizardStep: Int, CaseIterable {
    case welcome = 0
    case folder
    case ready
}

@MainActor
public final class WizardState: ObservableObject {
    @Published public var currentStep: WizardStep = .welcome
    @Published public var pluginsPath: String = ""
    @Published public var pluginsURL: URL?

    public var pickFolder: (() -> URL?)?
    public var initWorkspace: ((URL) -> Bool)?
    public var openInFinder: ((URL) -> Void)?
    public var onComplete: (() -> Void)?

    public init() {}

    public func chooseFolder() {
        guard let url = pickFolder?() else { return }
        pluginsURL = url
        pluginsPath = url.path(percentEncoded: false)
    }

    public func finish() {
        guard let url = pluginsURL else { return }
        guard initWorkspace?(url) == true else { return }
        onComplete?()
    }
}

public struct WizardView: View {
    @ObservedObject var state: WizardState

    public init(state: WizardState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.currentStep {
                case .welcome: welcomeStep
                case .folder: folderStep
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if state.currentStep != .welcome {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if let prev = WizardStep(rawValue: state.currentStep.rawValue - 1) {
                                state.currentStep = prev
                            }
                        }
                    }
                }

                Spacer()

                if state.currentStep == .ready {
                    Button("Open Macotron") {
                        state.finish()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.pluginsURL == nil)
                } else {
                    Button("Next") {
                        advance()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.currentStep == .folder && state.pluginsURL == nil)
                }
            }
            .padding(16)
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let next = WizardStep(rawValue: state.currentStep.rawValue + 1) {
                state.currentStep = next
            }
        }
    }

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
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Welcome to Macotron")
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("Macotron is a thin macOS host for JavaScript plugins. Pick a folder for your plugins — edit them with Cursor or Claude Code.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .padding(24)
    }

    private var folderStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Plugins Folder")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a directory Macotron will use as your plugin workdir. The app will create plugins/, settings.json, and agent docs there.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if state.pluginsPath.isEmpty {
                Text("No folder selected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                Text(state.pluginsPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button("Choose Folder…") {
                    state.chooseFolder()
                }

                if let url = state.pluginsURL {
                    Button("Open in Finder") {
                        state.openInFinder?(url)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)

            Text("Open the launcher with your hotkey to search commands and apps. Edit plugins in your chosen folder — Macotron reloads on save.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Spacer()
        }
        .padding(24)
    }
}
