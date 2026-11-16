// CarbonHotKeys.swift — RegisterEventHotKey for global shortcuts
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "carbonHotKeys")

/// System-registered hotkeys. Unlike a CGEvent tap, the OS only invokes us for
/// the combos we bind, so typing never goes through Macotron and the tap cannot
/// time out or stall the keyboard.
public final class CarbonHotKeys: @unchecked Sendable {
    public static let shared = CarbonHotKeys()

    public typealias Handler = () -> Void

    private struct Slot {
        var ref: EventHotKeyRef?
        let keyCode: UInt32
        let mods: UInt32
        let handler: Handler
    }

    fileprivate static let signature = OSType(0x4D43544F) // 'MCTO'

    private let lock = NSLock()
    private var nextID: UInt32 = 1
    private var slots: [UInt32: Slot] = [:]
    private var eventHandler: EventHandlerRef?
    private var observers: [NSObjectProtocol] = []

    private init() {
        installEventHandler()
        // macOS sometimes stops delivering a registration with no error (seen on
        // macOS 26 after a day of uptime); registering again revives it. Do that
        // whenever the user is likely to reach for a shortcut next.
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.reregisterAll(reason: note.name.rawValue)
            })
        }
        // Covers the Macotron menu, which opens without activating the app.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reregisterAll(reason: "menu")
        })
    }

    public static func modifiers(from flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskCommand) { mods |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { mods |= UInt32(shiftKey) }
        if flags.contains(.maskControl) { mods |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        return mods
    }

    @discardableResult
    public func register(keyCode: UInt32, carbonModifiers: UInt32, handler: @escaping Handler) -> UInt32? {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID &+= 1
        let (status, ref) = Self.registerRef(id: id, keyCode: keyCode, mods: carbonModifiers)
        guard status == noErr, let ref else {
            logger.error("RegisterEventHotKey failed: \(status) key=\(keyCode) mods=\(carbonModifiers)")
            return nil
        }
        slots[id] = Slot(ref: ref, keyCode: keyCode, mods: carbonModifiers, handler: handler)
        logger.debug("registered hotkey \(id) key=\(keyCode) mods=\(carbonModifiers)")
        return id
    }

    public func unregister(_ id: UInt32) {
        lock.lock()
        let slot = slots.removeValue(forKey: id)
        lock.unlock()
        if let ref = slot?.ref {
            UnregisterEventHotKey(ref)
        }
    }

    public func unregister(_ ids: [UInt32]) {
        for id in ids { unregister(id) }
    }

    func invoke(_ id: UInt32) {
        lock.lock()
        let handler = slots[id]?.handler
        lock.unlock()
        logger.info("hotkey \(id) fired, handler=\(handler != nil)")
        handler?()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            carbonHotKeyCallback,
            1,
            &spec,
            nil,
            &eventHandler
        )
        if status != noErr {
            logger.error("InstallEventHandler failed: \(status)")
        }
    }

    /// Exclusive, as Hammerspoon does, so another app cannot take the combo
    /// out from under us.
    private static func registerRef(id: UInt32, keyCode: UInt32, mods: UInt32) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            mods,
            EventHotKeyID(signature: signature, id: id),
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        return (status, ref)
    }

    private func reregisterAll(reason: String) {
        lock.lock()
        let snapshot = slots
        lock.unlock()
        guard !snapshot.isEmpty else { return }
        var failed = 0
        for (id, slot) in snapshot {
            if let ref = slot.ref {
                UnregisterEventHotKey(ref)
            }
            let (status, ref) = Self.registerRef(id: id, keyCode: slot.keyCode, mods: slot.mods)
            lock.lock()
            if slots[id] == nil {
                // Unregistered while we looped.
                if let ref { UnregisterEventHotKey(ref) }
            } else if status == noErr {
                slots[id]?.ref = ref
            } else {
                failed += 1
                logger.error("Re-register hotkey \(id) failed: \(status)")
                slots[id]?.ref = nil
            }
            lock.unlock()
        }
        logger.info("re-registered \(snapshot.count) hotkeys (\(reason, privacy: .public)), \(failed) failed")
    }
}

private func carbonHotKeyCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr, hotKeyID.signature == CarbonHotKeys.signature else {
        return OSStatus(eventNotHandledErr)
    }
    CarbonHotKeys.shared.invoke(hotKeyID.id)
    return noErr
}
