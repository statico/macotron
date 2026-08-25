// SnippetsModule.swift — macotron.snippets: in-memory text snippets
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CQuickJS
import MacotronEngine

/// Only ever touched on the main actor: the tap callback reaches the module through a
/// hop to main, so the tap thread never reads this.
private final class SnippetsTapState: @unchecked Sendable {
    weak var module: SnippetsModule?

    static let shared = SnippetsTapState()
}

@MainActor
public final class SnippetsModule: NativeModule {
    public let name = "snippets"

    private var snippets: [String: String] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var typedBuffer = ""

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        engine.configStore["__snippetsModule"] = self
        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")
        let snippets = JS_NewObject(ctx)

        JS_SetPropertyStr(ctx, snippets, "list", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = module(ctx) else { return QJS_Undefined() }
            let items: [Any] = module.snippets.sorted { $0.key < $1.key }.map {
                ["abbr": $0.key, "body": $0.value]
            }
            return JSBridge.newArray(ctx, items)
        }, "list", 0))

        JS_SetPropertyStr(ctx, snippets, "set", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]),
                  let body = JSBridge.toString(ctx, argv[1]) else { return QJS_Undefined() }
            module.snippets[abbr] = body
            return QJS_Undefined()
        }, "set", 2))

        JS_SetPropertyStr(ctx, snippets, "remove", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]) else { return QJS_Undefined() }
            module.snippets.removeValue(forKey: abbr)
            return QJS_Undefined()
        }, "remove", 1))

        JS_SetPropertyStr(ctx, snippets, "insert", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = module(ctx),
                  let abbr = JSBridge.toString(ctx, argv[0]),
                  let body = module.snippets[abbr] else { return QJS_Undefined() }
            if Engine.isDryRun(ctx) { return QJS_Undefined() }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            return QJS_Undefined()
        }, "insert", 1))

        JS_SetPropertyStr(ctx, snippets, "setExpansionEnabled", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 1, let module = module(ctx) else { return JS_NewBool(ctx, false) }
            if Engine.isDryRun(ctx) { return JS_NewBool(ctx, true) }
            return JS_NewBool(ctx, module.setExpansionEnabled(JS_ToBool(ctx, argv[0]) != 0))
        }, "setExpansionEnabled", 1))

        JS_SetPropertyStr(ctx, snippets, "isExpansionEnabled", JS_NewCFunction(ctx, { ctx, _, _, _ in
            guard let ctx, let module = module(ctx) else { return JS_NewBool(ctx, false) }
            return JS_NewBool(ctx, module.eventTap != nil)
        }, "isExpansionEnabled", 0))

        JS_SetPropertyStr(ctx, macotron, "snippets", snippets)
        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        teardownEventTap()
    }

    var hasEventTap: Bool { eventTap != nil }

    private func setExpansionEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            setupEventTap()
        } else {
            teardownEventTap()
        }
        return eventTap != nil
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }

        SnippetsTapState.shared.module = self
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in
                    SnippetsTapState.shared.module?.reenableEventTap()
                }
                return Unmanaged.passRetained(event)
            }

            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            var characters = [UniChar](repeating: 0, count: 8)
            var length = 0
            event.keyboardGetUnicodeString(
                maxStringLength: characters.count,
                actualStringLength: &length,
                unicodeString: &characters
            )
            let text = String(utf16CodeUnits: characters, count: length)

            Task { @MainActor in
                SnippetsTapState.shared.module?.handleKeyDown(keyCode: keyCode, flags: flags, text: text)
            }
            return Unmanaged.passRetained(event)
        }

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )

        guard let eventTap else {
            SnippetsTapState.shared.module = nil
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            EventTapThread.shared.add(runLoopSource)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func teardownEventTap() {
        if let runLoopSource {
            EventTapThread.shared.remove(runLoopSource)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        typedBuffer = ""
        SnippetsTapState.shared.module = nil
    }

    private func handleKeyDown(keyCode: CGKeyCode, flags: CGEventFlags, text: String) {
        if flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty == false
            || [CGKeyCode(kVK_Space), CGKeyCode(kVK_Return), CGKeyCode(kVK_Escape), CGKeyCode(kVK_Tab)].contains(keyCode) {
            typedBuffer = ""
            return
        }

        guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7e }), !text.isEmpty else { return }
        typedBuffer = String((typedBuffer + text).suffix(32))

        guard let abbr = snippets.keys.filter({ typedBuffer.hasSuffix($0) }).max(by: { $0.count < $1.count }),
              let body = snippets[abbr] else { return }
        typedBuffer = ""
        expand(abbr: abbr, body: body)
    }

    private func expand(abbr: String, body: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let source = CGEventSource(stateID: .combinedSessionState)

        for _ in 0..<abbr.count {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)?.post(tap: .cghidEventTap)
        }

        // ponytail: paste expansion briefly clobbers the pasteboard; synthesize characters directly if that becomes unacceptable.
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
        let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        pasteDown?.flags = .maskCommand
        pasteDown?.post(tap: .cghidEventTap)
        let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        pasteUp?.flags = .maskCommand
        pasteUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}

@MainActor
private func module(_ ctx: OpaquePointer) -> SnippetsModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__snippetsModule"] as? SnippetsModule
}
