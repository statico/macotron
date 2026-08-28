// AudioDevices.swift — Core Audio default I/O, volume, and change watch
import AudioToolbox
import CoreAudio
import CQuickJS
import Foundation
import MacotronEngine

public struct AudioDeviceInfo: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var uid: String
    public var input: Bool
    public var output: Bool

    var js: [String: Any] {
        ["id": id, "name": name, "uid": uid, "input": input, "output": output]
    }
}

enum AudioDevices {
    static func clampVolume(_ value: Double) -> Float {
        Float(min(1, max(0, value)))
    }

    static func list() -> [AudioDeviceInfo] {
        allIDs().compactMap(info)
    }

    static func input() -> AudioDeviceInfo? {
        info(defaultID(kAudioHardwarePropertyDefaultInputDevice))
    }

    static func output() -> AudioDeviceInfo? {
        info(defaultID(kAudioHardwarePropertyDefaultOutputDevice))
    }

    static func find(_ spec: String) -> AudioDeviceInfo? {
        let needle = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return list().first { $0.name == needle || $0.uid == needle }
    }

    static func find(id: AudioDeviceID) -> AudioDeviceInfo? {
        info(id)
    }

    static func setDefault(id: AudioDeviceID, input: Bool) -> Bool {
        var value = id
        var addr = AudioObjectPropertyAddress(
            mSelector: input
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &value
        ) == noErr
    }

    static func volume(id: AudioDeviceID) -> Double? {
        if let v = scalar(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput) {
            return Double(v)
        }
        if let v = scalar(id, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput) {
            return Double(v)
        }
        return nil
    }

    static func setVolume(id: AudioDeviceID, _ value: Double) -> Bool {
        var v = clampVolume(value)
        if setScalar(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, &v) {
            return true
        }
        return setScalar(id, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, &v)
    }

    static func isMuted(id: AudioDeviceID, preferInput: Bool = false) -> Bool {
        muteValue(id, preferInput: preferInput) ?? false
    }

    static func setMuted(id: AudioDeviceID, _ on: Bool, preferInput: Bool = false) -> Bool {
        var value: UInt32 = on ? 1 : 0
        var addr = muteAddress(id, preferInput: preferInput)
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value) == noErr
    }

    // MARK: - Core Audio

    private static func allIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultID(_ selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func info(_ id: AudioDeviceID) -> AudioDeviceInfo? {
        guard id != 0, id != kAudioObjectUnknown else { return nil }
        let name = cfString(id, kAudioObjectPropertyName)
        guard !name.isEmpty else { return nil }
        return AudioDeviceInfo(
            id: Int(id),
            name: name,
            uid: cfString(id, kAudioDevicePropertyDeviceUID),
            input: hasStreams(id, kAudioDevicePropertyScopeInput),
            output: hasStreams(id, kAudioDevicePropertyScopeOutput)
        )
    }

    private static func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func cfString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return "" }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<CFString>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return "" }
        return buf.load(as: CFString.self) as String
    }

    private static func scalar(
        _ id: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope
    ) -> Float? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            var value: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectHasProperty(id, &addr),
               AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        return nil
    }

    private static func setScalar(
        _ id: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ value: inout Float
    ) -> Bool {
        var ok = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            let size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectHasProperty(id, &addr),
               AudioObjectSetPropertyData(id, &addr, 0, nil, size, &value) == noErr {
                ok = true
            }
        }
        return ok
    }

    private static func muteAddress(_ id: AudioDeviceID, preferInput: Bool) -> AudioObjectPropertyAddress {
        let hasInput = hasStreams(id, kAudioDevicePropertyScopeInput)
        let hasOutput = hasStreams(id, kAudioDevicePropertyScopeOutput)
        let scope = preferInput && hasInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &addr) { return addr }
        addr.mElement = 1
        if AudioObjectHasProperty(id, &addr) { return addr }
        addr.mScope = scope == kAudioObjectPropertyScopeInput
            ? kAudioObjectPropertyScopeOutput
            : kAudioObjectPropertyScopeInput
        addr.mElement = kAudioObjectPropertyElementMain
        if AudioObjectHasProperty(id, &addr) { return addr }
        addr.mElement = 1
        return addr
    }

    private static func muteValue(_ id: AudioDeviceID, preferInput: Bool) -> Bool? {
        var addr = muteAddress(id, preferInput: preferInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &addr),
              AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }
}

private final class AudioWatchState: @unchecked Sendable {
    static let shared = AudioWatchState()
    weak var engine: Engine?
    var listening = false
}

enum AudioWatch {
    static func start(_ engine: Engine) {
        AudioWatchState.shared.engine = engine
        guard !AudioWatchState.shared.listening else { return }
        add(kAudioHardwarePropertyDefaultInputDevice)
        add(kAudioHardwarePropertyDefaultOutputDevice)
        add(kAudioHardwarePropertyDevices)
        AudioWatchState.shared.listening = true
    }

    static func stop() {
        AudioWatchState.shared.engine = nil
        guard AudioWatchState.shared.listening else { return }
        remove(kAudioHardwarePropertyDefaultInputDevice)
        remove(kAudioHardwarePropertyDefaultOutputDevice)
        remove(kAudioHardwarePropertyDevices)
        AudioWatchState.shared.listening = false
    }

    private static func add(_ selector: AudioObjectPropertySelector) {
        var addr = address(selector)
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &addr, audioListener, nil
        )
    }

    private static func remove(_ selector: AudioObjectPropertySelector) {
        var addr = address(selector)
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &addr, audioListener, nil
        )
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func emit(_ flags: [String]) {
        Task { @MainActor in
            guard let engine = AudioWatchState.shared.engine, let ctx = engine.context else { return }
            let data = JSBridge.newObject(ctx, ["flags": flags as [Any]])
            engine.eventBus.emit("audio:changed", engine: engine, data: data)
            JS_FreeValue(ctx, data)
        }
    }
}

private let audioListener: AudioObjectPropertyListenerProc = { _, count, addrs, _ in
    var flags: [String] = []
    for i in 0..<Int(count) {
        switch addrs[i].mSelector {
        case kAudioHardwarePropertyDefaultInputDevice: flags.append("input")
        case kAudioHardwarePropertyDefaultOutputDevice: flags.append("output")
        case kAudioHardwarePropertyDevices: flags.append("devices")
        default: break
        }
    }
    if flags.isEmpty { flags = ["devices"] }
    AudioWatch.emit(flags)
    return noErr
}
