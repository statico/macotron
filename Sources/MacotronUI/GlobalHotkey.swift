// GlobalHotkey.swift — Global keyboard shortcut for toggling the launcher panel
import Foundation
import CoreGraphics
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.macotron", category: "globalHotkey")

// MARK: - HotkeyCombo

/// Parsed representation of a keyboard shortcut string like "cmd+space".
private struct HotkeyCombo: Equatable, Sendable {
    let modifiers: CGEventFlags
    let keyCode: CGKeyCode
    let raw: String

    /// Parse a combo string like "cmd+space", "ctrl+opt+l".
    /// Returns nil if the string cannot be parsed.
    static func parse(_ combo: String) -> HotkeyCombo? {
        let parts = combo.lowercased()
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        var flags: CGEventFlags = []
        var keyPart: String?

        for part in parts {
            switch part {
            case "cmd", "command", "meta":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "ctrl", "control":
                flags.insert(.maskControl)
            case "opt", "option", "alt":
                flags.insert(.maskAlternate)
            default:
                keyPart = part
            }
        }

        guard let key = keyPart, let code = keyCodeFromString(key) else { return nil }
        return HotkeyCombo(modifiers: flags, keyCode: code, raw: combo.lowercased())
    }

    /// Check if this combo matches a CGEvent.
    func matches(_ event: CGEvent) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }

        let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let eventMods = event.flags.intersection(relevantMask)
        return eventMods == modifiers
    }

    // MARK: - Key code mapping

    private static func keyCodeFromString(_ key: String) -> CGKeyCode? {
        switch key {
        // Letters
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)

        // Numbers
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)

        // Arrow keys
        case "left": return CGKeyCode(kVK_LeftArrow)
        case "right": return CGKeyCode(kVK_RightArrow)
        case "up": return CGKeyCode(kVK_UpArrow)
        case "down": return CGKeyCode(kVK_DownArrow)

        // Special keys
        case "return", "enter": return CGKeyCode(kVK_Return)
        case "tab": return CGKeyCode(kVK_Tab)
        case "space": return CGKeyCode(kVK_Space)
        case "delete", "backspace": return CGKeyCode(kVK_Delete)
        case "forwarddelete": return CGKeyCode(kVK_ForwardDelete)
        case "escape", "esc": return CGKeyCode(kVK_Escape)
        case "home": return CGKeyCode(kVK_Home)
        case "end": return CGKeyCode(kVK_End)
        case "pageup": return CGKeyCode(kVK_PageUp)
        case "pagedown": return CGKeyCode(kVK_PageDown)

        // Function keys
        case "f1": return CGKeyCode(kVK_F1)
        case "f2": return CGKeyCode(kVK_F2)
        case "f3": return CGKeyCode(kVK_F3)
        case "f4": return CGKeyCode(kVK_F4)
        case "f5": return CGKeyCode(kVK_F5)
        case "f6": return CGKeyCode(kVK_F6)
        case "f7": return CGKeyCode(kVK_F7)
        case "f8": return CGKeyCode(kVK_F8)
        case "f9": return CGKeyCode(kVK_F9)
        case "f10": return CGKeyCode(kVK_F10)
        case "f11": return CGKeyCode(kVK_F11)
        case "f12": return CGKeyCode(kVK_F12)

        // Punctuation / symbols
        case "-", "minus": return CGKeyCode(kVK_ANSI_Minus)
        case "=", "equal", "equals": return CGKeyCode(kVK_ANSI_Equal)
        case "[", "leftbracket": return CGKeyCode(kVK_ANSI_LeftBracket)
        case "]", "rightbracket": return CGKeyCode(kVK_ANSI_RightBracket)
        case ";", "semicolon": return CGKeyCode(kVK_ANSI_Semicolon)
        case "'", "quote": return CGKeyCode(kVK_ANSI_Quote)
        case "\\", "backslash": return CGKeyCode(kVK_ANSI_Backslash)
        case ",", "comma": return CGKeyCode(kVK_ANSI_Comma)
        case ".", "period": return CGKeyCode(kVK_ANSI_Period)
        case "/", "slash": return CGKeyCode(kVK_ANSI_Slash)
        case "`", "grave": return CGKeyCode(kVK_ANSI_Grave)

        default: return nil
        }
    }
}

