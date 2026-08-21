// NotifyModule.swift — macotron.notify: native macOS notifications from JS
import CQuickJS
import Foundation
import MacotronEngine
import UserNotifications
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "notify")

/// Banners are otherwise suppressed while Macotron is the active app (launcher).
private final class NotifyPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
public final class NotifyModule: NativeModule {
    public let name = "notify"
    public let moduleVersion = 1

    private var notificationCenter: UNUserNotificationCenter?
    private var authorizationGranted = false
    private let presenter = NotifyPresenter()

    public init() {}

    private var center: UNUserNotificationCenter {
        if let notificationCenter { return notificationCenter }
        let c = UNUserNotificationCenter.current()
        notificationCenter = c
        return c
    }

    public func register(in engine: Engine, options: [String: Any]) {
        let dryRun = engine.dryRun

        if !dryRun {
            center.delegate = presenter
            center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.authorizationGranted = granted
                    if let error {
                        logger.error("Notification authorization failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JS_GetPropertyStr(ctx, global, "macotron")

        let notifyObj = JS_NewObject(ctx)

        // -----------------------------------------------------------------
        // macotron.notify.show(title, body, opts?)
        //   opts.sound   — Bool (default true)
        //   opts.subtitle — String (optional)
        //   opts.id      — String (optional, for replacing existing)
        // -----------------------------------------------------------------
        JS_SetPropertyStr(ctx, notifyObj, "show", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "notify.show requires at least title and body")
            }

            guard let title = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "notify.show: title must be a string")
            }
            guard let body = JSBridge.toString(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "notify.show: body must be a string")
            }

            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                if engine.dryRun {
                    return QJS_Undefined()
                }
            }

            // Parse optional opts object
            var sound = true
            var subtitle: String? = nil
            var identifier = UUID().uuidString

            if argc > 2 && !JS_IsUndefined(argv[2]) && !JS_IsNull(argv[2]) {
                let opts = argv[2]

                let soundVal = JSBridge.getProperty(ctx, opts, "sound")
                if !JS_IsUndefined(soundVal) {
                    sound = JSBridge.toBool(ctx, soundVal)
                }
                JS_FreeValue(ctx, soundVal)

                let subtitleVal = JSBridge.getProperty(ctx, opts, "subtitle")
                if !JS_IsUndefined(subtitleVal) && !JS_IsNull(subtitleVal) {
                    subtitle = JSBridge.toString(ctx, subtitleVal)
                }
                JS_FreeValue(ctx, subtitleVal)

                let idVal = JSBridge.getProperty(ctx, opts, "id")
                if !JS_IsUndefined(idVal) && !JS_IsNull(idVal) {
                    if let customID = JSBridge.toString(ctx, idVal) {
                        identifier = customID
                    }
                }
                JS_FreeValue(ctx, idVal)
            }

            // Build and schedule the notification
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let subtitle { content.subtitle = subtitle }
            if sound { content.sound = .default }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil // deliver immediately
            )

            let center = UNUserNotificationCenter.current()
            center.add(request) { error in
                if let error {
                    logger.error("Failed to deliver notification: \(error.localizedDescription)")
                }
            }

            return QJS_Undefined()
        }, "show", 3))

        // macotron.notify.toast(title, body?, opts?)
        //   opts.position — "top" | "bottom" (default "bottom")
        //   opts.duration — milliseconds (default 3000)
        //   opts.color    — "info" | "success" | "error" | "warning" | name | #RRGGBB
        JS_SetPropertyStr(ctx, notifyObj, "toast", JS_NewCFunction(ctx, { ctx, thisVal, argc, argv -> JSValue in
            guard let ctx, let argv, argc >= 1 else {
                return QJS_ThrowTypeError(ctx, "notify.toast requires a title")
            }
            guard let title = JSBridge.toString(ctx, argv[0]) else {
                return QJS_ThrowTypeError(ctx, "notify.toast: title must be a string")
            }

            let opaque = JS_GetContextOpaque(ctx)
            if let opaque {
                let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
                if engine.dryRun {
                    return QJS_Undefined()
                }
            }

            var body: String?
            var opts: JSValue?
            if argc >= 2 {
                if JS_IsObject(argv[1]) && !JS_IsString(argv[1]) {
                    opts = argv[1]
                } else {
                    let text = JSBridge.toString(ctx, argv[1]) ?? ""
                    body = text.isEmpty ? nil : text
                    if argc >= 3 && JS_IsObject(argv[2]) {
                        opts = argv[2]
                    }
                }
            }

            var position = ToastPosition.bottom
            var duration: TimeInterval = 3
            var sfSymbol: String?
            var color: String?
            if let opts {
                let posVal = JSBridge.getProperty(ctx, opts, "position")
                if !JS_IsUndefined(posVal), let name = JSBridge.toString(ctx, posVal) {
                    position = ToastPosition.parse(name)
                }
                JS_FreeValue(ctx, posVal)

                let durVal = JSBridge.getProperty(ctx, opts, "duration")
                if !JS_IsUndefined(durVal) {
                    let ms = JSBridge.toDouble(ctx, durVal)
                    if ms > 0 { duration = ms / 1000 }
                }
                JS_FreeValue(ctx, durVal)

                let symVal = JSBridge.getProperty(ctx, opts, "sfSymbol")
                if !JS_IsUndefined(symVal) {
                    sfSymbol = JSBridge.toString(ctx, symVal)
                }
                JS_FreeValue(ctx, symVal)

                let colorVal = JSBridge.getProperty(ctx, opts, "color")
                if !JS_IsUndefined(colorVal) {
                    color = JSBridge.toString(ctx, colorVal)
                }
                JS_FreeValue(ctx, colorVal)
            }

            ToastHost.shared.show(
                title: title,
                body: body,
                position: position,
                duration: duration,
                sfSymbol: sfSymbol,
                color: color
            )
            return QJS_Undefined()
        }, "toast", 3))
        JS_SetPropertyStr(ctx, macotron, "notify", notifyObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        notificationCenter?.removeAllPendingNotificationRequests()
        ToastHost.shared.hide()
    }
}
