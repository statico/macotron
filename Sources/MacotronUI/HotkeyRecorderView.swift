// HotkeyRecorderView.swift — Raycast-style hotkey recorder control
import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A Raycast-style hotkey recorder. Click to start recording, press a modifier+key
/// combo to set the shortcut. Escape cancels, Delete clears.
public struct HotkeyRecorderView: View {
    @Binding var combo: String
    var onSave: () -> Void

    @State private var isRecording = false
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?
    @State private var flagsMonitor: Any?

    public var body: some View {
        pill
            .overlay(alignment: .top) {
                if isRecording {
                    recordingBubble
                        .offset(y: -54)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isRecording)
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 6) {
            Spacer()

            if isRecording {
                if !combo.isEmpty {
                    ForEach(displayParts(combo), id: \.self) { part in
                        keyCap(part)
                            .opacity(0.35)
                    }
                } else {
                    Text("Type Shortcut")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            } else if combo.isEmpty {
                Text("Click to Record")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(displayParts(combo), id: \.self) { part in
                    keyCap(part)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isRecording ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRecording {
                startRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Recording Bubble

    private var recordingBubble: some View {
        VStack(spacing: 4) {
            if !heldModifiers.isEmpty {
                HStack(spacing: 4) {
                    ForEach(modifierSymbols(heldModifiers), id: \.self) { sym in
                        keyCap(sym)
                    }
                }
            }
            Text("Recording...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Key Cap

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
            )
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        heldModifiers = []

        // Monitor modifier key changes to show held modifiers live
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            heldModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
            return event
        }

        // Monitor key presses to capture the combo
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // consume
        }
    }

    private func stopRecording() {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
        flagsMonitor = nil
        isRecording = false
        heldModifiers = []
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Delete/Backspace clears the shortcut
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            combo = ""
            stopRecording()
            onSave()
            return
        }

        // Require at least one modifier for a valid hotkey
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard !mods.isEmpty else { return }

        // Build combo string in canonical order
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("opt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }

        if let keyName = keyNameFromCode(event.keyCode) {
            parts.append(keyName)
            combo = parts.joined(separator: "+")
            stopRecording()
            onSave()
        }
    }

    // MARK: - Display Helpers

    /// Convert a combo string like "cmd+shift+space" into display symbols ["⌘", "⇧", "Space"]
    private func displayParts(_ combo: String) -> [String] {
        combo.split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .map { part in
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

    /// Convert held modifier flags into symbol strings for live display
    private func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        var syms: [String] = []
        if flags.contains(.control) { syms.append("\u{2303}") }
        if flags.contains(.option) { syms.append("\u{2325}") }
        if flags.contains(.shift) { syms.append("\u{21E7}") }
        if flags.contains(.command) { syms.append("\u{2318}") }
        return syms
    }

    // MARK: - Key Code → Name

    private func keyNameFromCode(_ keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        // Letters
        case kVK_ANSI_A: return "a"
        case kVK_ANSI_B: return "b"
        case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"
        case kVK_ANSI_E: return "e"
        case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"
        case kVK_ANSI_H: return "h"
        case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"
        case kVK_ANSI_K: return "k"
        case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"
        case kVK_ANSI_N: return "n"
        case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"
        case kVK_ANSI_Q: return "q"
        case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"
        case kVK_ANSI_T: return "t"
        case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"
        case kVK_ANSI_W: return "w"
        case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"
        case kVK_ANSI_Z: return "z"

        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Arrow keys
        case kVK_LeftArrow: return "left"
        case kVK_RightArrow: return "right"
        case kVK_UpArrow: return "up"
        case kVK_DownArrow: return "down"

        // Special keys
        case kVK_Return: return "return"
        case kVK_Tab: return "tab"
        case kVK_Space: return "space"
        case kVK_Delete: return "delete"
        case kVK_ForwardDelete: return "forwarddelete"
        case kVK_Home: return "home"
        case kVK_End: return "end"
        case kVK_PageUp: return "pageup"
        case kVK_PageDown: return "pagedown"

        // Function keys
        case kVK_F1: return "f1"
        case kVK_F2: return "f2"
        case kVK_F3: return "f3"
        case kVK_F4: return "f4"
        case kVK_F5: return "f5"
        case kVK_F6: return "f6"
        case kVK_F7: return "f7"
        case kVK_F8: return "f8"
        case kVK_F9: return "f9"
        case kVK_F10: return "f10"
        case kVK_F11: return "f11"
        case kVK_F12: return "f12"

        // Punctuation
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        default: return nil
        }
    }
}