// MARK: - GlobalHotkeyState

/// Shared mutable state accessed by the C function pointer callback.
/// The CGEvent tap callback cannot capture Swift context, so we use a singleton.
private final class GlobalHotkeyState: @unchecked Sendable {
    let lock = NSLock()
    var combo: HotkeyCombo?

    static let shared = GlobalHotkeyState()
}

// MARK: - GlobalHotkey

/// Registers a single global keyboard shortcut via a CGEvent tap.
///
/// Usage:
/// ```swift
/// let hotkey = GlobalHotkey(combo: "cmd+space") {
///     launcherPanel.toggle()
/// }
/// // Later, to change the binding:
/// hotkey.updateHotkey("ctrl+space")
/// // On teardown:
/// hotkey.cleanup()
/// ```
@MainActor
public final class GlobalHotkey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: @MainActor () -> Void

    /// Create a global hotkey listener.
    /// - Parameters:
    ///   - combo: A hotkey string like "cmd+space", "ctrl+shift+l".
    ///   - callback: Closure invoked on the main actor when the hotkey fires.
    public init(combo: String, callback: @escaping @MainActor () -> Void) {
        self.callback = callback

        if let parsed = HotkeyCombo.parse(combo) {
            let state = GlobalHotkeyState.shared
            state.lock.lock()
            state.combo = parsed
            state.lock.unlock()
            logger.info("Global hotkey registered: \(combo)")
        } else {
            logger.warning("Failed to parse global hotkey combo: \(combo)")
        }

        setupEventTap()
    }

    /// Change the hotkey binding at runtime.
    public func updateHotkey(_ combo: String) {
        if let parsed = HotkeyCombo.parse(combo) {
            let state = GlobalHotkeyState.shared
            state.lock.lock()
            state.combo = parsed
            state.lock.unlock()
            logger.info("Global hotkey updated: \(combo)")
        } else {
            logger.warning("Failed to parse global hotkey combo: \(combo)")
        }
    }

    /// Tear down the event tap and release resources.
    public func cleanup() {
        teardownEventTap()
        let state = GlobalHotkeyState.shared
        state.lock.lock()
        state.combo = nil
        state.lock.unlock()
        logger.info("Global hotkey cleaned up")
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // C function pointer callback — cannot capture Swift context.
        // Reads the combo from GlobalHotkeyState singleton and dispatches
        // to MainActor via DispatchQueue.main.
        let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            // Re-enable the tap if the system disabled it
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    let machPort = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue()
                    // swiftlint:disable:next force_cast
                    CGEvent.tapEnable(tap: (machPort as! CFMachPort), enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let state = GlobalHotkeyState.shared
            state.lock.lock()
            let combo = state.combo
            state.lock.unlock()

            guard let combo, combo.matches(event) else {
                return Unmanaged.passRetained(event)
            }

            // Dispatch callback to the main thread (MainActor)
            DispatchQueue.main.async {
                // Post a notification that the global hotkey singleton picks up.
                NotificationCenter.default.post(name: GlobalHotkey.firedNotification, object: nil)
            }

            // Consume the event so it does not propagate to other apps
            return nil
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: nil
        )

        guard let eventTap else {
            logger.error("Failed to create CGEvent tap for global hotkey. Ensure Accessibility permission is granted.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        // Observe the notification posted by the C callback
        NotificationCenter.default.addObserver(
            forName: GlobalHotkey.firedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // We are already on the main queue; MainActor is satisfied.
            MainActor.assumeIsolated {
                self?.callback()
            }
        }

        logger.info("Global hotkey event tap installed")
    }

    private func teardownEventTap() {
        NotificationCenter.default.removeObserver(self, name: GlobalHotkey.firedNotification, object: nil)

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        // Safety net: remove the notification observer.
        // The event tap and run loop source are already nil after cleanup(),
        // but guard against leaks if cleanup() was not called.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Internal

    /// Notification name used to bridge from the C callback to the Swift callback.
    private static let firedNotification = Notification.Name("com.macotron.globalHotkey.fired")
}
