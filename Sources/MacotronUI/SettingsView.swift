// SettingsView.swift — General prefs, plugins list, about
import AppKit
import SwiftUI

/// A configurable option exposed by a plugin
public struct ModuleOption: Identifiable {
    public let id: String
    public let key: String
    public let label: String
    public let type: String
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

/// Summary info for a single plugin
public struct ModuleSummary: Identifiable {
    public let id: String
    public let filename: String
    public let title: String
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
        self.title = title.isEmpty ? String(filename.dropLast(3)) : title
        self.description = description
        self.options = options
        self.events = events
        self.hotkeys = hotkeys
        self.hasErrors = hasErrors
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class SettingsState: ObservableObject {
    @Published public var launcherHotkey: String = "cmd+space"
    @Published public var showDockIcon: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var moduleSummaries: [ModuleSummary] = []
    @Published public var pluginsPath: String = ""
    @Published public var requestedTab: Int?

    public var readHotkey: (() -> String)?
    public var writeHotkey: ((String) -> Void)?
    public var readShowDockIcon: (() -> Bool)?
    public var writeShowDockIcon: ((Bool) -> Void)?
    public var readShowMenuBarIcon: (() -> Bool)?
    public var writeShowMenuBarIcon: ((Bool) -> Void)?
    public var loadModuleSummaries: (() -> [ModuleSummary])?
    public var saveModuleOption: ((_ filename: String, _ key: String, _ value: Any) -> Void)?
    public var deleteModule: ((_ filename: String) -> Bool)?
    public var changePluginsFolder: (() -> Void)?
    public var openPluginsFolder: (() -> Void)?
    public var configDirURL: URL?

    public init() {}

    public func load() {
        launcherHotkey = readHotkey?() ?? "cmd+space"
        showDockIcon = readShowDockIcon?() ?? true
        showMenuBarIcon = readShowMenuBarIcon?() ?? true
        pluginsPath = configDirURL?.path(percentEncoded: false) ?? ""
        refreshModules()
    }

    public func refreshModules() {
        moduleSummaries = loadModuleSummaries?() ?? []
    }

    public func saveHotkey() {
        writeHotkey?(launcherHotkey)
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

public struct SettingsView: View {
    @ObservedObject var state: SettingsState
    @State private var selectedTab: Int

    public init(state: SettingsState, initialTab: Int = 0) {
        self.state = state
        self._selectedTab = State(initialValue: initialTab)
    }

    private let labelWidth: CGFloat = 140
    private let githubPluginsURL = URL(string: "https://github.com/search?q=topic%3Amacotron-plugin&type=repositories")!

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, 2)
                .padding(.bottom, 6)

            Divider()

            switch selectedTab {
            case 1: pluginsTab
            case 2: aboutTab
            default: generalTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            state.load()
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            }
        }
        .onChange(of: state.requestedTab) {
            if let tab = state.requestedTab {
                selectedTab = tab
                state.requestedTab = nil
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            Spacer()
            tabButton(icon: "gearshape", label: "General", tag: 0)
            tabButton(icon: "puzzlepiece.extension", label: "Plugins", tag: 1)
            tabButton(icon: "info.circle", label: "About", tag: 2)
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    private var generalTab: some View {
        VStack(spacing: 0) {
            formRow("Launcher Hotkey") {
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

            formRow("Plugins Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.pluginsPath.isEmpty ? "(not set)" : state.pluginsPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Button("Change…") {
                            state.changePluginsFolder?()
                            state.load()
                        }
                        .controlSize(.small)

                        Button("Open Folder") {
                            state.openPluginsFolder?()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Spacer()
        }
    }

    private var pluginsTab: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Browse plugins on GitHub") {
                    NSWorkspace.shared.open(githubPluginsURL)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if state.moduleSummaries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No plugins installed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Add .js files to the plugins/ folder, or browse GitHub.")
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
        .onAppear { state.refreshModules() }
    }

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

            Text("A thin macOS host for JavaScript plugins. Edit plugins with your coding agent — Macotron loads and runs them.")
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
}

struct ModuleSummaryRow: View {
    let summary: ModuleSummary
    @ObservedObject var state: SettingsState
    @State private var isExpanded: Bool = false
    @State private var showDeleteAlert: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
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
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(summary.filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    if !summary.description.isEmpty {
                        Text(summary.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if summary.hasErrors {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(summary.errorMessage ?? "Plugin has errors")
                                .font(.system(size: 11))
                                .lineLimit(2)
                        }
                        .foregroundStyle(.red)
                    }

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

                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete plugin")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            if isExpanded && !summary.options.isEmpty {
                Divider().padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.options) { option in
                        ModuleOptionRow(option: option, filename: summary.filename, state: state)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .alert("Delete Plugin?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if state.deleteModule?(summary.filename) == true {
                    state.refreshModules()
                }
            }
        } message: {
            Text("Delete \(summary.title)? This cannot be undone.")
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
                    Text(option.label).font(.system(size: 12)).foregroundStyle(.secondary)
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
                    Text(option.label).font(.system(size: 12)).foregroundStyle(.secondary)
                    HotkeyRecorderView(combo: $hotkeyValue) {
                        state.saveModuleOption?(filename, option.key, hotkeyValue)
                        state.refreshModules()
                    }
                    .onAppear { hotkeyValue = (option.currentValue as? String) ?? "" }
                }
            default:
                HStack(spacing: 8) {
                    Text(option.label).font(.system(size: 12)).foregroundStyle(.secondary)
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
