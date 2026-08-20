import AppKit

enum CommandHold {
    static func isHeld(commandDown: Bool, recording: Bool, appActive: Bool) -> Bool {
        appActive && !recording && commandDown
    }

    static func commandDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }
}

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
