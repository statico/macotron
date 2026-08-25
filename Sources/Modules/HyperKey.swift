import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "hyperKey")

enum HyperKeyKind: String {
    case caps
    case fn
}

enum HyperKeyDecision: Equatable {
    case pass
    case swallow
    case modify(CGEventFlags)
}

struct HyperKeyMapper: Equatable {
    var kind: HyperKeyKind
    var held = false

    static let hyperFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    var triggerKeyCode: CGKeyCode {
        switch kind {
        case .caps: return CGKeyCode(kVK_CapsLock)
        case .fn: return CGKeyCode(kVK_Function)
        }
    }

    mutating func handle(type: CGEventType, keyCode: CGKeyCode, flags: CGEventFlags) -> HyperKeyDecision {
        if keyCode == triggerKeyCode {
            if type == .flagsChanged {
                switch kind {
                case .caps:
                    held.toggle()
                case .fn:
                    held = flags.contains(.maskSecondaryFn)
                }
            }
            return .swallow
        }
        if held, type == .keyDown || type == .keyUp {
            var next = flags
            next.remove(.maskAlphaShift)
            next.formUnion(Self.hyperFlags)
            return .modify(next)
        }
        return .pass
    }
}

private final class HyperKeyTapState: @unchecked Sendable {
    static let shared = HyperKeyTapState()
    let lock = NSLock()
    var mapper = HyperKeyMapper(kind: .caps)
    var eventTap: CFMachPort?
    var enabled = false

    var tap: CFMachPort? {
        lock.lock()
        defer { lock.unlock() }
        return eventTap
    }
}

final class HyperKey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var kind: HyperKeyKind?

    var current: String? { kind?.rawValue }
    var hasTap: Bool { eventTap != nil }

    @discardableResult
    func set(_ raw: String?, dryRun: Bool) -> Bool {
        guard let raw else {
            kind = nil
            teardown()
            return true
        }
        guard let parsed = HyperKeyKind(rawValue: raw) else { return false }
        kind = parsed
        teardown()
        if dryRun { return true }
        guard setup() else {
            kind = nil
            return false
        }
        return true
    }

    func cleanup() {
        kind = nil
        teardown()
    }

    private func setup() -> Bool {
        guard let kind, eventTap == nil else { return eventTap != nil }

        let state = HyperKeyTapState.shared
        state.lock.lock()
        state.mapper = HyperKeyMapper(kind: kind)
        state.enabled = true
        state.lock.unlock()

        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = HyperKeyTapState.shared.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let shared = HyperKeyTapState.shared
            shared.lock.lock()
            let decision = shared.enabled
                ? shared.mapper.handle(type: type, keyCode: keyCode, flags: flags)
                : .pass
            shared.lock.unlock()
            switch decision {
            case .pass:
                return Unmanaged.passRetained(event)
            case .swallow:
                return nil
            case .modify(let next):
                event.flags = next
                return Unmanaged.passRetained(event)
            }
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )
        guard let eventTap else {
            logger.error("Failed to create hyper key CGEvent tap")
            state.lock.lock()
            state.enabled = false
            state.lock.unlock()
            return false
        }

        state.lock.lock()
        state.eventTap = eventTap
        state.lock.unlock()
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            EventTapThread.shared.add(runLoopSource)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func teardown() {
        if let runLoopSource {
            EventTapThread.shared.remove(runLoopSource)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        let state = HyperKeyTapState.shared
        state.lock.lock()
        state.eventTap = nil
        state.enabled = false
        state.mapper.held = false
        state.lock.unlock()
    }
}
