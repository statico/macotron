import Foundation
import MacotronEngine
import SwiftUI

public enum ShortcutConflicts {
    public static let launcherID = "launcher"

    public struct Claim: Equatable {
        public let id: String
        public let combo: String
        public let label: String
        public let pluginFile: String?
    }

    public static func normalize(_ combo: String) -> String? {
        let s = combo.lowercased().trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == CommandShortcuts.unbound { return nil }
        return s
    }

    public static func claims(
        launcher: String,
        apps: [AppShortcutSummary],
        modules: [ModuleSummary],
        commandShortcuts: CommandShortcuts = CommandShortcuts()
    ) -> [Claim] {
        var out: [Claim] = []
        if let combo = normalize(launcher) {
            out.append(Claim(id: launcherID, combo: combo, label: "Launcher", pluginFile: nil))
        }
        for app in apps {
            if let combo = normalize(app.shortcut) {
                out.append(Claim(id: "app:\(app.id)", combo: combo, label: app.name, pluginFile: nil))
            }
        }
        for module in modules where module.isEnabled {
            for hotkey in module.hotkeys {
                if let combo = normalize(hotkey.shortcut) {
                    out.append(Claim(
                        id: "hotkey:\(hotkey.id)",
                        combo: combo,
                        label: "\(module.title) · \(hotkey.name)",
                        pluginFile: module.filename
                    ))
                }
            }
            for command in module.commands {
                if let combo = normalize(command.shortcut) {
                    out.append(Claim(
                        id: "command:\(command.id)",
                        combo: combo,
                        label: "\(module.title) · \(command.name)",
                        pluginFile: module.filename
                    ))
                }
            }
            for option in module.options where option.type == "keybinding" {
                if let combo = normalize((option.currentValue as? String) ?? "") {
                    out.append(Claim(
                        id: "option:\(module.filename)/\(option.key)",
                        combo: combo,
                        label: "\(module.title) · \(option.label)",
                        pluginFile: module.filename
                    ))
                }
            }
        }
        for host in HostCommands.all {
            if let combo = normalize(commandShortcuts.combo(for: host.id)) {
                out.append(Claim(id: host.id, combo: combo, label: host.name, pluginFile: nil))
            }
        }
        return out
    }

    public static func warning(for id: String, combo: String, in claims: [Claim]) -> String? {
        guard let normalized = normalize(combo) else { return nil }
        let others = claims.filter { $0.combo == normalized && $0.id != id }.map(\.label)
        guard !others.isEmpty else { return nil }
        return "Also used by " + others.joined(separator: ", ")
    }

    public static func pluginHasConflict(_ filename: String, in claims: [Claim]) -> Bool {
        Dictionary(grouping: claims, by: \.combo).values.contains { group in
            group.count > 1 && group.contains { $0.pluginFile == filename }
        }
    }

    public static func hotkeyRows(from claims: [Claim]) -> [ShowHotkeysRow] {
        claims
            .sorted { lhs, rhs in
                let label = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
                if label != .orderedSame { return label == .orderedAscending }
                let combo = lhs.combo.localizedCaseInsensitiveCompare(rhs.combo)
                if combo != .orderedSame { return combo == .orderedAscending }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
            .map { ShowHotkeysRow(id: $0.id, combo: $0.combo, label: $0.label) }
    }
}

extension SettingsState {
    var shortcutClaims: [ShortcutConflicts.Claim] {
        if let claimsCache { return claimsCache }
        var table = CommandShortcuts()
        table.assign(commandId: HostCommands.showHotkeysID, combo: showHotkeysHotkey)
        let claims = StepTimer.measure("shortcut claims") { ShortcutConflicts.claims(
            launcher: launcherHotkey,
            apps: appShortcuts,
            modules: moduleSummaries,
            commandShortcuts: table
        ) }
        claimsCache = claims
        return claims
    }

    func shortcutWarning(id: String, combo: String) -> String? {
        ShortcutConflicts.warning(for: id, combo: combo, in: shortcutClaims)
    }

    func pluginHasShortcutConflict(_ filename: String) -> Bool {
        ShortcutConflicts.pluginHasConflict(filename, in: shortcutClaims)
    }
}

struct ShortcutConflictNote: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
