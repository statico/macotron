// KeyboardModule.swift — macotron.keyboard: global keyboard shortcut registration
import CQuickJS
import MacotronEngine
import Foundation
import CoreGraphics
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.macotron", category: "keyboard")

// MARK: - KeyCombo

/// Represents a parsed keyboard shortcut combo (e.g. "cmd+shift+left").
struct KeyCombo: Equatable {
    let modifiers: CGEventFlags
    let keyCode: CGKeyCode
    let raw: String

    /// Parse a combo string like "cmd+shift+left", "ctrl+opt+a".
    /// Returns nil if the string cannot be parsed.
    static func parse(_ combo: String) -> KeyCombo? {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
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
        return KeyCombo(modifiers: flags, keyCode: code, raw: combo.lowercased())
    }

    /// Check if this combo matches a CGEvent.
    func matches(_ event: CGEvent) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }

        // Mask out device-specific bits; check only the modifier keys we care about
        let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let eventMods = event.flags.intersection(relevantMask)
        return eventMods == modifiers
    }

    /// Map a key name string to a macOS virtual key code.
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

extension KeyCombo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers.rawValue)
        hasher.combine(keyCode)
    }
}

// MARK: - KeyboardModule

/// Global state for the CGEvent tap callback (must be accessible from a C function pointer).
/// Stored outside the actor because the event tap callback runs on an arbitrary thread.
private final class KeyboardTapState: @unchecked Sendable {
    let lock = NSLock()
    var combos: [KeyCombo] = []
    weak var module: KeyboardModule?

    static let shared = KeyboardTapState()
}

@MainActor
public final class KeyboardModule: NativeModule {
    public let name = "keyboard"

    private weak var engine: Engine?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredCombos: [KeyCombo] = []

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        let keyboardObj = JS_NewObject(ctx)

        // ---------- on(combo, callback) ----------
        JS_SetPropertyStr(ctx, keyboardObj, "on", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else { return QJS_Undefined() }
            guard let comboStr = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }

            // Register the JS callback on the event bus under "keyboard:{combo}"
            let eventName = "keyboard:\(comboStr.lowercased())"
            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                engine.eventBus.on(eventName, callback: argv[1], ctx: ctx)
            }

            // Parse and register the combo in the global tap state
            if let combo = KeyCombo.parse(comboStr) {
                let state = KeyboardTapState.shared
                state.lock.lock()
                if !state.combos.contains(combo) {
                    state.combos.append(combo)
                }
                state.lock.unlock()
            } else {
                logger.warning("Failed to parse keyboard combo: \(comboStr)")
            }

            return QJS_Undefined()
        }, "on", 2))

        JS_SetPropertyStr(ctx, macotron, "keyboard", keyboardObj)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        // Set up the global event tap
        KeyboardTapState.shared.module = self
        setupEventTap()
    }

    public func cleanup() {
        teardownEventTap()
        KeyboardTapState.shared.lock.lock()
        KeyboardTapState.shared.combos.removeAll()
        KeyboardTapState.shared.module = nil
        KeyboardTapState.shared.lock.unlock()
        registeredCombos.removeAll()
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // CGEvent tap callback — this is a C function pointer, cannot capture context.
        // We use the global KeyboardTapState singleton to access registered combos.
        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            // If the tap is disabled by the system, re-enable it
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    let machPort = Unmanaged<AnyObject>.fromOpaque(refcon).takeUnretainedValue()
                    CGEvent.tapEnable(tap: (machPort as! CFMachPort), enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let state = KeyboardTapState.shared
            state.lock.lock()
            let combos = state.combos
            state.lock.unlock()

            for combo in combos {
                if combo.matches(event) {
                    let comboRaw = combo.raw
                    // Dispatch back to MainActor to emit via eventBus
                    DispatchQueue.main.async {
                        let state = KeyboardTapState.shared
                        guard let module = state.module else { return }
                        guard let engine = module.engine else { return }
                        let eventName = "keyboard:\(comboRaw)"
                        engine.eventBus.emit(eventName, engine: engine)
                    }
                    // Consume the event so it does not propagate
                    return nil
                }
            }

            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        guard let eventTap else {
            logger.error("Failed to create CGEvent tap. Ensure Input Monitoring / Accessibility permission is granted.")
            return
        }

        // Pass the machPort as userInfo so the callback can re-enable it on timeout
        let opaquePort = Unmanaged.passUnretained(eventTap).toOpaque()
        // We need to recreate with userInfo — but CGEvent.tapCreate doesn't allow updating userInfo.
        // Instead, store it in the shared state for the callback to reference if needed.

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        logger.info("Keyboard event tap installed")
    }

    private func teardownEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
