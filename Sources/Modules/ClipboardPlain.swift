import AppKit

enum ClipboardPlain {
    static func applyCurrentText(to pasteboard: NSPasteboard = .general) {
        guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
