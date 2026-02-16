// NotifyModule.swift — macotron.notify: native macOS notifications from JS
import CQuickJS
import Foundation
import MacotronEngine
import UserNotifications
import os

private let logger = Logger(subsystem: "com.macotron", category: "notify")

@MainActor
public final class NotifyModule: NativeModule {
    public let name = "notify"
    public let moduleVersion = 1

    private let center = UNUserNotificationCenter.current()
    private var authorizationGranted = false

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        // Request notification authorization eagerly on register
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.authorizationGranted = granted
                if let error {
                    logger.error("Notification authorization failed: \(error.localizedDescription)")
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

            logger.info("notify.show: \(title)")
            return QJS_Undefined()
        }, "show", 3))
        JS_SetPropertyStr(ctx, macotron, "notify", notifyObj)

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)
    }

    public func cleanup() {
        // Remove any pending notifications posted by modules on reload
        center.removeAllPendingNotificationRequests()
    }
}
