import AppKit

enum ShortcutRecording {
    static let didChange = Notification.Name("ShortcutRecordingDidChange")
    nonisolated(unsafe) static var isActive = false

    static func begin() {
        isActive = true
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func end() {
        guard isActive else { return }
        isActive = false
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
