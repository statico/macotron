import Foundation

/// Turns a title typed in Settings into a plugin filename and starter source.
public enum PluginDraft {
    public static func slug(_ title: String) -> String {
        let flattened = title.lowercased().map { ch in
            ch.isLetter || ch.isNumber ? ch : "-"
        }
        return String(flattened)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    public static func filename(for title: String) -> String? {
        let slug = slug(title)
        return slug.isEmpty ? nil : "\(slug).js"
    }

    public static func source(title: String) -> String {
        let name = escape(title)
        return """
        macotron.plugin({
          title: "\(name)",
          description: "",
        });

        macotron.command("\(name)", "", () => {
          macotron.notify.toast("\(name)", "Hello");
        });

        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
