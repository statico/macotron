import AppKit
import Carbon.HIToolbox
import CoreGraphics

public struct KeyCombo: Equatable, Sendable {
    public let modifiers: CGEventFlags
    public let keyCode: CGKeyCode
    public let raw: String

    public static func parse(_ combo: String) -> KeyCombo? {
        let parts = combo.lowercased().split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var flags: CGEventFlags = []
        var keyPart: String?
        for part in parts {
            switch part {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            default: keyPart = part
            }
        }
        guard let key = keyPart, let code = codeByName[key] else { return nil }
        return KeyCombo(modifiers: flags, keyCode: code, raw: combo.lowercased())
    }

    public func matches(_ event: CGEvent) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }
        let mask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        return event.flags.intersection(mask) == modifiers
    }

    public var carbonModifiers: UInt32 { CarbonHotKeys.modifiers(from: modifiers) }

    public var menuEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var mods: NSEvent.ModifierFlags = []
        if modifiers.contains(.maskCommand) { mods.insert(.command) }
        if modifiers.contains(.maskShift) { mods.insert(.shift) }
        if modifiers.contains(.maskControl) { mods.insert(.control) }
        if modifiers.contains(.maskAlternate) { mods.insert(.option) }
        switch nameByCode[keyCode] {
        case "space": return (" ", mods)
        case "return": return ("\r", mods)
        case "tab": return ("\t", mods)
        case let name: return (name ?? "", mods)
        }
    }

    public static func combo(from event: NSEvent) -> String? {
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard !mods.isEmpty, let key = nameByCode[CGKeyCode(event.keyCode)] else { return nil }
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("opt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    public static func glyphs(_ combo: String) -> [String] {
        combo.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }.map { part in
            switch part.lowercased() {
            case "cmd", "command", "meta": return "\u{2318}"
            case "shift": return "\u{21E7}"
            case "ctrl", "control": return "\u{2303}"
            case "opt", "option", "alt": return "\u{2325}"
            case "space": return "Space"
            case "return", "enter": return "\u{23CE}"
            case "delete", "backspace": return "\u{232B}"
            case "forwarddelete": return "\u{2326}"
            case "tab": return "\u{21E5}"
            case "escape", "esc": return "\u{238B}"
            case "left": return "\u{2190}"
            case "right": return "\u{2192}"
            case "up": return "\u{2191}"
            case "down": return "\u{2193}"
            case "home": return "\u{2196}"
            case "end": return "\u{2198}"
            case "pageup": return "PgUp"
            case "pagedown": return "PgDn"
            default: return part.uppercased()
            }
        }
    }
}

extension KeyCombo: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(modifiers.rawValue)
        hasher.combine(keyCode)
    }
}

private let namedKeys: [(String, CGKeyCode)] = {
    var pairs: [(String, CGKeyCode)] = [
        ("left", CGKeyCode(kVK_LeftArrow)),
        ("right", CGKeyCode(kVK_RightArrow)),
        ("up", CGKeyCode(kVK_UpArrow)),
        ("down", CGKeyCode(kVK_DownArrow)),
        ("return", CGKeyCode(kVK_Return)),
        ("tab", CGKeyCode(kVK_Tab)),
        ("space", CGKeyCode(kVK_Space)),
        ("delete", CGKeyCode(kVK_Delete)),
        ("forwarddelete", CGKeyCode(kVK_ForwardDelete)),
        ("escape", CGKeyCode(kVK_Escape)),
        ("home", CGKeyCode(kVK_Home)),
        ("end", CGKeyCode(kVK_End)),
        ("pageup", CGKeyCode(kVK_PageUp)),
        ("pagedown", CGKeyCode(kVK_PageDown)),
        ("-", CGKeyCode(kVK_ANSI_Minus)),
        ("=", CGKeyCode(kVK_ANSI_Equal)),
        ("[", CGKeyCode(kVK_ANSI_LeftBracket)),
        ("]", CGKeyCode(kVK_ANSI_RightBracket)),
        (";", CGKeyCode(kVK_ANSI_Semicolon)),
        ("'", CGKeyCode(kVK_ANSI_Quote)),
        ("\\", CGKeyCode(kVK_ANSI_Backslash)),
        (",", CGKeyCode(kVK_ANSI_Comma)),
        (".", CGKeyCode(kVK_ANSI_Period)),
        ("/", CGKeyCode(kVK_ANSI_Slash)),
        ("`", CGKeyCode(kVK_ANSI_Grave)),
    ]
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    let letterCodes = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z,
    ]
    for (ch, code) in zip(letters, letterCodes) {
        pairs.append((String(ch), CGKeyCode(code)))
    }
    let digitCodes = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    for (i, code) in digitCodes.enumerated() {
        pairs.append((String(i), CGKeyCode(code)))
    }
    let functionCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]
    for (i, code) in functionCodes.enumerated() {
        pairs.append(("f\(i + 1)", CGKeyCode(code)))
    }
    return pairs
}()

private let codeByName: [String: CGKeyCode] = {
    var d = Dictionary(uniqueKeysWithValues: namedKeys)
    d["enter"] = d["return"]
    d["backspace"] = d["delete"]
    d["esc"] = d["escape"]
    d["minus"] = d["-"]
    d["equal"] = d["="]
    d["equals"] = d["="]
    d["leftbracket"] = d["["]
    d["rightbracket"] = d["]"]
    d["semicolon"] = d[";"]
    d["quote"] = d["'"]
    d["backslash"] = d["\\"]
    d["comma"] = d[","]
    d["period"] = d["."]
    d["slash"] = d["/"]
    d["grave"] = d["`"]
    return d
}()

private let nameByCode = Dictionary(uniqueKeysWithValues: namedKeys.map { ($0.1, $0.0) })
