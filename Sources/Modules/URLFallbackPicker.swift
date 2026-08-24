import MacotronEngine
import AppKit

@MainActor
enum URLFallbackPicker {
    struct Choice: Equatable {
        let title: String
        let bundleID: String
    }

    static func choices(for url: URL) -> [Choice] {
        var out: [Choice] = []
        var seen: Set<String> = ["io.statico.macotron"]
        func add(_ title: String, _ id: String) {
            guard !seen.contains(id) else { return }
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return }
            seen.insert(id)
            out.append(Choice(title: title, bundleID: id))
        }
        add("Safari", "com.apple.Safari")
        add("Chrome", "com.google.Chrome")
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: url) {
            guard let id = Bundle(url: appURL)?.bundleIdentifier else { continue }
            add("Default", id)
            if out.contains(where: { $0.title == "Default" }) { break }
        }
        return out
    }

    static func show(url: URL, open: @escaping (URL, String?) -> Void) {
        let items = choices(for: url)
        guard !items.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Open Link"
        alert.informativeText = url.host ?? url.absoluteString
        for item in items {
            alert.addButton(withTitle: item.title)
        }
        alert.addButton(withTitle: "Cancel")

        AppActivation.activate("browser picker")
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard items.indices.contains(index) else { return }
        open(url, items[index].bundleID)
    }
}
