enum EventLabel {
    private static let names: [String: String] = [
        "audio:changed": "Audio device changed",
        "media:changed": "Now Playing changed",
        "space:changed": "Desktop changed",
        "usb:changed": "USB device changed",
        "hid:input": "HID input report",
        "clipboard:changed": "Clipboard changed",
        "display:changed": "Display changed",
        "wifi:changed": "Wi-Fi changed",
        "app:activated": "App became frontmost",
        "app:launched": "App launched",
        "app:terminated": "App quit",
        "window:focused": "Window focused",
        "window:created": "Window opened",
        "system:sleep": "Mac went to sleep",
        "system:wake": "Mac woke up",
        "system:lock": "Screen locked",
        "system:unlock": "Screen unlocked",
        "system:idle": "Idle",
        "system:active": "No longer idle",
        "timer:tick": "Timer",
    ]

    static func displayName(_ event: String) -> String {
        if let name = names[event] { return name }
        if event.hasPrefix("keyboard:") {
            let rest = String(event.dropFirst("keyboard:".count))
            if let slash = rest.lastIndex(of: "/") {
                return String(rest[rest.index(after: slash)...])
            }
            return rest
        }
        if event.hasPrefix("url:") {
            return "URL " + event.dropFirst("url:".count).replacingOccurrences(of: ":", with: "://")
        }
        if event.hasPrefix("schedule:every ") {
            return "Every " + event.dropFirst("schedule:every ".count)
        }
        if event.hasPrefix("schedule:at ") {
            return "At " + event.dropFirst("schedule:at ".count)
        }
        return fallback(event)
    }

    private static func fallback(_ event: String) -> String {
        let words = event
            .split { $0 == ":" || $0 == "-" || $0 == "_" }
            .map(String.init)
        guard let first = words.first else { return event }
        return ([first.localizedCapitalized] + words.dropFirst().map { $0.lowercased() })
            .joined(separator: " ")
    }
}
