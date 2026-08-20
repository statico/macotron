// HotkeyRecorderView.swift — hotkey recorder control
import SwiftUI
import AppKit
import Carbon.HIToolbox
import MacotronEngine

/// Click to start recording, press a modifier+key
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
        .padding(.horizontal, 8)
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
        .overlay(alignment: .trailing) {
            if !combo.isEmpty {
                Button(action: clearShortcut) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Shortcut")
                .accessibilityLabel("Clear Shortcut")
                .padding(.trailing, 8)
            }
        }
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
        ShortcutRecording.begin()

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
        heldModifiers = []
        if isRecording {
            isRecording = false
            ShortcutRecording.end()
        }
    }

    private func clearShortcut() {
        combo = ""
        stopRecording()
        onSave()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        // Delete/Backspace clears the shortcut
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            clearShortcut()
            return
        }

        // Require at least one modifier for a valid hotkey
        let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard !mods.isEmpty, let comboString = KeyCombo.combo(from: event) else { return }
        combo = comboString
        stopRecording()
        onSave()
    }

    private func displayParts(_ combo: String) -> [String] {
        KeyCombo.glyphs(combo)
    }

    private func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        var syms: [String] = []
        if flags.contains(.control) { syms.append("\u{2303}") }
        if flags.contains(.option) { syms.append("\u{2325}") }
        if flags.contains(.shift) { syms.append("\u{21E7}") }
        if flags.contains(.command) { syms.append("\u{2318}") }
        return syms
    }
}
