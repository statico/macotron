import Foundation
import MacotronEngine
import SwiftUI

enum ShortcutConflicts {
    static let launcherID = "launcher"

    struct Claim: Equatable {
        let id: String
        let combo: String
        let label: String
        let pluginFile: String?
    }

    static func normalize(_ combo: String) -> String? {
        let s = combo.lowercased().trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == CommandShortcuts.unbound { return nil }
        return s
    }

    static func claims(
        launcher: String,
        apps: [AppShortcutSummary],
        modules: [ModuleSummary]
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
        return out
    }

    static func warning(for id: String, combo: String, in claims: [Claim]) -> String? {
        guard let normalized = normalize(combo) else { return nil }
        let others = claims.filter { $0.combo == normalized && $0.id != id }.map(\.label)
        guard !others.isEmpty else { return nil }
        return "Also used by " + others.joined(separator: ", ")
    }

    static func pluginHasConflict(_ filename: String, in claims: [Claim]) -> Bool {
        Dictionary(grouping: claims, by: \.combo).values.contains { group in
            group.count > 1 && group.contains { $0.pluginFile == filename }
        }
    }
}

extension SettingsState {
    var shortcutClaims: [ShortcutConflicts.Claim] {
        ShortcutConflicts.claims(
            launcher: launcherHotkey,
            apps: appShortcuts,
            modules: moduleSummaries
        )
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
