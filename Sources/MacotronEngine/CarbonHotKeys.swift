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
    private var wakeObservers: [NSObjectProtocol] = []

    private init() {
        installEventHandler()
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in names {
            wakeObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reregisterAll()
            })
        }
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
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            logger.error("RegisterEventHotKey failed: \(status) key=\(keyCode) mods=\(carbonModifiers)")
            return nil
        }
        slots[id] = Slot(ref: ref, keyCode: keyCode, mods: carbonModifiers, handler: handler)
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

    private func reregisterAll() {
        lock.lock()
        let snapshot = slots
        lock.unlock()
        for (id, slot) in snapshot {
            if let ref = slot.ref {
                UnregisterEventHotKey(ref)
            }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(
                slot.keyCode,
                slot.mods,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            lock.lock()
            if status == noErr {
                slots[id]?.ref = ref
            } else {
                logger.error("Re-register hotkey \(id) failed: \(status)")
                slots[id]?.ref = nil
            }
            lock.unlock()
        }
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
